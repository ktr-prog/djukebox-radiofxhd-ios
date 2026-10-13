// Radio.fx source plugin "Qobuz" (own credentials, streaming only).
//
// NOT part of the app bundle. Copy this file to the app's Documents/Plugins folder (Files app) and switch it on under
// Quellen > Autostart. The plugin has NO built-in credentials. You enter them yourself, the app stores nothing:
//   * app_id and secret: access data that Qobuz issued to you for your own application
//   * your own login code (code_autorisation) from Qobuz's official sign-in page
// The plugin only streams: every title is marked "cache: false", so the host plays it from a temporary buffer file
// that is deleted when the app starts again; nothing is put into the library.
//
// Play reporting: the plugin tells Qobuz which titles you played and for how long (track/reportStreamingStart and
// ...EndJson), so that the artists are counted. On by default; switch off by typing  report=off  in the sign-in dialog.
// The reports identify this client honestly (software_version "radiofx-ios/..."), they never pretend to be another app.
//
// Written from the public API shape used by third-party clients; untested against the live service.

var BASE = 'https://www.qobuz.com/api.json/0.2/';

// ---- md5 (needed for the signed file-url request) ----
function md5(str) {
  function rl(n, c) { return (n << c) | (n >>> (32 - c)); }
  function add(x, y) { return (x + y) | 0; }
  var S = [7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
           4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21];
  var K = [], i;
  for (i = 0; i < 64; i++) K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) | 0;
  var bytes = [], u = unescape(encodeURIComponent(str));
  for (i = 0; i < u.length; i++) bytes.push(u.charCodeAt(i));
  var bitLen = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  for (i = 0; i < 4; i++) bytes.push((bitLen >>> (8 * i)) & 255);
  for (i = 0; i < 4; i++) bytes.push(0);
  var a0 = 0x67452301 | 0, b0 = 0xefcdab89 | 0, c0 = 0x98badcfe | 0, d0 = 0x10325476 | 0;
  for (var off = 0; off < bytes.length; off += 64) {
    var M = [];
    for (i = 0; i < 16; i++)
      M[i] = bytes[off + i * 4] | (bytes[off + i * 4 + 1] << 8) | (bytes[off + i * 4 + 2] << 16) | (bytes[off + i * 4 + 3] << 24);
    var A = a0, B = b0, C = c0, D = d0;
    for (i = 0; i < 64; i++) {
      var F, g;
      if (i < 16) { F = (B & C) | (~B & D); g = i; }
      else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
      else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
      else { F = C ^ (B | ~D); g = (7 * i) % 16; }
      F = add(add(F, A), add(K[i], M[g]));
      A = D; D = C; C = B; B = add(B, rl(F, S[i]));
    }
    a0 = add(a0, A); b0 = add(b0, B); c0 = add(c0, C); d0 = add(d0, D);
  }
  var out = '', w = [a0, b0, c0, d0];
  for (i = 0; i < 4; i++)
    for (var j = 0; j < 4; j++) out += ('0' + ((w[i] >>> (8 * j)) & 255).toString(16)).slice(-2);
  return out;
}

function enc(s) { return encodeURIComponent(s); }
function cfg(k) { return hostGet(k) || ''; }

function qs(params) {
  var a = [];
  for (var k in params) if (params[k] !== undefined && params[k] !== null) a.push(enc(k) + '=' + enc(params[k]));
  return a.join('&');
}

function api(path, params, needAuth) {
  var id = cfg('app_id');
  if (!id) return Promise.reject(new Error('Erst anmelden: App-ID fehlt.'));
  var headers = { 'X-App-Id': id };
  var tok = cfg('token');
  if (needAuth !== false && tok) headers['X-User-Auth-Token'] = tok;
  return fetchText(BASE + path + '?' + qs(params || {}), { headers: headers }).then(function (r) {
    if (r.status === 401 || r.status === 403) throw new Error('Qobuz hat die Anmeldung abgelehnt (' + r.status + '). Bitte neu anmelden.');
    if (r.status === 404) throw new Error('Nicht gefunden.');
    if (r.status < 200 || r.status >= 300) {
      var m = ''; try { m = JSON.parse(r.text).message || ''; } catch (e) {}
      throw new Error('Qobuz antwortete mit HTTP ' + r.status + (m ? ': ' + m : ''));
    }
    try { return JSON.parse(r.text); } catch (e) { throw new Error('Qobuz hat etwas anderes als JSON geschickt.'); }
  });
}

