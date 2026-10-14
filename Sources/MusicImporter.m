#import "MusicImporter.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "RadioAppDelegate.h"
#import "DBOperations.h"
#import "ServerEntry.h"
#import "FolderObject.h"
#import "ClipObject.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

// ---- Ogg Opus decoder (formerly RfxOpus.h/.m, merged here so no extra file has to be added to the project)
@interface RfxOpus : NSObject
+ (BOOL)available;
// Decodes src to a WAV at dst. tags gets title/artist/album/duration (NSNumber seconds); *art gets the embedded picture if any.
+ (BOOL)DecodeFile:(NSString *)src toWav:(NSString *)dst tags:(NSMutableDictionary *)tags art:(NSData **)art;
@end

#include <stdio.h>
#include <stdint.h>
#if RFX_HAVE_OPUSFILE
#include <opusfile.h>
#endif

@implementation RfxOpus

+ (BOOL)available {
#if RFX_HAVE_OPUSFILE
    return YES;
#else
    return NO;
#endif
}

#if RFX_HAVE_OPUSFILE
static void PutU32(unsigned char *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
static void PutU16(unsigned char *p, uint16_t v) { p[0] = v; p[1] = v >> 8; }

static void WavHeader(unsigned char *h, uint32_t dataBytes) {
    memcpy(h, "RIFF", 4);  PutU32(h + 4, 36 + dataBytes);
    memcpy(h + 8, "WAVEfmt ", 8);  PutU32(h + 16, 16);
    PutU16(h + 20, 1); PutU16(h + 22, 2);          // PCM, stereo
    PutU32(h + 24, 48000); PutU32(h + 28, 48000 * 4);
    PutU16(h + 32, 4); PutU16(h + 34, 16);
    memcpy(h + 36, "data", 4); PutU32(h + 40, dataBytes);
}

static NSString *Tag(const OpusTags *t, const char *name) {
    const char *v = opus_tags_query(t, name, 0);
    return v ? [NSString stringWithUTF8String:v] : nil;
}
#endif

+ (BOOL)DecodeFile:(NSString *)src toWav:(NSString *)dst tags:(NSMutableDictionary *)tags art:(NSData **)art {
#if RFX_HAVE_OPUSFILE
    int err = 0;
    OggOpusFile *of = op_open_file([src fileSystemRepresentation], &err);
    if (of == NULL) { NSLog(@"[Opus] cannot open %@ (%d)", src, err); return NO; }
    const OpusTags *t = op_tags(of, -1);
    if (t != NULL) {
        NSString *s;
        if ((s = Tag(t, "TITLE")))  [tags setObject:s forKey:@"title"];
        if ((s = Tag(t, "ARTIST"))) [tags setObject:s forKey:@"artist"];
        if ((s = Tag(t, "ALBUM")))  [tags setObject:s forKey:@"album"];
        int n = opus_tags_query_count(t, "METADATA_BLOCK_PICTURE");
        for (int i = 0; i < n && art != NULL && *art == nil; i++) {
            const char *v = opus_tags_query(t, "METADATA_BLOCK_PICTURE", i);
            OpusPictureTag pic;
            if (v != NULL && opus_picture_tag_parse(&pic, v) == 0) {
                if (pic.data_length > 0) *art = [NSData dataWithBytes:pic.data length:pic.data_length];
                opus_picture_tag_clear(&pic);
            }
        }
    }
    FILE *f = fopen([dst fileSystemRepresentation], "wb");
    if (f == NULL) { op_free(of); return NO; }
    unsigned char hdr[44];
    memset(hdr, 0, sizeof(hdr));
    fwrite(hdr, 1, sizeof(hdr), f);
    static opus_int16 buf[5760 * 2];
    uint64_t frames = 0;
    for (;;) {
        int n = op_read_stereo(of, buf, (int)(sizeof(buf) / sizeof(buf[0])));
        if (n == OP_HOLE) continue;
        if (n <= 0) break;
        fwrite(buf, 4, (size_t)n, f);
        frames += (uint64_t)n;
    }
    op_free(of);
    BOOL ok = frames > 0;
    if (ok) {
        WavHeader(hdr, (uint32_t)(frames * 4));
        fseek(f, 0, SEEK_SET);
        fwrite(hdr, 1, sizeof(hdr), f);
        [tags setObject:[NSNumber numberWithDouble:(double)frames / 48000.0] forKey:@"duration"];
    }
    fclose(f);
    if (!ok) [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
    return ok;
#else
    return NO;
#endif
}

@end


// Documents/Import/<file>              -> folder "Imported"
// Documents/Import/<name>/<file>       -> folder "<name>"
// Files are MOVED into the library, so the next start does not import them twice.
// Tags (title, artist, album, cover) come from the file; without tags "Artist - Title.ext" or the file name is used.
static long long gLastClipID = 0, gLastFolderID = 0;
static NSMutableArray *gLastClipIDs = nil;

@implementation MusicImporter

+ (long long)lastImportedClipID { return gLastClipID; }
+ (long long)lastImportedFolderID { return gLastFolderID; }
+ (NSArray *)lastImportedClipIDs { return gLastClipIDs ? [NSArray arrayWithArray:gLastClipIDs] : [NSArray array]; }

+ (NSSet *)audioExtensions {
    return [NSSet setWithObjects:@"mp3", @"m4a", @"mp4", @"m4b", @"m4r", @"aac", @"adts", @"wav", @"wave", @"aif", @"aiff", @"aifc", @"caf", @"flac",
            @"alac", @"mp2", @"mp1", @"ac3", @"ec3", @"amr", @"3gp", @"3g2", @"opus", @"ogg", @"oga", nil];
}

// aspect-fill square JPEG
+ (NSData *)SquareJPEG:(UIImage *)img size:(CGFloat)side {
    if (img == nil || [img size].width < 1 || [img size].height < 1) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), YES, 1.0);
    CGSize s = [img size];
    CGFloat k = MAX(side / s.width, side / s.height);
    CGFloat w = s.width * k, h = s.height * k;
    [img drawInRect:CGRectMake((side - w) * 0.5f, (side - h) * 0.5f, w, h)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return UIImageJPEGRepresentation(out, 0.9f);
}

// plain coloured tile with the first letter, for songs without any cover
+ (UIImage *)PlaceholderForTitle:(NSString *)title {
    CGFloat side = 196.0f;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), YES, 1.0);
    NSUInteger hue = 0;
    for (NSUInteger i = 0; i < [title length]; i++) hue = hue * 31 + [title characterAtIndex:i];
    [[UIColor colorWithHue:(CGFloat)(hue % 360) / 360.0f saturation:0.45f brightness:0.45f alpha:1.0f] setFill];
    UIRectFill(CGRectMake(0, 0, side, side));
    NSString *ch = [title length] ? [[title substringToIndex:1] uppercaseString] : @"?";
    NSDictionary *at = [NSDictionary dictionaryWithObjectsAndKeys:[UIFont boldSystemFontOfSize:110.0f], NSFontAttributeName,
                        [UIColor colorWithWhite:1.0f alpha:0.35f], NSForegroundColorAttributeName, nil];
    CGSize cs = [ch sizeWithAttributes:at];
    [ch drawAtPoint:CGPointMake((side - cs.width) * 0.5f, (side - cs.height) * 0.5f) withAttributes:at];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

