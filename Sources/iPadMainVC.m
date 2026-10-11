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

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return o == 3; }

// Hide the status bar and the home indicator (UIStatusBarHidden in Info.plist is ignored by modern iOS when the
// view controller decides; the home indicator did not exist in 2013).  See DEVIATIONS.md.
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeBottom; }

// Landscape only (as in the original); rotation support was removed again.
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscapeRight;
}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}

// The window can have any size (iPad mini, iPad Pro, Split-less full screen): refit when it differs from the kiosk view.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (m_kioskview == nil) return;
    CGSize sz = [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] GetiPadSize];
    CGRect cur = [m_kioskview frame];
    if (fabsf(cur.size.width - sz.width) < 0.5f && fabsf(cur.size.height - sz.height) < 0.5f) return;
    [m_kioskview setFrame:CGRectMake(0.0f, 0.0f, sz.width, sz.height)];
    [m_kioskview FitSubViews:sz];
    [[m_kioskview m_glv] SetDrawVars:sz];
    [[m_kioskview m_glv] ReInit:1];
}

// The legacy willRotate/didRotate callbacks are not delivered on current iOS; the same work is done around the size transition.
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    if (m_kioskview == nil) return;
    RadioAppDelegate *d = (RadioAppDelegate *)[[UIApplication sharedApplication] delegate];
    [d SetTransitionSize:size];
    GLView *glv = [m_kioskview m_glv];
    // before: black out the flow, wait for the texture thread, drop the framebuffer of the old size
    [glv setM_drawemptyturn:1];
    [glv drawView];
    [glv setM_rotateready:0];
    for (int n = 0; n < 0x14 && ![glv m_threadwaiting]; n++) {
        [glv setM_drawemptyturn:1];
        [NSThread sleepForTimeInterval:0.01];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, 0);
    }
    [glv EmptyAllTextures];
    [glv destroyFramebuffer];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        [m_kioskview setFrame:CGRectMake(0.0f, 0.0f, size.width, size.height)];
        [m_kioskview FitSubViews:size];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        [d SetTransitionSize:CGSizeZero];
        CGSize sz = [d GetiPadSize];
        [m_kioskview setFrame:CGRectMake(0.0f, 0.0f, sz.width, sz.height)];
        [m_kioskview FitSubViews:sz];
        [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"MsgiPadDidrotate" object:nil]];
        [glv SetDrawVars:sz];
        [glv SetUpTippRects];
        [glv ReInit:1];
        [glv setM_rotateready:1];
        [glv ReInitThread];
    }];
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