function img(o) {
  if (!o) return undefined;
  var i = o.image || o;
  return i.large || i.small || i.thumbnail || i.back || undefined;
}

function albumItem(a) {
  var artist = (a.artist && a.artist.name) || '';
  var year = a.released_at ? new Date(a.released_at * 1000).getUTCFullYear() : undefined;
  return {
    ref: 'album/' + a.id, kind: 'album', title: a.title + (a.version ? ' (' + a.version + ')' : ''),
    subtitle: artist, artist: artist, album: a.title, year: year,
    track_count: a.tracks_count, art: img(a),
    playable: false, browsable: true
  };
}

var DUR = {};     // track id -> length in seconds (from search/browse)
var STREAMS = {}; // track id -> { format_id, blob }
var PLAYING = {}; // ref -> { started, blob }
var SOFTWARE = 'radiofx-ios/1.0';

function trackItem(t, album) {
  if (t.id && t.duration) DUR[t.id] = t.duration;
  var al = t.album || album || {};
  var artist = (t.performer && t.performer.name) || (al.artist && al.artist.name) || '';
  return {
    ref: 'track/' + t.id, kind: 'track', title: t.title + (t.version ? ' (' + t.version + ')' : ''),
    subtitle: artist, artist: artist, album: al.title || '', track_no: t.track_number, disc_no: t.media_number,
    duration_ms: (t.duration || 0) * 1000, art: img(al), playable: t.streamable !== false, browsable: false
  };
}

function exchange(code) {
  var id = cfg('app_id'), secret = cfg('secret');
  if (!id || !secret) return Promise.reject(new Error('App-ID und Secret fehlen noch.'));
  return fetchText(BASE + 'oauth/callback?' + qs({ code: code, private_key: secret }), { headers: { 'X-App-Id': id } }).then(function (r) {
    var j = null; try { j = JSON.parse(r.text); } catch (e) {}
    if (r.status < 200 || r.status >= 300 || !j) throw new Error('Der Code wurde nicht angenommen (HTTP ' + r.status + ').');
    var tok = j.token || j.user_auth_token || (j.user && j.user.user_auth_token);
    if (!tok) throw new Error('Qobuz hat kein Anmelde-Token geliefert.');
    hostSet('token', tok);
    var uid = j.user_id || (j.user && j.user.id);
    if (uid) hostSet('user_id', String(uid));
    return { ok: true };
  });
}

function completeAuth(input) {
  var s = String(input || '').trim();
  var m;
  if ((m = /^(?:app_id|id)\s*=\s*(\S+)$/i.exec(s))) { hostSet('app_id', m[1]); return Promise.resolve({ ok: true, message: 'App-ID gespeichert.' }); }
  if ((m = /^secret\s*=\s*(\S+)$/i.exec(s))) { hostSet('secret', m[1]); return Promise.resolve({ ok: true, message: 'Secret gespeichert.' }); }
  if ((m = /^redirect\s*=\s*(\S+)$/i.exec(s))) { hostSet('redirect', m[1]); return Promise.resolve({ ok: true, message: 'Redirect gespeichert.' }); }
  if ((m = /^format\s*=\s*(\d+)$/i.exec(s))) { hostSet('format', m[1]); return Promise.resolve({ ok: true, message: 'Format gespeichert.' }); }
  if ((m = /^report\s*=\s*(on|off)$/i.exec(s))) {
    hostSet('report', m[1].toLowerCase());
    if (m[1].toLowerCase() === 'off') hostSet('pending', '');
    return Promise.resolve({ ok: true, message: 'Wiedergabe-Meldung: ' + m[1].toLowerCase() });
  }
  if (/^(clear|reset)$/i.test(s)) { ['app_id', 'secret', 'token', 'user_id', 'redirect', 'pending'].forEach(function (k) { hostSet(k, ''); }); return Promise.resolve({ ok: true }); }
  m = /code_autorisation=([^&\s#]+)/.exec(s);
  var code = m ? decodeURIComponent(m[1]) : s;
  if (!code) return Promise.reject(new Error('Nichts eingegeben.'));
  return exchange(code);
}

var FORMATS = [27, 7, 6, 5];

function fileUrl(id, fmt) {
  var secret = cfg('secret');
  var ts = String(Math.floor(Date.now() / 1000));
  var sig = md5('trackgetFileUrlformat_id' + fmt + 'intentstreamtrack_id' + id + ts + secret);
  return api('track/getFileUrl', { track_id: id, format_id: fmt, intent: 'stream', request_ts: ts, request_sig: sig });
}

// ---- play reporting ----
function reportOn() { return cfg('report') !== 'off' && !!cfg('token') && !!cfg('user_id'); }

function uuid4() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    var r = Math.floor(Math.random() * 16);
    return (c === 'x' ? r : ((r & 3) | 8)).toString(16);
  });
}

