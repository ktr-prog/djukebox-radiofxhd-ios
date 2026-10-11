// Port addition (not in the original app): earlier builds seeded a "Test Songs" demo folder.  It is gone now;
// this only cleans up what those builds left behind.  See DEVIATIONS.md.
#import <Foundation/Foundation.h>
@class ServerEntry;

@interface TestLibrary : NSObject
// Removes the demo folder "Test Songs" (folder id 100), its three songs and its files, if present.
+ (void)RemoveDemoForServer:(ServerEntry *)server;
@end
