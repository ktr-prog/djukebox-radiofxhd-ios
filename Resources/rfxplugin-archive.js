// Radio.fx source plugin "Live Music Archive" (Internet Archive, mediatype etree: concert recordings that are free to share).
// Speaks the ricercar source-plugin protocol 1 (method names and item fields), running inside the app (JavaScriptCore).
// Host API: fetchText(url, opts) -> Promise({status, text}), hostLog(text), hostGet/hostSet(key[, value]).
// Written from the endpoints and sort orders visible in the original ricercar-archive plugin; not a copy of its code.

function enc(s) { return encodeURIComponent(s); }

function getJSON(url) {
  return fetchText(url, {}).then(function (r) {
    if (r.status === 429 || r.status === 503) throw new Error('archive.org ist gerade überlastet, bitte später erneut versuchen.');
    if (r.status === 404) throw new Error('Auf archive.org nicht gefunden.');
    if (r.status < 200 || r.status >= 300) throw new Error('archive.org antwortete mit HTTP ' + r.status);
    try { return JSON.parse(r.text); }
    catch (e) { throw new Error('archive.org hat etwas anderes als JSON geschickt.'); }
  });
}

function parseLen(l) {
  if (!l) return 0;
  var s = String(l);
  if (s.indexOf(':') >= 0) {
    var p = s.split(':'), t = 0;
    for (var i = 0; i < p.length; i++) t = t * 60 + parseFloat(p[i]);
    return Math.round(t * 1000);
  }
  return Math.round(parseFloat(s) * 1000) || 0;
}

function one(v) { return Array.isArray(v) ? v[0] : v; }

function showItem(d) {
  var sub = [];
  var creator = one(d.creator), venue = one(d.venue), cov = one(d.coverage);
  if (creator) sub.push(creator);
  if (d.date) sub.push(String(one(d.date)).slice(0, 10));
  var where = [venue, cov].filter(Boolean).join(', ');
  if (where) sub.push(where);
  return {
    ref: 'show/' + d.identifier, kind: 'album',
    title: one(d.title) || d.identifier, subtitle: sub.join(' · '),
    artist: creator || '', album: one(d.title) || '', year: parseInt(String(one(d.date) || ''), 10) || undefined,
    art: 'https://archive.org/services/img/' + d.identifier,
    playable: false, browsable: true
  };
}

function artistItem(d) {
  return {
    ref: 'artist/' + d.identifier, kind: 'artist', title: one(d.title) || d.identifier,
    subtitle: d.item_count ? (d.item_count + ' Konzerte') : '',
    art: 'https://archive.org/services/img/' + d.identifier,
    playable: false, browsable: true
  };
}

var FIELDS = ['identifier', 'title', 'creator', 'date', 'venue', 'coverage', 'item_count'];

function advanced(query, sort, offset, limit, mapper) {
  var rows = limit || 40, page = Math.floor((offset || 0) / rows) + 1;
  var url = 'https://archive.org/advancedsearch.php?q=' + enc(query) +
    FIELDS.map(function (f) { return '&fl%5B%5D=' + f; }).join('') +
    '&sort%5B%5D=' + enc(sort) + '&rows=' + rows + '&page=' + page + '&output=json';
  return getJSON(url).then(function (j) {
    var docs = (j.response && j.response.docs) || [];
    var total = j.response ? j.response.numFound : docs.length;
    return { items: docs.map(mapper || showItem), total: total, has_more: page * rows < total };
  });
}