function postForm(path, fields) {
  return fetchText(BASE + path, {
    method: 'POST',
    headers: { 'X-App-Id': cfg('app_id'), 'X-User-Auth-Token': cfg('token'), 'Content-Type': 'application/x-www-form-urlencoded' },
    body: qs(fields)
  });
}

function playbackStarted(ref) {
  var m = /^track\/(\d+)$/.exec(ref || '');
  if (!m || !reportOn()) return Promise.resolve({ ok: true });
  var st = STREAMS[m[1]] || {};
  var now = Math.floor(Date.now() / 1000);
  PLAYING[ref] = { started: now, blob: st.blob || null, id: m[1] };
  var ev = { track_id: parseInt(m[1], 10), date: now, user_id: parseInt(cfg('user_id'), 10) };
  if (st.format_id) ev.format_id = st.format_id;
  return postForm('track/reportStreamingStart', { events: JSON.stringify([ev]) })
    .then(function () { return { ok: true }; }, function () { return { ok: true }; });
}

function pendingList() { try { return JSON.parse(cfg('pending') || '[]'); } catch (e) { return []; } }

function flushReports() {
  var list = pendingList();
  if (!list.length || !reportOn()) return Promise.resolve();
  var batch = list.slice(0, 20);
  return fetchText(BASE + 'track/reportStreamingEndJson', {
    method: 'POST',
    headers: { 'X-App-Id': cfg('app_id'), 'X-User-Auth-Token': cfg('token'), 'Content-Type': 'application/json' },
    body: JSON.stringify({ events: batch, renderer_context: { software_version: SOFTWARE } })
  }).then(function (r) {
    var j = null; try { j = JSON.parse(r.text); } catch (e) {}
    if (!j || j.status !== 'success') return; // keep for later
    var cur = pendingList();
    hostSet('pending', JSON.stringify(cur.slice(batch.length)));
    if (cur.length > batch.length) return flushReports();
  }, function () {});
}

function playbackEnded(ref, ms) {
  var pl = PLAYING[ref];
  delete PLAYING[ref];
  if (!pl || !pl.blob || !reportOn()) return flushReports().then(function () { return { ok: true }; });
  var secs = Math.floor((ms || 0) / 1000);
  if (DUR[pl.id]) secs = Math.min(secs, DUR[pl.id]);
  if (secs > 0) {
    var list = pendingList();
    list.push({ blob: pl.blob, track_context_uuid: uuid4(), start_stream: new Date(pl.started * 1000).toISOString(),
                online: true, local: false, duration: secs });
    if (list.length > 200) list = list.slice(list.length - 200);
    hostSet('pending', JSON.stringify(list));
  }
  return flushReports().then(function () { return { ok: true }; });
}

