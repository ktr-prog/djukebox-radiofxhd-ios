// KioskView : UIView -- decompiled from Radiofx_iPad (armv7), ported to arm64 / modern iOS.
// Manual reference counting (CLANG_ENABLE_OBJC_ARC=NO).  Feature groups that depend on the dead backend or on
// removed third-party code (Spotify, remote control, EPG, printing, third-party animation, jingles, ambience,
// facebook, copy thread, ...) are not part of this file; see DEVIATIONS.md.
#import <ImageIO/ImageIO.h>
#import "KioskView.h"
#import "TestLibrary.h"
#import "MusicImporter.h"
#import "GLView.h"
#import <AVFoundation/AVFoundation.h>
#import "KeyboardView.h"
#import "MultichannelMixerController.h"
#import "RadioAppDelegate.h"
#import "ServerComm.h"
#import "ServerEntry.h"
#import "DBOperations.h"
#import "FolderObject.h"
#import "ClipObject.h"
#import "CGPointObject.h"
#import "Globals.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <unistd.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <CommonCrypto/CommonDigest.h>

// Fast switching / queue dragging can touch the queue while it is changing; an out-of-range index must not
// take the whole app down.  These behave like the NSMutableArray methods but ignore a bad index.
@interface NSObject (RfxGrave)
+ (void)rfx_graveRelease:(id)o;
@end
@implementation NSObject (RfxGrave)
+ (void)rfx_graveRelease:(id)o { [self performSelector:@selector(rfx_graveRelease2:) withObject:o afterDelay:10.0]; }
+ (void)rfx_graveRelease2:(id)o { [o release]; }
@end

@interface NSMutableArray (RfxSafeQueue)
- (id)rfx_objectAtIndex:(NSUInteger)i;
- (void)rfx_removeObjectAtIndex:(NSUInteger)i;
- (void)rfx_insertObject:(id)o atIndex:(NSUInteger)i;
@end
@implementation NSMutableArray (RfxSafeQueue)
- (id)rfx_objectAtIndex:(NSUInteger)i { return (i < [self count]) ? [self objectAtIndex:i] : nil; }
- (void)rfx_removeObjectAtIndex:(NSUInteger)i {
    if (i >= [self count]) return;
    // Several ivars (m_cliptorotate, pending performSelectors, animations) point at clips without retaining them.
    // Keep a removed clip alive for a while so none of them can touch freed memory.
    id o = [[self objectAtIndex:i] retain];
    [self removeObjectAtIndex:i];
    [NSObject performSelectorOnMainThread:@selector(rfx_graveRelease:) withObject:o waitUntilDone:NO];
}
- (void)rfx_insertObject:(id)o atIndex:(NSUInteger)i { if (o == nil) return; if (i > [self count]) i = [self count]; [self insertObject:o atIndex:i]; }
@end


#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])
#define ISIPAD ([DEL m_isipad])
#define THUMB (ISIPAD ? 0x52 : 0x38)
#define BARH (ISIPAD ? 0x7e : 0x5a)


#pragma mark - Quellen (source plugins, ricercar protocol 1 via a bridge)

// Speaks the ricercar source-plugin protocol (JSON-RPC 2.0, protocol 1) to a plugin that runs on a computer in the
// user's network behind Tools/rfx-plugin-bridge.py.  The host is neutral: it knows no service, ships no plugin and
// holds no credentials; sign-in goes through the plugin's auth.begin / auth.complete (the user opens the address in
// the browser and pastes back what the plugin asks for).

#pragma mark - plugin cache (files that plugins resolved are loaded here and played through the audio engine)

static unsigned long long RfxHash64(NSString *s, NSString **hex) {
    unsigned char d[CC_SHA256_DIGEST_LENGTH];
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256([data bytes], (CC_LONG)[data length], d);
    unsigned long long v = 0;
    NSMutableString *h = [NSMutableString string];
    for (int i = 0; i < 16; i++) { [h appendFormat:@"%02x", d[i]]; if (i < 8) v = (v << 8) | d[i]; }
    if (hex != NULL) *hex = h;
    return v;
}

static long long RfxItemID(NSString *plugin, NSString *ref) {
    NSString *hex = nil;
    unsigned long long h64 = RfxHash64([NSString stringWithFormat:@"%@|%@", plugin, ref], &hex);
    return -(long long)(h64 & 0x3fffffffffULL) - 100000;
}

// A source plugin written in JavaScript, running inside the app (JavaScriptCore).  The script defines
// handle(method, params) -> Promise and speaks the ricercar plugin protocol 1 method names.  It gets fetchText(url, opts),
// hostLog(text), hostOpen(url) and hostGet/hostSet(key[, value]) (small per-plugin storage).
@interface RfxJSPlugin : NSObject {
    JSContext *m_ctx;
    int m_nextid;
    NSMutableDictionary *m_pending;
    NSString *m_pid;
}
- (id)initWithScript:(NSString *)src pluginId:(NSString *)pid error:(NSString **)err;
- (void)call:(NSString *)method params:(NSDictionary *)params done:(void (^)(id result, NSString *err))done;
@end

// Values file: Documents/Plugins/<plugin>.txt  (same name as the .js).  Lines "NAME = value" (# or // = comment).  They are appended to the
// script as  var NAME = ...;  so they override the empty gaps in the .js; true/false/numbers stay unquoted, everything else becomes a string.
static NSString *RfxPluginValues(NSString *pid) {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *path = [[[docs stringByAppendingPathComponent:@"Plugins"] stringByAppendingPathComponent:pid] stringByAppendingPathExtension:@"txt"];
    NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (txt == nil) return @"";
    NSMutableString *out = [NSMutableString stringWithString:@"\n"];
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSString *raw in [txt componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:ws];
        if ([line length] == 0 || [line hasPrefix:@"#"] || [line hasPrefix:@"//"]) continue;
        NSRange r = [line rangeOfString:@"="];
        if (r.location == NSNotFound || r.location == 0) continue;
        NSString *key = [[line substringToIndex:r.location] stringByTrimmingCharactersInSet:ws];
        NSString *val = [[line substringFromIndex:r.location + 1] stringByTrimmingCharactersInSet:ws];
        if ([val length] >= 2 && (([val hasPrefix:@"'"] && [val hasSuffix:@"'"]) || ([val hasPrefix:@"\""] && [val hasSuffix:@"\""])))
            val = [val substringWithRange:NSMakeRange(1, [val length] - 2)];
        if ([val length] == 0) continue;                                       // empty = leave the gap as it is
        NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"] invertedSet];
        if ([key rangeOfCharacterFromSet:bad].location != NSNotFound) continue;
        BOOL raw2 = [val isEqualToString:@"true"] || [val isEqualToString:@"false"] ||
                    ([val length] < 10 && [val rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound);
        if (raw2) [out appendFormat:@"var %@ = %@;\n", key, val];
        else {
            NSString *e = [val stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
            e = [e stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
            [out appendFormat:@"var %@ = '%@';\n", key, e];
        }
    }
    return out;
}

@implementation RfxJSPlugin

- (id)initWithScript:(NSString *)src pluginId:(NSString *)pid error:(NSString **)err {
    self = [super init];
    if (!self) return nil;
    m_nextid = 1;
    m_pending = [[NSMutableDictionary alloc] init];
    m_pid = [pid retain];
    m_ctx = [[JSContext alloc] init];
    __block NSString *firstError = nil;
    RfxJSPlugin *me = self;
    [m_ctx setExceptionHandler:^(JSContext *c, JSValue *ex) { if (firstError == nil) firstError = [[ex toString] retain]; }];
    m_ctx[@"__native_log"] = ^(NSString *t) {
        NSLog(@"[plugin %@] %@", pid, t);
        // also into  Dateien > Radio.fx > Plugins > <plugin>-log.txt  (the on-screen message is too short for long errors)
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *lp = [[[docs stringByAppendingPathComponent:@"Plugins"] stringByAppendingPathComponent:pid] stringByAppendingString:@"-log.txt"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *at = [fm attributesOfItemAtPath:lp error:nil];
        if (at != nil && [[at objectForKey:NSFileSize] unsignedLongLongValue] > 200000) [fm removeItemAtPath:lp error:nil];
        if (![fm fileExistsAtPath:lp]) [fm createFileAtPath:lp contents:nil attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:lp];
        if (fh != nil) {
            NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
            [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            [fh seekToEndOfFile];
            [fh writeData:[[NSString stringWithFormat:@"%@  %@\n", [df stringFromDate:[NSDate date]], t] dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    };
    m_ctx[@"__native_open"] = ^(NSString *u) {
        NSURL *url = [NSURL URLWithString:u];
        if (url != nil) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    };
    m_ctx[@"__native_get"] = ^NSString *(NSString *k) {
        return [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithFormat:@"RfxPlugin.%@.%@", pid, k]];
    };
    m_ctx[@"__native_set"] = ^(NSString *k, NSString *v) {
        NSString *key = [NSString stringWithFormat:@"RfxPlugin.%@.%@", pid, k];
        if (v == nil || [v length] == 0) [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
        else [[NSUserDefaults standardUserDefaults] setObject:v forKey:key];
    };
    m_ctx[@"__native_fetch"] = ^(int fid, NSString *url, NSString *optsJson) {
        NSDictionary *o = nil;
        if (optsJson != nil) {
            id j = [NSJSONSerialization JSONObjectWithData:[optsJson dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if ([j isKindOfClass:[NSDictionary class]]) o = j;
        }
        NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
        NSString *meth = [o objectForKey:@"method"];
        if (meth != nil) [r setHTTPMethod:meth];
        NSDictionary *hd = [o objectForKey:@"headers"];
        for (NSString *k in hd) [r setValue:[NSString stringWithFormat:@"%@", [hd objectForKey:k]] forHTTPHeaderField:k];
        NSString *body = [o objectForKey:@"body"];
        if (body != nil) [r setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
        [r setTimeoutInterval:30.0];
        [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *e) {
            NSString *text = (data != nil) ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
            NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                JSValue *fn = me->m_ctx[@"__fetchDone"];
                if (e != nil) [fn callWithArguments:@[@(fid), @NO, [e localizedDescription], @0]];
                else [fn callWithArguments:@[@(fid), @YES, (text != nil ? text : @""), @(code)]];
            });
        }] resume];
    };
    m_ctx[@"__native_timer"] = ^(int tid, double ms) {
        [me retain];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ms * 1000000.0)), dispatch_get_main_queue(), ^{
            [me->m_ctx[@"__timerFire"] callWithArguments:@[@(tid)]];
            [me release];
        });
    };
    m_ctx[@"__native_reply"] = ^(int cid, BOOL ok, NSString *payload) {
        NSNumber *key = [NSNumber numberWithInt:cid];
        void (^d)(id, NSString *) = [[me->m_pending objectForKey:key] retain];
        [me->m_pending removeObjectForKey:key];
        if (d == nil) return;
        if (ok) {
            id r = nil;
            if (payload != nil && [payload length] > 0)
                r = [NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:nil];
            d((r == [NSNull null] ? nil : r), nil);
        } else {
            d(nil, payload != nil ? payload : @"Fehler im Plugin");
        }
        [d release];
    };
    NSString *shim =
    @"var __global = this;\n"
    "var global = this, self = this, window = this;\n"
    "if (typeof globalThis === 'undefined') { var globalThis = this; }\n"
    "var module = { exports: {} };\n"
    "var exports = module.exports;\n"
    "var __cbs = {}; var __n = 0;\n"
    "function fetchText(url, opts) { return new Promise(function (res, rej) { var id = ++__n; __cbs[id] = [res, rej];\n"
    "  __native_fetch(id, url, JSON.stringify(opts || {})); }); }\n"
    "function __fetchDone(id, ok, body, status) { var c = __cbs[id]; delete __cbs[id]; if (!c) return;\n"
    "  if (ok) c[0]({ status: status, text: body }); else c[1](new Error(body)); }\n"
    "function hostLog(t) { __native_log(String(t)); }\n"
    "function hostOpen(u) { __native_open(String(u)); }\n"
    "function hostGet(k) { return __native_get(String(k)); }\n"
    "function hostSet(k, v) { __native_set(String(k), v == null ? '' : String(v)); }\n"
    "function __fmt(a) { var o = [], i, v; for (i = 0; i < a.length; i++) { v = a[i];\n"
    "  try { o.push(typeof v === 'string' ? v : JSON.stringify(v)); } catch (e) { o.push(String(v)); } } return o.join(' '); }\n"
    "var console = { log: function () { hostLog(__fmt(arguments)); }, info: function () { hostLog(__fmt(arguments)); },\n"
    "  warn: function () { hostLog(__fmt(arguments)); }, error: function () { hostLog(__fmt(arguments)); }, debug: function () {} };\n"
    "var __timers = {}, __tn = 0;\n"
    "function setTimeout(fn, ms) { var id = ++__tn; __timers[id] = { fn: fn, every: 0 }; __native_timer(id, +ms || 0); return id; }\n"
    "function setInterval(fn, ms) { var id = ++__tn; __timers[id] = { fn: fn, every: +ms || 1 }; __native_timer(id, +ms || 1); return id; }\n"
    "function clearTimeout(id) { delete __timers[id]; }\n"
    "var clearInterval = clearTimeout;\n"
    "function __timerFire(id) { var t = __timers[id]; if (!t) return; if (t.every) __native_timer(id, t.every); else delete __timers[id];\n"
    "  try { t.fn(); } catch (e) { hostLog('timer: ' + e); } }\n"
    "function fetch(url, o) { o = o || {};\n"
    "  return fetchText(String(url), { method: o.method, headers: o.headers, body: o.body == null ? undefined : (typeof o.body === 'string' ? o.body : String(o.body)) }).then(function (r) {\n"
    "    return { ok: r.status >= 200 && r.status < 300, status: r.status, url: String(url),\n"
    "      text: function () { return Promise.resolve(r.text); }, json: function () { return Promise.resolve(JSON.parse(r.text)); } }; }); }\n"
    "var __b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';\n"
    "function btoa(s) { s = String(s); var o = '', i = 0, a, b, c;\n"
    "  while (i < s.length) { a = s.charCodeAt(i++) & 255; b = i < s.length ? s.charCodeAt(i++) & 255 : -1; c = i < s.length ? s.charCodeAt(i++) & 255 : -1;\n"
    "    o += __b64.charAt(a >> 2) + __b64.charAt(((a & 3) << 4) | (b < 0 ? 0 : b >> 4)) + (b < 0 ? '=' : __b64.charAt(((b & 15) << 2) | (c < 0 ? 0 : c >> 6))) + (c < 0 ? '=' : __b64.charAt(c & 63)); }\n"
    "  return o; }\n"
    "function atob(s) { s = String(s).replace(/[^A-Za-z0-9+\\/]/g, ''); var o = '', b = 0, n = 0, i;\n"
    "  for (i = 0; i < s.length; i++) { b = ((b << 6) | __b64.indexOf(s.charAt(i))) & 65535; n += 6; if (n >= 8) { n -= 8; o += String.fromCharCode((b >> n) & 255); } }\n"
    "  return o; }\n"
    "function URLSearchParams(init) { var me = this, k; this.l = [];\n"
    "  if (typeof init === 'string') init.replace(/^\\?/, '').split('&').forEach(function (p) { if (!p) return; var kv = p.split('=');\n"
    "    me.l.push([decodeURIComponent(kv[0]), decodeURIComponent((kv[1] || '').replace(/\\+/g, ' '))]); });\n"
    "  else if (init) for (k in init) this.l.push([k, String(init[k])]); }\n"
    "URLSearchParams.prototype.append = function (k, v) { this.l.push([k, String(v)]); };\n"
    "URLSearchParams.prototype.set = function (k, v) { this.l = this.l.filter(function (e) { return e[0] !== k; }); this.l.push([k, String(v)]); };\n"
    "URLSearchParams.prototype.get = function (k) { for (var i = 0; i < this.l.length; i++) if (this.l[i][0] === k) return this.l[i][1]; return null; };\n"
    "URLSearchParams.prototype.has = function (k) { return this.get(k) !== null; };\n"
    "URLSearchParams.prototype.toString = function () { return this.l.map(function (e) { return encodeURIComponent(e[0]) + '=' + encodeURIComponent(e[1]); }).join('&'); };\n"
    "var __rpcId = 0, __rpcPending = {};\n"
    "function __rpcIn(line) { var m; try { m = typeof line === 'string' ? JSON.parse(line) : line; } catch (e) { return; }\n"
    "  if (m && m.id != null && __rpcPending[m.id]) { var p = __rpcPending[m.id]; delete __rpcPending[m.id]; if (m.error) p[1](m.error); else p[0](m.result); } }\n"
    "var writeLine = function (l) { __rpcIn(l); };\n"
    "var send = writeLine, emit = writeLine, print = writeLine;\n"
    "var process = { stdout: { write: function (l) { String(l).split('\\n').forEach(function (x) { if (x) __rpcIn(x); }); return true; } },\n"
    "  argv: [], env: {}, platform: 'ios', on: function () {} };\n"
    "var stdout = process.stdout;\n"
    "function __adapt() {\n"
    "  if (typeof handle === 'function') return;\n"
    "  var m = module.exports, f = null, o = null, i, c, names, nm;\n"
    "  var cands = [m, m && m.default, __global.plugin, __global.Plugin, __global.source, __global.exports === m ? null : __global.exports];\n"
    "  for (i = 0; i < cands.length && !f; i++) { c = cands[i]; if (!c) continue;\n"
    "    if (typeof c === 'function') { f = c; }\n"
    "    else if (typeof c.handle === 'function') { f = c.handle; o = c; }\n"
    "    else if (typeof c.handleRequest === 'function') { f = c.handleRequest; o = c; }\n"
    "    else if (c.methods && typeof c.methods === 'object') { f = (function (mm) { return function (method, p) { var fn = mm[method]; if (!fn) throw new Error('method not found'); return fn.call(mm, p); }; })(c.methods); }\n"
    "    else if (c.handlers && typeof c.handlers === 'object') { f = (function (mm) { return function (method, p) { var fn = mm[method]; if (!fn) throw new Error('method not found'); return fn.call(mm, p); }; })(c.handlers); } }\n"
    "  if (!f && typeof __global.handleRequest === 'function') f = __global.handleRequest;\n"
    "  if (!f && typeof __global.onRequest === 'function') f = __global.onRequest;\n"
    "  if (!f && __global.methods && typeof __global.methods === 'object') f = (function (mm) { return function (method, p) { var fn = mm[method]; if (!fn) throw new Error('method not found'); return fn.call(mm, p); }; })(__global.methods);\n"
    "  if (!f && __global.handlers && typeof __global.handlers === 'object') f = (function (mm) { return function (method, p) { var fn = mm[method]; if (!fn) throw new Error('method not found'); return fn.call(mm, p); }; })(__global.handlers);\n"
    "  if (!f) { names = ['onMessage', 'onmessage', 'onLine', 'processLine', 'process_line', 'handleLine', 'handleMessage', 'rpc'];\n"
    "    for (i = 0; i < names.length && !f; i++) { nm = names[i];\n"
    "      if (typeof __global[nm] === 'function') { f = __global[nm]; o = null; }\n"
    "      else if (m && typeof m[nm] === 'function') { f = m[nm]; o = m; } }\n"
    "    if (f) f = (function (fn, owner) { return function (method, p) { return new Promise(function (res, rej) {\n"
    "      var id = ++__rpcId, r; __rpcPending[id] = [res, rej];\n"
    "      try { r = fn.call(owner, JSON.stringify({ jsonrpc: '2.0', id: id, method: method, params: p })); } catch (e) { delete __rpcPending[id]; return rej(e); }\n"
    "      Promise.resolve(r).then(function (v) { if (v === undefined || v === null || v === '' || !__rpcPending[id]) return;\n"
    "        delete __rpcPending[id]; var j = typeof v === 'string' ? JSON.parse(v) : v;\n"
    "        if (j && j.error) rej(j.error); else res(j && j.jsonrpc ? j.result : j); }, rej); }); }; })(f, o); }\n"
    "  if (f) { var fo = o, ff = f; __global.handle = function (method, p) { return ff.call(fo, method, p); }; } }\n"
    "function __unwrap(r) { if (r && typeof r === 'object' && r.jsonrpc && !Array.isArray(r)) { if (r.error) throw r.error; if ('result' in r) return r.result; } return r; }\n"
    "function __errText(e) {\n"
    "  if (e && typeof e === 'object' && typeof e.code === 'number') {\n"
    "    var base = { '-32001': 'Anmeldung nötig', '-32002': 'Nicht gefunden', '-32003': 'Nicht verfügbar', '-32004': 'Zu viele Anfragen, später erneut versuchen', '-32005': 'Netzwerkfehler' }[String(e.code)];\n"
    "    var msg = e.message ? String(e.message) : '';\n"
    "    var rs = e.data && e.data.restrictions ? ' [' + [].concat(e.data.restrictions).join(', ') + ']' : '';\n"
    "    return (base ? base + (msg ? ': ' + msg : '') : (msg || ('Fehler ' + e.code))) + rs; }\n"
    "  return String((e && e.message) || e); }\n"
    "function __dispatch(id, method, paramsJson) {\n"
    "  Promise.resolve().then(function () { return __unwrap(handle(method, JSON.parse(paramsJson))); })\n"
    "   .then(function (r) { __native_reply(id, true, JSON.stringify(r === undefined ? null : r)); },\n"
    "         function (e) { __native_reply(id, false, __errText(e)); }); }\n";
    [m_ctx evaluateScript:shim];
    [m_ctx evaluateScript:[src stringByAppendingString:RfxPluginValues(pid)]];
    // ricercar-style scripts (module.exports.handle / methods / onMessage ...) are adapted to handle(method, params)
    if (firstError == nil) [m_ctx evaluateScript:@"__adapt();"];
    if (firstError == nil && [[m_ctx[@"handle"] toString] hasPrefix:@"undefined"]) firstError = [@"Das Plugin definiert weder handle(method, params) noch eine bekannte Ricercar-Schnittstelle (module.exports.handle, methods, onMessage ...)." retain];
    if (firstError != nil) {
        if (err != NULL) *err = [firstError autorelease];
        [self release];
        return nil;
    }
    [m_ctx setExceptionHandler:^(JSContext *c, JSValue *ex) { NSLog(@"[plugin %@] JS-Fehler: %@", pid, ex); }];
    return self;
}

- (void)dealloc {
    [m_ctx release]; [m_pending release]; [m_pid release];
    [super dealloc];
}

- (void)call:(NSString *)method params:(NSDictionary *)params done:(void (^)(id, NSString *))done {
    int cid = m_nextid++;
    [m_pending setObject:[[done copy] autorelease] forKey:[NSNumber numberWithInt:cid]];
    NSData *pj = [NSJSONSerialization dataWithJSONObject:(params != nil ? params : [NSDictionary dictionary]) options:0 error:nil];
    NSString *ps = [[[NSString alloc] initWithData:pj encoding:NSUTF8StringEncoding] autorelease];
    [[m_ctx objectForKeyedSubscript:@"__dispatch"] callWithArguments:@[@(cid), method, ps]];
}

@end

static UIView *gRfxToastHost = nil;   // the kiosk view (the window can be hidden behind other windows)

// A plugin may name an icon address ("icon_url" in its initialize result).  The app loads it once (also .ico) and keeps it as
// Documents/Plugins/<plugin id>.png, which the search window shows in the header of that source.
static void RfxFetchPluginIcon(id urlStr, NSString *pid) {
    if (![urlStr isKindOfClass:[NSString class]] || [urlStr length] == 0 || [pid length] == 0) return;
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *dest = [[[docs stringByAppendingPathComponent:@"Plugins"] stringByAppendingPathComponent:pid] stringByAppendingPathExtension:@"png"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:dest]) return;
    NSURL *u = [NSURL URLWithString:urlStr];
    if (u == nil) return;
    [[[NSURLSession sharedSession] dataTaskWithURL:u completionHandler:^(NSData *d, NSURLResponse *rs, NSError *er) {
        if (d == nil || er != nil) { NSLog(@"[Plugin] icon %@: %@", urlStr, er ? [er localizedDescription] : @"keine Daten"); return; }
        UIImage *img = nil;
        CGImageSourceRef src = CGImageSourceCreateWithData((CFDataRef)d, NULL);     // .ico: take the largest image of the file
        if (src != NULL) {
            size_t n = CGImageSourceGetCount(src), best = 0, bw = 0;
            for (size_t i = 0; i < n; i++) {
                CGImageRef cg = CGImageSourceCreateImageAtIndex(src, i, NULL);
                if (cg != NULL) { if (CGImageGetWidth(cg) >= bw) { bw = CGImageGetWidth(cg); best = i; } CGImageRelease(cg); }
            }
            CGImageRef cg = (n > 0) ? CGImageSourceCreateImageAtIndex(src, best, NULL) : NULL;
            if (cg != NULL) { img = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
            CFRelease(src);
        }
        if (img == nil) img = [UIImage imageWithData:d];
        NSData *png = (img != nil) ? UIImagePNGRepresentation(img) : nil;
        if (png == nil) { NSLog(@"[Plugin] icon %@: Format nicht lesbar", urlStr); return; }
        [[NSFileManager defaultManager] createDirectoryAtPath:[dest stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        [png writeToFile:dest atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{ [[[(KioskView *)gRfxToastHost m_glv] GetKBView] ReloadAll]; });
    }] resume];
}

@interface RfxPluginHost : NSObject {
    RfxJSPlugin *m_js;
    int m_nextid;
    NSDictionary *m_caps;
    NSString *m_pluginName;
    NSString *m_pluginId;
    NSString *m_iconUrl;
}
@property (nonatomic, retain) NSString *iconUrl;
@property (nonatomic, retain) NSString *pluginId;
@property (nonatomic, retain) NSDictionary *caps;
@property (nonatomic, retain) NSString *pluginName;
- (id)initWithJS:(RfxJSPlugin *)js;
- (void)call:(NSString *)method params:(NSDictionary *)params done:(void (^)(id result, NSString *err))done;
- (void)initializeDone:(void (^)(NSString *err))done;
- (BOOL)has:(NSString *)cap;
@end

@implementation RfxPluginHost
@synthesize caps = m_caps, pluginName = m_pluginName, pluginId = m_pluginId, iconUrl = m_iconUrl;

- (id)initWithJS:(RfxJSPlugin *)js {
    self = [super init];
    if (self) { m_js = [js retain]; m_nextid = 1; }
    return self;
}
- (void)dealloc { [m_js release]; [m_caps release]; [m_pluginName release]; [m_pluginId release]; [m_iconUrl release]; [super dealloc]; }

- (BOOL)has:(NSString *)cap { return [[m_caps objectForKey:cap] boolValue]; }

// ricercar protocol 1 error codes as the plugin (bridge) reports them
static NSString *RfxRpcErrorText(id er) {
    if (![er isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"%@", er];
    NSString *msg = [[er objectForKey:@"message"] description];
    NSString *base = nil;
    switch ([[er objectForKey:@"code"] intValue]) {
    case -32001: base = @"Anmeldung nötig"; break;
    case -32002: base = @"Nicht gefunden"; break;
    case -32003: base = @"Nicht verfügbar"; break;
    case -32004: base = @"Zu viele Anfragen, später erneut versuchen"; break;
    case -32005: base = @"Netzwerkfehler"; break;
    }
    NSString *t = (base != nil) ? ([msg length] ? [NSString stringWithFormat:@"%@: %@", base, msg] : base) : ([msg length] ? msg : @"Fehler");
    id rs = [[er objectForKey:@"data"] isKindOfClass:[NSDictionary class]] ? [[er objectForKey:@"data"] objectForKey:@"restrictions"] : nil;
    if ([rs isKindOfClass:[NSArray class]] && [rs count] > 0) t = [t stringByAppendingFormat:@" [%@]", [rs componentsJoinedByString:@", "]];
    return t;
}

// Compatibility layer for ricercar plugins: the wire format is the same, but plugins differ in what they leave out.
// Missing capabilities are assumed, a search answer without groups becomes one group, browse.root without sections gets
// the plugin's library.* lists, browse.list on "library.*" is routed to that method, stream_url/uri count as url.
- (id)Normalize:(NSString *)method result:(id)r {
    if (![r isKindOfClass:[NSDictionary class]]) return r;
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:r];
    if ([method isEqualToString:@"initialize"]) {
        if ([m objectForKey:@"capabilities"] == nil) {
            [m setObject:[NSDictionary dictionaryWithObjectsAndKeys:@YES, @"auth", @YES, @"browse", @YES, @"search", @YES, @"resolve", nil] forKey:@"capabilities"];
        }
        if ([m objectForKey:@"plugin"] == nil && [m objectForKey:@"name"] != nil)
            [m setObject:[NSDictionary dictionaryWithObjectsAndKeys:[m objectForKey:@"name"], @"name", ([m objectForKey:@"id"] ? [m objectForKey:@"id"] : [m objectForKey:@"name"]), @"id", nil] forKey:@"plugin"];
    } else if ([method isEqualToString:@"search"]) {
        if ([m objectForKey:@"groups"] == nil && [[m objectForKey:@"items"] isKindOfClass:[NSArray class]])
            [m setObject:[NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:@"mixed", @"kind", [m objectForKey:@"items"], @"items", nil]] forKey:@"groups"];
    } else if ([method isEqualToString:@"browse.root"]) {
        if ([[m objectForKey:@"sections"] count] == 0) {
            NSMutableArray *sec = [NSMutableArray array];
            if ([self has:@"library"]) {
                NSArray *lib = [NSArray arrayWithObjects:@"albums", @"Alben", @"tracks", @"Titel", @"playlists", @"Playlists", @"artists", @"Künstler", nil];
                for (int i = 0; i + 1 < (int)[lib count]; i += 2)
                    [sec addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"library.%@", [lib objectAtIndex:i]], @"ref", @"folder", @"kind",
                                    [lib objectAtIndex:i + 1], @"title", @NO, @"playable", @YES, @"browsable", nil]];
            }
            id home = [m objectForKey:@"home"];
            if ([home isKindOfClass:[NSArray class]])
                for (id h in home)
                    if ([h isKindOfClass:[NSDictionary class]] && [[h objectForKey:@"ref"] isKindOfClass:[NSString class]] && [h objectForKey:@"title"] != nil)
                        [sec addObject:[NSDictionary dictionaryWithObjectsAndKeys:[h objectForKey:@"ref"], @"ref", @"folder", @"kind", [h objectForKey:@"title"], @"title", @NO, @"playable", @YES, @"browsable", nil]];
            if ([sec count] > 0) [m setObject:sec forKey:@"sections"];
        }
    } else if ([method isEqualToString:@"track.resolve"]) {
        if ([m objectForKey:@"url"] == nil) {
            id u = [m objectForKey:@"stream_url"]; if (u == nil) u = [m objectForKey:@"uri"]; if (u == nil) u = [m objectForKey:@"stream"];
            if ([u isKindOfClass:[NSString class]]) [m setObject:u forKey:@"url"];
        }
    }
    return m;
}

- (void)call:(NSString *)method params:(NSDictionary *)params done:(void (^)(id, NSString *))done {
    NSString *m = method; NSDictionary *p = params;
    NSString *ref = [params objectForKey:@"ref"];
    if ([method isEqualToString:@"browse.list"] && [ref hasPrefix:@"library."]) {
        m = ref;
        p = [NSDictionary dictionaryWithObjectsAndKeys:([params objectForKey:@"offset"] ? [params objectForKey:@"offset"] : @0), @"offset",
             ([params objectForKey:@"limit"] ? [params objectForKey:@"limit"] : @50), @"limit", nil];
    }
    void (^d)(id, NSString *) = [[done copy] autorelease];
    [self rawCall:m params:p done:^(id r, NSString *e) { d((e == nil ? [self Normalize:method result:r] : r), e); }];
}

- (void)rawCall:(NSString *)method params:(NSDictionary *)params done:(void (^)(id, NSString *))done {
    if (m_js != nil) { [m_js call:method params:params done:done]; return; }
    // plugins only run inside the app (JavaScriptCore); there is no connection to outside processes
    dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"Plugin nicht geladen."); });
}

- (void)initializeDone:(void (^)(NSString *))done {
    NSDictionary *out = [NSDictionary dictionaryWithObjectsAndKeys:@"ios", @"device", [NSNumber numberWithBool:NO], @"bit_perfect",
                         [NSNumber numberWithInt:192000], @"max_rate", [NSNumber numberWithInt:24], @"max_bits",
                         [NSArray arrayWithObjects:@44100, @48000, @88200, @96000, @176400, @192000, nil], @"rates", nil];
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1], @"protocol",
                       [NSDictionary dictionaryWithObjectsAndKeys:@"radiofx", @"name", @"1.0", @"version", nil], @"host",
                       @"", @"data_dir", @"", @"cache_dir", @"de-DE", @"locale", out, @"output",
                       [NSDictionary dictionary], @"settings", nil];
    [self call:@"initialize" params:p done:^(id result, NSString *e) {
        if (e != nil) { done(e); return; }
        [self setCaps:[result objectForKey:@"capabilities"]];
        [self setPluginName:[[result objectForKey:@"plugin"] objectForKey:@"name"]];
        [self setPluginId:[[result objectForKey:@"plugin"] objectForKey:@"id"]];
        id iu = [[result objectForKey:@"plugin"] objectForKey:@"icon_url"];
        if ([iu isKindOfClass:[NSString class]]) [self setIconUrl:iu];
        done(nil);
    }];
}
@end


#pragma mark - plugin manager (autostart, search results in the normal search, import queue)

// crossfade length (seconds), set in the dev menu; the original always used 5
static float RfxCrossfadeSeconds(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"RfxDevCrossfade"];
    float f = (v == nil) ? 12.0f : [v floatValue];
    if (f != f || f < 1.0f) f = 1.0f;
    if (f > 12.0f) f = 12.0f;
    return f;
}
// long fades are shortened for very short songs so the next song is still queued in time
static float RfxFadeForDuration(int dur) {
    float l = RfxCrossfadeSeconds();
    if (l > 5.0f) l = fminf(l, fmaxf(5.0f, ((float)dur - 6.0f) / 2.0f));
    return l;
}

// Documents/Plugins is the one place for plugins. The app ships its plugins in the bundle (Plugins/) and copies each one
// there on start if it is missing; existing files (your edits, keys you typed in) are never overwritten.
// To get a fresh copy of a shipped plugin, delete its file in the Files app.
// The values of <plugin>.txt are also written into the gaps of <plugin>.js itself (the "var NAME = ...;" lines), so the script
// in the Files app shows what is used.  Only lines that exist in the script are changed, and only when the value differs.
static void RfxApplyValuesToScripts(NSString *pdir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *f in [fm contentsOfDirectoryAtPath:pdir error:nil]) {
        if ([[f pathExtension] caseInsensitiveCompare:@"js"] != NSOrderedSame) continue;
        NSString *pid = [f stringByDeletingPathExtension];
        NSString *vals = RfxPluginValues(pid);
        if ([vals length] < 3) continue;
        NSString *jp = [pdir stringByAppendingPathComponent:f];
        NSString *src = [NSString stringWithContentsOfFile:jp encoding:NSUTF8StringEncoding error:nil];
        if (src == nil) continue;
        NSString *out = src;
        NSRegularExpression *pair = [NSRegularExpression regularExpressionWithPattern:@"^var ([A-Z0-9_]+) = (.*);$" options:NSRegularExpressionAnchorsMatchLines error:nil];
        for (NSTextCheckingResult *m in [pair matchesInString:vals options:0 range:NSMakeRange(0, [vals length])]) {
            NSString *key = [vals substringWithRange:[m rangeAtIndex:1]];
            NSString *lit = [vals substringWithRange:[m rangeAtIndex:2]];
            NSString *pat = [NSString stringWithFormat:@"^(var %@ = )(?:'(?:[^'\\\\\\n]|\\\\.)*'|\"(?:[^\"\\\\\\n]|\\\\.)*\"|[^;\\n]*);", key];
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:NSRegularExpressionAnchorsMatchLines error:nil];
            if (re == nil) continue;
            NSString *tpl = [NSString stringWithFormat:@"$1%@;", [NSRegularExpression escapedTemplateForString:lit]];
            out = [re stringByReplacingMatchesInString:out options:0 range:NSMakeRange(0, [out length]) withTemplate:tpl];
        }
        if (![out isEqualToString:src]) [out writeToFile:jp atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

static NSString *RfxPluginDir(void) {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *pdir = [docs stringByAppendingPathComponent:@"Plugins"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:pdir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *shipped = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Plugins"];
    for (NSString *f in [fm contentsOfDirectoryAtPath:shipped error:nil]) {
        if ([[f pathExtension] caseInsensitiveCompare:@"js"] != NSOrderedSame && [[f pathExtension] caseInsensitiveCompare:@"txt"] != NSOrderedSame) continue;
        NSString *dst = [pdir stringByAppendingPathComponent:f];
        if (![fm fileExistsAtPath:dst]) [fm copyItemAtPath:[shipped stringByAppendingPathComponent:f] toPath:dst error:nil];
    }
    RfxApplyValuesToScripts(pdir);
    return pdir;
}

static NSDictionary *RfxPluginPaths(void) {
    NSString *pdir = RfxPluginDir();
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:pdir error:nil])
        if ([[f pathExtension] caseInsensitiveCompare:@"js"] == NSOrderedSame)
            [d setObject:[pdir stringByAppendingPathComponent:f] forKey:[f stringByDeletingPathExtension]];
    return d;
}


