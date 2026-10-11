#import "TestLibrary.h"
#import "RadioAppDelegate.h"
#import "DBOperations.h"
#import "ServerEntry.h"
#import "FolderObject.h"
#import "ClipObject.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@implementation TestLibrary

+ (void)SeedIfEmptyForServer:(ServerEntry *)server {
    if (server == nil) return;
    NSString *src = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"TestMusic"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:src]) return;

    // Only seed an empty library.
    [DEL LockDB:NO];
    DBOperations *db = [[DBOperations alloc] init];
    NSArray *ids = [db GetLibraryServerIDs];
    [db release];
    [DEL UnlockDB];
    if ([ids count] != 0) return;

    int sid = [server serverid];
    FolderObject *folder = [[FolderObject alloc] init];
    [folder setFoldername:@"Test Songs"];
    [folder setFolderid:1];
    [folder setServerid:sid];
    NSString *dir = [NSString stringWithFormat:@"%@%@/", [DEL CreateServerDir:server withfolderobject:folder], [DEL Buildfoldername:folder]];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    NSArray *files = [fm contentsOfDirectoryAtPath:src error:nil];
    for (NSString *f in files)
        [fm copyItemAtPath:[src stringByAppendingPathComponent:f] toPath:[dir stringByAppendingPathComponent:f] error:nil];

    NSString *names[3][2] = { {@"Test Artist A", @"Song One"}, {@"Test Artist B", @"Song Two"}, {@"Test Artist C", @"Song Three"} };
    [DEL LockDB:NO];
    db = [[DBOperations alloc] init];
    [db InsertFolder:folder];
    for (int i = 0; i < 3; i++) {
        ClipObject *co = [[ClipObject alloc] init];
        [co setID:i + 1];
        [co setM_interpret:names[i][0]];
        [co setM_title:names[i][1]];
        [co setM_folderid:1];
        [co setM_serverid:sid];
        [co setM_albumname:@""];
        [co setM_tracknumber:i + 1];
        [co setM_duration:30];
        [co setM_information:@""];
        [co setM_filename:@""];
        [co setM_channel:@""];
        [co setM_genre:@""];
        [db InsertClip:co withserverid:sid];
        [co release];
    }
    [db release];
    [DEL UnlockDB];
    [folder release];
}

@end
