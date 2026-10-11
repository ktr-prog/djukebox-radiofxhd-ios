// iPadMainVC : UIViewController  -- decompiled from Radiofx_iPad (armv7)
// Dropped: UpdateDownloaded:/DoTheUpdate:/DeleteUnzipFolder (self-update via
// ZipArchive from the dead server).  See DEVIATIONS.md.
#import "iPadMainVC.h"
#import "KioskView.h"
#import "GLView.h"
#import "RadioAppDelegate.h"
#import "Globals.h"

@implementation iPadMainVC

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)CheckRemoveChannelView {
    [m_kioskview RemoveDirectChannelKey];
}

- (void)StartKioskShutdowntimer:(int)kioskShutdowntimer {
    if (m_kioskview == nil) return;
    [m_kioskview StartKioskShutdowntimer:kioskShutdowntimer];
}

- (void)SetKioskViewEnd {
    if (m_kioskview == nil) return;
    [m_kioskview EndFunction];
}

- (void)ForwardRemoveDirectChannelKey {
    [m_kioskview RemoveDirectChannelKey];
}

- (void)viewDidUnload {
    [super viewDidUnload];
}

- (void)didReceiveMemoryWarning {
    if (m_kioskview != nil) {
        [[m_kioskview m_glv] SetMemoryWarning];
        [m_kioskview TryReleaseMMCMixer];
        [[m_kioskview m_glv] RemoveTexturesExeptRondell];
    }
    [super didReceiveMemoryWarning];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o {
    return o == 3;
}

// Hide the status bar and the home indicator (UIStatusBarHidden in Info.plist is ignored by modern iOS when the
// view controller decides; the home indicator did not exist in 2013).  See DEVIATIONS.md.
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeBottom; }

// iOS 6+ replacement for shouldAutorotateToInterfaceOrientation: (see DEVIATIONS.md)
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscapeRight;
}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)from {
    [[NSNotificationCenter defaultCenter] postNotification:
        [NSNotification notificationWithName:@"MsgiPadDidrotate" object:nil]];
    if (m_kioskview == nil) return;
    CGSize sz = [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] GetiPadSize];
    [[m_kioskview m_glv] SetDrawVars:sz];
    [[m_kioskview m_glv] ReInit:1];
    [[m_kioskview m_glv] setM_rotateready:1];
    [[m_kioskview m_glv] ReInitThread];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)o duration:(NSTimeInterval)duration {
    CGSize sz = [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] GetiPadSize];
    if (m_kioskview == nil) return;
    [m_kioskview setFrame:CGRectMake(0.0f, 0.0f, sz.width, sz.height)];
    [m_kioskview FitSubViews:sz];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)o duration:(NSTimeInterval)duration {
    if (m_kioskview == nil) return;
    [[m_kioskview m_glv] setM_drawemptyturn:1];
    [[m_kioskview m_glv] drawView];
    [[m_kioskview m_glv] setM_rotateready:0];
    int n = 0;
    GLView *glv;
    for (;;) {
        BOOL again;
        if (![[m_kioskview m_glv] m_threadwaiting]) {
            again = (n < 0x14);
            n++;
        } else {
            again = NO;
        }
        glv = [m_kioskview m_glv];
        if (!again) break;
        [glv setM_drawemptyturn:1];
        [NSThread sleepForTimeInterval:0.01];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, 0);
    }
    [glv EmptyAllTextures];
    [[m_kioskview m_glv] destroyFramebuffer];
}

- (void)ShowKioskMode {
    RadioAppDelegate *d = (RadioAppDelegate *)[[UIApplication sharedApplication] delegate];
    if ([d m_kioskpresent]) return;
    CGSize sz = [d GetiPadSize];
    [d setM_kioskpresent:YES];
    gv_kioskflag = 0;
    m_kioskview = [[KioskView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, sz.width, sz.height)];
    NSArray *subs = [[self view] subviews];
    if ([subs count] == 0)
        [[self view] addSubview:m_kioskview];
    else
        [[self view] insertSubview:m_kioskview belowSubview:[subs objectAtIndex:0]];
    [m_kioskview release];
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (id)GetKioskView {
    return m_kioskview;
}

- (id)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
    self = [super initWithNibName:nibName bundle:bundle];
    if (self != nil) {
        [[self view] setBackgroundColor:[UIColor blackColor]];
        m_kioskview = nil;
        // original also observed "MsgUpdateDownloaded" (self-update) -- dropped
    }
    return self;
}

@end