// Stream-only titles are kept next to the local files: in the directory of the library folder "Imported" (the folder is
// created if it does not exist yet).  Nothing is emptied at start.
static NSString *RfxStreamDir(void) {
    static NSString *cached = nil;
    if (cached != nil) return cached;
    __block NSString *dir = nil;
    void (^work)(void) = ^{
        KioskView *kv = (KioskView *)gRfxToastHost;
        ServerEntry *sve = [kv isKindOfClass:[KioskView class]] ? [kv m_sve] : nil;
        if (sve == nil) return;
        int sid = [sve serverid];
        [DEL LockDB:NO];
        DBOperations *db = [[DBOperations alloc] init];
        long long fid = [db FolderIDForName:@"Imported" serverid:sid];
        FolderObject *folder = [[[FolderObject alloc] init] autorelease];
        [folder setFoldername:@"Imported"];
        [folder setServerid:sid];
        if (fid < 0) {
            long long next = [db MaxFolderID];
            if (next < 199) next = 199;
            fid = next + 1;
            [folder setFolderid:fid];
            [db InsertFolder:folder];
        } else {
            [folder setFolderid:fid];
        }
        [db release];
        [DEL UnlockDB];
        dir = [[NSString stringWithFormat:@"%@%@/", [DEL CreateServerDir:sve withfolderobject:folder], [DEL Buildfoldername:folder]] retain];
    };
    if ([NSThread isMainThread]) work(); else dispatch_sync(dispatch_get_main_queue(), work);
    if (dir == nil) {            // fallback: temporary folder
        dir = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"PluginStream"] retain];
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    cached = dir;
    return cached;
}

// Downloads belong to the collection that is open: Documents/Import/<collection name>/ is imported into the folder of that name (the
// importer's rule); with no collection of the library open (radio, iPod music, nothing) they go to "Imported" as before.
static NSString *RfxImportDir(NSString *docs) {
    __block NSString *sub = nil;
    void (^work)(void) = ^{
        KioskView *kv = (KioskView *)gRfxToastHost;
        if (![kv isKindOfClass:[KioskView class]]) return;
        GLView *g = [kv m_glv];
        long long fid = [g m_selectedfolderid];
        if (fid < 199 || [g m_selectedipodid] != 0) return;          // reserved ids (radio, iPod, demo, spotify) never take downloads
        [DEL LockDB:NO];
        DBOperations *db = [[DBOperations alloc] init];
        FolderObject *f = [db GetFolderForID:fid withserverid:[g m_selectedserverid] withipodid:0 withspotifyid:nil];
        [db release];
        [DEL UnlockDB];
        NSString *n = [f foldername];
        if ([n length] && [n rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\\"]].location == NSNotFound && ![n hasPrefix:@"."])
            sub = [n copy];
        [f release];
    };
    if ([NSThread isMainThread]) work(); else dispatch_sync(dispatch_get_main_queue(), work);
    NSString *base = [docs stringByAppendingPathComponent:@"Import"];
    NSString *r = (sub != nil && ![sub isEqualToString:@"Imported"]) ? [base stringByAppendingPathComponent:sub] : base;
    [sub release];
    return r;
}

static NSString *RfxSafeName(NSString *s) {
    NSMutableString *m = [NSMutableString stringWithString:(s != nil ? s : @"")];
    for (NSString *bad in [NSArray arrayWithObjects:@"/", @":", @"\\", @"?", @"*", @"\"", @"<", @">", @"|", nil])
        [m replaceOccurrencesOfString:bad withString:@"-" options:0 range:NSMakeRange(0, [m length])];
    NSString *t = [m stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([t length] > 120) t = [t substringToIndex:120];
    return [t length] ? t : @"Unknown";
}


static BOOL gRfxBarBusy = NO;

// No banner any more: messages only go to the log.
void RfxToast(NSString *t) {
    NSLog(@"[Msg] %@", t);
}

// Download progress is only shown by the water in the carousel; no bars anywhere else.
static void RfxProgress(NSString *text, float frac) {
}
static void RfxProgressHide(void) {
}

// square jpeg + 40 px thumbnail in the app's own naming (BuildSmallPicpath)
static void RfxWriteThumbs(UIImage *img, NSString *pic, NSString *title) {
    if (img == nil) img = [MusicImporter PlaceholderForTitle:title];
    NSData *big = [MusicImporter SquareJPEG:img size:196.0f];
    NSData *small = [MusicImporter SquareJPEG:img size:40.0f];
    if (big) [big writeToFile:pic atomically:YES];
    if (small) [small writeToFile:[DEL BuildSmallPicpath:pic] atomically:YES];
}


#pragma mark - backdrop (muted music video excerpt behind the coverflow)

// Documents/backdrop-log.txt (visible in the Files app): what the backdrop did for the last songs, for finding out why no picture comes
void RfxBDLog(NSString *line) {
    NSLog(@"[backdrop] %@", line);
    @try {
        NSString *p = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"backdrop-log.txt"];
        NSString *old = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
        if (old == nil) old = @"";
        if ([old length] > 20000) old = [old substringFromIndex:[old length] - 10000];
        NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
        [f setDateFormat:@"HH:mm:ss"];
        [[old stringByAppendingFormat:@"%@  %@\n", [f stringFromDate:[NSDate date]], line] writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (NSException *e) {}
}


extern UIView *gRfxBackdropGL;
// A projection into the background: the music video that belongs to the song that plays (stream resolved by the YouTube Music plugin, muted) runs as a
// 10 second excerpt in a loop; a new song cross-fades into the next video.  The picture sits behind the coverflow (the GL
// view clears to transparent while it runs).  Dev menu switch "RfxDevBackdrop".
// A video file of the user (Documents/Backdrops): the same 10 second excerpt, muted, looped, works offline.
// TEST MODE: the downloaded video is kept whole and plays from start to end in a loop (shortening to the 10 s excerpt comes later)
static const BOOL kBackdropFullTest = YES;

@interface RfxVideoView : UIView {
    AVPlayer *m_p;
    id m_obs;
    id m_endobs;
    double m_s, m_e;
}
- (id)initWithFrame:(CGRect)f asset:(AVURLAsset *)asset duration:(double)dur;
- (id)initWithFrame:(CGRect)f asset:(AVURLAsset *)asset duration:(double)dur start:(double)fs;   // fs >= 0: excerpt starts there (downloaded excerpt files)
- (BOOL)isRunning;
- (NSString *)diag;
- (void)stop;
@end

@implementation RfxVideoView
+ (Class)layerClass { return [AVPlayerLayer class]; }
- (id)initWithFrame:(CGRect)f asset:(AVURLAsset *)asset duration:(double)dur { return [self initWithFrame:f asset:asset duration:dur start:-1.0]; }
- (id)initWithFrame:(CGRect)f asset:(AVURLAsset *)asset duration:(double)dur start:(double)fs {
    self = [super initWithFrame:f];
    if (self) {
        [self setBackgroundColor:[UIColor blackColor]];
        AVPlayerItem *it = [AVPlayerItem playerItemWithAsset:asset];
        m_p = [[AVPlayer playerWithPlayerItem:it] retain];
        [m_p setMuted:YES];
        [m_p setAllowsExternalPlayback:NO];
        [(AVPlayerLayer *)[self layer] setPlayer:m_p];
        [(AVPlayerLayer *)[self layer] setVideoGravity:AVLayerVideoGravityResizeAspectFill];
        {   // the picture fades into black towards the bottom (where the shadow of the covers begins)
            CAGradientLayer *gm = [CAGradientLayer layer];
            gm.colors = [NSArray arrayWithObjects:(id)[[UIColor colorWithWhite:0 alpha:1] CGColor], (id)[[UIColor colorWithWhite:0 alpha:1] CGColor], (id)[[UIColor colorWithWhite:0 alpha:0] CGColor], nil];
            gm.locations = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.0f], [NSNumber numberWithFloat:0.45f], [NSNumber numberWithFloat:1.0f], nil];
            gm.startPoint = CGPointMake(0.5f, 0.0f); gm.endPoint = CGPointMake(0.5f, 1.0f);
            gm.frame = f;
            [[self layer] setMask:gm];
        }
        if (dur <= 0.0) { dur = CMTimeGetSeconds([asset duration]); if (dur != dur || dur < 0) dur = 0; }
        m_s = (dur > 12.0) ? fmin(dur * 0.35, dur - 11.0) : 0.0;
        m_e = (dur > 0) ? fmin(m_s + 10.0, dur) : m_s + 10.0;
        if (fs >= 0.0) { m_s = fs; m_e = fs + 10.0; }       // the downloaded file holds exactly this part
        if (fs >= 0.0 && kBackdropFullTest) {                // test mode: the whole downloaded video plays, then starts over
            m_s = 0.0; m_e = 1.0e9;
            __block RfxVideoView *me2 = self;
            m_endobs = [[[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:it queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
                [me2->m_p seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
                [me2->m_p play];
            }] retain];
        }
        [m_p seekToTime:CMTimeMakeWithSeconds(m_s, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        [m_p play];
        __block RfxVideoView *me = self;
        m_obs = [[m_p addPeriodicTimeObserverForInterval:CMTimeMake(1, 4) queue:dispatch_get_main_queue() usingBlock:^(CMTime t) {
            if (CMTimeGetSeconds(t) >= me->m_e - 0.05) {
                [me->m_p seekToTime:CMTimeMakeWithSeconds(me->m_s, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
            }
        }] retain];
    }
    return self;
}
// the picture is there: the item is ready and the excerpt has started to play
- (void)layoutSubviews {
    [super layoutSubviews];
    CALayer *m = [[self layer] mask];
    if (m != nil) { [CATransaction begin]; [CATransaction setDisableActions:YES]; [m setFrame:[self bounds]]; [CATransaction commit]; }
}
- (BOOL)isRunning {
    // a layer of a view with alpha 0 is not rendered, so isReadyForDisplay never turns YES for it: judge by the playback itself
    AVPlayerItem *it = [m_p currentItem];
    return it != nil && [it status] == AVPlayerItemStatusReadyToPlay && [m_p rate] > 0.0f && CMTimeGetSeconds([m_p currentTime]) >= m_s + 0.25;
}
- (NSString *)diag {
    AVPlayerItem *it = [m_p currentItem];
    return [NSString stringWithFormat:@"status=%d rate=%.1f t=%.1f ready=%d err=%@", (int)[it status], [m_p rate], CMTimeGetSeconds([m_p currentTime]),
            (int)[(AVPlayerLayer *)[self layer] isReadyForDisplay], [[it error] localizedDescription]];
}
- (void)stop {
    if (m_endobs != nil) { [[NSNotificationCenter defaultCenter] removeObserver:m_endobs]; [m_endobs release]; m_endobs = nil; }
    if (m_obs != nil) { [m_p removeTimeObserver:m_obs]; [m_obs release]; m_obs = nil; }
    [m_p pause];
    [(AVPlayerLayer *)[self layer] setPlayer:nil];
    [m_p release]; m_p = nil;
}
@end

@interface RfxBackdrop : NSObject {
    UIView *m_cur;
    UIView *m_pending;
    int m_gen;
}
+ (RfxBackdrop *)shared;
- (int)bumpGen;
- (int)gen;
- (void)showFile:(NSString *)path in:(UIView *)host behind:(UIView *)ref;
- (void)showFile:(NSString *)path in:(UIView *)host behind:(UIView *)ref start:(double)fs;
- (void)downloadURL:(NSURL *)url headers:(NSDictionary *)headers duration:(double)dur bitrate:(double)br videoId:(NSString *)vid done:(void (^)(NSString *path, double start))done;
+ (NSString *)cachedFileForVideoId:(NSString *)vid start:(double *)start;
- (void)showURL:(NSURL *)url headers:(NSDictionary *)headers duration:(double)dur in:(UIView *)host behind:(UIView *)ref;
- (void)clear;
@end

static RfxBackdrop *gRfxBD = nil;
extern BOOL gRfxBackdropOn;
static void SetBackdropTransparent(BOOL on) {      // the coverflow clears to transparent while a video runs behind it
    gRfxBackdropOn = on;
    UIView *g = [gRfxBackdropGL retain];
    [[g layer] setOpaque:!on];
    [g setBackgroundColor:(on ? [UIColor clearColor] : [UIColor blackColor])];     // the black ground of the GL view would cover the video
    RfxBDLog(on ? @"GL-Ansicht transparent" : @"GL-Ansicht wieder deckend");
    [g release];
}
static const CGFloat kBackdropAlpha = 0.36;       // dimmed like a projection in the background

@implementation RfxBackdrop
+ (RfxBackdrop *)shared { if (gRfxBD == nil) gRfxBD = [[RfxBackdrop alloc] init]; return gRfxBD; }
- (int)bumpGen { return ++m_gen; }
- (int)gen { return m_gen; }

- (void)teardown:(UIView *)w {
    if (w == nil) return;
    if ([w isKindOfClass:[RfxVideoView class]]) [(RfxVideoView *)w stop];
    [w removeFromSuperview];
    [w release];
}

// the new picture is ready: it fades in, the old one fades out
- (void)promote:(UIView *)w {
    UIView *old = m_cur;
    m_cur = m_pending; m_pending = nil;
    SetBackdropTransparent(YES);
    [UIView animateWithDuration:2.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [w setAlpha:kBackdropAlpha];
        [old setAlpha:0.0];
    } completion:^(BOOL f) { [self teardown:old]; }];
}

- (void)attach:(RfxVideoView *)v in:(UIView *)host behind:(UIView *)ref {
    [v setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [v setUserInteractionEnabled:NO];
    if ([ref isKindOfClass:[GLView class]]) {          // only the part above the shadow of the covers
        CGRect fr = [ref frame];
        fr.size.height = fr.size.height * [(GLView *)ref BackdropBottomFraction];
        [v setFrame:fr];
    }
    [v setAlpha:0.01];          // not 0: a fully transparent view is not rendered, the player would not start showing frames
    RfxBDLog([NSString stringWithFormat:@"Player angelegt (Host %@, Frame %@)", NSStringFromClass([host class]), NSStringFromCGRect([v frame])]);
    [host insertSubview:v belowSubview:ref];
    m_pending = v;
    int g = m_gen;
    __block int tries = 0;
    __block void (^poll)(void) = nil;
    poll = [^{
        if (m_pending != v || m_gen != g) { [poll release]; return; }
        if ([v isRunning]) { RfxBDLog(@"Video läuft"); [self promote:v]; [poll release]; return; }
        if (tries == 4 || tries == 14 || tries == 30) RfxBDLog([NSString stringWithFormat:@"wartet auf Start: %@", [v diag]]);
        if (++tries > 60) { RfxBDLog([NSString stringWithFormat:@"Video startet nicht (Player-Timeout): %@", [v diag]]); [self teardown:m_pending]; m_pending = nil; [poll release]; return; }       // never started (offline, stream refused)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), poll);
    } copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), poll);
}

- (void)showFile:(NSString *)path in:(UIView *)host behind:(UIView *)ref {
    if (m_pending != nil) { [self teardown:m_pending]; m_pending = nil; }
    AVURLAsset *as = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    RfxVideoView *v = [[RfxVideoView alloc] initWithFrame:[ref frame] asset:as duration:0.0];
    [self attach:v in:host behind:ref];
}

- (void)showFile:(NSString *)path in:(UIView *)host behind:(UIView *)ref start:(double)fs {
    if (m_pending != nil) { [self teardown:m_pending]; m_pending = nil; }
    AVURLAsset *as = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    RfxVideoView *v = [[RfxVideoView alloc] initWithFrame:[ref frame] asset:as duration:0.0 start:fs];
    [self attach:v in:host behind:ref];
}

// Downloaded videos: Documents/BackdropCache/<videoId>_f.mp4 (visible in the Files app while debugging)
+ (NSString *)backdropDir {
    NSString *d = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"BackdropCache"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
+ (NSString *)cachedFileForVideoId:(NSString *)vid start:(double *)start {
    if ([vid length] == 0) return nil;
    NSString *p = [[self backdropDir] stringByAppendingPathComponent:[vid stringByAppendingString:@"_f.mp4"]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:p]) return nil;
    if (start) *start = 0.0;
    return p;
}

- (void)downloadURL:(NSURL *)url headers:(NSDictionary *)headers duration:(double)dur bitrate:(double)br videoId:(NSString *)vid done:(void (^)(NSString *, double))done {
    NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:url];
    [rq setTimeoutInterval:60.0];
    for (NSString *k in headers) [rq setValue:[[headers objectForKey:k] description] forHTTPHeaderField:k];
    NSString *dest = [[RfxBackdrop backdropDir] stringByAppendingPathComponent:[vid stringByAppendingString:@"_f.mp4"]];
    void (^cb)(NSString *, double) = [done copy];
    [[[NSURLSession sharedSession] downloadTaskWithRequest:rq completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
        NSString *path = nil;
        if (err == nil && loc != nil && (code == 200 || code == 206)) {
            NSData *head = [NSData dataWithContentsOfURL:loc options:NSDataReadingMappedIfSafe error:nil];
            unsigned long long sz = [[[[NSFileManager defaultManager] attributesOfItemAtPath:[loc path] error:nil] objectForKey:NSFileSize] unsignedLongLongValue];
            NSData *first = ([head length] > 0) ? [head subdataWithRange:NSMakeRange(0, MIN((NSUInteger)524288, [head length]))] : nil;
            BOOL moov = first != nil && [first rangeOfData:[NSData dataWithBytes:"moov" length:4] options:0 range:NSMakeRange(0, [first length])].location != NSNotFound;
            BOOL ftyp = first != nil && [first rangeOfData:[NSData dataWithBytes:"ftyp" length:4] options:0 range:NSMakeRange(0, MIN((NSUInteger)64, [first length]))].location != NSNotFound;
            RfxBDLog([NSString stringWithFormat:@"Download fertig: %llu Bytes, HTTP %d, ftyp=%d moov-vorn=%d", sz, (int)code, ftyp, moov]);
            if (sz > 100000 && ftyp) {
                [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
                if ([[NSFileManager defaultManager] moveItemAtPath:[loc path] toPath:dest error:nil]) path = dest;
            }
        } else if (err != nil) RfxBDLog([NSString stringWithFormat:@"Download Fehler: %@", [err localizedDescription]]);
        else RfxBDLog([NSString stringWithFormat:@"Download abgelehnt: HTTP %d", (int)code]);
        if (path != nil) {   // keep the cache small: at most 12 videos
            NSString *dir = [RfxBackdrop backdropDir];
            NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
            if ([all count] > 12) {
                NSMutableArray *dated = [NSMutableArray array];
                for (NSString *fn in all) {
                    NSDate *dt = [[[NSFileManager defaultManager] attributesOfItemAtPath:[dir stringByAppendingPathComponent:fn] error:nil] fileModificationDate];
                    [dated addObject:[NSArray arrayWithObjects:fn, (dt ? dt : [NSDate distantPast]), nil]];
                }
                [dated sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [[a objectAtIndex:1] compare:[b objectAtIndex:1]]; }];
                for (int i = 0; i < (int)[dated count] - 12; i++) [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:[[dated objectAtIndex:i] objectAtIndex:0]] error:nil];
            }
        }
        cb(path, 0.0);
        [cb release];
    }] resume];
}

// a video stream that the plugin resolved (the way the plugin resolves the audio of a song)
- (void)showURL:(NSURL *)url headers:(NSDictionary *)headers duration:(double)dur in:(UIView *)host behind:(UIView *)ref {
    if (m_pending != nil) { [self teardown:m_pending]; m_pending = nil; }
    NSDictionary *opt = [headers count] ? [NSDictionary dictionaryWithObject:headers forKey:@"AVURLAssetHTTPHeaderFieldsKey"] : nil;
    AVURLAsset *as = [AVURLAsset URLAssetWithURL:url options:opt];
    RfxVideoView *v = [[RfxVideoView alloc] initWithFrame:[ref frame] asset:as duration:dur];
    [self attach:v in:host behind:ref];
}

- (void)clear {
    [self bumpGen];
    if (m_pending != nil) { [self teardown:m_pending]; m_pending = nil; }
    UIView *old = m_cur; m_cur = nil;
    if (old == nil) { SetBackdropTransparent(NO); return; }
    [UIView animateWithDuration:1.2 animations:^{ [old setAlpha:0.0]; } completion:^(BOOL f) { [self teardown:old]; if (m_cur == nil && m_pending == nil) SetBackdropTransparent(NO); }];
}
@end

@interface RfxPluginManager () {
    NSMutableDictionary *m_hosts;      // name -> RfxPluginHost (loaded)
    NSMutableSet *m_loading;
    KioskView *m_kv;
    NSTimer *m_deb;
    NSString *m_pendText;
    void (^m_pendDone)(NSString *, NSArray *);
    NSMutableArray *m_queue;           // import queue: {item, host, plugin}
    BOOL m_busy;
    int m_total, m_doneCount;
    BOOL m_queueLast;
    BOOL m_warned;
    BOOL m_anyImport;
    RfxPluginHost *m_playHost;          // plugin of the stream that is playing (for play reports)
    NSString *m_playRef;
    double m_playStart;
    NSTimer *m_stimer;                  // search progress bar (animated while a search is pending)
    double m_st0;
    NSString *m_sphase;
}
@end

static RfxPluginManager *gRfxPM = nil;

@implementation RfxPluginManager

+ (RfxPluginManager *)shared {
    if (gRfxPM == nil) gRfxPM = [[RfxPluginManager alloc] init];
    return gRfxPM;
}
- (id)init {
    self = [super init];
    if (self) { m_hosts = [[NSMutableDictionary alloc] init]; m_loading = [[NSMutableSet alloc] init]; m_queue = [[NSMutableArray alloc] init]; }
    return self;
}
+ (void)Toast:(NSString *)t { RfxToast(t); }
- (void)setKiosk:(KioskView *)kv { m_kv = kv; gRfxToastHost = kv; }

// Order of the music providers (search sections, plugin list): Documents is not involved, kept in NSUserDefaults "RfxPluginOrder".
static NSArray *RfxSortByOrder(NSArray *names) {
    NSArray *ord = [[NSUserDefaults standardUserDefaults] arrayForKey:@"RfxPluginOrder"];
    return [names sortedArrayUsingComparator:^NSComparisonResult(id x, id y) {
        NSUInteger ix = ord ? [ord indexOfObject:x] : NSNotFound, iy = ord ? [ord indexOfObject:y] : NSNotFound;
        if (ix != iy) return ix < iy ? NSOrderedAscending : NSOrderedDescending;       // listed ones first, in their order
        return [(NSString *)x caseInsensitiveCompare:y];
    }];
}
- (NSArray *)AllNames { return RfxSortByOrder([RfxPluginPaths() allKeys]); }
- (void)MovePlugin:(NSString *)name by:(int)delta {
    NSMutableArray *a = [NSMutableArray arrayWithArray:[self AllNames]];
    int i = (int)[a indexOfObject:name], j = i + delta;
    if (i < 0 || j < 0 || j >= (int)[a count]) return;
    [a exchangeObjectAtIndex:i withObjectAtIndex:j];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:@"RfxPluginOrder"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// never configured: nothing starts by itself; plugins (Qobuz needs your keys) you switch on yourself.
// Names of plugins that no longer exist (the old "archive" plugin) are dropped.
- (NSArray *)AutostartList {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:@"RfxPluginAutostart"];
    if (a == nil) return [NSArray array];
    NSDictionary *paths = RfxPluginPaths();
    NSMutableArray *ok = [NSMutableArray array];
    for (NSString *n in a) if ([paths objectForKey:n] != nil) [ok addObject:n];
    return ok;
}
- (BOOL)IsAutostart:(NSString *)name { return [[self AutostartList] containsObject:name]; }
- (NSArray *)SearchPlatforms {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in RfxSortByOrder([m_hosts allKeys])) {
        RfxPluginHost *h = [m_hosts objectForKey:n];
        if (![h has:@"search"]) continue;
        NSString *pn = [[[h pluginName] componentsSeparatedByString:@" ("] objectAtIndex:0];
        if ([pn length] == 0) pn = n;
        NSString *rn = [[NSUserDefaults standardUserDefaults] stringForKey:[@"RfxSrcNote." stringByAppendingString:n]];
        [out addObject:[NSDictionary dictionaryWithObjectsAndKeys:n, @"id", pn, @"name", ([rn length] ? rn : @""), @"note", nil]];
    }
    return out;
}

// Titles of a plugin that cannot deliver audio itself (Spotify): look the same title up at the other loaded sources, in the
// order of the provider list (Dev menu), and use the first one that finds it with about the same length and can resolve it.
- (void)ResolveRedirect:(NSDictionary *)red fallback:(NSDictionary *)fb exclude:(NSString *)ex done:(void (^)(id, NSString *))done {
    NSString *q = [red objectForKey:@"query"];
    long long dur = [[red objectForKey:@"duration_ms"] respondsToSelector:@selector(longLongValue)] ? [[red objectForKey:@"duration_ms"] longLongValue] : 0;
    NSMutableArray *cands = [NSMutableArray array];
    for (NSString *n in RfxSortByOrder([m_hosts allKeys])) {
        RfxPluginHost *h = [m_hosts objectForKey:n];
        if ([n isEqualToString:ex] || ![h has:@"search"] || ![h has:@"resolve"]) continue;
        [cands addObject:n];
    }
    void (^final)(NSString *) = [[^(NSString *why) {
        if ([fb isKindOfClass:[NSDictionary class]] && [[fb objectForKey:@"url"] isKindOfClass:[NSString class]]) done(fb, nil);     // e.g. a 30 s preview
        else done(nil, why);
    } copy] autorelease];
    if ([q length] == 0 || [cands count] == 0) {
        final(@"Spotify-Titel: keine andere Quelle geladen (z. B. Qobuz oder YouTube Music unter Quellen > Autostart einschalten).");
        return;
    }
    __block int idx = 0;
    __block void (^try1)(void) = nil;
    try1 = [^{
        if (idx >= (int)[cands count]) {
            final(@"Spotify-Titel: bei deinen anderen Quellen nicht gefunden.");
            [try1 release];
            return;
        }
        RfxPluginHost *h = [m_hosts objectForKey:[cands objectAtIndex:idx]];
        NSDictionary *sp = [NSDictionary dictionaryWithObjectsAndKeys:q, @"query", [NSArray arrayWithObjects:@"track", nil], @"kinds",
                            [NSNumber numberWithInt:0], @"offset", [NSNumber numberWithInt:6], @"limit", nil];
        [h call:@"search" params:sp done:^(id r, NSString *e) {
            NSDictionary *best = nil;
            long long bestd = 0;
            if (e == nil && [r isKindOfClass:[NSDictionary class]]) {
                for (NSDictionary *g in [r objectForKey:@"groups"]) {
                    if (![[g objectForKey:@"kind"] isEqualToString:@"track"]) continue;
                    for (NSDictionary *it in [g objectForKey:@"items"]) {
                        long long idur = [[it objectForKey:@"duration_ms"] respondsToSelector:@selector(longLongValue)] ? [[it objectForKey:@"duration_ms"] longLongValue] : 0;
                        long long d = (dur > 0 && idur > 0) ? llabs(idur - dur) : 0;
                        if (dur > 0 && idur > 0 && d > 12000) continue;                 // another version / a different title
                        if (best == nil || d < bestd) { best = it; bestd = d; }
                    }
                }
            }
            if (best == nil || [best objectForKey:@"ref"] == nil) { idx++; try1(); return; }
            NSDictionary *rp = [NSDictionary dictionaryWithObjectsAndKeys:[best objectForKey:@"ref"], @"ref", @"play", @"purpose", nil];
            [h call:@"track.resolve" params:rp done:^(id r2, NSString *e2) {
                if (e2 == nil && [r2 isKindOfClass:[NSDictionary class]] && [[r2 objectForKey:@"url"] isKindOfClass:[NSString class]]) {
                    done(r2, nil);
                    [try1 release];
                } else { idx++; try1(); }
            }];
        }];
    } copy];
    try1();
}

// the music video of a song as a stream (needs the YouTube Music plugin to be loaded): done gets url, headers, duration and video id
- (void)StreamVideoForTitle:(NSString *)title artist:(NSString *)artist videoId:(NSString *)vid done:(void (^)(NSDictionary *))done {
    if ([title length] == 0 && [vid length] == 0) { RfxBDLog(@"kein Titel"); done(nil); return; }
    void (^done2)(NSDictionary *) = [done copy];
    [self Load:@"ytmusic" done:^(RfxPluginHost *h) {          // loads the plugin when it is not running yet (no autostart needed)
        if (h == nil) { RfxBDLog(@"Plugin ytmusic nicht verfügbar (fehlt in Documents/Plugins oder Fehler beim Laden)"); done2(nil); [done2 release]; return; }
        NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:(title ? title : @""), @"title", (artist ? artist : @""), @"artist", (vid ? vid : @""), @"videoId", nil];
        [h call:@"video.stream" params:p done:^(id r, NSString *e) {
            if (e != nil) RfxBDLog([NSString stringWithFormat:@"video.stream Fehler: %@", e]);
            done2(([r isKindOfClass:[NSDictionary class]] && [[r objectForKey:@"url"] length] > 0) ? r : nil);
            [done2 release];
        }];
    }];
}
- (BOOL)IsLoaded:(NSString *)name { return [m_hosts objectForKey:name] != nil; }

- (void)SetAutostart:(BOOL)on forName:(NSString *)name {
    NSMutableArray *a = [NSMutableArray arrayWithArray:[self AutostartList]];
    [a removeObject:name];
    if (on) [a addObject:name];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:@"RfxPluginAutostart"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (on) [self Load:name done:nil];
    else [m_hosts removeObjectForKey:name];
}

- (void)StartAutoload {
    {   // the Archive plugin was removed: delete its copy from Documents/Plugins once
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        [[NSFileManager defaultManager] removeItemAtPath:[[docs stringByAppendingPathComponent:@"Plugins"] stringByAppendingPathComponent:@"archive.js"] error:nil];
    }
    // (the stream folder is no longer emptied at start, see RfxStreamDir)
    for (NSString *n in [self AutostartList]) [self Load:n done:nil];
}

- (void)Load:(NSString *)name done:(void (^)(RfxPluginHost *))done {
    RfxPluginHost *h = [m_hosts objectForKey:name];
    if (h != nil) { if (done) done(h); return; }
    if ([m_loading containsObject:name]) { if (done) done(nil); return; }
    NSString *path = [RfxPluginPaths() objectForKey:name];
    NSString *src = (path != nil) ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    if (src == nil) { RfxToast([NSString stringWithFormat:@"Plugin %@ nicht gefunden.", name]); if (done) done(nil); return; }
    NSString *err = nil;
    RfxJSPlugin *js = [[RfxJSPlugin alloc] initWithScript:src pluginId:name error:&err];
    if (js == nil) { RfxToast([NSString stringWithFormat:@"Plugin %@: %@", name, err]); if (done) done(nil); return; }
    RfxPluginHost *host = [[[RfxPluginHost alloc] initWithJS:js] autorelease];
    [js release];
    [m_loading addObject:name];
    [host initializeDone:^(NSString *e) {
        [m_loading removeObject:name];
        if (e != nil) { RfxToast([NSString stringWithFormat:@"Plugin %@: %@", name, e]); if (done) done(nil); return; }
        [m_hosts setObject:host forKey:name];
        RfxFetchPluginIcon([host iconUrl], name);
        if (done) done(host);
    }];
}

#pragma mark search

// progress bar for the plugin search: the bar creeps forward while the search / cover loading runs, then disappears
- (void)SearchBusy:(NSString *)phase {
    [m_sphase release]; m_sphase = [phase copy];
    gRfxBarBusy = YES;
    if (m_stimer == nil) {
        m_st0 = CACurrentMediaTime();
        m_stimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(SearchTick) userInfo:nil repeats:YES];
    }
    [self SearchTick];
}
- (void)SearchTick {
    double t = CACurrentMediaTime() - m_st0;
    NSString *pn = nil, *pid = nil;
    for (NSString *n in m_hosts) {
        RfxPluginHost *h = [m_hosts objectForKey:n];
        if ([h has:@"search"]) { pn = [h pluginName]; pid = n; break; }
    }
    NSString *rn = pid ? [[NSUserDefaults standardUserDefaults] stringForKey:[@"RfxSrcNote." stringByAppendingString:pid]] : nil;
    if (pn != nil && [rn length]) pn = [[[pn componentsSeparatedByString:@" ("] objectAtIndex:0] stringByAppendingFormat:@" \u00B7 %@", rn];
    [[[m_kv m_glv] GetKBView] SetSearchProgress:(float)(0.9 * (1.0 - exp(-t / 2.5))) label:pn pluginId:pid];
}
- (void)SearchIdle {
    [m_stimer invalidate]; m_stimer = nil;
    [m_sphase release]; m_sphase = nil;
    gRfxBarBusy = m_busy;
    [[[m_kv m_glv] GetKBView] SetSearchProgress:-1.0f label:nil];
}

- (void)SearchText:(NSString *)text done:(void (^)(NSString *, NSArray *))done {
    NSString *t = [[text copy] autorelease];
    void (^d)(NSString *, NSArray *) = [[done copy] autorelease];
    dispatch_async(dispatch_get_main_queue(), ^{
        [m_pendText release]; m_pendText = [t retain];
        [m_pendDone release]; m_pendDone = [d copy];
        if ([t length] > 1 && [m_hosts count] > 0) [self SearchBusy:@"Suche ..."]; else [self SearchIdle];
        [m_deb invalidate];
        m_deb = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self selector:@selector(FireSearch) userInfo:nil repeats:NO];
    });
}

