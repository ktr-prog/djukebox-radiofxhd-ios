#import "SLabel.h"
#import "KeyboardView.h"

@implementation SLabel
@synthesize m_section, m_index;

- (void)touchesEnded:(NSSet *)touchesEnded withEvent:(UIEvent *)event {
    if (m_index != -1) {
        if (m_section != -1) {
            if (m_kbpointer != nil) {
                [m_kbpointer AddItemFromSearchList:m_index withsection:m_section withdirectClipObject:nil];
            }
        }
    }
    [super touchesEnded:touchesEnded withEvent:event];
}

- (void)SetKBPointer:(KeyboardView *)kBPointer {
    m_kbpointer = kBPointer;
}

- (id)init {
    self = [super init];
    if (self != nil) {
        m_index = -1;
        m_kbpointer = nil;
        m_section = -1;
    }
    return self;
}
@end
