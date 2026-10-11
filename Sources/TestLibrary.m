#import "TestLibrary.h"
#import "RadioAppDelegate.h"
#import "DBOperations.h"
#import "ServerEntry.h"
#import "FolderObject.h"
#import "ClipObject.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@implementation TestLibrary

// Shows a one-time status box so a failed seed can be diagnosed on a device without a debugger.
+ (void)ShowStatus:(NSString *)text {
    NSLog(@"[TestLibrary] %@", text);       // on-screen status window removed (log only)
}

// Copies Resources/TestMusic/* into dir.  A repo upload may rename duplicates ("name (1).mp3") and add stray
// files, so names are normalised and only mp3/jpg files are copied.  Existing files are left alone.
+ (int)CopyDemoFilesTo:(NSString *)dir {
    NSString *src = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"TestMusic"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSRegularExpression *dup = [NSRegularExpression regularExpressionWithPattern:@" \\(\\d+\\)(?=\\.[A-Za-z0-9]+$)" options:0 error:nil];
    int ok = 0;
    for (NSString *f in [fm contentsOfDirectoryAtPath:src error:nil]) {
        NSString *ext = [[f pathExtension] lowercaseString];
        if (![ext isEqualToString:@"mp3"] && ![ext isEqualToString:@"jpg"]) continue;
        NSString *name = [dup stringByReplacingMatchesInString:f options:0 range:NSMakeRange(0, [f length]) withTemplate:@""];
        NSString *to = [dir stringByAppendingPathComponent:name];
        NSString *from = [src stringByAppendingPathComponent:f];
        if ([fm fileExistsAtPath:to]) {
            // replace a demo file that differs from the bundled one (e.g. regenerated test tones)
            unsigned long long a = [[fm attributesOfItemAtPath:from error:nil] fileSize];
            unsigned long long b = [[fm attributesOfItemAtPath:to error:nil] fileSize];
            if (a == b) { ok++; continue; }
            [fm removeItemAtPath:to error:nil];
        }
        if ([fm copyItemAtPath:from toPath:to error:nil]) ok++;
    }
    return ok;
}

+ (void)SeedIfEmptyForServer:(ServerEntry *)server {
    NSMutableString *log = [NSMutableString string];
    if (server == nil) { [self ShowStatus:@"no server entry"]; return; }
    NSString *src = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"TestMusic"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:src]) { [self ShowStatus:@"TestMusic folder is not in the app bundle (files missing in the repo?)"]; return; }

    // An earlier build used folder id 1, which the app reserves for a special folder: remove those rows.
    [DEL LockDB:NO];
    DBOperations *db = [[DBOperations alloc] init];
    [db DeleteLegacyDemoRows];
    [db release];
    [DEL UnlockDB];
    {
        NSString *oldDir = [NSString stringWithFormat:@"%@/Documents/%@/1-Test Songs", [DEL GetHomeDir], [[server servername] uppercaseString]];
        [fm removeItemAtPath:oldDir error:nil];
    }

    // Only seed when there is not a single song.
    [DEL LockDB:NO];
    db = [[DBOperations alloc] init];
    int existing = [db CountAllSongs];
    [db release];
    [DEL UnlockDB];
    if (existing != 0) {
        // Already seeded (or a real library).  Only the demo folder is ever touched: re-copy missing demo
        // files (e.g. after an earlier build stored them under wrong names).
        FolderObject *df = [[FolderObject alloc] init];
        [df setFoldername:@"Test Songs"];
        [df setFolderid:100];
        [df setServerid:[server serverid]];
        NSString *ddir = [NSString stringWithFormat:@"%@%@/", [DEL CreateServerDir:server withfolderobject:df], [DEL Buildfoldername:df]];
        [df release];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:ddir isDirectory:&isDir] && isDir) [self CopyDemoFilesTo:ddir];
        return;
    }

    int sid = [server serverid];
    FolderObject *folder = [[FolderObject alloc] init];
    [folder setFoldername:@"Test Songs"];
    [folder setFolderid:100];   // 1, 3, -33, -44, -66 are reserved folder ids
    [folder setServerid:sid];
    NSString *dir = [NSString stringWithFormat:@"%@%@/", [DEL CreateServerDir:server withfolderobject:folder], [DEL Buildfoldername:folder]];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    int copied = [self CopyDemoFilesTo:dir];
    [log appendFormat:@"files copied: %d (expected 9)\nserverid %d\n", copied, sid];

    NSString *names[3][2] = { {@"Test Artist A", @"Song One"}, {@"Test Artist B", @"Song Two"}, {@"Test Artist C", @"Song Three"} };
    [DEL LockDB:NO];
    db = [[DBOperations alloc] init];
    [log appendFormat:@"folder insert: %@\n", [db InsertFolder:folder] ? @"ok" : @"FAILED"];
    for (int i = 0; i < 3; i++) {
        ClipObject *co = [[ClipObject alloc] init];
        [co setID:i + 1];
        [co setM_interpret:names[i][0]];
        [co setM_title:names[i][1]];
        [co setM_folderid:100];
        [co setM_serverid:sid];
        [co setM_albumname:@""];
        [co setM_tracknumber:i + 1];
        [co setM_duration:30];
        [co setM_information:@""];
        [co setM_filename:@""];
        [co setM_channel:@""];
        [co setM_genre:@""];
        [log appendFormat:@"song %d insert: %@\n", i + 1, [db InsertClip:co withserverid:sid] ? @"ok" : @"FAILED"];
        [co release];
    }
    [log appendFormat:@"songs in DB now: %d\n", [db CountAllSongs]];
    NSMutableArray *vis = [db GetFolders:server onlyexclude:NO checkempty:YES withLimits:YES withremotefolders:YES join:YES];
    [log appendFormat:@"folders the app will list: %d", (int)[vis count]];
    [vis release];
    [db release];
    [DEL UnlockDB];
    [folder release];
    [self ShowStatus:log];
}

@end
