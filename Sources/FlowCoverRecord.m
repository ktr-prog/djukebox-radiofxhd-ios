// -[FlowCoverRecord initWithTexture:] @0x3fbb2  -[FlowCoverRecord dealloc] @0x3fbfc
#import "FlowCoverRecord.h"

@implementation FlowCoverRecord
@synthesize texture, percent;

- (id)initWithTexture:(GLuint)tex {
    self = [super init];
    if (self) {
        texture = tex;
        percent = 0;
    }
    return self;
}

- (void)dealloc {
    if (texture != 0)
        glDeleteTextures(1, &texture);
    [super dealloc];
}
@end
