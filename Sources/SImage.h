// SImage : UIImageView -- recovered from Radiofx_iPad (cell image in the search result table)
#import <UIKit/UIKit.h>

@class KeyboardView;

@interface SImage : UIImageView {
    long long m_id;           // +52
    int m_section;            // +60
    int m_index;              // +64
    KeyboardView *m_kbpointer; // +68
}
@property (assign) int m_section;
@property (assign) int m_index;
@property (assign) long long m_id;
- (void)touchesEnded:(NSSet *)touchesEnded withEvent:(UIEvent *)event;
- (void)SetKBPointer:(KeyboardView *)kBPointer;
- (id)init;
@end
