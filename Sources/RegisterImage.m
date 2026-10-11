// Recovered from -[RegisterImage ...] @0x3f3xx..0x3fa0x
#import "RegisterImage.h"
#import "GLView.h"
#import "RadioAppDelegate.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@implementation RegisterImage
@synthesize m_enabled, m_index;

- (void)InitView {
    m_index = -1;
    m_pglv = nil;
    m_enabled = NO;
    m_additionalimage = nil;
    m_mainimage = nil;
    m_darkimage = nil;
    [self setBackgroundColor:[UIColor colorWithWhite:0.55f alpha:1.0f]];
}

- (void)dealloc { [super dealloc]; }

- (void)SetGLVPointer:(id)gLVPointer { m_pglv = gLVPointer; }

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [m_pglv RestartIdleTimer];
    [m_pglv RestartAdvertTimer];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event { }

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event { [self touchesEndedFunc]; }

- (void)touchesEndedFunc {
    if ([DEL m_isstattalm] && [m_pglv IsShowingAskBox]) return;
    if (m_index != 4) {
        if (!m_enabled) return;
        if ([m_pglv m_executingflags]) return;
        [m_pglv performSelector:@selector(ToggleKBAndRegister:) withObject:[NSNumber numberWithInt:m_index] afterDelay:0.01];
    } else {
        [m_pglv ForcePinching];
    }
}

// Renders the button picture: the icon centred (38x34 of 56x48 points, scaled by 2/3 on the phone layout)
// and a grey frame around it; [isadditional] selects the darker frame used for the "pressed" overlay.
- (void)SetImage:(id)image withisadditionalimage:(BOOL)isadditional withcreate:(BOOL)create {
    UIImage *pic = [DEL NonCachedImage:image];
    float scale = [DEL m_isipad] ? 1.0f : 0.6666667f;
    float W = (float)(int)(scale * 56.0f);
    float H = (float)(int)(scale * 48.0f);
    CGContextRef ctx = [DEL BeginImageContext:CGSizeMake(W, H)];
    CGContextSetFillColorWithColor(ctx, [[UIColor colorWithWhite:0.0f alpha:0.0f] CGColor]);
    CGContextFillRect(ctx, CGRectMake(0, 0, W, H));

    float A = (float)(int)((double)scale * 38.0);      // picture width
    float B = (float)(int)((double)scale * 8.0);       // top margin
    float C = (float)(int)((double)scale * 34.0);      // picture height
    float X = (float)(int)((W - A) * 0.5f);            // left margin
    CGContextDrawImage(ctx, CGRectMake(X, B, A, C), [pic CGImage]);

    CGContextSetFillColorWithColor(ctx, [[UIColor colorWithWhite:(isadditional ? 0.18f : 0.251f) alpha:1.0f] CGColor]);
    CGContextFillRect(ctx, CGRectMake(0, 0, X, H));                       // left
    CGContextFillRect(ctx, CGRectMake(X + A, 0, W - X - A, H));           // right
    CGContextFillRect(ctx, CGRectMake(0, 0, W, B));                       // top
    CGContextFillRect(ctx, CGRectMake(0, B + C, W, H - B - C));           // bottom

    UIImageView **slot = isadditional ? &m_darkimage : &m_mainimage;
    UIImage *result = [DEL EndImageContext:ctx];
    if (create) {
        *slot = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, [self frame].size.width, [self frame].size.height)];
        [*slot setAlpha:1.0f];
        [*slot setImage:result];
        [self addSubview:*slot];
        [*slot release];
        [*slot setUserInteractionEnabled:NO];
    } else {
        [*slot setImage:result];
    }
}

- (void)SetAdditionalWhiteImage {
    m_additionalimage = [[UIView alloc] initWithFrame:[m_mainimage frame]];
    [m_additionalimage setBackgroundColor:[UIColor whiteColor]];
    [m_additionalimage setAlpha:0.0f];
    [self insertSubview:m_additionalimage belowSubview:m_mainimage];
    [m_additionalimage release];
}

- (void)ShowDarkImage:(float)darkImage {
    if (m_darkimage == nil) return;
    [m_darkimage setAlpha:darkImage];
}

- (void)SetSyncImage:(id)syncImage { }      // empty in the binary

- (void)SetAdditionalAlpha:(float)additionalAlpha {
    if (m_additionalimage == nil) return;
    [m_additionalimage setAlpha:additionalAlpha];
}
@end
