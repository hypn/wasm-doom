# syntax=docker/dockerfile:1
#
# Builds Odamex Web as two images, run together by compose.yaml:
#
#   server  the game server (odasrv), on a network with no internet access
#   bridge  the site and the WebSocket-to-UDP bridge, on port 8765
#
#   docker compose up -d --build
#
# Both are distroless (no shell, no package manager) and run as a non-root
# user from the start; compose.yaml adds the rest of the hardening.  If one of
# them were compromised, it couldn't change the other, the site, or (for the
# game server) reach anything but the bridge.
#
# DOOM1.WAD, in the repository root, ends up in both images.

# --- Build: the same tools as "Setting up a build machine" in README.md ------
# Debian 13, the same as the distroless images below, so odasrv's system
# libraries (glibc, libstdc++) match the ones it runs with.
FROM debian:13 AS build

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates git python3 xz-utils build-essential cmake ninja-build zlib1g-dev npm \
 && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch 6.0.12 https://github.com/emscripten-core/emsdk.git /emsdk \
 && /emsdk/emsdk install 6.0.12 \
 && /emsdk/emsdk activate 6.0.12
ENV EMSDK=/emsdk

WORKDIR /src
COPY . .
# build/ is kept between docker builds, so rebuilds are incremental.  Locked,
# since compose builds both images at once from this one stage.
RUN --mount=type=cache,id=odamex-web-build-debian13,target=/src/build,sharing=locked \
    ./build.sh
# The bridge's dependency, installed here so the bridge image needs no npm.
RUN npm ci --prefix dist/bridge --omit=dev --ignore-scripts --no-audit --no-fund

# --- Game server: glibc, libstdc++ and zlib, nothing else -----------------------
FROM gcr.io/distroless/cc-debian13:nonroot AS server

COPY --from=build /src/dist/server/ /app/server/
COPY --from=build /src/dist/www/wads/DOOM1.WAD /app/DOOM1.WAD
WORKDIR /app/server

# Its only network is compose.yaml's internal one, which only the bridge
# shares, so it listens on all of the container's addresses.  It logs to
# docker's log; +logfile /dev/null and -crashdir keep it from writing to
# ~/.odamex, which is read-only.
ENTRYPOINT ["/app/server/odasrv", "-config", "/dev/null", "-crashdir", "/tmp", \
            "+logfile", "/dev/null", "-iwad", "/app/DOOM1.WAD", "-port", "10666", \
            "+exec", "server.cfg"]

# --- Bridge: Node.js, nothing else ----------------------------------------------
FROM gcr.io/distroless/nodejs22-debian13:nonroot AS bridge

COPY --from=build /src/dist/www/ /app/www/
COPY --from=build /src/dist/bridge/ /app/bridge/

EXPOSE 8765
# The image's entrypoint is node.  "server" is the game server's name on
# compose.yaml's internal network.
CMD ["/app/bridge/bridge.js", "/app/www", "8765", "server:10666"]
