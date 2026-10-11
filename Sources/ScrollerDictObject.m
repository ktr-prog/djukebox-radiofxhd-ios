#import "ScrollerDictObject.h"

@implementation ScrollerDictObject
@synthesize midspotifyid, m_iscolorpic, midipodid, midid, midindex, numsongs, seconds;

- (id)init {
    self = [super init];
    if (self) {
        numsongs = 0; seconds = 0; midindex = 0;
        midid = 0; midipodid = 0;
        img = nil; m_iscolorpic = NO; midspotifyid = nil;
    }
    return self;
}

- (void)dealloc {
    if (midspotifyid != nil) { [midspotifyid release]; midspotifyid = nil; }
    [super dealloc];
}

// The picture is *not* retained here (original behaviour): the consumer
// (MTObject OverviewNextMT:) releases it after it has been handed to the image view.
- (UIImage *)GetPic { return img; }
- (void)SetPic:(UIImage *)pic { img = pic; }
@end
