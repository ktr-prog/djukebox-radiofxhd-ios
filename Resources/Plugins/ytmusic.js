// Radio.fx source plugin "YouTube Music" - runs completely on the iPad (no server, no account, no keys).
//
// This file ships with the app and is copied to  Dateien > Radio.fx > Plugins  on first start.
// Switch it on under Quellen > Plugins an/aus (restart the app once).
//
// How it works (written from the YouTube Music web API as the open-source projects lms-ytmusic and yt-dlp use it):
//   * Search and lists: the same "InnerTube" calls the YouTube Music web page makes (WEB_REMIX client, search / browse).
//   * Playing: a "player" request as the visionOS client (the client yt-dlp uses when no JavaScript runtime is available). It
//     returns direct audio addresses that need neither a signature solver nor a PO token. The best AAC (m4a) audio stream is
//     downloaded in 5 MB pieces with the same User-Agent the address was issued for. Nothing is transcoded.
// Limits: YouTube Music has no official interface. Google can change or block this at any time, then searching still works but
//   playing reports an error (the message says what YouTube answered). Titles that YouTube only hands out after a signature
//   challenge or with a PO token cannot be played by this plugin. "Made for kids" titles are not available.
//   Use it within the terms of service of YouTube.
// Untested against the live service.

// ---------------------------------------------------------------------------------------------------------------
// LUECKE 1 (optional, normally leave empty) - PROXY_URL: address of a running ytmproxy.py (from lms-ytmusic) on one of your own
//            computers, e.g. 'http://192.168.178.20:9876'. If filled, playing goes through it instead of the built-in way.
var PROXY_URL = '';
// ---------------------------------------------------------------------------------------------------------------

var API_KEY = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-KLET5YdCE';       // public key of the web client (the one lms-ytmusic uses)
var REMIX_VERSION = '1.20260707.12.00';
var WEB_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
var VIS = {
  name: 'VISIONOS', id: '101', version: '1.02',
  ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
  ctx: { clientName: 'VISIONOS', clientVersion: '1.02', deviceMake: 'Apple', deviceModel: 'RealityDevice17,1',
         userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
         osName: 'visionOS', osVersion: '26.5.23O471', hl: 'en', gl: 'US' }
};
var SONGS_PARAMS = 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D';

function enc(s) { return encodeURIComponent(s).replace(/[!'()*]/g, function (c) { return '%' + c.charCodeAt(0).toString(16).toUpperCase(); }); }
function cfg(k) { return hostGet(k) || ''; }
function base() { return String(PROXY_URL || '').replace(/\s+/g, '').replace(/\/+$/, ''); }

// ---- InnerTube -------------------------------------------------------------------------------------------------
function remix(ep, body) {
  hostLog('Anfrage: ' + ep);
  var b = { context: { client: { clientName: 'WEB_REMIX', clientVersion: REMIX_VERSION, hl: 'en', gl: 'US' } } };
  for (var k in body) b[k] = body[k];
  return fetchText('https://music.youtube.com/youtubei/v1/' + ep + '?prettyPrint=false&key=' + API_KEY, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': API_KEY, 'X-YouTube-Client-Name': '67', 'X-YouTube-Client-Version': REMIX_VERSION,
               'User-Agent': WEB_UA, 'Origin': 'https://music.youtube.com', 'Referer': 'https://music.youtube.com/', 'Accept-Language': 'en-US,en;q=0.9' },
    body: JSON.stringify(b)
  }).then(function (r) {
    if (r.status < 200 || r.status >= 300) throw new Error('YouTube Music antwortete mit HTTP ' + r.status + '.');
    try { return JSON.parse(r.text); } catch (e) { throw new Error('YouTube Music hat etwas anderes als JSON geschickt.'); }
  });
}

function visitorData() {
  var v = cfg('visitor');
  if (v) return Promise.resolve(v);
  return fetchText('https://www.youtube.com/', { headers: { 'User-Agent': WEB_UA, 'Accept-Language': 'en-US,en;q=0.9' } }).then(function (r) {
    var m = /"visitorData":"([^"]+)"/.exec(r.text || '');
    if (m) { hostSet('visitor', m[1]); return m[1]; }
    return '';
  }, function () { return ''; });
}