function cleanTerms(q) { return String(q).replace(/["()\[\]{}\\:]/g, ' ').replace(/\s+/g, ' ').trim(); }

function pad2(n) { return (n < 10 ? '0' : '') + n; }

function todayQuery() {
  var d = new Date(), md = pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()), ys = [];
  for (var y = d.getFullYear(); y >= 1950; y--) ys.push(y + '-' + md);
  return 'mediatype:etree AND date:(' + ys.join(' OR ') + ')';
}

function showTracks(id) {
  return getJSON('https://archive.org/metadata/' + enc(id)).then(function (m) {
    var meta = m.metadata || {};
    var files = (m.files || []).filter(function (f) {
      if (f.private === 'true' || f.private === true) return false;
      return /^flac$/i.test(f.format || '') || /\.flac$/i.test(f.name || '');
    }).sort(function (a, b) { return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0); });
    var album = one(meta.title) || id, artist = one(meta.creator) || '';
    var year = parseInt(String(one(meta.date) || ''), 10) || undefined;
    var genre = one(meta.subject) || undefined;
    var items = files.map(function (f, i) {
      var base = String(f.name).replace(/^.*\//, '').replace(/\.flac$/i, '');
      return {
        ref: 'file/' + id + '/' + enc(f.name), kind: 'track',
        title: f.title || base, artist: f.creator || artist, album: album, album_artist: artist,
        track_no: parseInt(f.track, 10) || (i + 1), year: year, genre: genre,
        duration_ms: parseLen(f.length),
        art: 'https://archive.org/services/img/' + id,
        album_ref: 'show/' + id,
        format: { codec: 'flac' }, playable: true, browsable: false
      };
    });
    return { items: items, total: items.length, has_more: false };
  });
}

function handle(method, p) {
  switch (method) {
    case 'initialize':
      return Promise.resolve({
        protocol: 1,
        plugin: { id: 'archive', name: 'Live Music Archive', version: '0.2.0' },
        capabilities: { browse: true, search: true, resolve: true }
      });
    case 'browse.root':
      return Promise.resolve({ sections: [
        { ref: 'popular', kind: 'folder', title: 'Beliebt', browsable: true, playable: false },
        { ref: 'week', kind: 'folder', title: 'Beliebt diese Woche', browsable: true, playable: false },
        { ref: 'recent', kind: 'folder', title: 'Neu hinzugefügt', browsable: true, playable: false },
        { ref: 'today', kind: 'folder', title: 'An diesem Tag', browsable: true, playable: false },
        { ref: 'newest', kind: 'folder', title: 'Neueste Konzerte', browsable: true, playable: false },
        { ref: 'artists', kind: 'folder', title: 'Künstler', browsable: true, playable: false }
      ] });
    case 'browse.list': {
      var r = p.ref, o = p.offset, l = p.limit;
      if (r === 'popular') return advanced('mediatype:etree', 'downloads desc', o, l);
      if (r === 'week') return advanced('mediatype:etree', 'week desc', o, l);
      if (r === 'recent') return advanced('mediatype:etree', 'publicdate desc', o, l);
      if (r === 'newest') return advanced('mediatype:etree', 'date desc', o, l);
      if (r === 'today') return advanced(todayQuery(), 'downloads desc', o, l);
      if (r === 'artists') return advanced('mediatype:collection AND collection:etree', 'downloads desc', o, l, artistItem);
      if (r.indexOf('artist/') === 0) return advanced('mediatype:etree AND collection:' + r.slice(7), 'date desc', o, l);
      if (r.indexOf('show/') === 0) return showTracks(r.slice(5));
      return Promise.reject(new Error('Unbekannter Eintrag.'));
    }
    case 'search': {
      var t = cleanTerms(p.query);
      if (!t) return Promise.resolve({ groups: [] });
      var wantArtists = !p.kinds || p.kinds.indexOf('artist') >= 0;
      var shows = advanced('mediatype:etree AND (title:(' + t + ') OR creator:(' + t + '))', 'downloads desc', p.offset, p.limit);
      var artists = (wantArtists && !p.offset)
        ? advanced('mediatype:collection AND collection:etree AND title:(' + t + ')', 'downloads desc', 0, 8, artistItem)
        : Promise.resolve({ items: [], total: 0, has_more: false });
      return Promise.all([shows, artists]).then(function (res) {
        var groups = [];
        if (res[1].items.length) groups.push({ kind: 'artist', items: res[1].items, total: res[1].total, has_more: res[1].has_more });
        groups.push({ kind: 'album', items: res[0].items, total: res[0].total, has_more: res[0].has_more });
        return { groups: groups };
      });
    }
    case 'item.get': {
      if (p.ref.indexOf('show/') === 0) {
        return getJSON('https://archive.org/metadata/' + enc(p.ref.slice(5))).then(function (m) {
          var me = m.metadata || {};
          return showItem({ identifier: p.ref.slice(5), title: me.title, creator: me.creator, date: me.date, venue: me.venue, coverage: me.coverage });
        });
      }
      return Promise.reject(new Error('Nicht unterstützt.'));
    }
    case 'track.resolve': {
      var m = /^file\/([^\/]+)\/(.+)$/.exec(p.ref);
      if (!m) return Promise.reject(new Error('Ungültige Referenz.'));
      var path = m[2].split('%2F').join('/');
      var url = 'https://archive.org/download/' + enc(m[1]) + '/' + path;
      return fetchText(url, { method: 'HEAD' }).then(function (r) {
        if (r.status === 404 || r.status === 403 || r.status === 410) throw new Error('Diese Datei ist nicht mehr öffentlich.');
        return { url: url, format: { codec: 'flac' }, delivery: 'direct' };
      });
    }
    default:
      return Promise.reject(new Error('method not found'));
  }
}