- (void)FireSearch {
    m_deb = nil;
    NSString *text = [[m_pendText retain] autorelease];
    void (^done)(NSString *, NSArray *) = [[m_pendDone retain] autorelease];
    NSMutableArray *hosts = [NSMutableArray array];
    for (NSString *n in m_hosts) if ([[m_hosts objectForKey:n] has:@"search"]) [hosts addObject:n];
    if ([hosts count] == 0 && [text length] > 1 && !m_warned) {
        m_warned = YES;
        RfxToast([[RfxPluginPaths() allKeys] count] ? @"Kein Plugin geladen: Quellen > Autostart wählen." : @"Keine Plugins gefunden.");
    }
    if ([hosts count] == 0 || [text length] == 0 || done == nil) {
        [self SearchIdle];
        return;
    }
    __block BOOL hadErr = NO;
    __block int waiting = (int)[hosts count];
    NSMutableArray *all = [NSMutableArray array];
    for (NSString *n in hosts) {
        RfxPluginHost *h = [m_hosts objectForKey:n];
        NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:text, @"query", [NSArray arrayWithObjects:@"track", nil], @"kinds",
                           [NSNumber numberWithInt:0], @"offset", [NSNumber numberWithInt:20], @"limit", nil];
        [h call:@"search" params:p done:^(id r, NSString *e) {
            NSString *note = nil;
            if (e == nil && [r isKindOfClass:[NSDictionary class]]) {
                id snote = [r objectForKey:@"source_note"];       // e.g. "Premium" / "Free": shown behind the service name
                if ([snote isKindOfClass:[NSString class]] && [snote length]) {
                    note = snote;
                    [[NSUserDefaults standardUserDefaults] setObject:snote forKey:[@"RfxSrcNote." stringByAppendingString:n]];
                }
                for (NSDictionary *g in [r objectForKey:@"groups"]) {
                    if (![[g objectForKey:@"kind"] isEqualToString:@"track"]) continue;       // single titles only: no albums, artists, playlists
                    for (NSDictionary *it in [g objectForKey:@"items"]) {
                        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:it];
                        [m setObject:n forKey:@"_plugin"];
                        if ([h pluginName] != nil) {      // short source name (text before a bracket) shown under the title
                            NSString *sn = [[[h pluginName] componentsSeparatedByString:@" ("] objectAtIndex:0];
                            if ([sn length]) [m setObject:sn forKey:@"_source"];
                            if (note != nil) [m setObject:note forKey:@"_note"];
                        }
                        if ([m objectForKey:@"kind"] == nil) [m setObject:[g objectForKey:@"kind"] forKey:@"kind"];
                        [all addObject:m];
                    }
                }
            }
            if (e != nil) { hadErr = YES; RfxToast([NSString stringWithFormat:@"Plugin-Suche %@: %@", n, e]); }
            if (--waiting == 0) {
                if ([all count] == 0) { [self SearchIdle]; done(text, [NSArray array]); return; }
                [self SearchBusy:@"Lade Cover ..."];
                [self BuildClips:all text:text done:^(NSString *tx, NSArray *clips) { done(tx, clips); [self SearchIdle]; }];
            }
        }];
    }
}

- (void)BuildClips:(NSArray *)all text:(NSString *)text done:(void (^)(NSString *, NSArray *))done {
    int sid = [[m_kv m_sve] serverid];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *tdir = [[docs stringByAppendingPathComponent:@"PluginCache"] stringByAppendingPathComponent:@"thumbs"];
        [[NSFileManager defaultManager] createDirectoryAtPath:tdir withIntermediateDirectories:YES attributes:nil error:nil];
        NSMutableArray *specs = [NSMutableArray array];   // {item, pic, id}
        // The list is shown at once.  Covers that are not on the device yet get a placeholder thumbnail now and are loaded in
        // the background; the list refreshes as they arrive (the small file is a placeholder until the big one exists).
        for (NSDictionary *it in all) {
            NSString *hex = nil;
            unsigned long long h64 = RfxHash64([NSString stringWithFormat:@"%@|%@", [it objectForKey:@"_plugin"], [it objectForKey:@"ref"]], &hex);
            NSString *pic = [tdir stringByAppendingPathComponent:[hex stringByAppendingPathExtension:@"jpg"]];
            [specs addObject:[NSDictionary dictionaryWithObjectsAndKeys:it, @"item", pic, @"pic", [NSNumber numberWithLongLong:-(long long)(h64 & 0x3fffffffffULL) - 100000], @"id", nil]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:pic] && [[NSFileManager defaultManager] fileExistsAtPath:[DEL BuildSmallPicpath:pic]]) continue;
            NSString *art = [it objectForKey:@"art"];
            NSURL *au = ([art isKindOfClass:[NSString class]] && [art length]) ? [NSURL URLWithString:art] : nil;
            NSString *title = [it objectForKey:@"title"];
            if (au == nil) { RfxWriteThumbs(nil, pic, title); continue; }
            NSString *small = [DEL BuildSmallPicpath:pic];
            if (![[NSFileManager defaultManager] fileExistsAtPath:small]) {
                NSData *ph = [MusicImporter SquareJPEG:[MusicImporter PlaceholderForTitle:title] size:40.0f];
                if (ph) [ph writeToFile:small atomically:YES];
            }
            NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:au];
            [rq setTimeoutInterval:15.0];
            [[[NSURLSession sharedSession] dataTaskWithRequest:rq completionHandler:^(NSData *d, NSURLResponse *rs, NSError *er) {
                NSAutoreleasePool *p2 = [[NSAutoreleasePool alloc] init];
                UIImage *img = (d != nil && er == nil) ? [UIImage imageWithData:d] : nil;
                RfxWriteThumbs(img, pic, title);
                dispatch_async(dispatch_get_main_queue(), ^{ [[[m_kv m_glv] GetKBView] ReloadResults]; });
                [p2 release];
            }] resume];
        }
        NSMutableArray *clips = [NSMutableArray array];
        for (NSDictionary *sp in specs) {
            NSDictionary *it = [sp objectForKey:@"item"];
            ClipObject *c = [[ClipObject alloc] init];
            [c setID:[[sp objectForKey:@"id"] longLongValue]];
            [c setM_folderid:-88];
            [c setM_serverid:sid];
            NSString *kind = [it objectForKey:@"kind"];
            BOOL isTrack = [kind isEqualToString:@"track"];
            NSString *artist = [it objectForKey:@"artist"];
            if (![artist isKindOfClass:[NSString class]] || [artist length] == 0) artist = [it objectForKey:@"subtitle"];
            if (![artist isKindOfClass:[NSString class]]) artist = @"";
            NSString *extra = isTrack ? @"" : ([[it objectForKey:@"track_count"] intValue] > 0 ?
                [NSString stringWithFormat:@" · Album, %d Titel", [[it objectForKey:@"track_count"] intValue]] : @" · Album");
            [c setM_title:([it objectForKey:@"title"] ? [it objectForKey:@"title"] : @"")];
            [c setM_interpret:[artist stringByAppendingString:extra]];
            [c setM_albumname:([it objectForKey:@"album"] && [[it objectForKey:@"album"] isKindOfClass:[NSString class]] ? [it objectForKey:@"album"] : @"")];
            [c setM_picturepath:[sp objectForKey:@"pic"]];
            NSData *j = [NSJSONSerialization dataWithJSONObject:it options:0 error:nil];
            if (j != nil) [c setM_information:[[[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] autorelease]];
            [clips addObject:c];
            [c release];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(text, clips); });
        [pool release];
    });
}

#pragma mark import

- (void)ImportClip:(ClipObject *)co {
    NSData *j = [[co m_information] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *it = (j != nil) ? [NSJSONSerialization JSONObjectWithData:j options:0 error:nil] : nil;
    RfxPluginHost *h = [m_hosts objectForKey:[it objectForKey:@"_plugin"]];
    if (it == nil || h == nil) { RfxToast(@"Plugin nicht geladen."); return; }
    NSMutableDictionary *mit = [NSMutableDictionary dictionaryWithDictionary:it];
    if ([[co m_picturepath] length]) [mit setObject:[co m_picturepath] forKey:@"_pic"];
    [self ImportItem:mit host:h queueLast:YES];
}

// the chosen title goes into the carousel first (as a stream-only tile without file); a water level on its cover shows the progress
- (void)AddPlaceholderForItem:(NSDictionary *)it plugin:(NSString *)plugin {
    GLView *glv = [m_kv m_glv];
    if (glv == nil) return;
    NSString *ref = [it objectForKey:@"ref"];
    if (ref == nil) return;
    long long cid = RfxItemID(plugin, ref);
    NSString *pic = [[it objectForKey:@"_pic"] isKindOfClass:[NSString class]] ? [it objectForKey:@"_pic"] : nil;
    ClipObject *pc = [[ClipObject alloc] init];
    [pc setID:cid];
    [pc setM_folderid:-88];
    [pc setM_filepath:nil];
    [pc setM_serverid:[[m_kv m_sve] serverid]];
    [pc setM_title:([it objectForKey:@"title"] ? [it objectForKey:@"title"] : @"")];
    NSString *artist = [[it objectForKey:@"artist"] isKindOfClass:[NSString class]] ? [it objectForKey:@"artist"] : @"";
    [pc setM_interpret:artist];
    [pc setM_albumname:([[it objectForKey:@"album"] isKindOfClass:[NSString class]] ? [it objectForKey:@"album"] : @"")];
    // no cover while the water runs: the tile looks like a title without cover; the real cover comes with the finished import
    [pc setM_duration:[[it objectForKey:@"duration_ms"] intValue] / 1000];
    NSData *jr = [NSJSONSerialization dataWithJSONObject:[NSDictionary dictionaryWithObjectsAndKeys:plugin, @"_plugin", ref, @"ref", nil] options:0 error:nil];
    if (jr != nil) [pc setM_information:[[[NSString alloc] initWithData:jr encoding:NSUTF8StringEncoding] autorelease]];
    [glv SetWaterForClipID:cid level:0.04f];
    [glv AddPicture:pc];                                  // takes over the reference
    [glv ShowAllTilesKeepingSearch];                      // the search text only narrows while searching local titles
    [glv ReInitThread];                                   // the loader thread builds the cover now
    [glv BuildCoverNowForPluginClipID:cid];               // and the cover is also built right here, so it shows at once
    ClipObject *target = [[ClipObject alloc] init];
    [target setID:cid];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [glv SpinAutomaticToClip:target orIndex:-1];
        [target release];
    });
}

- (void)ImportItem:(NSDictionary *)it host:(RfxPluginHost *)h queueLast:(BOOL)queueLast {
    NSString *kind = [it objectForKey:@"kind"];
    NSString *plugin = [it objectForKey:@"_plugin"] ? [it objectForKey:@"_plugin"] : [h pluginId];
    if ([kind isEqualToString:@"track"] || [kind length] == 0) {
        [self AddPlaceholderForItem:it plugin:plugin];
        [m_queue addObject:[NSDictionary dictionaryWithObjectsAndKeys:it, @"item", h, @"host", plugin, @"plugin", nil]];
        m_total++; m_queueLast = queueLast && !m_busy && [m_queue count] == 1;
        [self Pump];
        return;
    }
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:[it objectForKey:@"ref"], @"ref", [NSNumber numberWithInt:0], @"offset", [NSNumber numberWithInt:500], @"limit", nil];
    NSString *album = [it objectForKey:@"title"];
    [h call:@"browse.list" params:p done:^(id r, NSString *e) {
        if (e != nil) { RfxToast([NSString stringWithFormat:@"Album: %@", e]); return; }
        int n = 0;
        for (NSDictionary *t in [r objectForKey:@"items"]) {
            if (![[t objectForKey:@"kind"] isEqualToString:@"track"] || ([t objectForKey:@"playable"] && ![[t objectForKey:@"playable"] boolValue])) continue;
            NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:t];
            if (![[m objectForKey:@"album"] isKindOfClass:[NSString class]]) [m setObject:album forKey:@"album"];
            if ([m objectForKey:@"art"] == nil && [it objectForKey:@"art"] != nil) [m setObject:[it objectForKey:@"art"] forKey:@"art"];
            [m setObject:plugin forKey:@"_plugin"];
            [m_queue addObject:[NSDictionary dictionaryWithObjectsAndKeys:m, @"item", h, @"host", plugin, @"plugin", nil]];
            m_total++; n++;
        }
        m_queueLast = NO;
        if (n == 0) { RfxToast(@"Keine abspielbaren Titel."); return; }
        [self Pump];
    }];
}

- (void)Pump {
    if (m_busy) return;
    if ([m_queue count] == 0) {
        if (m_total > 0) [self FinishBatch];
        m_total = 0; m_doneCount = 0;
        return;
    }
    m_busy = YES;
    NSDictionary *job = [[[m_queue objectAtIndex:0] retain] autorelease];
    [m_queue removeObjectAtIndex:0];
    NSDictionary *it = [job objectForKey:@"item"];
    RfxPluginHost *h = [job objectForKey:@"host"];
    RfxProgress([NSString stringWithFormat:@"%d/%d  %@", m_doneCount + 1, m_total, [it objectForKey:@"title"]], (float)m_doneCount / (float)(m_total > 0 ? m_total : 1));
    GLView *wglv = [m_kv m_glv];
    long long wid = RfxItemID([job objectForKey:@"plugin"], [it objectForKey:@"ref"]);
    [wglv SetWaterForClipID:wid level:0.06f];
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:[it objectForKey:@"ref"], @"ref", @"play", @"purpose", nil];
    void (^afterResolve)(id, NSString *) = [[^(id r, NSString *e) {
        NSURL *url = (e == nil && [r isKindOfClass:[NSDictionary class]] && [[r objectForKey:@"url"] isKindOfClass:[NSString class]]) ? [NSURL URLWithString:[r objectForKey:@"url"]] : nil;
        if (url == nil) {
            RfxToast([NSString stringWithFormat:@"%@: %@", [it objectForKey:@"title"], (e ? e : @"keine Adresse")]);
            [wglv ClearWater]; [wglv RemovePluginPlaceholder:wid];
            [self JobDone]; return;
        }
        [wglv SetWaterForClipID:wid level:0.15f];
        int dc = m_doneCount, tot = m_total;
        // a plugin can say how long the delivered file really is (e.g. a 30 s preview of a longer title)
        NSDictionary *qit = it;
        id rd = [r objectForKey:@"duration_ms"];
        if ([rd isKindOfClass:[NSNumber class]] && [rd intValue] > 0) {
            NSMutableDictionary *m2 = [NSMutableDictionary dictionaryWithDictionary:it];
            [m2 setObject:rd forKey:@"duration_ms"];
            qit = m2;
        }
        // a plugin can mark a title as "stream only" (resolve result "cache": false): it is only buffered in the
        // temporary folder for playing and is never put into the library
        id cacheFlag = [r objectForKey:@"cache"];
        // DEVIATION: every title (also previews) is treated like a local file: it is imported into the library (radio.db) and
        // stays in the carousel.  The plugin's "cache: false" is ignored on purpose.
        BOOL stream = NO;
        (void)cacheFlag;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
            NSString *dir = stream ? RfxStreamDir() : RfxImportDir(docs);
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *ext = [[url path] pathExtension];
            if ([ext length] == 0 || [ext length] > 5) ext = [[[r objectForKey:@"format"] objectForKey:@"codec"] description];
            if ([ext length] == 0 || [ext isEqualToString:@"(null)"]) ext = @"audio";
            NSString *artist = [[it objectForKey:@"artist"] isKindOfClass:[NSString class]] && [[it objectForKey:@"artist"] length] ? [it objectForKey:@"artist"] : @"Unknown Artist";
            NSString *stem = RfxSafeName([NSString stringWithFormat:@"%@ - %@", artist, [it objectForKey:@"title"]]);
            NSString *file = [dir stringByAppendingPathComponent:[stem stringByAppendingPathExtension:ext]];
            NSString *cover = [dir stringByAppendingPathComponent:[stem stringByAppendingPathExtension:@"jpg"]];
            NSString *art = [it objectForKey:@"art"];
            if ([art isKindOfClass:[NSString class]] && [art length] && ![[NSFileManager defaultManager] fileExistsAtPath:cover]) {
                NSURL *au = [NSURL URLWithString:art];
                NSData *d = (au != nil) ? [NSData dataWithContentsOfURL:au] : nil;
                if (d != nil && [UIImage imageWithData:d] != nil) [d writeToFile:cover atomically:YES];
            }
            __block NSString *msg = nil;
            // a plugin can hand over request headers (e.g. the User-Agent a stream address was issued for) and say that the
            // file has to be fetched in pieces (Range requests of 5 MB), which some stream servers require
            id rhd = [r objectForKey:@"headers"];
            NSDictionary *hdrs = [rhd isKindOfClass:[NSDictionary class]] ? rhd : nil;
            long long total = [[r objectForKey:@"size"] respondsToSelector:@selector(longLongValue)] ? [[r objectForKey:@"size"] longLongValue] : 0;
            BOOL chunked = [[r objectForKey:@"chunked"] boolValue] && total > 0;
            NSString *ptitle = [it objectForKey:@"title"] ? [it objectForKey:@"title"] : @"";
            if (![[NSFileManager defaultManager] fileExistsAtPath:file] && chunked) {
                NSString *part = [file stringByAppendingString:@".part"];
                [[NSFileManager defaultManager] removeItemAtPath:part error:nil];
                [[NSFileManager defaultManager] createFileAtPath:part contents:nil attributes:nil];
                NSFileHandle *wh = [NSFileHandle fileHandleForWritingAtPath:part];
                long long pos = 0;
                const long long CH = 5LL * 1048576LL;
                while (pos < total && msg == nil) {
                    long long end = (pos + CH - 1 < total - 1) ? pos + CH - 1 : total - 1;
                    NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:url];
                    for (NSString *hk in hdrs) [rq setValue:[NSString stringWithFormat:@"%@", [hdrs objectForKey:hk]] forHTTPHeaderField:hk];
                    [rq setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", pos, end] forHTTPHeaderField:@"Range"];
                    [rq setTimeoutInterval:40.0];
                    dispatch_semaphore_t s2 = dispatch_semaphore_create(0);
                    __block NSData *got = nil;
                    __block NSInteger gcode = 0;
                    [[[NSURLSession sharedSession] dataTaskWithRequest:rq completionHandler:^(NSData *d, NSURLResponse *rs, NSError *er) {
                        gcode = [rs isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)rs statusCode] : 0;
                        if (er != nil) msg = [[er localizedDescription] copy];
                        else if (gcode != 206 && gcode != 200) msg = [[NSString stringWithFormat:@"HTTP %ld", (long)gcode] copy];
                        else got = [d retain];
                        dispatch_semaphore_signal(s2);
                    }] resume];
                    dispatch_semaphore_wait(s2, DISPATCH_TIME_FOREVER);
                    dispatch_release(s2);
                    if (got != nil) {
                        if ([got length] == 0) msg = [@"leere Antwort" copy];
                        else { [wh writeData:got]; pos += (gcode == 200) ? total : (long long)[got length]; }
                        [got release];
                    }
                    float tf = (float)((double)pos / (double)total);
                    RfxProgress([NSString stringWithFormat:@"%d/%d  %@  %.1f MB", dc + 1, tot, ptitle, pos / 1048576.0], ((float)dc + tf) / (float)(tot > 0 ? tot : 1));
                    [wglv SetWaterForClipID:wid level:0.15f + 0.82f * tf];
                }
                [wh closeFile];
                if (msg == nil) {
                    if (![[NSFileManager defaultManager] moveItemAtPath:part toPath:file error:nil]) msg = [@"Datei nicht ablegbar" copy];
                } else {
                    [[NSFileManager defaultManager] removeItemAtPath:part error:nil];
                }
            } else if (![[NSFileManager defaultManager] fileExistsAtPath:file]) {
                dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                NSMutableURLRequest *rq0 = [NSMutableURLRequest requestWithURL:url];
                for (NSString *hk in hdrs) [rq0 setValue:[NSString stringWithFormat:@"%@", [hdrs objectForKey:hk]] forHTTPHeaderField:hk];
                NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithRequest:rq0 completionHandler:^(NSURL *tmp, NSURLResponse *resp, NSError *err) {
                    NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 200;
                    if (err != nil) msg = [[err localizedDescription] copy];
                    else if (code < 200 || code >= 300) msg = [[NSString stringWithFormat:@"HTTP %ld", (long)code] copy];
                    else if (![[NSFileManager defaultManager] moveItemAtURL:tmp toURL:[NSURL fileURLWithPath:file] error:nil]) msg = [@"Datei nicht ablegbar" copy];
                    dispatch_semaphore_signal(sem);
                }];
                [task resume];
                while (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC))) != 0) {
                    long long got = [task countOfBytesReceived], all = [task countOfBytesExpectedToReceive];
                    float tf = (all > 0) ? (float)((double)got / (double)all) : 0.0f;
                    RfxProgress([NSString stringWithFormat:@"%d/%d  %@  %.1f MB", dc + 1, tot, ptitle, got / 1048576.0], ((float)dc + tf) / (float)(tot > 0 ? tot : 1));
                    if (all <= 0) tf = 1.0f - (float)exp(-(double)got / 1048576.0 / 3.0);     // size unknown: fills up slowly
                    [wglv SetWaterForClipID:wid level:0.15f + 0.82f * tf];
                }
                dispatch_release(sem);
            }
            {   // log what was really delivered: first bytes tell the format (fLaC = FLAC, ID3 / 0xFF 0xFB = MP3)
                NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:file];
                NSData *hd = [fh readDataOfLength:4];
                [fh closeFile];
                unsigned long long fsz = [[[NSFileManager defaultManager] attributesOfItemAtPath:file error:nil] fileSize];
                NSLog(@"[Stream] %@  %llu bytes  first bytes: %@", [file lastPathComponent], fsz, hd);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (msg != nil) {
                    RfxToast([NSString stringWithFormat:@"%@: %@", [it objectForKey:@"title"], msg]); [msg release];
                    [wglv ClearWater]; [wglv RemovePluginPlaceholder:wid];
                } else {
                    [wglv SetWaterForClipID:wid level:1.0f];
                    if (stream) {
                        [wglv SetFilepath:file forPluginClipID:wid];
                        [self QueueStreamed:qit file:file cover:cover];
                        if ([[NSFileManager defaultManager] fileExistsAtPath:cover]) [wglv SetPicture:cover forPluginClipID:wid];
                    }
                    else {
                        // the water fills up completely first, then the title becomes a normal tile with its cover
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [self ImportDownloadedFor:wid];
                            [wglv ClearWater];
                            [self JobDone];
                        });
                        return;
                    }
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [wglv ClearWater]; });
                }
                [self JobDone];
            });
            [pool release];
        });
    } copy] autorelease];
    // a plugin that has no audio of its own (Spotify) answers with {redirect: {query, duration_ms ...}}: the same title is looked up at the other sources
    [h call:@"track.resolve" params:p done:^(id r0, NSString *e0) {
        id rd0 = (e0 == nil && [r0 isKindOfClass:[NSDictionary class]]) ? [r0 objectForKey:@"redirect"] : nil;
        if ([rd0 isKindOfClass:[NSDictionary class]]) [self ResolveRedirect:rd0 fallback:r0 exclude:[job objectForKey:@"plugin"] done:afterResolve];
        else afterResolve(r0, e0);
    }];
}

- (void)JobDone {
    m_busy = NO;
    m_doneCount++;
    [self Pump];
}

- (void)FinishBatch {
    RfxProgressHide();
}

#pragma mark play reports (plugins with the "reporting" capability)

// A stream that starts playing / stops playing is announced to its plugin (playback.started / playback.ended with the
// listened time), so a plugin can report plays to its service the way that service asks for it.
- (void)PlaybackStarted:(ClipObject *)c {
    [self PlaybackEnded];                               // the previous stream stops when the next one starts
    if (c == nil || [c m_folderid] != -88 || [[c m_information] length] == 0) return;
    NSData *j = [[c m_information] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *d = (j != nil) ? [NSJSONSerialization JSONObjectWithData:j options:0 error:nil] : nil;
    RfxPluginHost *h = [d isKindOfClass:[NSDictionary class]] ? [m_hosts objectForKey:[d objectForKey:@"_plugin"]] : nil;
    NSString *ref = [d objectForKey:@"ref"];
    if (h == nil || [ref length] == 0 || ![h has:@"reporting"]) return;
    m_playHost = h;
    m_playRef = [ref copy];
    m_playStart = CACurrentMediaTime();
    [h call:@"playback.started" params:[NSDictionary dictionaryWithObject:ref forKey:@"ref"] done:^(id r, NSString *e) {
        if (e != nil) NSLog(@"[plugin] playback.started: %@", e);
    }];
}

- (void)PlaybackEnded {
    if (m_playRef == nil) return;
    int ms = (int)((CACurrentMediaTime() - m_playStart) * 1000.0);
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:m_playRef, @"ref", [NSNumber numberWithInt:ms], @"listened_ms", nil];
    RfxPluginHost *h = m_playHost;
    [m_playRef release]; m_playRef = nil; m_playHost = nil;
    [h call:@"playback.ended" params:p done:^(id r, NSString *e) {
        if (e != nil) NSLog(@"[plugin] playback.ended: %@", e);
    }];
}

// stream-only title: the buffer file in the temporary folder is played like a local song, nothing goes into the library
- (void)QueueStreamed:(NSDictionary *)it file:(NSString *)file cover:(NSString *)cover {
    if (m_kv == nil) return;
    NSString *hex = nil;
    unsigned long long h64 = RfxHash64([NSString stringWithFormat:@"%@|%@", [it objectForKey:@"_plugin"], [it objectForKey:@"ref"]], &hex);
    ClipObject *c = [[ClipObject alloc] init];
    [c setID:-(long long)(h64 & 0x3fffffffffULL) - 100000];
    [c setM_folderid:-88];
    [c setM_serverid:[[m_kv m_sve] serverid]];
    [c setM_title:([it objectForKey:@"title"] ? [it objectForKey:@"title"] : @"")];
    [c setM_interpret:([[it objectForKey:@"artist"] isKindOfClass:[NSString class]] ? [it objectForKey:@"artist"] : @"")];
    [c setM_albumname:([[it objectForKey:@"album"] isKindOfClass:[NSString class]] ? [it objectForKey:@"album"] : @"")];
    [c setM_filepath:file];
    NSData *jr = [NSJSONSerialization dataWithJSONObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    ([it objectForKey:@"_plugin"] ? [it objectForKey:@"_plugin"] : @""), @"_plugin", ([it objectForKey:@"ref"] ? [it objectForKey:@"ref"] : @""), @"ref", nil] options:0 error:nil];
    if (jr != nil) [c setM_information:[[[NSString alloc] initWithData:jr encoding:NSUTF8StringEncoding] autorelease]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:cover]) {
        [c setM_picturepath:cover];
        UIImage *img = [UIImage imageWithContentsOfFile:cover];
        if (img != nil) { NSData *sm = [MusicImporter SquareJPEG:img size:40.0f]; if (sm) [sm writeToFile:[DEL BuildSmallPicpath:cover] atomically:YES]; }
    }
    [c setM_duration:[[it objectForKey:@"duration_ms"] intValue] / 1000];
    [c setM_tracknumber:[[it objectForKey:@"track_no"] intValue]];
    gRfxPlayNow = YES;                                    // a title the user chose plays right away
    [[[m_kv m_glv] GetKBView] AddItemFromSearchList:0 withsection:0 withdirectClipObject:c];
    gRfxPlayNow = NO;
    [c release];
}

// imports what is waiting in Documents/Import (normal library import).  Every imported song takes the place of the tile
// of the title that was loading (wid, 0: none) and is appended to the play queue; if nothing is playing it starts.
// The carousel is not narrowed to a folder.
- (void)ImportDownloadedFor:(long long)wid {
    if (m_kv == nil) return;
    GLView *glv = [m_kv m_glv];
    [MusicImporter ImportForServer:[m_kv m_sve]];
    NSArray *ids = [MusicImporter lastImportedClipIDs];
    if ([ids count] == 0) {
        RfxToast(@"Import fehlgeschlagen (Format nicht lesbar?).");
        if (wid != 0) [glv RemovePluginPlaceholder:wid];
        return;
    }
    int sid = [[m_kv m_sve] serverid];
    BOOL first = YES;
    for (NSNumber *n in ids) {
        [DEL LockDB:NO];
        DBOperations *db = [[DBOperations alloc] init];
        ClipObject *c = [[db GetSongWithID:[n longLongValue] withServerid:sid] retain];
        FolderObject *of = (c != nil) ? [db GetFolderForID:[c m_folderid] withserverid:[c m_serverid] withipodid:[c m_ipodid] withspotifyid:[c m_spotifyfolderid]] : nil;
        [db release];
        [DEL UnlockDB];
        if (c == nil) { [of release]; continue; }
        if (of != nil) {      // the DB row has no file / cover paths: build them like every other list does (else black cover, nothing to play)
            NSString *dir = [NSString stringWithFormat:@"%@%@/", [DEL CreateServerDir:[m_kv m_sve] withfolderobject:of], [DEL Buildfoldername:of]];
            [DEL BuildAndCheckFilePathes:c withfm:[NSFileManager defaultManager] withserverdir:dir withCheck:YES];
            [of release];
        }
        if (first && wid != 0) { [glv ReplacePluginPlaceholder:wid withClip:[c retain]]; }
        else [glv AddPicture:[c retain]];
        first = NO;
        [glv MarkClipPlayed:c];                       // inserted during a shuffle round: counts as played
        gRfxPlayNow = YES;
        [[glv GetKBView] AddItemFromSearchList:0 withsection:0 withdirectClipObject:c];
        gRfxPlayNow = NO;
        [c release];
    }
    if (first && wid != 0) [glv RemovePluginPlaceholder:wid];
}

- (void)FinishImportQueue:(BOOL)queue {
    [self ImportDownloadedFor:0];
}
@end

@interface RfxSourcesPanel : UIView <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate> {
    RfxPluginHost *m_host;
    UITextField *m_addr, *m_query;
    UILabel *m_status;
    UITableView *m_table;
    NSMutableArray *m_items;
    NSMutableArray *m_back;        // stack of NSDictionary {title, items}
    NSURLSessionDownloadTask *m_dltask;
    NSTimer *m_dltimer;
}
@end

@implementation RfxSourcesPanel

