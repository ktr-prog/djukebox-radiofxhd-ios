#import "NSString+RegexCompat.h"

@implementation NSString (RegexCompat)
- (NSString *)stringByReplacingOccurrencesOfRegex:(NSString *)regex withString:(NSString *)replacement {
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:regex options:0 error:&err];
    if (re == nil) return self;
    return [re stringByReplacingMatchesInString:self options:0 range:NSMakeRange(0, [self length]) withTemplate:replacement];
}
@end
