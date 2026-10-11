#import "TestLibrary.h"
#import "RadioAppDelegate.h"
#import "DBOperations.h"
#import "ServerEntry.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@implementation TestLibrary

+ (void)RemoveDemoForServer:(ServerEntry *)server {
    if (server == nil) return;
    [DEL LockDB:NO];
    DBOperations *db = [[DBOperations alloc] init];
    [db DeleteDemoFolder];
    [db DeleteLegacyDemoRows];
    [db release];
    [DEL UnlockDB];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = [NSString stringWithFormat:@"%@/Documents/%@", [DEL GetHomeDir], [[server servername] uppercaseString]];
    [fm removeItemAtPath:[base stringByAppendingPathComponent:@"100-Test Songs"] error:nil];
    [fm removeItemAtPath:[base stringByAppendingPathComponent:@"1-Test Songs"] error:nil];
}

@end