- (UIButton *)Btn:(NSString *)t x:(float)x y:(float)y w:(float)w tag:(int)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setFrame:CGRectMake(x, y, w, 40.0f)];
    [b setTitle:t forState:UIControlStateNormal];
    [b setTag:tag];
    [b addTarget:self action:@selector(ButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    return b;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    m_items = [[NSMutableArray alloc] init];
    m_back = [[NSMutableArray alloc] init];
    [self setBackgroundColor:[UIColor colorWithWhite:0.06f alpha:1.0f]];
    [self setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    float W = frame.size.width, y = 12.0f;
    [self Btn:@"Schließen" x:12 y:y w:110 tag:0];
    [self Btn:@"Verbinden" x:132 y:y w:110 tag:1];
    [self Btn:@"Anmelden" x:252 y:y w:110 tag:2];
    [self Btn:@"Abmelden" x:372 y:y w:110 tag:3];
    [self Btn:@"Zurück" x:492 y:y w:90 tag:4];
    y += 50.0f;
    m_query = [[UITextField alloc] initWithFrame:CGRectMake(12, y, W - 24, 36)];
    [m_query setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    [m_query setBorderStyle:UITextBorderStyleRoundedRect];
    [m_query setPlaceholder:@"Suchen (Titel, Interpret, Album)"];
    [m_query setReturnKeyType:UIReturnKeySearch];
    [m_query setDelegate:self];
    [self addSubview:m_query]; [m_query release];
    y += 44.0f;
    m_status = [[UILabel alloc] initWithFrame:CGRectMake(12, y, W - 24, 38)];
    [m_status setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    [m_status setNumberOfLines:2];
    [m_status setFont:[UIFont systemFontOfSize:14.0f]];
    [m_status setTextColor:[UIColor colorWithWhite:0.75f alpha:1.0f]];
    [m_status setText:@"Nicht verbunden."];
    [self addSubview:m_status]; [m_status release];
    y += 40.0f;
    m_table = [[UITableView alloc] initWithFrame:CGRectMake(0, y, W, frame.size.height - y) style:UITableViewStylePlain];
    [m_table setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [m_table setBackgroundColor:[UIColor clearColor]];
    [m_table setDataSource:self]; [m_table setDelegate:self];
    [self addSubview:m_table]; [m_table release];
    return self;
}

- (void)dealloc {
    [m_dltimer invalidate];
    [m_dltask cancel];
    [m_host release]; [m_items release]; [m_back release];
    [super dealloc];
}

- (void)Say:(NSString *)t { [m_status setText:t]; }

- (void)Alert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *vc = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    while ([vc presentedViewController] != nil) vc = [vc presentedViewController];
    [vc presentViewController:ac animated:YES completion:nil];
}

- (void)ButtonTapped:(UIButton *)b {
    switch ([b tag]) {
    case 0: [self removeFromSuperview]; break;
    case 1: [self Connect]; break;
    case 2: [self SignIn]; break;
    case 3: [self SignOut]; break;
    case 4: [self GoBack]; break;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; [self Search]; return YES; }

- (void)Connect { [self PickPlugin]; }

- (void)StartHost {
    [self Say:@"Verbinde ..."];
    [m_host initializeDone:^(NSString *e) {
        if (e != nil) { [self Say:[NSString stringWithFormat:@"Verbindung fehlgeschlagen: %@", e]]; return; }
        [self Say:[NSString stringWithFormat:@"Verbunden: %@", [m_host pluginName]]];
        [self ShowAuthStatus];
        if ([m_host has:@"browse"]) [self LoadRoot];
    }];
}

// plugins: every *.js in Documents/Plugins (Files app > Radio.fx > Plugins)
- (void)PickPlugin {
    NSDictionary *all = RfxPluginPaths();
    NSArray *names = [[all allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Plugin wählen"
        message:@"Die Plugins liegen im Ordner Plugins der App (Dateien-App). Dort kannst du sie auch bearbeiten." preferredStyle:UIAlertControllerStyleAlert];
    for (NSString *name in names) {
        NSString *p = [all objectForKey:name];
        [ac addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self ConnectJS:p name:name]; }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *vc = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    while ([vc presentedViewController] != nil) vc = [vc presentedViewController];
    [vc presentViewController:ac animated:YES completion:nil];
}

- (void)ConnectJS:(NSString *)path name:(NSString *)name {
    NSString *src = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (src == nil) { [self Say:@"Plugin-Datei nicht lesbar."]; return; }
    NSString *err = nil;
    RfxJSPlugin *js = [[RfxJSPlugin alloc] initWithScript:src pluginId:name error:&err];
    if (js == nil) { [self Say:[NSString stringWithFormat:@"Plugin-Fehler: %@", err]]; return; }
    [m_host release];
    m_host = [[RfxPluginHost alloc] initWithJS:js];
    [js release];
    [self StartHost];
}

- (void)ShowAuthStatus {
    if (![m_host has:@"auth"]) return;
    [m_host call:@"auth.status" params:nil done:^(id r, NSString *e) {
        if (e != nil) return;
        NSString *st = [r objectForKey:@"state"];
        NSString *acc = [[r objectForKey:@"account"] objectForKey:@"display_name"];
        [self Say:[NSString stringWithFormat:@"%@ — %@%@", [m_host pluginName], st, (acc != nil ? [@" " stringByAppendingString:acc] : @"")]];
    }];
}

- (void)SignIn {
    if (m_host == nil || ![m_host has:@"auth"]) { [self Say:@"Erst verbinden (das Plugin braucht die Fähigkeit \"auth\")."]; return; }
    [m_host call:@"auth.begin" params:nil done:^(id r, NSString *e) {
        if (e != nil) { [self Alert:@"Anmeldung" msg:e]; return; }
        if (![r isKindOfClass:[NSDictionary class]]) { [self Alert:@"Anmeldung" msg:@"Unerwartete Antwort des Plugins."]; return; }
        id uo = [r objectForKey:@"url"];   // JS null arrives as NSNull, not nil
        id io = [r objectForKey:@"instructions"];
        NSString *url = ([uo isKindOfClass:[NSString class]] && [uo length] > 0) ? uo : nil;
        NSString *ins = [io isKindOfClass:[NSString class]] ? io : nil;
        BOOL needInput = [[r objectForKey:@"expects_input"] boolValue];
        if (url == nil && !needInput) {   // the plugin did it itself (or needs setup): just tell the result
            [self Alert:@"Anmeldung" msg:(ins != nil ? ins : @"Fertig.")];
            [self ShowAuthStatus];
            return;
        }
        if (url != nil && [NSURL URLWithString:url] != nil) [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Anmeldung"
            message:[NSString stringWithFormat:@"%@\n\n%@%@",
                     (ins != nil ? ins : @""), (url != nil ? @"Die Seite wurde im Browser geöffnet. Füge hier den Code oder die Adresse ein, die du bekommst." : @"Gib hier ein, was das Plugin verlangt."),
                     (needInput ? @"" : @"\n(Das Plugin schließt die Anmeldung evtl. selbst ab.)")]
            preferredStyle:UIAlertControllerStyleAlert];
        [ac addTextFieldWithConfigurationHandler:^(UITextField *t) { [t setPlaceholder:@"Code / Adresse"]; [t setAutocapitalizationType:UITextAutocapitalizationTypeNone]; [t setAutocorrectionType:UITextAutocorrectionTypeNo]; }];
        [ac addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
        [ac addAction:[UIAlertAction actionWithTitle:@"Senden" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSString *in = [[[ac textFields] objectAtIndex:0] text];
            [m_host call:@"auth.complete" params:[NSDictionary dictionaryWithObject:(in != nil ? in : @"") forKey:@"input"] done:^(id r2, NSString *e2) {
                if (e2 != nil) { [self Alert:@"Anmeldung fehlgeschlagen" msg:e2]; return; }
                [self ShowAuthStatus];
            }];
        }]];
        UIViewController *vc = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        while ([vc presentedViewController] != nil) vc = [vc presentedViewController];
        [vc presentViewController:ac animated:YES completion:nil];
    }];
}

- (void)SignOut {
    if (m_host == nil || ![m_host has:@"auth"]) return;
    [m_host call:@"auth.sign_out" params:nil done:^(id r, NSString *e) { [self ShowAuthStatus]; }];
}

- (void)SetItems:(NSArray *)items {
    [m_items removeAllObjects];
    [m_items addObjectsFromArray:items];
    [m_table reloadData];
}

- (void)LoadRoot {
    [m_host call:@"browse.root" params:nil done:^(id r, NSString *e) {
        if (e != nil) { [self Say:[NSString stringWithFormat:@"Durchsuchen: %@", e]]; return; }
        [m_back removeAllObjects];
        [self SetItems:[r objectForKey:@"sections"]];
    }];
}

- (void)Search {
    NSString *q = [[m_query text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([q length] == 0 || m_host == nil) return;
    if (![m_host has:@"search"]) { [self Say:@"Dieses Plugin hat keine Suche."]; return; }
    [self Say:@"Suche ..."];
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:q, @"query", [NSNumber numberWithInt:0], @"offset", [NSNumber numberWithInt:40], @"limit", nil];
    [m_host call:@"search" params:p done:^(id r, NSString *e) {
        if (e != nil) { [self Say:[NSString stringWithFormat:@"Suche: %@", e]]; return; }
        NSMutableArray *all = [NSMutableArray array];
        for (NSDictionary *g in [r objectForKey:@"groups"]) [all addObjectsFromArray:[g objectForKey:@"items"]];
        [m_back addObject:[NSDictionary dictionaryWithObject:[NSArray arrayWithArray:m_items] forKey:@"items"]];
        [self SetItems:all];
        [self Say:[NSString stringWithFormat:@"%lu Treffer", (unsigned long)[all count]]];
    }];
}

- (void)GoBack {
    if ([m_back count] == 0) return;
    NSArray *prev = [[m_back lastObject] objectForKey:@"items"];
    [m_back removeLastObject];
    [self SetItems:prev];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)[m_items count]; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"src"];
    if (c == nil) {
        c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"src"] autorelease];
        [c setBackgroundColor:[UIColor clearColor]];
        [[c textLabel] setTextColor:[UIColor whiteColor]];
        [[c detailTextLabel] setTextColor:[UIColor colorWithWhite:0.65f alpha:1.0f]];
    }
    NSDictionary *it = [m_items objectAtIndex:[ip row]];
    BOOL browsable = [[it objectForKey:@"browsable"] boolValue];
    [[c textLabel] setText:[NSString stringWithFormat:@"%@%@", (browsable ? @"▸ " : @""), ([it objectForKey:@"title"] ? [it objectForKey:@"title"] : @"")]];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *k in [NSArray arrayWithObjects:@"artist", @"album", @"subtitle", nil]) {
        id v = [it objectForKey:k];
        if ([v isKindOfClass:[NSString class]] && [v length] > 0 && ![parts containsObject:v]) [parts addObject:v];
    }
    int ms = [[it objectForKey:@"duration_ms"] intValue];
    NSString *d = (ms > 0) ? [NSString stringWithFormat:@"  (%d:%02d)", ms / 60000, (ms / 1000) % 60] : @"";
    [[c detailTextLabel] setText:[[parts componentsJoinedByString:@" — "] stringByAppendingString:d]];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *it = [m_items objectAtIndex:[ip row]];
    NSString *ref = [it objectForKey:@"ref"];
    if (ref == nil) return;
    if ([[it objectForKey:@"browsable"] boolValue]) {
        NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:ref, @"ref", [NSNumber numberWithInt:0], @"offset", [NSNumber numberWithInt:200], @"limit", nil];
        [self Say:@"Lade ..."];
        [m_host call:@"browse.list" params:p done:^(id r, NSString *e) {
            if (e != nil) { [self Say:[NSString stringWithFormat:@"Durchsuchen: %@", e]]; return; }
            [m_back addObject:[NSDictionary dictionaryWithObject:[NSArray arrayWithArray:m_items] forKey:@"items"]];
            [self SetItems:[r objectForKey:@"items"]];
            [self Say:[it objectForKey:@"title"]];
        }];
        return;
    }
    if (![m_host has:@"resolve"]) return;
    [self Say:@"Hole Stream-Adresse ..."];
    [m_host call:@"track.resolve" params:[NSDictionary dictionaryWithObjectsAndKeys:ref, @"ref", @"play", @"purpose", nil] done:^(id r, NSString *e) {
        if (e != nil) { [self Say:[NSString stringWithFormat:@"Wiedergabe: %@", e]]; return; }
        id rd0 = [r isKindOfClass:[NSDictionary class]] ? [r objectForKey:@"redirect"] : nil;
        if ([rd0 isKindOfClass:[NSDictionary class]]) {
            [self Say:@"Suche bei anderen Quellen ..."];
            [[RfxPluginManager shared] ResolveRedirect:rd0 fallback:r exclude:[m_host pluginId] done:^(id r2, NSString *e2) {
                if (e2 != nil) { [self Say:e2]; return; }
                [self PlayItem:it resolved:r2];
            }];
            return;
        }
        [self PlayItem:it resolved:r];
    }];
}


#pragma mark playing a resolved item: load into the cache, then queue it like any local song

- (void)FinishItem:(NSDictionary *)it file:(NSString *)file cover:(NSString *)cover hashId:(long long)hid {
    [[RfxPluginManager shared] FinishImportQueue:YES];
    [self removeFromSuperview];
}

- (void)TickDownload {
    if (m_dltask == nil) return;
    long long got = [m_dltask countOfBytesReceived], all = [m_dltask countOfBytesExpectedToReceive];
    if (all > 0) [self Say:[NSString stringWithFormat:@"Lade ... %.1f / %.1f MB", got / 1048576.0, all / 1048576.0]];
    else [self Say:[NSString stringWithFormat:@"Lade ... %.1f MB", got / 1048576.0]];
}

- (void)PlayItem:(NSDictionary *)it resolved:(NSDictionary *)r {
    NSURL *url = [NSURL URLWithString:([r objectForKey:@"url"] ? [r objectForKey:@"url"] : @"")];
    if (url == nil) { [self Say:@"Ungültige Stream-Adresse."]; return; }
    NSString *pid = ([m_host pluginId] != nil) ? [m_host pluginId] : @"plugin";
    // everything lands in the main "Imported" folder (files directly in Documents/Import)
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *dir = RfxImportDir(docs);
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *hex = nil;
    unsigned long long h64 = RfxHash64([NSString stringWithFormat:@"%@|%@", pid, [it objectForKey:@"ref"]], &hex);
    long long hid = -(long long)(h64 & 0x3fffffffffULL) - 100000;
    NSString *ext = [[url path] pathExtension];
    if ([ext length] == 0 || [ext length] > 5) ext = [[r objectForKey:@"format"] objectForKey:@"codec"];
    if ([ext length] == 0) ext = @"audio";
    NSString *stem = [NSString stringWithFormat:@"%@ - %@", [[it objectForKey:@"artist"] length] ? [it objectForKey:@"artist"] : @"Unknown Artist", [it objectForKey:@"title"] ? [it objectForKey:@"title"] : hex];
    stem = [[stem stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString *file = [dir stringByAppendingPathComponent:[stem stringByAppendingPathExtension:ext]];
    NSString *cover = [dir stringByAppendingPathComponent:[stem stringByAppendingPathExtension:@"jpg"]];
    NSFileManager *fm = [NSFileManager defaultManager];

    void (^loadAudio)(void) = [[^{
        if ([fm fileExistsAtPath:file]) {
            [self FinishItem:it file:file cover:([fm fileExistsAtPath:cover] ? cover : nil) hashId:hid];
            return;
        }
        [self Say:@"Lade ..."];
        m_dltask = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *tmp, NSURLResponse *resp, NSError *err) {
            NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 200;
            NSString *msg = nil;
            if (err != nil) msg = [err localizedDescription];
            else if (code < 200 || code >= 300) msg = [NSString stringWithFormat:@"HTTP %ld", (long)code];
            else if (![[NSFileManager defaultManager] moveItemAtURL:tmp toURL:[NSURL fileURLWithPath:file] error:nil]) msg = @"Datei konnte nicht abgelegt werden.";
            dispatch_async(dispatch_get_main_queue(), ^{
                [m_dltimer invalidate]; m_dltimer = nil; m_dltask = nil;
                if (msg != nil) { if ([err code] != NSURLErrorCancelled) [self Say:[NSString stringWithFormat:@"Laden fehlgeschlagen: %@", msg]]; return; }
                [self FinishItem:it file:file cover:([fm fileExistsAtPath:cover] ? cover : nil) hashId:hid];
            });
        }];
        m_dltimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(TickDownload) userInfo:nil repeats:YES];
        [m_dltask resume];
    } copy] autorelease];

    NSString *art = [it objectForKey:@"art"];
    if ([art length] > 0 && [NSURL URLWithString:art] != nil && ![fm fileExistsAtPath:cover]) {
        [self Say:@"Lade Cover ..."];
        NSURL *au = [NSURL URLWithString:art];
        [[[NSURLSession sharedSession] dataTaskWithURL:au completionHandler:^(NSData *d, NSURLResponse *rs, NSError *e) {
            if (d != nil && e == nil && [UIImage imageWithData:d] != nil) [d writeToFile:cover atomically:YES];
            dispatch_async(dispatch_get_main_queue(), ^{ loadAudio(); });
        }] resume];
    } else {
        loadAudio();
    }
}

@end

@implementation KioskView
@synthesize m_lastsongdragged, m_tenmintimer, m_lastshownNoCoverFor, m_didstopmanual, m_resetfadeover;
@synthesize m_clipStartTime, m_pausebegintime, m_errorplayingsong, g_scaling, mMCMixer, m_draggingobj;
@synthesize m_stopsecondthread, m_willplayradio, m_trailerimagetime, m_copynotifyflag, m_limitduration;
@synthesize m_limitinittime, m_ordering, m_lastvolume, m_freespace, m_30secsearchInitTime, m_crossfadeInitTime;
@synthesize m_crossfadeDuration, m_presongDuration, m_presongInitTime, m_shrinkdevider, m_rotateclip;
@synthesize m_updateunzipped, m_autoselected, m_first_start, cancelcopy, m_fadingover, m_sve, m_clips;
@synthesize m_cantransform, m_glv, m_ignoreXdiff;

#pragma mark - lifecycle

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        mMCMixer = [[MultichannelMixerController alloc] init];
        m_lastsongdragged = 0;
        m_activateView = nil;
        m_dragginposforremotecmds = -1;
        m_didstopmanual = NO;
        m_draggingorigpos = -1;
        m_errorplayingsong = NO;
        m_wdrplayer = nil;
        m_angle = 0;
        cancelcopy = NO;
        startTime = -1.0;
        m_threadrunning[0] = m_threadrunning[1] = NO;
        m_cliptorotate = nil;
        m_foldertimer = nil;
        m_firstcheck = YES;
        m_fadingover = NO;
        m_blackview = nil;
        m_first_start = YES;
        m_autoselected = YES;
        m_updateunzipped = NO;
        m_rotateclip = NO;
        m_shrinkdevider = NO;
        m_presongInitTime = -1.0;
        m_presongDuration = -1.0;
        m_crossfadeDuration = -1.0;
        m_crossfadeInitTime = -1.0;
        m_shutdowntimer = nil;
        m_shutdown = NO;
        m_freespace = YES;
        m_lastvolume = 0;
        m_ordering = NO;
        m_draggingrunningsong = NO;
        m_helpPicture = nil;
        m_fiveoclockflag = NO;
        m_limitinittime = -1.0;
        m_copynotifyflag = NO;
        [self setMultipleTouchEnabled:NO];
        m_trailerimagetime = 0;
        m_blackoverlay = nil;
        m_songcounter = 0;
        m_jingleindex = 0;
        m_crossfadetime = 5.0f;
        m_curfade = 5.0f;
        m_playingjingle = NO;
        m_stopsecondthread = NO;
        m_enableddebuggingtext = NO;
        m_resetangle = NO;
        m_pausebegintime = -1.0;
        m_resetfadeover = -1.0;
        m_lastshownNoCoverFor = nil;
        m_waitview = nil;
        m_blackborderview = nil;
        m_showfirstsongInfos = NO;
        m_loadingscreen = nil;
        m_loadinglabel = nil;
        m_lastCDXDiff = 0;
        m_ignoreXdiff = NO;
        m_tenmintimer = CACurrentMediaTime();
        m_colorarray = [[NSArray arrayWithObjects:
            [NSNumber numberWithInt:0x4ebbc3], [NSNumber numberWithInt:0x174244], [NSNumber numberWithInt:0x7accd2],
            [NSNumber numberWithInt:0x008cd1], [NSNumber numberWithInt:0x023047], [NSNumber numberWithInt:0x40a9dd],
            [NSNumber numberWithInt:0x2e3b8c], [NSNumber numberWithInt:0x151b3e], [NSNumber numberWithInt:0x626ca9],
            [NSNumber numberWithInt:0x674592], [NSNumber numberWithInt:0x291c3a], [NSNumber numberWithInt:0x8d74ad],
            [NSNumber numberWithInt:0xb04287], [NSNumber numberWithInt:0x321326], [NSNumber numberWithInt:0xbf659d],
            [NSNumber numberWithInt:0xb90f1d], [NSNumber numberWithInt:0x39080c], [NSNumber numberWithInt:0xcb4b56],
            [NSNumber numberWithInt:0xd9800b], [NSNumber numberWithInt:0x362105], [NSNumber numberWithInt:0xe3a048],
            [NSNumber numberWithInt:0xcfcc00], [NSNumber numberWithInt:0x3d3c01], [NSNumber numberWithInt:0xdfdd57],
            [NSNumber numberWithInt:0x7db61c], [NSNumber numberWithInt:0x2d400d], [NSNumber numberWithInt:0xa9cf69],
            [NSNumber numberWithInt:0x037637], [NSNumber numberWithInt:0x013418], [NSNumber numberWithInt:0x59a57b], nil] retain];

        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        // original: floatForKey:@"keykioskvolume", NaN -> 0.3f.  A missing key (fresh install) would give
        // silence; 0.3f (the original's own fallback value) is used instead -- see DEVIATIONS.md.
        float vol = ([defs objectForKey:@"keykioskvolume"] == nil) ? 0.3f : [defs floatForKey:@"keykioskvolume"];
        if (vol != vol) vol = 0.3f;
        [self setM_lastvolume:vol];
        if ([self m_lastvolume] < 0) [self setM_lastvolume:0.0f];
        if ([self m_lastvolume] > 1.0f) [self setM_lastvolume:1.0f];
        // original "keyownvolume" state: the app gain stays at 1.0 and the system volume decides the loudness
        if ([DEL m_useownvolume] != 0) [self setM_lastvolume:1.0f];

        border = (((ISIPAD ? -86 : -60) + (ISIPAD ? 0x7e : 0x5a)) >> 1);
        [self setBackgroundColor:[UIColor colorWithWhite:0.0f alpha:1.0f]];
        m_clips = [[NSMutableArray alloc] init];

        ServerComm *sc = [DEL GetServerComm];
        m_sve = [sc GetChoosenRfxServer:nil];
        if (m_sve == nil) {
            ServerEntry *def = [[ServerEntry alloc] init];
            [def setServername:@"cloud01.rfx.tobit.com"];
            // original also stored a hard-coded password for the dead server here -- not needed, omitted
            [def setStateFlags:[DEL ModifyStateFlags:[def StateFlags]]];
            [def setStateFlags:([def StateFlags] | 0x400)];
            [def setStateFlags:([def StateFlags] | 0x8000000)];
            [def setChoosen:1];
            [sc AddMTServer:def];
            [sc SaveServerList];
            [def release];
            m_sve = [sc GetChoosenRfxServer:nil];
            if ([DEL GetDeliveredStatus] == 0)
                [DEL SetDeliveredStatus];
        }
        // DEVIATION: match the server entry to the local library (see ServerComm / DEVIATIONS.md)
        if ([sc AdaptToLocalLibrary]) {
            [m_sve release];
            m_sve = [sc GetChoosenRfxServer:nil];
        }
        // DEVIATION: demo songs for a device without music (only when the library is empty)
        [MusicImporter ImportForServer:m_sve];      // Documents/Import -> library
        [[RfxPluginManager shared] setKiosk:self];
        [[RfxPluginManager shared] StartAutoload];  // plugins chosen under Quellen > Autostart
        [TestLibrary RemoveDemoForServer:m_sve];
        m_trailerimagetime = [m_sve trailerimagetime];

        CGSize pad = [DEL GetiPadSize];
        m_divider = [[UIView alloc] initWithFrame:[self GetDividerFrame:pad]];
        [m_divider setBackgroundColor:[UIColor colorWithWhite:0.15f alpha:1.0f]];
        [self addSubview:m_divider];
        [m_divider release];

        m_label = [[UILabel alloc] initWithFrame:[self GetDebugLabelFrame:pad]];
        [m_label setTextColor:[UIColor colorWithWhite:0.2f alpha:1.0f]];
        [m_label setBackgroundColor:[UIColor clearColor]];
        [m_label setTextAlignment:NSTextAlignmentRight];
        [m_label setFont:[UIFont systemFontOfSize:(ISIPAD ? 17.0f : 15.0f)]];
        [self addSubview:m_label];
        [m_label release];
        [self SetDebugText:@" "];

        // port addition: small always-on sample-rate readout (file rate / engine rate / device rate)
        m_ratelabel = [[UILabel alloc] initWithFrame:CGRectMake(12.0f, 6.0f, 520.0f, 18.0f)];
        [m_ratelabel setTextColor:[UIColor colorWithWhite:0.85f alpha:1.0f]];
        [m_ratelabel setBackgroundColor:[UIColor clearColor]];
        [m_ratelabel setFont:[UIFont fontWithName:@"Courier" size:12.0f]];
        [m_ratelabel setText:@"sample rate: -"];
        [m_ratelabel setUserInteractionEnabled:NO];
        [m_ratelabel setHidden:![[NSUserDefaults standardUserDefaults] boolForKey:@"RfxDevRateLabel"]];
        [self addSubview:m_ratelabel];
        [m_ratelabel release];
        {
            // hidden dev menu: five quick taps in the top left corner
            UITapGestureRecognizer *dev = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ShowDevMenu)];
            [dev setNumberOfTapsRequired:5];
            [dev setCancelsTouchesInView:NO];
            [dev setDelaysTouchesBegan:NO];
            [dev setDelaysTouchesEnded:NO];
            [dev setDelegate:(id)self];
            [self addGestureRecognizer:dev];
            [dev release];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(RateInfo:) name:@"RfxSampleRateInfo" object:nil];

        m_blackborderview = [[UIView alloc] initWithFrame:[self GetBlackBorderViewRect]];
        [m_blackborderview setBackgroundColor:[UIColor blackColor]];
        [self addSubview:m_blackborderview];
        [m_blackborderview setUserInteractionEnabled:NO];
        [m_blackborderview release];

        m_glv = [[GLView alloc] initWithFrame:[self GetOpenGLFrame:pad]];
        [self addSubview:m_glv];
        [m_glv release];
        [m_glv SetParent:self];
        [m_glv StartPreScrollerThread];
        [m_glv setM_lastflags:-1];
        NSInteger lastdirect = [defs integerForKey:@"k_lastdirctchannelid"];
        m_willplayradio = (lastdirect > 0);

        UIImage *tslogo = [UIImage imageNamed:@"ts-text.png"];
        m_tslogo = nil;
        {
            CGSize ls = [tslogo size];
            CGFloat sc2 = ISIPAD ? 1.0f : 1.5f;
            m_tslogo = [[UIImageView alloc] initWithFrame:CGRectMake(
                ([self frame].size.width - ls.width / sc2) * 0.5f,
                (([self frame].size.height + [m_divider frame].size.height) - BARH) +
                    ((BARH - [m_divider frame].size.height) - ls.height / sc2) * 0.5f,
                ls.width / sc2, ls.height / sc2)];
            [m_tslogo setImage:tslogo];
            [m_tslogo setAlpha:0.0f];
            [self addSubview:m_tslogo];
            [m_tslogo release];
        }
        [m_glv AddKBView];
        [m_glv ExecuteServerFlags:[NSNumber numberWithInt:0]];
        m_willplayradio = NO;
        [self CreateFonts];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ErrorPlayingSong)
            name:@"MCM_MSG_ERROR_PLAYING_FILE" object:nil];
        [self CheckLoadingscreen];
        [self FolderTimerfunc:nil];
        m_first_start = NO;
        [NSThread detachNewThreadSelector:@selector(TimerThread) toTarget:self withObject:nil];
        {
            CADisplayLink *rl = [CADisplayLink displayLinkWithTarget:self selector:@selector(RotationFrame)];
            [rl setPreferredFramesPerSecond:20];
            [rl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
        if (m_sve != nil)
            [self performSelector:@selector(StartThread) withObject:nil afterDelay:0];

        m_blackoverlay = [[UIView alloc] initWithFrame:[self GetBlackOverLayViewRect]];
        [m_blackoverlay setBackgroundColor:[UIColor blackColor]];
        [m_blackoverlay setAlpha:0.0f];
        [self addSubview:m_blackoverlay];
        [m_blackoverlay release];
        if (lastdirect >= 1)
            [self FadeQueueToBlack:YES];

        m_pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(scaleVolume:)];
        [self addGestureRecognizer:m_pinchGesture];
        [m_pinchGesture release];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self EndFunction];
    [self CheckPendingSong];
    [self setM_lastshownNoCoverFor:nil];
    if (mMCMixer != nil) { [mMCMixer release]; mMCMixer = nil; }
    if (m_sve != nil) { [m_sve release]; m_sve = nil; }
    if (m_colorarray != nil) { [m_colorarray release]; m_colorarray = nil; }
    if (m_titlefont != nil) { [m_titlefont release]; m_titlefont = nil; }
    [DEL setM_kioskpresent:NO];
    [super dealloc];
}

- (void)CreateFonts {
    m_titlefont = [[UIFont fontWithName:@"TrebuchetMS-Bold" size:20.0f] retain];
    if (m_titlefont == nil)
        m_titlefont = [[UIFont boldSystemFontOfSize:20.0f] retain];
}

#pragma mark - simple accessors

- (GLView *)m_glv { return m_glv; }
- (GLView *)GetGLView { return m_glv; }
- (id)GetBlackView { return m_blackview; }
- (BOOL)ShowingLoadingscreen { return m_loadingscreen != nil; }
- (BOOL)IsThreadRunning { return m_threadrunning[0] || m_threadrunning[1]; }
- (float)GetBlackOverlayAlpha { return [m_blackoverlay alpha]; }
- (void)StopOverviewTimer {}
- (void)AirplayRestart {}
- (void)SendChangesToRemoteApps {}
- (void)SetRadioAniVar:(int)radioAniVar {}
- (void)SyncSVEwithUserdef {}
- (void)RefreshSettings { [[m_glv GetKBView] RefreshSettings]; }

- (void)StartThread {
    // original: MarkFilesOnce / StartCopyThread: (replication from the server); nothing to do offline
    [self SetDebugText:@""];
}

- (void)RateInfo:(NSNotification *)n {
    NSString *t = [[n userInfo] objectForKey:@"text"];
    [m_ratelabel setText:t];
    if (![m_ratelabel isHidden]) [self bringSubviewToFront:m_ratelabel];
    UILabel *dl = (UILabel *)[[self viewWithTag:7741] viewWithTag:7746];
    if (dl != nil) [dl setText:t];
    [m_lastrateinfo release];
    m_lastrateinfo = [t copy];
}

#pragma mark - hidden dev menu (5 taps in the top left corner)

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    if (![g isKindOfClass:[UITapGestureRecognizer class]] || [(UITapGestureRecognizer *)g numberOfTapsRequired] != 5) return YES;
    CGPoint p = [touch locationInView:self];
    return p.x < 110.0f && p.y < 110.0f && [self viewWithTag:7741] == nil;
}

- (void)ShowDevMenu {
    if ([self viewWithTag:7741] != nil) return;
    CGRect b = [self bounds];
    UIView *ov = [[UIView alloc] initWithFrame:b];
    [ov setTag:7741];
    [ov setBackgroundColor:[UIColor colorWithWhite:0.0f alpha:0.94f]];
    [ov setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:b];
    [sv setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [ov addSubview:sv];
    float cx = b.size.width * 0.5f, y = 70.0f, rowW = 560.0f;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y, rowW, 34.0f)];
    [title setText:@"Dev-Menü"]; [title setTextColor:[UIColor whiteColor]]; [title setBackgroundColor:[UIColor clearColor]];
    [title setFont:[UIFont systemFontOfSize:26.0f]]; [title setTextAlignment:NSTextAlignmentCenter];
    [sv addSubview:title]; [title release];
    y += 70.0f;
    NSArray *rows = [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"Schwarzer Rahmen um die Cover", @"RfxDevCoverBorder", [NSNumber numberWithInt:1], nil],
        [NSArray arrayWithObjects:@"Sample-Rate-Anzeige auf dem Bildschirm", @"RfxDevRateLabel", [NSNumber numberWithInt:2], nil],
        [NSArray arrayWithObjects:@"Bit-Perfect: Lautstärke dem System überlassen", @"RfxDevNoVolume", [NSNumber numberWithInt:3], nil],
        [NSArray arrayWithObjects:@"Alle versteckten Buttons aktivieren", @"RfxDevAllButtons", [NSNumber numberWithInt:4], nil],
        [NSArray arrayWithObjects:@"Beta-Look (erste Djukebox)", @"RfxDevBetaLook", [NSNumber numberWithInt:5], nil],
        [NSArray arrayWithObjects:@"Hintergrund: Musikvideo-Ausschnitt (eigene Clips offline)", @"RfxDevBackdrop", [NSNumber numberWithInt:6], nil], nil];
    for (NSArray *r in rows) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y, rowW - 80.0f, 31.0f)];
        [l setText:[r objectAtIndex:0]]; [l setTextColor:[UIColor whiteColor]]; [l setBackgroundColor:[UIColor clearColor]];
        [l setFont:[UIFont systemFontOfSize:19.0f]];
        [sv addSubview:l]; [l release];
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(cx + rowW * 0.5f - 51.0f, y, 51.0f, 31.0f)];
        id pref = [[NSUserDefaults standardUserDefaults] objectForKey:[r objectAtIndex:1]];
        BOOL on = (pref == nil) ? NO : [pref boolValue];
        [sw setOn:on];
        [sw setTag:7750 + [[r objectAtIndex:2] intValue]];
        [sw addTarget:self action:@selector(DevSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        [sv addSubview:sw]; [sw release];
        y += 46.0f;
    }
    {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y, 230.0f, 31.0f)];
        [l setText:@"Rahmenbreite"]; [l setTextColor:[UIColor whiteColor]]; [l setBackgroundColor:[UIColor clearColor]];
        [l setFont:[UIFont systemFontOfSize:19.0f]];
        [sv addSubview:l]; [l release];
        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f + 240.0f, y, rowW - 240.0f, 31.0f)];
        [sl setMinimumValue:0.0f]; [sl setMaximumValue:8.0f];
        id wp = [[NSUserDefaults standardUserDefaults] objectForKey:@"RfxDevCoverBorderWidth"];
        [sl setValue:(wp == nil ? 2.0f : [wp floatValue])];
        [sl setTag:7760];
        [sl addTarget:self action:@selector(DevSliderDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [sv addSubview:sl]; [sl release];
        y += 52.0f;
    }
    {
        float cf = RfxCrossfadeSeconds();
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y, 230.0f, 31.0f)];
        [l setTag:7762];
        [l setText:[NSString stringWithFormat:@"Überblendzeit %.1f s", cf]]; [l setTextColor:[UIColor whiteColor]]; [l setBackgroundColor:[UIColor clearColor]];
        [l setFont:[UIFont systemFontOfSize:19.0f]];
        [sv addSubview:l]; [l release];
        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f + 240.0f, y, rowW - 240.0f, 31.0f)];
        [sl setMinimumValue:1.0f]; [sl setMaximumValue:12.0f];
        [sl setValue:cf];
        [sl setTag:7761];
        [sl addTarget:self action:@selector(DevSliderMoved:) forControlEvents:UIControlEventValueChanged];
        [sl addTarget:self action:@selector(DevSliderDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [sv addSubview:sl]; [sl release];
        y += 46.0f;
    }
    {   // effect of the playing cover: < name >
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y, 150.0f, 31.0f)];
        [l setText:@"Cover-Effekt"]; [l setTextColor:[UIColor whiteColor]]; [l setBackgroundColor:[UIColor clearColor]];
        [l setFont:[UIFont systemFontOfSize:19.0f]];
        [sv addSubview:l]; [l release];
        UIButton *pb = [UIButton buttonWithType:UIButtonTypeSystem];
        [pb setFrame:CGRectMake(cx - rowW * 0.5f + 150.0f, y - 3.0f, 44.0f, 37.0f)];
        [pb setTitle:@"\u25C0" forState:UIControlStateNormal]; [pb setTag:7776];
        [pb addTarget:self action:@selector(DevFXStep:) forControlEvents:UIControlEventTouchUpInside];
        [sv addSubview:pb];
        UILabel *nm = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f + 194.0f, y, rowW - 194.0f - 44.0f, 31.0f)];
        [nm setTag:7775]; [nm setText:RfxBeatFXName(gRfxBeatFX)]; [nm setTextColor:[UIColor colorWithRed:0.55f green:0.85f blue:1.0f alpha:1.0f]];
        [nm setBackgroundColor:[UIColor clearColor]]; [nm setFont:[UIFont systemFontOfSize:17.0f]]; [nm setTextAlignment:NSTextAlignmentCenter];
        [nm setAdjustsFontSizeToFitWidth:YES];
        [sv addSubview:nm]; [nm release];
        UIButton *nb = [UIButton buttonWithType:UIButtonTypeSystem];
        [nb setFrame:CGRectMake(cx + rowW * 0.5f - 44.0f, y - 3.0f, 44.0f, 37.0f)];
        [nb setTitle:@"\u25B6" forState:UIControlStateNormal]; [nb setTag:7777];
        [nb addTarget:self action:@selector(DevFXStep:) forControlEvents:UIControlEventTouchUpInside];
        [sv addSubview:nb];
        y += 46.0f;
    }
    {
        NSArray *names = [[RfxPluginManager shared] AllNames];
        UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y + 8.0f, rowW, 26.0f)];
        [h setText:([names count] ? @"Plugins (Ordner Plugins in der Dateien-App)" : @"Keine Plugins im Ordner Plugins gefunden")];
        [h setTextColor:[UIColor colorWithWhite:0.7f alpha:1.0f]]; [h setBackgroundColor:[UIColor clearColor]];
        [h setFont:[UIFont systemFontOfSize:15.0f]];
        [sv addSubview:h]; [h release];
        y += 40.0f;
        for (int i = 0; i < (int)[names count]; i++) {
            NSString *n = [names objectAtIndex:i];
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f + 84.0f, y, rowW - 164.0f, 31.0f)];
            [l setText:n]; [l setTextColor:[UIColor whiteColor]]; [l setBackgroundColor:[UIColor clearColor]];
            [l setFont:[UIFont systemFontOfSize:19.0f]];
            [sv addSubview:l]; [l release];
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(cx + rowW * 0.5f - 51.0f, y, 51.0f, 31.0f)];
            [sw setOn:[[RfxPluginManager shared] IsAutostart:n]];
            [sw setTag:7800 + i];
            [sw addTarget:self action:@selector(DevPluginChanged:) forControlEvents:UIControlEventValueChanged];
            [sv addSubview:sw]; [sw release];
            for (int k = 0; k < 2; k++) {       // order of the providers: up / down
                UIButton *ab = [UIButton buttonWithType:UIButtonTypeSystem];
                [ab setFrame:CGRectMake(cx - rowW * 0.5f + 40.0f * k, y - 3.0f, 40.0f, 37.0f)];
                [ab setTitle:(k == 0 ? @"\u25B2" : @"\u25BC") forState:UIControlStateNormal];
                [[ab titleLabel] setFont:[UIFont systemFontOfSize:20.0f]];
                [ab setEnabled:(k == 0 ? i > 0 : i < (int)[names count] - 1)];
                [ab setTag:(k == 0 ? 7900 : 7950) + i];
                [ab addTarget:self action:@selector(DevPluginMove:) forControlEvents:UIControlEventTouchUpInside];
                [sv addSubview:ab];
            }
            y += 46.0f;
        }
    }
    UILabel *info = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y + 10.0f, rowW, 40.0f)];
    [info setTag:7746];
    [info setText:(m_lastrateinfo != nil ? m_lastrateinfo : @"Sample-Rate: -")];
    [info setTextColor:[UIColor colorWithWhite:0.8f alpha:1.0f]]; [info setBackgroundColor:[UIColor clearColor]];
    [info setFont:[UIFont fontWithName:@"Courier" size:14.0f]]; [info setNumberOfLines:2];
    [sv addSubview:info]; [info release];
    {
        UIButton *qb = [UIButton buttonWithType:UIButtonTypeSystem];
        [qb setFrame:CGRectMake(cx - rowW * 0.5f, y + 60.0f, rowW, 44.0f)];
        [qb setTitle:@"Quellen durchsuchen / anmelden" forState:UIControlStateNormal];
        [[qb titleLabel] setFont:[UIFont systemFontOfSize:19.0f]];
        [qb addTarget:self action:@selector(OpenSourcesPanel) forControlEvents:UIControlEventTouchUpInside];
        [sv addSubview:qb];
    }
    [sv setContentSize:CGSizeMake(b.size.width, y + 140.0f)];
    [sv release];
    UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
    [x setFrame:CGRectMake(b.size.width - 70.0f, 20.0f, 50.0f, 50.0f)];
    [x setTitle:@"\u2715" forState:UIControlStateNormal];
    [x setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [[x titleLabel] setFont:[UIFont systemFontOfSize:26.0f]];
    [x setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin];
    [x addTarget:self action:@selector(CloseDevMenu) forControlEvents:UIControlEventTouchUpInside];
    [sv addSubview:x];
    [self addSubview:ov];
    [ov release];
}

