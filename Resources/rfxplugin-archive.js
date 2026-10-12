// Radio.fx source plugin "Live Music Archive" (Internet Archive, collection etree: concert recordings that are free to share).
// Speaks the ricercar source-plugin protocol 1 (method names and item fields), running inside the app (JavaScriptCore).
// Host API: fetchText(url, opts) -> Promise({status, text}), hostLog(text).

function enc(s) { return encodeURIComponent(s); }

function getJSON(url) {
  return fetchText(url, {}).then(function (r) {
    if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status);
    return JSON.parse(r.text);
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

function showItem(d) {
  var sub = [];
  if (d.creator) sub.push(d.creator);
  if (d.date) sub.push(String(d.date).slice(0, 10));
  return {
    ref: 'show/' + d.identifier, kind: 'album',
    title: d.title || d.identifier, subtitle: sub.join(' · '),
    artist: d.creator || '', album: d.title || '',
    art: 'https://archive.org/services/img/' + d.identifier,
    playable: false, browsable: true
  };
}

function listShows(query, sort, offset, limit) {
  var rows = limit || 40, page = Math.floor((offset || 0) / rows) + 1;
  var url = 'https://archive.org/advancedsearch.php?q=' + enc(query) +
    '&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=creator&fl%5B%5D=date' +
    '&sort%5B%5D=' + enc(sort) + '&rows=' + rows + '&page=' + page + '&output=json';
  return getJSON(url).then(function (j) {
    var docs = (j.response && j.response.docs) || [];
    return { items: docs.map(showItem), total: j.response ? j.response.numFound : docs.length,
             has_more: j.response ? (page * rows < j.response.numFound) : false };
  });
}

function cleanTerms(q) { return String(q).replace(/["()\[\]{}\\:]/g, ' ').replace(/\s+/g, ' ').trim(); }

function showTracks(id) {
  return getJSON('https://archive.org/metadata/' + enc(id)).then(function (m) {
    var meta = m.metadata || {};
    var files = (m.files || []).filter(function (f) {
      return /^flac$/i.test(f.format || '') || /\.flac$/i.test(f.name || '');
    }).sort(function (a, b) { return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0); });
    var items = files.map(function (f, i) {
      var base = String(f.name).replace(/^.*\//, '').replace(/\.flac$/i, '');
      return {
        ref: 'file/' + id + '/' + enc(f.name), kind: 'track',
        title: f.title || base, artist: f.creator || meta.creator || '', album: meta.title || id,
        track_no: parseInt(f.track, 10) || (i + 1), duration_ms: parseLen(f.length),
        art: 'https://archive.org/services/img/' + id,
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
        plugin: { id: 'archive', name: 'Live Music Archive', version: '0.1.0' },
        capabilities: { browse: true, search: true, resolve: true }
      });
    case 'browse.root':
      return Promise.resolve({ sections: [
        { ref: 'popular', kind: 'folder', title: 'Beliebt', browsable: true, playable: false },
        { ref: 'recent', kind: 'folder', title: 'Neu hinzugefügt', browsable: true, playable: false }
      ] });
    case 'browse.list':
      if (p.ref === 'popular') return listShows('collection:etree', 'downloads desc', p.offset, p.limit);
      if (p.ref === 'recent') return listShows('collection:etree', 'addeddate desc', p.offset, p.limit);
      if (p.ref.indexOf('show/') === 0) return showTracks(p.ref.slice(5));
      return Promise.reject(new Error('unknown ref'));
    case 'search': {
      var t = cleanTerms(p.query);
      if (!t) return Promise.resolve({ groups: [] });
      var q = 'collection:etree AND (title:(' + t + ') OR creator:(' + t + '))';
      return listShows(q, 'downloads desc', p.offset, p.limit).then(function (r) {
        return { groups: [{ kind: 'album', items: r.items, total: r.total, has_more: r.has_more }] };
      });
    }
    case 'track.resolve': {
      var m = /^file\/([^\/]+)\/(.+)$/.exec(p.ref);
      if (!m) return Promise.reject(new Error('bad ref'));
      return Promise.resolve({
        url: 'https://archive.org/download/' + enc(m[1]) + '/' + m[2].split('%2F').join('/'),
        format: { codec: 'flac' }, delivery: 'direct'
      });
    }
    default:
      return Promise.reject(new Error('method not found'));
  }
}
