// Odamex Web bridge: serves the site and relays browser clients to odasrv.
//
// The browser client's UDP socket is carried over a WebSocket (Emscripten's
// SOCKFS), one binary message per datagram.  Each WebSocket gets its own UDP
// socket here, so the server sees every browser as a separate client.
//
// Usage: node bridge.js <site dir> [http port] [odasrv host:port]

'use strict';

const dgram = require('node:dgram');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { WebSocketServer } = require('ws');

const SITE_DIR = path.resolve(process.argv[2] || '.');
const HTTP_PORT = Number(process.argv[3] || 8765);
const [SERVER_HOST, SERVER_PORT] = (process.argv[4] || '127.0.0.1:10666').split(':');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.wad': 'application/octet-stream',
};

// Static files from SITE_DIR.
const httpServer = http.createServer((req, res) => {
  const urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = path.join(SITE_DIR, urlPath.endsWith('/') ? urlPath + 'index.html' : urlPath);
  if (!file.startsWith(SITE_DIR + path.sep)) {
    res.writeHead(403).end();
    return;
  }
  fs.stat(file, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404).end('Not found');
      return;
    }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Content-Length': stat.size,
      'Cache-Control': 'no-cache',
    });
    fs.createReadStream(file).pipe(res);
  });
});

// Emscripten sends this first so a server can learn the client's bound port.
// odasrv speaks plain UDP, so it is dropped.
function isPortHandshake(data) {
  return data.length === 10 && data[0] === 0xff && data[1] === 0xff && data[2] === 0xff &&
    data[3] === 0xff && data.toString('latin1', 4, 8) === 'port';
}

const wss = new WebSocketServer({
  server: httpServer,
  path: '/ws',
  handleProtocols: (protocols) => (protocols.has('binary') ? 'binary' : false),
});

wss.on('connection', (ws, req) => {
  const who = req.socket.remoteAddress + ':' + req.socket.remotePort;
  const udp = dgram.createSocket('udp4');
  let open = true;

  function close() {
    if (!open) return;
    open = false;
    udp.close();
    ws.terminate();
    console.log(`[bridge] ${who} disconnected (${wss.clients.size} connected)`);
  }

  udp.on('message', (msg) => {
    if (ws.readyState === ws.OPEN) ws.send(msg, { binary: true });
  });
  udp.on('error', (err) => {
    console.warn(`[bridge] ${who} UDP error: ${err.message}`);
    close();
  });

  ws.on('message', (data, isBinary) => {
    if (!isBinary || isPortHandshake(data)) return;
    udp.send(data, Number(SERVER_PORT), SERVER_HOST);
  });
  ws.on('close', close);
  ws.on('error', close);

  console.log(`[bridge] ${who} connected (${wss.clients.size} connected)`);
});

// Listening errors reach both the HTTP and WebSocket servers.
function onListenError(err) {
  console.error(err.code === 'EADDRINUSE'
    ? `[bridge] error: port ${HTTP_PORT} is already in use (is another copy running?)`
    : `[bridge] error: ${err.message}`);
  process.exit(1);
}
httpServer.on('error', onListenError);
wss.on('error', onListenError);

httpServer.listen(HTTP_PORT, () => {
  console.log(`[bridge] serving ${SITE_DIR} on http://localhost:${HTTP_PORT}/`);
  console.log(`[bridge] relaying /ws to odasrv at ${SERVER_HOST}:${SERVER_PORT}`);
});
