// Shared boot code for the Odamex Web pages.  Needs odamex.js loaded first.
//
//   OdamexWeb.boot({
//     canvas, iwad: 'DOOM1.WAD', args: [...],   // extra command-line args
//     websocketUrl,                             // multiplayer only
//     onStatus(text, fraction), onFatal(message),
//   })

var OdamexWeb = (function () {
  var CONFIG_DIR = '/home/web_user/.odamex';
  var WAD_DIR = '/data';

  // Run after the saved config loads, so these win over older saved settings.
  // hud_scalescoreboard is multiplied by the screen's integer scale factor (3
  // at 1280x720), so 0.7 draws the scoreboard at 2x; 3x would not fit.
  var WEB_CFG = [
    'bind tab +showscores',
    'bind m togglemap',
    'set hud_scalescoreboard 0.7',
  ].join('\n') + '\n';

  // Fetch a file with progress reporting; resolves to a Uint8Array.
  async function fetchWithProgress(url, onProgress) {
    var res = await fetch(url);
    if (!res.ok) throw new Error('Could not download ' + url + ' (' + res.status + ')');
    var total = +res.headers.get('Content-Length') || 0;
    var reader = res.body.getReader(), chunks = [], got = 0;
    for (;;) {
      var r = await reader.read();
      if (r.done) break;
      chunks.push(r.value); got += r.value.length;
      onProgress(got, total);
    }
    var out = new Uint8Array(got), pos = 0;
    chunks.forEach(function (c) { out.set(c, pos); pos += c.length; });
    return out;
  }

  function syncfs(FS, populate) {
    return new Promise(function (resolve) {
      FS.syncfs(populate, function (err) {
        if (err) console.warn('IDBFS sync failed', err);
        resolve();
      });
    });
  }

  async function boot(opts) {
    var onStatus = opts.onStatus || function () {};
    onStatus('Starting engine…', 0);

    var config = {
      canvas: opts.canvas,
      print: function (t) { console.log(t); },
      printErr: function (t) { console.warn(t); },
      onFatal: opts.onFatal,
      onAbort: function (what) { opts.onFatal('The engine crashed: ' + what); },
    };
    if (opts.websocketUrl) config.websocket = { url: opts.websocketUrl, subprotocol: 'binary' };
    var mod = await createOdamex(config);
    var FS = mod.FS;

    // Persist the config (odamex.cfg, screenshots) in IndexedDB.
    FS.mkdirTree(CONFIG_DIR);
    FS.mount(FS.filesystems.IDBFS, {}, CONFIG_DIR);
    await syncfs(FS, true);

    // Download the game.  The engine's own resources are built into it.
    FS.mkdirTree(WAD_DIR);
    var data = await fetchWithProgress('wads/' + opts.iwad, function (got, total) {
      onStatus('Downloading ' + opts.iwad + ' — ' + (got / 1048576).toFixed(1) + ' MB' +
               (total ? ' of ' + (total / 1048576).toFixed(1) + ' MB' : ''),
               total ? got / total : 0);
    });
    FS.writeFile(WAD_DIR + '/' + opts.iwad, data);

    // Save settings periodically and when the page is hidden.
    setInterval(function () { syncfs(FS, false); }, 10000);
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'hidden') syncfs(FS, false);
    });

    // Clicking the game captures the mouse for mouselook.
    opts.canvas.addEventListener('click', function () {
      if (document.pointerLockElement !== this && this.requestPointerLock) this.requestPointerLock();
    });

    FS.writeFile(WAD_DIR + '/odamex-web.cfg', WEB_CFG);

    onStatus('', 1);
    opts.canvas.focus();
    mod.callMain([
      '-iwad', WAD_DIR + '/' + opts.iwad,
      '-waddir', WAD_DIR,
      '+set', 'vid_fullscreen', '0',
      '+exec', WAD_DIR + '/odamex-web.cfg',
    ].concat(opts.args || []));
    return mod;
  }

  return { boot: boot };
})();
