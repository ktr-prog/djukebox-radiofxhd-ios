// Minimal replacement for the single RegexKitLite method the app uses
// (RegexKitLite's ICU-based implementation is not needed on modern iOS).
#import <Foundation/Foundation.h>

@interface NSString (RegexCompat)
- (NSString *)stringByReplacingOccurrencesOfRegex:(NSString *)regex withString:(NSString *)replacement;
@end
