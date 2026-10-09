# Odamex Web

Shareware DOOM in the browser, single player and online deathmatch, built from
the [Odamex](https://odamex.net) source port: specifically the
`odamex-src-12.3.0` source release, Odamex version 12.3.0. `engine/` is that
source, trimmed and patched (see [Changes from Odamex
12.3.0](#changes-from-odamex-1230)).

- **Single player** (`index.html`): the Odamex client compiled to WebAssembly
  with Emscripten.
- **Multiplayer** (`multiplayer.html`): the same client, connected over a
  WebSocket to a small Node.js bridge, which relays it as UDP to a native
  Odamex server (`odasrv`) running deathmatch on E1M1–E1M9.

## Quick start

1. Install the tools, once: see [Setting up a build machine](#setting-up-a-build-machine).
2. Build: `./build.sh` (the first build takes a while).
3. Run: `dist/run.sh`, then open http://localhost:8765/ (single player) or
   http://localhost:8765/multiplayer.html (deathmatch).

To put it online, see [Deploying to a VPS](#deploying-to-a-vps). Or skip
all of this and use [Docker](#docker), which needs only Docker.

The game, the shareware `DOOM1.WAD` (v1.9), is included in the repository.

## Setting up a build machine

On a fresh Ubuntu (24.04; 22.04 works too, see below):

```sh
# Compilers and build tools; zlib for the server; Node.js for the bridge
sudo apt update
sudo apt install -y git python3 build-essential cmake ninja-build zlib1g-dev nodejs npm rsync

# The Emscripten SDK, which compiles the client to WebAssembly (needs git and python3)
git clone https://github.com/emscripten-core/emsdk.git ~/emsdk
~/emsdk/emsdk install 6.0.12
~/emsdk/emsdk activate 6.0.12
```

`build.sh` and `run.sh` find the Emscripten SDK in `~/emsdk` themselves (or
wherever `$EMSDK` points), and check for each tool before starting: if
something is missing, they say what and how to install it.

| Tool | Used for | Ubuntu package |
|---|---|---|
| Emscripten SDK 6.0.12 | compiling the client to WebAssembly | not packaged; installed above |
| CMake 3.19+ | configuring the builds | `cmake` |
| Ninja | running the builds | `ninja-build` |
| GCC (C++17) | the native server, and `protoc` for the client build | `build-essential` |
| zlib headers | the native server | `zlib1g-dev` |
| Node.js 16+ and npm | the multiplayer bridge | `nodejs npm` |
| git, Python 3 | installing the Emscripten SDK | `git python3` |
| rsync | copying `dist/` to a VPS | `rsync` |

On Ubuntu 22.04, the packaged Node.js (12) is too old for the bridge; leave
out `nodejs npm`, and `run.sh` uses the Node.js that comes with the
Emscripten SDK instead.

Tested with Emscripten 6.0.12, CMake 4.4, GCC on Ubuntu (WSL2) and Node.js 24.

## Build

```sh
./build.sh               # everything
./build.sh client        # or just the web client and site
./build.sh server        # or just the game server, bridge and run.sh
```

Everything you need ends up in `dist/`:

| Path | What | From |
|---|---|---|
| `dist/www/` | The site: both pages, the WebAssembly client they share (`odamex.js`, `odamex.wasm`) and `DOOM1.WAD` | compiled from `engine/`, plus `web/` and `DOOM1.WAD` copied |
| `dist/server/` | The native game server (`odasrv`) and its settings (`server.cfg`) | compiled from `engine/`, plus `multiplayer/server.cfg` copied |
| `dist/bridge/` | The WebSocket-to-UDP bridge between browsers and the server | copied from `multiplayer/` (JavaScript, nothing to compile) |
| `dist/run.sh` | Starts the server and bridge | copied from `multiplayer/` |

`dist/` only uses what's inside it, so it can be copied to another machine and
run there (with Node.js). Intermediate files go to `build/`; the first client
build also compiles a native `protoc` there, which generates the network
protocol code. Both `build/` and `dist/` are ignored by git.

Builds are incremental: the first one compiles everything and takes a while,
later ones only recompile what changed, and the files are copied into `dist/`
every time. Re-run `./build.sh` after editing anything outside `dist/`. For a
clean build, delete `build/` and `dist/` first.

## Run

```sh
dist/run.sh              # server + bridge on http://localhost:8765/
dist/run.sh 8080         # or another HTTP port
```

Then open `http://localhost:8765/` for single player, or
`http://localhost:8765/multiplayer.html` for deathmatch. Ctrl+C stops both.
The first run installs the bridge's one dependency (`ws`) into
`dist/bridge/node_modules/`. Single player alone needs only a static web
server for `dist/www/`.

The bridge serves the site and the WebSocket on the HTTP port; the server
listens on UDP 10666, which only the bridge needs to reach. So the game uses
only HTTP and one WebSocket, and a single tunnel exposes it to friends, for
example `cloudflared tunnel --url http://localhost:8765` (no account needed).

Controls: click the game to capture the mouse, Esc for the menu, the `` ` ``
key for the console, T to chat, hold Tab for the scoreboard, M for the
automap. Settings are saved in the browser.

## Deploying to a VPS

`dist/` is everything the VPS needs: no source, compilers or Emscripten.
Build on your own machine, copy `dist/` across, and run it there.

**Which VPS:** the game server in `dist/` is a Linux program built against
your build machine's system libraries. As a rule of thumb, the VPS should run
the same Ubuntu version as your build machine, or newer; one built on Ubuntu
24.04 to 26.04 runs on Ubuntu 24.04 or newer, or Debian 13. If in doubt, try
it: `run.sh` says so if the server can't start. If the VPS is older, build
there instead: clone the repository on the VPS, set it up as in
[Setting up a build machine](#setting-up-a-build-machine) (Emscripten
included), and run `./build.sh` on it.

**1. On the VPS** (as root, or with `sudo`), once: install Node.js for the
bridge, and create a user to run the game, since the game server refuses to
run as root.

```sh
sudo apt update && sudo apt install -y nodejs npm rsync
sudo adduser --disabled-password --gecos '' doom
```

**2. On your machine:** build, then copy `dist/` to the VPS.

```sh
./build.sh
rsync -a dist/ root@your-vps:/home/doom/odamex-web/
ssh root@your-vps chown -R doom: /home/doom/odamex-web
```

**3. On the VPS:** open the port if the firewall is on, and try it.

```sh
sudo ufw allow 8765/tcp              # only if ufw is enabled
sudo -u doom /home/doom/odamex-web/run.sh
```

Open `http://your-vps-ip:8765/`; Ctrl+C stops it. Only TCP 8765 needs to be
open: the game server's UDP port (10666) is only used by the bridge, on the
same machine.

**4. Keep it running,** across logouts and reboots, as a systemd service.
Create `/etc/systemd/system/odamex-web.service` (e.g. with
`sudo nano /etc/systemd/system/odamex-web.service`) containing:

```ini
[Unit]
Description=Odamex Web (DOOM server and bridge)
After=network-online.target

[Service]
User=doom
ExecStart=/home/doom/odamex-web/run.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Then start it, and have it start on boot:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now odamex-web
```

`systemctl status odamex-web` shows whether it's running, `journalctl -u
odamex-web -f` follows its output, and the logs are in
`/home/doom/odamex-web/logs/`.

**Updating:** rebuild, repeat the `rsync` and `chown` from step 2, then
`sudo systemctl restart odamex-web`. The logs, ban list and installed bridge
dependency on the VPS are kept, but `server.cfg` is replaced: change server
settings in `multiplayer/server.cfg` on your machine, not on the VPS.

**HTTPS (optional):** put a web server that handles certificates in front, for
example [Caddy](https://caddyserver.com), with a domain pointing at the VPS.
After `sudo apt install caddy`, put this in `/etc/caddy/Caddyfile` and run
`sudo systemctl reload caddy`:

```
doom.example.com {
	reverse_proxy localhost:8765
}
```

Open ports 80 and 443 instead of 8765, and use `https://doom.example.com/`.
The multiplayer page switches to a secure WebSocket by itself.

## Docker

Instead of setting up a build machine, Docker can build and run everything.
Only Docker is needed:

```sh
docker build -t odamex-web .
docker run -d --name odamex-web -p 8765:8765 -v odamex-logs:/app/logs \
  --restart unless-stopped odamex-web
```

Then open http://localhost:8765/. `--restart unless-stopped` keeps it running
across reboots, and the `odamex-logs` volume keeps the logs across
containers.

| Command | What |
|---|---|
| `docker logs -f odamex-web` | Follow the server's and bridge's output |
| `docker stop odamex-web` / `docker start odamex-web` | Stop and start it |
| `docker build -t odamex-web .` then `docker rm -f odamex-web` and the `docker run` above | Update it after changing anything, including `multiplayer/server.cfg` |

The image is built in two stages: one with the build tools runs `build.sh`,
and the final image holds only `dist/` and Node.js, running as a normal user.
Both use Ubuntu 24.04, so the host's OS version doesn't matter; this also
makes Docker the easiest way onto a VPS with an older OS. The first build
downloads the Emscripten SDK and compiles everything, so it takes a while;
later builds reuse the compiled files and are much quicker.

The ban list lives inside the container, so a new container starts with an
empty one.

## Server settings

The server takes all its settings from `server.cfg` (source:
`multiplayer/server.cfg`): deathmatch on nightmare skill with no monsters, 30
frags or 10 minutes per map then the next map, up to 16 players. To change
them, edit `multiplayer/server.cfg`, run `./build.sh server` (or edit
`dist/server/server.cfg` directly) and restart `dist/run.sh`.

Everything the server and bridge write stays in `dist/`; nothing goes to
`~/.odamex`, Odamex's usual folder:

| File | What |
|---|---|
| `dist/logs/odasrv.log` | The server's log (`+logfile`) |
| `dist/logs/bridge.log` | The bridge's log: connections and disconnections |
| `dist/logs/` | Also where server crash reports would go (`-crashdir`) |
| `dist/server/banlist.json` | The server's ban list |

Both logs are also shown in the terminal, and are appended to across runs.
`run.sh` starts the server with `-config /dev/null`, so it doesn't read or
write a saved-settings file (normally `~/.odamex/odasrv.cfg`).

**Cheats** (`iddqd`, `idkfa`, …) work in single player already, except on
nightmare skill, where `set sv_allowcheats 1` in the console enables them. In
multiplayer the server decides: add `set sv_allowcheats "1"` to `server.cfg`
to allow them, for every player.

## Layout

| Path | What |
|---|---|
| `build.sh` | Builds everything into `dist/` |
| `Dockerfile`, `.dockerignore` | Builds and runs everything with Docker |
| `AGENTS.md` | Technical notes for AI coding agents: design decisions and gotchas |
| `.gitattributes` | Keeps shell scripts LF and WADs untouched in any git checkout |
| `engine/` | The Odamex engine: source (`client/`, `common/`, `server/`, `odaproto/`), bundled libraries (`libraries/`: fmt, JsonCpp, libADLMIDI, minilzo, protobuf, textscreen, tinylibs), CMake modules and `wad/resources.wad`, the engine's built-in resources |
| `web/` | The pages and their shared script (`odamex-web.js`) and styles |
| `multiplayer/` | The bridge (`bridge.js`, `package.json`), server settings (`server.cfg`) and `run.sh` |
| `DOOM1.WAD` | The game: the shareware DOOM v1.9 IWAD, unmodified. Replacing it with another copy works in any letter case (`doom1.wad`); `build.sh` warns if it isn't v1.9 shareware |

## Changes from Odamex 12.3.0

- The client runs its game loop as browser animation frames
  (`emscripten_set_main_loop`), and the client no longer reads console
  commands from a terminal.
- No `odamex.wad`: the engine resources Doom 1 needs are compiled into the
  executables from `engine/wad/resources.wad` (see below).
- The full-screen console shows the game's title screen instead of the
  Odamex logo.
- The pages set some defaults on every start (`web/odamex-web.js`): Tab shows
  the scoreboard, M the automap, and the scoreboard is drawn at 2×.
- No WAD downloads (curl), boot window (FLTK), stack traces (cpptrace) or UPnP.
- The `logfile` command no longer creates `~/.odamex` when given a path.
- The version string has no git commit (it described Odamex's own repository).
- Desktop builds, the launchers, installers and tests are removed; the
  client builds for the browser only.

## Built-in resources

`engine/wad/resources.wad` is the `odamex.wad` built from Odamex 12.3.0's
`wad/` directory, with the lumps Doom 1 doesn't need removed:

- Odamex's own sounds (announcer, voting, CTF, join/leave, dog, railgun);
  Doom's sounds come from the IWAD, and a sound with no lump plays nothing.
  `DSEMPTY`, the engine's silence marker, is kept.
- Other games' map definitions and patches (`_D2NFO`, `_PLUTNFO`, `_TNTNFO`,
  `_BFGNFO`, `_CHEXNFO`, `_CHXHACK`, `_HERENFO`, `_HESWNFO`, `DAGGER`), and
  the episode 2/3 intermissions (`_DEP2INT`, `_DEP3INT`).
- `CONBACK`, the Odamex console background; the console shows the game's
  `TITLEPIC` instead.
- Sprites for things Doom 1 deathmatch never spawns: the MBF dog (`DOGS`),
  CTF items (`?FLG`, `?SOK`, `?CAR`, `?DWN`, `WP?F`) and Horde items (`CARE`,
  `O1UP`, `RSTM`).

Everything the engine loads unconditionally is kept, including the CTF status
bar icons and `HORDEDEF`, which the engine reads on every map start. The
editable sources (PNGs, sounds, `wadinfo.txt`, `odawad.py`) are in the `wad/`
directory of the [Odamex repository](https://github.com/odamex/odamex) at
12.3.0. `engine/wad/embed.cmake` turns the WAD into C++ when building.

## License

The code is GPLv2, as Odamex; see `LICENSE` and `3RD-PARTY-LICENSES`.
`DOOM1.WAD` is id Software's shareware DOOM, included unmodified as its
shareware terms allow; it is not covered by the GPL. DOOM is a trademark of id
Software.
