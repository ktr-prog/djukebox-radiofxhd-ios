// Port addition (not in the original app): imports audio files that the user drops into Documents/Import
// (Files app > On My iPad > Radio.fx > Import) every time the app starts.  See DEVIATIONS.md.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class ServerEntry;

@interface MusicImporter : NSObject
+ (void)ImportForServer:(ServerEntry *)server;
+ (NSSet *)audioExtensions;
+ (NSData *)SquareJPEG:(UIImage *)img size:(CGFloat)side;
+ (UIImage *)PlaceholderForTitle:(NSString *)title;
// IDs of the last song / folder written by ImportForServer: (0 if nothing was imported)
+ (long long)lastImportedClipID;
+ (long long)lastImportedFolderID;
// IDs of all songs written by the last ImportForServer (NSNumber, in import order)
+ (NSArray *)lastImportedClipIDs;
@end
