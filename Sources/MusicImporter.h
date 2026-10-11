// Port addition (not in the original app): imports audio files that the user drops into Documents/Import
// (Files app > On My iPad > Radio.fx > Import) every time the app starts.  See DEVIATIONS.md.
#import <Foundation/Foundation.h>
@class ServerEntry;

@interface MusicImporter : NSObject
+ (void)ImportForServer:(ServerEntry *)server;
@end
