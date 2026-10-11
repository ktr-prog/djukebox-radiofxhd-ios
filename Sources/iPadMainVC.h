// iPadMainVC : UIViewController  (recovered; armv7 instance size 156)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class KioskView;

@interface iPadMainVC : UIViewController {
    KioskView *m_kioskview;
}
- (void)CheckRemoveChannelView;
- (void)StartKioskShutdowntimer:(int)kioskShutdowntimer;
- (void)SetKioskViewEnd;
- (void)ForwardRemoveDirectChannelKey;
- (void)ShowKioskMode;
- (id)GetKioskView;
- (id)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle;
@end