- (void)DevSwitchChanged:(UISwitch *)sw {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    switch ([sw tag]) {
    case 7751:
        [d setBool:[sw isOn] forKey:@"RfxDevCoverBorder"]; [d synchronize];
        [m_glv RefreshCoverTextures];
        break;
    case 7752:
        [d setBool:[sw isOn] forKey:@"RfxDevRateLabel"]; [d synchronize];
        [m_ratelabel setHidden:![sw isOn]];
        if ([sw isOn]) [self bringSubviewToFront:m_ratelabel];
        break;
    case 7753:
        [d setBool:[sw isOn] forKey:@"RfxDevNoVolume"]; [d synchronize];
        // same state change as the original "keyownvolume" setting: no app slider, app gain 1.0, system volume rules
        [DEL GetUseOwnVolume:nil];
        if ([DEL m_useownvolume] != 0) {
            [self setM_lastvolume:1.0f];
        } else {
            float sv = ([d objectForKey:@"keykioskvolume"] == nil) ? 0.3f : [d floatForKey:@"keykioskvolume"];
            if (sv != sv || sv < 0) sv = 0.3f;
            [self setM_lastvolume:fminf(sv, 1.0f)];
        }
        [self SetPlayerVolume:[self m_lastvolume]];
        [[m_glv GetKBView] InstallVolumeSlider:[DEL GetiPadSize]];
        [[m_glv GetKBView] SetVolSlider:[self m_lastvolume]];
        [m_glv ExecuteServerFlags:[NSNumber numberWithInt:1]];
        break;
    case 7755:
        [d setBool:[sw isOn] forKey:@"RfxDevBetaLook"]; [d synchronize];
        gRfxBetaLook = [sw isOn];
        [m_glv SetUpTippRects];
        [m_glv drawView];
        break;
    case 7756:
        [d setBool:[sw isOn] forKey:@"RfxDevBackdrop"]; [d synchronize];
        if (![sw isOn]) [[RfxBackdrop shared] clear];
        else if ([self IsPlayingClips] && [[self m_clips] count] > 0) [self UpdateBackdropForClip:[[self m_clips] objectAtIndex:0]];
        break;
    case 7754:
        [d setBool:[sw isOn] forKey:@"RfxDevAllButtons"]; [d synchronize];
        [m_glv ExecuteServerFlags:[NSNumber numberWithInt:1]];
        break;
    }
    [self bringSubviewToFront:[self viewWithTag:7741]];
}

- (void)DevFXStep:(UIButton *)bt {
    int n = RfxBeatFXCount();
    gRfxBeatFX = (gRfxBeatFX + ([bt tag] == 7777 ? 1 : n - 1)) % n;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:gRfxBeatFX forKey:@"RfxDevBeatFX"]; [d synchronize];
    UILabel *nm = (UILabel *)[[self viewWithTag:7741] viewWithTag:7775];
    [nm setText:RfxBeatFXName(gRfxBeatFX)];
}

- (void)DevSliderMoved:(UISlider *)sl {
    if ([sl tag] != 7761) return;
    UILabel *l = (UILabel *)[[self viewWithTag:7741] viewWithTag:7762];
    [l setText:[NSString stringWithFormat:@"Überblendzeit %.1f s", [sl value]]];
}

- (void)DevSliderDone:(UISlider *)sl {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([sl tag] == 7761) {
        // takes effect with the next song (the timers of the running song are already set)
        [d setFloat:roundf([sl value] * 2.0f) / 2.0f forKey:@"RfxDevCrossfade"]; [d synchronize];
        return;
    }
    [d setFloat:[sl value] forKey:@"RfxDevCoverBorderWidth"]; [d synchronize];
    [m_glv RefreshCoverTextures];
}

// one switch per detected plugin script (Documents/Plugins/*.js)
- (void)DevPluginChanged:(UISwitch *)sw {
    NSArray *names = [[RfxPluginManager shared] AllNames];
    int i = (int)[sw tag] - 7800;
    if (i < 0 || i >= (int)[names count]) return;
    NSString *n = [names objectAtIndex:i];
    [[RfxPluginManager shared] SetAutostart:[sw isOn] forName:n];
    RfxToast([NSString stringWithFormat:@"%@: %@", n, ([sw isOn] ? @"an (geladen, auch beim nächsten Start)" : @"aus")]);
}

- (void)DevPluginMove:(UIButton *)bt {
    NSArray *names = [[RfxPluginManager shared] AllNames];
    int t = (int)[bt tag], up = (t < 7950);
    int i = t - (up ? 7900 : 7950);
    if (i < 0 || i >= (int)[names count]) return;
    [[RfxPluginManager shared] MovePlugin:[names objectAtIndex:i] by:(up ? -1 : 1)];
    [self CloseDevMenu];
    [self ShowDevMenu];            // rebuild with the new order (search sections follow the next search)
}

- (void)OpenSourcesPanel {
    if ([self viewWithTag:7770] != nil) return;
    RfxSourcesPanel *p = [[RfxSourcesPanel alloc] initWithFrame:[self bounds]];
    [p setTag:7770];
    [self addSubview:p];
    [p release];
}

- (void)CloseDevMenu {
    [[self viewWithTag:7741] removeFromSuperview];
}

- (void)SetDebugText:(NSString *)debugText {
    if (([[self m_sve] StateFlags] & 0x400) == 0) return;
    [m_label setText:debugText];
}

- (void)CheckDebugTextEnabled {
    if ([@"Debuggingtexts enabled" isEqualToString:[m_label text]])
        [self SetDebugText:@""];
}

- (void)ExternDraw:(int)externDraw {
    [self performSelectorOnMainThread:@selector(ExternDrawInMT:) withObject:[NSNumber numberWithInt:externDraw] waitUntilDone:YES];
}

- (void)ExternDrawInMT:(NSNumber *)externDrawInMT {
    [m_glv setM_radioanivar:[externDrawInMT intValue]];
    [m_glv drawView];
}

#pragma mark - layout

- (CGRect)GetOpenGLFrame:(CGSize)openGLFrame {
    return CGRectMake(0, 0, openGLFrame.width, openGLFrame.height - (ISIPAD ? 126.0f : 90.0f));
}

- (CGRect)GetDividerFrame:(CGSize)dividerFrame {
    return CGRectMake(0, dividerFrame.height - (ISIPAD ? 126.0f : 90.0f), dividerFrame.width, 4.0f);
}

- (CGRect)GetDebugLabelFrame:(CGSize)debugLabelFrame {
    if (ISIPAD)
        return CGRectMake(debugLabelFrame.width - 340.0f, debugLabelFrame.height - 40.0f, 320.0f, 20.0f);
    return CGRectMake(debugLabelFrame.width - 290.0f, debugLabelFrame.height - 20.0f, 280.0f, 18.0f);
}

- (CGRect)GetBlackBorderViewRect {
    CGSize pad = [DEL GetiPadSize];
    return CGRectMake(0, (pad.height - BARH) + 4.0f, (float)(border - 1), (float)(BARH - 4));
}

- (CGRect)GetBlackOverLayViewRect {
    CGSize pad = [DEL GetiPadSize];
    float h = ISIPAD ? 126.0f : 90.0f;
    return CGRectMake(0, pad.height - h, pad.width, h);
}

- (CGRect)GetFrameForDragPic:(int)frameForDragPic {
    CGSize pad = [DEL GetiPadSize];
    int dx = [self m_ignoreXdiff] ? 0 : m_lastCDXDiff;
    return CGRectMake((float)((border - dx) + ((border + THUMB) * frameForDragPic)),
                      (pad.height - (float)border) - (float)THUMB,
                      (float)THUMB, (float)THUMB);
}

- (CGRect)GetFrameForDragPicText:(int)frameForDragPicText {
    CGSize pad = [DEL GetiPadSize];
    int dx = [self m_ignoreXdiff] ? 0 : m_lastCDXDiff;
    return CGRectMake((float)(((-350 - dx) + border) + ((border + THUMB) * frameForDragPicText)),
                      (((pad.height - (float)border) - (float)THUMB) - (float)(THUMB >> 1)) - 5.0f,
                      (float)(THUMB + 0x2bc), (float)(THUMB >> 1));
}

- (CGRect)MakeSmallFrame:(CGRect)r {
    return CGRectMake(r.origin.x + ((r.size.width - 10.0f) * 0.5f), r.origin.y + ((r.size.height - 10.0f) * 0.5f), 10.0f, 10.0f);
}

- (void)FitSubViews:(CGSize)fitSubViews {
    [m_glv setFrame:[self GetOpenGLFrame:fitSubViews]];
    [m_divider setFrame:[self GetDividerFrame:fitSubViews]];
    [m_label setFrame:[self GetDebugLabelFrame:fitSubViews]];
    [m_blackoverlay setFrame:[self GetBlackOverLayViewRect]];
    [m_blackborderview setFrame:[self GetBlackBorderViewRect]];
    [self OrderClipPics:[NSNumber numberWithInt:1]];
    [m_glv SetUpTippRects];
    [m_glv FitSubViews:fitSubViews];
}

- (void)FadeQueueToBlack:(BOOL)fadeQueueToBlack {
    if (fadeQueueToBlack) {
        [m_blackoverlay retain];
        if ([m_blackoverlay superview] != nil)
            [m_blackoverlay removeFromSuperview];
        [self insertSubview:m_blackoverlay belowSubview:m_glv];
        [m_blackoverlay release];
    }
    [self SendCDsToBackGround];
    [self bringSubviewToFront:m_label];
    [self bringSubviewToFront:m_ratelabel];
    [UIView beginAnimations:@"kioskblackoverlayani" context:nil];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.4];
    [m_blackoverlay setAlpha:fadeQueueToBlack ? 1.0f : 0.0f];
    [UIView commitAnimations];
}

#pragma mark - loading screen

// DEVIATION: the original showed a "Fast geschafft: ... my.djukebox.com" screen for an empty library.  It is removed
// completely; an empty library just shows an empty carousel.
- (void)CheckLoadingscreen { }

#pragma mark - folders

static BOOL IsSpecialFolderId(long long fid) { return fid == -66 || fid == -44 || fid == -33; }

- (void)FolderTimerfunc:(id)timer {
    if (m_foldertimer != nil) {
        [m_foldertimer invalidate];
        [m_foldertimer release];
        m_foldertimer = nil;
    }
    ServerEntry *choosen = [[DEL GetServerComm] GetChoosenRfxServer:nil];
    [DEL LockDB:NO];
    DBOperations *dbop = [[DBOperations alloc] init];
    NSMutableArray *allFolders = [dbop GetFolders:choosen onlyexclude:NO checkempty:YES withLimits:NO withremotefolders:YES join:YES];
    [DEL RemoveVirtFolder:allFolders alsoIPOD:NO alsospotify:NO];
    NSMutableArray *limited = [dbop GetFolders:m_sve onlyexclude:NO checkempty:YES withLimits:YES withremotefolders:YES join:YES];
    [DEL RemoveVirtFolder:limited alsoIPOD:YES alsospotify:NO];
    [dbop release];
    [DEL UnlockDB];
    [choosen release];

    if (allFolders == nil || [allFolders count] == 0) {
        // original: [self CheckLastDirectChannel] (direct streaming channel, dropped)
        [allFolders release];
        [limited release];
        return;
    }

    // scheduled folders (flag 2) and their distance to "now"
    NSMutableArray *sched = [[NSMutableArray alloc] init];
    long tz = (long)[[NSTimeZone defaultTimeZone] secondsFromGMTForDate:[NSDate date]];
    long now = (long)time(0);
    for (NSUInteger i = 0; i < [allFolders count]; i++) {
        FolderObject *f = [allFolders objectAtIndex:i];
        if (([f flags] & 2) != 0) {
            [sched addObject:f];
            [f setTimediff:(int)([f autoselect] - ((now + tz) % 86400))];
        }
    }
    long long target = -1;      // folder to show (r4:r6 in the binary)
    int bestPast = -90000;
    for (NSUInteger i = 0; i < [sched count]; i++) {
        FolderObject *f = [sched objectAtIndex:i];
        if ([f timediff] <= -1 && [f timediff] > bestPast) {
            bestPast = [f timediff];
            target = [f folderid];
        }
        if ([f timediff] <= -1)
            [f setTimediff:(0x15180 + [f timediff])];
    }
    [sched sortUsingSelector:@selector(compareTimediffs:)];

    BOOL decided = NO;
    if ([sched count] != 0 && [[sched objectAtIndex:0] timediff] <= 5) {
        target = [[sched objectAtIndex:0] folderid];
        decided = YES;
    }
    if (!decided) {
        if (!m_firstcheck) {
            target = -1;
        } else {
            m_firstcheck = NO;
            if (target == -1) {
                // first start without a schedule: the folder played last, else the first folder
                [DEL LockDB:NO];
                DBOperations *d2 = [[DBOperations alloc] init];
                NSString *spot = nil;
                int last = [d2 GetLastPlayedFolder:[m_sve serverid] withspotifyfolderid:&spot];
                [d2 release];
                [DEL UnlockDB];
                long long lastId = last;
                BOOL found = NO;
                if (!IsSpecialFolderId(lastId)) {
                    for (NSUInteger i = 0; i < [limited count]; i++) {
                        if ([[limited objectAtIndex:i] folderid] == lastId) {
                            if (lastId != -1) { found = YES; }
                            break;
                        }
                    }
                }
                if (found) target = lastId;
                // DEVIATION: the original leaves nothing selected when the last played folder is one of the
                // dropped virtual folders (-33 / -44 / -66); here the first folder is used instead.
                else if ([limited count] != 0) target = [[limited objectAtIndex:0] folderid];
                else if ([allFolders count] != 0) target = [[allFolders objectAtIndex:0] folderid];
            }
        }
    }
    if (IsSpecialFolderId(target)) target = -1;

    // look the folder object up: scheduled folders first, then all folders
    FolderObject *folder = nil;
    if (target != -1) {
        for (NSUInteger i = 0; i < [sched count]; i++)
            if ([[sched objectAtIndex:i] folderid] == target) { folder = [sched objectAtIndex:i]; break; }
        if (folder == nil)
            for (NSUInteger i = 0; i < [allFolders count]; i++)
                if ([[allFolders objectAtIndex:i] folderid] == target) { folder = [allFolders objectAtIndex:i]; break; }
    }

    NSUInteger nextIdx = 0;
    if (folder != nil) {
        BOOL inLimited = NO;
        for (NSUInteger i = 0; i < [limited count]; i++)
            if ([[limited objectAtIndex:i] folderid] == target) { inLimited = YES; break; }
        if (inLimited)
            [m_glv ShowOnlyFolder:folder withstartSong:(m_shutdown ? NO : YES) channelviewwaspresent:NO];
        for (NSUInteger i = 0; i < [sched count]; i++)
            if ([sched objectAtIndex:i] == folder) { nextIdx = i + 1; break; }
    }
    if ([sched count] > nextIdx) {
        int diff = [[sched objectAtIndex:nextIdx] timediff] - 3;
        double interval = (diff < 10) ? 10.0 : (double)diff;
        m_foldertimer = [[NSTimer scheduledTimerWithTimeInterval:interval target:self
                            selector:@selector(FolderTimerfunc:) userInfo:nil repeats:NO] retain];
    }
    [sched release];
    [allFolders release];
    [limited release];
}

- (void)StartDirectFolder:(FolderObject *)directFolder {
    [m_glv ReleaseLastPlayingInfos];
    if (![m_glv m_pinching]) {
        [m_glv ShowOnlyFolder:directFolder withstartSong:YES channelviewwaspresent:NO];
    } else {
        [DEL LockDB:NO];
        DBOperations *dbop = [[DBOperations alloc] init];
        NSMutableArray *folders = [dbop GetFolders:m_sve onlyexclude:NO checkempty:YES withLimits:YES withremotefolders:YES join:YES];
        [dbop release];
        [DEL UnlockDB];
        int idx = 0;
        for (NSUInteger i = 0; i < [folders count]; i++) {
            if ([[folders objectAtIndex:i] folderid] == [directFolder folderid]) { idx = (int)i; break; }
        }
        [folders release];
        [m_glv PrepareCloseScroller];
        [m_glv setM_pinchstatus:3];
        [m_glv setM_newselectedfolderindex:idx];
        [m_glv performSelector:@selector(PinchAniBack) withObject:nil afterDelay:0];
    }
}

- (long long)GetSelectedFolderid { return [m_glv m_selectedfolderid]; }
- (int)GetSelectedServerid { return [m_glv m_selectedserverid]; }

- (void)StartveryfirstSong {
    if ([[self m_clips] count] == 0) return;
    ClipObject *c = [[[self m_clips] rfx_objectAtIndex:0] retain];
    [c setM_imgv:[[UIImageView alloc] initWithFrame:CGRectZero]];
    UIImage *pic = [m_glv CreateCDPicture:c roundpic:YES];
    [[c m_imgv] setImage:pic];
    [self AddCDPictureToView:c];
    [self OrderClipPics:[NSNumber numberWithInt:1]];
    [[c m_imgv] release];
    [self StartFirstFolderSong:[NSNumber numberWithInt:0]];
    [c release];
}

- (void)StartFirstFolderSong:(NSNumber *)firstFolderSong {
    if (m_loadingscreen != nil) return;
    int tries = [firstFolderSong intValue];
    if (tries > 5) return;
    if ([m_glv m_selectedfolderid] == -33) {
        if (gv_kioskflag == 0)
            [self performSelector:@selector(StartFirstFolderSong:) withObject:[NSNumber numberWithInt:tries + 1] afterDelay:0.3];
        return;
    }
    if ([[self m_clips] count] != 0) {
        // "nothing is playing" = no running song (the audio graph itself keeps running between songs)
        if (m_cliptorotate == nil && [self m_pausebegintime] < 0 && !m_fadingover && !m_ordering) {
            ClipObject *first = [[[self m_clips] rfx_objectAtIndex:0] retain];
            [self StopPlayers];
            [self StartAudioPlayer:first withAniNext:NO witharg1:1];
            [first release];
        }
        [self SendCDsToBackGround];
        return;
    }
    [self setM_rotateclip:NO];
    [self setM_shrinkdevider:NO];
    [self setM_presongInitTime:-1.0];
    [self setM_crossfadeInitTime:-1.0];
    m_cliptorotate = nil;
    [self StopPlayers];
    [m_glv GetArrayLock:NO];
    ClipObject *pick = nil;
    BOOL needShuffle = NO;
    if ([[m_glv m_tilearray] count] != 0) {
        NSMutableArray *tiles = [[NSMutableArray alloc] init];
        [tiles addObjectsFromArray:[m_glv m_tilearray]];
        for (NSInteger i = (NSInteger)[tiles count] - 1; i >= 0; i--) {
            ClipObject *tc = [tiles objectAtIndex:i];
            if ([tc ID] == -5 || ([tc m_folderid] == -88 && [[tc m_filepath] length] == 0)) [tiles removeObjectAtIndex:i];
        }
        if ([tiles count] != 0) {
            // continue with the song that was playing when the app was closed (first start only)
            static BOOL resumed = NO;
            ClipObject *t = nil;
            if (!resumed) {
                resumed = YES;
                long long last = [[[NSUserDefaults standardUserDefaults] objectForKey:@"RfxLastClipID"] longLongValue];
                if (last > 0) {
                    for (ClipObject *c in tiles) {
                        if ([c ID] == last) { t = c; break; }
                        for (ClipObject *tr in ([c m_tracks] ? [c m_tracks] : [NSArray array])) if ([tr ID] == last) { t = c; break; }
                        if (t != nil) break;
                    }
                }
            }
            if (t == nil) {
                needShuffle = YES;          // the shuffle (which knows what was played) picks it below
            } else {
                ClipObject *src = ([t m_tracks] != nil && [[t m_tracks] count] != 0) ? [[t m_tracks] objectAtIndex:0] : t;
                pick = [[ClipObject alloc] init];
                [self CopyPropertiesFromObject:src toObject:pick];
            }
        }
        [tiles release];
    }
    [m_glv releaseArraylock];
    if (needShuffle) { m_autoselected = YES; pick = [m_glv getNextClipObject]; }
    if (pick == nil || [pick m_folderid] == -33) {
        [pick release];
        if (gv_kioskflag == 0 && tries < 6)            // an empty collection (new playlist) must not keep retrying for ever
            [self performSelector:@selector(StartFirstFolderSong:) withObject:[NSNumber numberWithInt:tries + 1] afterDelay:0.3];
        return;
    }
    m_angle = 0;
    [[self m_clips] rfx_insertObject:pick atIndex:0];
    [pick release];
    [pick setM_imgv:[[UIImageView alloc] initWithFrame:CGRectZero]];
    UIImage *pic = [m_glv CreateCDPicture:pick roundpic:YES];
    [[pick m_imgv] setImage:pic];
    [self AddCDPictureToView:pick];
    [[pick m_imgv] release];
    [self CheckQueueHintLabel];
    [self OrderClipPics:[NSNumber numberWithInt:1]];
    [self StartAudioPlayer:pick withAniNext:NO witharg1:1];
    [self SendCDsToBackGround];
    [m_glv SelectClipImmediately:pick];
}

- (BOOL)IsInArray:(FolderObject *)inArray witharray:(NSArray *)array {
    for (NSUInteger i = 0; i < [array count]; i++)
        if ([[array objectAtIndex:i] folderid] == [inArray folderid]) return YES;
    return NO;
}

- (BOOL)FolderInArray:(FolderObject *)folderInArray withArray:(NSArray *)array {
    for (NSUInteger i = 0; i < [array count]; i++)
        if ([[array objectAtIndex:i] folderid] == [folderInArray folderid]) return YES;
    return NO;
}

- (void)CheckNoFolders { }

- (void)RemoveDirectChannelKey {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"k_lastdirctchannelid"];
    [d synchronize];
}

#pragma mark - limitations

- (void)CheckNextTime:(int *)nextTime withchecktime:(int)checktime withsecofday:(int)secofday {
    if (checktime > secofday) {
        if (*nextTime > checktime) *nextTime = checktime;
    }
}

- (void)CheckLimitationsLater {
    [self performSelector:@selector(CheckLimitations) withObject:nil afterDelay:0];
}

- (void)CheckLimitations {
    [self setM_limitinittime:-1.0];
    int dayIndex = 0;
    long secLong = 0;
    [DEL GetLimitationVars:&dayIndex withsecofday:&secLong];
    int secofday = (int)secLong;
    int nextTime = secofday + 0x2a300;      // two days ahead
    [DEL LockDB:NO];
    DBOperations *dbop = [[DBOperations alloc] init];
    NSMutableArray *folders = [dbop GetFolders:m_sve onlyexclude:NO checkempty:YES withLimits:NO withremotefolders:YES join:YES];
    [dbop release];
    [DEL UnlockDB];
    int start = 0, end = 0;
    for (NSInteger i = (NSInteger)[folders count] - 1; i >= 0; i--) {
        FolderObject *f = [folders objectAtIndex:i];
        BOOL remove = YES;
        // yesterday's window that runs past midnight
        [DEL GetFolderLimitationForDayIndex:((dayIndex - 1) < 1 ? 6 : (dayIndex - 2)) withstarttime:&start withendtime:&end withFolderobject:f];
        end -= 86400;
        if (end >= 1 && secofday <= end) {
            [self CheckNextTime:&nextTime withchecktime:end withsecofday:secofday];
            remove = NO;
        }
        // today
        [DEL GetFolderLimitationForDayIndex:(dayIndex - 1) withstarttime:&start withendtime:&end withFolderobject:f];
        if (secofday >= start && secofday <= end) remove = NO;
        [self CheckNextTime:&nextTime withchecktime:start withsecofday:secofday];
        [self CheckNextTime:&nextTime withchecktime:end withsecofday:secofday];
        // tomorrow
        [DEL GetFolderLimitationForDayIndex:((dayIndex + 1) > 7 ? 0 : dayIndex) withstarttime:&start withendtime:&end withFolderobject:f];
        [self CheckNextTime:&nextTime withchecktime:start withsecofday:secofday];
        [self CheckNextTime:&nextTime withchecktime:end withsecofday:secofday];
        if (remove) [folders removeObjectAtIndex:i];
    }
    if (nextTime - secofday <= 0x13) nextTime = secofday + 0x14;

    for (NSUInteger i = 0; i < [folders count]; i++) {
        FolderObject *f = [folders objectAtIndex:i];
        if ([f folderid] == [m_glv m_selectedfolderid] && [f serverid] == [m_glv m_selectedserverid] &&
            [f ipodid] == [m_glv m_selectedipodid]) {
            // the shown folder is still allowed: check again when the next limit starts or ends
            [folders release];
            [self setM_limitduration:(double)((nextTime + 2) - secofday)];
            [self setM_limitinittime:CACurrentMediaTime()];
            [self CheckNoFolders];
            return;
        }
    }
    [folders release];
    // the shown folder is not allowed any more: switch to the first allowed one
    [DEL LockDB:NO];
    dbop = [[DBOperations alloc] init];
    NSMutableArray *allowed = [dbop GetFolders:m_sve onlyexclude:NO checkempty:YES withLimits:YES withremotefolders:NO join:YES];
    [dbop release];
    [DEL UnlockDB];
    [DEL RemoveVirtFolder:allowed alsoIPOD:NO alsospotify:NO];
    if ([allowed count] != 0) {
        FolderObject *first = [allowed objectAtIndex:0];
        if (first != nil && [first folderid] != [m_glv m_selectedfolderid] && ![m_glv IsShowingChannelView])
            [m_glv ShowOnlyFolder:first withstartSong:([[self m_clips] count] == 0) channelviewwaspresent:NO];
    }
    [allowed release];
    [self setM_limitduration:(double)((nextTime + 2) - secofday)];
    [self setM_limitinittime:CACurrentMediaTime()];
    [self CheckNoFolders];
}

- (BOOL)SongFitsInRondell:(ClipObject *)song {
    long long sel = [m_glv m_selectedfolderid];
    if (sel == -1) return YES;
    if (sel == -1) return NO;
    if ([song m_folderid] != sel) return NO;
    if ([m_glv m_selectedserverid] == -1) return NO;
    if ([m_glv m_selectedserverid] != [song m_serverid]) return NO;
    return [m_glv m_selectedipodid] == [song m_ipodid];
}

- (void)CheckQueueInMainThread:(NSNumber *)queueInMainThread {
    int serverid = [queueInMainThread intValue];
    for (NSInteger i = (NSInteger)[[self m_clips] count] - 1; i >= 0; i--) {
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:i];
        if ([c m_serverid] != serverid) continue;
        if (c == m_cliptorotate) {
            m_cliptorotate = nil;
            [self setM_presongInitTime:-1.0];
            [self setM_crossfadeInitTime:-1.0];
            [self setM_limitinittime:-1.0];
            [self setM_shrinkdevider:NO];
            [self SetDeviderPlayingPercent:0.0f];
            [self StopPlayers];
        }
        if ([c m_imgv] != nil) { [[c m_imgv] removeFromSuperview]; [c setM_imgv:nil]; }
        if ([c m_imgvtext] != nil) { [[c m_imgvtext] removeFromSuperview]; [c setM_imgvtext:nil]; }
        if ([c m_swapimgv] != nil) { [[c m_swapimgv] removeFromSuperview]; [c setM_swapimgv:nil]; }
        [[self m_clips] rfx_removeObjectAtIndex:i];
        [self CheckQueueHintLabel];
    }
}

#pragma mark - queue (the row of cover thumbnails above the divider)

static int s_aniCounterDelete = 0;      // data_00368248 + 4
static int s_aniCounterNotAccepted = 0; // data_00368248 + 8

static void RemoveClipViews(ClipObject *c) {
    if ([c m_imgv] != nil) [[c m_imgv] removeFromSuperview];
    if ([c m_imgvtext] != nil) [[c m_imgvtext] removeFromSuperview];
    if ([c m_swapimgv] != nil) [[c m_swapimgv] removeFromSuperview];
}

- (void)AddClip:(ClipObject *)clip atIndex:(int)indexArg fromDragging:(BOOL)dragging withsendqueue:(BOOL)sendqueue
  withaddanyway:(BOOL)addanyway sendremotedelayed:(BOOL)sendremotedelayed {
    if (m_loadingscreen != nil) { RfxToast(@"Ladebildschirm aktiv – Titel nicht eingereiht."); return; }
    int count = (int)[[self m_clips] count];
    int flags = [m_sve StateFlags];
    int insertAt = (indexArg < 0) ? count : indexArg;
    BOOL skipDupCheck = ((flags & 0x20) == 0) ? addanyway : ((flags & 0xff) != 0);
    if (gRfxPlayNow) skipDupCheck = YES;
    if (!skipDupCheck && ([clip ID] != 0 || [clip m_ipodid] != 0)) {
        // the same song may only be in the queue once
        for (NSUInteger i = 0; i < [[self m_clips] count]; i++) {
            ClipObject *other = [[self m_clips] rfx_objectAtIndex:i];
            if ([other ID] == [clip ID] && [clip m_serverid] == [other m_serverid] && [other m_ipodid] == [clip m_ipodid]) {
                RfxToast(@"Dieser Titel ist schon in der Warteschlange.");
                [other retain];
                [m_glv setM_preventdragging:CACurrentMediaTime()];
                [self StartNotAcceptedAni:clip withqueuecd:other];
                [other release];
                return;
            }
        }
    }
    [self setM_lastsongdragged:CACurrentMediaTime()];

    int pos;
    BOOL replaceFirst = NO;
    if (gRfxPlayNow) {
        // a downloaded title is appended to the queue; it does not interrupt what is playing
        pos = count;
    } else if ((flags & 4) != 0) {
        pos = count;
    } else if (insertAt > 0) {
        pos = (insertAt < count) ? insertAt : count;
    } else if ([[self m_clips] count] == 0) {
        pos = 0;
    } else if (m_fadingover || (flags & 0x10) != 0) {
        pos = 1;
    } else {
        replaceFirst = YES;
        pos = 0;
    }

    if (!replaceFirst) {
        [[self m_clips] rfx_insertObject:clip atIndex:pos];
        [self AddCDPictureToView:clip];
        [self CheckQueueHintLabel];
        if ([m_glv IsShowingChannelView]) {
            [self sendSubviewToBack:[clip m_imgv]];
            if ([clip m_imgvtext] != nil) [self sendSubviewToBack:[clip m_imgvtext]];
            if ([clip m_swapimgv] != nil) [self sendSubviewToBack:[clip m_swapimgv]];
            [self OrderClipPics:[NSNumber numberWithInt:1]];
            [[clip m_imgv] setAlpha:1.0f];
            if ([clip m_imgvtext] != nil) [[clip m_imgvtext] setAlpha:0.0f];
            if ([clip m_swapimgv] != nil) [[clip m_swapimgv] setAlpha:0.0f];
        } else {
            m_ordering = YES;
            [UIView beginAnimations:@"OrderClipsAni" context:NULL];
            [UIView setAnimationDuration:0.6];
            [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
            [UIView setAnimationDelegate:self];
            [[clip m_imgv] setAlpha:1.0f];
            if ([clip m_imgvtext] != nil) [[clip m_imgvtext] setAlpha:0.0f];
            if ([clip m_swapimgv] != nil) [[clip m_swapimgv] setAlpha:0.0f];
            [self OrderClipPics:[NSNumber numberWithInt:1]];
            [UIView commitAnimations];
            [self performSelector:@selector(sendSubviewToBack:) withObject:[clip m_imgv] afterDelay:0.65];
            if ([clip m_imgvtext] != nil)
                [self performSelector:@selector(sendSubviewToBack:) withObject:[clip m_imgvtext] afterDelay:0.66];
            if ([clip m_swapimgv] != nil)
                [self performSelector:@selector(sendSubviewToBack:) withObject:[clip m_swapimgv] afterDelay:0.67];
        }
        // nothing is playing and the queue was empty: the chosen title starts by itself
        if (gRfxPlayNow && (count == 0 || m_cliptorotate == nil)) [self performSelector:@selector(StartFirstFolderSong:) withObject:[NSNumber numberWithInt:0] afterDelay:0.7];
        [clip release];
        return;
    }

    // default mode: the new song replaces the one that is playing right now (cross fade)
    ClipObject *oldFirst = [[[self m_clips] rfx_objectAtIndex:0] retain];
    [[self m_clips] rfx_removeObjectAtIndex:0];
    [[self m_clips] rfx_insertObject:clip atIndex:0];
    [self AddCDPictureToView:clip];
    [self CheckQueueHintLabel];
    m_fadingover = YES;
    [self performSelector:@selector(FadeOverProcess:) withObject:nil afterDelay:0.8];
    [self StartOrderAni:oldFirst];
    [clip release];
}

- (void)AddCDPictureToView:(ClipObject *)cdClip {
    UIView *above = nil;
    if (m_blackview != nil) above = m_blackview;
    else if (m_activateView != nil) above = m_activateView;
    else if (m_waitview != nil) above = m_waitview;
    else if (m_blackoverlay != nil && (double)[m_blackoverlay alpha] > 0.1) above = m_blackoverlay;
    else if (m_helpPicture != nil) above = m_helpPicture;

    if (above != nil) {
        [self insertSubview:[cdClip m_imgv] belowSubview:above];
        if ([cdClip m_imgvtext] != nil) [self insertSubview:[cdClip m_imgvtext] belowSubview:above];
        if ([cdClip m_swapimgv] != nil) [self insertSubview:[cdClip m_swapimgv] belowSubview:above];
    } else {
        [self addSubview:[cdClip m_imgv]];
        if ([cdClip m_imgvtext] != nil) [self addSubview:[cdClip m_imgvtext]];
        if ([cdClip m_swapimgv] != nil) [self addSubview:[cdClip m_swapimgv]];
        [self bringSubviewToFront:[m_glv GetKBView]];
    }
    if ([m_glv isShowingDimmViewOrNoConnView]) {
        if (![DEL m_isstattalm]) {
            [self sendSubviewToBack:[cdClip m_imgv]];
            if ([cdClip m_imgvtext] != nil) [self sendSubviewToBack:[cdClip m_imgvtext]];
            if ([cdClip m_swapimgv] != nil) [self sendSubviewToBack:[cdClip m_swapimgv]];
        }
    }
}

- (void)AddPictureToKiosk:(id)pictureToKiosk {
    if (m_loadingscreen != nil) return;
    [m_glv performSelectorOnMainThread:@selector(AddPicture:) withObject:pictureToKiosk waitUntilDone:YES];
    [m_glv SetLastmidindex:-2];
    [m_glv performSelectorOnMainThread:@selector(drawView) withObject:nil waitUntilDone:YES];
}

- (void)OrderClipPics:(NSNumber *)orderClipPics {
    int mode = [orderClipPics intValue];
    m_cantransform = NO;
    for (NSUInteger i = 0; i < [[self m_clips] count]; i++) {
        ClipObject *c = [[[self m_clips] rfx_objectAtIndex:i] retain];
        CGRect fr = [self GetFrameForDragPic:(int)i];
        // a spinning CD keeps its rotation (resetting it inside the animation block made the spin snap back and stutter)
        BOOL spin = NO;   // rotation is a layer animation now; the model transform stays identity
        if (spin) {
            [[c m_imgv] setBounds:CGRectMake(0, 0, fr.size.width, fr.size.height)];
            [[c m_imgv] setCenter:CGPointMake(CGRectGetMidX(fr), CGRectGetMidY(fr))];
        } else {
            [[c m_imgv] setTransform:CGAffineTransformMakeRotation(0)];
            [[c m_imgv] setFrame:fr];
        }
        [[c m_imgv] setAlpha:1.0f];
        if ([c m_swapimgv] != nil) {
            if (spin) { [[c m_swapimgv] setBounds:CGRectMake(0, 0, fr.size.width, fr.size.height)]; [[c m_swapimgv] setCenter:CGPointMake(CGRectGetMidX(fr), CGRectGetMidY(fr))]; }
            else [[c m_swapimgv] setFrame:fr];
            [[c m_swapimgv] setAlpha:0.0f];
        }
        if ([c m_imgvtext] != nil) {
            [[c m_imgvtext] setFrame:CGRectMake(fr.origin.x - 350.0f, (fr.origin.y - fr.size.height) - 23.0f,
                                                (float)(THUMB + 0x2bc), (float)((double)THUMB * 3.0 * 0.25))];
            [[c m_imgvtext] setAlpha:0.0f];
        }
        [c release];
    }
    if (mode == 1) m_cantransform = YES;
}

- (void)MoveCDs {
    for (NSUInteger i = 0; i < [[self m_clips] count]; i++) {
        ClipObject *c = [[[self m_clips] rfx_objectAtIndex:i] retain];
        CGRect f = [self GetFrameForDragPic:(int)i];
        [[c m_imgv] setCenter:CGPointMake((float)(int)((double)f.origin.x + (double)f.size.width * 0.5),
                                          (float)(int)((double)f.origin.y + (double)f.size.height * 0.5))];
        [c release];
    }
}

- (void)StartOrderAni:(ClipObject *)orderAni {
    m_ordering = YES;
    if (orderAni != nil) [self setM_ignoreXdiff:YES];
    [UIView beginAnimations:@"OrderClipsAni" context:NULL];
    [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDuration:0.6];
    [self OrderClipPics:[NSNumber numberWithInt:0]];
    if (orderAni == nil) {
        m_cantransform = YES;
        [UIView commitAnimations];
        return;
    }
    BOOL pad = ISIPAD;
    [[orderAni m_imgv] setTransform:CGAffineTransformMakeRotation(0)];
    CGRect f = [[orderAni m_imgv] frame];
    [[orderAni m_imgv] setFrame:CGRectMake(f.origin.x - (pad ? 112.0f : 86.0f), f.origin.y, f.size.width, f.size.height)];
    if ([[self m_clips] count] != 0)
        [[[[self m_clips] rfx_objectAtIndex:0] m_imgv] setAlpha:1.0f];
    m_cantransform = YES;
    [UIView commitAnimations];
    [self performSelector:@selector(FinalDelete:) withObject:orderAni afterDelay:1.5];
}

- (void)OrderClipsReady { m_ordering = NO; }

- (void)CorrectZindexComplete:(ClipObject *)c {
    [self CorrectZindex:[c m_imgv]];
    if ([c m_imgvtext] != nil) [self CorrectZindex:[c m_imgvtext]];
    if ([c m_swapimgv] != nil) [self CorrectZindex:[c m_swapimgv]];
}

- (void)CorrectZindex:(UIView *)view {
    if (view == nil) return;
    [view retain];
    [view removeFromSuperview];
    [self insertSubview:view belowSubview:[m_glv GetRegister0]];
    [view release];
}

- (int)GetInsertIndex:(CGPoint)insertIndex {
    int thumb = THUMB;
    int xdiff = [self m_ignoreXdiff] ? 0 : m_lastCDXDiff;
    if (insertIndex.x < 10.0f) return 0;
    int xd = (int)(insertIndex.x - 2.0f) + (thumb >> 1);
    int v = (xd < 0) ? xdiff : (xdiff + xd);
    return (int)((float)v / (float)(border + thumb));
}

- (void)CheckInsertPosition:(int *)insertPosition {
    if (([m_sve StateFlags] & 4) == 0) return;
    if (m_oldindex > 0) {
        if ((unsigned)m_oldindex <= [[self m_clips] count]) *insertPosition = m_oldindex;
    } else {
        *insertPosition = 1;
    }
}

- (void)FinalDelete:(ClipObject *)finalDelete {
    if (m_cliptorotate == finalDelete) {
        m_rotateclip = NO;
        m_cliptorotate = nil;
        [NSThread sleepForTimeInterval:0.1];
    }
    if (m_resetangle) {
        m_resetangle = NO;
        m_angle = 0;
        [NSThread sleepForTimeInterval:0.1];
    }
    [[finalDelete m_imgv] removeFromSuperview];
    if ([finalDelete m_imgvtext] != nil) [[finalDelete m_imgvtext] removeFromSuperview];
    if ([finalDelete m_swapimgv] != nil) [[finalDelete m_swapimgv] removeFromSuperview];
    // the views died with removeFromSuperview (assign properties): do not leave dangling pointers behind
    [finalDelete setM_imgv:nil];
    [finalDelete setM_imgvtext:nil];
    [finalDelete setM_swapimgv:nil];
    [finalDelete release];
}

- (void)DeleteCDAni:(ClipObject *)cDAni {
    if (m_draggingrunningsong) {
        if (!m_playingjingle) {
            ClipObject *copy = [[ClipObject alloc] init];
            [self CopyPropertiesFromObject:cDAni toObject:copy];
            [self performSelector:@selector(FadeOverProcess:) withObject:copy afterDelay:0.01];
        }
        m_draggingrunningsong = NO;
    }
    s_aniCounterDelete++;
    CGRect f = [[cDAni m_imgv] frame];
    [UIView beginAnimations:[NSString stringWithFormat:@"deletecd%i", s_aniCounterDelete] context:NULL];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.8];
    float off = ISIPAD ? 41.0f : 28.0f;
    CGRect shrunk = CGRectMake(f.origin.x + off, f.origin.y + off, 0.0f, 0.0f);
    [[cDAni m_imgv] setFrame:shrunk];
    [[cDAni m_imgv] setAlpha:0.0f];
    [[cDAni m_imgvtext] setFrame:shrunk];
    [[cDAni m_imgvtext] setAlpha:0.0f];
    [[cDAni m_swapimgv] setFrame:shrunk];
    [[cDAni m_swapimgv] setAlpha:0.0f];
    [UIView commitAnimations];
    [self performSelector:@selector(FinalDelete:) withObject:cDAni afterDelay:1.5];
}

