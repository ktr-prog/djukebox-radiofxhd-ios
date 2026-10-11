#import "NSString+RfxMatch.h"

@implementation NSString (RfxMatch)
// Normalises umlauts / punctuation and does a case-insensitive substring search.
- (BOOL)RfxMatchString:(NSString *)search {
    NSString *s = [self stringByReplacingOccurrencesOfRegex:@"[üÜ]" withString:@"ue"];
    s = [s stringByReplacingOccurrencesOfRegex:@"[öÖ]" withString:@"oe"];
    s = [s stringByReplacingOccurrencesOfRegex:@"[äÄ]" withString:@"ae"];
    s = [s stringByReplacingOccurrencesOfRegex:@"ß" withString:@"ss"];
    s = [s stringByReplacingOccurrencesOfRegex:@"[^a-zA-Z0-9 ]" withString:@""];
    return [s rangeOfString:search options:NSCaseInsensitiveSearch].location != NSNotFound;
}
@end