function playerCall(vid, visitor) {
  var ctx = {}; for (var k in VIS.ctx) ctx[k] = VIS.ctx[k];
  if (visitor) ctx.visitorData = visitor;
  var headers = { 'Content-Type': 'application/json', 'X-YouTube-Client-Name': VIS.id, 'X-YouTube-Client-Version': VIS.version,
                  'Origin': 'https://www.youtube.com', 'User-Agent': VIS.ua };
  if (visitor) headers['X-Goog-Visitor-Id'] = visitor;
  return fetchText('https://www.youtube.com/youtubei/v1/player?prettyPrint=false', {
    method: 'POST', headers: headers,
    body: JSON.stringify({ context: { client: ctx }, videoId: vid, contentCheckOk: true, racyCheckOk: true,
                           playbackContext: { contentPlaybackContext: { html5Preference: 'HTML5_PREF_WANTS' } } })
  }).then(function (r) {
    if (r.status < 200 || r.status >= 300) throw new Error('YouTube antwortete mit HTTP ' + r.status + '.');
    try { return JSON.parse(r.text); } catch (e) { throw new Error('YouTube hat etwas anderes als JSON geschickt.'); }
  });
}

// best audio stream with a direct address: AAC in an mp4 container (itag 140 / 141 ...), highest bit rate
function pickAudio(pr) {
  var sd = (pr && pr.streamingData) || {};
  var list = (sd.adaptiveFormats || []).filter(function (f) { return f.url && /^audio\/mp4/.test(f.mimeType || ''); });
  list.sort(function (a, b) { return (b.bitrate || 0) - (a.bitrate || 0); });
  if (list.length) return { f: list[0], note: '' };
  var mixed = (sd.formats || []).filter(function (f) { return f.url && /^video\/mp4/.test(f.mimeType || '') && f.audioQuality; });   // itag 18: small video with sound
  if (mixed.length) return { f: mixed[0], note: 'mixed' };
  return null;
}
function whyNot(pr) {
  var ps = (pr && pr.playabilityStatus) || {};
  var msg = ps.reason || (ps.messages && ps.messages[0]) || ps.status || 'keine Antwort';
  var sd = (pr && pr.streamingData) || {};
  var all = (sd.adaptiveFormats || []).concat(sd.formats || []);
  if (!ps.status || ps.status === 'OK') {
    if (!all.length) return 'YouTube hat keine Streams geschickt (vermutlich PO-Token nötig).';
    if (all.some(function (f) { return f.signatureCipher || f.cipher; })) return 'YouTube verlangt für diesen Titel eine Signatur-Lösung (vom Plugin nicht unterstützt).';
    return 'Kein passender Audio-Stream mit direkter Adresse.';
  }
  return 'YouTube: ' + ps.status + ' - ' + msg;
}

function resolveSong(vid) {
  return visitorData().then(function (vis) {
    return playerCall(vid, vis).then(function (pr) {
      var pk = pickAudio(pr);
      if (pk) return pk;
      // a second try without visitor data, then the reason
      if (vis) return playerCall(vid, '').then(function (p2) { var pk2 = pickAudio(p2); if (pk2) return pk2; throw new Error(whyNot(p2)); });
      throw new Error(whyNot(pr));
    });
  }).then(function (pk) {
    var f = pk.f;
    var size = parseInt(f.contentLength, 10) || 0;
    var res = { url: f.url, cache: false, delivery: 'direct', format: { codec: 'm4a', sample_rate: parseInt(f.audioSampleRate, 10) || undefined },
                headers: { 'User-Agent': VIS.ua } };
    if (size > 0) { res.size = size; res.chunked = true; }
    var dur = parseInt(f.approxDurationMs, 10);
    if (dur > 0) res.duration_ms = dur;
    return res;
  });
}

