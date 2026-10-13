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
// Browsing was ported from the open-source ricercar-qconnect plugin (catalogue calls and item shapes only): favourites,
// your playlists, Discover shelves, new releases, album/artist/playlist/label pages, radio and similar albums.
// NOT taken over: its web-player access data, its encrypted-stream relay and Qobuz Connect.
// Written from the API shape that third-party clients use; untested against the live service.

// ---------------------------------------------------------------------------------------------------------------
// LUECKE 1 - APP_ID: the application id that Qobuz issued to you for your own app. Put it between the quotes.
//            Example: var APP_ID = '123456789';
var APP_ID = '950096963';

// LUECKE 2 - SECRET: the secret that belongs to that application id (also issued by Qobuz). Keep this file private.
//            Example: var SECRET = 'abcdef0123456789abcdef0123456789';
var SECRET = '979549437fcc4a3faad4867b5cd25dcb';

// LUECKE 3 - CODE_AUTORISATION: your own login code (or use EMAIL and PASSWORD in LUECKE 3b instead). How to get it:
//            1. Open this address in the browser, with your APP_ID in place of APP_ID_HERE:
//               https://www.qobuz.com/signin/oauth?ext_app_id=APP_ID_HERE
//               (if Qobuz wants a return address, add  &redirect_url=ADDRESS  and put the same ADDRESS in LUECKE 4)
//            2. Sign in with your own Qobuz account.
//            3. Qobuz sends you to an address that contains  code_autorisation=XXXX . Copy the XXXX part (or the whole
//               address, both work) and put it between the quotes.
//            The code is used once and swapped for a login token that the app remembers. If Qobuz later refuses the
//            login, get a new code the same way and replace this one.
var CODE_AUTORISATION = '';

// LUECKE 3b (Alternative zu Lücke 3) - EMAIL und PASSWORD: deine eigenen Qobuz-Anmeldedaten. Wenn beide ausgefüllt sind (und
//            Lücke 3 leer ist), meldet sich das Plugin selbst an (user/login) und holt sich bei Bedarf automatisch ein neues Token.
//            Achtung: das Passwort steht dann im Klartext in dieser Datei. Gib die Datei nie weiter.
var EMAIL = 'kt.brauner@gmail.com';
var PASSWORD = '#AmongUs69';

// LUECKE 4 (optional) - REDIRECT_URL: only if Qobuz asked for a return address in step 1; otherwise leave it empty.
var REDIRECT_URL = '';

// LUECKE 5 (optional) - FORMAT: highest quality to ask for. 27 = up to 24 bit/192 kHz, 7 = 24 bit/96 kHz, 6 = CD, 5 = MP3.
var FORMAT = 27;

// LUECKE 6 (optional) - REPORT_PLAYS: true = tell Qobuz what you played (so the artists get counted), false = do not.
var REPORT_PLAYS = true;

// LUECKE 7 (optional, AUS) - CACHE_TRACKS: false = stream only (temporary buffer, deleted at the next app start, nothing in the library).
//            true = the played title is kept as a file in the Radio.fx library (offline cache).
//            Switch this on ONLY if the terms of your Qobuz access (the agreement you got with your APP_ID) allow storing titles.
//            That check and the responsibility for it are yours. Without Qobuz's permission leave it false.
var CACHE_TRACKS = true;
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
  return ready().then(function () { return apiCall(path, params, needAuth); }).catch(function (e) {
    // token expired and e-mail/password given: log in again once
    if (e && e.auth && EMAIL && PASSWORD && !cfg('relogin')) {
      hostSet('token', ''); hostSet('relogin', '1');
      return loginPassword().then(function () { hostSet('relogin', ''); return apiCall(path, params, needAuth); },
                                  function (e2) { hostSet('relogin', ''); throw e2; });
    }
    throw e;
  });
}

