# syntax=docker/dockerfile:1
#
# Builds Odamex Web and runs it: the site, game server and bridge, on port 8765.
#
#   docker build -t odamex-web .
#   docker run -d --name odamex-web -p 8765:8765 -v odamex-logs:/app/logs \
#     --restart unless-stopped odamex-web
#
# DOOM1.WAD, in the repository root, ends up in the image.

# --- Build: the same tools as "Setting up a build machine" in README.md ------
FROM ubuntu:24.04 AS build

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates git python3 xz-utils build-essential cmake ninja-build zlib1g-dev npm \
 && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/emscripten-core/emsdk.git /emsdk \
 && /emsdk/emsdk install 6.0.12 \
 && /emsdk/emsdk activate 6.0.12
ENV EMSDK=/emsdk

WORKDIR /src
COPY . .
# build/ is kept between docker builds, so rebuilds are incremental.
RUN --mount=type=cache,target=/src/build ./build.sh
# The bridge's dependency, installed here so the final image needs no npm.
RUN npm ci --prefix dist/bridge --omit=dev --no-audit --no-fund

# --- Run: dist/ and Node.js, as a normal user (odasrv refuses root) ----------
# The same Ubuntu as the build stage, so odasrv's system libraries match.
FROM ubuntu:24.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      nodejs tini \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home doom \
 && mkdir /app && chown doom:doom /app

USER doom
WORKDIR /app
COPY --from=build --chown=doom:doom /src/dist/ /app/
RUN mkdir -p /app/logs

EXPOSE 8765
VOLUME /app/logs
# tini passes "docker stop" on to the server and bridge (-g: all of them).
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/app/run.sh"]
