// Radio.fx source plugin "Qobuz" (streaming only, your own account and your own access data).
//
// This file ships with the app and is copied to  Dateien > Radio.fx > Plugins  on first start.
// FILL IN THE GAPS BELOW (the lines marked "LUECKE"), save the file, then switch the plugin on under
// Quellen > Plugins an/aus (restart the app once). The app never stores these values anywhere else; they live only here.
// If you want a clean copy again, delete this file in the Files app; the app puts a fresh one back on the next start.
//
// What the plugin does: search, browse (new releases, your favourites) and stream. Every title is marked "cache: false",
// so it plays from a temporary buffer file that is deleted at the next app start; nothing is put into the library.
// It also tells Qobuz what you played and for how long (REPORT_PLAYS), identifying itself honestly as "radiofx-ios".
// Written from the API shape that third-party clients use; untested against the live service.

// ---------------------------------------------------------------------------------------------------------------
// LUECKE 1 - APP_ID: the application id that Qobuz issued to you for your own app. Put it between the quotes.
//            Example: var APP_ID = '123456789';
var APP_ID = '';

// LUECKE 2 - SECRET: the secret that belongs to that application id (also issued by Qobuz). Keep this file private.
//            Example: var SECRET = 'abcdef0123456789abcdef0123456789';
var SECRET = '';

// LUECKE 3 - CODE_AUTORISATION: your own login code. How to get it:
//            1. Open this address in the browser, with your APP_ID in place of APP_ID_HERE:
//               https://www.qobuz.com/signin/oauth?ext_app_id=APP_ID_HERE
//               (if Qobuz wants a return address, add  &redirect_url=ADDRESS  and put the same ADDRESS in LUECKE 4)
//            2. Sign in with your own Qobuz account.
//            3. Qobuz sends you to an address that contains  code_autorisation=XXXX . Copy the XXXX part (or the whole
//               address, both work) and put it between the quotes.
//            The code is used once and swapped for a login token that the app remembers. If Qobuz later refuses the
//            login, get a new code the same way and replace this one.
var CODE_AUTORISATION = '';

// LUECKE 4 (optional) - REDIRECT_URL: only if Qobuz asked for a return address in step 1; otherwise leave it empty.
var REDIRECT_URL = '';

// LUECKE 5 (optional) - FORMAT: highest quality to ask for. 27 = up to 24 bit/192 kHz, 7 = 24 bit/96 kHz, 6 = CD, 5 = MP3.
var FORMAT = 27;

// LUECKE 6 (optional) - REPORT_PLAYS: true = tell Qobuz what you played (so the artists get counted), false = do not.
var REPORT_PLAYS = true;
// ---------------------------------------------------------------------------------------------------------------

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
  return ready().then(function () { return apiCall(path, params, needAuth); });
}

function apiCall(path, params, needAuth) {
  var id = APP_ID;
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
  var id = APP_ID, secret = SECRET;
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
  if (!s) return Promise.reject(new Error('Nichts eingegeben.'));
  var m = /code_autorisation=([^&\s#]+)/.exec(s);
  return exchange(m ? decodeURIComponent(m[1]) : s);
}

// the code from LUECKE 3 is swapped for a token automatically, once
function ready() {
  if (cfg('token')) return Promise.resolve();
  var m = /code_autorisation=([^&\s#]+)/.exec(CODE_AUTORISATION || '');
  var code = m ? decodeURIComponent(m[1]) : String(CODE_AUTORISATION || '').trim();
  if (!APP_ID || !SECRET) return Promise.reject(new Error('Qobuz: LUECKE 1 und 2 (APP_ID, SECRET) in Plugins/qobuz.js ausfüllen.'));
  if (!code) return Promise.reject(new Error('Qobuz: LUECKE 3 (CODE_AUTORISATION) in Plugins/qobuz.js ausfüllen.'));
  if (cfg('used_code') === code) return Promise.reject(new Error('Qobuz: der Code wurde schon benutzt und ist nicht mehr gültig. Neuen CODE_AUTORISATION holen.'));
  hostSet('used_code', code);
  return exchange(code);
}

var FORMATS = [27, 7, 6, 5];

function fileUrl(id, fmt) {
  var secret = SECRET;
  var ts = String(Math.floor(Date.now() / 1000));
  var sig = md5('trackgetFileUrlformat_id' + fmt + 'intentstreamtrack_id' + id + ts + secret);
  return api('track/getFileUrl', { track_id: id, format_id: fmt, intent: 'stream', request_ts: ts, request_sig: sig });
}

// ---- play reporting ----
function reportOn() { return REPORT_PLAYS !== false && !!cfg('token') && !!cfg('user_id'); }

function uuid4() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    var r = Math.floor(Math.random() * 16);
    return (c === 'x' ? r : ((r & 3) | 8)).toString(16);
  });
}

function postForm(path, fields) {
  return fetchText(BASE + path, {
    method: 'POST',
    headers: { 'X-App-Id': APP_ID, 'X-User-Auth-Token': cfg('token'), 'Content-Type': 'application/x-www-form-urlencoded' },
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
    headers: { 'X-App-Id': APP_ID, 'X-User-Auth-Token': cfg('token'), 'Content-Type': 'application/json' },
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
        plugin: { id: 'qobuz', name: 'Qobuz (eigene Zugangsdaten)', version: '0.3.0' },
        capabilities: { browse: true, search: true, resolve: true, auth: true, reporting: true }
      });

    case 'auth.status': {
      var have = !!cfg('token');
      return Promise.resolve({
        state: have ? 'signed_in' : (APP_ID && SECRET && CODE_AUTORISATION ? 'signed_out' : 'needs_setup'),
        account: have ? { display_name: cfg('user_id') ? ('Nutzer ' + cfg('user_id')) : 'angemeldet' } : undefined
      });
    }
    case 'auth.begin':
      if (!APP_ID || !SECRET || !CODE_AUTORISATION)
        return Promise.resolve({ url: null, expects_input: false,
          instructions: 'Die Zugangsdaten stehen in der Datei Plugins/qobuz.js (Dateien-App > Radio.fx > Plugins). Fülle dort die Lücken 1 bis 3 aus (APP_ID, SECRET, CODE_AUTORISATION), speichere und starte die App neu.' });
      return Promise.resolve({ url: null, expects_input: true,
        instructions: 'Die Lücken in Plugins/qobuz.js sind ausgefüllt. Hier kannst du alternativ einen neuen Code (oder die ganze Adresse mit code_autorisation=...) einfügen.' });
    case 'auth.complete': return completeAuth(p && p.input);
    case 'auth.sign_out': hostSet('token', ''); hostSet('user_id', ''); hostSet('pending', ''); hostSet('used_code', ''); return Promise.resolve({ ok: true });

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
      var want = parseInt(FORMAT, 10) || 27;
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
