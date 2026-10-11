// RadioVC : UIViewController (recovered; armv7 size 164)
#import <UIKit/UIKit.h>

@interface RadioVC : UIViewController {
    NSString *m_titlefordisplay;
    NSString *m_interpretfordisplay;
    NSMutableArray *m_pchannelinfos;
}
@property (nonatomic, retain) NSString *m_titlefordisplay;
@property (nonatomic, retain) NSString *m_interpretfordisplay;
- (void)SetpChannelInfos:(NSMutableArray *)infos;
- (id)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle;
@end