function apiCall(path, params, needAuth) {
  var id = APP_ID;
  var headers = { 'X-App-Id': id };
  var tok = cfg('token');
  if (needAuth !== false && tok) headers['X-User-Auth-Token'] = tok;
  return fetchText(BASE + path + '?' + qs(params || {}), { headers: headers }).then(function (r) {
    if (r.status === 401 || r.status === 403) { var ea = new Error('Qobuz hat die Anmeldung abgelehnt (' + r.status + '). Bitte neu anmelden.'); ea.auth = true; throw ea; }
    if (r.status === 404) throw new Error('Nicht gefunden.');
    if (r.status < 200 || r.status >= 300) {
      var m = ''; try { m = JSON.parse(r.text).message || ''; } catch (e) {}
      throw new Error('Qobuz antwortete mit HTTP ' + r.status + (m ? ': ' + m : ''));
    }
    try { return JSON.parse(r.text); } catch (e) { throw new Error('Qobuz hat etwas anderes als JSON geschickt.'); }
  });
}

// signed request: md5( object + method + sorted(key+value) + timestamp + secret ), as the API expects for some calls
function apiSigned(obj, action, params) {
  params = params || {};
  var keys = Object.keys(params).filter(function (k) { return params[k] !== undefined && params[k] !== null; }).sort();
  var ts = String(Math.floor(Date.now() / 1000));
  var base = obj + action;
  keys.forEach(function (k) { base += k + params[k]; });
  var all = {};
  keys.forEach(function (k) { all[k] = params[k]; });
  all.request_ts = ts;
  all.request_sig = md5(base + ts + SECRET);
  return api(obj + '/' + action, all);
}

// ---- items (shapes follow the ricercar protocol; Qobuz answers come in two shapes, "classic" and "discover") ----
function nameOf(o) {
  if (!o) return '';
  if (typeof o === 'string') return o;
  var n = o.name;
  if (n && typeof n === 'object') n = n.display;
  return n ? String(n) : '';
}

function mainArtist(o) {
  if (!o) return '';
  if (o.performer && o.performer.name) return nameOf(o.performer);
  if (o.artist) return nameOf(o.artist);
  var as = o.artists;
  if (as && as.length) {
    for (var i = 0; i < as.length; i++) if ((as[i].roles || []).indexOf('main-artist') >= 0) return nameOf(as[i]);
    return nameOf(as[0]);
  }
  return '';
}

function img(o) {
  if (!o) return undefined;
  var i = o.image || o.images || o;
  if (i.portrait && i.portrait.hash)
    return 'https://static.qobuz.com/images/artists/covers/large/' + i.portrait.hash + '.' + (i.portrait.format || 'jpg');
  if (i.covers && i.covers.length) return i.covers[0];
  return i.large || i.extralarge || i.small || i.thumbnail || i.rectangle || i.back || o.picture || undefined;
}

function yearOf(a) {
  if (a.released_at) return new Date(a.released_at * 1000).getUTCFullYear();
  var d = a.release_date_original || (a.dates && a.dates.original) || a.release_date_stream;
  var y = d ? parseInt(String(d).slice(0, 4), 10) : NaN;
  return isNaN(y) ? undefined : y;
}

function fmtOf(o) {
  var ai = o.audio_info || o;
  var rate = ai.maximum_sampling_rate, bits = ai.maximum_bit_depth;
  if (!rate && !bits) return undefined;
  return { sample_rate: Math.round((rate || 0) * 1000) || undefined, bits: bits || undefined, codec: 'flac' };
}

function streamable(o) {
  if (o.streamable === false) return false;
  if (o.rights && o.rights.streamable === false) return false;
  return true;
}

function folder(ref, title) { return { ref: ref, kind: 'folder', title: title, playable: false, browsable: true }; }

