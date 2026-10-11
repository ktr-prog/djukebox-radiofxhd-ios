// Port addition (not in the original app): seeds a tiny demo library so the app can be tested on a device
// that has no music.  See DEVIATIONS.md.
#import <Foundation/Foundation.h>
@class ServerEntry;

@interface TestLibrary : NSObject
// If the library is empty, copies Resources/TestMusic/* into Documents/<SERVER>/<folder>/ and inserts the
// matching MTFolders / Mixxtapes rows.  Does nothing when any song exists (a real Radio.db is never touched).
+ (void)SeedIfEmptyForServer:(ServerEntry *)server;
@end
