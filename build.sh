#!/usr/bin/env bash
#
# Builds Odamex Web into dist/:
#
#   dist/www/      the site: both pages, the WebAssembly client and DOOM1.WAD
#                  (serve this alone for single player)
#   dist/server/   the native game server (odasrv) and its config
#   dist/bridge/   the WebSocket-to-UDP bridge between browsers and odasrv
#   dist/run.sh    starts the server and bridge (multiplayer)
#
# Usage: ./build.sh [client|server]     (default: both)
#
# The game, the shareware DOOM1.WAD (v1.9), is in the repository root.  For the
# tools needed, see "Setting up a build machine" in README.md.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$ROOT/engine"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
EMSDK_DIR="${EMSDK:-$HOME/emsdk}"

WHAT="${1:-all}"
case "$WHAT" in
  client|server|all) ;;
  *) echo "usage: ./build.sh [client|server]" >&2; exit 2 ;;
esac

# Explains what's missing and how to install it on Ubuntu, then stops.
missing() {
  echo "error: $1 is not installed." >&2
  echo "       Install it with: $2" >&2
  echo "       (See \"Setting up a build machine\" in README.md.)" >&2
  exit 1
}
need() { command -v "$1" >/dev/null || missing "$1" "$2"; }

echo "==> Checking build tools"
need cmake "sudo apt install cmake"
need ninja "sudo apt install ninja-build"
need c++ "sudo apt install build-essential"
CMAKE_VERSION="$(cmake --version | head -n1 | awk '{print $3}')"
if ! printf '%s\n' 3.19 "$CMAKE_VERSION" | sort -V -C; then
  missing "cmake 3.19 or newer (found $CMAKE_VERSION)" "sudo apt install cmake, or: pip install --user cmake"
fi
echo "    cmake $CMAKE_VERSION, ninja $(ninja --version), $(c++ --version | head -n1)"

if [ "$WHAT" != server ] && ! command -v emcc >/dev/null; then
  if [ ! -f "$EMSDK_DIR/emsdk_env.sh" ]; then
    echo "error: the Emscripten SDK is not installed (looked in $EMSDK_DIR)." >&2
    echo "       Install it with:" >&2
    echo "         git clone https://github.com/emscripten-core/emsdk.git ~/emsdk" >&2
    echo "         ~/emsdk/emsdk install 6.0.12 && ~/emsdk/emsdk activate 6.0.12" >&2
    echo "       (See \"Setting up a build machine\" in README.md.)" >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  source "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1
fi
if [ "$WHAT" != server ]; then
  echo "    emcc $(emcc --version | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
fi

if [ "$WHAT" != client ] && ! echo '#include <zlib.h>' | c++ -x c++ -fsyntax-only - 2>/dev/null; then
  missing "zlib (headers)" "sudo apt install zlib1g-dev"
fi

# The game: DOOM1.WAD in any letter case (downloads are often doom1.wad).
WAD="$(find "$ROOT" -maxdepth 1 -iname doom1.wad -print -quit)"
if [ -z "$WAD" ]; then
  echo "error: the game is missing: the shareware DOOM1.WAD (v1.9) should be in $ROOT/" >&2
  exit 1
fi
if [ "$(md5sum < "$WAD" | cut -d' ' -f1)" != f0cefca49926d00903cf57551d901abe ]; then
  echo "    warning: $(basename "$WAD") isn't the v1.9 shareware DOOM1.WAD; it may not work." >&2
fi

build_client() {
  # A native protoc matching the bundled protobuf, to generate the network
  # protocol code (a WebAssembly one can't run during the build).
  if [ ! -x "$BUILD/host-protoc/protoc" ]; then
    echo "==> Building a native protoc (first build only, takes a few minutes)"
    cmake -S "$ENGINE/libraries/protobuf/cmake" -B "$BUILD/host-protoc" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_BUILD_SHARED_LIBS=OFF
    ninja -C "$BUILD/host-protoc" protoc
  fi

  # Odamex relies on C++ exceptions, so every library is built with native
  # Wasm exceptions.  The flags are only exported here, for the client.
  echo "==> Building the browser client (the first build also builds its libraries)"
  (
    export CFLAGS="-fwasm-exceptions" CXXFLAGS="-fwasm-exceptions" LDFLAGS="-fwasm-exceptions"
    if [ ! -f "$BUILD/client/build.ninja" ]; then
      emcmake cmake -S "$ENGINE" -B "$BUILD/client" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SERVER=0 -DUSE_LTO=0 -DODAMEX_HOST_PROTOC="$BUILD/host-protoc/protoc"
    fi
    ninja -C "$BUILD/client" odamex
  )

  echo "==> Assembling dist/www/"
  rm -rf "$DIST/www"
  mkdir -p "$DIST/www/wads"
  cp "$ROOT"/web/* "$BUILD/client/client/odamex.js" "$BUILD/client/client/odamex.wasm" "$DIST/www/"
  cp "$WAD" "$DIST/www/wads/DOOM1.WAD"
}

build_server() {
  echo "==> Building the game server (the first build also builds its libraries)"
  if [ ! -f "$BUILD/server/build.ninja" ]; then
    cmake -S "$ENGINE" -B "$BUILD/server" -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_CLIENT=0
  fi
  ninja -C "$BUILD/server" odasrv

  echo "==> Assembling dist/server/, dist/bridge/ and dist/run.sh"
  mkdir -p "$DIST/server" "$DIST/bridge"
  cp "$BUILD/server/server/odasrv" "$ROOT/multiplayer/server.cfg" "$DIST/server/"
  cp "$ROOT/multiplayer/bridge.js" "$ROOT/multiplayer/package.json" \
     "$ROOT/multiplayer/package-lock.json" "$DIST/bridge/"
  cp "$ROOT/multiplayer/run.sh" "$DIST/run.sh"
}

case "$WHAT" in
  client) build_client ;;
  server) build_server ;;
  all) build_client; build_server ;;
esac

echo "==> Built $DIST"
echo "    Single player: serve dist/www/ with any web server."
echo "    Multiplayer: run dist/run.sh (needs both parts built)."