function albumItem(a) {
  var artist = mainArtist(a);
  return {
    ref: 'album/' + a.id, kind: 'album', title: a.title + (a.version ? ' (' + a.version + ')' : ''),
    subtitle: artist, artist: artist, album: a.title, year: yearOf(a), genre: a.genre && a.genre.name,
    track_count: a.tracks_count || a.track_count, art: img(a), format: fmtOf(a),
    artist_ref: a.artist && a.artist.id ? 'artist/' + a.artist.id : undefined,
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
  var artist = mainArtist(t) || mainArtist(al);
  var ps = t.physical_support || {};
  return {
    ref: 'track/' + t.id, kind: 'track', title: t.title + (t.version ? ' (' + t.version + ')' : ''),
    subtitle: artist, artist: artist, album: al.title || '', album_artist: mainArtist(al) || undefined,
    track_no: t.track_number || ps.track_number, disc_no: t.media_number || ps.media_number,
    duration_ms: (t.duration || 0) * 1000, art: img(al), format: fmtOf(t),
    album_ref: al.id ? 'album/' + al.id : undefined,
    entry_id: t.playlist_track_id ? String(t.playlist_track_id) : undefined,
    playable: streamable(t), browsable: false
  };
}

function artistItem(x) {
  return { ref: 'artist/' + x.id, kind: 'artist', title: nameOf(x), subtitle: x.albums_count ? x.albums_count + ' Alben' : '',
           art: img(x), playable: false, browsable: true };
}

function playlistItem(p) {
  var owner = nameOf(p.owner);
  return { ref: 'playlist/' + p.id, kind: 'playlist', title: nameOf(p) || p.name, subtitle: owner,
           track_count: p.tracks_count || p.track_count, art: img(p), playable: false, browsable: true };
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

// login with e-mail and password (user/login): the answer holds the token and the user
function loginPassword() {
  var dev = cfg('device_id');
  if (!dev) { dev = uuid4(); hostSet('device_id', dev); }
  return fetchText(BASE + 'user/login?' + qs({ username: EMAIL, password: PASSWORD, device_manufacturer_id: dev }),
                   { headers: { 'X-App-Id': APP_ID } }).then(function (r) {
    var j = null; try { j = JSON.parse(r.text); } catch (e) {}
    if (r.status < 200 || r.status >= 300 || !j || !j.user_auth_token)
      throw new Error('Qobuz hat E-Mail/Passwort nicht angenommen (HTTP ' + r.status + '). Eingaben in Plugins/qobuz.js prüfen.');
    hostSet('token', j.user_auth_token);
    var uid = j.user && j.user.id;
    if (uid) hostSet('user_id', String(uid));
    return { ok: true };
  });
}

// the login from the gaps is done automatically, once: first the code (LUECKE 3), else e-mail and password (LUECKE 3b)
function ready() {
  if (cfg('token')) return Promise.resolve();
  var m = /code_autorisation=([^&\s#]+)/.exec(CODE_AUTORISATION || '');
  var code = m ? decodeURIComponent(m[1]) : String(CODE_AUTORISATION || '').trim();
  if (!APP_ID || !SECRET) return Promise.reject(new Error('Qobuz: LUECKE 1 und 2 (APP_ID, SECRET) in Plugins/qobuz.js ausfüllen.'));
  if (code && cfg('used_code') !== code) { hostSet('used_code', code); return exchange(code); }
  if (EMAIL && PASSWORD) return loginPassword();
  if (code) return Promise.reject(new Error('Qobuz: der Code wurde schon benutzt und ist nicht mehr gültig. Neuen CODE_AUTORISATION holen oder EMAIL/PASSWORD eintragen.'));
  return Promise.reject(new Error('Qobuz: LUECKE 3 (CODE_AUTORISATION) oder 3b (EMAIL und PASSWORD) in Plugins/qobuz.js ausfüllen.'));
}

var FORMATS = [27, 7, 6, 5];

function fileUrl(id, fmt) {
  return apiSigned('track', 'getFileUrl', { track_id: id, format_id: fmt, intent: 'stream' });
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

// ---- browsing ----
var DISCOVER = { 'qobuzissims': 'qobuzissims', 'album-of-the-week': 'albumOfTheWeek', 'playlists': 'playlists',
                 'most-streamed': 'mostStreamed', 'press-awards': 'pressAward', 'ideal-discography': 'idealDiscography' };
var DISCOVER_TITLES = { 'qobuzissims': 'Qobuzissimes', 'album-of-the-week': 'Album der Woche', 'playlists': 'Qobuz-Playlists',
                        'most-streamed': 'Meistgehört', 'press-awards': 'Auszeichnungen der Presse', 'ideal-discography': 'Ideale Diskografie' };

function paged(items, total, off, lim) {
  total = total == null ? undefined : total;
  return { items: items, total: total, has_more: total != null ? off + items.length < total : items.length >= lim };
}

function favList(kind, p) {
  var off = p.offset || 0, lim = Math.min(p.limit || 50, 200);
  return apiSigned('favorite', 'getUserFavorites', { type: kind, offset: off, limit: lim }).then(function (j) {
    var c = j[kind] || {}, it = c.items || [];
    var fn = kind === 'albums' ? albumItem : kind === 'artists' ? artistItem : function (x) { return trackItem(x); };
    return paged(it.map(fn), c.total, off, lim);
  });
}

function playlistsList(p) {
  var off = p.offset || 0, lim = Math.min(p.limit || 50, 200);
  return api('playlist/getUserPlaylists', { offset: off, limit: lim }).then(function (j) {
    var c = j.playlists || {}, it = c.items || [];
    return paged(it.map(playlistItem), c.total, off, lim);
  });
}

function albumsOf(j, off, lim) { var c = j.albums || {}, it = c.items || []; return paged(it.map(albumItem), c.total, off, lim); }
function tracksOf(j, off, lim, album) { var c = j.tracks || {}, it = c.items || []; return paged(it.map(function (x) { return trackItem(x, album); }), c.total, off, lim); }

function browseList(ref, off, lim) {
  var m;
  lim = Math.min(lim, 200);
  if (ref === 'fav') return Promise.resolve({ items: [folder('fav/albums', 'Alben'), folder('fav/tracks', 'Titel'), folder('fav/artists', 'Künstler')], total: 3, has_more: false });
  if (ref === 'fav/albums') return favList('albums', { offset: off, limit: lim });
  if (ref === 'fav/tracks') return favList('tracks', { offset: off, limit: lim });
  if (ref === 'fav/artists') return favList('artists', { offset: off, limit: lim });
  if (ref === 'my/playlists') return playlistsList({ offset: off, limit: lim });
  if (ref === 'discover') {
    var its = Object.keys(DISCOVER).map(function (k) { return folder('discover/' + k, DISCOVER_TITLES[k]); });
    return Promise.resolve({ items: its, total: its.length, has_more: false });
  }
  if ((m = /^featured\/(new-releases|editor-picks)$/.exec(ref)))
    return api('album/getFeatured', { type: m[1], offset: off, limit: lim }).then(function (j) { return albumsOf(j, off, lim); });
  if ((m = /^discover\/([a-z-]+)$/.exec(ref)) && DISCOVER[m[1]])
    return api('discover/' + DISCOVER[m[1]], { offset: off, limit: lim }).then(function (j) {
      var it = j.items || (j.albums && j.albums.items) || (j.playlists && j.playlists.items) || [];
      var out = it.map(function (x) { return (x.tracks_count != null || x.track_count != null) && x.owner ? playlistItem(x) : (x.owner && !x.artists && !x.artist ? playlistItem(x) : albumItem(x)); });
      return { items: out, has_more: j.has_more === true };
    });
  if ((m = /^album\/([\w-]+)$/.exec(ref)))
    return api('album/get', { album_id: m[1], offset: off, limit: lim }).then(function (j) { return tracksOf(j, off, lim, j); });
  if ((m = /^artist\/([\w-]+)$/.exec(ref)))
    return api('artist/get', { artist_id: m[1], extra: 'albums', offset: off, limit: lim }).then(function (j) { return albumsOf(j, off, lim); });
  if ((m = /^playlist\/([\w-]+)$/.exec(ref)))
    return api('playlist/get', { playlist_id: m[1], extra: 'tracks', offset: off, limit: lim }).then(function (j) { return tracksOf(j, off, lim); });
  if ((m = /^label\/([\w-]+)$/.exec(ref)))
    return api('label/get', { label_id: m[1], extra: 'albums', offset: off, limit: lim }).then(function (j) { return albumsOf(j, off, lim); });
  if ((m = /^radio\/(track|album|artist)\/([\w-]+)$/.exec(ref))) {
    var prm = {}; prm[m[1] + '_id'] = m[2];
    return api('radio/' + m[1], prm).then(function (j) { var t = tracksOf(j, 0, 500); t.has_more = false; return t; });
  }
  if ((m = /^similar\/([\w-]+)$/.exec(ref)))
    return api('album/suggest', { album_id: m[1] }).then(function (j) { var a = albumsOf(j, 0, 500); a.has_more = false; return a; });
  return Promise.reject(new Error('Unbekannter Eintrag.'));
}

function handle(method, p) {
  switch (method) {
    case 'initialize':
      return Promise.resolve({
        protocol: 1,
        plugin: { id: 'qobuz', name: 'Qobuz (eigene Zugangsdaten)', version: '0.5.0' },
        capabilities: { browse: true, search: true, resolve: true, auth: true, reporting: true, library: true }
      });

    case 'auth.status': {
      var have = !!cfg('token');
      return Promise.resolve({
        state: have ? 'signed_in' : (APP_ID && SECRET && (CODE_AUTORISATION || (EMAIL && PASSWORD)) ? 'signed_out' : 'needs_setup'),
        account: have ? { display_name: cfg('user_id') ? ('Nutzer ' + cfg('user_id')) : 'angemeldet' } : undefined
      });
    }
    case 'auth.begin':
      if (!APP_ID || !SECRET || !(CODE_AUTORISATION || (EMAIL && PASSWORD)))
        return Promise.resolve({ url: null, expects_input: false,
          instructions: 'Die Zugangsdaten stehen in der Datei Plugins/qobuz.js (Dateien-App > Radio.fx > Plugins). Fülle dort die Lücken 1 und 2 (APP_ID, SECRET) und 3 (CODE_AUTORISATION) oder 3b (EMAIL, PASSWORD) aus, speichere und starte die App neu.' });
      return Promise.resolve({ url: null, expects_input: true,
        instructions: 'Die Lücken in Plugins/qobuz.js sind ausgefüllt. Hier kannst du alternativ einen neuen Code (oder die ganze Adresse mit code_autorisation=...) einfügen.' });
    case 'auth.complete': return completeAuth(p && p.input);
    case 'auth.sign_out': hostSet('token', ''); hostSet('user_id', ''); hostSet('pending', ''); hostSet('used_code', ''); hostSet('relogin', ''); return Promise.resolve({ ok: true });

    case 'browse.root':
      return Promise.resolve({ sections: [
        folder('fav', 'Favoriten'),
        folder('my/playlists', 'Meine Playlists'),
        folder('discover', 'Entdecken'),
        folder('featured/new-releases', 'Neuheiten'),
        folder('featured/editor-picks', 'Auswahl der Redaktion')
      ] });

    case 'browse.list': return browseList(p.ref || '', p.offset || 0, p.limit || 50);

    case 'library.albums': return favList('albums', p);
    case 'library.artists': return favList('artists', p);
    case 'library.tracks': return favList('tracks', p);
    case 'library.playlists': return playlistsList(p);

    case 'search': {
      var q = String(p.query || '').trim();
      if (!q) return Promise.resolve({ groups: [] });
      return api('catalog/search', { query: q, offset: p.offset || 0, limit: p.limit || 12 }).then(function (j) {
        var groups = [];
        function add(kind, c, fn) { var it = (c && c.items) || []; if (it.length) groups.push({ kind: kind, items: it.map(fn), total: c.total, has_more: (p.offset || 0) + it.length < (c.total || 0) }); }
        add('album', j.albums, albumItem);
        add('track', j.tracks, function (x) { return trackItem(x); });
        add('artist', j.artists, artistItem);
        add('playlist', j.playlists, playlistItem);
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
          if (j && j.sample === true) throw new Error('Nur 30-Sekunden-Vorschau: das Abo erlaubt diesen Titel nicht in voller Länge.');
          if (!j || !j.url) {
            var codes = ((j && j.restrictions) || []).map(function (r) { return r.code || r; });
            if (codes.length && !codes.every(function (c) { return /^Format/.test(c); })) { var e0 = new Error('Nicht verfügbar [' + codes.join(', ') + ']'); e0.final = true; throw e0; }
            throw new Error('Kein Stream für dieses Format.');
          }
          var fmt = j.format_id || order[i];
          STREAMS[m[1]] = { format_id: fmt, blob: j.blob || null };
          return {
            url: j.url, cache: CACHE_TRACKS === true, delivery: 'direct',
            format: { codec: fmt === 5 ? 'mp3' : 'flac', sample_rate: Math.round((j.sampling_rate || 0) * 1000) || undefined, bits: j.bit_depth || undefined }
          };
        }).catch(function (e) {
          if (i + 1 < order.length && !e.final && !/abgelehnt|anmeld/i.test(String(e.message))) return attempt(i + 1);
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