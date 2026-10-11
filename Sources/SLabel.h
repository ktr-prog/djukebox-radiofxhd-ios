// SLabel : UILabel -- recovered from Radiofx_iPad (cell labels in the search result table)
#import <UIKit/UIKit.h>

@class KeyboardView;

@interface SLabel : UILabel {
    int m_index;               // +112
    int m_section;             // +116
    KeyboardView *m_kbpointer; // +120
}
@property (assign) int m_section;
@property (assign) int m_index;
- (void)touchesEnded:(NSSet *)touchesEnded withEvent:(UIEvent *)event;
- (void)SetKBPointer:(KeyboardView *)kBPointer;
- (id)init;
@end