- (void)StartNotAcceptedAni:(ClipObject *)notAcceptedAni withqueuecd:(ClipObject *)queuecd {
    [self addSubview:[notAcceptedAni m_imgv]];
    if ([[notAcceptedAni m_swapimgv] superview] == nil && [notAcceptedAni m_swapimgv] != nil)
        [self addSubview:[notAcceptedAni m_swapimgv]];
    if ([[notAcceptedAni m_imgvtext] superview] == nil && [notAcceptedAni m_imgvtext] != nil)
        [self addSubview:[notAcceptedAni m_imgvtext]];
    BOOL pad = ISIPAD;
    int idx = 0;
    if (queuecd != nil) {
        for (NSUInteger i = 0; i < [[self m_clips] count]; i++)
            if (queuecd == [[self m_clips] rfx_objectAtIndex:i]) { idx = (int)i; break; }
    }
    s_aniCounterNotAccepted++;
    [UIView beginAnimations:[NSString stringWithFormat:@"notacceptedani%i", s_aniCounterNotAccepted] context:NULL];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.5];
    [[notAcceptedAni m_imgv] setAlpha:1.0f];
    if (queuecd == nil) {
        CGRect f = [[notAcceptedAni m_imgv] frame];
        [[notAcceptedAni m_imgv] setFrame:CGRectMake(f.origin.x + (float)(THUMB >> 1), (f.origin.y + (float)(THUMB >> 1)) - 150.0f, 0.0f, 0.0f)];
    } else {
        [[notAcceptedAni m_imgv] setFrame:[self GetFrameForDragPic:idx]];
        if ([[self m_clips] count] != 0 && queuecd == [[self m_clips] rfx_objectAtIndex:0])
            m_resetangle = YES;
    }
    if ([notAcceptedAni m_swapimgv] != nil) {
        [[notAcceptedAni m_swapimgv] setAlpha:0.0f];
        [[notAcceptedAni m_swapimgv] setFrame:[[notAcceptedAni m_imgv] frame]];
    }
    if ([notAcceptedAni m_imgvtext] != nil) {
        [[notAcceptedAni m_imgvtext] setAlpha:0.0f];
        CGRect f = [[notAcceptedAni m_imgv] frame];
        [[notAcceptedAni m_imgvtext] setFrame:CGRectMake(f.origin.x - 350.0f, (f.origin.y - f.size.height) - 23.0f,
                                                         (float)(THUMB + 0x2bc), (float)((double)THUMB * 3.0 * 0.25))];
    }
    (void)pad;
    [UIView commitAnimations];
    [self performSelector:@selector(FinalDelete:) withObject:notAcceptedAni afterDelay:0.8];
}

- (void)SimpleDeleteWithOrder:(NSNumber *)simpleDeleteWithOrder {
    int idx = [simpleDeleteWithOrder intValue];
    if (idx < 0 || (unsigned)idx >= [[self m_clips] count]) return;
    if (idx != 0) {
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:idx];
        RemoveClipViews(c);
        [[self m_clips] rfx_removeObjectAtIndex:idx];
        [self StartOrderAni:nil];
        [self CheckQueueHintLabel];
    } else if (![self m_fadingover]) {
        [self setM_crossfadeInitTime:-1.0];
        [self setM_presongInitTime:-1.0];
        [self performSelector:@selector(CheckNextSong:)
                   withObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:0], @"how",
                                                [NSNumber numberWithFloat:m_curfade], @"time", nil]
                   afterDelay:0.01];
    }
}

- (void)RemoveAndOrderImage:(ClipObject *)c {
    RemoveClipViews(c);
    [[self m_clips] removeObject:c];
    [self OrderClipPics:[NSNumber numberWithInt:1]];
    [self CheckQueueHintLabel];
}

- (void)RemoveDragginObjInMT {
    m_draggingorigpos = -1;
    if ([m_draggingobj m_imgv] != nil && [[m_draggingobj m_imgv] superview] != nil)
        [[m_draggingobj m_imgv] removeFromSuperview];
    if ([m_draggingobj m_imgvtext] != nil && [[m_draggingobj m_imgvtext] superview] != nil)
        [[m_draggingobj m_imgvtext] removeFromSuperview];
    if ([m_draggingobj m_swapimgv] != nil && [[m_draggingobj m_swapimgv] superview] != nil)
        [[m_draggingobj m_swapimgv] removeFromSuperview];
    if (m_draggingobj != nil) {
        [m_draggingobj release];
        m_draggingobj = nil;
    }
    m_draggingrunningsong = NO;
}

- (void)DelPicInMainThread:(ClipObject *)c {
    if ([c m_imgv] != nil && [[c m_imgv] superview] != nil) [[c m_imgv] removeFromSuperview];
    if ([c m_imgvtext] != nil && [[c m_imgvtext] superview] != nil) [[c m_imgvtext] removeFromSuperview];
    if ([c m_swapimgv] != nil && [[c m_swapimgv] superview] != nil) [[c m_swapimgv] removeFromSuperview];
}

- (void)RemoveImageInMainThread:(UIView *)v { [v removeFromSuperview]; }

- (void)OrderGLVAndBlackView { }   // empty in the binary (@0x77be0)

- (void)SendCDsToBackGround {
    if (m_waitview != nil) [self sendSubviewToBack:m_waitview];
    for (NSUInteger i = 0; i < [[self m_clips] count]; i++)
        { UIView *v = [[[self m_clips] rfx_objectAtIndex:i] m_imgv]; if (v != nil) [self sendSubviewToBack:v]; }
}

- (void)EmptyQueue {
    while ([[self m_clips] count] != 0) {
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:0];
        RemoveClipViews(c);
        [[self m_clips] rfx_removeObjectAtIndex:0];
    }
    [self CheckQueueHintLabel];
}

- (void)SwapImage:(ClipObject *)swapImage withalpha:(float)alpha {
    if ([swapImage m_swapimgv] == nil) return;
    [[swapImage m_imgv] setImage:nil];
    [[swapImage m_imgv] setAlpha:alpha];
    [[swapImage m_imgv] setImage:[[swapImage m_swapimgv] image]];
    [[swapImage m_swapimgv] removeFromSuperview];
    [swapImage setM_swapimgv:nil];
}

- (ClipObject *)IsClipInList:(ClipObject *)clipInList {
    if ([self m_clips] == nil) return nil;
    for (NSUInteger i = 0; i < [[self m_clips] count]; i++) {
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:i];
        if ([c ID] == [clipInList ID] && [c m_serverid] == [clipInList m_serverid] && [c m_ipodid] == [clipInList m_ipodid])
            return c;
    }
    return nil;
}

static NSString *CopyStr(NSString *s) { return s == nil ? nil : [NSString stringWithFormat:@"%@", s]; }

- (void)CopyPropertiesFromObject:(ClipObject *)from toObject:(ClipObject *)object {
    [object setM_interpret:[NSString stringWithFormat:@"%@", [from m_interpret]]];
    [object setM_title:[NSString stringWithFormat:@"%@", [from m_title]]];
    [object setID:[from ID]];
    [object setM_filesize:[from m_filesize]];
    [object setM_ipodid:[from m_ipodid]];
    [object setM_folderipodid:[from m_folderipodid]];
    [object setM_filepath:CopyStr([from m_filepath])];
    [object setM_picturepath:CopyStr([from m_picturepath])];
    [object setM_folderid:[from m_folderid]];
    [object setM_serverid:[from m_serverid]];
    [object setM_albumid:[from m_albumid]];
    [object setM_albumname:CopyStr([from m_albumname])];
    [object setM_tracknumber:[from m_tracknumber]];
    [object setM_duration:[from m_duration]];
    [object setM_information:CopyStr([from m_information])];
    [object setM_starttime:[from m_starttime]];
    [object setM_channelid:[from m_channelid]];
    [object setM_epgid:[from m_epgid]];
    [object setM_filename:CopyStr([from m_filename])];
    [object setM_genre:CopyStr([from m_genre])];
    [object setM_channel:CopyStr([from m_channel])];
    [object setM_spotifyid:CopyStr([from m_spotifyid])];
    [object setM_spotifyfolderid:CopyStr([from m_spotifyfolderid])];
}

- (void)CheckPendingSong {
    // DEVIATION: the original deleted the mp3 and cover files of songs the user had removed from the library
    // (m_clipstodelete).  The port never deletes files from the user's Documents folder; the list is just cleared.
    for (NSInteger i = (NSInteger)[[m_glv m_clipstodelete] count] - 1; i >= 0; i--) {
        ClipObject *c = [[m_glv m_clipstodelete] objectAtIndex:i];
        if ([self IsClipInList:c] == nil) [[m_glv m_clipstodelete] removeObjectAtIndex:i];
    }
}

- (void)RemoveOnlyFirstClip {
    m_ordering = NO;
    if ([[self m_clips] count] == 0) return;
    ClipObject *c = [[self m_clips] rfx_objectAtIndex:0];
    if ([c m_imgv] != nil && [[c m_imgv] superview] != nil) [[c m_imgv] removeFromSuperview];
    if ([c m_imgvtext] != nil && [[c m_imgvtext] superview] != nil) [[c m_imgvtext] removeFromSuperview];
    if ([c m_swapimgv] != nil && [[c m_swapimgv] superview] != nil) [[c m_swapimgv] removeFromSuperview];
    [[self m_clips] rfx_removeObjectAtIndex:0];
    if (mMCMixer != nil) [mMCMixer FadeOut:3.0f];
    [self setM_tenmintimer:CACurrentMediaTime()];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 3.5, false);
    [self setM_presongInitTime:-1.0];
    [self setM_shrinkdevider:NO];
    [self setM_crossfadeInitTime:-1.0];
    m_rotateclip = NO;
    m_cliptorotate = nil;
    m_angle = 0;
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
    [self SetDeviderPlayingPercent:0.0f];
    m_fadingover = NO;
    if ([[self m_clips] count] != 0) {
        [self StartOrderAni:nil];
        [self StartFirstFolderSong:[NSNumber numberWithInt:0]];
        m_fadingover = NO;
    }
}

- (void)CheckQueueHintLabel {
    // original: only active for the stationary-installation mode (m_isstattalm) which shows a hint after
    // one song is queued -- not part of the port.
}

- (void)SetLeftTimeInMTFirstObject:(UIImage *)img {
    if ([[self m_clips] count] != 0)
        [[[[self m_clips] rfx_objectAtIndex:0] m_imgvtext] setImage:img];
    [img release];
}

- (void)SetLeftTimeInMT:(UIImage *)img {
    if ([self m_draggingobj] != nil)
        [[[self m_draggingobj] m_imgvtext] setImage:img];
    [img release];
}

- (void)CheckRunningSongLeftTime {
    if ([self m_draggingobj] != nil && m_draggingrunningsong) {
        [[self m_draggingobj] retain];
        UIImage *img = [[m_glv CreateTextPicture:[self m_draggingobj] withtime:[self GetSongTimeLeft:[self m_draggingobj]] maxWidthPointer:NULL] retain];
        [[self m_draggingobj] release];
        [self performSelectorOnMainThread:@selector(SetLeftTimeInMT:) withObject:img waitUntilDone:NO];
    }
    if (m_showfirstsongInfos && [[self m_clips] count] != 0) {
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:0];
        [c retain];
        UIImage *img = [[m_glv CreateTextPicture:c withtime:[self GetSongTimeLeft:c] maxWidthPointer:NULL] retain];
        [c release];
        [self performSelectorOnMainThread:@selector(SetLeftTimeInMTFirstObject:) withObject:img waitUntilDone:NO];
    }
}

- (int)GetSongTimeLeft:(ClipObject *)song {
    if (song == nil) return -1;
    double left = (double)[song m_duration] - (CACurrentMediaTime() - [self m_crossfadeInitTime]);
    return left <= 0 ? 0 : (int)left;
}

- (int)GetTimeActSongPlayed {
    if ([self m_fadingover]) return -1;
    double played = CACurrentMediaTime() - [self m_clipStartTime];
    return played < 2.0 ? -1 : (int)played;
}

- (int)GetTimeGone {
    int t = (int)(CACurrentMediaTime() - [self m_clipStartTime]);
    return t <= 0 ? 0 : t;
}

#pragma mark - pictures

static UIImage *s_brightened = nil;     // data_00398844: result of BrightenPicture:

- (BOOL)CreateFolder:(NSString *)folder {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:folder]) return YES;
    NSError *err = nil;
    if ([fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&err]) return YES;
    [self performSelectorOnMainThread:@selector(SetDebugText:) withObject:@"Could not create directory" waitUntilDone:YES];
    return NO;
}

- (UIImage *)GetSmallImage:(ClipObject *)smallImage {
    NSString *p = [DEL BuildSmallPicpath:[smallImage m_picturepath]];
    return p == nil ? nil : [UIImage imageWithContentsOfFile:p];
}

- (void)CreateSmallPic:(UIImage *)smallPic withClipObject:(ClipObject *)clipObject {
    NSString *path = [DEL BuildSmallPicpath:[clipObject m_picturepath]];
    if (smallPic == nil) return;
    CGSize sz = [smallPic size];
    float shortSide = (sz.width < sz.height) ? sz.width : sz.height;
    float scale = shortSide / 40.0f;
    CGContextRef ctx = [DEL BeginImageContext:CGSizeMake((float)(int)(sz.width / scale), (float)(int)(sz.height / scale))];
    CGContextDrawImage(ctx, CGRectMake(0, 0, (float)(int)(sz.width / scale), (float)(int)(sz.height / scale)), [smallPic CGImage]);
    UIImage *out = [DEL EndImageContext:ctx];
    [UIImageJPEGRepresentation(out, 1.0f) writeToFile:path atomically:YES];
    [DEL AddSkipBackupAttributeToFile:path];
}

// Fits the picture into a kThumbSize square on black, then blends "dimmpixel.png" over it.  The result is
// left in s_brightened (retained), exactly like the original which used a global.
- (void)BrightenPicture:(NSData *)brightenPicture {
    UIImage *img = [[UIImage alloc] initWithData:brightenPicture];
    if (img == nil) return;
    float T = (float)kThumbSize;
    CGSize sz = [img size];
    float scale = (sz.width >= sz.height) ? (sz.width / T) : (sz.height / T);
    float xoff = 0, yoff = 0;
    if (sz.width != sz.height) {
        if (sz.width > sz.height) yoff = (float)(int)((double)(T - sz.height / scale) * 0.5);
        else xoff = (float)(int)((double)(T - sz.width / scale) * 0.5);
    }
    CGContextRef ctx = [DEL BeginImageContext:CGSizeMake(T, T)];
    CGContextSetFillColorWithColor(ctx, [[UIColor blackColor] CGColor]);
    CGContextFillRect(ctx, CGRectMake(0, 0, T, T));
    CGContextDrawImage(ctx, CGRectMake(xoff, yoff, (float)(int)(sz.width / scale), (float)(int)(sz.height / scale)), [img CGImage]);
    CGContextSetBlendMode(ctx, kCGBlendModeLuminosity);
    CGImageRef dimm = [[UIImage imageNamed:@"dimmpixel.png"] CGImage];
    CGImageRetain(dimm);
    CGContextDrawImage(ctx, CGRectMake(0, 0, T, T), dimm);
    s_brightened = [[DEL EndImageContext:ctx] retain];
    CGImageRelease(dimm);
    [img release];
}

// ---- ID3v2 picture extraction (replaces the original's C++ CId3v2 class) ----

static uint32_t ID3SyncSafe(const uint8_t *p) {
    return ((uint32_t)(p[0] & 0x7f) << 21) | ((uint32_t)(p[1] & 0x7f) << 14) | ((uint32_t)(p[2] & 0x7f) << 7) | (p[3] & 0x7f);
}

// index of the end of a text field in the given encoding (returns the index after the terminator)
static NSUInteger ID3SkipText(const uint8_t *b, NSUInteger i, NSUInteger end, int enc) {
    if (enc == 1 || enc == 2) {
        while (i + 1 < end) {
            if (b[i] == 0 && b[i + 1] == 0) return i + 2;
            i += 2;
        }
        return end;
    }
    while (i < end) { if (b[i++] == 0) return i; }
    return end;
}

// Returns the bytes of the first embedded picture of the tag or nil.
static NSData *ID3FindPicture(NSData *data, NSUInteger *neededTagSize) {
    const uint8_t *d = (const uint8_t *)[data bytes];
    NSUInteger len = [data length];
    if (neededTagSize) *neededTagSize = 0;
    if (len < 10 || memcmp(d, "ID3", 3) != 0) return nil;
    int ver = d[3];
    if (ver < 2 || ver > 4) return nil;
    uint8_t flags = d[5];
    NSUInteger tagSize = ID3SyncSafe(d + 6) + 10;
    if (neededTagSize) *neededTagSize = tagSize;
    if (tagSize > len) return nil;                      // tag not completely loaded yet
    NSUInteger pos = 10, end = tagSize;
    if (flags & 0x40) {                                 // extended header
        if (ver == 3 && pos + 4 <= end) pos += 4 + (((NSUInteger)d[pos] << 24) | (d[pos + 1] << 16) | (d[pos + 2] << 8) | d[pos + 3]);
        else if (ver == 4 && pos + 4 <= end) pos += ID3SyncSafe(d + pos);
    }
    BOOL unsync = (flags & 0x80) != 0;
    int hdr = (ver == 2) ? 6 : 10;
    while (pos + hdr <= end) {
        const uint8_t *f = d + pos;
        if (f[0] == 0) break;                           // padding
        NSUInteger fsize;
        if (ver == 2) fsize = ((NSUInteger)f[3] << 16) | (f[4] << 8) | f[5];
        else if (ver == 3) fsize = ((NSUInteger)f[4] << 24) | (f[5] << 16) | (f[6] << 8) | f[7];
        else fsize = ID3SyncSafe(f + 4);
        NSUInteger body = pos + hdr;
        if (fsize == 0 || body + fsize > end) break;
        BOOL isPic = (ver == 2) ? (memcmp(f, "PIC", 3) == 0) : (memcmp(f, "APIC", 4) == 0);
        if (isPic) {
            NSMutableData *tmp = nil;
            const uint8_t *b = d + body;
            NSUInteger n = fsize;
            if (unsync || (ver == 4 && (f[9] & 0x02))) {
                tmp = [NSMutableData dataWithCapacity:fsize];
                for (NSUInteger k = 0; k < fsize; k++) {
                    [tmp appendBytes:b + k length:1];
                    if (b[k] == 0xff && k + 1 < fsize && b[k + 1] == 0) k++;
                }
                b = (const uint8_t *)[tmp bytes];
                n = [tmp length];
            }
            if (n < 4) return nil;
            int enc = b[0];
            NSUInteger i = 1;
            if (ver == 2) i += 3;                       // 3 letter image format
            else i = ID3SkipText(b, i, n, 0);           // MIME type (always ISO-8859-1)
            if (i >= n) return nil;
            i += 1;                                     // picture type
            i = ID3SkipText(b, i, n, enc);              // description
            if (i >= n) return nil;
            return [NSData dataWithBytes:b + i length:n - i];
        }
        pos = body + fsize;
    }
    return nil;
}

- (NSString *)ExtractPicture:(NSString *)extractPicture {
    // DEVIATION: opened read-only (the original opened for updating because RepairHeader wrote into the mp3).
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:extractPicture];
    if (fh == nil) return nil;
    NSString *result = nil;
    @try {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:extractPicture error:NULL];
        NSNumber *fsize = [attrs objectForKey:NSFileSize];
        BOOL tooSmall = (fsize == nil) || [fsize intValue] <= 0x200;
        NSData *first = [fh readDataOfLength:0x200];
        if (first != nil && !tooSmall) {
            NSData *more = [fh readDataOfLength:0x4e20];
            if (more != nil) {
                NSMutableData *buf = [[NSMutableData alloc] init];
                [buf appendData:first];
                [buf appendData:more];
                NSUInteger need = 0;
                NSData *pic = ID3FindPicture(buf, &need);
                if (pic == nil && need > [buf length] && need < (16u << 20)) {
                    NSData *rest = [fh readDataOfLength:(need - [buf length])];
                    if (rest != nil) {
                        [buf appendData:rest];
                        pic = ID3FindPicture(buf, &need);
                    }
                }
                if (pic != nil && [pic length] != 0) {
                    NSString *jpg = [[extractPicture stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"];
                    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                    s_brightened = nil;
                    [self BrightenPicture:pic];
                    if (s_brightened != nil) {
                        [UIImageJPEGRepresentation(s_brightened, 1.0f) writeToFile:jpg atomically:YES];
                        [DEL AddSkipBackupAttributeToFile:jpg];
                        [s_brightened release];
                        s_brightened = nil;
                        result = [[jpg retain] autorelease];
                    }
                    [pool release];
                    [[result retain] autorelease];
                }
                [buf release];
            }
        }
    } @catch (NSException *e) {
        result = nil;
    }
    [fh closeFile];
    return result;
}

- (UIImage *)GetSongImage:(NSString *)songImage withclipobject:(ClipObject *)clipobject {
    if ([clipobject ID] == -6) return [UIImage imageNamed:@"waiting.png"];
    [clipobject retain];
    UIImage *img = nil;
    if (songImage != nil) {
        img = [UIImage imageWithContentsOfFile:songImage];
        if (img != nil && [clipobject ID] == -5) {
            // branding picture: crop to a centred square
            CGSize sz = [img size];
            if (sz.width != sz.height) {
                int x, y;
                if (sz.width <= sz.height) { x = 0; y = (int)((sz.height - sz.width) * 0.5f); }
                else { x = (int)((sz.width - sz.height) * 0.5f); y = 0; }
                CGImageRef cg = CGImageCreateWithImageInRect([img CGImage],
                    CGRectMake((float)x, (float)y, sz.width - (float)(x << 1), sz.height - (float)(y << 1)));
                UIImage *cropped = [UIImage imageWithCGImage:cg];
                CGImageRelease(cg);
                img = cropped;
            }
        }
    }
    if (img == nil && [clipobject m_picturepath] != nil)
        img = [UIImage imageWithContentsOfFile:[clipobject m_picturepath]];
    if (img == nil) {
        if ([clipobject m_filepath] != nil && [clipobject m_folderid] != -44 && [clipobject m_folderid] != -66) {
            [clipobject setM_picturepath:[self ExtractPicture:[clipobject m_filepath]]];
            if ([clipobject m_picturepath] != nil) img = [UIImage imageWithContentsOfFile:[clipobject m_picturepath]];
        } else if ([clipobject m_tracks] != nil) {
            [clipobject setM_picturepath:[self ExtractPicture:[[[clipobject m_tracks] objectAtIndex:0] m_filepath]]];
            if ([clipobject m_picturepath] != nil) img = [UIImage imageWithContentsOfFile:[clipobject m_picturepath]];
        }
    }
    BOOL found = (img != nil);

    ClipObject *src = clipobject;
    if ([clipobject m_tracks] != nil && [[clipobject m_tracks] count] != 0)
        src = [[clipobject m_tracks] objectAtIndex:0];

    if (!found && src != nil && [src m_filepath] != nil) {
        // No cover anywhere: paint one (random colour set, interpret rotated, title wrapped) and keep it
        // next to the mp3 as <mp3 name>.jpg so it is found next time.
        NSString *jpg = [[[src m_filepath] stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"];
        int T = kThumbSize;
        CGContextRef ctx = [DEL BeginImageContext:CGSizeMake((float)T, (float)T)];
        NSUInteger sets = [m_colorarray count] / 3;
        int ci = (int)(random() % sets);
        int c0 = [[m_colorarray objectAtIndex:ci * 3] intValue];
        int c1 = [[m_colorarray objectAtIndex:ci * 3 + 1] intValue];
        int c2 = [[m_colorarray objectAtIndex:ci * 3 + 2] intValue];
#define RGBCOL(c) [UIColor colorWithRed:(float)(((c) >> 16) & 0xff) / 255.0f green:(float)(((c) >> 8) & 0xff) / 255.0f blue:(float)((c) & 0xff) / 255.0f alpha:1.0f]
        CGContextSetFillColorWithColor(ctx, [RGBCOL(c0) CGColor]);
        CGContextFillRect(ctx, CGRectMake(0, 0, (float)T, (float)T));
        for (int pass = 0; pass < 2; pass++) {
            NSString *text = [(pass != 0 ? [src m_title] : [src m_interpret]) uppercaseString];
            if (text == nil) continue;
            if (pass == 0) {
                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx, (float)((double)T * 0.5), (float)((double)T * 0.5));
                CGContextRotateCTM(ctx, 1.5707963f);
                CGContextTranslateCTM(ctx, (float)((double)(0 - T) * 0.5), (float)((double)(0 - T) * 0.5));
            }
            CGContextSetFillColorWithColor(ctx, [RGBCOL(pass != 0 ? c1 : c2) CGColor]);
            if (pass == 0) {
                static NSString *const fonts[6] = { @"Futura-CondensedExtraBold", @"Verdana-Bold", @"Georgia-Bold",
                                                    @"HoeflerText-Black", @"AmericanTypewriter-Bold", @"GillSans-Bold" };
                UIFont *font = [UIFont fontWithName:fonts[random() % 6] size:55.0f];
                if (font == nil) font = [UIFont boldSystemFontOfSize:55.0f];
                [DEL OwndrawAtPoint:ctx withtext:text drawAtPoint:CGPointMake(0, 17.0f) forWidth:0 withFont:font lineBreakMode:0];
                CGContextRestoreGState(ctx);
            } else {
                NSMutableArray *lines = [[NSMutableArray alloc] init];
                NSMutableString *cur = [NSMutableString stringWithCapacity:1];
                NSArray *words = [text componentsSeparatedByString:@" "];
                int wordsInLine = 0;
                for (NSUInteger w = 0; w < [words count]; w++) {
                    [cur appendString:[NSString stringWithFormat:@"%@%@", (w == 0 ? @"" : @" "), [words objectAtIndex:w]]];
                    CGSize tsz = [cur sizeWithFont:m_titlefont];
                    int prev = wordsInLine;
                    wordsInLine++;
                    if (tsz.width > (float)(T - 40) && prev >= 1) {
                        NSUInteger wl = [[words objectAtIndex:w] length];
                        [cur deleteCharactersInRange:NSMakeRange([cur length] - (wl + 1), wl + 1)];
                        [lines addObject:[NSString stringWithFormat:@"%@", cur]];
                        [cur setString:[NSString stringWithFormat:@"%@", [words objectAtIndex:w]]];
                        wordsInLine = 1;
                    }
                    if (w == [words count] - 1 && [cur length] != 0) {
                        [lines addObject:[NSString stringWithFormat:@"%@", cur]];
                        [cur setString:@""];
                    }
                }
                int n = (int)[lines count];
                for (int i = n - 1; i >= 0; i--) {
                    NSString *line = [lines objectAtIndex:i];
                    CGSize lsz = [line sizeWithFont:m_titlefont];
                    int w = (int)(lsz.width < (float)(T - 40) ? lsz.width : (float)(T - 40));
                    int x = (T - (T - 40)) / 2;
                    int y = ((T - 24 * n) / 2) + 24 * (n - i) - 24;
                    [DEL OwndrawAtPoint:ctx withtext:line drawAtPoint:CGPointMake((float)x, (float)y) forWidth:w withFont:m_titlefont lineBreakMode:0];
                }
                [lines release];
            }
        }
        // 1px frame in a brighter shade of the background colour
        float h, s, v, r, g, b;
        [DEL RGBtoHSV:(float)((c0 >> 16) & 0xff) withgreen:(float)((c0 >> 8) & 0xff) withblue:(float)(c0 & 0xff) withue:&h withsat:&s withval:&v];
        double nv = (double)v * 1.4;
        float val = (nv < 255.0) ? (float)nv : 255.0f;
        [DEL HSVtoRGB:&r withgreen:&g withblue:&b withhue:h withsat:s withval:val];
        CGContextSetFillColorWithColor(ctx, [[UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:1.0f] CGColor]);
        CGContextFillRect(ctx, CGRectMake(0, 0, (float)T, 1.0f));
        CGContextFillRect(ctx, CGRectMake((float)(T - 1), 0, 1.0f, (float)T));
        CGContextFillRect(ctx, CGRectMake(0, (float)(T - 1), (float)T, 1.0f));
        CGContextFillRect(ctx, CGRectMake(0, 0, 1.0f, (float)T));
#undef RGBCOL
        img = [DEL EndImageContext:ctx];
        if (img != nil) {
            [UIImageJPEGRepresentation(img, 1.0f) writeToFile:jpg atomically:YES];
            [DEL AddSkipBackupAttributeToFile:jpg];
        }
        [src setM_picturepath:jpg];
    }
    if (img == nil) img = [UIImage imageNamed:@"cover-note.png"];
    if (src != clipobject && [src m_picturepath] != nil)
        [clipobject setM_picturepath:[NSString stringWithFormat:@"%@", [src m_picturepath]]];
    [clipobject release];
    return img;
}

#pragma mark - touches

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    if (t == nil) return;
    if ([m_glv m_selectedfolderid] == -33) return;
    CGPoint p = [t locationInView:self];
    m_starttouchpoint = p;
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    [self touchesBeganDelayed:po];
}