// ---- parsing (ported from ytmproxy.py of lms-ytmusic) ----------------------------------------------------------------
function runs(o) { var r = o && o.runs; if (r && r.length) return r.map(function (x) { return x.text || ''; }).join(''); return (o && o.simpleText) || ''; }
function g(o, path) { for (var i = 0; i < path.length; i++) { if (o == null) return undefined; o = o[path[i]]; } return o; }
function colRuns(r, i) { return g(r, ['flexColumns', i, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs']) || []; }
function col(r, i, k) { var rr = colRuns(r, i); return (rr[k || 0] && rr[k || 0].text) || ''; }
function fixedCol(r) { var rr = g(r, ['fixedColumns', 0, 'musicResponsiveListItemFixedColumnRenderer', 'text', 'runs']) || []; return (rr[0] && rr[0].text) || ''; }
function secs(d) {
  var p = String(d || '').trim().split(':'); if (!/^\d+(:\d+){1,2}$/.test(String(d || '').trim())) return 0;
  if (p.length === 2) return (+p[0]) * 60 + (+p[1]);
  if (p.length === 3) return (+p[0]) * 3600 + (+p[1]) * 60 + (+p[2]);
  return 0;
}
function bigThumb(list) {
  var u = (list && list.length) ? (list[list.length - 1].url || '') : '';
  return u.replace(/=w\d+-h\d+[^&?]*$/, '=w544-h544-l90-rj').replace(/=s\d+[^&?]*$/, '=s544');
}
function thumbOf(r) { return bigThumb(g(r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'])); }
function pageType(r) { return g(r, ['navigationEndpoint', 'browseEndpoint', 'browseEndpointContextSupportedConfigs', 'browseEndpointContextMusicConfig', 'pageType']) || ''; }
function videoIdOf(r) { return g(r, ['overlay', 'musicItemThumbnailOverlayRenderer', 'content', 'musicPlayButtonRenderer', 'playNavigationEndpoint', 'watchEndpoint', 'videoId']) || ''; }
function browseIdOf(r) { return g(r, ['navigationEndpoint', 'browseEndpoint', 'browseId']) || ''; }

function parseListItem(r, hdr) {
  var pt = pageType(r), vid = videoIdOf(r);
  if (pt === 'MUSIC_PAGE_TYPE_ALBUM') return { type: 'album', title: col(r, 0), artist: col(r, 1), year: col(r, 2), browseId: browseIdOf(r), thumbnail: thumbOf(r) };
  if (pt === 'MUSIC_PAGE_TYPE_ARTIST') return { type: 'artist', name: col(r, 0), browseId: browseIdOf(r), thumbnail: thumbOf(r) };
  if (/PLAYLIST|PODCAST/.test(pt)) return { type: 'playlist', title: col(r, 0), count: col(r, 1), browseId: browseIdOf(r), thumbnail: thumbOf(r) };
  if (vid || pt === 'MUSIC_PAGE_TYPE_TRACK') {
    var c1 = colRuns(r, 1), artist = col(r, 1), album = col(r, 2);
    if (!album && c1.length >= 5) album = (c1[2] && c1[2].text) || '';         // search: "Artist • Album • 3:45" in one column
    var dur = secs(fixedCol(r) || col(r, 3) || col(r, 4));
    if (!dur) for (var i = c1.length - 1; i >= 0 && !dur; i--) dur = secs(c1[i].text);
    var it = { type: 'song', title: col(r, 0), artist: artist, album: album, duration: dur, videoId: vid, thumbnail: thumbOf(r) };
    if (hdr) { if (!it.thumbnail) it.thumbnail = hdr.thumbnail; if (!it.artist || it.artist === it.title) it.artist = hdr.artist; if (!it.album) it.album = hdr.title; }
    return it;
  }
  return null;
}
function parseTwoRow(r) {
  var title = runs(r.title), sub = runs(r.subtitle), bid = g(r, ['navigationEndpoint', 'browseEndpoint', 'browseId']) || '';
  var th = bigThumb(g(r, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']));
  var vid = g(r, ['navigationEndpoint', 'watchEndpoint', 'videoId']);
  if (vid) return { type: 'song', title: title, artist: sub, videoId: vid, thumbnail: th, duration: 0, album: '' };
  if (/^MPRE/.test(bid)) return { type: 'album', title: title, artist: sub, browseId: bid, thumbnail: th };
  if (/^UC/.test(bid)) return { type: 'artist', name: title, browseId: bid, thumbnail: th };
  if (bid) return { type: 'playlist', title: title, count: sub, browseId: bid, thumbnail: th };
  return null;
}
function shelfItems(contents, hdr) {
  var out = [];
  (contents || []).forEach(function (e) {
    var it = null;
    if (e.musicResponsiveListItemRenderer) it = parseListItem(e.musicResponsiveListItemRenderer, hdr);
    else if (e.musicTwoRowItemRenderer) it = parseTwoRow(e.musicTwoRowItemRenderer);
    if (it) out.push(it);
  });
  return out;
}
function sectionsItems(sections, hdr) {
  var out = [];
  (sections || []).forEach(function (s) {
    ['musicShelfRenderer', 'musicPlaylistShelfRenderer', 'musicCarouselShelfRenderer', 'gridRenderer'].forEach(function (k) {
      var t = s[k]; if (!t) return;
      out = out.concat(shelfItems(t.contents || t.items, hdr));
    });
    var card = s.musicCardShelfRenderer;                       // top result card of a search
    if (card) {
      var th = bigThumb(g(card, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']));
      var vid = g(card, ['onTap', 'watchEndpoint', 'videoId']);
      if (vid) out.push({ type: 'song', title: runs(card.title), artist: '', videoId: vid, thumbnail: th, duration: 0, album: '' });
      out = out.concat(shelfItems(card.contents, hdr));
    }
    var its = s.itemSectionRenderer;
    if (its) out = out.concat(shelfItems(its.contents, hdr));
  });
  return out;
}
function find(o, key, depth) {
  if (!o || typeof o !== 'object' || (depth || 0) > 12) return null;
  if (o[key]) return o[key];
  for (var k in o) { var r = find(o[k], key, (depth || 0) + 1); if (r) return r; }
  return null;
}
function headerOf(data) {
  var h = find(data, 'musicResponsiveHeaderRenderer') || find(data, 'musicDetailHeaderRenderer') || find(data, 'musicImmersiveHeaderRenderer');
  if (!h) return null;
  var th = find(h, 'thumbnails');
  return { title: runs(h.title), artist: runs(h.straplineTextOne) || '', thumbnail: bigThumb(th) };
}

// ---- items for the app -----------------------------------------------------------------------------------------------
function folder(ref, title) { return { ref: ref, kind: 'folder', title: title, playable: false, browsable: true }; }
function songItem(r) {
  return { ref: 'song/' + r.videoId, kind: 'track', title: r.title || '', subtitle: r.artist || '', artist: r.artist || '', album: r.album || '',
           duration_ms: (r.duration || 0) * 1000, art: r.thumbnail || undefined, playable: true, browsable: false };
}
function itemOf(r) {
  if (!r) return null;
  if (r.type === 'song' && r.videoId) return songItem(r);
  if (r.type === 'album' && r.browseId) return { ref: 'album/' + r.browseId, kind: 'album', title: r.title || '', subtitle: r.artist || r.year || '', artist: r.artist || '', art: r.thumbnail || undefined, playable: false, browsable: true };
  if (r.type === 'playlist' && r.browseId) return { ref: 'playlist/' + r.browseId, kind: 'playlist', title: r.title || '', subtitle: r.count || '', art: r.thumbnail || undefined, playable: false, browsable: true };
  if (r.type === 'artist' && r.browseId) return { ref: 'artist/' + r.browseId, kind: 'artist', title: r.name || '', art: r.thumbnail || undefined, playable: false, browsable: true };
  return null;
}
function itemsOf(list) { var o = []; (list || []).forEach(function (r) { var i = itemOf(r); if (i) o.push(i); }); return o; }
function paged(items, off, lim) { var s = items.slice(off, off + lim); return { items: s, total: items.length, has_more: off + s.length < items.length }; }

function singleCol(data) { return g(data, ['contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents']) || []; }
function twoColSecondary(data) { return g(data, ['contents', 'twoColumnBrowseResultsRenderer', 'secondaryContents', 'sectionListRenderer', 'contents']) || []; }

function browseList(ref, off, lim) {
  function listOf(data, hdr) {
    var secs2 = twoColSecondary(data); if (!secs2.length) secs2 = singleCol(data);
    return paged(itemsOf(sectionsItems(secs2, hdr)), off, lim);
  }
  if (ref === 'charts') return remix('browse', { browseId: 'FEmusic_charts' }).then(function (d) { return listOf(d); });
  if (ref === 'new') return remix('browse', { browseId: 'FEmusic_new_releases' }).then(function (d) { return listOf(d); });
  if (ref === 'home') return remix('browse', { browseId: 'FEmusic_home' }).then(function (d) { return listOf(d); });
  var m = /^(album|playlist|artist)\/(.+)$/.exec(ref);
  if (m) {
    var bid = m[2];
    if (m[1] === 'playlist' && !/^VL/.test(bid) && !/^(MPRE|OLAK)/.test(bid)) bid = 'VL' + bid;
    return remix('browse', { browseId: bid }).then(function (d) {
      var hdr = headerOf(d);
      if (m[1] === 'artist') return listOf(d, hdr);
      return listOf(d, hdr);
    });
  }
  return Promise.reject(new Error('Unbekannte Liste: ' + ref));
}

// ---- protocol --------------------------------------------------------------------------------------------------------
function handle(method, p) {
  switch (method) {
    case 'initialize':
      return Promise.resolve({
        protocol: 1,
        plugin: { id: 'ytmusic', name: 'YouTube Music', version: '0.2.0', icon_url: 'https://music.youtube.com/favicon.ico' },
        capabilities: { browse: true, search: true, resolve: true }
      });

    case 'browse.root':
      return Promise.resolve({ sections: [ folder('charts', 'Charts'), folder('new', 'Neuheiten'), folder('home', 'Startseite') ] });
    case 'browse.list': return browseList(p.ref || '', p.offset || 0, p.limit || 50);

    case 'search': {
      var q = String(p.query || '').trim();
      if (!q) return Promise.resolve({ groups: [] });
      return remix('search', { query: q, params: SONGS_PARAMS }).then(function (d) {
        var tabs = g(d, ['contents', 'tabbedSearchResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents'])
                || g(d, ['contents', 'sectionListRenderer', 'contents']) || [];
        var items = itemsOf(sectionsItems(tabs)).filter(function (x) { return x.kind === 'track'; });
        if (!items.length) { hostLog('search leer'); return { groups: [] }; }      // the app shows "Keine Ergebnisse" in this section
        var off = p.offset || 0, lim = p.limit || 20;
        return { groups: [{ kind: 'track', items: items.slice(off, off + lim), total: items.length, has_more: off + lim < items.length }] };
      });
    }

    case 'track.resolve': {
      var m = /^song\/([\w-]{6,20})$/.exec(p.ref || '');
      if (!m) return Promise.reject(new Error('Ungültige Referenz.'));
      if (base()) return Promise.resolve({ url: base() + '/stream/' + m[1], cache: false, delivery: 'direct', format: { codec: 'mp3' } });
      return resolveSong(m[1]);
    }

    case 'playback.started': case 'playback.ended': return Promise.resolve({ ok: true });

    default:
      return Promise.reject(new Error('method not found'));
  }
}
