# AGENTS.md

Notes for AI agents working on this repository. `README.md` is the human
guide (setup, build, deploy); keep it in sync when behaviour changes. This file
covers what isn't obvious from the code: why things are the way they are, and
what breaks if you change them.

## Shape of the project

- `engine/` is the `odamex-src-12.3.0` source release, Odamex 12.3.0
  (upstream: github.com/odamex/odamex, tag `12.3.0`), trimmed and patched. Two products are built from it:
  - **client**, for the browser only (Emscripten). `engine/client/CMakeLists.txt`
    refuses non-Emscripten builds; the desktop client is gone.
  - **server** (`odasrv`), native Linux.
- `web/` holds the pages; `web/odamex-web.js` boots the client for both.
- `multiplayer/` holds `bridge.js` (WebSocket to UDP relay, also the HTTP
  server), `server.cfg` and `run.sh`.
- `build.sh` is the only entry point: it builds into `build/` (intermediate)
  and assembles `dist/` (`www/`, `server/`, `bridge/`, `run.sh`). `dist/` must
  stay self-contained: `run.sh` only references paths inside it.
- `DOOM1.WAD` (shareware v1.9, md5 `f0cefca49926d00903cf57551d901abe`) is
  committed on purpose. It is the only supported IWAD.

## Engine changes from upstream

Every client-only web change is behind `#ifdef __EMSCRIPTEN__`; grep for it.
Changed upstream files (diff against tag `12.3.0` for details):

- Game loop: `client/src/d_main.cpp`, `client/sdl/i_main.cpp`, `common/d_main.cpp`
- Hidden-tab recovery: `common/d_main.cpp` (`CappedTaskScheduler`),
  `client/src/cl_game.cpp` (ack batching), `client/src/cl_main.cpp`
  (`CL_SimulateSectors`)
- Stubs for removed dependencies: `client/src/cl_download.cpp`,
  `client/src/otransfer.{h,cpp}` (curl), `common/m_stacktrace.cpp` (cpptrace),
  `common/m_consolecommandstream.cpp` (threads), `common/m_fileio_posix.cpp`
  (header)
- Built-in resources: `common/w_wad.{h,cpp}`, `common/m_resfile.{h,cpp}`,
  `common/d_main.cpp`, plus comments in `common/svc_message.cpp`,
  `client/src/wi_interlevel.cpp`, `server/src/sv_level.cpp`,
  `server/src/sv_maplist.cpp`
- Console background (`TITLEPIC`): `client/src/c_console.cpp`
- `logfile` no longer creates `~/.odamex` when given a path: `common/c_dispatch.cpp`
- All the CMake files, and `engine/wad/` (replaced entirely)

Preserve line endings when editing, and don't mass-convert them:
`common/w_ident.cpp`, `common/version.h` and many vendored files under
`engine/libraries/` are CRLF as shipped upstream, which keeps diffs against
upstream clean; compilers don't care. `.gitattributes` forces LF only for
`*.sh` (bash breaks on CRLF) and marks WADs binary.

## Client (WebAssembly)

- **Game loop.** Upstream loops forever in `D_DoomLoop`. Here it calls
  `emscripten_set_main_loop(D_DoomLoopFrame, 0, false)` and returns, then
  `main()` returns *without* `call_terms()`; `EXIT_RUNTIME=0` keeps the module
  alive. `D_RunTics` skips its sleep loop. Never add blocking loops or sleeps:
  there is no Asyncify, so `emscripten_sleep` aborts and `I_Sleep` busy-waits.
- **Exceptions.** Odamex uses C++ exceptions for errors, so *everything*
  (including the libraries built at configure time) is compiled with
  `-fwasm-exceptions`, set via `CFLAGS`/`CXXFLAGS`/`LDFLAGS` in `build.sh`'s
  client step. Mixing exception models breaks the link or the runtime. Since
  `main()` has returned, `D_DoomLoopFrame` catches everything itself and
  reports to the page through `Module.onFatal`; unknown types are named via
  `abi::__cxa_current_exception_type()`.
- **Hidden tabs.** The browser stops animation frames while the tab is
  hidden, but the WebSocket keeps queueing the server's packets. On return,
  `CappedTaskScheduler` drops the missed time instead of fast-forwarding
  through it (each extra tic sends a ticcmd that the server queues: lag and
  rubberbanding), and the client sends the backlog's acks in batches so
  `net_buffer` (8 KB; once overflowed it sends garbage) doesn't overflow.
  The backlog itself must still be read: the server resends only what isn't
  acked, so dropping packets loses spawns and deaths. Doors and lifts only
  move through sector snapshots (the server doesn't send their line
  activations), applied at `world_index`, which jumps ahead after a backlog;
  `CL_SimulateSectors` applies the latest snapshot before discarding stale
  ones, or doors would stay where they were when the tab was hidden. After 65 s hidden, the
  server times the player out (`CLIENT_TIMEOUT`).
- **No threads.** The build has no pthreads; `std::thread` throws "Not
  supported" at runtime (that was the stdin console reader, now stubbed). Keep
  it that way rather than enabling pthreads, which needs cross-origin isolation
  headers on the host.
- **Networking needs no engine changes.** Emscripten's SOCKFS carries the UDP
  socket over a WebSocket, one message per datagram, to `Module.websocket.url`
  (set by `odamex-web.js` to same-origin `/ws`). The `+connect` address is
  cosmetic: the bridge forwards everything to `127.0.0.1:10666`.