- (void)touchesBeganDelayed:(CGPointObject *)touchesBeganDelayed {
    float x = [touchesBeganDelayed x];
    float y = [touchesBeganDelayed y];
    [touchesBeganDelayed release];
    [m_glv StopIdleTimer];
    [m_glv StopAdvertTimer];
    if (m_fadingover) return;
    if ([m_glv IsShowingChannelView]) return;
    if ([DEL m_isstattalm] && [m_glv IsShowingAskBox]) {
        [m_glv setM_cancelcard:YES];
        return;
    }
    int flags = [m_sve StateFlags];
    if ((flags & 4) != 0 && (flags & 8) != 0) return;
    if ([self m_draggingobj] != nil) return;
    int thumb = THUMB;
    float xdiff = [self m_ignoreXdiff] ? 0 : (float)m_lastCDXDiff;
    if ([[self m_clips] count] == 0) return;
    int idx = (int)(((x + xdiff) - (float)(border / 2)) / (float)(border + thumb));
    if ((unsigned)idx >= [[self m_clips] count]) return;
    m_oldindex = idx;

    if (idx == 0) {
        if ((flags & 0x10) != 0 || (flags & 8) != 0) {
            // not draggable: only show the remaining time above the running song
            ClipObject *first = [[self m_clips] rfx_objectAtIndex:0];
            CGRect fr = [self GetFrameForDragPic:0];
            if ([first m_imgvtext] == nil)
                [first setM_imgvtext:[[UIImageView alloc] initWithFrame:CGRectZero]];
            [[first m_imgvtext] setAlpha:0.5f];
            int w = 0;
            [[first m_imgvtext] setImage:[m_glv CreateTextPicture:first withtime:[self GetSongTimeLeft:first] maxWidthPointer:&w]];
            float W = (float)(thumb + 0x2bc);
            float x0 = fr.origin.x - 350.0f;
            int v = (int)((x0 + W * 0.5f) - 10.0f);
            float tx = (v <= -1) ? ((x0 - (float)v) + 5.0f) : x0;
            [[first m_imgvtext] setFrame:CGRectMake(tx, (fr.origin.y - fr.size.height) - 23.0f, W, (float)((double)thumb * 3.0 * 0.25))];
            if ([[first m_imgvtext] superview] != self) {
                [self addSubview:[first m_imgvtext]];
                [[first m_imgvtext] release];
            }
            m_showfirstsongInfos = YES;
            return;
        }
        m_draggingrunningsong = YES;
        [[[[self m_clips] rfx_objectAtIndex:0] m_imgv] setTransform:CGAffineTransformMakeRotation(0)];
    }

    // pick the thumbnail up: a copy of it follows the finger
    ClipObject *src = [[[self m_clips] rfx_objectAtIndex:idx] retain];
    m_draggingobj = [[ClipObject alloc] init];
    [self CopyPropertiesFromObject:src toObject:[self m_draggingobj]];
    if (idx >= 1 && mMCMixer != nil) [mMCMixer PlayPrePlay:m_draggingobj];
    if ([src m_imgv] != nil && [[src m_imgv] image] != nil) {
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectZero];
        [[self m_draggingobj] setM_imgv:iv];
        [self addSubview:[[self m_draggingobj] m_imgv]];
        [iv release];
        UIImage *copy = [[UIImage alloc] initWithCGImage:[[[src m_imgv] image] CGImage]];
        [[[self m_draggingobj] m_imgv] setImage:copy];
        [copy release];
    }
    if ([src m_swapimgv] != nil && [[src m_swapimgv] image] != nil) {
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectZero];
        [[self m_draggingobj] setM_swapimgv:iv];
        [self addSubview:[[self m_draggingobj] m_swapimgv]];
        [iv release];
        UIImage *copy = [[UIImage alloc] initWithCGImage:[[[src m_swapimgv] image] CGImage]];
        [[[self m_draggingobj] m_swapimgv] setImage:copy];
        [copy release];
    }
    if ([[self m_draggingobj] m_imgvtext] == nil) {
        int left = m_draggingrunningsong ? [self GetSongTimeLeft:[self m_draggingobj]] : -1;
        UIImageView *iv = [[UIImageView alloc] initWithImage:[m_glv CreateTextPicture:src withtime:left maxWidthPointer:NULL]];
        [[self m_draggingobj] setM_imgvtext:iv];
        [self addSubview:[[self m_draggingobj] m_imgvtext]];
        [iv release];
    }
    [[[self m_draggingobj] m_imgvtext] setAlpha:0.5f];
    if ([[self m_draggingobj] m_swapimgv] == nil) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:[m_glv CreateCDPicture:src roundpic:NO]];
        [[self m_draggingobj] setM_swapimgv:iv];
        [self addSubview:[[self m_draggingobj] m_swapimgv]];
        [iv release];
    }
    [[[self m_draggingobj] m_swapimgv] setAlpha:0.5f];
    [[[self m_draggingobj] m_imgv] setAlpha:0.0f];
    [[[self m_draggingobj] m_imgv] setFrame:CGRectMake(x - (float)(thumb >> 1), y - (float)(thumb >> 1), (float)thumb, (float)thumb)];
    [self bringSubviewToFront:[[self m_draggingobj] m_imgv]];
    CGRect f = [[[self m_draggingobj] m_imgv] frame];
    [[[self m_draggingobj] m_imgvtext] setFrame:CGRectMake(f.origin.x - 350.0f, (f.origin.y - f.size.height) - 23.0f,
                                                           (float)(thumb + 0x2bc), (float)((double)thumb * 3.0 * 0.25))];
    [self bringSubviewToFront:[[self m_draggingobj] m_imgvtext]];
    f = [[[self m_draggingobj] m_imgv] frame];
    [[[self m_draggingobj] m_swapimgv] setFrame:CGRectMake(f.origin.x + f.size.width * -0.5f, f.origin.y + f.size.height * -0.5f,
                                                           f.size.width + f.size.width, f.size.height + f.size.height)];
    [self bringSubviewToFront:[[self m_draggingobj] m_swapimgv]];
    m_draggingorigpos = idx;
    m_dragginposforremotecmds = idx;
    [src release];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (m_fadingover) return;
    if ([m_glv IsShowingChannelView]) return;
    UITouch *t = [touches anyObject];
    if (t == nil) return;
    CGPoint p = [t locationInView:self];
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    [self touchesMovedDelayed:po];
}

- (void)touchesMovedDelayed:(CGPointObject *)touchesMovedDelayed {
    float x = [touchesMovedDelayed x];
    float y = [touchesMovedDelayed y];
    [touchesMovedDelayed release];
    int thumb = THUMB;
    if ([self m_draggingobj] == nil) return;
    [[[self m_draggingobj] m_imgv] setFrame:CGRectMake(x - (float)(thumb >> 1), y - (float)(thumb >> 1), (float)thumb, (float)thumb)];
    CGRect f = [[[self m_draggingobj] m_imgv] frame];
    [[[self m_draggingobj] m_imgvtext] setFrame:CGRectMake(f.origin.x - 350.0f, (f.origin.y - f.size.height) - 23.0f,
                                                           (float)(thumb + 0x2bc), (float)((double)thumb * 3.0 * 0.25))];
    if ([[self m_draggingobj] m_swapimgv] != nil) {
        f = [[[self m_draggingobj] m_imgv] frame];
        [[[self m_draggingobj] m_swapimgv] setFrame:CGRectMake(f.origin.x + f.size.width * -0.5f, f.origin.y + f.size.height * -0.5f,
                                                               f.size.width + f.size.width, f.size.height + f.size.height)];
    }
    BOOL moved = fabsf(m_starttouchpoint.x - x) >= 18.0f || fabsf(m_starttouchpoint.y - y) >= 18.0f;
    if (!moved) return;
    if (m_draggingorigpos == -1) return;
    // the finger left the touch-down spot: take the original out of the queue
    if ((unsigned)m_draggingorigpos < [[self m_clips] count]) {
        if (m_draggingorigpos == 0) m_lastCDXDiff = 0;
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:m_draggingorigpos];
        if ([c m_imgv] != nil && [[c m_imgv] superview] != nil) [[c m_imgv] removeFromSuperview];
        if ([c m_imgvtext] != nil && [[c m_imgvtext] superview] != nil) [[c m_imgvtext] removeFromSuperview];
        if ([c m_swapimgv] != nil && [[c m_swapimgv] superview] != nil) [[c m_swapimgv] removeFromSuperview];
        [c setM_imgv:nil];
        [c setM_imgvtext:nil];
        [c setM_swapimgv:nil];
        if (m_draggingorigpos == 0) {
            m_rotateclip = NO;
            m_cliptorotate = nil;
        }
        [[self m_clips] rfx_removeObjectAtIndex:m_draggingorigpos];
        m_ordering = YES;
        if (m_draggingorigpos == 0) m_lastCDXDiff = 0;
        [UIView beginAnimations:@"OrderClipsAni" context:NULL];
        [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationDuration:0.6];
        [self OrderClipPics:[NSNumber numberWithInt:1]];
        [UIView commitAnimations];
        [self CheckQueueHintLabel];
    }
    m_draggingorigpos = -1;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    if (t == nil) return;
    CGPoint p = [t locationInView:self];
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    [self touchesEndedDelayed:po];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    if (t == nil) return;
    CGPoint p = [t locationInView:self];
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    [self touchesEndedDelayed:po];
}

// A tap on a queue thumbnail (second tap within 0.4s) -- shared by the "dragging obj discarded" and the plain path.
- (void)HandleQueueTapAtX:(float)x {
    if (startTime <= 0) {
        startTime = CACurrentMediaTime();
        return;
    }
    if (CACurrentMediaTime() - startTime >= 0.4) {
        startTime = CACurrentMediaTime();
        return;
    }
    int thumb = THUMB;
    float xdiff = [self m_ignoreXdiff] ? 0 : (float)m_lastCDXDiff;
    int maxIdx;
    if (ISIPAD) maxIdx = 9;
    else maxIdx = ([self frame].size.width > [self frame].size.height) ? 6 : 4;
    int idx = (int)(((x + xdiff) - (float)(border / 2)) / (float)(border + thumb));
    if (idx < maxIdx) {
        unsigned count = (unsigned)[[self m_clips] count];
        if (idx >= 1 && !((unsigned)idx >= count)) {
            if ([m_glv m_selectedfolderid] != -33) {
                int flags = [m_sve StateFlags];
                if ((flags & 0x10) == 0 && (flags & 4) == 0) {
                    // double tap on a queued song: play it now
                    m_fadingover = YES;
                    [self setM_rotateclip:NO];
                    m_cliptorotate = nil;
                    [self setM_presongInitTime:-1.0];
                    [self setM_crossfadeInitTime:-1.0];
                    if (idx >= 2) {
                        ClipObject *moved = [[[self m_clips] rfx_objectAtIndex:idx] retain];
                        if ([moved m_imgv] != nil) [self CorrectZindexComplete:moved];
                        [[self m_clips] rfx_removeObjectAtIndex:idx];
                        [[self m_clips] rfx_insertObject:moved atIndex:1];
                        [moved release];
                    }
                    ClipObject *first = [[[self m_clips] rfx_objectAtIndex:0] retain];
                    [[self m_clips] rfx_removeObjectAtIndex:0];
                    [self performSelector:@selector(FadeOverProcess:) withObject:nil afterDelay:0.8];
                    [self StartOrderAni:first];
                    [self performSelectorOnMainThread:@selector(CheckQueueHintLabel) withObject:nil waitUntilDone:YES];
                    [self SendCDsToBackGround];
                }
            }
        }
    } else {
        // tap right of the queue: open the keyboard / register
        if (m_blackview == nil) {
            if (![m_glv IsShowingMTScroller]) {
                if (![[m_glv GetKBView] m_keyboardshown]) {
                    if (([m_sve StateFlags] & 0x40000) == 0)
                        [m_glv ToggleKBAndRegister:[NSNumber numberWithInt:5]];
                }
            }
        }
    }
    startTime = -1.0;
}

- (void)touchesEndedDelayed:(CGPointObject *)touchesEndedDelayed {
    [m_glv RestartIdleTimer];
    [m_glv RestartAdvertTimer];
    float x = [touchesEndedDelayed x];
    float y = [touchesEndedDelayed y];
    [touchesEndedDelayed release];
    if (m_showfirstsongInfos && [[self m_clips] count] != 0) {
        m_showfirstsongInfos = NO;
        ClipObject *first = [[self m_clips] rfx_objectAtIndex:0];
        if ([first m_imgvtext] != nil) {
            [[first m_imgvtext] removeFromSuperview];
            [first setM_imgvtext:nil];
        }
    }
    if (![self g_scaling]) [m_glv CheckToRemoveRegister];

    BOOL discardDrag = m_fadingover || ([m_glv IsShowingChannelView] && !m_shutdown);
    if (discardDrag) {
        if ([self m_draggingobj] != nil) {
            ClipObject *obj = m_draggingobj;
            m_draggingobj = nil;
            [self performSelector:@selector(DeleteCDAni:) withObject:obj afterDelay:0.1];
        }
        return;
    }

    if ([self m_draggingobj] == nil) {
        [self HandleQueueTapAtX:x];
        return;
    }

    if (mMCMixer != nil) [mMCMixer StopPreplay];

    if (m_draggingorigpos != -1) {
        // the finger never left the touch-down spot: it was a tap, drop the drag copy
        m_draggingorigpos = -1;
        if ([m_draggingobj m_imgv] != nil && [[m_draggingobj m_imgv] superview] != nil) [[m_draggingobj m_imgv] removeFromSuperview];
        if ([m_draggingobj m_imgvtext] != nil && [[m_draggingobj m_imgvtext] superview] != nil) [[m_draggingobj m_imgvtext] removeFromSuperview];
        if ([m_draggingobj m_swapimgv] != nil && [[m_draggingobj m_swapimgv] superview] != nil) [[m_draggingobj m_swapimgv] removeFromSuperview];
        if (m_draggingobj != nil) {
            [m_draggingobj release];
            m_draggingobj = nil;
        }
        m_draggingrunningsong = NO;
        if (startTime > 0) {
            [self HandleQueueTapAtX:x];
        } else {
            startTime = CACurrentMediaTime();
            [self SendCDsToBackGround];
        }
        return;
    }

    // the dragged thumbnail was dropped: where?
    int pos = -5;
    BOOL removeFirst = NO;      // r4
    BOOL recalcXdiff = NO;      // r6
    BOOL rotateFirst = NO;      // r8
    int flags = [m_sve StateFlags];
    if (CGRectContainsPoint([m_glv frame], CGPointMake(x, y))) {
        // dropped on the coverflow: remove it from the queue
        if ((flags & 8) != 0) {
            pos = (int)[[self m_clips] count];
            [self CheckInsertPosition:&pos];
            removeFirst = YES;
        } else {
            ClipObject *obj = m_draggingobj;
            m_draggingobj = nil;
            if (m_draggingrunningsong) m_fadingover = YES;
            [self performSelector:@selector(DeleteCDAni:) withObject:obj afterDelay:0.1];
            [self performSelector:@selector(CheckPendingSong) withObject:nil afterDelay:0.7];
            removeFirst = YES;
        }
    } else {
        unsigned count = (unsigned)[[self m_clips] count];
        unsigned ins = (unsigned)[self GetInsertIndex:CGPointMake(x, y)];
        if (ins > count && count != 0) pos = (int)count;
        else pos = (int)ins;
        [self CheckInsertPosition:&pos];
        count = (unsigned)[[self m_clips] count];
        if (count == 0) {
            pos = 0;
            if (m_draggingrunningsong) {
                m_draggingrunningsong = NO;
                removeFirst = YES; recalcXdiff = YES; rotateFirst = YES;
            } else if (mMCMixer != nil && [mMCMixer isPlaying]) {
                if ((flags & 0x10) != 0) { removeFirst = YES; pos = 1; }
                else {
                    removeFirst = YES;
                    if (!m_playingjingle) {
                        m_fadingover = YES;
                        [self performSelector:@selector(FadeOverProcess:) withObject:nil afterDelay:0.8];
                    }
                }
            } else {
                pos = 0;
                removeFirst = YES;
            }
        } else if (pos == 0) {
            if (m_draggingrunningsong) {
                m_draggingrunningsong = NO;
                removeFirst = YES; recalcXdiff = YES; rotateFirst = YES;
            } else if (mMCMixer != nil && [mMCMixer isPlaying]) {
                if ((flags & 0x10) != 0) { removeFirst = YES; pos = 1; }
                else {
                    removeFirst = YES;
                    if (!m_playingjingle) {
                        m_fadingover = YES;
                        [self performSelector:@selector(FadeOverProcess:) withObject:nil afterDelay:0.8];
                    }
                }
            } else {
                removeFirst = YES;
            }
        } else if (m_draggingrunningsong) {
            if ((flags & 4) != 0) {
                pos = 0;
                m_draggingrunningsong = NO;
                removeFirst = YES; rotateFirst = YES;
            } else {
                m_draggingrunningsong = NO;
                [self setM_ignoreXdiff:YES];
                removeFirst = YES;
                if (!m_playingjingle) {
                    m_fadingover = YES;
                    [self performSelector:@selector(FadeOverProcess:) withObject:nil afterDelay:0.8];
                    removeFirst = NO;
                }
            }
        } else {
            removeFirst = YES;
        }
    }

    if (pos >= 0) {
        ClipObject *oldFirst = nil;     // local_c
        if (m_fadingover && removeFirst) {
            oldFirst = [[[self m_clips] rfx_objectAtIndex:0] retain];
            [[self m_clips] rfx_removeObjectAtIndex:0];
        }
        [[self m_clips] rfx_insertObject:[self m_draggingobj] atIndex:pos];
        m_dragginposforremotecmds = -1;
        [self CorrectZindexComplete:m_draggingobj];
        [m_draggingobj release];        // the array holds it now
        m_draggingobj = nil;
        if (recalcXdiff) {
            double played = CACurrentMediaTime() - [self m_clipStartTime];
            m_lastCDXDiff = (m_clipDuration > 0) ? [self CalcXDiff:(float)((m_clipDuration - played) / m_clipDuration)] : 0;
        }
        [self StartOrderAni:oldFirst];
        if (rotateFirst) {
            m_angle = 0;
            m_cliptorotate = [[self m_clips] rfx_objectAtIndex:0];
            m_rotateclip = YES;
        }
        [self CheckQueueHintLabel];
    }
    [self SendCDsToBackGround];
}

#pragma mark - pinch (volume)

- (void)scaleVolume:(UIPinchGestureRecognizer *)scaleVolume {
    float scale = (float)[scaleVolume scale];
    [self Restart30secsearchTimer];
    switch ([scaleVolume state]) {
    case UIGestureRecognizerStateEnded:
        [self setG_scaling:NO];
        [m_glv RestartIdleTimer];
        [m_glv RestartAdvertTimer];
        if ([m_glv m_pinchstatus] == 2) [[m_glv getScroller] RestartOverviewTimer];
        if ([[m_glv GetKBView] m_keyboardshown] && [[m_glv GetKBView] m_showwhat] == 0)
            [[m_glv GetKBView] RestartKeyboardtimerFast];
        if ([m_glv m_volumepinch] > 0) {
            [m_glv setM_volumepinch:-1.0f];
            [m_glv RemoveDraggingObject];
            [self SetLastVolumeKiosk];
        }
        break;
    case UIGestureRecognizerStateChanged:
        if ([m_glv m_volumepinch] > 0) {
            if (![self m_fadingover]) {
                double k = ISIPAD ? 1.0 : 2.0;
                float nv = (float)((double)[m_glv m_volumepinch] + (((double)scale - 1.0) * 0.5) * k);
                nv = fminf(1.0f, fmaxf(0.0f, nv));
                [self setM_lastvolume:nv];
                [self SetPlayerVolume:nv];
                [[m_glv GetKBView] SetVolSlider:[self m_lastvolume]];
            }
            [m_glv RemoveDraggingObject];
        }
        break;
    case UIGestureRecognizerStateBegan:
        [self setG_scaling:YES];
        [m_glv StopIdleTimer];
        [m_glv StopAdvertTimer];
        if ([m_glv m_pinchstatus] == 2) [[m_glv getScroller] RestartOverviewTimer];
        if (([m_glv m_lastflags] & 0x1000) != 0) return;
        if ([DEL m_useownvolume] != 0) return;
        [m_glv setM_volumepinch:[self GetPlayerVolume]];
        if ((double)[m_glv m_volumepinch] < 0.001) [m_glv setM_volumepinch:0.001f];
        [m_glv RemoveDraggingObject];
        if ([m_glv m_pinchstatus] == 2) {
            [[m_glv GetKBView] StopKeyboardtimer];
            [m_glv ShowVolumeForOverview];
        }
        if (![[m_glv GetKBView] m_keyboardshown]) {
            [[m_glv GetKBView] StopKeyboardtimer];
            [m_glv performSelector:@selector(ToggleKBAndRegister:) withObject:[NSNumber numberWithInt:0] afterDelay:0.01];
        }
        break;
    default:
        break;
    }
}

// Port diagnostics: one-time on-screen status for the first play request (no debugger on a sideloaded device).
static void KV_PlayStatus(NSString *text) {
    NSLog(@"[Play] %@", text);       // on-screen status window removed (log only)
}

#pragma mark - now playing

// ---- Now Playing / lock screen / Control Center (port addition) ------------------------------------------
- (void)SetupRemoteCommands {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    MPRemoteCommandCenter *rc = [MPRemoteCommandCenter sharedCommandCenter];
    [[rc playCommand] addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        if ([self m_pausebegintime] >= 0) [self OtherAudio:0]; else [self ContinuePlayers];
        [self UpdateNowPlayingRate];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [[rc pauseCommand] addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        if ([self m_pausebegintime] < 0) [self OtherAudio:0]; else [self PausePlayers];
        [self UpdateNowPlayingRate];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [[rc togglePlayPauseCommand] addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self OtherAudio:0];
        [self UpdateNowPlayingRate];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [[rc nextTrackCommand] addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        if ([[self m_clips] count] == 0) return MPRemoteCommandHandlerStatusNoActionableNowPlayingItem;
        [self CheckNextSong:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:0], @"how",
                             [NSNumber numberWithFloat:1.0f], @"time", nil]];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [[rc previousTrackCommand] setEnabled:NO];
    [[rc seekForwardCommand] setEnabled:NO];
    [[rc seekBackwardCommand] setEnabled:NO];
    [[rc changePlaybackPositionCommand] setEnabled:NO];
}

- (void)UpdateNowPlayingRate {
    MPNowPlayingInfoCenter *c = [MPNowPlayingInfoCenter defaultCenter];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:[c nowPlayingInfo]];
    if ([d count] == 0) return;
    BOOL paused = ([self m_pausebegintime] >= 0) || (mMCMixer != nil && ![mMCMixer isPlaying]);
    [d setObject:[NSNumber numberWithDouble:paused ? 0.0 : 1.0] forKey:MPNowPlayingInfoPropertyPlaybackRate];
    [c setNowPlayingInfo:d];
}

- (void)UpdateNowPlayingForClip:(ClipObject *)clip {
    if (clip == nil || [clip m_folderid] == -44 || [clip m_folderid] == -66) return;
    [self SetupRemoteCommands];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if ([clip m_title]) [d setObject:[clip m_title] forKey:MPMediaItemPropertyTitle];
    if ([clip m_interpret]) [d setObject:[clip m_interpret] forKey:MPMediaItemPropertyArtist];
    if ([clip m_albumname] && [[clip m_albumname] length]) [d setObject:[clip m_albumname] forKey:MPMediaItemPropertyAlbumTitle];
    if ([clip m_duration] > 0) [d setObject:[NSNumber numberWithInt:[clip m_duration]] forKey:MPMediaItemPropertyPlaybackDuration];
    [d setObject:[NSNumber numberWithDouble:0.0] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [d setObject:[NSNumber numberWithDouble:1.0] forKey:MPNowPlayingInfoPropertyPlaybackRate];
    UIImage *img = ([clip m_picturepath] != nil) ? [UIImage imageWithContentsOfFile:[clip m_picturepath]] : nil;
    if (img != nil) {
        MPMediaItemArtwork *art = [[MPMediaItemArtwork alloc] initWithBoundsSize:[img size]
                                                                  requestHandler:^UIImage *(CGSize sz) { return img; }];
        [d setObject:art forKey:MPMediaItemPropertyArtwork];
        [art release];
    }
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:d];
    // the real length is only known once the mixer has opened the file
    [self performSelector:@selector(RefreshNowPlayingDuration) withObject:nil afterDelay:1.0];
}

- (void)RefreshNowPlayingDuration {
    if (mMCMixer == nil) return;
    int dur = [mMCMixer duration];
    if (dur <= 0) return;
    MPNowPlayingInfoCenter *c = [MPNowPlayingInfoCenter defaultCenter];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:[c nowPlayingInfo]];
    if ([d count] == 0) return;
    [d setObject:[NSNumber numberWithInt:dur] forKey:MPMediaItemPropertyPlaybackDuration];
    [c setNowPlayingInfo:d];
}

#pragma mark - playback

- (BOOL)WillPlayJingle { return NO; }   // jingles are a server feature (GetReserved2Val) -- see DEVIATIONS.md

- (void)SetMixerFlags {
    // ambience (second audio source) is not part of the port, so only the stereo/mono flags remain
    int flags = [[self m_sve] StateFlags];
    if ((flags & 0x200000) != 0 || (flags & 0x400000) != 0) [mMCMixer setPlayMono];
    else [mMCMixer setPlayStereo];
    [mMCMixer setAllowPrePlay:((flags & 0x400000) != 0)];
}

- (void)PlayFileOnBackground:(NSString *)fileOnBackground {
    if ([self mMCMixer] != nil)
        [[self mMCMixer] PlayFile:fileOnBackground widthCrossfadeTime:m_crossfadetime inSteps:0x14];
}

- (void)StartOnePlayer:(int)onePlayer withVolume:(float)volume withurl:(NSURL *)url withclipobject:(ClipObject *)clipobject {
    if (url == nil) {
        NSString *pp = [clipobject m_picturepath];
        NSString *dirp = [pp stringByDeletingLastPathComponent];
        NSArray *list = (dirp != nil) ? [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirp error:nil] : nil;
        KV_PlayStatus([NSString stringWithFormat:@"no file for this clip (id %lld, folder %lld)\nfilepath: %@\npicture: %@\ntitle: %@ / %@\nfiles in folder: %@", [clipobject ID], [clipobject m_folderid], [clipobject m_filepath], pp, [clipobject m_interpret], [clipobject m_title], [list componentsJoinedByString:@" | "]]);
        return;
    }
    if ([clipobject m_folderid] == -66 || [clipobject m_folderid] == -44) { KV_PlayStatus(@"clip is a special folder, skipped"); return; }
    KV_PlayStatus([NSString stringWithFormat:@"play requested\n%@\nexists: %d\nout volume %.2f, mute %d", [url path], (int)[[NSFileManager defaultManager] fileExistsAtPath:[url path]], volume, (int)[DEL g_mute]]);
    if (mMCMixer == nil) mMCMixer = [[MultichannelMixerController alloc] init];
    [self SetMixerFlags];
    [mMCMixer startAUGraph];
    BOOL reduce = [DEL g_reduce];
    BOOL mute = [DEL g_mute];
    float v = mute ? 0.0f : (reduce ? volume * 0.25f : volume);
    [mMCMixer setOutputVolume:v];
    [self UpdateNowPlayingForClip:clipobject];
    [self performSelectorOnMainThread:@selector(PlayFileOnBackground:) withObject:[url path] waitUntilDone:NO];
    [mMCMixer setOutputVolume:v];
}

- (void)UpdateBackdropForClip:(ClipObject *)c {
    RfxBackdrop *bd = [RfxBackdrop shared];
    if (c == nil || ![[NSUserDefaults standardUserDefaults] boolForKey:@"RfxDevBackdrop"]) { [bd clear]; return; }
    RfxBDLog(@"Song gestartet, Hintergrund an");
    gRfxBackdropGL = m_glv;
    int gen = [bd bumpGen];
    NSString *title = [c m_title] ? [c m_title] : @"", *artist = [c m_interpret] ? [c m_interpret] : @"";
    RfxBDLog([NSString stringWithFormat:@"Titel: '%@' / Interpret: '%@'", title, artist]);
    // 1. a video of the user in Documents/Backdrops ("Artist - Title.mp4" or "Title.mp4"): works offline
    NSString *dir = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"Backdrops"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *want1 = [[NSString stringWithFormat:@"%@ - %@", artist, title] lowercaseString], *want2 = [title lowercaseString];
    for (NSString *fn in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
        NSString *ext = [[fn pathExtension] lowercaseString];
        if (![ext isEqualToString:@"mp4"] && ![ext isEqualToString:@"m4v"] && ![ext isEqualToString:@"mov"]) continue;
        NSString *base = [[fn stringByDeletingPathExtension] lowercaseString];
        if ([base length] > 0 && ([base isEqualToString:want1] || [base isEqualToString:want2])) {
            [bd showFile:[dir stringByAppendingPathComponent:fn] in:self behind:m_glv];
            return;
        }
    }
    // 2. the music video from YouTube: the YouTube Music plugin resolves it, the app downloads the 10 second excerpt (like the
    //    audio of a song) and plays that file in a loop.  The excerpt stays in the cache, so a known title starts at once.
    NSString *key = [[NSString stringWithFormat:@"%@|%@", artist, title] lowercaseString];
    NSDictionary *cache = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"RfxVideoIDCache"];
    NSString *known = [cache objectForKey:key];
    double cs = 0.0;
    NSString *cf = [RfxBackdrop cachedFileForVideoId:known start:&cs];
    if (cf != nil) { RfxBDLog([NSString stringWithFormat:@"Cache: %@", [cf lastPathComponent]]); [bd showFile:cf in:self behind:m_glv start:cs]; return; }
    [[RfxPluginManager shared] StreamVideoForTitle:title artist:artist videoId:known done:^(NSDictionary *r) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (r == nil) { RfxBDLog(@"kein Video gefunden/aufgelöst"); return; }
            NSString *vid = [r objectForKey:@"videoId"];
            RfxBDLog([NSString stringWithFormat:@"Video %@ aufgelöst, lade Ausschnitt", vid]);
            if ([vid length] > 0 && ![vid isEqualToString:known]) {
                NSMutableDictionary *cd = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"RfxVideoIDCache"]];
                [cd setObject:vid forKey:key];
                [[NSUserDefaults standardUserDefaults] setObject:cd forKey:@"RfxVideoIDCache"];
            }
            if ([bd gen] != gen) return;                         // another song started meanwhile
            NSDictionary *hd = [[r objectForKey:@"headers"] isKindOfClass:[NSDictionary class]] ? [r objectForKey:@"headers"] : nil;
            NSURL *vu = [NSURL URLWithString:[r objectForKey:@"url"]];
            double dsec = [[r objectForKey:@"duration_ms"] doubleValue] / 1000.0;
            [bd downloadURL:vu headers:hd duration:dsec bitrate:[[r objectForKey:@"bitrate"] doubleValue] videoId:vid done:^(NSString *path, double fs) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([bd gen] != gen) return;
                    RfxBDLog(path != nil ? [NSString stringWithFormat:@"Ausschnitt geladen: %@", [path lastPathComponent]] : @"Download fehlgeschlagen, streame");
                    if (path != nil) [bd showFile:path in:self behind:m_glv start:fs];
                    else [bd showURL:vu headers:hd duration:dsec in:self behind:m_glv];       // download refused: stream the excerpt instead
                });
            }];
        });
    }];
}

- (void)StartAudioPlayer:(ClipObject *)audioPlayer withAniNext:(BOOL)aniNext witharg1:(int)arg1 {
    [[RfxPluginManager shared] PlaybackStarted:audioPlayer];
    [self UpdateBackdropForClip:audioPlayer];
    if (audioPlayer != nil) {
        [m_glv MarkClipPlayed:audioPlayer];
        if ([audioPlayer ID] > 0)
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithLongLong:[audioPlayer ID]] forKey:@"RfxLastClipID"];
    }
    [self setM_crossfadeInitTime:-1.0];
    m_didfade = NO;
    m_spinHold = CACurrentMediaTime() + 6.0;      // the CD spins from the moment the song is started
    [m_glv performSelectorOnMainThread:@selector(drawView) withObject:nil waitUntilDone:NO];      // the cover starts to beat together with the CD
    [self RotationFrame];
    if (audioPlayer != nil && [audioPlayer m_folderid] != -44 && !m_autoselected) {
        DBOperations *dbop = [[DBOperations alloc] init];
        [DEL LockDB:YES];
        [dbop IncTimesPlayed:audioPlayer];
        [DEL UnlockDB];
        [dbop release];
    }
    NSURL *url = nil;
    if (audioPlayer != nil && [audioPlayer m_folderid] != -44 && [audioPlayer m_folderid] != -66 && [audioPlayer m_filepath] != nil)
        url = [NSURL fileURLWithPath:[audioPlayer m_filepath]];

    if (mMCMixer != nil && [mMCMixer isPlaying]) {
        // something is playing already: start the new song on the next bus (the mixer cross fades them)
        m_didfade = YES;
        BOOL pad = ISIPAD;
        NSUInteger count = [[self m_clips] count];
        int pinch = [m_glv m_pinchstatus];
        BOOL logo = !(pinch != 0 || count >= (NSUInteger)(pad ? 4 : 3));
        if (logo) [self LogoAni:[NSNumber numberWithInt:1]];
        [self StartOnePlayer:0 withVolume:[self m_lastvolume] withurl:url withclipobject:audioPlayer];
        // Port change: the new CD starts spinning and the queue starts to slide as soon as its song fades in
        // (the original waited for the whole cross fade first, ~5 s later).
        BOOL inQueue = (audioPlayer != nil && [[self m_clips] indexOfObjectIdenticalTo:audioPlayer] != NSNotFound);
        if (aniNext && inQueue) {
            m_angle = 0;
            m_lastRotTime = 0;
            m_cliptorotate = audioPlayer;
            [self setM_rotateclip:YES];
            if (logo) [self performSelector:@selector(LogoAni:) withObject:[NSNumber numberWithInt:0] afterDelay:(double)m_crossfadetime];
            m_oldindex = m_oldindex - 1;
            [self setM_resetfadeover:CACurrentMediaTime() + (double)m_crossfadetime + 0.9];
            m_restEarly = YES;
            if (!([DEL g_end] || gv_kioskflag) && [self AniToNextSong:audioPlayer withjingle:nil]) return;
            m_restEarly = NO;
        } else {
            double t0 = CACurrentMediaTime();
            for (;;) {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
                if (CACurrentMediaTime() >= t0 + (double)m_crossfadetime) break;
                if ([DEL g_end] || gv_kioskflag) break;
            }
            m_oldindex = m_oldindex - 1;
            if (logo && !([DEL g_end] || gv_kioskflag))
                [self LogoAni:[NSNumber numberWithInt:0]];
        }
    } else {
        m_fadingover = YES;
        m_crossfadetime = 2.0f;
        [self StartOnePlayer:0 withVolume:[self m_lastvolume] withurl:url withclipobject:audioPlayer];
        [self setM_resetfadeover:CACurrentMediaTime() + (double)m_crossfadetime + 0.9];
        if (aniNext && audioPlayer != nil && [[self m_clips] indexOfObjectIdenticalTo:audioPlayer] != NSNotFound) {
            m_angle = 0; m_lastRotTime = 0; m_cliptorotate = audioPlayer; [self setM_rotateclip:YES];
        }
        if ([[self m_clips] count] >= 2 && aniNext) {
            if ([self AniToNextSong:audioPlayer withjingle:nil]) return;
        }
    }
    if ([DEL g_end] || gv_kioskflag) return;
    [self StartAudioPlayerRest];
}

- (BOOL)AniToNextSong:(ClipObject *)aniToNextSong withjingle:(NSString *)jingle {
    ClipObject *first = [[self m_clips] rfx_objectAtIndex:0];
    if ([[self m_clips] count] >= 2) {
        BOOL keepSpin = (m_cliptorotate != nil && m_cliptorotate != first && [self m_rotateclip]);
        if (!keepSpin) {
            [self setM_rotateclip:NO];
            m_cliptorotate = nil;
        }
        RemoveClipViews(first);
        [[self m_clips] rfx_removeObjectAtIndex:0];
        m_ordering = YES;
        [self setM_ignoreXdiff:YES];
        [UIView beginAnimations:@"OrderClipsAni" context:NULL];
        [UIView setAnimationDidStopSelector:@selector(StartAudioPlayerRest)];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
        [UIView setAnimationDuration:1.6];
        [self OrderClipPics:[NSNumber numberWithInt:1]];
        [UIView commitAnimations];
        [self CheckPendingSong];
        [self CheckQueueHintLabel];
        return YES;
    }
    if ([[self m_clips] count] != 1) return NO;

    // the queue ran dry: pick the next song from the coverflow
    m_autoselected = YES;
    [self setM_tenmintimer:CACurrentMediaTime()];
    ClipObject *next = [m_glv getNextClipObject];
    RemoveClipViews(first);
    [[self m_clips] rfx_removeObjectAtIndex:0];
    if (next == nil) {
        [self setM_rotateclip:NO];
        m_cliptorotate = nil;
    } else {
        [[self m_clips] rfx_insertObject:next atIndex:0];
        [next release];
        [next setM_imgv:[[UIImageView alloc] initWithFrame:[self GetFrameForDragPic:0]]];
        [[next m_imgv] setImage:[m_glv CreateCDPicture:next roundpic:YES]];
        [self AddCDPictureToView:next];
        [[next m_imgv] release];
        [self CheckQueueHintLabel];
    }
    m_ordering = YES;
    [self setM_ignoreXdiff:YES];
    [UIView beginAnimations:@"OrderClipsAni" context:NULL];
    [UIView setAnimationDidStopSelector:(next != nil ? @selector(StartAudioPlayerRest) : @selector(OrderClipsReady))];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
    [UIView setAnimationDuration:1.6];
    [self OrderClipPics:[NSNumber numberWithInt:1]];
    [UIView commitAnimations];
    [self CheckPendingSong];
    [self CheckQueueHintLabel];
    return YES;
}

