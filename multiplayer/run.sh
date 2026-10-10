#!/usr/bin/env bash
#
# Runs Odamex Web multiplayer: odasrv on UDP 10666, and the bridge serving the
# site and relaying browsers to odasrv on http://localhost:8765/.
#
# Their output is shown here and also saved in dist/logs/ (odasrv.log and
# bridge.log), along with any server crash reports.
#
# build.sh copies this to dist/run.sh; it uses only what's in dist/, so dist/
# can be copied elsewhere and run there.
#
# Needs: Node.js 16+ with npm (the Emscripten SDK's own works).
#
# Usage: dist/run.sh [http port]
#
set -euo pipefail

DIST="$(cd "$(dirname "$0")" && pwd)"
HTTP_PORT="${1:-8765}"
SERVER_PORT=10666
EMSDK_DIR="${EMSDK:-$HOME/emsdk}"

echo "==> Checking what's needed"
if [ "$(id -u)" = 0 ]; then
  echo "error: don't run this as root; the game server refuses to, for safety." >&2
  echo "       Run it as a normal user instead, for example:" >&2
  echo "         sudo adduser --disabled-password --gecos '' doom" >&2
  echo "         sudo cp -r \"$DIST\" /home/doom/odamex-web && sudo chown -R doom: /home/doom/odamex-web" >&2
  echo "         sudo -u doom /home/doom/odamex-web/run.sh" >&2
  exit 1
fi
# Ubuntu's own Node.js may be missing or too old; the Emscripten SDK has one.
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$NODE_MAJOR" -lt 16 ] && [ -f "$EMSDK_DIR/emsdk_env.sh" ]; then
  echo "    Using the Emscripten SDK's Node.js"
  # shellcheck disable=SC1091
  source "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
fi
# npm is only needed the first time, to install the bridge's dependency.
NEED_NPM=0
[ -d "$DIST/bridge/node_modules/ws" ] || NEED_NPM=1
if [ "$NODE_MAJOR" -lt 16 ] || { [ "$NEED_NPM" = 1 ] && ! command -v npm >/dev/null; }; then
  echo "error: Node.js 16 or newer, with npm, is needed for the bridge." >&2
  echo "       Install it with: sudo apt install nodejs npm (Ubuntu 24.04+)," >&2
  echo "       or install the Emscripten SDK, which includes one." >&2
  echo "       (See \"Setting up a build machine\" in README.md.)" >&2
  exit 1
fi
if [ ! -x "$DIST/server/odasrv" ]; then
  echo "error: the server isn't built: run ./build.sh server" >&2
  exit 1
fi
if [ ! -f "$DIST/www/odamex.wasm" ]; then
  echo "error: the site isn't built: run ./build.sh client" >&2
  exit 1
fi
echo "    node $(node --version)"

if [ "$NEED_NPM" = 1 ]; then
  echo "==> Installing the bridge's dependency (ws)"
  npm install --prefix "$DIST/bridge" --no-audit --no-fund
fi

echo "==> Starting the server and bridge (Ctrl+C stops both; logs in $DIST/logs/)"
mkdir -p "$DIST/logs"
# odasrv writes files such as banlist.json to its working directory, and would
# otherwise use ~/.odamex for its log, crash reports and saved settings.  All
# its settings are in server.cfg, run once the WADs are loaded (addmap needs
# them), so the saved-settings file is left empty.  -ip 127.0.0.1 keeps the
# server off the network: only the bridge, on this machine, can reach it.
(cd "$DIST/server" && exec ./odasrv -config /dev/null \
  -crashdir "$DIST/logs" +logfile "$DIST/logs/odasrv.log" \
  -iwad "$DIST/www/wads/DOOM1.WAD" -ip 127.0.0.1 -port "$SERVER_PORT" \
  +exec server.cfg </dev/null) &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT

# Without the server, the site would load but multiplayer would never connect.
sleep 2
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "error: the game server stopped straight away; its messages are above," >&2
  echo "       and in dist/logs/odasrv.log." >&2
  echo "       If they mention GLIBC or GLIBCXX, this system is older than the one" >&2
  echo "       dist/ was built on: see \"Deploying to a VPS\" in README.md." >&2
  exit 1
fi

node "$DIST/bridge/bridge.js" "$DIST/www" "$HTTP_PORT" "127.0.0.1:$SERVER_PORT" 2>&1 \
  | tee -a "$DIST/logs/bridge.log"
