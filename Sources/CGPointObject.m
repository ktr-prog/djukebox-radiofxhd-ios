#import "CGPointObject.h"

@implementation CGPointObject
@synthesize x, y;

- (id)init {
    self = [super init];
    if (self != nil) {
        x = 0;
        y = 0;
    }
    return self;
}
@end