- (void)StartAudioPlayerRest {
    m_ordering = NO;
    ClipObject *clip = nil;
    if ([[self m_clips] count] != 0) clip = [[[self m_clips] rfx_objectAtIndex:0] retain];
    BOOL keepSpin = (clip != nil && m_cliptorotate == clip && [self m_rotateclip]);
    double keptAngle = m_angle;
    [self setM_shrinkdevider:NO];
    [self setM_rotateclip:NO];
    [self setM_presongInitTime:-1.0];
    [self SetDeviderPlayingPercent:0.0f];
    m_angle = keepSpin ? keptAngle : 0;
    m_cliptorotate = nil;
    int duration = 0;
    if (clip != nil) {
        m_cliptorotate = clip;
        [self setM_rotateclip:YES];
        if ([clip m_folderid] == -44 || [clip m_folderid] == -66 || mMCMixer == nil) {
            duration = [clip m_duration];
        } else {
            duration = [mMCMixer duration];
            if (duration == 0) duration = [clip m_duration];
        }
    }
    if (m_didfade && !m_restEarly) duration = (int)((float)duration - m_crossfadetime);
    m_restEarly = NO;
    int dur = (duration < 0xd) ? 0xd : duration;
    [self StartDevider:dur];
    [self StartPresongTimer:dur];
    [self StartCrossFadeTimer:dur];
    m_songcounter = m_songcounter + 1;
    [self setM_ignoreXdiff:NO];
    if ([self m_errorplayingsong]) {
        // the file could not be played: jump to the end of the song so the next one starts quickly
        [self setM_errorplayingsong:NO];
        double left = [self m_presongDuration] - (CACurrentMediaTime() - [self m_presongInitTime]);
        if ((left - 1.0) > 1.0) {
            [self setM_presongInitTime:[self m_presongInitTime] - (left - 1.0)];
            [self setM_crossfadeInitTime:[self m_crossfadeInitTime] - (left - 1.0)];
        }
    }
    [self CheckPendingSong];
    [clip release];
}

- (void)StartPresongTimer:(int)presongTimer {
    if (presongTimer < 0xb) return;
    [self setM_presongDuration:(double)(float)((double)presongTimer - fmax(7.0, (double)RfxFadeForDuration(presongTimer) + 2.0))];
    [self setM_presongInitTime:CACurrentMediaTime()];
}

- (void)StartCrossFadeTimer:(int)crossFadeTimer {
    m_curfade = RfxFadeForDuration(crossFadeTimer);
    [self setM_crossfadeDuration:(double)(float)((double)crossFadeTimer - (double)m_curfade)];
    [self setM_crossfadeInitTime:CACurrentMediaTime()];
}

// 7 seconds before the end of a song the next one is put into the queue (so the next cover shows up)
- (void)PresongTimerFunction {
    [self setM_presongInitTime:-1.0];
    if ([DEL m_isstattalm]) return;
    if (m_playingjingle) return;
    if ([[self m_clips] count] != 1) return;
    m_autoselected = YES;
    ClipObject *next = [m_glv getNextClipObject];
    if (next == nil) return;
    ClipObject *copy = [[ClipObject alloc] init];
    [self CopyPropertiesFromObject:next toObject:copy];
    [copy setM_imgv:[[UIImageView alloc] initWithFrame:CGRectZero]];
    [[copy m_imgv] setImage:[m_glv CreateCDPicture:copy roundpic:YES]];
    [self AddCDPictureToView:copy];
    [[copy m_imgv] release];
    [[copy m_imgv] setAlpha:0.0f];
    [[copy m_imgv] setFrame:[self MakeSmallFrame:[self GetFrameForDragPic:1]]];
    [[self m_clips] addObject:copy];
    [copy release];
    m_ordering = YES;
    [UIView beginAnimations:@"OrderClipsAni" context:NULL];
    [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDuration:0.6];
    [[copy m_imgv] setAlpha:1.0f];
    [[copy m_imgv] setFrame:[self GetFrameForDragPic:1]];
    [UIView commitAnimations];
    [next release];
    [self CheckQueueHintLabel];
}

- (void)FadeOverProcess:(id)fadeOverProcess {
    m_fadingover = YES;
    [fadeOverProcess release];          // the copy made by DeleteCDAni: (nil is fine); it was never released before
    fadeOverProcess = nil;
    [self setM_presongInitTime:-1.0];
    [self setM_rotateclip:NO];
    m_cliptorotate = nil;
    [self setM_shrinkdevider:NO];
    [self setM_crossfadeInitTime:-1.0];
    m_crossfadetime = 2.0f;
    ClipObject *clip = nil;
    BOOL have = NO;
    if ([[self m_clips] count] != 0) {
        clip = [[[self m_clips] rfx_objectAtIndex:0] retain];
        have = (clip != nil);
    } else {
        m_autoselected = YES;
        ClipObject *next = [m_glv getNextClipObject];
        if (next != nil) {
            [next retain];
            [[self m_clips] addObject:next];
            [next release];
            [next setM_imgv:[[UIImageView alloc] initWithFrame:[self GetFrameForDragPic:0]]];
            [[next m_imgv] setAlpha:0.0f];
            [[next m_imgv] setImage:[m_glv CreateCDPicture:next roundpic:YES]];
            [self AddCDPictureToView:next];
            [[next m_imgv] release];
            m_ordering = YES;
            [UIView beginAnimations:@"OrderClipsAni" context:NULL];
            [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
            [UIView setAnimationDelegate:self];
            [UIView setAnimationDuration:0.6];
            [[next m_imgv] setAlpha:1.0f];
            [UIView commitAnimations];
            [self CheckQueueHintLabel];
            clip = next;
            have = YES;
        }
    }
    if (have) {
        ClipObject *copy = [[ClipObject alloc] init];
        [self CopyPropertiesFromObject:clip toObject:copy];
        [self performSelector:@selector(SpinWhenNoAdvertising:) withObject:copy afterDelay:0.5];
        [self StartAudioPlayer:clip withAniNext:NO witharg1:1];
    }
    m_fadingover = NO;
    [self CheckPendingSong];
    if (have) [clip release];
}

- (void)SpinWhenNoAdvertising:(ClipObject *)spinWhenNoAdvertising {
    if (m_blackview != nil) {
        [self performSelector:@selector(SpinWhenNoAdvertising:) withObject:spinWhenNoAdvertising afterDelay:0];
        return;
    }
    if (![DEL g_end]) {
        if ([DEL IsBrandingPicturePresent])
            [self performSelector:@selector(SpinToBrandingPic) withObject:nil afterDelay:0];
        [m_glv SpinAutomaticToClip:spinWhenNoAdvertising orIndex:0];
    }
    [spinWhenNoAdvertising release];
}

- (void)SpinToBrandingPic {
    if (![DEL IsBrandingPicturePresent]) return;
    if ([m_glv m_fingersonscreen] > 0) return;
    ClipObject *c = [[ClipObject alloc] init];
    [c setID:-5];
    [m_glv SpinAutomaticToClip:c orIndex:0];
    [c release];
}

- (void)CheckNextSong:(NSDictionary *)nextSong {
    if (m_loadingscreen != nil) return;
    m_crossfadetime = [[nextSong objectForKey:@"time"] floatValue];
    int how = [[nextSong objectForKey:@"how"] intValue];
    // (original: when "auto selected" and an update was unzipped / the 5 o'clock flag was set the app exited here)
    m_fadingover = YES;
    if (m_draggingrunningsong) {
        m_draggingrunningsong = NO;
        [[self m_clips] rfx_insertObject:m_draggingobj atIndex:0];
        m_draggingobj = nil;
        [self CheckQueueHintLabel];
    }
    NSUInteger count = [[self m_clips] count];
    ClipObject *next = nil;
    if (count < 2) {
        if ([[self m_clips] count] == 1 && ![DEL m_isstattalm]) {
            next = [m_glv getNextClipObject];
            if (next != nil) {
                [[self m_clips] addObject:next];
                [next release];
                [next setM_imgv:[[UIImageView alloc] initWithFrame:[self GetFrameForDragPic:1]]];
                [[next m_imgv] setImage:[m_glv CreateCDPicture:next roundpic:YES]];
                [self AddCDPictureToView:next];
                [[next m_imgv] release];
                [self CheckQueueHintLabel];
            }
        }
    } else {
        next = [[self m_clips] rfx_objectAtIndex:1];
    }
    m_playingjingle = NO;
    if (next == nil) {
        // nothing left to play: the finished song slides out of the queue
        m_cliptorotate = nil;
        m_rotateclip = NO;
        m_ordering = YES;
        ClipObject *first = [[self m_clips] rfx_objectAtIndex:0];
        if (first != nil) {
            CGRect f = [[first m_imgv] frame];
            if ([first m_imgv] != nil) [[first m_imgv] setTransform:CGAffineTransformMakeRotation(0)];
            [UIView beginAnimations:@"OrderClipsAni" context:NULL];
            [UIView setAnimationDuration:0.6];
            [UIView setAnimationDidStopSelector:@selector(RemoveOnlyFirstClip)];
            [UIView setAnimationDelegate:self];
            [[first m_imgv] setFrame:CGRectMake(f.origin.x - 200.0f, f.origin.y, f.size.width, f.size.height)];
            [UIView commitAnimations];
        }
    } else {
        [self StartAudioPlayer:next withAniNext:YES witharg1:how];
        m_fadingover = ([self m_resetfadeover] > 0);
        ClipObject *copy = [[ClipObject alloc] init];
        [self CopyPropertiesFromObject:next toObject:copy];
        [self performSelector:@selector(SpinWhenNoAdvertising:) withObject:copy afterDelay:0.5];
    }
    [self SendCDsToBackGround];
}

- (void)StopPlayers {
    [[RfxPluginManager shared] PlaybackEnded];
    if (mMCMixer == nil) return;
    [mMCMixer StopPlayingBus:0];
    [mMCMixer StopPlayingBus:1];
    [mMCMixer StopPlayingBus:3];
    [mMCMixer StopPlayingBus:4];
    [mMCMixer StopPlayingBus:2];
    [mMCMixer stopAUGraph];
}

- (void)ContinuePlayers { if (mMCMixer != nil) [mMCMixer startAUGraph]; }
- (void)PausePlayers { [[RfxPluginManager shared] PlaybackEnded]; if (mMCMixer != nil) [mMCMixer stopAUGraph]; }

- (void)FlushGLForBackground { [m_glv FinishGL]; }

- (BOOL)IsPlayingClips {
    return (mMCMixer != nil && [mMCMixer isPlaying]) ? YES : NO;
}

- (void)SetPlayerVolume:(float)playerVolume {
    [self SetWdrPlayerVolume:playerVolume];
    BOOL reduce = [DEL g_reduce];
    BOOL mute = [DEL g_mute];
    if (mMCMixer != nil)
        [mMCMixer setOutputVolume:(mute ? 0.0f : (reduce ? playerVolume * 0.25f : playerVolume))];
}

- (void)SetWdrPlayerVolume:(float)wdrPlayerVolume {
    if (m_wdrplayer == nil) return;
    m_volumebefore = wdrPlayerVolume;
    [m_wdrplayer setVolume:wdrPlayerVolume];
}

- (float)GetPlayerVolume {
    return (mMCMixer != nil) ? [mMCMixer getOutputVolume] : 0.0f;
}

- (void)LowerVolume:(BOOL)lowerVolume {
    m_volumebefore = [self m_lastvolume];
    float start = [self m_lastvolume];
    for (int i = 10; i > 0; i--) {
        [self setM_lastvolume:[self m_lastvolume] - ((start * (lowerVolume ? 1.0f : 0.75f)) / 10.0f)];
        if ([self m_lastvolume] < 0) [self setM_lastvolume:0.0f];
        if ([self m_lastvolume] > 1.0f) [self setM_lastvolume:1.0f];
        if (mMCMixer != nil) [mMCMixer setOutputVolume:[self m_lastvolume]];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    }
}

- (void)RaiseVolume {
    [self setM_lastvolume:0.0f];
    for (int i = 10; i > 0; i--) {
        [self setM_lastvolume:[self m_lastvolume] + (m_volumebefore / 10.0f)];
        if (i == 1) [self setM_lastvolume:m_volumebefore];
        if ([self m_lastvolume] < 0) [self setM_lastvolume:0.0f];
        if ([self m_lastvolume] > 1.0f) [self setM_lastvolume:1.0f];
        if (mMCMixer != nil) [mMCMixer setOutputVolume:[self m_lastvolume]];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    }
}

- (void)SetLastVolumeKiosk {
    if ([DEL m_useownvolume] != 0) return;      // keep the user's own slider value while the system volume rules
    float v = [self m_lastvolume];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setFloat:fminf(1.0f, ((double)v < 0.001 ? 0.001f : v)) forKey:@"keykioskvolume"];
    [d synchronize];
}

- (void)ErrorPlayingSong { [self setM_errorplayingsong:YES]; }

// remote control events: 0 = play/pause, 1 = next song, -1 = previous song
- (void)OtherAudio:(int)otherAudio {
    if ([m_glv m_selectedfolderid] == -33) return;
    if (m_fadingover) return;
    if (otherAudio == -1) {
        if ([[self m_clips] count] != 0) {
            ClipObject *cur = [[self m_clips] rfx_objectAtIndex:0];
            [m_glv GetArrayLock:NO];
            int tile = 0, track = -1;
            BOOL found = NO;
            NSArray *tiles = [m_glv m_tilearray];
            for (tile = 0; (NSUInteger)tile < [tiles count] && !found; tile++) {
                ClipObject *t = [tiles objectAtIndex:tile];
                if ([t m_tracks] == nil) {
                    if ([t m_serverid] == [cur m_serverid] && [t ID] == [cur ID] && [t m_ipodid] == [cur m_ipodid]) {
                        track = -1; found = YES; break;
                    }
                } else {
                    for (NSUInteger k = 0; k < [[t m_tracks] count]; k++) {
                        ClipObject *tr = [[t m_tracks] objectAtIndex:k];
                        if ([tr m_serverid] == [cur m_serverid] && [tr ID] == [cur ID] && [tr m_ipodid] == [cur m_ipodid]) {
                            track = (int)k; found = YES; break;
                        }
                    }
                    if (found) break;
                }
            }
            ClipObject *prev = nil;
            if (found) {
                if (track == -1) { tile = tile - 1; track = -1; }
                else if (track != 0) { track = track - 1; }
                else { tile = tile - 1; track = 0; }
                if (tile <= -1) tile = (int)[[m_glv m_tilearray] count] - 1;
                ClipObject *t = [[m_glv m_tilearray] objectAtIndex:tile];
                ClipObject *item;
                if ([t m_tracks] != nil) {
                    if (track < 0 || (NSUInteger)track >= [[t m_tracks] count]) item = [[t m_tracks] lastObject];
                    else item = [[t m_tracks] objectAtIndex:track];
                } else item = t;
                if (item != nil) {
                    prev = [[ClipObject alloc] init];
                    [self CopyPropertiesFromObject:item toObject:prev];
                }
            }
            [m_glv releaseArraylock];
            if (prev != nil) {
                [[self m_clips] rfx_insertObject:prev atIndex:1];
                [prev setM_imgv:[[UIImageView alloc] initWithFrame:[self MakeSmallFrame:[self GetFrameForDragPic:1]]]];
                [[prev m_imgv] setImage:[m_glv CreateCDPicture:prev roundpic:YES]];
                [self AddCDPictureToView:prev];
                [[prev m_imgv] release];
                [prev release];
                [[prev m_imgv] setAlpha:0.0f];
                m_ordering = YES;
                [UIView beginAnimations:@"OrderClipsAni" context:NULL];
                [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
                [UIView setAnimationDelegate:self];
                [UIView setAnimationDuration:0.4];
                [[prev m_imgv] setAlpha:1.0f];
                [self OrderClipPics:[NSNumber numberWithInt:1]];
                [UIView commitAnimations];
                [self CheckQueueHintLabel];
            }
        }
    } else if (otherAudio == 1) {
        [self PresongTimerFunction];
        m_autoselected = NO;
    } else if (otherAudio == 0) {
        if ([self m_pausebegintime] >= 0) {
            [self ContinueFunction];
            return;
        }
        [self setM_pausebegintime:CACurrentMediaTime()];
        [self PausePlayers];
        [self setM_rotateclip:NO];
        [self setM_shrinkdevider:NO];
        return;
    }
    if ([[self m_clips] count] == 0) return;
    [self setM_presongInitTime:-1.0];
    [self setM_crossfadeInitTime:-1.0];
    [self CheckNextSong:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:0], @"how",
                                      [NSNumber numberWithFloat:1.0f], @"time", nil]];
}

- (void)ContinueFunction {
    [self ContinuePlayers];
    double now = CACurrentMediaTime();
    double paused = now - [self m_pausebegintime];
    [self setM_presongInitTime:[self m_presongInitTime] + paused];
    [self setM_crossfadeInitTime:[self m_crossfadeInitTime] + paused];
    [self setM_clipStartTime:[self m_clipStartTime] + paused];
    [self setM_rotateclip:YES];
    [self setM_shrinkdevider:YES];
    [self setM_pausebegintime:-1.0];
}

- (void)ReStartIfNeeded {
    if (!m_shutdown) {
        if ([m_glv m_selectedfolderid] != -33) {
            if ([self m_pausebegintime] > 0) [self ContinueFunction];
        }
    }
    [m_glv ResumeAfterBackground];
}

- (void)TryReleaseMMCMixer {
    if (mMCMixer == nil) return;
    if ([mMCMixer isPlaying]) return;
    [mMCMixer release];
    mMCMixer = nil;
}

- (void)CardReaderOff {
    if (m_glv != nil) [m_glv SwitchCardReaderLight:NO];
}

#pragma mark - divider / rotation

- (void)StartDevider:(int)d {
    [self SetDeviderPlayingPercent:1.0f];
    m_clipDuration = (double)d;
    [self setM_clipStartTime:CACurrentMediaTime()];
    [self setM_shrinkdevider:YES];
}

- (void)DeviderTimerFunc {
    double now = CACurrentMediaTime();
    double start = [self m_clipStartTime];
    if (m_clipDuration <= 0) return;
    [self SetDeviderPlayingPercent:(float)((m_clipDuration - (now - start)) / m_clipDuration)];
    if (((now - start) - 5.0) >= m_clipDuration)
        [self setM_shrinkdevider:NO];
}

- (int)CalcXDiff:(float)pct {
    int thumb = ISIPAD ? 0x52 : 0x38;
    int v = (int)((double)(float)thumb * (1.0 - (double)pct));
    int mx = border + thumb;
    if (v > mx) v = mx;
    return v <= 0 ? 0 : v;
}

- (void)SetDeviderPlayingPercent:(float)pct {
    int xd = [self CalcXDiff:pct];
    if (m_draggingrunningsong) {
        if ([[self m_clips] count] == 0)
            xd = 0;
        else if ([[[self m_clips] rfx_objectAtIndex:0] ID] != [m_draggingobj ID])
            xd = 0;
    }
    if (m_lastCDXDiff == xd || m_ordering) return;
    m_lastCDXDiff = xd;
    [self MoveCDs];
}

- (void)SetDeviderPlayingPercentDelayed:(NSNumber *)pct {
    [self SetDeviderPlayingPercent:[pct floatValue]];
}

- (void)SetDeviderPlayingPercentMT {
    [self SetDeviderPlayingPercent:0.0f];
}

// The spinning CD is a Core Animation rotation on the layer (runs on the render server, so it stays smooth even when the
// main thread is busy and it starts the moment it is added).  This supervisor (a few times per second) makes sure that
// exactly the first clip of the queue spins while a song is playing.
- (void)RotationFrame {
    ClipObject *first = ([[self m_clips] count] > 0) ? [[self m_clips] rfx_objectAtIndex:0] : nil;
    BOOL playing = (mMCMixer != nil && [mMCMixer isPlaying]) || CACurrentMediaTime() < m_spinHold;
    UIImageView *want = (first != nil && playing) ? [first m_imgv] : nil;
    if (want != nil && [want superview] == nil) want = nil;
    if (want != m_spinView) {
        if (m_spinView != nil) {
            [[m_spinView layer] removeAnimationForKey:@"rfxspin"];
            [m_spinView release];
            m_spinView = nil;
        }
        if (want != nil) m_spinView = [want retain];
    }
    if (m_spinView != nil && [[m_spinView layer] animationForKey:@"rfxspin"] == nil) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        [a setFromValue:[NSNumber numberWithFloat:0.0f]];
        [a setToValue:[NSNumber numberWithFloat:(float)(2.0 * M_PI)]];
        [a setDuration:9.0];                       // 40 degrees per second, as before
        [a setRepeatCount:HUGE_VALF];
        [a setRemovedOnCompletion:NO];
        [a setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
        [[m_spinView layer] addAnimation:a forKey:@"rfxspin"];
    }
}

- (void)RotationTimerFunction { [self RotationFrame]; }

- (void)LogoAni:(NSNumber *)logoAni {
    if ([(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] m_isstattalm]) return;
    int v = [logoAni intValue];
    [UIView beginAnimations:@"tobitlogoani" context:NULL];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.3];
    [m_tslogo setAlpha:v > 0 ? 1.0f : 0.0f];
    [UIView commitAnimations];
}

- (void)Restart30secsearchTimer {
    if ([self m_30secsearchInitTime] <= 0) return;
    [self setM_30secsearchInitTime:CACurrentMediaTime()];
}

- (void)ResetTACTime:(double)t {
    [m_glv setM_moveTACInitTime:t];
}

#pragma mark - kiosk shutdown

- (void)StartKioskShutdowntimer:(int)kioskShutdowntimer {
    if (m_shutdowntimer != nil) { [m_shutdowntimer invalidate]; m_shutdowntimer = nil; }
    m_shutdowntimer = [[NSTimer scheduledTimerWithTimeInterval:(double)kioskShutdowntimer
                                                         target:self
                                                       selector:@selector(ShutdownFunction:)
                                                       userInfo:nil repeats:NO] retain];
}

- (void)StopKioskShutdowntimer {
    if (m_shutdowntimer == nil) return;
    [m_shutdowntimer invalidate];
    m_shutdowntimer = nil;
}

- (void)ShutdownFunction:(id)timer {
    if (m_shutdowntimer != nil) { [m_shutdowntimer invalidate]; m_shutdowntimer = nil; }
    if (m_shutdown) return;
    m_shutdown = YES;
    [self setM_rotateclip:NO];
    [self setM_shrinkdevider:NO];
    [self setM_presongInitTime:-1.0];
    [self setM_crossfadeInitTime:-1.0];
    m_cliptorotate = nil;
    if (m_foldertimer != nil) { [m_foldertimer invalidate]; m_foldertimer = nil; }
    [self SetLastVolumeKiosk];
    [self StopPlayers];
    // original then showed the shutdown (TP) animation; dropped, see DEVIATIONS.md
}

- (void)EndFunction {
    gv_kioskflag = 1;
    cancelcopy = YES;
    [m_glv setM_drawempty:YES];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [m_glv ReInitThread];
    [NSThread sleepForTimeInterval:0.2];
    [self SetLastVolumeKiosk];
    [self StopPlayers];
    if (m_foldertimer != nil) { [m_foldertimer invalidate]; m_foldertimer = nil; }
    [self setM_rotateclip:NO];
    [self setM_shrinkdevider:NO];
    [self setM_presongInitTime:-1.0];
    [self setM_crossfadeInitTime:-1.0];
    [m_glv StopIdleTimer];
    [m_glv StopAdvertTimer];
    [m_glv GLVEndFunction];
    m_cliptorotate = nil;
    if (m_clips != nil) { [m_clips release]; m_clips = nil; }
}

#pragma mark - timer thread

- (void)TimerThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSThread setThreadPriority:0.8];
    KeyboardView *kb = [m_glv GetKBView];
    int iter = 0;
    double lastCheck = CACurrentMediaTime();
    RadioAppDelegate *dg = (RadioAppDelegate *)[[UIApplication sharedApplication] delegate];
    while (!gv_kioskflag) {
        if (++iter % 250 == 0) {
            [pool release];
            pool = [[NSAutoreleasePool alloc] init];
        }
        BOOL bg = [dg m_isinbackground];
        if ([self m_shrinkdevider] && !bg)
            [self performSelectorOnMainThread:@selector(DeviderTimerFunc) withObject:nil waitUntilDone:NO];

        if ([self m_presongInitTime] > 0 && [self m_pausebegintime] < 0) {
            if (CACurrentMediaTime() - [self m_presongInitTime] > [self m_presongDuration]) {
                [self setM_presongInitTime:-1.0];
                [self performSelectorOnMainThread:@selector(PresongTimerFunction) withObject:nil waitUntilDone:NO];
            }
        }
        if ([self m_crossfadeInitTime] > 0 && [self m_pausebegintime] < 0) {
            if (CACurrentMediaTime() - [self m_crossfadeInitTime] > [self m_crossfadeDuration]) {
                [self setM_crossfadeInitTime:-1.0];
                [self performSelectorOnMainThread:@selector(CheckNextSong:)
                    withObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithInt:1], @"how",
                                [NSNumber numberWithFloat:5.0f], @"time", nil]
                    waitUntilDone:NO];
            }
        }
        if ([m_glv m_idleinittime] > 0) {
            if (CACurrentMediaTime() - [m_glv m_idleinittime] > 65.0) {
                [m_glv setM_idleinittime:-1.0];
                [m_glv performSelectorOnMainThread:@selector(IdleTimerFunc) withObject:nil waitUntilDone:NO];
            }
        }
        if ([self m_limitinittime] > 0) {
            if (CACurrentMediaTime() - [self m_limitinittime] > [self m_limitduration]) {
                [self setM_limitinittime:-1.0];
                [self performSelectorOnMainThread:@selector(CheckLimitations) withObject:nil waitUntilDone:NO];
            }
        }
        if ([self m_30secsearchInitTime] > 0) {
            if (CACurrentMediaTime() - [self m_30secsearchInitTime] > 30.0) {
                [self setM_30secsearchInitTime:-1.0];
                [m_glv performSelectorOnMainThread:@selector(ForwardDelete30secSearchText) withObject:nil waitUntilDone:NO];
            }
        }
        if ([self m_resetfadeover] > 0 && CACurrentMediaTime() > [self m_resetfadeover]) {
            [self setM_resetfadeover:-1.0];
            m_fadingover = NO;
        }
        if ([kb m_keyboardinittime] > 0) {
            double to = ([kb m_showwhat] == 0) ? 10.0 : 30.0;
            if (CACurrentMediaTime() - [kb m_keyboardinittime] > to) {
                [kb setM_keyboardinittime:-1.0];
                [kb performSelectorOnMainThread:@selector(KBTimerFunc) withObject:nil waitUntilDone:NO];
            }
        }
        if (CACurrentMediaTime() - lastCheck > 1.0) {
            // main thread only: it reads the queue and the dragged clip, which the UI deletes at any time
            [self performSelectorOnMainThread:@selector(CheckRunningSongLeftTime) withObject:nil waitUntilDone:NO];
            lastCheck = CACurrentMediaTime();
        }
        [NSThread sleepForTimeInterval:bg ? 0.3 : 0.05];
    }
    [pool release];
}


// ---- recovered later (used by MTObject / MTScroller) ----

// nil and @"" are considered equal; otherwise plain string equality.
- (BOOL)spotifyIDsMatch:(NSString *)a withsecondid:(NSString *)b {
    if (a == nil && b == nil) return YES;
    if (b == nil)  return [a length] == 0;
    if (a == nil)  return [b length] == 0;
    return [b isEqualToString:a];
}

- (BOOL)selectedSpotifyIDMatches:(NSString *)other {
    return [self spotifyIDsMatch:[m_glv m_selectedspotifyfolderid] withsecondid:other];
}

// Grey-scale version of a tile picture (used for folders that are not the selected one):
// draw the picture, then multiply the "sw-mask" picture with luminosity blending.
- (UIImage *)BlackAndWhitePicture:(UIImage *)pic withfolderid:(long long)folderid {
    RadioAppDelegate *ad = (RadioAppDelegate *)[[UIApplication sharedApplication] delegate];
    float s = [ad m_isipad] ? 190.0f : 120.0f;
    CGContextRef c1 = [ad BeginImageContext:CGSizeMake(s, s)];
    if ([pic CGImage]) CGContextDrawImage(c1, CGRectMake(0, 0, s, s), [pic CGImage]);   // nil guard (deviation)
    UIImage *colored = [ad EndImageContext:c1];

    CGContextRef c2 = [ad BeginImageContext:CGSizeMake(s, s)];
    UIImage *mask = [UIImage imageNamed:((folderid | 2) == 3) ? @"sw-mask-rss.png" : @"sw-mask.png"];
    if ([mask CGImage]) CGContextDrawImage(c2, CGRectMake(0, 0, s, s), [mask CGImage]);
    CGContextSetBlendMode(c2, kCGBlendModeLuminosity);
    CGContextDrawImage(c2, CGRectMake(0, 0, s, s), [colored CGImage]);
    UIImage *res = [ad EndImageContext:c2];
    // Make sure nothing keeps a colour tint (the mask/luminosity blend left some): force R=G=B on the finished picture, alpha is kept.
    CGImageRef cg = [res CGImage];
    if (cg != NULL) {
        size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef bc = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(cs);
        if (bc != NULL) {
            CGContextDrawImage(bc, CGRectMake(0, 0, w, h), cg);
            unsigned char *px = (unsigned char *)CGBitmapContextGetData(bc);
            for (size_t i = 0; i < w * h; i++, px += 4) {
                unsigned char g = (unsigned char)((px[0] * 77 + px[1] * 151 + px[2] * 28) >> 8);
                px[0] = px[1] = px[2] = g;
            }
            CGImageRef gi = CGBitmapContextCreateImage(bc);
            if (gi != NULL) { res = [UIImage imageWithCGImage:gi scale:[res scale] orientation:UIImageOrientationUp]; CGImageRelease(gi); }
            CGContextRelease(bc);
        }
    }
    return [res retain];
}


// "*" marks folders of a foreign server; the "Musik" (-44) folder never gets one.
- (NSString *)BuildMTFoldername:(FolderObject *)folder {
    NSString *prefix;
    if ([folder folderid] == -44)                         prefix = @"";
    else if ([folder serverid] == [m_sve serverid])       prefix = @"";
    else                                                   prefix = @"*";
    return [NSString stringWithFormat:@"%@%@", prefix, [folder foldername]];
}

// iPhone only (re-fits the GL view to the radio layout); the iPad build returns at once.
- (void)FitGLViewForiPhone:(BOOL)radio {
    if ([(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] m_isipad]) return;
    // iPhone layout switch is not part of this iPad-only build.
}


// Parses the leading id of a folder/file name: "<id>-name" (or "<id>.xxx" for iPod strings).
- (long long)GetIDFromNSString:(NSString *)str withisipodstring:(BOOL)isipod {
    long long v = -1;
    const char *c = [DEL ConvertNSString:str withorder:0];
    int n = 0;
    if (c != NULL) n = sscanf(c, isipod ? "%lld." : "%lld-", &v);
    return (n != 1) ? -1 : v;
}


#pragma mark - remote control / online leftovers (inert offline)

- (id)GetRCConDeviceID {
    return (m_rcon == nil) ? nil : [m_rcon m_serverdeviceid];
}

// Lazily created (the original builds it in its setup code).
- (NSMutableDictionary *)m_nowdict {
    if (m_nowdict == nil) m_nowdict = [[NSMutableDictionary alloc] init];
    return m_nowdict;
}

// Looked a cover up at the "songdetails" web service; the service is gone.
- (UIImage *)GetSongPictureFor:(NSString *)title withinterpret:(NSString *)interpret {
    return nil;
}

// The original queued an RCQueueObject for the remote-control thread; without a connection
// (m_rcon == nil) it did nothing, which is the only case left.
- (void)InsertIntoRemoteQueue:(int)type withpoint:(CGPoint)point witharg1:(long long)arg1 witharg2:(int)arg2
                     witharg3:(int)arg3 withleaveoutclient:(long)leaveoutclient witharg4:(int)arg4 {
    if (m_rcon == nil) return;
}

// The animated help page (web/video help) is not part of the offline build.
- (void)StartHelpPictureAni { }

#pragma mark - help overlay (light bulb)

static NSArray *TutorialPages(void) {
    return [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"titel-finden", @"Titel auswählen", nil],
        [NSArray arrayWithObjects:@"reihenfolge-aendern", @"Reihenfolge ändern", nil],
        [NSArray arrayWithObjects:@"titel-abwaehlen", @"Titel aus der Queue entfernen", nil],
        [NSArray arrayWithObjects:@"titel-abbrechen", @"Titel abbrechen", nil],
        [NSArray arrayWithObjects:@"titel-loeschen", @"Titel entfernen", nil],
        [NSArray arrayWithObjects:@"lautstaerke-aendern", @"Lautstärke ändern", nil],
        [NSArray arrayWithObjects:@"kollektionen-anzeigen", @"Kollektion auswählen", nil],
        nil];
}

- (void)ShowTutorial {
    if ([self viewWithTag:7731] != nil) return;
    m_tutorialpage = 0;
    CGRect b = [self bounds];
    UIView *ov = [[UIView alloc] initWithFrame:b];
    [ov setTag:7731];
    [ov setBackgroundColor:[UIColor colorWithWhite:0.0f alpha:0.92f]];
    [ov setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake((b.size.width - 508.0f) * 0.5f, (b.size.height - 454.0f) * 0.5f - 30.0f, 508.0f, 454.0f)];
    [iv setTag:7732];
    [iv setContentMode:UIViewContentModeScaleAspectFit];
    [iv setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
    [ov addSubview:iv];
    [iv release];
    UILabel *cap = [[UILabel alloc] initWithFrame:CGRectMake(40.0f, (b.size.height + 454.0f) * 0.5f - 10.0f, b.size.width - 80.0f, 60.0f)];
    [cap setTag:7733];
    [cap setBackgroundColor:[UIColor clearColor]];
    [cap setTextColor:[UIColor whiteColor]];
    [cap setFont:[UIFont systemFontOfSize:22.0f]];
    [cap setTextAlignment:NSTextAlignmentCenter];
    [cap setNumberOfLines:2];
    [cap setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
    [ov addSubview:cap];
    [cap release];
    UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
    [x setFrame:CGRectMake(b.size.width - 70.0f, 20.0f, 50.0f, 50.0f)];
    [x setTitle:@"✕" forState:UIControlStateNormal];
    [x setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [[x titleLabel] setFont:[UIFont systemFontOfSize:26.0f]];
    [x setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin];
    [x addTarget:self action:@selector(CloseTutorial) forControlEvents:UIControlEventTouchUpInside];
    [ov addSubview:x];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(TutorialTap:)];
    [ov addGestureRecognizer:tap];
    [tap release];
    [ov setAlpha:0.0f];
    [self addSubview:ov];
    [ov release];
    [self ShowTutorialPage];
    [UIView animateWithDuration:0.25 animations:^{ [ov setAlpha:1.0f]; }];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(CloseTutorial) object:nil];
    [self performSelector:@selector(CloseTutorial) withObject:nil afterDelay:30.0];
}

- (void)ShowTutorialPage {
    UIView *ov = [self viewWithTag:7731];
    if (ov == nil) return;
    NSArray *pages = TutorialPages();
    if (m_tutorialpage >= (int)[pages count]) { [self CloseTutorial]; return; }
    NSArray *p = [pages objectAtIndex:m_tutorialpage];
    NSString *path = [[NSBundle mainBundle] pathForResource:[p objectAtIndex:0] ofType:@"png"];
    UIImage *img = path ? [UIImage imageWithContentsOfFile:path] : nil;
    [(UIImageView *)[ov viewWithTag:7732] setImage:img];
    [(UILabel *)[ov viewWithTag:7733] setText:[p objectAtIndex:1]];
}

- (void)TutorialTap:(UITapGestureRecognizer *)g {
    m_tutorialpage++;
    [self ShowTutorialPage];
}

- (void)CloseTutorial {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(CloseTutorial) object:nil];
    UIView *ov = [self viewWithTag:7731];
    if (ov == nil) return;
    [ov setTag:0];
    [UIView animateWithDuration:0.25 animations:^{ [ov setAlpha:0.0f]; } completion:^(BOOL f){ [ov removeFromSuperview]; }];
}




// Started the promo-video ("TP") tile animation of the overview; the video tile is not built offline.
- (void)StartTPAni:(id)arg { }
@end