+ (void)ImportForServer:(ServerEntry *)server {
    gLastClipID = 0; gLastFolderID = 0;
    if (gLastClipIDs == nil) gLastClipIDs = [[NSMutableArray alloc] init];
    [gLastClipIDs removeAllObjects];
    if (server == nil) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *importDir = [docs stringByAppendingPathComponent:@"Import"];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:importDir isDirectory:&isDir]) {
        [fm createDirectoryAtPath:importDir withIntermediateDirectories:YES attributes:nil error:nil];
        return;
    }

    // collect the audio files
    NSMutableArray *found = [NSMutableArray array];       // relative paths
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:importDir];
    for (NSString *rel in en) {
        if ([[[rel lastPathComponent] lowercaseString] hasPrefix:@"."]) continue;
        if (![[self audioExtensions] containsObject:[[rel pathExtension] lowercaseString]]) continue;
        [found addObject:rel];
    }
    if ([found count] == 0) return;
    [found sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    int sid = [server serverid];
    [DEL LockDB:NO];
    DBOperations *db = [[DBOperations alloc] init];
    long long nextID = [db MaxClipID];
    if (nextID < 999) nextID = 999;                       // 1..3 are the demo songs
    long long nextFolder = [db MaxFolderID];
    if (nextFolder < 199) nextFolder = 199;               // 1, 3, -33, -44, -66 are reserved; 100 = demo folder
    NSMutableDictionary *folders = [NSMutableDictionary dictionary];     // name -> FolderObject
    int imported = 0;

    for (NSString *rel in found) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *src = [importDir stringByAppendingPathComponent:rel];
        NSString *ext = [[rel pathExtension] lowercaseString];
        NSArray *parts = [rel pathComponents];
        NSString *folderName = ([parts count] > 1) ? [parts objectAtIndex:0] : @"Imported";

        // ---- Ogg Opus is not readable by Core Audio: decode it to WAV first (the original file is deleted after the import)
        NSString *origSrc = nil;
        NSMutableDictionary *opusTags = [NSMutableDictionary dictionary];
        NSData *opusArt = nil;
        if ([ext isEqualToString:@"opus"] || [ext isEqualToString:@"ogg"] || [ext isEqualToString:@"oga"]) {
            NSString *wav = [[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"rfx-opus-%d", (int)[found indexOfObject:rel]]] stringByAppendingPathExtension:@"wav"];
            if (![RfxOpus DecodeFile:src toWav:wav tags:opusTags art:&opusArt]) {
                NSLog(@"[Import] %@ skipped: cannot decode (Opus support %@)", rel, [RfxOpus available] ? @"present, file is not Ogg Opus" : @"not built in");
                [pool release];
                continue;
            }
            origSrc = src;
            src = wav;
            ext = @"wav";
        }

        // ---- tags
        NSString *title = nil, *artist = nil, *album = nil;
        NSData *art = nil;
        int duration = 0;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:src] options:nil];
        NSArray *meta = [asset commonMetadata];
        for (AVMetadataItem *it in meta) {
            NSString *key = [it commonKey];
            if ([key isEqualToString:@"title"] && title == nil) title = [it stringValue];
            else if ([key isEqualToString:@"artist"] && artist == nil) artist = [it stringValue];
            else if ([key isEqualToString:@"albumName"] && album == nil) album = [it stringValue];
            else if ([key isEqualToString:@"artwork"] && art == nil) {
                id v = [it value];
                if ([v isKindOfClass:[NSData class]]) art = v;
                else if ([it dataValue] != nil) art = [it dataValue];
            }
        }
        double secs = CMTimeGetSeconds([asset duration]);
        if (secs > 0 && secs < 1.0e6) duration = (int)(secs + 0.5);
        NSString *base = [[[rel lastPathComponent] stringByDeletingPathExtension] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (origSrc != nil) {
            if (title == nil)  title = [opusTags objectForKey:@"title"];
            if (artist == nil) artist = [opusTags objectForKey:@"artist"];
            if (album == nil)  album = [opusTags objectForKey:@"album"];
            if (art == nil)    art = opusArt;
            if (duration == 0) duration = (int)([[opusTags objectForKey:@"duration"] doubleValue] + 0.5);
        }
        if ([title length] == 0) {
            NSRange r = [base rangeOfString:@" - "];
            if (r.location != NSNotFound && r.location > 0) {
                if ([artist length] == 0) artist = [base substringToIndex:r.location];
                title = [base substringFromIndex:r.location + 3];
            } else {
                title = base;
            }
        }
        if ([artist length] == 0) artist = @"Unknown Artist";
        if ([album length] == 0) album = @"";

        // ---- cover: embedded, else a same-named / folder.jpg / cover.jpg picture next to the file
        // The cover is kept byte-for-byte: embedded art or the sidecar picture is copied unchanged
        // (no resize / re-encode); only the small thumbnail is generated.
        UIImage *cover = (art != nil) ? [UIImage imageWithData:art] : nil;
        NSData *coverBytes = (cover != nil) ? art : nil;
        if (cover == nil) {
            NSString *coverRef = (origSrc != nil) ? origSrc : src;
            NSString *dir = [coverRef stringByDeletingLastPathComponent];
            NSString *stem = [coverRef stringByDeletingPathExtension];
            for (NSString *cand in [NSArray arrayWithObjects:[stem stringByAppendingPathExtension:@"jpg"], [stem stringByAppendingPathExtension:@"png"],
                                    [dir stringByAppendingPathComponent:@"cover.jpg"], [dir stringByAppendingPathComponent:@"folder.jpg"],
                                    [dir stringByAppendingPathComponent:@"cover.png"], [dir stringByAppendingPathComponent:@"folder.png"], nil]) {
                if ([fm fileExistsAtPath:cand]) { coverBytes = [NSData dataWithContentsOfFile:cand]; cover = [UIImage imageWithData:coverBytes]; if (cover != nil) break; coverBytes = nil; }
            }
        }
        if (cover == nil) { cover = [self PlaceholderForTitle:title]; coverBytes = nil; }

        // ---- folder
        FolderObject *folder = [folders objectForKey:folderName];
        if (folder == nil) {
            folder = [[[FolderObject alloc] init] autorelease];
            [folder setFoldername:folderName];
            [folder setServerid:sid];
            long long fid = [db FolderIDForName:folderName serverid:sid];
            if (fid < 0) { fid = ++nextFolder; }
            [folder setFolderid:fid];
            [db InsertFolder:folder];
            [folders setObject:folder forKey:folderName];
        }
        NSString *fdir = [NSString stringWithFormat:@"%@%@/", [DEL CreateServerDir:server withfolderobject:folder], [DEL Buildfoldername:folder]];
        [fm createDirectoryAtPath:fdir withIntermediateDirectories:YES attributes:nil error:nil];

        // ---- clip row + file names (BuildAndCheckFilePathes makes "<ID>-<artist>-<title>.mp3" with the app's own shortening)
        ClipObject *co = [[ClipObject alloc] init];
        [co setID:++nextID];
        [co setM_interpret:artist];
        [co setM_title:title];
        [co setM_albumname:album];
        [co setM_folderid:[folder folderid]];
        [co setM_serverid:sid];
        [co setM_tracknumber:0];
        [co setM_duration:duration];
        [co setM_information:@""];
        [co setM_filename:@""];
        [co setM_channel:@""];
        [co setM_genre:@""];
        [DEL BuildAndCheckFilePathes:co withfm:fm withserverdir:fdir withCheck:NO];
        NSString *dest = [[[co m_filepath] stringByDeletingPathExtension] stringByAppendingPathExtension:ext];
        NSString *pic = [co m_picturepath];

        NSError *err = nil;
        BOOL moved = [fm moveItemAtPath:src toPath:dest error:&err];
        if (!moved) moved = [fm copyItemAtPath:src toPath:dest error:&err] && [fm removeItemAtPath:src error:nil];
        if (moved) {
            if (origSrc != nil) [fm removeItemAtPath:origSrc error:nil];
            NSData *big = (coverBytes != nil) ? coverBytes : [self SquareJPEG:cover size:512.0f];
            NSData *small = [self SquareJPEG:cover size:40.0f];
            if (big) [big writeToFile:pic atomically:YES];
            if (small) [small writeToFile:[DEL BuildSmallPicpath:pic] atomically:YES];
            // the original app's sidecar picture (same name as the sound file) is what the importer will find next time
            if ([db InsertClip:co withserverid:sid]) { imported++; gLastClipID = [co ID]; gLastFolderID = [folder folderid]; [gLastClipIDs addObject:[NSNumber numberWithLongLong:[co ID]]]; }
        } else {
            NSLog(@"[Import] could not move %@: %@", src, err);
        }
        [co release];
        [pool release];
    }
    [db release];
    [DEL UnlockDB];

    // remove sub-folders that are empty now
    for (NSString *name in [fm contentsOfDirectoryAtPath:importDir error:nil]) {
        NSString *p = [importDir stringByAppendingPathComponent:name];
        BOOL d = NO;
        if ([fm fileExistsAtPath:p isDirectory:&d] && d && [[fm contentsOfDirectoryAtPath:p error:nil] count] == 0)
            [fm removeItemAtPath:p error:nil];
    }
    NSLog(@"[Import] imported %d of %d files", imported, (int)[found count]);
}

@end