- **Boot** (`web/odamex-web.js`): the module is built with `MODULARIZE`
  (`createOdamex`) and `INVOKE_RUN=0`. The page mounts IDBFS at
  `/home/web_user/.odamex` (saved settings), writes the IWAD to `/data`, then
  calls `callMain`. `WEB_CFG` is written and `+exec`'d on every start, after
  the saved config, so it overrides user changes to those settings (Tab
  scoreboard, M automap, `hud_scalescoreboard 0.7`): intentional.
- Can't be tested headlessly in this environment (a headless Chrome attempt
  hung). Build it, then ask the user to test in a browser; errors show on the
  page's error screen and in the browser console.

## Built-in resources (no odamex.wad)

- `engine/wad/resources.wad` (upstream `odamex.wad`, trimmed; what was removed
  and why is in the README) is embedded as a C++ array by
  `engine/wad/embed.cmake` into the `odamex-builtin` library, linked through
  `odamex-common`.
- The engine assumes `wadfiles[0]` is the engine resource file (the server
  skips it when sending its WAD list; demo and hash code offsets by it). So it
  stays slot 0: `OResFile::makeBuiltin()` creates it, and `AddFile` opens it
  with `fmemopen()` instead of `fopen()`.
- Before removing more lumps, check how each is loaded. `W_GetNumForName`,
  `W_CachePatch(name)` and `W_CachePatchHandle` are fatal if the lump is
  missing; `W_CheckNumForName` and missing sound lumps are not. Lessons
  learned: `HORDEDEF` is needed on every map start, even in deathmatch
  (`P_HordePickDefine`), and the CTF status bar icons are loaded
  unconditionally.
- Lumps can also be referenced from data lumps (`SNDINFO`, `_D1NFO` and other
  MAPINFO lumps), not just C++. Grep both.

## Server

- `run.sh` passes `-config /dev/null`, `-crashdir`, `+logfile` and
  `+exec server.cfg`, and runs `odasrv` with `dist/server` as its working
  directory (it writes `banlist.json` there). Together these keep everything
  out of `~/.odamex`.
- Don't move settings into `-config`: that file is executed *before* the WADs
  load, so `addmap` fails there. `server.cfg` is `+exec`'d afterwards.
- `odasrv` refuses to run as root (`server/src/i_main.cpp`); `run.sh` checks
  for root first, and the Docker image runs as user `doom`.
- The server binary needs the build machine's glibc/libstdc++ or newer
  (built on Ubuntu 24.04+: glibc 2.38, GLIBCXX 3.4.32). Docker sidesteps this
  by using `ubuntu:24.04` for both stages; keep the two stages on the same base.

## Build system

- Libraries are built at **configure** time (`execute_process` in
  `engine/libraries/*.cmake`, via `lib_buildgen`/`lib_build`). After changing a
  library's flags, delete `build/client` or `build/server` rather than expecting
  ninja to notice.
- `protoc` must be native: `build.sh` builds it from the bundled protobuf
  (21.1, `protoc` 3.21.1) into `build/host-protoc` and passes
  `ODAMEX_HOST_PROTOC`. The generated code must match the library version.
- Emscripten restricts `find_package` to its sysroot; the top-level CMake adds
  `build/.../libraries` to `CMAKE_FIND_ROOT_PATH`, and `lib_buildgen` passes the
  toolchain file to the library sub-builds.
- On the web, SDL2, SDL2_mixer, zlib and libpng come from Emscripten ports
  (interface targets in `engine/libraries/CMakeLists.txt`). The native server
  uses the system zlib.
- Deliberately removed, with the reasons; don't reintroduce them without
  solving the reason:
  - cpptrace: downloaded libdwarf and zstd at configure time.
  - bundled zlib: its CMake renames `zconf.h` inside the source tree.
  - git version stamping (`ODAMEX_NO_GITVER` is always on): failed in a repo
    with no commits, and described Odamex's repo, not ours.
  - cvar docs refresh: wrote into the source tree on every build.
  - Python WAD tools: replaced by the committed `resources.wad`.
- A build must not modify anything outside `build/` and `dist/`.

## Testing

There are no automated tests. After changes:

1. `./build.sh` (or `client`/`server`); both should end with `==> Built`.
2. `dist/run.sh`, then check the pages load and the server answers through
   the bridge. A quick check without a browser is a Node.js script, using
   `dist/bridge/node_modules/ws`, that connects to `ws://127.0.0.1:8765/ws`
   with subprotocol `binary` and sends the launcher query: 4 bytes, int32
   little-endian `777123` (`LAUNCHER_CHALLENGE`). The reply contains the
   server name and current map.
3. For gameplay or rendering changes, ask the user to test in a browser.

To check that a build or run wrote nothing to `~/.odamex`, run with `HOME`
pointed at an empty directory.

## Environment gotchas

- The user's shell is zsh: an unmatched glob aborts the whole command, a word
  starting with `=` is expanded (`echo ===` fails), and `pkill -f`/`pgrep -f`
  patterns can match your own command line. Kill by PID, or use
  `pgrep -x odasrv`.
- `cmake` and `ninja` may only be in `~/.local/bin`; add it to `PATH`.
- `run.sh` falls back to the Emscripten SDK's Node.js if the system's is
  missing or older than 16.