function handle(method, p) {
  switch (method) {
    case 'initialize':
      return Promise.resolve({
        protocol: 1,
        plugin: { id: 'qobuz', name: 'Qobuz (eigene Zugangsdaten)', version: '0.2.0' },
        capabilities: { browse: true, search: true, resolve: true, auth: true, reporting: true }
      });

    case 'auth.status': {
      var have = !!cfg('token');
      return Promise.resolve({
        state: have ? 'signed_in' : (cfg('app_id') && cfg('secret') ? 'signed_out' : 'needs_setup'),
        account: have ? { display_name: cfg('user_id') ? ('Nutzer ' + cfg('user_id')) : 'angemeldet' } : undefined
      });
    }
    case 'auth.begin': {
      if (!cfg('app_id') || !cfg('secret')) {
        return Promise.resolve({ url: null, expects_input: true,
          instructions: 'Gib nacheinander ein (je mit Senden):\n  app_id=DEINE_APP_ID\n  secret=DEIN_SECRET\nDas sind Zugangsdaten, die Qobuz dir für eine eigene App ausgestellt hat. Danach noch einmal Anmelden tippen.' });
      }
      var u = 'https://www.qobuz.com/signin/oauth?ext_app_id=' + enc(cfg('app_id')) + (cfg('redirect') ? '&redirect_url=' + enc(cfg('redirect')) : '');
      return Promise.resolve({ url: u, expects_input: true,
        instructions: 'Melde dich auf der Qobuz-Seite mit deinem eigenen Konto an. Kopiere danach die Adresse der Seite, auf der du landest (sie enthält code_autorisation=…), und füge sie hier ein. Optional: redirect=ADRESSE oder format=27|7|6|5 (27 = bis 24 Bit/192 kHz, 7 = 24/96, 6 = CD, 5 = MP3).' });
    }
    case 'auth.complete': return completeAuth(p && p.input);
    case 'auth.sign_out': hostSet('token', ''); hostSet('user_id', ''); hostSet('pending', ''); return Promise.resolve({ ok: true });

    case 'browse.root':
      return Promise.resolve({ sections: [
        { ref: 'new', kind: 'folder', title: 'Neuheiten', browsable: true, playable: false },
        { ref: 'fav-albums', kind: 'folder', title: 'Meine Alben', browsable: true, playable: false },
        { ref: 'fav-tracks', kind: 'folder', title: 'Meine Titel', browsable: true, playable: false }
      ] });

    case 'browse.list': {
      var r = p.ref, o = p.offset || 0, l = p.limit || 50;
      if (r === 'new')
        return api('album/getFeatured', { type: 'new-releases', offset: o, limit: l }).then(function (j) {
          var a = (j.albums && j.albums.items) || [];
          return { items: a.map(albumItem), total: (j.albums && j.albums.total) || a.length, has_more: false };
        });
      if (r === 'fav-albums')
        return api('favorite/getUserFavorites', { type: 'albums', offset: o, limit: l }).then(function (j) {
          var a = (j.albums && j.albums.items) || [];
          return { items: a.map(albumItem), total: (j.albums && j.albums.total) || a.length, has_more: false };
        });
      if (r === 'fav-tracks')
        return api('favorite/getUserFavorites', { type: 'tracks', offset: o, limit: l }).then(function (j) {
          var t = (j.tracks && j.tracks.items) || [];
          return { items: t.map(function (x) { return trackItem(x); }), total: (j.tracks && j.tracks.total) || t.length, has_more: false };
        });
      if (r.indexOf('album/') === 0)
        return api('album/get', { album_id: r.slice(6) }).then(function (j) {
          var t = (j.tracks && j.tracks.items) || [];
          return { items: t.map(function (x) { return trackItem(x, j); }), total: t.length, has_more: false };
        });
      return Promise.reject(new Error('Unbekannter Eintrag.'));
    }

    case 'search': {
      var q = String(p.query || '').trim();
      if (!q) return Promise.resolve({ groups: [] });
      return api('catalog/search', { query: q, offset: p.offset || 0, limit: p.limit || 12 }).then(function (j) {
        var groups = [];
        var al = (j.albums && j.albums.items) || [];
        var tr = (j.tracks && j.tracks.items) || [];
        if (al.length) groups.push({ kind: 'album', items: al.map(albumItem), total: j.albums.total, has_more: false });
        if (tr.length) groups.push({ kind: 'track', items: tr.map(function (x) { return trackItem(x); }), total: j.tracks.total, has_more: false });
        return { groups: groups };
      });
    }

    case 'track.resolve': {
      var m = /^track\/(\d+)$/.exec(p.ref || '');
      if (!m) return Promise.reject(new Error('Ungültige Referenz.'));
      var want = parseInt(cfg('format'), 10) || 27;
      var order = FORMATS.filter(function (f) { return f <= want; });
      if (!order.length) order = [5];
      function attempt(i) {
        return fileUrl(m[1], order[i]).then(function (j) {
          if (!j || !j.url) throw new Error('Kein Stream für dieses Format.');
          var fmt = j.format_id || order[i];
          STREAMS[m[1]] = { format_id: fmt, blob: j.blob || null };
          return {
            url: j.url, cache: false, delivery: 'direct',
            format: { codec: fmt === 5 ? 'mp3' : 'flac', sample_rate: Math.round((j.sampling_rate || 0) * 1000) || undefined, bits: j.bit_depth || undefined }
          };
        }).catch(function (e) {
          if (i + 1 < order.length && !/abgelehnt|anmeld/i.test(String(e.message))) return attempt(i + 1);
          throw e;
        });
      }
      return attempt(0);
    }

    case 'playback.started': return playbackStarted(p && p.ref);
    case 'playback.ended': return playbackEnded(p && p.ref, p && p.listened_ms);

    default:
      return Promise.reject(new Error('method not found'));
  }
}
