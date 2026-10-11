// RadioVC -- decompiled from Radiofx_iPad.  SetMp3Metadata: (stream ICY
// metadata parsing through RegEx) is dropped with the streamer.
#import "RadioVC.h"
#import "RadioAppDelegate.h"

@implementation RadioVC
@synthesize m_titlefordisplay, m_interpretfordisplay;

- (void)dealloc { [super dealloc]; }
- (void)viewDidUnload {}
- (void)didReceiveMemoryWarning { [super didReceiveMemoryWarning]; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; }
- (void)viewWillDisappear:(BOOL)animated {}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o {
    return [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] shouldAutorotateTo:o];
}

- (void)SetpChannelInfos:(NSMutableArray *)infos {
    m_pchannelinfos = infos;
}

- (id)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
    self = [super initWithNibName:nibName bundle:bundle];
    if (self != nil) {
        [self setTitle:@"Radio"];
        [self setM_interpretfordisplay:nil];
        [self setM_titlefordisplay:nil];
        m_pchannelinfos = nil;
    }
    return self;
}
@end
