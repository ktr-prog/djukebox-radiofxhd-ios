// ScrollerDictObject : NSObject -- recovered (instance size 44 on armv7)
// Cache entry for one folder of the "overview" (MTScroller) grid.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ScrollerDictObject : NSObject {
    int seconds;
    int numsongs;
    int midindex;
    long long midid;
    UIImage *img;
    long long midipodid;
    BOOL m_iscolorpic;
    NSString *midspotifyid;
}
@property (nonatomic, retain) NSString *midspotifyid;
@property (assign) BOOL m_iscolorpic;
@property (assign) long long midipodid;
@property (assign) long long midid;
@property (assign) int midindex;
@property (assign) int numsongs;
@property (assign) int seconds;
- (UIImage *)GetPic;
- (void)SetPic:(UIImage *)pic;
@end
