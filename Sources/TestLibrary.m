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
    NSLog(@"[TestLibrary] %@", text);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *vc = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        while ([vc presentedViewController]) vc = [vc presentedViewController];
        if (vc == nil) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Demo library" message:text preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
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
    if (existing != 0) return; // real library (or already seeded): stay silent

    int sid = [server serverid];
    FolderObject *folder = [[FolderObject alloc] init];
    [folder setFoldername:@"Test Songs"];
    [folder setFolderid:100];   // 1, 3, -33, -44, -66 are reserved folder ids
    [folder setServerid:sid];
    NSString *dir = [NSString stringWithFormat:@"%@%@/", [DEL CreateServerDir:server withfolderobject:folder], [DEL Buildfoldername:folder]];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    NSArray *files = [fm contentsOfDirectoryAtPath:src error:nil];
    int copied = 0;
    for (NSString *f in files) {
        NSString *to = [dir stringByAppendingPathComponent:f];
        if ([fm fileExistsAtPath:to]) { copied++; continue; }
        if ([fm copyItemAtPath:[src stringByAppendingPathComponent:f] toPath:to error:nil]) copied++;
    }
    [log appendFormat:@"files copied: %d/%d\nserverid %d\n", copied, (int)[files count], sid];

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
