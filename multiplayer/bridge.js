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
const net = require('node:net');
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
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { Allow: 'GET, HEAD' }).end();
    return;
  }
  // A malformed URL (bad %-escape) would otherwise throw and stop the bridge.
  let urlPath;
  try {
    urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  } catch {
    res.writeHead(400).end();
    return;
  }
  if (urlPath.includes('\0')) {
    res.writeHead(400).end();
    return;
  }
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
      'X-Content-Type-Options': 'nosniff',
    });
    if (req.method === 'HEAD') {
      res.end();
      return;
    }
    // An unhandled stream error (say, the file was just replaced) would stop
    // the bridge.
    fs.createReadStream(file).on('error', () => res.destroy()).pipe(res);
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
  // One message is one UDP datagram; odasrv's packets are at most 8 KB.
  // (ws would otherwise buffer messages of up to 100 MB.)
  maxPayload: 64 * 1024,
});

// Limits, since anyone who can load the page can connect.  A player needs one
// connection, sending about 35 packets a second (one per game tic).
const MAX_CONNECTIONS = 64;           // in all (the server takes 16 players)
// Behind some setups (Docker's port forwarding, a proxy in another container)
// every player has the same address, so this is no lower than the server's
// player limit.
const MAX_CONNECTIONS_PER_IP = 16;
const PACKETS_PER_SECOND = 100;       // more is dropped, as UDP would
const PACKET_BURST = 200;
const MAX_BUFFERED_TO_BROWSER = 1024 * 1024;  // a browser not reading: drop packets
const HEARTBEAT_MS = 30000;           // drop connections that stop answering pings

const connectionsPerIp = new Map();
let connections = 0;

// Reverse proxies whose X-Forwarded-For is believed: a comma-separated list of
// addresses, subnets (172.18.0.0/16) and "gateway", this machine's default
// gateway (in Docker, how the host's proxy reaches a published port).  Only
// list proxies: anyone else connecting from one of these addresses could make
// up their own.
const TRUSTED_PROXIES = process.env.TRUSTED_PROXIES || '127.0.0.1,::1';

// "::ffff:1.2.3.4", how IPv4 addresses arrive on a dual-stack socket, as 1.2.3.4.
function plainIp(ip) {
  return ip.startsWith('::ffff:') && net.isIPv4(ip.slice(7)) ? ip.slice(7) : ip;
}

// The default gateway from /proc/net/route, where it is hex, in byte order.
function defaultGateway() {
  try {
    for (const line of fs.readFileSync('/proc/net/route', 'latin1').split('\n').slice(1)) {
      const [, destination, gateway] = line.trim().split(/\s+/);
      if (destination === '00000000' && gateway && gateway !== '00000000') {
        return Buffer.from(gateway, 'hex').reverse().join('.');
      }
    }
  } catch {}
  return null;
}

const trustedProxies = new net.BlockList();
for (const entry of TRUSTED_PROXIES.split(',').map((e) => e.trim()).filter(Boolean)) {
  const [address, prefix] = entry === 'gateway' ? [defaultGateway()] : entry.split('/');
  const type = address && net.isIP(address) === 6 ? 'ipv6' : 'ipv4';
  if (!address || !net.isIP(address) || (prefix !== undefined && !/^\d+$/.test(prefix))) {
    console.error(`[bridge] error: TRUSTED_PROXIES: can't use "${entry}"`);
    process.exit(1);
  }
  if (prefix !== undefined) trustedProxies.addSubnet(address, Number(prefix), type);
  else trustedProxies.addAddress(address, type);
  console.log(`[bridge] trusting X-Forwarded-For from ${entry === 'gateway' ? address + ' (gateway)' : entry}`);
}

// The browser's address.  Behind a trusted reverse proxy, the proxy's
// X-Forwarded-For is used instead: its last entry, the one the proxy added
// (nginx's $proxy_add_x_forwarded_for, Caddy and cloudflared all add one).
function clientIp(req) {
  const ip = plainIp(req.socket.remoteAddress || '');
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && net.isIP(ip) &&
      trustedProxies.check(ip, net.isIP(ip) === 6 ? 'ipv6' : 'ipv4')) {
    const last = plainIp(forwarded.split(',').pop().trim());
    if (net.isIP(last)) return last;
  }
  return ip;
}

wss.on('connection', (ws, req) => {
  const ip = clientIp(req);
  const who = ip + ':' + req.socket.remotePort;
  const ipCount = connectionsPerIp.get(ip) || 0;
  if (connections >= MAX_CONNECTIONS || ipCount >= MAX_CONNECTIONS_PER_IP) {
    console.warn(`[bridge] ${who} refused: too many connections`);
    ws.close(1013, 'Too many connections');
    return;
  }
  connections++;
  connectionsPerIp.set(ip, ipCount + 1);

  // Connected to odasrv, so the socket only accepts datagrams from it: anyone
  // else sending to this port can't inject packets into the game.
  const udp = dgram.createSocket('udp4');
  let udpReady = false;
  let pending = [];   // packets from the browser before the socket is ready
  let open = true;
  let alive = true;
  let tokens = PACKET_BURST;
  let lastRefill = Date.now();

  function close() {
    if (!open) return;
    open = false;
    clearInterval(heartbeat);
    udp.close();
    ws.terminate();
    connections--;
    const left = connectionsPerIp.get(ip) - 1;
    if (left > 0) connectionsPerIp.set(ip, left);
    else connectionsPerIp.delete(ip);
    console.log(`[bridge] ${who} disconnected (${connections} connected)`);
  }

  udp.connect(Number(SERVER_PORT), SERVER_HOST, () => {
    udpReady = true;
    for (const data of pending) udp.send(data);
    pending = null;
  });
  udp.on('message', (msg) => {
    if (ws.readyState === ws.OPEN && ws.bufferedAmount < MAX_BUFFERED_TO_BROWSER) {
      ws.send(msg, { binary: true });
    }
  });
  udp.on('error', (err) => {
    console.warn(`[bridge] ${who} UDP error: ${err.message}`);
    close();
  });

  ws.on('message', (data, isBinary) => {
    if (!isBinary || isPortHandshake(data)) return;

    const now = Date.now();
    tokens = Math.min(PACKET_BURST, tokens + (now - lastRefill) * PACKETS_PER_SECOND / 1000);
    lastRefill = now;
    if (tokens < 1) return;
    tokens--;

    if (udpReady) udp.send(data);
    else if (pending.length < 32) pending.push(data);
  });
  ws.on('pong', () => { alive = true; });
  ws.on('close', close);
  ws.on('error', close);

  const heartbeat = setInterval(() => {
    if (!alive) {
      console.log(`[bridge] ${who} stopped responding`);
      close();
      return;
    }
    alive = false;
    ws.ping();
  }, HEARTBEAT_MS);

  console.log(`[bridge] ${who} connected (${connections} connected)`);
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
