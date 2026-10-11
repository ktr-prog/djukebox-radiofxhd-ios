// KioskView : UIView -- decompiled from Radiofx_iPad (armv7), ported to arm64 / modern iOS.
// Manual reference counting (CLANG_ENABLE_OBJC_ARC=NO).  Feature groups that depend on the dead backend or on
// removed third-party code (Spotify, remote control, EPG, printing, third-party animation, jingles, ambience,
// facebook, copy thread, ...) are not part of this file; see DEVIATIONS.md.
#import "KioskView.h"
#import "TestLibrary.h"
#import "MusicImporter.h"
#import "GLView.h"
#import "KeyboardView.h"
#import "MultichannelMixerController.h"
#import "RadioAppDelegate.h"
#import "ServerComm.h"
#import "ServerEntry.h"
#import "DBOperations.h"
#import "FolderObject.h"
#import "ClipObject.h"
#import "CGPointObject.h"
#import "Globals.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <unistd.h>

// Fast switching / queue dragging can touch the queue while it is changing; an out-of-range index must not
// take the whole app down.  These behave like the NSMutableArray methods but ignore a bad index.
@interface NSObject (RfxGrave)
+ (void)rfx_graveRelease:(id)o;
@end
@implementation NSObject (RfxGrave)
+ (void)rfx_graveRelease:(id)o { [self performSelector:@selector(rfx_graveRelease2:) withObject:o afterDelay:10.0]; }
+ (void)rfx_graveRelease2:(id)o { [o release]; }
@end

@interface NSMutableArray (RfxSafeQueue)
- (id)rfx_objectAtIndex:(NSUInteger)i;
- (void)rfx_removeObjectAtIndex:(NSUInteger)i;
- (void)rfx_insertObject:(id)o atIndex:(NSUInteger)i;
@end
@implementation NSMutableArray (RfxSafeQueue)
- (id)rfx_objectAtIndex:(NSUInteger)i { return (i < [self count]) ? [self objectAtIndex:i] : nil; }
- (void)rfx_removeObjectAtIndex:(NSUInteger)i {
    if (i >= [self count]) return;
    // Several ivars (m_cliptorotate, pending performSelectors, animations) point at clips without retaining them.
    // Keep a removed clip alive for a while so none of them can touch freed memory.
    id o = [[self objectAtIndex:i] retain];
    [self removeObjectAtIndex:i];
    [NSObject performSelectorOnMainThread:@selector(rfx_graveRelease:) withObject:o waitUntilDone:NO];
}
- (void)rfx_insertObject:(id)o atIndex:(NSUInteger)i { if (o == nil) return; if (i > [self count]) i = [self count]; [self insertObject:o atIndex:i]; }
@end


#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])
#define ISIPAD ([DEL m_isipad])
#define THUMB (ISIPAD ? 0x52 : 0x38)
#define BARH (ISIPAD ? 0x7e : 0x5a)

@implementation KioskView
@synthesize m_lastsongdragged, m_tenmintimer, m_lastshownNoCoverFor, m_didstopmanual, m_resetfadeover;
@synthesize m_clipStartTime, m_pausebegintime, m_errorplayingsong, g_scaling, mMCMixer, m_draggingobj;
@synthesize m_stopsecondthread, m_willplayradio, m_trailerimagetime, m_copynotifyflag, m_limitduration;
@synthesize m_limitinittime, m_ordering, m_lastvolume, m_freespace, m_30secsearchInitTime, m_crossfadeInitTime;
@synthesize m_crossfadeDuration, m_presongDuration, m_presongInitTime, m_shrinkdevider, m_rotateclip;
@synthesize m_updateunzipped, m_autoselected, m_first_start, cancelcopy, m_fadingover, m_sve, m_clips;
@synthesize m_cantransform, m_glv, m_ignoreXdiff;

#pragma mark - lifecycle

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        mMCMixer = [[MultichannelMixerController alloc] init];
        m_lastsongdragged = 0;
        m_activateView = nil;
        m_dragginposforremotecmds = -1;
        m_didstopmanual = NO;
        m_draggingorigpos = -1;
        m_errorplayingsong = NO;
        m_wdrplayer = nil;
        m_angle = 0;
        cancelcopy = NO;
        startTime = -1.0;
        m_threadrunning[0] = m_threadrunning[1] = NO;
        m_cliptorotate = nil;
        m_foldertimer = nil;
        m_firstcheck = YES;
        m_fadingover = NO;
        m_blackview = nil;
        m_first_start = YES;
        m_autoselected = YES;
        m_updateunzipped = NO;
        m_rotateclip = NO;
        m_shrinkdevider = NO;
        m_presongInitTime = -1.0;
        m_presongDuration = -1.0;
        m_crossfadeDuration = -1.0;
        m_crossfadeInitTime = -1.0;
        m_shutdowntimer = nil;
        m_shutdown = NO;
        m_freespace = YES;
        m_lastvolume = 0;
        m_ordering = NO;
        m_draggingrunningsong = NO;
        m_helpPicture = nil;
        m_fiveoclockflag = NO;
        m_limitinittime = -1.0;
        m_copynotifyflag = NO;
        [self setMultipleTouchEnabled:NO];
        m_trailerimagetime = 0;
        m_blackoverlay = nil;
        m_songcounter = 0;
        m_jingleindex = 0;
        m_crossfadetime = 5.0f;
        m_playingjingle = NO;
        m_stopsecondthread = NO;
        m_enableddebuggingtext = NO;
        m_resetangle = NO;
        m_pausebegintime = -1.0;
        m_resetfadeover = -1.0;
        m_lastshownNoCoverFor = nil;
        m_waitview = nil;
        m_blackborderview = nil;
        m_showfirstsongInfos = NO;
        m_loadingscreen = nil;
        m_loadinglabel = nil;
        m_lastCDXDiff = 0;
        m_ignoreXdiff = NO;
        m_tenmintimer = CACurrentMediaTime();
        m_colorarray = [[NSArray arrayWithObjects:
            [NSNumber numberWithInt:0x4ebbc3], [NSNumber numberWithInt:0x174244], [NSNumber numberWithInt:0x7accd2],
            [NSNumber numberWithInt:0x008cd1], [NSNumber numberWithInt:0x023047], [NSNumber numberWithInt:0x40a9dd],
            [NSNumber numberWithInt:0x2e3b8c], [NSNumber numberWithInt:0x151b3e], [NSNumber numberWithInt:0x626ca9],
            [NSNumber numberWithInt:0x674592], [NSNumber numberWithInt:0x291c3a], [NSNumber numberWithInt:0x8d74ad],
            [NSNumber numberWithInt:0xb04287], [NSNumber numberWithInt:0x321326], [NSNumber numberWithInt:0xbf659d],
            [NSNumber numberWithInt:0xb90f1d], [NSNumber numberWithInt:0x39080c], [NSNumber numberWithInt:0xcb4b56],
            [NSNumber numberWithInt:0xd9800b], [NSNumber numberWithInt:0x362105], [NSNumber numberWithInt:0xe3a048],
            [NSNumber numberWithInt:0xcfcc00], [NSNumber numberWithInt:0x3d3c01], [NSNumber numberWithInt:0xdfdd57],
            [NSNumber numberWithInt:0x7db61c], [NSNumber numberWithInt:0x2d400d], [NSNumber numberWithInt:0xa9cf69],
            [NSNumber numberWithInt:0x037637], [NSNumber numberWithInt:0x013418], [NSNumber numberWithInt:0x59a57b], nil] retain];

        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        // original: floatForKey:@"keykioskvolume", NaN -> 0.3f.  A missing key (fresh install) would give
        // silence; 0.3f (the original's own fallback value) is used instead -- see DEVIATIONS.md.
        float vol = ([defs objectForKey:@"keykioskvolume"] == nil) ? 0.3f : [defs floatForKey:@"keykioskvolume"];
        if (vol != vol) vol = 0.3f;
        [self setM_lastvolume:vol];
        if ([self m_lastvolume] < 0) [self setM_lastvolume:0.0f];
        if ([self m_lastvolume] > 1.0f) [self setM_lastvolume:1.0f];

        border = (((ISIPAD ? -86 : -60) + (ISIPAD ? 0x7e : 0x5a)) >> 1);
        [self setBackgroundColor:[UIColor colorWithWhite:0.0f alpha:1.0f]];
        m_clips = [[NSMutableArray alloc] init];

        ServerComm *sc = [DEL GetServerComm];
        m_sve = [sc GetChoosenRfxServer:nil];
        if (m_sve == nil) {
            ServerEntry *def = [[ServerEntry alloc] init];
            [def setServername:@"cloud01.rfx.tobit.com"];
            // original also stored a hard-coded password for the dead server here -- not needed, omitted
            [def setStateFlags:[DEL ModifyStateFlags:[def StateFlags]]];
            [def setStateFlags:([def StateFlags] | 0x400)];
            [def setStateFlags:([def StateFlags] | 0x8000000)];
            [def setChoosen:1];
            [sc AddMTServer:def];
            [sc SaveServerList];
            [def release];
            m_sve = [sc GetChoosenRfxServer:nil];
            if ([DEL GetDeliveredStatus] == 0)
                [DEL SetDeliveredStatus];
        }
        // DEVIATION: match the server entry to the local library (see ServerComm / DEVIATIONS.md)
        if ([sc AdaptToLocalLibrary]) {
            [m_sve release];
            m_sve = [sc GetChoosenRfxServer:nil];
        }
        // DEVIATION: demo songs for a device without music (only when the library is empty)
        [MusicImporter ImportForServer:m_sve];      // Documents/Import -> library
        [TestLibrary RemoveDemoForServer:m_sve];
        m_trailerimagetime = [m_sve trailerimagetime];

        CGSize pad = [DEL GetiPadSize];
        m_divider = [[UIView alloc] initWithFrame:[self GetDividerFrame:pad]];
        [m_divider setBackgroundColor:[UIColor colorWithWhite:0.15f alpha:1.0f]];
        [self addSubview:m_divider];
        [m_divider release];

        m_label = [[UILabel alloc] initWithFrame:[self GetDebugLabelFrame:pad]];
        [m_label setTextColor:[UIColor colorWithWhite:0.2f alpha:1.0f]];
        [m_label setBackgroundColor:[UIColor clearColor]];
        [m_label setTextAlignment:NSTextAlignmentRight];
        [m_label setFont:[UIFont systemFontOfSize:(ISIPAD ? 17.0f : 15.0f)]];
        [self addSubview:m_label];
        [m_label release];
        [self SetDebugText:@" "];

        // port addition: small always-on sample-rate readout (file rate / engine rate / device rate)
        m_ratelabel = [[UILabel alloc] initWithFrame:CGRectMake(12.0f, 6.0f, 520.0f, 18.0f)];
        [m_ratelabel setTextColor:[UIColor colorWithWhite:0.85f alpha:1.0f]];
        [m_ratelabel setBackgroundColor:[UIColor clearColor]];
        [m_ratelabel setFont:[UIFont fontWithName:@"Courier" size:12.0f]];
        [m_ratelabel setText:@"sample rate: -"];
        [m_ratelabel setUserInteractionEnabled:NO];
        [m_ratelabel setHidden:![[NSUserDefaults standardUserDefaults] boolForKey:@"RfxDevRateLabel"]];
        [self addSubview:m_ratelabel];
        [m_ratelabel release];
        {
            // hidden dev menu: five quick taps in the top left corner
            UITapGestureRecognizer *dev = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ShowDevMenu)];
            [dev setNumberOfTapsRequired:5];
            [dev setCancelsTouchesInView:NO];
            [dev setDelaysTouchesBegan:NO];
            [dev setDelaysTouchesEnded:NO];
            [dev setDelegate:(id)self];
            [self addGestureRecognizer:dev];
            [dev release];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(RateInfo:) name:@"RfxSampleRateInfo" object:nil];

        m_blackborderview = [[UIView alloc] initWithFrame:[self GetBlackBorderViewRect]];
        [m_blackborderview setBackgroundColor:[UIColor blackColor]];
        [self addSubview:m_blackborderview];
        [m_blackborderview setUserInteractionEnabled:NO];
        [m_blackborderview release];

        m_glv = [[GLView alloc] initWithFrame:[self GetOpenGLFrame:pad]];
        [self addSubview:m_glv];
        [m_glv release];
        [m_glv SetParent:self];
        [m_glv StartPreScrollerThread];
        [m_glv setM_lastflags:-1];
        NSInteger lastdirect = [defs integerForKey:@"k_lastdirctchannelid"];
        m_willplayradio = (lastdirect > 0);

        UIImage *tslogo = [UIImage imageNamed:@"ts-text.png"];
        m_tslogo = nil;
        {
            CGSize ls = [tslogo size];
            CGFloat sc2 = ISIPAD ? 1.0f : 1.5f;
            m_tslogo = [[UIImageView alloc] initWithFrame:CGRectMake(
                ([self frame].size.width - ls.width / sc2) * 0.5f,
                (([self frame].size.height + [m_divider frame].size.height) - BARH) +
                    ((BARH - [m_divider frame].size.height) - ls.height / sc2) * 0.5f,
                ls.width / sc2, ls.height / sc2)];
            [m_tslogo setImage:tslogo];
            [m_tslogo setAlpha:0.0f];
            [self addSubview:m_tslogo];
            [m_tslogo release];
        }
        [m_glv AddKBView];
        [m_glv ExecuteServerFlags:[NSNumber numberWithInt:0]];
        m_willplayradio = NO;
        [self CreateFonts];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ErrorPlayingSong)
            name:@"MCM_MSG_ERROR_PLAYING_FILE" object:nil];
        [self CheckLoadingscreen];
        [self FolderTimerfunc:nil];
        m_first_start = NO;
        [NSThread detachNewThreadSelector:@selector(TimerThread) toTarget:self withObject:nil];
        {
            CADisplayLink *rl = [CADisplayLink displayLinkWithTarget:self selector:@selector(RotationFrame)];
            [rl setPreferredFramesPerSecond:20];
            [rl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
        if (m_sve != nil)
            [self performSelector:@selector(StartThread) withObject:nil afterDelay:0];

        m_blackoverlay = [[UIView alloc] initWithFrame:[self GetBlackOverLayViewRect]];
        [m_blackoverlay setBackgroundColor:[UIColor blackColor]];
        [m_blackoverlay setAlpha:0.0f];
        [self addSubview:m_blackoverlay];
        [m_blackoverlay release];
        if (lastdirect >= 1)
            [self FadeQueueToBlack:YES];

        m_pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(scaleVolume:)];
        [self addGestureRecognizer:m_pinchGesture];
        [m_pinchGesture release];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self EndFunction];
    [self CheckPendingSong];
    [self setM_lastshownNoCoverFor:nil];
    if (mMCMixer != nil) { [mMCMixer release]; mMCMixer = nil; }
    if (m_sve != nil) { [m_sve release]; m_sve = nil; }
    if (m_colorarray != nil) { [m_colorarray release]; m_colorarray = nil; }
    if (m_titlefont != nil) { [m_titlefont release]; m_titlefont = nil; }
    [DEL setM_kioskpresent:NO];
    [super dealloc];
}

- (void)CreateFonts {
    m_titlefont = [[UIFont fontWithName:@"TrebuchetMS-Bold" size:20.0f] retain];
    if (m_titlefont == nil)
        m_titlefont = [[UIFont boldSystemFontOfSize:20.0f] retain];
}

#pragma mark - simple accessors

- (GLView *)m_glv { return m_glv; }
- (GLView *)GetGLView { return m_glv; }
- (id)GetBlackView { return m_blackview; }
- (BOOL)ShowingLoadingscreen { return m_loadingscreen != nil; }
- (BOOL)IsThreadRunning { return m_threadrunning[0] || m_threadrunning[1]; }
- (float)GetBlackOverlayAlpha { return [m_blackoverlay alpha]; }
- (void)StopOverviewTimer {}
- (void)AirplayRestart {}
- (void)SendChangesToRemoteApps {}
- (void)SetRadioAniVar:(int)radioAniVar {}
- (void)SyncSVEwithUserdef {}
- (void)RefreshSettings { [[m_glv GetKBView] RefreshSettings]; }

- (void)StartThread {
    // original: MarkFilesOnce / StartCopyThread: (replication from the server); nothing to do offline
    [self SetDebugText:@""];
}

- (void)RateInfo:(NSNotification *)n {
    NSString *t = [[n userInfo] objectForKey:@"text"];
    [m_ratelabel setText:t];
    if (![m_ratelabel isHidden]) [self bringSubviewToFront:m_ratelabel];
    UILabel *dl = (UILabel *)[[self viewWithTag:7741] viewWithTag:7746];
    if (dl != nil) [dl setText:t];
    [m_lastrateinfo release];
    m_lastrateinfo = [t copy];
}

#pragma mark - hidden dev menu (5 taps in the top left corner)

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    if (![g isKindOfClass:[UITapGestureRecognizer class]] || [(UITapGestureRecognizer *)g numberOfTapsRequired] != 5) return YES;
    CGPoint p = [touch locationInView:self];
    return p.x < 110.0f && p.y < 110.0f && [self viewWithTag:7741] == nil;
}

- (void)ShowDevMenu {
    if ([self viewWithTag:7741] != nil) return;
    CGRect b = [self bounds];
    UIView *ov = [[UIView alloc] initWithFrame:b];
    [ov setTag:7741];
    [ov setBackgroundColor:[UIColor colorWithWhite:0.0f alpha:0.94f]];
    [ov setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    float cx = b.size.width * 0.5f, y = 70.0f, rowW = 560.0f;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y, rowW, 34.0f)];
    [title setText:@"Dev-Menü"]; [title setTextColor:[UIColor whiteColor]]; [title setBackgroundColor:[UIColor clearColor]];
    [title setFont:[UIFont systemFontOfSize:26.0f]]; [title setTextAlignment:NSTextAlignmentCenter];
    [ov addSubview:title]; [title release];
    y += 70.0f;
    NSArray *rows = [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"Schwarzer Rahmen um die Cover", @"RfxDevCoverBorder", [NSNumber numberWithInt:1], nil],
        [NSArray arrayWithObjects:@"Sample-Rate-Anzeige auf dem Bildschirm", @"RfxDevRateLabel", [NSNumber numberWithInt:2], nil],
        [NSArray arrayWithObjects:@"Lautstärke-Button deaktivieren", @"RfxDevNoVolume", [NSNumber numberWithInt:3], nil],
        [NSArray arrayWithObjects:@"Alle versteckten Buttons aktivieren", @"RfxDevAllButtons", [NSNumber numberWithInt:4], nil], nil];
    for (NSArray *r in rows) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y, rowW - 80.0f, 31.0f)];
        [l setText:[r objectAtIndex:0]]; [l setTextColor:[UIColor whiteColor]]; [l setBackgroundColor:[UIColor clearColor]];
        [l setFont:[UIFont systemFontOfSize:19.0f]];
        [ov addSubview:l]; [l release];
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(cx + rowW * 0.5f - 51.0f, y, 51.0f, 31.0f)];
        id pref = [[NSUserDefaults standardUserDefaults] objectForKey:[r objectAtIndex:1]];
        BOOL on = (pref == nil) ? ([[r objectAtIndex:2] intValue] == 1) : [pref boolValue];
        [sw setOn:on];
        [sw setTag:7750 + [[r objectAtIndex:2] intValue]];
        [sw addTarget:self action:@selector(DevSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        [ov addSubview:sw]; [sw release];
        y += 52.0f;
    }
    {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y, 230.0f, 31.0f)];
        [l setText:@"Rahmenbreite"]; [l setTextColor:[UIColor whiteColor]]; [l setBackgroundColor:[UIColor clearColor]];
        [l setFont:[UIFont systemFontOfSize:19.0f]];
        [ov addSubview:l]; [l release];
        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f + 240.0f, y, rowW - 240.0f, 31.0f)];
        [sl setMinimumValue:0.0f]; [sl setMaximumValue:8.0f];
        id wp = [[NSUserDefaults standardUserDefaults] objectForKey:@"RfxDevCoverBorderWidth"];
        [sl setValue:(wp == nil ? 2.0f : [wp floatValue])];
        [sl setTag:7760];
        [sl addTarget:self action:@selector(DevSliderDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [ov addSubview:sl]; [sl release];
        y += 52.0f;
    }
    UILabel *info = [[UILabel alloc] initWithFrame:CGRectMake(cx - rowW * 0.5f, y + 10.0f, rowW, 40.0f)];
    [info setTag:7746];
    [info setText:(m_lastrateinfo != nil ? m_lastrateinfo : @"Sample-Rate: -")];
    [info setTextColor:[UIColor colorWithWhite:0.8f alpha:1.0f]]; [info setBackgroundColor:[UIColor clearColor]];
    [info setFont:[UIFont fontWithName:@"Courier" size:14.0f]]; [info setNumberOfLines:2];
    [ov addSubview:info]; [info release];
    UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
    [x setFrame:CGRectMake(b.size.width - 70.0f, 20.0f, 50.0f, 50.0f)];
    [x setTitle:@"\u2715" forState:UIControlStateNormal];
    [x setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [[x titleLabel] setFont:[UIFont systemFontOfSize:26.0f]];
    [x setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin];
    [x addTarget:self action:@selector(CloseDevMenu) forControlEvents:UIControlEventTouchUpInside];
    [ov addSubview:x];
    [self addSubview:ov];
    [ov release];
}

- (void)DevSwitchChanged:(UISwitch *)sw {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    switch ([sw tag]) {
    case 7751:
        [d setBool:[sw isOn] forKey:@"RfxDevCoverBorder"]; [d synchronize];
        [m_glv RefreshCoverTextures];
        break;
    case 7752:
        [d setBool:[sw isOn] forKey:@"RfxDevRateLabel"]; [d synchronize];
        [m_ratelabel setHidden:![sw isOn]];
        if ([sw isOn]) [self bringSubviewToFront:m_ratelabel];
        break;
    case 7753:
        [d setBool:[sw isOn] forKey:@"RfxDevNoVolume"]; [d synchronize];
        [m_glv ExecuteServerFlags:[NSNumber numberWithInt:1]];
        break;
    case 7754:
        [d setBool:[sw isOn] forKey:@"RfxDevAllButtons"]; [d synchronize];
        [m_glv ExecuteServerFlags:[NSNumber numberWithInt:1]];
        break;
    }
    [self bringSubviewToFront:[self viewWithTag:7741]];
}

- (void)DevSliderDone:(UISlider *)sl {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setFloat:[sl value] forKey:@"RfxDevCoverBorderWidth"]; [d synchronize];
    [m_glv RefreshCoverTextures];
}

- (void)CloseDevMenu {
    [[self viewWithTag:7741] removeFromSuperview];
}

- (void)SetDebugText:(NSString *)debugText {
    if (([[self m_sve] StateFlags] & 0x400) == 0) return;
    [m_label setText:debugText];
}

- (void)CheckDebugTextEnabled {
    if ([@"Debuggingtexts enabled" isEqualToString:[m_label text]])
        [self SetDebugText:@""];
}

- (void)ExternDraw:(int)externDraw {
    [self performSelectorOnMainThread:@selector(ExternDrawInMT:) withObject:[NSNumber numberWithInt:externDraw] waitUntilDone:YES];
}

- (void)ExternDrawInMT:(NSNumber *)externDrawInMT {
    [m_glv setM_radioanivar:[externDrawInMT intValue]];
    [m_glv drawView];
}

#pragma mark - layout

- (CGRect)GetOpenGLFrame:(CGSize)openGLFrame {
    return CGRectMake(0, 0, openGLFrame.width, openGLFrame.height - (ISIPAD ? 126.0f : 90.0f));
}

- (CGRect)GetDividerFrame:(CGSize)dividerFrame {
    return CGRectMake(0, dividerFrame.height - (ISIPAD ? 126.0f : 90.0f), dividerFrame.width, 4.0f);
}

- (CGRect)GetDebugLabelFrame:(CGSize)debugLabelFrame {
    if (ISIPAD)
        return CGRectMake(debugLabelFrame.width - 340.0f, debugLabelFrame.height - 40.0f, 320.0f, 20.0f);
    return CGRectMake(debugLabelFrame.width - 290.0f, debugLabelFrame.height - 20.0f, 280.0f, 18.0f);
}

- (CGRect)GetBlackBorderViewRect {
    CGSize pad = [DEL GetiPadSize];
    return CGRectMake(0, (pad.height - BARH) + 4.0f, (float)(border - 1), (float)(BARH - 4));
}

- (CGRect)GetBlackOverLayViewRect {
    CGSize pad = [DEL GetiPadSize];
    float h = ISIPAD ? 126.0f : 90.0f;
    return CGRectMake(0, pad.height - h, pad.width, h);
}

- (CGRect)GetFrameForDragPic:(int)frameForDragPic {
    CGSize pad = [DEL GetiPadSize];
    int dx = [self m_ignoreXdiff] ? 0 : m_lastCDXDiff;
    return CGRectMake((float)((border - dx) + ((border + THUMB) * frameForDragPic)),
                      (pad.height - (float)border) - (float)THUMB,
                      (float)THUMB, (float)THUMB);
}

- (CGRect)GetFrameForDragPicText:(int)frameForDragPicText {
    CGSize pad = [DEL GetiPadSize];
    int dx = [self m_ignoreXdiff] ? 0 : m_lastCDXDiff;
    return CGRectMake((float)(((-350 - dx) + border) + ((border + THUMB) * frameForDragPicText)),
                      (((pad.height - (float)border) - (float)THUMB) - (float)(THUMB >> 1)) - 5.0f,
                      (float)(THUMB + 0x2bc), (float)(THUMB >> 1));
}

- (CGRect)MakeSmallFrame:(CGRect)r {
    return CGRectMake(r.origin.x + ((r.size.width - 10.0f) * 0.5f), r.origin.y + ((r.size.height - 10.0f) * 0.5f), 10.0f, 10.0f);
}

- (void)FitSubViews:(CGSize)fitSubViews {
    [m_glv setFrame:[self GetOpenGLFrame:fitSubViews]];
    [m_divider setFrame:[self GetDividerFrame:fitSubViews]];
    [m_label setFrame:[self GetDebugLabelFrame:fitSubViews]];
    [m_blackoverlay setFrame:[self GetBlackOverLayViewRect]];
    [m_blackborderview setFrame:[self GetBlackBorderViewRect]];
    [self OrderClipPics:[NSNumber numberWithInt:1]];
    [m_glv SetUpTippRects];
    [m_glv FitSubViews:fitSubViews];
}

- (void)FadeQueueToBlack:(BOOL)fadeQueueToBlack {
    if (fadeQueueToBlack) {
        [m_blackoverlay retain];
        if ([m_blackoverlay superview] != nil)
            [m_blackoverlay removeFromSuperview];
        [self insertSubview:m_blackoverlay belowSubview:m_glv];
        [m_blackoverlay release];
    }
    [self SendCDsToBackGround];
    [self bringSubviewToFront:m_label];
    [self bringSubviewToFront:m_ratelabel];
    [UIView beginAnimations:@"kioskblackoverlayani" context:nil];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.4];
    [m_blackoverlay setAlpha:fadeQueueToBlack ? 1.0f : 0.0f];
    [UIView commitAnimations];
}

#pragma mark - loading screen

- (void)CheckLoadingscreen {
    DBOperations *dbop = [[DBOperations alloc] init];
    [DEL LockDB:YES];
    int count = [dbop GetCompleteSongCount];
    [DEL UnlockDB];
    [dbop release];
    // DEVIATION: the original showed this "fill your library at my.djukebox.com" screen below 10 songs (the
    // cloud would fill it up).  Offline there is no cloud, so it only appears for a completely empty library.
    if (count < 1) {
        if (m_loadingscreen != nil) return;
        UIImage *img = [UIImage imageNamed:@"loadingscreen.png"];
        CGRect fr = [self frame];
        BOOL small = fr.size.width < 1024.0f;
        float imgscale = small ? 0.45f : 1.0f;
        float yoff = small ? 10.0f : 40.0f;
        CGSize isz = [img size];
        m_loadingscreen = [[UIImageView alloc] initWithFrame:CGRectMake(
            (fr.size.width - isz.width * imgscale) * 0.5f,
            ((fr.size.height - isz.height * imgscale) * 0.5f) + yoff,
            isz.width * imgscale, isz.height * imgscale)];
        [m_loadingscreen setImage:img];
        KeyboardView *kb = [m_glv GetKBView];
        [self insertSubview:m_loadingscreen belowSubview:kb];
        [m_loadingscreen release];
        m_loadinglabel = [[UILabel alloc] initWithFrame:CGRectZero];
        float lw = (float)(int)(small ? fr.size.width * 0.97 : fr.size.width * 0.75);
        float lh = small ? 55.0f : 90.0f;
        float loff = small ? 5.0f : 35.0f;
        [m_loadinglabel setFrame:CGRectMake(([self frame].size.width - lw) * 0.5f,
                                            ([m_loadingscreen frame].origin.y - lh) - loff, lw, lh)];
        [m_loadinglabel setFont:[UIFont systemFontOfSize:small ? 13.0f : 19.0f]];
        [m_loadinglabel setTextAlignment:NSTextAlignmentCenter];
        [m_loadinglabel setBackgroundColor:[UIColor clearColor]];
        [m_loadinglabel setTextColor:[UIColor colorWithWhite:0.753f alpha:1.0f]];
        [m_loadinglabel setNumberOfLines:small ? 3 : 4];
        [m_loadinglabel setText:[NSString stringWithFormat:@"Fast geschafft: Wählen Sie nun noch unter my.djukebox.com eine\nMusikquelle aus und die djukebox® füllt sich nach und nach mit Musik.%@\nBitte nicht ausschalten.", small ? @"" : @"\n"]];
        [self insertSubview:m_loadinglabel belowSubview:kb];
        [m_loadinglabel release];
        m_rotateclip = NO;
        m_cliptorotate = nil;
        [self setM_rotateclip:NO];
        [self setM_shrinkdevider:NO];
        [self setM_presongInitTime:-1.0];
        [self setM_crossfadeInitTime:-1.0];
        m_cliptorotate = nil;
        [self StopPlayers];
        [m_glv EmptyRondell];
        for (ClipObject *c in [self m_clips]) {
            if ([c m_imgv] != nil) { [[c m_imgv] removeFromSuperview]; [c setM_imgv:nil]; }
            if ([c m_imgvtext] != nil) { [[c m_imgvtext] removeFromSuperview]; [c setM_imgvtext:nil]; }
            if ([c m_swapimgv] != nil) { [[c m_swapimgv] removeFromSuperview]; [c setM_swapimgv:nil]; }
        }
        [[self m_clips] removeAllObjects];
    } else {
        if (m_loadingscreen == nil) return;
        [m_loadingscreen removeFromSuperview];
        m_loadingscreen = nil;
        [m_loadinglabel removeFromSuperview];
        m_loadinglabel = nil;
        [m_glv ReShowFolder];
        [self StartFirstFolderSong:[NSNumber numberWithInt:1]];
    }
}

#pragma mark - folders

static BOOL IsSpecialFolderId(long long fid) { return fid == -66 || fid == -44 || fid == -33; }

- (void)FolderTimerfunc:(id)timer {
    if (m_foldertimer != nil) {
        [m_foldertimer invalidate];
        [m_foldertimer release];
        m_foldertimer = nil;
    }
    ServerEntry *choosen = [[DEL GetServerComm] GetChoosenRfxServer:nil];
    [DEL LockDB:NO];
    DBOperations *dbop = [[DBOperations alloc] init];
    NSMutableArray *allFolders = [dbop GetFolders:choosen onlyexclude:NO checkempty:YES withLimits:NO withremotefolders:YES join:YES];
    [DEL RemoveVirtFolder:allFolders alsoIPOD:NO alsospotify:NO];
    NSMutableArray *limited = [dbop GetFolders:m_sve onlyexclude:NO checkempty:YES withLimits:YES withremotefolders:YES join:YES];
    [DEL RemoveVirtFolder:limited alsoIPOD:YES alsospotify:NO];
    [dbop release];
    [DEL UnlockDB];
    [choosen release];

    if (allFolders == nil || [allFolders count] == 0) {
        // original: [self CheckLastDirectChannel] (direct streaming channel, dropped)
        [allFolders release];
        [limited release];
        return;
    }

    // scheduled folders (flag 2) and their distance to "now"
    NSMutableArray *sched = [[NSMutableArray alloc] init];
    long tz = (long)[[NSTimeZone defaultTimeZone] secondsFromGMTForDate:[NSDate date]];
    long now = (long)time(0);
    for (NSUInteger i = 0; i < [allFolders count]; i++) {
        FolderObject *f = [allFolders objectAtIndex:i];
        if (([f flags] & 2) != 0) {
            [sched addObject:f];
            [f setTimediff:(int)([f autoselect] - ((now + tz) % 86400))];
        }
    }
    long long target = -1;      // folder to show (r4:r6 in the binary)
    int bestPast = -90000;
    for (NSUInteger i = 0; i < [sched count]; i++) {
        FolderObject *f = [sched objectAtIndex:i];
        if ([f timediff] <= -1 && [f timediff] > bestPast) {
            bestPast = [f timediff];
            target = [f folderid];
        }
        if ([f timediff] <= -1)
            [f setTimediff:(0x15180 + [f timediff])];
    }
    [sched sortUsingSelector:@selector(compareTimediffs:)];

    BOOL decided = NO;
    if ([sched count] != 0 && [[sched objectAtIndex:0] timediff] <= 5) {
        target = [[sched objectAtIndex:0] folderid];
        decided = YES;
    }
    if (!decided) {
        if (!m_firstcheck) {
            target = -1;
        } else {
            m_firstcheck = NO;
            if (target == -1) {
                // first start without a schedule: the folder played last, else the first folder
                [DEL LockDB:NO];
                DBOperations *d2 = [[DBOperations alloc] init];
                NSString *spot = nil;
                int last = [d2 GetLastPlayedFolder:[m_sve serverid] withspotifyfolderid:&spot];
                [d2 release];
                [DEL UnlockDB];
                long long lastId = last;
                BOOL found = NO;
                if (!IsSpecialFolderId(lastId)) {
                    for (NSUInteger i = 0; i < [limited count]; i++) {
                        if ([[limited objectAtIndex:i] folderid] == lastId) {
                            if (lastId != -1) { found = YES; }
                            break;
                        }
                    }
                }
                if (found) target = lastId;
                // DEVIATION: the original leaves nothing selected when the last played folder is one of the
                // dropped virtual folders (-33 / -44 / -66); here the first folder is used instead.
                else if ([limited count] != 0) target = [[limited objectAtIndex:0] folderid];
                else if ([allFolders count] != 0) target = [[allFolders objectAtIndex:0] folderid];
            }
        }
    }
    if (IsSpecialFolderId(target)) target = -1;

    // look the folder object up: scheduled folders first, then all folders
    FolderObject *folder = nil;
    if (target != -1) {
        for (NSUInteger i = 0; i < [sched count]; i++)
            if ([[sched objectAtIndex:i] folderid] == target) { folder = [sched objectAtIndex:i]; break; }
        if (folder == nil)
            for (NSUInteger i = 0; i < [allFolders count]; i++)
                if ([[allFolders objectAtIndex:i] folderid] == target) { folder = [allFolders objectAtIndex:i]; break; }
    }

    NSUInteger nextIdx = 0;
    if (folder != nil) {
        BOOL inLimited = NO;
        for (NSUInteger i = 0; i < [limited count]; i++)
            if ([[limited objectAtIndex:i] folderid] == target) { inLimited = YES; break; }
        if (inLimited)
            [m_glv ShowOnlyFolder:folder withstartSong:(m_shutdown ? NO : YES) channelviewwaspresent:NO];
        for (NSUInteger i = 0; i < [sched count]; i++)
            if ([sched objectAtIndex:i] == folder) { nextIdx = i + 1; break; }
    }
    if ([sched count] > nextIdx) {
        int diff = [[sched objectAtIndex:nextIdx] timediff] - 3;
        double interval = (diff < 10) ? 10.0 : (double)diff;
        m_foldertimer = [[NSTimer scheduledTimerWithTimeInterval:interval target:self
                            selector:@selector(FolderTimerfunc:) userInfo:nil repeats:NO] retain];
    }
    [sched release];
    [allFolders release];
    [limited release];
}

- (void)StartDirectFolder:(FolderObject *)directFolder {
    [m_glv ReleaseLastPlayingInfos];
    if (![m_glv m_pinching]) {
        [m_glv ShowOnlyFolder:directFolder withstartSong:YES channelviewwaspresent:NO];
    } else {
        [DEL LockDB:NO];
        DBOperations *dbop = [[DBOperations alloc] init];
        NSMutableArray *folders = [dbop GetFolders:m_sve onlyexclude:NO checkempty:YES withLimits:YES withremotefolders:YES join:YES];
        [dbop release];
        [DEL UnlockDB];
        int idx = 0;
        for (NSUInteger i = 0; i < [folders count]; i++) {
            if ([[folders objectAtIndex:i] folderid] == [directFolder folderid]) { idx = (int)i; break; }
        }
        [folders release];
        [m_glv PrepareCloseScroller];
        [m_glv setM_pinchstatus:3];
        [m_glv setM_newselectedfolderindex:idx];
        [m_glv performSelector:@selector(PinchAniBack) withObject:nil afterDelay:0];
    }
}

- (long long)GetSelectedFolderid { return [m_glv m_selectedfolderid]; }
- (int)GetSelectedServerid { return [m_glv m_selectedserverid]; }

- (void)StartveryfirstSong {
    if ([[self m_clips] count] == 0) return;
    ClipObject *c = [[[self m_clips] rfx_objectAtIndex:0] retain];
    [c setM_imgv:[[UIImageView alloc] initWithFrame:CGRectZero]];
    UIImage *pic = [m_glv CreateCDPicture:c roundpic:YES];
    [[c m_imgv] setImage:pic];
    [self AddCDPictureToView:c];
    [self OrderClipPics:[NSNumber numberWithInt:1]];
    [[c m_imgv] release];
    [self StartFirstFolderSong:[NSNumber numberWithInt:0]];
    [c release];
}

- (void)StartFirstFolderSong:(NSNumber *)firstFolderSong {
    if (m_loadingscreen != nil) return;
    int tries = [firstFolderSong intValue];
    if (tries > 5) return;
    if ([m_glv m_selectedfolderid] == -33) {
        if (gv_kioskflag == 0)
            [self performSelector:@selector(StartFirstFolderSong:) withObject:[NSNumber numberWithInt:tries + 1] afterDelay:0.3];
        return;
    }
    if ([[self m_clips] count] != 0) {
        if (mMCMixer == nil || ![mMCMixer isPlaying]) {
            ClipObject *first = [[[self m_clips] rfx_objectAtIndex:0] retain];
            [self StopPlayers];
            [self StartAudioPlayer:first withAniNext:NO witharg1:1];
            [first release];
        }
        [self SendCDsToBackGround];
        return;
    }
    [self setM_rotateclip:NO];
    [self setM_shrinkdevider:NO];
    [self setM_presongInitTime:-1.0];
    [self setM_crossfadeInitTime:-1.0];
    m_cliptorotate = nil;
    [self StopPlayers];
    [m_glv GetArrayLock:NO];
    ClipObject *pick = nil;
    if ([[m_glv m_tilearray] count] != 0) {
        NSMutableArray *tiles = [[NSMutableArray alloc] init];
        [tiles addObjectsFromArray:[m_glv m_tilearray]];
        for (NSInteger i = (NSInteger)[tiles count] - 1; i >= 0; i--) {
            if ([[tiles objectAtIndex:i] ID] == -5) [tiles removeObjectAtIndex:i];
        }
        if ([tiles count] != 0) {
            // continue with the song that was playing when the app was closed (first start only)
            static BOOL resumed = NO;
            ClipObject *t = nil;
            if (!resumed) {
                resumed = YES;
                long long last = [[[NSUserDefaults standardUserDefaults] objectForKey:@"RfxLastClipID"] longLongValue];
                if (last > 0) {
                    for (ClipObject *c in tiles) {
                        if ([c ID] == last) { t = c; break; }
                        for (ClipObject *tr in ([c m_tracks] ? [c m_tracks] : [NSArray array])) if ([tr ID] == last) { t = c; break; }
                        if (t != nil) break;
                    }
                }
            }
            if (t == nil) t = [tiles objectAtIndex:(random() % [tiles count])];
            ClipObject *src = ([t m_tracks] != nil && [[t m_tracks] count] != 0) ? [[t m_tracks] objectAtIndex:0] : t;
            pick = [[ClipObject alloc] init];
            [self CopyPropertiesFromObject:src toObject:pick];
        }
        [tiles release];
    }
    [m_glv releaseArraylock];
    if (pick == nil || [pick m_folderid] == -33) {
        [pick release];
        if (gv_kioskflag == 0)
            [self performSelector:@selector(StartFirstFolderSong:) withObject:[NSNumber numberWithInt:tries + 1] afterDelay:0.3];
        return;
    }
    m_angle = 0;
    [[self m_clips] rfx_insertObject:pick atIndex:0];
    [pick release];
    [pick setM_imgv:[[UIImageView alloc] initWithFrame:CGRectZero]];
    UIImage *pic = [m_glv CreateCDPicture:pick roundpic:YES];
    [[pick m_imgv] setImage:pic];
    [self AddCDPictureToView:pick];
    [[pick m_imgv] release];
    [self CheckQueueHintLabel];
    [self OrderClipPics:[NSNumber numberWithInt:1]];
    [self StartAudioPlayer:pick withAniNext:NO witharg1:1];
    [self SendCDsToBackGround];
    [m_glv SelectClipImmediately:pick];
}

- (BOOL)IsInArray:(FolderObject *)inArray witharray:(NSArray *)array {
    for (NSUInteger i = 0; i < [array count]; i++)
        if ([[array objectAtIndex:i] folderid] == [inArray folderid]) return YES;
    return NO;
}

- (BOOL)FolderInArray:(FolderObject *)folderInArray withArray:(NSArray *)array {
    for (NSUInteger i = 0; i < [array count]; i++)
        if ([[array objectAtIndex:i] folderid] == [folderInArray folderid]) return YES;
    return NO;
}

- (void)CheckNoFolders { }

- (void)RemoveDirectChannelKey {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"k_lastdirctchannelid"];
    [d synchronize];
}

#pragma mark - limitations

- (void)CheckNextTime:(int *)nextTime withchecktime:(int)checktime withsecofday:(int)secofday {
    if (checktime > secofday) {
        if (*nextTime > checktime) *nextTime = checktime;
    }
}

- (void)CheckLimitationsLater {
    [self performSelector:@selector(CheckLimitations) withObject:nil afterDelay:0];
}

- (void)CheckLimitations {
    [self setM_limitinittime:-1.0];
    int dayIndex = 0;
    long secLong = 0;
    [DEL GetLimitationVars:&dayIndex withsecofday:&secLong];
    int secofday = (int)secLong;
    int nextTime = secofday + 0x2a300;      // two days ahead
    [DEL LockDB:NO];
    DBOperations *dbop = [[DBOperations alloc] init];
    NSMutableArray *folders = [dbop GetFolders:m_sve onlyexclude:NO checkempty:YES withLimits:NO withremotefolders:YES join:YES];
    [dbop release];
    [DEL UnlockDB];
    int start = 0, end = 0;
    for (NSInteger i = (NSInteger)[folders count] - 1; i >= 0; i--) {
        FolderObject *f = [folders objectAtIndex:i];
        BOOL remove = YES;
        // yesterday's window that runs past midnight
        [DEL GetFolderLimitationForDayIndex:((dayIndex - 1) < 1 ? 6 : (dayIndex - 2)) withstarttime:&start withendtime:&end withFolderobject:f];
        end -= 86400;
        if (end >= 1 && secofday <= end) {
            [self CheckNextTime:&nextTime withchecktime:end withsecofday:secofday];
            remove = NO;
        }
        // today
        [DEL GetFolderLimitationForDayIndex:(dayIndex - 1) withstarttime:&start withendtime:&end withFolderobject:f];
        if (secofday >= start && secofday <= end) remove = NO;
        [self CheckNextTime:&nextTime withchecktime:start withsecofday:secofday];
        [self CheckNextTime:&nextTime withchecktime:end withsecofday:secofday];
        // tomorrow
        [DEL GetFolderLimitationForDayIndex:((dayIndex + 1) > 7 ? 0 : dayIndex) withstarttime:&start withendtime:&end withFolderobject:f];
        [self CheckNextTime:&nextTime withchecktime:start withsecofday:secofday];
        [self CheckNextTime:&nextTime withchecktime:end withsecofday:secofday];
        if (remove) [folders removeObjectAtIndex:i];
    }
    if (nextTime - secofday <= 0x13) nextTime = secofday + 0x14;

    for (NSUInteger i = 0; i < [folders count]; i++) {
        FolderObject *f = [folders objectAtIndex:i];
        if ([f folderid] == [m_glv m_selectedfolderid] && [f serverid] == [m_glv m_selectedserverid] &&
            [f ipodid] == [m_glv m_selectedipodid]) {
            // the shown folder is still allowed: check again when the next limit starts or ends
            [folders release];
            [self setM_limitduration:(double)((nextTime + 2) - secofday)];
            [self setM_limitinittime:CACurrentMediaTime()];
            [self CheckNoFolders];
            return;
        }
    }
    [folders release];
    // the shown folder is not allowed any more: switch to the first allowed one
    [DEL LockDB:NO];
    dbop = [[DBOperations alloc] init];
    NSMutableArray *allowed = [dbop GetFolders:m_sve onlyexclude:NO checkempty:YES withLimits:YES withremotefolders:NO join:YES];
    [dbop release];
    [DEL UnlockDB];
    [DEL RemoveVirtFolder:allowed alsoIPOD:NO alsospotify:NO];
    if ([allowed count] != 0) {
        FolderObject *first = [allowed objectAtIndex:0];
        if (first != nil && [first folderid] != [m_glv m_selectedfolderid] && ![m_glv IsShowingChannelView])
            [m_glv ShowOnlyFolder:first withstartSong:([[self m_clips] count] == 0) channelviewwaspresent:NO];
    }
    [allowed release];
    [self setM_limitduration:(double)((nextTime + 2) - secofday)];
    [self setM_limitinittime:CACurrentMediaTime()];
    [self CheckNoFolders];
}

- (BOOL)SongFitsInRondell:(ClipObject *)song {
    long long sel = [m_glv m_selectedfolderid];
    if (sel == -1) return YES;
    if (sel == -1) return NO;
    if ([song m_folderid] != sel) return NO;
    if ([m_glv m_selectedserverid] == -1) return NO;
    if ([m_glv m_selectedserverid] != [song m_serverid]) return NO;
    return [m_glv m_selectedipodid] == [song m_ipodid];
}

- (void)CheckQueueInMainThread:(NSNumber *)queueInMainThread {
    int serverid = [queueInMainThread intValue];
    for (NSInteger i = (NSInteger)[[self m_clips] count] - 1; i >= 0; i--) {
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:i];
        if ([c m_serverid] != serverid) continue;
        if (c == m_cliptorotate) {
            m_cliptorotate = nil;
            [self setM_presongInitTime:-1.0];
            [self setM_crossfadeInitTime:-1.0];
            [self setM_limitinittime:-1.0];
            [self setM_shrinkdevider:NO];
            [self SetDeviderPlayingPercent:0.0f];
            [self StopPlayers];
        }
        if ([c m_imgv] != nil) { [[c m_imgv] removeFromSuperview]; [c setM_imgv:nil]; }
        if ([c m_imgvtext] != nil) { [[c m_imgvtext] removeFromSuperview]; [c setM_imgvtext:nil]; }
        if ([c m_swapimgv] != nil) { [[c m_swapimgv] removeFromSuperview]; [c setM_swapimgv:nil]; }
        [[self m_clips] rfx_removeObjectAtIndex:i];
        [self CheckQueueHintLabel];
    }
}

#pragma mark - queue (the row of cover thumbnails above the divider)

static int s_aniCounterDelete = 0;      // data_00368248 + 4
static int s_aniCounterNotAccepted = 0; // data_00368248 + 8

static void RemoveClipViews(ClipObject *c) {
    if ([c m_imgv] != nil) [[c m_imgv] removeFromSuperview];
    if ([c m_imgvtext] != nil) [[c m_imgvtext] removeFromSuperview];
    if ([c m_swapimgv] != nil) [[c m_swapimgv] removeFromSuperview];
}

- (void)AddClip:(ClipObject *)clip atIndex:(int)indexArg fromDragging:(BOOL)dragging withsendqueue:(BOOL)sendqueue
  withaddanyway:(BOOL)addanyway sendremotedelayed:(BOOL)sendremotedelayed {
    if (m_loadingscreen != nil) return;
    int count = (int)[[self m_clips] count];
    int flags = [m_sve StateFlags];
    int insertAt = (indexArg < 0) ? count : indexArg;
    BOOL skipDupCheck = ((flags & 0x20) == 0) ? addanyway : ((flags & 0xff) != 0);
    if (!skipDupCheck && ([clip ID] != 0 || [clip m_ipodid] != 0)) {
        // the same song may only be in the queue once
        for (NSUInteger i = 0; i < [[self m_clips] count]; i++) {
            ClipObject *other = [[self m_clips] rfx_objectAtIndex:i];
            if ([other ID] == [clip ID] && [clip m_serverid] == [other m_serverid] && [other m_ipodid] == [clip m_ipodid]) {
                [other retain];
                [m_glv setM_preventdragging:CACurrentMediaTime()];
                [self StartNotAcceptedAni:clip withqueuecd:other];
                [other release];
                return;
            }
        }
    }
    [self setM_lastsongdragged:CACurrentMediaTime()];

    int pos;
    BOOL replaceFirst = NO;
    if ((flags & 4) != 0) {
        pos = count;
    } else if (insertAt > 0) {
        pos = (insertAt < count) ? insertAt : count;
    } else if ([[self m_clips] count] == 0) {
        pos = 0;
    } else if (m_fadingover || (flags & 0x10) != 0) {
        pos = 1;
    } else {
        replaceFirst = YES;
        pos = 0;
    }

    if (!replaceFirst) {
        [[self m_clips] rfx_insertObject:clip atIndex:pos];
        [self AddCDPictureToView:clip];
        [self CheckQueueHintLabel];
        if ([m_glv IsShowingChannelView]) {
            [self sendSubviewToBack:[clip m_imgv]];
            if ([clip m_imgvtext] != nil) [self sendSubviewToBack:[clip m_imgvtext]];
            if ([clip m_swapimgv] != nil) [self sendSubviewToBack:[clip m_swapimgv]];
            [self OrderClipPics:[NSNumber numberWithInt:1]];
            [[clip m_imgv] setAlpha:1.0f];
            if ([clip m_imgvtext] != nil) [[clip m_imgvtext] setAlpha:0.0f];
            if ([clip m_swapimgv] != nil) [[clip m_swapimgv] setAlpha:0.0f];
        } else {
            m_ordering = YES;
            [UIView beginAnimations:@"OrderClipsAni" context:NULL];
            [UIView setAnimationDuration:0.6];
            [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
            [UIView setAnimationDelegate:self];
            [[clip m_imgv] setAlpha:1.0f];
            if ([clip m_imgvtext] != nil) [[clip m_imgvtext] setAlpha:0.0f];
            if ([clip m_swapimgv] != nil) [[clip m_swapimgv] setAlpha:0.0f];
            [self OrderClipPics:[NSNumber numberWithInt:1]];
            [UIView commitAnimations];
            [self performSelector:@selector(sendSubviewToBack:) withObject:[clip m_imgv] afterDelay:0.65];
            if ([clip m_imgvtext] != nil)
                [self performSelector:@selector(sendSubviewToBack:) withObject:[clip m_imgvtext] afterDelay:0.66];
            if ([clip m_swapimgv] != nil)
                [self performSelector:@selector(sendSubviewToBack:) withObject:[clip m_swapimgv] afterDelay:0.67];
        }
        [clip release];
        return;
    }

    // default mode: the new song replaces the one that is playing right now (cross fade)
    ClipObject *oldFirst = [[[self m_clips] rfx_objectAtIndex:0] retain];
    [[self m_clips] rfx_removeObjectAtIndex:0];
    [[self m_clips] rfx_insertObject:clip atIndex:0];
    [self AddCDPictureToView:clip];
    [self CheckQueueHintLabel];
    m_fadingover = YES;
    [self performSelector:@selector(FadeOverProcess:) withObject:nil afterDelay:0.8];
    [self StartOrderAni:oldFirst];
    [clip release];
}

- (void)AddCDPictureToView:(ClipObject *)cdClip {
    UIView *above = nil;
    if (m_blackview != nil) above = m_blackview;
    else if (m_activateView != nil) above = m_activateView;
    else if (m_waitview != nil) above = m_waitview;
    else if (m_blackoverlay != nil && (double)[m_blackoverlay alpha] > 0.1) above = m_blackoverlay;
    else if (m_helpPicture != nil) above = m_helpPicture;

    if (above != nil) {
        [self insertSubview:[cdClip m_imgv] belowSubview:above];
        if ([cdClip m_imgvtext] != nil) [self insertSubview:[cdClip m_imgvtext] belowSubview:above];
        if ([cdClip m_swapimgv] != nil) [self insertSubview:[cdClip m_swapimgv] belowSubview:above];
    } else {
        [self addSubview:[cdClip m_imgv]];
        if ([cdClip m_imgvtext] != nil) [self addSubview:[cdClip m_imgvtext]];
        if ([cdClip m_swapimgv] != nil) [self addSubview:[cdClip m_swapimgv]];
        [self bringSubviewToFront:[m_glv GetKBView]];
    }
    if ([m_glv isShowingDimmViewOrNoConnView]) {
        if (![DEL m_isstattalm]) {
            [self sendSubviewToBack:[cdClip m_imgv]];
            if ([cdClip m_imgvtext] != nil) [self sendSubviewToBack:[cdClip m_imgvtext]];
            if ([cdClip m_swapimgv] != nil) [self sendSubviewToBack:[cdClip m_swapimgv]];
        }
    }
}

- (void)AddPictureToKiosk:(id)pictureToKiosk {
    if (m_loadingscreen != nil) return;
    [m_glv performSelectorOnMainThread:@selector(AddPicture:) withObject:pictureToKiosk waitUntilDone:YES];
    [m_glv SetLastmidindex:-2];
    [m_glv performSelectorOnMainThread:@selector(drawView) withObject:nil waitUntilDone:YES];
}

- (void)OrderClipPics:(NSNumber *)orderClipPics {
    int mode = [orderClipPics intValue];
    m_cantransform = NO;
    for (NSUInteger i = 0; i < [[self m_clips] count]; i++) {
        ClipObject *c = [[[self m_clips] rfx_objectAtIndex:i] retain];
        CGRect fr = [self GetFrameForDragPic:(int)i];
        // a spinning CD keeps its rotation (resetting it inside the animation block made the spin snap back and stutter)
        BOOL spin = NO;   // rotation is a layer animation now; the model transform stays identity
        if (spin) {
            [[c m_imgv] setBounds:CGRectMake(0, 0, fr.size.width, fr.size.height)];
            [[c m_imgv] setCenter:CGPointMake(CGRectGetMidX(fr), CGRectGetMidY(fr))];
        } else {
            [[c m_imgv] setTransform:CGAffineTransformMakeRotation(0)];
            [[c m_imgv] setFrame:fr];
        }
        [[c m_imgv] setAlpha:1.0f];
        if ([c m_swapimgv] != nil) {
            if (spin) { [[c m_swapimgv] setBounds:CGRectMake(0, 0, fr.size.width, fr.size.height)]; [[c m_swapimgv] setCenter:CGPointMake(CGRectGetMidX(fr), CGRectGetMidY(fr))]; }
            else [[c m_swapimgv] setFrame:fr];
            [[c m_swapimgv] setAlpha:0.0f];
        }
        if ([c m_imgvtext] != nil) {
            [[c m_imgvtext] setFrame:CGRectMake(fr.origin.x - 350.0f, (fr.origin.y - fr.size.height) - 23.0f,
                                                (float)(THUMB + 0x2bc), (float)((double)THUMB * 3.0 * 0.25))];
            [[c m_imgvtext] setAlpha:0.0f];
        }
        [c release];
    }
    if (mode == 1) m_cantransform = YES;
}

- (void)MoveCDs {
    for (NSUInteger i = 0; i < [[self m_clips] count]; i++) {
        ClipObject *c = [[[self m_clips] rfx_objectAtIndex:i] retain];
        CGRect f = [self GetFrameForDragPic:(int)i];
        [[c m_imgv] setCenter:CGPointMake((float)(int)((double)f.origin.x + (double)f.size.width * 0.5),
                                          (float)(int)((double)f.origin.y + (double)f.size.height * 0.5))];
        [c release];
    }
}

- (void)StartOrderAni:(ClipObject *)orderAni {
    m_ordering = YES;
    if (orderAni != nil) [self setM_ignoreXdiff:YES];
    [UIView beginAnimations:@"OrderClipsAni" context:NULL];
    [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDuration:0.6];
    [self OrderClipPics:[NSNumber numberWithInt:0]];
    if (orderAni == nil) {
        m_cantransform = YES;
        [UIView commitAnimations];
        return;
    }
    BOOL pad = ISIPAD;
    [[orderAni m_imgv] setTransform:CGAffineTransformMakeRotation(0)];
    CGRect f = [[orderAni m_imgv] frame];
    [[orderAni m_imgv] setFrame:CGRectMake(f.origin.x - (pad ? 112.0f : 86.0f), f.origin.y, f.size.width, f.size.height)];
    if ([[self m_clips] count] != 0)
        [[[[self m_clips] rfx_objectAtIndex:0] m_imgv] setAlpha:1.0f];
    m_cantransform = YES;
    [UIView commitAnimations];
    [self performSelector:@selector(FinalDelete:) withObject:orderAni afterDelay:1.5];
}

- (void)OrderClipsReady { m_ordering = NO; }

- (void)CorrectZindexComplete:(ClipObject *)c {
    [self CorrectZindex:[c m_imgv]];
    if ([c m_imgvtext] != nil) [self CorrectZindex:[c m_imgvtext]];
    if ([c m_swapimgv] != nil) [self CorrectZindex:[c m_swapimgv]];
}

- (void)CorrectZindex:(UIView *)view {
    if (view == nil) return;
    [view retain];
    [view removeFromSuperview];
    [self insertSubview:view belowSubview:[m_glv GetRegister0]];
    [view release];
}

- (int)GetInsertIndex:(CGPoint)insertIndex {
    int thumb = THUMB;
    int xdiff = [self m_ignoreXdiff] ? 0 : m_lastCDXDiff;
    if (insertIndex.x < 10.0f) return 0;
    int xd = (int)(insertIndex.x - 2.0f) + (thumb >> 1);
    int v = (xd < 0) ? xdiff : (xdiff + xd);
    return (int)((float)v / (float)(border + thumb));
}

- (void)CheckInsertPosition:(int *)insertPosition {
    if (([m_sve StateFlags] & 4) == 0) return;
    if (m_oldindex > 0) {
        if ((unsigned)m_oldindex <= [[self m_clips] count]) *insertPosition = m_oldindex;
    } else {
        *insertPosition = 1;
    }
}

- (void)FinalDelete:(ClipObject *)finalDelete {
    if (m_cliptorotate == finalDelete) {
        m_rotateclip = NO;
        m_cliptorotate = nil;
        [NSThread sleepForTimeInterval:0.1];
    }
    if (m_resetangle) {
        m_resetangle = NO;
        m_angle = 0;
        [NSThread sleepForTimeInterval:0.1];
    }
    [[finalDelete m_imgv] removeFromSuperview];
    if ([finalDelete m_imgvtext] != nil) [[finalDelete m_imgvtext] removeFromSuperview];
    if ([finalDelete m_swapimgv] != nil) [[finalDelete m_swapimgv] removeFromSuperview];
    // the views died with removeFromSuperview (assign properties): do not leave dangling pointers behind
    [finalDelete setM_imgv:nil];
    [finalDelete setM_imgvtext:nil];
    [finalDelete setM_swapimgv:nil];
    [finalDelete release];
}

- (void)DeleteCDAni:(ClipObject *)cDAni {
    if (m_draggingrunningsong) {
        if (!m_playingjingle) {
            ClipObject *copy = [[ClipObject alloc] init];
            [self CopyPropertiesFromObject:cDAni toObject:copy];
            [self performSelector:@selector(FadeOverProcess:) withObject:copy afterDelay:0.01];
        }
        m_draggingrunningsong = NO;
    }
    s_aniCounterDelete++;
    CGRect f = [[cDAni m_imgv] frame];
    [UIView beginAnimations:[NSString stringWithFormat:@"deletecd%i", s_aniCounterDelete] context:NULL];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.8];
    float off = ISIPAD ? 41.0f : 28.0f;
    CGRect shrunk = CGRectMake(f.origin.x + off, f.origin.y + off, 0.0f, 0.0f);
    [[cDAni m_imgv] setFrame:shrunk];
    [[cDAni m_imgv] setAlpha:0.0f];
    [[cDAni m_imgvtext] setFrame:shrunk];
    [[cDAni m_imgvtext] setAlpha:0.0f];
    [[cDAni m_swapimgv] setFrame:shrunk];
    [[cDAni m_swapimgv] setAlpha:0.0f];
    [UIView commitAnimations];
    [self performSelector:@selector(FinalDelete:) withObject:cDAni afterDelay:1.5];
}

- (void)StartNotAcceptedAni:(ClipObject *)notAcceptedAni withqueuecd:(ClipObject *)queuecd {
    [self addSubview:[notAcceptedAni m_imgv]];
    if ([[notAcceptedAni m_swapimgv] superview] == nil && [notAcceptedAni m_swapimgv] != nil)
        [self addSubview:[notAcceptedAni m_swapimgv]];
    if ([[notAcceptedAni m_imgvtext] superview] == nil && [notAcceptedAni m_imgvtext] != nil)
        [self addSubview:[notAcceptedAni m_imgvtext]];
    BOOL pad = ISIPAD;
    int idx = 0;
    if (queuecd != nil) {
        for (NSUInteger i = 0; i < [[self m_clips] count]; i++)
            if (queuecd == [[self m_clips] rfx_objectAtIndex:i]) { idx = (int)i; break; }
    }
    s_aniCounterNotAccepted++;
    [UIView beginAnimations:[NSString stringWithFormat:@"notacceptedani%i", s_aniCounterNotAccepted] context:NULL];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.5];
    [[notAcceptedAni m_imgv] setAlpha:1.0f];
    if (queuecd == nil) {
        CGRect f = [[notAcceptedAni m_imgv] frame];
        [[notAcceptedAni m_imgv] setFrame:CGRectMake(f.origin.x + (float)(THUMB >> 1), (f.origin.y + (float)(THUMB >> 1)) - 150.0f, 0.0f, 0.0f)];
    } else {
        [[notAcceptedAni m_imgv] setFrame:[self GetFrameForDragPic:idx]];
        if ([[self m_clips] count] != 0 && queuecd == [[self m_clips] rfx_objectAtIndex:0])
            m_resetangle = YES;
    }
    if ([notAcceptedAni m_swapimgv] != nil) {
        [[notAcceptedAni m_swapimgv] setAlpha:0.0f];
        [[notAcceptedAni m_swapimgv] setFrame:[[notAcceptedAni m_imgv] frame]];
    }
    if ([notAcceptedAni m_imgvtext] != nil) {
        [[notAcceptedAni m_imgvtext] setAlpha:0.0f];
        CGRect f = [[notAcceptedAni m_imgv] frame];
        [[notAcceptedAni m_imgvtext] setFrame:CGRectMake(f.origin.x - 350.0f, (f.origin.y - f.size.height) - 23.0f,
                                                         (float)(THUMB + 0x2bc), (float)((double)THUMB * 3.0 * 0.25))];
    }
    (void)pad;
    [UIView commitAnimations];
    [self performSelector:@selector(FinalDelete:) withObject:notAcceptedAni afterDelay:0.8];
}

- (void)SimpleDeleteWithOrder:(NSNumber *)simpleDeleteWithOrder {
    int idx = [simpleDeleteWithOrder intValue];
    if (idx < 0 || (unsigned)idx >= [[self m_clips] count]) return;
    if (idx != 0) {
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:idx];
        RemoveClipViews(c);
        [[self m_clips] rfx_removeObjectAtIndex:idx];
        [self StartOrderAni:nil];
        [self CheckQueueHintLabel];
    } else if (![self m_fadingover]) {
        [self setM_crossfadeInitTime:-1.0];
        [self setM_presongInitTime:-1.0];
        [self performSelector:@selector(CheckNextSong:)
                   withObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:0], @"how",
                                                [NSNumber numberWithFloat:5.0f], @"time", nil]
                   afterDelay:0.01];
    }
}

- (void)RemoveAndOrderImage:(ClipObject *)c {
    RemoveClipViews(c);
    [[self m_clips] removeObject:c];
    [self OrderClipPics:[NSNumber numberWithInt:1]];
    [self CheckQueueHintLabel];
}

- (void)RemoveDragginObjInMT {
    m_draggingorigpos = -1;
    if ([m_draggingobj m_imgv] != nil && [[m_draggingobj m_imgv] superview] != nil)
        [[m_draggingobj m_imgv] removeFromSuperview];
    if ([m_draggingobj m_imgvtext] != nil && [[m_draggingobj m_imgvtext] superview] != nil)
        [[m_draggingobj m_imgvtext] removeFromSuperview];
    if ([m_draggingobj m_swapimgv] != nil && [[m_draggingobj m_swapimgv] superview] != nil)
        [[m_draggingobj m_swapimgv] removeFromSuperview];
    if (m_draggingobj != nil) {
        [m_draggingobj release];
        m_draggingobj = nil;
    }
    m_draggingrunningsong = NO;
}

- (void)DelPicInMainThread:(ClipObject *)c {
    if ([c m_imgv] != nil && [[c m_imgv] superview] != nil) [[c m_imgv] removeFromSuperview];
    if ([c m_imgvtext] != nil && [[c m_imgvtext] superview] != nil) [[c m_imgvtext] removeFromSuperview];
    if ([c m_swapimgv] != nil && [[c m_swapimgv] superview] != nil) [[c m_swapimgv] removeFromSuperview];
}

- (void)RemoveImageInMainThread:(UIView *)v { [v removeFromSuperview]; }

- (void)OrderGLVAndBlackView { }   // empty in the binary (@0x77be0)

- (void)SendCDsToBackGround {
    if (m_waitview != nil) [self sendSubviewToBack:m_waitview];
    for (NSUInteger i = 0; i < [[self m_clips] count]; i++)
        { UIView *v = [[[self m_clips] rfx_objectAtIndex:i] m_imgv]; if (v != nil) [self sendSubviewToBack:v]; }
}

- (void)EmptyQueue {
    while ([[self m_clips] count] != 0) {
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:0];
        RemoveClipViews(c);
        [[self m_clips] rfx_removeObjectAtIndex:0];
    }
    [self CheckQueueHintLabel];
}

- (void)SwapImage:(ClipObject *)swapImage withalpha:(float)alpha {
    if ([swapImage m_swapimgv] == nil) return;
    [[swapImage m_imgv] setImage:nil];
    [[swapImage m_imgv] setAlpha:alpha];
    [[swapImage m_imgv] setImage:[[swapImage m_swapimgv] image]];
    [[swapImage m_swapimgv] removeFromSuperview];
    [swapImage setM_swapimgv:nil];
}

- (ClipObject *)IsClipInList:(ClipObject *)clipInList {
    if ([self m_clips] == nil) return nil;
    for (NSUInteger i = 0; i < [[self m_clips] count]; i++) {
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:i];
        if ([c ID] == [clipInList ID] && [c m_serverid] == [clipInList m_serverid] && [c m_ipodid] == [clipInList m_ipodid])
            return c;
    }
    return nil;
}

static NSString *CopyStr(NSString *s) { return s == nil ? nil : [NSString stringWithFormat:@"%@", s]; }

- (void)CopyPropertiesFromObject:(ClipObject *)from toObject:(ClipObject *)object {
    [object setM_interpret:[NSString stringWithFormat:@"%@", [from m_interpret]]];
    [object setM_title:[NSString stringWithFormat:@"%@", [from m_title]]];
    [object setID:[from ID]];
    [object setM_filesize:[from m_filesize]];
    [object setM_ipodid:[from m_ipodid]];
    [object setM_folderipodid:[from m_folderipodid]];
    [object setM_filepath:CopyStr([from m_filepath])];
    [object setM_picturepath:CopyStr([from m_picturepath])];
    [object setM_folderid:[from m_folderid]];
    [object setM_serverid:[from m_serverid]];
    [object setM_albumid:[from m_albumid]];
    [object setM_albumname:CopyStr([from m_albumname])];
    [object setM_tracknumber:[from m_tracknumber]];
    [object setM_duration:[from m_duration]];
    [object setM_information:CopyStr([from m_information])];
    [object setM_starttime:[from m_starttime]];
    [object setM_channelid:[from m_channelid]];
    [object setM_epgid:[from m_epgid]];
    [object setM_filename:CopyStr([from m_filename])];
    [object setM_genre:CopyStr([from m_genre])];
    [object setM_channel:CopyStr([from m_channel])];
    [object setM_spotifyid:CopyStr([from m_spotifyid])];
    [object setM_spotifyfolderid:CopyStr([from m_spotifyfolderid])];
}

- (void)CheckPendingSong {
    // DEVIATION: the original deleted the mp3 and cover files of songs the user had removed from the library
    // (m_clipstodelete).  The port never deletes files from the user's Documents folder; the list is just cleared.
    for (NSInteger i = (NSInteger)[[m_glv m_clipstodelete] count] - 1; i >= 0; i--) {
        ClipObject *c = [[m_glv m_clipstodelete] objectAtIndex:i];
        if ([self IsClipInList:c] == nil) [[m_glv m_clipstodelete] removeObjectAtIndex:i];
    }
}

- (void)RemoveOnlyFirstClip {
    m_ordering = NO;
    if ([[self m_clips] count] == 0) return;
    ClipObject *c = [[self m_clips] rfx_objectAtIndex:0];
    if ([c m_imgv] != nil && [[c m_imgv] superview] != nil) [[c m_imgv] removeFromSuperview];
    if ([c m_imgvtext] != nil && [[c m_imgvtext] superview] != nil) [[c m_imgvtext] removeFromSuperview];
    if ([c m_swapimgv] != nil && [[c m_swapimgv] superview] != nil) [[c m_swapimgv] removeFromSuperview];
    [[self m_clips] rfx_removeObjectAtIndex:0];
    if (mMCMixer != nil) [mMCMixer FadeOut:3.0f];
    [self setM_tenmintimer:CACurrentMediaTime()];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 3.5, false);
    [self setM_presongInitTime:-1.0];
    [self setM_shrinkdevider:NO];
    [self setM_crossfadeInitTime:-1.0];
    m_rotateclip = NO;
    m_cliptorotate = nil;
    m_angle = 0;
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
    [self SetDeviderPlayingPercent:0.0f];
    m_fadingover = NO;
    if ([[self m_clips] count] != 0) {
        [self StartOrderAni:nil];
        [self StartFirstFolderSong:[NSNumber numberWithInt:0]];
        m_fadingover = NO;
    }
}

- (void)CheckQueueHintLabel {
    // original: only active for the stationary-installation mode (m_isstattalm) which shows a hint after
    // one song is queued -- not part of the port.
}

- (void)SetLeftTimeInMTFirstObject:(UIImage *)img {
    if ([[self m_clips] count] != 0)
        [[[[self m_clips] rfx_objectAtIndex:0] m_imgvtext] setImage:img];
    [img release];
}

- (void)SetLeftTimeInMT:(UIImage *)img {
    if ([self m_draggingobj] != nil)
        [[[self m_draggingobj] m_imgvtext] setImage:img];
    [img release];
}

- (void)CheckRunningSongLeftTime {
    if ([self m_draggingobj] != nil && m_draggingrunningsong) {
        [[self m_draggingobj] retain];
        UIImage *img = [[m_glv CreateTextPicture:[self m_draggingobj] withtime:[self GetSongTimeLeft:[self m_draggingobj]] maxWidthPointer:NULL] retain];
        [[self m_draggingobj] release];
        [self performSelectorOnMainThread:@selector(SetLeftTimeInMT:) withObject:img waitUntilDone:NO];
    }
    if (m_showfirstsongInfos && [[self m_clips] count] != 0) {
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:0];
        [c retain];
        UIImage *img = [[m_glv CreateTextPicture:c withtime:[self GetSongTimeLeft:c] maxWidthPointer:NULL] retain];
        [c release];
        [self performSelectorOnMainThread:@selector(SetLeftTimeInMTFirstObject:) withObject:img waitUntilDone:NO];
    }
}

- (int)GetSongTimeLeft:(ClipObject *)song {
    if (song == nil) return -1;
    double left = (double)[song m_duration] - (CACurrentMediaTime() - [self m_crossfadeInitTime]);
    return left <= 0 ? 0 : (int)left;
}

- (int)GetTimeActSongPlayed {
    if ([self m_fadingover]) return -1;
    double played = CACurrentMediaTime() - [self m_clipStartTime];
    return played < 2.0 ? -1 : (int)played;
}

- (int)GetTimeGone {
    int t = (int)(CACurrentMediaTime() - [self m_clipStartTime]);
    return t <= 0 ? 0 : t;
}

#pragma mark - pictures

static UIImage *s_brightened = nil;     // data_00398844: result of BrightenPicture:

- (BOOL)CreateFolder:(NSString *)folder {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:folder]) return YES;
    NSError *err = nil;
    if ([fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&err]) return YES;
    [self performSelectorOnMainThread:@selector(SetDebugText:) withObject:@"Could not create directory" waitUntilDone:YES];
    return NO;
}

- (UIImage *)GetSmallImage:(ClipObject *)smallImage {
    NSString *p = [DEL BuildSmallPicpath:[smallImage m_picturepath]];
    return p == nil ? nil : [UIImage imageWithContentsOfFile:p];
}

- (void)CreateSmallPic:(UIImage *)smallPic withClipObject:(ClipObject *)clipObject {
    NSString *path = [DEL BuildSmallPicpath:[clipObject m_picturepath]];
    if (smallPic == nil) return;
    CGSize sz = [smallPic size];
    float shortSide = (sz.width < sz.height) ? sz.width : sz.height;
    float scale = shortSide / 40.0f;
    CGContextRef ctx = [DEL BeginImageContext:CGSizeMake((float)(int)(sz.width / scale), (float)(int)(sz.height / scale))];
    CGContextDrawImage(ctx, CGRectMake(0, 0, (float)(int)(sz.width / scale), (float)(int)(sz.height / scale)), [smallPic CGImage]);
    UIImage *out = [DEL EndImageContext:ctx];
    [UIImageJPEGRepresentation(out, 1.0f) writeToFile:path atomically:YES];
    [DEL AddSkipBackupAttributeToFile:path];
}

// Fits the picture into a kThumbSize square on black, then blends "dimmpixel.png" over it.  The result is
// left in s_brightened (retained), exactly like the original which used a global.
- (void)BrightenPicture:(NSData *)brightenPicture {
    UIImage *img = [[UIImage alloc] initWithData:brightenPicture];
    if (img == nil) return;
    float T = (float)kThumbSize;
    CGSize sz = [img size];
    float scale = (sz.width >= sz.height) ? (sz.width / T) : (sz.height / T);
    float xoff = 0, yoff = 0;
    if (sz.width != sz.height) {
        if (sz.width > sz.height) yoff = (float)(int)((double)(T - sz.height / scale) * 0.5);
        else xoff = (float)(int)((double)(T - sz.width / scale) * 0.5);
    }
    CGContextRef ctx = [DEL BeginImageContext:CGSizeMake(T, T)];
    CGContextSetFillColorWithColor(ctx, [[UIColor blackColor] CGColor]);
    CGContextFillRect(ctx, CGRectMake(0, 0, T, T));
    CGContextDrawImage(ctx, CGRectMake(xoff, yoff, (float)(int)(sz.width / scale), (float)(int)(sz.height / scale)), [img CGImage]);
    CGContextSetBlendMode(ctx, kCGBlendModeLuminosity);
    CGImageRef dimm = [[UIImage imageNamed:@"dimmpixel.png"] CGImage];
    CGImageRetain(dimm);
    CGContextDrawImage(ctx, CGRectMake(0, 0, T, T), dimm);
    s_brightened = [[DEL EndImageContext:ctx] retain];
    CGImageRelease(dimm);
    [img release];
}

// ---- ID3v2 picture extraction (replaces the original's C++ CId3v2 class) ----

static uint32_t ID3SyncSafe(const uint8_t *p) {
    return ((uint32_t)(p[0] & 0x7f) << 21) | ((uint32_t)(p[1] & 0x7f) << 14) | ((uint32_t)(p[2] & 0x7f) << 7) | (p[3] & 0x7f);
}

// index of the end of a text field in the given encoding (returns the index after the terminator)
static NSUInteger ID3SkipText(const uint8_t *b, NSUInteger i, NSUInteger end, int enc) {
    if (enc == 1 || enc == 2) {
        while (i + 1 < end) {
            if (b[i] == 0 && b[i + 1] == 0) return i + 2;
            i += 2;
        }
        return end;
    }
    while (i < end) { if (b[i++] == 0) return i; }
    return end;
}

// Returns the bytes of the first embedded picture of the tag or nil.
static NSData *ID3FindPicture(NSData *data, NSUInteger *neededTagSize) {
    const uint8_t *d = (const uint8_t *)[data bytes];
    NSUInteger len = [data length];
    if (neededTagSize) *neededTagSize = 0;
    if (len < 10 || memcmp(d, "ID3", 3) != 0) return nil;
    int ver = d[3];
    if (ver < 2 || ver > 4) return nil;
    uint8_t flags = d[5];
    NSUInteger tagSize = ID3SyncSafe(d + 6) + 10;
    if (neededTagSize) *neededTagSize = tagSize;
    if (tagSize > len) return nil;                      // tag not completely loaded yet
    NSUInteger pos = 10, end = tagSize;
    if (flags & 0x40) {                                 // extended header
        if (ver == 3 && pos + 4 <= end) pos += 4 + (((NSUInteger)d[pos] << 24) | (d[pos + 1] << 16) | (d[pos + 2] << 8) | d[pos + 3]);
        else if (ver == 4 && pos + 4 <= end) pos += ID3SyncSafe(d + pos);
    }
    BOOL unsync = (flags & 0x80) != 0;
    int hdr = (ver == 2) ? 6 : 10;
    while (pos + hdr <= end) {
        const uint8_t *f = d + pos;
        if (f[0] == 0) break;                           // padding
        NSUInteger fsize;
        if (ver == 2) fsize = ((NSUInteger)f[3] << 16) | (f[4] << 8) | f[5];
        else if (ver == 3) fsize = ((NSUInteger)f[4] << 24) | (f[5] << 16) | (f[6] << 8) | f[7];
        else fsize = ID3SyncSafe(f + 4);
        NSUInteger body = pos + hdr;
        if (fsize == 0 || body + fsize > end) break;
        BOOL isPic = (ver == 2) ? (memcmp(f, "PIC", 3) == 0) : (memcmp(f, "APIC", 4) == 0);
        if (isPic) {
            NSMutableData *tmp = nil;
            const uint8_t *b = d + body;
            NSUInteger n = fsize;
            if (unsync || (ver == 4 && (f[9] & 0x02))) {
                tmp = [NSMutableData dataWithCapacity:fsize];
                for (NSUInteger k = 0; k < fsize; k++) {
                    [tmp appendBytes:b + k length:1];
                    if (b[k] == 0xff && k + 1 < fsize && b[k + 1] == 0) k++;
                }
                b = (const uint8_t *)[tmp bytes];
                n = [tmp length];
            }
            if (n < 4) return nil;
            int enc = b[0];
            NSUInteger i = 1;
            if (ver == 2) i += 3;                       // 3 letter image format
            else i = ID3SkipText(b, i, n, 0);           // MIME type (always ISO-8859-1)
            if (i >= n) return nil;
            i += 1;                                     // picture type
            i = ID3SkipText(b, i, n, enc);              // description
            if (i >= n) return nil;
            return [NSData dataWithBytes:b + i length:n - i];
        }
        pos = body + fsize;
    }
    return nil;
}

- (NSString *)ExtractPicture:(NSString *)extractPicture {
    // DEVIATION: opened read-only (the original opened for updating because RepairHeader wrote into the mp3).
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:extractPicture];
    if (fh == nil) return nil;
    NSString *result = nil;
    @try {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:extractPicture error:NULL];
        NSNumber *fsize = [attrs objectForKey:NSFileSize];
        BOOL tooSmall = (fsize == nil) || [fsize intValue] <= 0x200;
        NSData *first = [fh readDataOfLength:0x200];
        if (first != nil && !tooSmall) {
            NSData *more = [fh readDataOfLength:0x4e20];
            if (more != nil) {
                NSMutableData *buf = [[NSMutableData alloc] init];
                [buf appendData:first];
                [buf appendData:more];
                NSUInteger need = 0;
                NSData *pic = ID3FindPicture(buf, &need);
                if (pic == nil && need > [buf length] && need < (16u << 20)) {
                    NSData *rest = [fh readDataOfLength:(need - [buf length])];
                    if (rest != nil) {
                        [buf appendData:rest];
                        pic = ID3FindPicture(buf, &need);
                    }
                }
                if (pic != nil && [pic length] != 0) {
                    NSString *jpg = [[extractPicture stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"];
                    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                    s_brightened = nil;
                    [self BrightenPicture:pic];
                    if (s_brightened != nil) {
                        [UIImageJPEGRepresentation(s_brightened, 1.0f) writeToFile:jpg atomically:YES];
                        [DEL AddSkipBackupAttributeToFile:jpg];
                        [s_brightened release];
                        s_brightened = nil;
                        result = [[jpg retain] autorelease];
                    }
                    [pool release];
                    [[result retain] autorelease];
                }
                [buf release];
            }
        }
    } @catch (NSException *e) {
        result = nil;
    }
    [fh closeFile];
    return result;
}

- (UIImage *)GetSongImage:(NSString *)songImage withclipobject:(ClipObject *)clipobject {
    if ([clipobject ID] == -6) return [UIImage imageNamed:@"waiting.png"];
    [clipobject retain];
    UIImage *img = nil;
    if (songImage != nil) {
        img = [UIImage imageWithContentsOfFile:songImage];
        if (img != nil && [clipobject ID] == -5) {
            // branding picture: crop to a centred square
            CGSize sz = [img size];
            if (sz.width != sz.height) {
                int x, y;
                if (sz.width <= sz.height) { x = 0; y = (int)((sz.height - sz.width) * 0.5f); }
                else { x = (int)((sz.width - sz.height) * 0.5f); y = 0; }
                CGImageRef cg = CGImageCreateWithImageInRect([img CGImage],
                    CGRectMake((float)x, (float)y, sz.width - (float)(x << 1), sz.height - (float)(y << 1)));
                UIImage *cropped = [UIImage imageWithCGImage:cg];
                CGImageRelease(cg);
                img = cropped;
            }
        }
    }
    if (img == nil && [clipobject m_picturepath] != nil)
        img = [UIImage imageWithContentsOfFile:[clipobject m_picturepath]];
    if (img == nil) {
        if ([clipobject m_filepath] != nil && [clipobject m_folderid] != -44 && [clipobject m_folderid] != -66) {
            [clipobject setM_picturepath:[self ExtractPicture:[clipobject m_filepath]]];
            if ([clipobject m_picturepath] != nil) img = [UIImage imageWithContentsOfFile:[clipobject m_picturepath]];
        } else if ([clipobject m_tracks] != nil) {
            [clipobject setM_picturepath:[self ExtractPicture:[[[clipobject m_tracks] objectAtIndex:0] m_filepath]]];
            if ([clipobject m_picturepath] != nil) img = [UIImage imageWithContentsOfFile:[clipobject m_picturepath]];
        }
    }
    BOOL found = (img != nil);

    ClipObject *src = clipobject;
    if ([clipobject m_tracks] != nil && [[clipobject m_tracks] count] != 0)
        src = [[clipobject m_tracks] objectAtIndex:0];

    if (!found && src != nil && [src m_filepath] != nil) {
        // No cover anywhere: paint one (random colour set, interpret rotated, title wrapped) and keep it
        // next to the mp3 as <mp3 name>.jpg so it is found next time.
        NSString *jpg = [[[src m_filepath] stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"];
        int T = kThumbSize;
        CGContextRef ctx = [DEL BeginImageContext:CGSizeMake((float)T, (float)T)];
        NSUInteger sets = [m_colorarray count] / 3;
        int ci = (int)(random() % sets);
        int c0 = [[m_colorarray objectAtIndex:ci * 3] intValue];
        int c1 = [[m_colorarray objectAtIndex:ci * 3 + 1] intValue];
        int c2 = [[m_colorarray objectAtIndex:ci * 3 + 2] intValue];
#define RGBCOL(c) [UIColor colorWithRed:(float)(((c) >> 16) & 0xff) / 255.0f green:(float)(((c) >> 8) & 0xff) / 255.0f blue:(float)((c) & 0xff) / 255.0f alpha:1.0f]
        CGContextSetFillColorWithColor(ctx, [RGBCOL(c0) CGColor]);
        CGContextFillRect(ctx, CGRectMake(0, 0, (float)T, (float)T));
        for (int pass = 0; pass < 2; pass++) {
            NSString *text = [(pass != 0 ? [src m_title] : [src m_interpret]) uppercaseString];
            if (text == nil) continue;
            if (pass == 0) {
                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx, (float)((double)T * 0.5), (float)((double)T * 0.5));
                CGContextRotateCTM(ctx, 1.5707963f);
                CGContextTranslateCTM(ctx, (float)((double)(0 - T) * 0.5), (float)((double)(0 - T) * 0.5));
            }
            CGContextSetFillColorWithColor(ctx, [RGBCOL(pass != 0 ? c1 : c2) CGColor]);
            if (pass == 0) {
                static NSString *const fonts[6] = { @"Futura-CondensedExtraBold", @"Verdana-Bold", @"Georgia-Bold",
                                                    @"HoeflerText-Black", @"AmericanTypewriter-Bold", @"GillSans-Bold" };
                UIFont *font = [UIFont fontWithName:fonts[random() % 6] size:55.0f];
                if (font == nil) font = [UIFont boldSystemFontOfSize:55.0f];
                [DEL OwndrawAtPoint:ctx withtext:text drawAtPoint:CGPointMake(0, 17.0f) forWidth:0 withFont:font lineBreakMode:0];
                CGContextRestoreGState(ctx);
            } else {
                NSMutableArray *lines = [[NSMutableArray alloc] init];
                NSMutableString *cur = [NSMutableString stringWithCapacity:1];
                NSArray *words = [text componentsSeparatedByString:@" "];
                int wordsInLine = 0;
                for (NSUInteger w = 0; w < [words count]; w++) {
                    [cur appendString:[NSString stringWithFormat:@"%@%@", (w == 0 ? @"" : @" "), [words objectAtIndex:w]]];
                    CGSize tsz = [cur sizeWithFont:m_titlefont];
                    int prev = wordsInLine;
                    wordsInLine++;
                    if (tsz.width > (float)(T - 40) && prev >= 1) {
                        NSUInteger wl = [[words objectAtIndex:w] length];
                        [cur deleteCharactersInRange:NSMakeRange([cur length] - (wl + 1), wl + 1)];
                        [lines addObject:[NSString stringWithFormat:@"%@", cur]];
                        [cur setString:[NSString stringWithFormat:@"%@", [words objectAtIndex:w]]];
                        wordsInLine = 1;
                    }
                    if (w == [words count] - 1 && [cur length] != 0) {
                        [lines addObject:[NSString stringWithFormat:@"%@", cur]];
                        [cur setString:@""];
                    }
                }
                int n = (int)[lines count];
                for (int i = n - 1; i >= 0; i--) {
                    NSString *line = [lines objectAtIndex:i];
                    CGSize lsz = [line sizeWithFont:m_titlefont];
                    int w = (int)(lsz.width < (float)(T - 40) ? lsz.width : (float)(T - 40));
                    int x = (T - (T - 40)) / 2;
                    int y = ((T - 24 * n) / 2) + 24 * (n - i) - 24;
                    [DEL OwndrawAtPoint:ctx withtext:line drawAtPoint:CGPointMake((float)x, (float)y) forWidth:w withFont:m_titlefont lineBreakMode:0];
                }
                [lines release];
            }
        }
        // 1px frame in a brighter shade of the background colour
        float h, s, v, r, g, b;
        [DEL RGBtoHSV:(float)((c0 >> 16) & 0xff) withgreen:(float)((c0 >> 8) & 0xff) withblue:(float)(c0 & 0xff) withue:&h withsat:&s withval:&v];
        double nv = (double)v * 1.4;
        float val = (nv < 255.0) ? (float)nv : 255.0f;
        [DEL HSVtoRGB:&r withgreen:&g withblue:&b withhue:h withsat:s withval:val];
        CGContextSetFillColorWithColor(ctx, [[UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:1.0f] CGColor]);
        CGContextFillRect(ctx, CGRectMake(0, 0, (float)T, 1.0f));
        CGContextFillRect(ctx, CGRectMake((float)(T - 1), 0, 1.0f, (float)T));
        CGContextFillRect(ctx, CGRectMake(0, (float)(T - 1), (float)T, 1.0f));
        CGContextFillRect(ctx, CGRectMake(0, 0, 1.0f, (float)T));
#undef RGBCOL
        img = [DEL EndImageContext:ctx];
        if (img != nil) {
            [UIImageJPEGRepresentation(img, 1.0f) writeToFile:jpg atomically:YES];
            [DEL AddSkipBackupAttributeToFile:jpg];
        }
        [src setM_picturepath:jpg];
    }
    if (img == nil) img = [UIImage imageNamed:@"cover-note.png"];
    if (src != clipobject && [src m_picturepath] != nil)
        [clipobject setM_picturepath:[NSString stringWithFormat:@"%@", [src m_picturepath]]];
    [clipobject release];
    return img;
}

#pragma mark - touches

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    if (t == nil) return;
    if ([m_glv m_selectedfolderid] == -33) return;
    CGPoint p = [t locationInView:self];
    m_starttouchpoint = p;
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    [self touchesBeganDelayed:po];
}

- (void)touchesBeganDelayed:(CGPointObject *)touchesBeganDelayed {
    float x = [touchesBeganDelayed x];
    float y = [touchesBeganDelayed y];
    [touchesBeganDelayed release];
    [m_glv StopIdleTimer];
    [m_glv StopAdvertTimer];
    if (m_fadingover) return;
    if ([m_glv IsShowingChannelView]) return;
    if ([DEL m_isstattalm] && [m_glv IsShowingAskBox]) {
        [m_glv setM_cancelcard:YES];
        return;
    }
    int flags = [m_sve StateFlags];
    if ((flags & 4) != 0 && (flags & 8) != 0) return;
    if ([self m_draggingobj] != nil) return;
    int thumb = THUMB;
    float xdiff = [self m_ignoreXdiff] ? 0 : (float)m_lastCDXDiff;
    if ([[self m_clips] count] == 0) return;
    int idx = (int)(((x + xdiff) - (float)(border / 2)) / (float)(border + thumb));
    if ((unsigned)idx >= [[self m_clips] count]) return;
    m_oldindex = idx;

    if (idx == 0) {
        if ((flags & 0x10) != 0 || (flags & 8) != 0) {
            // not draggable: only show the remaining time above the running song
            ClipObject *first = [[self m_clips] rfx_objectAtIndex:0];
            CGRect fr = [self GetFrameForDragPic:0];
            if ([first m_imgvtext] == nil)
                [first setM_imgvtext:[[UIImageView alloc] initWithFrame:CGRectZero]];
            [[first m_imgvtext] setAlpha:0.5f];
            int w = 0;
            [[first m_imgvtext] setImage:[m_glv CreateTextPicture:first withtime:[self GetSongTimeLeft:first] maxWidthPointer:&w]];
            float W = (float)(thumb + 0x2bc);
            float x0 = fr.origin.x - 350.0f;
            int v = (int)((x0 + W * 0.5f) - 10.0f);
            float tx = (v <= -1) ? ((x0 - (float)v) + 5.0f) : x0;
            [[first m_imgvtext] setFrame:CGRectMake(tx, (fr.origin.y - fr.size.height) - 23.0f, W, (float)((double)thumb * 3.0 * 0.25))];
            if ([[first m_imgvtext] superview] != self) {
                [self addSubview:[first m_imgvtext]];
                [[first m_imgvtext] release];
            }
            m_showfirstsongInfos = YES;
            return;
        }
        m_draggingrunningsong = YES;
        [[[[self m_clips] rfx_objectAtIndex:0] m_imgv] setTransform:CGAffineTransformMakeRotation(0)];
    }

    // pick the thumbnail up: a copy of it follows the finger
    ClipObject *src = [[[self m_clips] rfx_objectAtIndex:idx] retain];
    m_draggingobj = [[ClipObject alloc] init];
    [self CopyPropertiesFromObject:src toObject:[self m_draggingobj]];
    if (idx >= 1 && mMCMixer != nil) [mMCMixer PlayPrePlay:m_draggingobj];
    if ([src m_imgv] != nil && [[src m_imgv] image] != nil) {
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectZero];
        [[self m_draggingobj] setM_imgv:iv];
        [self addSubview:[[self m_draggingobj] m_imgv]];
        [iv release];
        UIImage *copy = [[UIImage alloc] initWithCGImage:[[[src m_imgv] image] CGImage]];
        [[[self m_draggingobj] m_imgv] setImage:copy];
        [copy release];
    }
    if ([src m_swapimgv] != nil && [[src m_swapimgv] image] != nil) {
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectZero];
        [[self m_draggingobj] setM_swapimgv:iv];
        [self addSubview:[[self m_draggingobj] m_swapimgv]];
        [iv release];
        UIImage *copy = [[UIImage alloc] initWithCGImage:[[[src m_swapimgv] image] CGImage]];
        [[[self m_draggingobj] m_swapimgv] setImage:copy];
        [copy release];
    }
    if ([[self m_draggingobj] m_imgvtext] == nil) {
        int left = m_draggingrunningsong ? [self GetSongTimeLeft:[self m_draggingobj]] : -1;
        UIImageView *iv = [[UIImageView alloc] initWithImage:[m_glv CreateTextPicture:src withtime:left maxWidthPointer:NULL]];
        [[self m_draggingobj] setM_imgvtext:iv];
        [self addSubview:[[self m_draggingobj] m_imgvtext]];
        [iv release];
    }
    [[[self m_draggingobj] m_imgvtext] setAlpha:0.5f];
    if ([[self m_draggingobj] m_swapimgv] == nil) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:[m_glv CreateCDPicture:src roundpic:NO]];
        [[self m_draggingobj] setM_swapimgv:iv];
        [self addSubview:[[self m_draggingobj] m_swapimgv]];
        [iv release];
    }
    [[[self m_draggingobj] m_swapimgv] setAlpha:0.5f];
    [[[self m_draggingobj] m_imgv] setAlpha:0.0f];
    [[[self m_draggingobj] m_imgv] setFrame:CGRectMake(x - (float)(thumb >> 1), y - (float)(thumb >> 1), (float)thumb, (float)thumb)];
    [self bringSubviewToFront:[[self m_draggingobj] m_imgv]];
    CGRect f = [[[self m_draggingobj] m_imgv] frame];
    [[[self m_draggingobj] m_imgvtext] setFrame:CGRectMake(f.origin.x - 350.0f, (f.origin.y - f.size.height) - 23.0f,
                                                           (float)(thumb + 0x2bc), (float)((double)thumb * 3.0 * 0.25))];
    [self bringSubviewToFront:[[self m_draggingobj] m_imgvtext]];
    f = [[[self m_draggingobj] m_imgv] frame];
    [[[self m_draggingobj] m_swapimgv] setFrame:CGRectMake(f.origin.x + f.size.width * -0.5f, f.origin.y + f.size.height * -0.5f,
                                                           f.size.width + f.size.width, f.size.height + f.size.height)];
    [self bringSubviewToFront:[[self m_draggingobj] m_swapimgv]];
    m_draggingorigpos = idx;
    m_dragginposforremotecmds = idx;
    [src release];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (m_fadingover) return;
    if ([m_glv IsShowingChannelView]) return;
    UITouch *t = [touches anyObject];
    if (t == nil) return;
    CGPoint p = [t locationInView:self];
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    [self touchesMovedDelayed:po];
}

- (void)touchesMovedDelayed:(CGPointObject *)touchesMovedDelayed {
    float x = [touchesMovedDelayed x];
    float y = [touchesMovedDelayed y];
    [touchesMovedDelayed release];
    int thumb = THUMB;
    if ([self m_draggingobj] == nil) return;
    [[[self m_draggingobj] m_imgv] setFrame:CGRectMake(x - (float)(thumb >> 1), y - (float)(thumb >> 1), (float)thumb, (float)thumb)];
    CGRect f = [[[self m_draggingobj] m_imgv] frame];
    [[[self m_draggingobj] m_imgvtext] setFrame:CGRectMake(f.origin.x - 350.0f, (f.origin.y - f.size.height) - 23.0f,
                                                           (float)(thumb + 0x2bc), (float)((double)thumb * 3.0 * 0.25))];
    if ([[self m_draggingobj] m_swapimgv] != nil) {
        f = [[[self m_draggingobj] m_imgv] frame];
        [[[self m_draggingobj] m_swapimgv] setFrame:CGRectMake(f.origin.x + f.size.width * -0.5f, f.origin.y + f.size.height * -0.5f,
                                                               f.size.width + f.size.width, f.size.height + f.size.height)];
    }
    BOOL moved = fabsf(m_starttouchpoint.x - x) >= 18.0f || fabsf(m_starttouchpoint.y - y) >= 18.0f;
    if (!moved) return;
    if (m_draggingorigpos == -1) return;
    // the finger left the touch-down spot: take the original out of the queue
    if ((unsigned)m_draggingorigpos < [[self m_clips] count]) {
        if (m_draggingorigpos == 0) m_lastCDXDiff = 0;
        ClipObject *c = [[self m_clips] rfx_objectAtIndex:m_draggingorigpos];
        if ([c m_imgv] != nil && [[c m_imgv] superview] != nil) [[c m_imgv] removeFromSuperview];
        if ([c m_imgvtext] != nil && [[c m_imgvtext] superview] != nil) [[c m_imgvtext] removeFromSuperview];
        if ([c m_swapimgv] != nil && [[c m_swapimgv] superview] != nil) [[c m_swapimgv] removeFromSuperview];
        [c setM_imgv:nil];
        [c setM_imgvtext:nil];
        [c setM_swapimgv:nil];
        if (m_draggingorigpos == 0) {
            m_rotateclip = NO;
            m_cliptorotate = nil;
        }
        [[self m_clips] rfx_removeObjectAtIndex:m_draggingorigpos];
        m_ordering = YES;
        if (m_draggingorigpos == 0) m_lastCDXDiff = 0;
        [UIView beginAnimations:@"OrderClipsAni" context:NULL];
        [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationDuration:0.6];
        [self OrderClipPics:[NSNumber numberWithInt:1]];
        [UIView commitAnimations];
        [self CheckQueueHintLabel];
    }
    m_draggingorigpos = -1;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    if (t == nil) return;
    CGPoint p = [t locationInView:self];
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    [self touchesEndedDelayed:po];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    if (t == nil) return;
    CGPoint p = [t locationInView:self];
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    [self touchesEndedDelayed:po];
}

// A tap on a queue thumbnail (second tap within 0.4s) -- shared by the "dragging obj discarded" and the plain path.
- (void)HandleQueueTapAtX:(float)x {
    if (startTime <= 0) {
        startTime = CACurrentMediaTime();
        return;
    }
    if (CACurrentMediaTime() - startTime >= 0.4) {
        startTime = CACurrentMediaTime();
        return;
    }
    int thumb = THUMB;
    float xdiff = [self m_ignoreXdiff] ? 0 : (float)m_lastCDXDiff;
    int maxIdx;
    if (ISIPAD) maxIdx = 9;
    else maxIdx = ([self frame].size.width > [self frame].size.height) ? 6 : 4;
    int idx = (int)(((x + xdiff) - (float)(border / 2)) / (float)(border + thumb));
    if (idx < maxIdx) {
        unsigned count = (unsigned)[[self m_clips] count];
        if (idx >= 1 && !((unsigned)idx >= count)) {
            if ([m_glv m_selectedfolderid] != -33) {
                int flags = [m_sve StateFlags];
                if ((flags & 0x10) == 0 && (flags & 4) == 0) {
                    // double tap on a queued song: play it now
                    m_fadingover = YES;
                    [self setM_rotateclip:NO];
                    m_cliptorotate = nil;
                    [self setM_presongInitTime:-1.0];
                    [self setM_crossfadeInitTime:-1.0];
                    if (idx >= 2) {
                        ClipObject *moved = [[[self m_clips] rfx_objectAtIndex:idx] retain];
                        if ([moved m_imgv] != nil) [self CorrectZindexComplete:moved];
                        [[self m_clips] rfx_removeObjectAtIndex:idx];
                        [[self m_clips] rfx_insertObject:moved atIndex:1];
                        [moved release];
                    }
                    ClipObject *first = [[[self m_clips] rfx_objectAtIndex:0] retain];
                    [[self m_clips] rfx_removeObjectAtIndex:0];
                    [self performSelector:@selector(FadeOverProcess:) withObject:nil afterDelay:0.8];
                    [self StartOrderAni:first];
                    [self performSelectorOnMainThread:@selector(CheckQueueHintLabel) withObject:nil waitUntilDone:YES];
                    [self SendCDsToBackGround];
                }
            }
        }
    } else {
        // tap right of the queue: open the keyboard / register
        if (m_blackview == nil) {
            if (![m_glv IsShowingMTScroller]) {
                if (![[m_glv GetKBView] m_keyboardshown]) {
                    if (([m_sve StateFlags] & 0x40000) == 0)
                        [m_glv ToggleKBAndRegister:[NSNumber numberWithInt:5]];
                }
            }
        }
    }
    startTime = -1.0;
}

- (void)touchesEndedDelayed:(CGPointObject *)touchesEndedDelayed {
    [m_glv RestartIdleTimer];
    [m_glv RestartAdvertTimer];
    float x = [touchesEndedDelayed x];
    float y = [touchesEndedDelayed y];
    [touchesEndedDelayed release];
    if (m_showfirstsongInfos && [[self m_clips] count] != 0) {
        m_showfirstsongInfos = NO;
        ClipObject *first = [[self m_clips] rfx_objectAtIndex:0];
        if ([first m_imgvtext] != nil) {
            [[first m_imgvtext] removeFromSuperview];
            [first setM_imgvtext:nil];
        }
    }
    if (![self g_scaling]) [m_glv CheckToRemoveRegister];

    BOOL discardDrag = m_fadingover || ([m_glv IsShowingChannelView] && !m_shutdown);
    if (discardDrag) {
        if ([self m_draggingobj] != nil) {
            ClipObject *obj = m_draggingobj;
            m_draggingobj = nil;
            [self performSelector:@selector(DeleteCDAni:) withObject:obj afterDelay:0.1];
        }
        return;
    }

    if ([self m_draggingobj] == nil) {
        [self HandleQueueTapAtX:x];
        return;
    }

    if (mMCMixer != nil) [mMCMixer StopPreplay];

    if (m_draggingorigpos != -1) {
        // the finger never left the touch-down spot: it was a tap, drop the drag copy
        m_draggingorigpos = -1;
        if ([m_draggingobj m_imgv] != nil && [[m_draggingobj m_imgv] superview] != nil) [[m_draggingobj m_imgv] removeFromSuperview];
        if ([m_draggingobj m_imgvtext] != nil && [[m_draggingobj m_imgvtext] superview] != nil) [[m_draggingobj m_imgvtext] removeFromSuperview];
        if ([m_draggingobj m_swapimgv] != nil && [[m_draggingobj m_swapimgv] superview] != nil) [[m_draggingobj m_swapimgv] removeFromSuperview];
        if (m_draggingobj != nil) {
            [m_draggingobj release];
            m_draggingobj = nil;
        }
        m_draggingrunningsong = NO;
        if (startTime > 0) {
            [self HandleQueueTapAtX:x];
        } else {
            startTime = CACurrentMediaTime();
            [self SendCDsToBackGround];
        }
        return;
    }

    // the dragged thumbnail was dropped: where?
    int pos = -5;
    BOOL removeFirst = NO;      // r4
    BOOL recalcXdiff = NO;      // r6
    BOOL rotateFirst = NO;      // r8
    int flags = [m_sve StateFlags];
    if (CGRectContainsPoint([m_glv frame], CGPointMake(x, y))) {
        // dropped on the coverflow: remove it from the queue
        if ((flags & 8) != 0) {
            pos = (int)[[self m_clips] count];
            [self CheckInsertPosition:&pos];
            removeFirst = YES;
        } else {
            ClipObject *obj = m_draggingobj;
            m_draggingobj = nil;
            if (m_draggingrunningsong) m_fadingover = YES;
            [self performSelector:@selector(DeleteCDAni:) withObject:obj afterDelay:0.1];
            [self performSelector:@selector(CheckPendingSong) withObject:nil afterDelay:0.7];
            removeFirst = YES;
        }
    } else {
        unsigned count = (unsigned)[[self m_clips] count];
        unsigned ins = (unsigned)[self GetInsertIndex:CGPointMake(x, y)];
        if (ins > count && count != 0) pos = (int)count;
        else pos = (int)ins;
        [self CheckInsertPosition:&pos];
        count = (unsigned)[[self m_clips] count];
        if (count == 0) {
            pos = 0;
            if (m_draggingrunningsong) {
                m_draggingrunningsong = NO;
                removeFirst = YES; recalcXdiff = YES; rotateFirst = YES;
            } else if (mMCMixer != nil && [mMCMixer isPlaying]) {
                if ((flags & 0x10) != 0) { removeFirst = YES; pos = 1; }
                else {
                    removeFirst = YES;
                    if (!m_playingjingle) {
                        m_fadingover = YES;
                        [self performSelector:@selector(FadeOverProcess:) withObject:nil afterDelay:0.8];
                    }
                }
            } else {
                pos = 0;
                removeFirst = YES;
            }
        } else if (pos == 0) {
            if (m_draggingrunningsong) {
                m_draggingrunningsong = NO;
                removeFirst = YES; recalcXdiff = YES; rotateFirst = YES;
            } else if (mMCMixer != nil && [mMCMixer isPlaying]) {
                if ((flags & 0x10) != 0) { removeFirst = YES; pos = 1; }
                else {
                    removeFirst = YES;
                    if (!m_playingjingle) {
                        m_fadingover = YES;
                        [self performSelector:@selector(FadeOverProcess:) withObject:nil afterDelay:0.8];
                    }
                }
            } else {
                removeFirst = YES;
            }
        } else if (m_draggingrunningsong) {
            if ((flags & 4) != 0) {
                pos = 0;
                m_draggingrunningsong = NO;
                removeFirst = YES; rotateFirst = YES;
            } else {
                m_draggingrunningsong = NO;
                [self setM_ignoreXdiff:YES];
                removeFirst = YES;
                if (!m_playingjingle) {
                    m_fadingover = YES;
                    [self performSelector:@selector(FadeOverProcess:) withObject:nil afterDelay:0.8];
                    removeFirst = NO;
                }
            }
        } else {
            removeFirst = YES;
        }
    }

    if (pos >= 0) {
        ClipObject *oldFirst = nil;     // local_c
        if (m_fadingover && removeFirst) {
            oldFirst = [[[self m_clips] rfx_objectAtIndex:0] retain];
            [[self m_clips] rfx_removeObjectAtIndex:0];
        }
        [[self m_clips] rfx_insertObject:[self m_draggingobj] atIndex:pos];
        m_dragginposforremotecmds = -1;
        [self CorrectZindexComplete:m_draggingobj];
        [m_draggingobj release];        // the array holds it now
        m_draggingobj = nil;
        if (recalcXdiff) {
            double played = CACurrentMediaTime() - [self m_clipStartTime];
            m_lastCDXDiff = (m_clipDuration > 0) ? [self CalcXDiff:(float)((m_clipDuration - played) / m_clipDuration)] : 0;
        }
        [self StartOrderAni:oldFirst];
        if (rotateFirst) {
            m_angle = 0;
            m_cliptorotate = [[self m_clips] rfx_objectAtIndex:0];
            m_rotateclip = YES;
        }
        [self CheckQueueHintLabel];
    }
    [self SendCDsToBackGround];
}

#pragma mark - pinch (volume)

- (void)scaleVolume:(UIPinchGestureRecognizer *)scaleVolume {
    float scale = (float)[scaleVolume scale];
    [self Restart30secsearchTimer];
    switch ([scaleVolume state]) {
    case UIGestureRecognizerStateEnded:
        [self setG_scaling:NO];
        [m_glv RestartIdleTimer];
        [m_glv RestartAdvertTimer];
        if ([m_glv m_pinchstatus] == 2) [[m_glv getScroller] RestartOverviewTimer];
        if ([[m_glv GetKBView] m_keyboardshown] && [[m_glv GetKBView] m_showwhat] == 0)
            [[m_glv GetKBView] RestartKeyboardtimerFast];
        if ([m_glv m_volumepinch] > 0) {
            [m_glv setM_volumepinch:-1.0f];
            [m_glv RemoveDraggingObject];
            [self SetLastVolumeKiosk];
        }
        break;
    case UIGestureRecognizerStateChanged:
        if ([m_glv m_volumepinch] > 0) {
            if (![self m_fadingover]) {
                double k = ISIPAD ? 1.0 : 2.0;
                float nv = (float)((double)[m_glv m_volumepinch] + (((double)scale - 1.0) * 0.5) * k);
                nv = fminf(1.0f, fmaxf(0.0f, nv));
                [self setM_lastvolume:nv];
                [self SetPlayerVolume:nv];
                [[m_glv GetKBView] SetVolSlider:[self m_lastvolume]];
            }
            [m_glv RemoveDraggingObject];
        }
        break;
    case UIGestureRecognizerStateBegan:
        [self setG_scaling:YES];
        [m_glv StopIdleTimer];
        [m_glv StopAdvertTimer];
        if ([m_glv m_pinchstatus] == 2) [[m_glv getScroller] RestartOverviewTimer];
        if (([m_glv m_lastflags] & 0x1000) != 0) return;
        if ([DEL m_useownvolume] != 0) return;
        [m_glv setM_volumepinch:[self GetPlayerVolume]];
        if ((double)[m_glv m_volumepinch] < 0.001) [m_glv setM_volumepinch:0.001f];
        [m_glv RemoveDraggingObject];
        if ([m_glv m_pinchstatus] == 2) {
            [[m_glv GetKBView] StopKeyboardtimer];
            [m_glv ShowVolumeForOverview];
        }
        if (![[m_glv GetKBView] m_keyboardshown]) {
            [[m_glv GetKBView] StopKeyboardtimer];
            [m_glv performSelector:@selector(ToggleKBAndRegister:) withObject:[NSNumber numberWithInt:0] afterDelay:0.01];
        }
        break;
    default:
        break;
    }
}

// Port diagnostics: one-time on-screen status for the first play request (no debugger on a sideloaded device).
static void KV_PlayStatus(NSString *text) {
    NSLog(@"[Play] %@", text);       // on-screen status window removed (log only)
}

#pragma mark - now playing

// ---- Now Playing / lock screen / Control Center (port addition) ------------------------------------------
- (void)SetupRemoteCommands {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    MPRemoteCommandCenter *rc = [MPRemoteCommandCenter sharedCommandCenter];
    [[rc playCommand] addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        if ([self m_pausebegintime] >= 0) [self OtherAudio:0]; else [self ContinuePlayers];
        [self UpdateNowPlayingRate];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [[rc pauseCommand] addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        if ([self m_pausebegintime] < 0) [self OtherAudio:0]; else [self PausePlayers];
        [self UpdateNowPlayingRate];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [[rc togglePlayPauseCommand] addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        [self OtherAudio:0];
        [self UpdateNowPlayingRate];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [[rc nextTrackCommand] addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
        if ([[self m_clips] count] == 0) return MPRemoteCommandHandlerStatusNoActionableNowPlayingItem;
        [self CheckNextSong:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:0], @"how",
                             [NSNumber numberWithFloat:1.0f], @"time", nil]];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [[rc previousTrackCommand] setEnabled:NO];
    [[rc seekForwardCommand] setEnabled:NO];
    [[rc seekBackwardCommand] setEnabled:NO];
    [[rc changePlaybackPositionCommand] setEnabled:NO];
}

- (void)UpdateNowPlayingRate {
    MPNowPlayingInfoCenter *c = [MPNowPlayingInfoCenter defaultCenter];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:[c nowPlayingInfo]];
    if ([d count] == 0) return;
    BOOL paused = ([self m_pausebegintime] >= 0) || (mMCMixer != nil && ![mMCMixer isPlaying]);
    [d setObject:[NSNumber numberWithDouble:paused ? 0.0 : 1.0] forKey:MPNowPlayingInfoPropertyPlaybackRate];
    [c setNowPlayingInfo:d];
}

- (void)UpdateNowPlayingForClip:(ClipObject *)clip {
    if (clip == nil || [clip m_folderid] == -44 || [clip m_folderid] == -66) return;
    [self SetupRemoteCommands];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if ([clip m_title]) [d setObject:[clip m_title] forKey:MPMediaItemPropertyTitle];
    if ([clip m_interpret]) [d setObject:[clip m_interpret] forKey:MPMediaItemPropertyArtist];
    if ([clip m_albumname] && [[clip m_albumname] length]) [d setObject:[clip m_albumname] forKey:MPMediaItemPropertyAlbumTitle];
    if ([clip m_duration] > 0) [d setObject:[NSNumber numberWithInt:[clip m_duration]] forKey:MPMediaItemPropertyPlaybackDuration];
    [d setObject:[NSNumber numberWithDouble:0.0] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [d setObject:[NSNumber numberWithDouble:1.0] forKey:MPNowPlayingInfoPropertyPlaybackRate];
    UIImage *img = ([clip m_picturepath] != nil) ? [UIImage imageWithContentsOfFile:[clip m_picturepath]] : nil;
    if (img != nil) {
        MPMediaItemArtwork *art = [[MPMediaItemArtwork alloc] initWithBoundsSize:[img size]
                                                                  requestHandler:^UIImage *(CGSize sz) { return img; }];
        [d setObject:art forKey:MPMediaItemPropertyArtwork];
        [art release];
    }
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:d];
    // the real length is only known once the mixer has opened the file
    [self performSelector:@selector(RefreshNowPlayingDuration) withObject:nil afterDelay:1.0];
}

- (void)RefreshNowPlayingDuration {
    if (mMCMixer == nil) return;
    int dur = [mMCMixer duration];
    if (dur <= 0) return;
    MPNowPlayingInfoCenter *c = [MPNowPlayingInfoCenter defaultCenter];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:[c nowPlayingInfo]];
    if ([d count] == 0) return;
    [d setObject:[NSNumber numberWithInt:dur] forKey:MPMediaItemPropertyPlaybackDuration];
    [c setNowPlayingInfo:d];
}

#pragma mark - playback

- (BOOL)WillPlayJingle { return NO; }   // jingles are a server feature (GetReserved2Val) -- see DEVIATIONS.md

- (void)SetMixerFlags {
    // ambience (second audio source) is not part of the port, so only the stereo/mono flags remain
    int flags = [[self m_sve] StateFlags];
    if ((flags & 0x200000) != 0 || (flags & 0x400000) != 0) [mMCMixer setPlayMono];
    else [mMCMixer setPlayStereo];
    [mMCMixer setAllowPrePlay:((flags & 0x400000) != 0)];
}

- (void)PlayFileOnBackground:(NSString *)fileOnBackground {
    if ([self mMCMixer] != nil)
        [[self mMCMixer] PlayFile:fileOnBackground widthCrossfadeTime:m_crossfadetime inSteps:0x14];
}

- (void)StartOnePlayer:(int)onePlayer withVolume:(float)volume withurl:(NSURL *)url withclipobject:(ClipObject *)clipobject {
    if (url == nil) {
        NSString *pp = [clipobject m_picturepath];
        NSString *dirp = [pp stringByDeletingLastPathComponent];
        NSArray *list = (dirp != nil) ? [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirp error:nil] : nil;
        KV_PlayStatus([NSString stringWithFormat:@"no file for this clip (id %lld, folder %lld)\nfilepath: %@\npicture: %@\ntitle: %@ / %@\nfiles in folder: %@", [clipobject ID], [clipobject m_folderid], [clipobject m_filepath], pp, [clipobject m_interpret], [clipobject m_title], [list componentsJoinedByString:@" | "]]);
        return;
    }
    if ([clipobject m_folderid] == -66 || [clipobject m_folderid] == -44) { KV_PlayStatus(@"clip is a special folder, skipped"); return; }
    KV_PlayStatus([NSString stringWithFormat:@"play requested\n%@\nexists: %d\nout volume %.2f, mute %d", [url path], (int)[[NSFileManager defaultManager] fileExistsAtPath:[url path]], volume, (int)[DEL g_mute]]);
    if (mMCMixer == nil) mMCMixer = [[MultichannelMixerController alloc] init];
    [self SetMixerFlags];
    [mMCMixer startAUGraph];
    BOOL reduce = [DEL g_reduce];
    BOOL mute = [DEL g_mute];
    float v = mute ? 0.0f : (reduce ? volume * 0.25f : volume);
    [mMCMixer setOutputVolume:v];
    [self UpdateNowPlayingForClip:clipobject];
    [self performSelectorOnMainThread:@selector(PlayFileOnBackground:) withObject:[url path] waitUntilDone:NO];
    [mMCMixer setOutputVolume:v];
}

- (void)StartAudioPlayer:(ClipObject *)audioPlayer withAniNext:(BOOL)aniNext witharg1:(int)arg1 {
    if (audioPlayer != nil) {
        [m_glv MarkClipPlayed:audioPlayer];
        if ([audioPlayer ID] > 0)
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithLongLong:[audioPlayer ID]] forKey:@"RfxLastClipID"];
    }
    [self setM_crossfadeInitTime:-1.0];
    m_didfade = NO;
    m_spinHold = CACurrentMediaTime() + 6.0;      // the CD spins from the moment the song is started
    [self RotationFrame];
    if (audioPlayer != nil && [audioPlayer m_folderid] != -44 && !m_autoselected) {
        DBOperations *dbop = [[DBOperations alloc] init];
        [DEL LockDB:YES];
        [dbop IncTimesPlayed:audioPlayer];
        [DEL UnlockDB];
        [dbop release];
    }
    NSURL *url = nil;
    if (audioPlayer != nil && [audioPlayer m_folderid] != -44 && [audioPlayer m_folderid] != -66 && [audioPlayer m_filepath] != nil)
        url = [NSURL fileURLWithPath:[audioPlayer m_filepath]];

    if (mMCMixer != nil && [mMCMixer isPlaying]) {
        // something is playing already: start the new song on the next bus (the mixer cross fades them)
        m_didfade = YES;
        BOOL pad = ISIPAD;
        NSUInteger count = [[self m_clips] count];
        int pinch = [m_glv m_pinchstatus];
        BOOL logo = !(pinch != 0 || count >= (NSUInteger)(pad ? 4 : 3));
        if (logo) [self LogoAni:[NSNumber numberWithInt:1]];
        [self StartOnePlayer:0 withVolume:[self m_lastvolume] withurl:url withclipobject:audioPlayer];
        // Port change: the new CD starts spinning and the queue starts to slide as soon as its song fades in
        // (the original waited for the whole cross fade first, ~5 s later).
        BOOL inQueue = (audioPlayer != nil && [[self m_clips] indexOfObjectIdenticalTo:audioPlayer] != NSNotFound);
        if (aniNext && inQueue) {
            m_angle = 0;
            m_lastRotTime = 0;
            m_cliptorotate = audioPlayer;
            [self setM_rotateclip:YES];
            if (logo) [self performSelector:@selector(LogoAni:) withObject:[NSNumber numberWithInt:0] afterDelay:(double)m_crossfadetime];
            m_oldindex = m_oldindex - 1;
            [self setM_resetfadeover:CACurrentMediaTime() + (double)m_crossfadetime + 0.9];
            m_restEarly = YES;
            if (!([DEL g_end] || gv_kioskflag) && [self AniToNextSong:audioPlayer withjingle:nil]) return;
            m_restEarly = NO;
        } else {
            double t0 = CACurrentMediaTime();
            for (;;) {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
                if (CACurrentMediaTime() >= t0 + (double)m_crossfadetime) break;
                if ([DEL g_end] || gv_kioskflag) break;
            }
            m_oldindex = m_oldindex - 1;
            if (logo && !([DEL g_end] || gv_kioskflag))
                [self LogoAni:[NSNumber numberWithInt:0]];
        }
    } else {
        m_fadingover = YES;
        m_crossfadetime = 2.0f;
        [self StartOnePlayer:0 withVolume:[self m_lastvolume] withurl:url withclipobject:audioPlayer];
        [self setM_resetfadeover:CACurrentMediaTime() + (double)m_crossfadetime + 0.9];
        if (aniNext && audioPlayer != nil && [[self m_clips] indexOfObjectIdenticalTo:audioPlayer] != NSNotFound) {
            m_angle = 0; m_lastRotTime = 0; m_cliptorotate = audioPlayer; [self setM_rotateclip:YES];
        }
        if ([[self m_clips] count] >= 2 && aniNext) {
            if ([self AniToNextSong:audioPlayer withjingle:nil]) return;
        }
    }
    if ([DEL g_end] || gv_kioskflag) return;
    [self StartAudioPlayerRest];
}

- (BOOL)AniToNextSong:(ClipObject *)aniToNextSong withjingle:(NSString *)jingle {
    ClipObject *first = [[self m_clips] rfx_objectAtIndex:0];
    if ([[self m_clips] count] >= 2) {
        BOOL keepSpin = (m_cliptorotate != nil && m_cliptorotate != first && [self m_rotateclip]);
        if (!keepSpin) {
            [self setM_rotateclip:NO];
            m_cliptorotate = nil;
        }
        RemoveClipViews(first);
        [[self m_clips] rfx_removeObjectAtIndex:0];
        m_ordering = YES;
        [self setM_ignoreXdiff:YES];
        [UIView beginAnimations:@"OrderClipsAni" context:NULL];
        [UIView setAnimationDidStopSelector:@selector(StartAudioPlayerRest)];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
        [UIView setAnimationDuration:1.6];
        [self OrderClipPics:[NSNumber numberWithInt:1]];
        [UIView commitAnimations];
        [self CheckPendingSong];
        [self CheckQueueHintLabel];
        return YES;
    }
    if ([[self m_clips] count] != 1) return NO;

    // the queue ran dry: pick the next song from the coverflow
    m_autoselected = YES;
    [self setM_tenmintimer:CACurrentMediaTime()];
    ClipObject *next = [m_glv getNextClipObject];
    RemoveClipViews(first);
    [[self m_clips] rfx_removeObjectAtIndex:0];
    if (next == nil) {
        [self setM_rotateclip:NO];
        m_cliptorotate = nil;
    } else {
        [[self m_clips] rfx_insertObject:next atIndex:0];
        [next release];
        [next setM_imgv:[[UIImageView alloc] initWithFrame:[self GetFrameForDragPic:0]]];
        [[next m_imgv] setImage:[m_glv CreateCDPicture:next roundpic:YES]];
        [self AddCDPictureToView:next];
        [[next m_imgv] release];
        [self CheckQueueHintLabel];
    }
    m_ordering = YES;
    [self setM_ignoreXdiff:YES];
    [UIView beginAnimations:@"OrderClipsAni" context:NULL];
    [UIView setAnimationDidStopSelector:(next != nil ? @selector(StartAudioPlayerRest) : @selector(OrderClipsReady))];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
    [UIView setAnimationDuration:1.6];
    [self OrderClipPics:[NSNumber numberWithInt:1]];
    [UIView commitAnimations];
    [self CheckPendingSong];
    [self CheckQueueHintLabel];
    return YES;
}

- (void)StartAudioPlayerRest {
    m_ordering = NO;
    ClipObject *clip = nil;
    if ([[self m_clips] count] != 0) clip = [[[self m_clips] rfx_objectAtIndex:0] retain];
    BOOL keepSpin = (clip != nil && m_cliptorotate == clip && [self m_rotateclip]);
    double keptAngle = m_angle;
    [self setM_shrinkdevider:NO];
    [self setM_rotateclip:NO];
    [self setM_presongInitTime:-1.0];
    [self SetDeviderPlayingPercent:0.0f];
    m_angle = keepSpin ? keptAngle : 0;
    m_cliptorotate = nil;
    int duration = 0;
    if (clip != nil) {
        m_cliptorotate = clip;
        [self setM_rotateclip:YES];
        if ([clip m_folderid] == -44 || [clip m_folderid] == -66 || mMCMixer == nil) {
            duration = [clip m_duration];
        } else {
            duration = [mMCMixer duration];
            if (duration == 0) duration = [clip m_duration];
        }
    }
    if (m_didfade && !m_restEarly) duration = (int)((float)duration - m_crossfadetime);
    m_restEarly = NO;
    int dur = (duration < 0xd) ? 0xd : duration;
    [self StartDevider:dur];
    [self StartPresongTimer:dur];
    [self StartCrossFadeTimer:dur];
    m_songcounter = m_songcounter + 1;
    [self setM_ignoreXdiff:NO];
    if ([self m_errorplayingsong]) {
        // the file could not be played: jump to the end of the song so the next one starts quickly
        [self setM_errorplayingsong:NO];
        double left = [self m_presongDuration] - (CACurrentMediaTime() - [self m_presongInitTime]);
        if ((left - 1.0) > 1.0) {
            [self setM_presongInitTime:[self m_presongInitTime] - (left - 1.0)];
            [self setM_crossfadeInitTime:[self m_crossfadeInitTime] - (left - 1.0)];
        }
    }
    [self CheckPendingSong];
    [clip release];
}

- (void)StartPresongTimer:(int)presongTimer {
    if (presongTimer < 0xb) return;
    [self setM_presongDuration:(double)(float)((double)presongTimer - 7.0)];
    [self setM_presongInitTime:CACurrentMediaTime()];
}

- (void)StartCrossFadeTimer:(int)crossFadeTimer {
    [self setM_crossfadeDuration:(double)(float)((double)crossFadeTimer - 5.0)];
    [self setM_crossfadeInitTime:CACurrentMediaTime()];
}

// 7 seconds before the end of a song the next one is put into the queue (so the next cover shows up)
- (void)PresongTimerFunction {
    [self setM_presongInitTime:-1.0];
    if ([DEL m_isstattalm]) return;
    if (m_playingjingle) return;
    if ([[self m_clips] count] != 1) return;
    m_autoselected = YES;
    ClipObject *next = [m_glv getNextClipObject];
    if (next == nil) return;
    ClipObject *copy = [[ClipObject alloc] init];
    [self CopyPropertiesFromObject:next toObject:copy];
    [copy setM_imgv:[[UIImageView alloc] initWithFrame:CGRectZero]];
    [[copy m_imgv] setImage:[m_glv CreateCDPicture:copy roundpic:YES]];
    [self AddCDPictureToView:copy];
    [[copy m_imgv] release];
    [[copy m_imgv] setAlpha:0.0f];
    [[copy m_imgv] setFrame:[self MakeSmallFrame:[self GetFrameForDragPic:1]]];
    [[self m_clips] addObject:copy];
    [copy release];
    m_ordering = YES;
    [UIView beginAnimations:@"OrderClipsAni" context:NULL];
    [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDuration:0.6];
    [[copy m_imgv] setAlpha:1.0f];
    [[copy m_imgv] setFrame:[self GetFrameForDragPic:1]];
    [UIView commitAnimations];
    [next release];
    [self CheckQueueHintLabel];
}

- (void)FadeOverProcess:(id)fadeOverProcess {
    m_fadingover = YES;
    [fadeOverProcess release];          // the copy made by DeleteCDAni: (nil is fine); it was never released before
    fadeOverProcess = nil;
    [self setM_presongInitTime:-1.0];
    [self setM_rotateclip:NO];
    m_cliptorotate = nil;
    [self setM_shrinkdevider:NO];
    [self setM_crossfadeInitTime:-1.0];
    m_crossfadetime = 2.0f;
    ClipObject *clip = nil;
    BOOL have = NO;
    if ([[self m_clips] count] != 0) {
        clip = [[[self m_clips] rfx_objectAtIndex:0] retain];
        have = (clip != nil);
    } else {
        m_autoselected = YES;
        ClipObject *next = [m_glv getNextClipObject];
        if (next != nil) {
            [next retain];
            [[self m_clips] addObject:next];
            [next release];
            [next setM_imgv:[[UIImageView alloc] initWithFrame:[self GetFrameForDragPic:0]]];
            [[next m_imgv] setAlpha:0.0f];
            [[next m_imgv] setImage:[m_glv CreateCDPicture:next roundpic:YES]];
            [self AddCDPictureToView:next];
            [[next m_imgv] release];
            m_ordering = YES;
            [UIView beginAnimations:@"OrderClipsAni" context:NULL];
            [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
            [UIView setAnimationDelegate:self];
            [UIView setAnimationDuration:0.6];
            [[next m_imgv] setAlpha:1.0f];
            [UIView commitAnimations];
            [self CheckQueueHintLabel];
            clip = next;
            have = YES;
        }
    }
    if (have) {
        ClipObject *copy = [[ClipObject alloc] init];
        [self CopyPropertiesFromObject:clip toObject:copy];
        [self performSelector:@selector(SpinWhenNoAdvertising:) withObject:copy afterDelay:0.5];
        [self StartAudioPlayer:clip withAniNext:NO witharg1:1];
    }
    m_fadingover = NO;
    [self CheckPendingSong];
    if (have) [clip release];
}

- (void)SpinWhenNoAdvertising:(ClipObject *)spinWhenNoAdvertising {
    if (m_blackview != nil) {
        [self performSelector:@selector(SpinWhenNoAdvertising:) withObject:spinWhenNoAdvertising afterDelay:0];
        return;
    }
    if (![DEL g_end]) {
        if ([DEL IsBrandingPicturePresent])
            [self performSelector:@selector(SpinToBrandingPic) withObject:nil afterDelay:0];
        [m_glv SpinAutomaticToClip:spinWhenNoAdvertising orIndex:0];
    }
    [spinWhenNoAdvertising release];
}

- (void)SpinToBrandingPic {
    if (![DEL IsBrandingPicturePresent]) return;
    if ([m_glv m_fingersonscreen] > 0) return;
    ClipObject *c = [[ClipObject alloc] init];
    [c setID:-5];
    [m_glv SpinAutomaticToClip:c orIndex:0];
    [c release];
}

- (void)CheckNextSong:(NSDictionary *)nextSong {
    if (m_loadingscreen != nil) return;
    m_crossfadetime = [[nextSong objectForKey:@"time"] floatValue];
    int how = [[nextSong objectForKey:@"how"] intValue];
    // (original: when "auto selected" and an update was unzipped / the 5 o'clock flag was set the app exited here)
    m_fadingover = YES;
    if (m_draggingrunningsong) {
        m_draggingrunningsong = NO;
        [[self m_clips] rfx_insertObject:m_draggingobj atIndex:0];
        m_draggingobj = nil;
        [self CheckQueueHintLabel];
    }
    NSUInteger count = [[self m_clips] count];
    ClipObject *next = nil;
    if (count < 2) {
        if ([[self m_clips] count] == 1 && ![DEL m_isstattalm]) {
            next = [m_glv getNextClipObject];
            if (next != nil) {
                [[self m_clips] addObject:next];
                [next release];
                [next setM_imgv:[[UIImageView alloc] initWithFrame:[self GetFrameForDragPic:1]]];
                [[next m_imgv] setImage:[m_glv CreateCDPicture:next roundpic:YES]];
                [self AddCDPictureToView:next];
                [[next m_imgv] release];
                [self CheckQueueHintLabel];
            }
        }
    } else {
        next = [[self m_clips] rfx_objectAtIndex:1];
    }
    m_playingjingle = NO;
    if (next == nil) {
        // nothing left to play: the finished song slides out of the queue
        m_cliptorotate = nil;
        m_rotateclip = NO;
        m_ordering = YES;
        ClipObject *first = [[self m_clips] rfx_objectAtIndex:0];
        if (first != nil) {
            CGRect f = [[first m_imgv] frame];
            if ([first m_imgv] != nil) [[first m_imgv] setTransform:CGAffineTransformMakeRotation(0)];
            [UIView beginAnimations:@"OrderClipsAni" context:NULL];
            [UIView setAnimationDuration:0.6];
            [UIView setAnimationDidStopSelector:@selector(RemoveOnlyFirstClip)];
            [UIView setAnimationDelegate:self];
            [[first m_imgv] setFrame:CGRectMake(f.origin.x - 200.0f, f.origin.y, f.size.width, f.size.height)];
            [UIView commitAnimations];
        }
    } else {
        [self StartAudioPlayer:next withAniNext:YES witharg1:how];
        m_fadingover = ([self m_resetfadeover] > 0);
        ClipObject *copy = [[ClipObject alloc] init];
        [self CopyPropertiesFromObject:next toObject:copy];
        [self performSelector:@selector(SpinWhenNoAdvertising:) withObject:copy afterDelay:0.5];
    }
    [self SendCDsToBackGround];
}

- (void)StopPlayers {
    if (mMCMixer == nil) return;
    [mMCMixer StopPlayingBus:0];
    [mMCMixer StopPlayingBus:1];
    [mMCMixer StopPlayingBus:3];
    [mMCMixer StopPlayingBus:4];
    [mMCMixer StopPlayingBus:2];
    [mMCMixer stopAUGraph];
}

- (void)ContinuePlayers { if (mMCMixer != nil) [mMCMixer startAUGraph]; }
- (void)PausePlayers { if (mMCMixer != nil) [mMCMixer stopAUGraph]; }

- (void)FlushGLForBackground { [m_glv FinishGL]; }

- (BOOL)IsPlayingClips {
    return (mMCMixer != nil && [mMCMixer isPlaying]) ? YES : NO;
}

- (void)SetPlayerVolume:(float)playerVolume {
    [self SetWdrPlayerVolume:playerVolume];
    BOOL reduce = [DEL g_reduce];
    BOOL mute = [DEL g_mute];
    if (mMCMixer != nil)
        [mMCMixer setOutputVolume:(mute ? 0.0f : (reduce ? playerVolume * 0.25f : playerVolume))];
}

- (void)SetWdrPlayerVolume:(float)wdrPlayerVolume {
    if (m_wdrplayer == nil) return;
    m_volumebefore = wdrPlayerVolume;
    [m_wdrplayer setVolume:wdrPlayerVolume];
}

- (float)GetPlayerVolume {
    return (mMCMixer != nil) ? [mMCMixer getOutputVolume] : 0.0f;
}

- (void)LowerVolume:(BOOL)lowerVolume {
    m_volumebefore = [self m_lastvolume];
    float start = [self m_lastvolume];
    for (int i = 10; i > 0; i--) {
        [self setM_lastvolume:[self m_lastvolume] - ((start * (lowerVolume ? 1.0f : 0.75f)) / 10.0f)];
        if ([self m_lastvolume] < 0) [self setM_lastvolume:0.0f];
        if ([self m_lastvolume] > 1.0f) [self setM_lastvolume:1.0f];
        if (mMCMixer != nil) [mMCMixer setOutputVolume:[self m_lastvolume]];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    }
}

- (void)RaiseVolume {
    [self setM_lastvolume:0.0f];
    for (int i = 10; i > 0; i--) {
        [self setM_lastvolume:[self m_lastvolume] + (m_volumebefore / 10.0f)];
        if (i == 1) [self setM_lastvolume:m_volumebefore];
        if ([self m_lastvolume] < 0) [self setM_lastvolume:0.0f];
        if ([self m_lastvolume] > 1.0f) [self setM_lastvolume:1.0f];
        if (mMCMixer != nil) [mMCMixer setOutputVolume:[self m_lastvolume]];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    }
}

- (void)SetLastVolumeKiosk {
    float v = [self m_lastvolume];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setFloat:fminf(1.0f, ((double)v < 0.001 ? 0.001f : v)) forKey:@"keykioskvolume"];
    [d synchronize];
}

- (void)ErrorPlayingSong { [self setM_errorplayingsong:YES]; }

// remote control events: 0 = play/pause, 1 = next song, -1 = previous song
- (void)OtherAudio:(int)otherAudio {
    if ([m_glv m_selectedfolderid] == -33) return;
    if (m_fadingover) return;
    if (otherAudio == -1) {
        if ([[self m_clips] count] != 0) {
            ClipObject *cur = [[self m_clips] rfx_objectAtIndex:0];
            [m_glv GetArrayLock:NO];
            int tile = 0, track = -1;
            BOOL found = NO;
            NSArray *tiles = [m_glv m_tilearray];
            for (tile = 0; (NSUInteger)tile < [tiles count] && !found; tile++) {
                ClipObject *t = [tiles objectAtIndex:tile];
                if ([t m_tracks] == nil) {
                    if ([t m_serverid] == [cur m_serverid] && [t ID] == [cur ID] && [t m_ipodid] == [cur m_ipodid]) {
                        track = -1; found = YES; break;
                    }
                } else {
                    for (NSUInteger k = 0; k < [[t m_tracks] count]; k++) {
                        ClipObject *tr = [[t m_tracks] objectAtIndex:k];
                        if ([tr m_serverid] == [cur m_serverid] && [tr ID] == [cur ID] && [tr m_ipodid] == [cur m_ipodid]) {
                            track = (int)k; found = YES; break;
                        }
                    }
                    if (found) break;
                }
            }
            ClipObject *prev = nil;
            if (found) {
                if (track == -1) { tile = tile - 1; track = -1; }
                else if (track != 0) { track = track - 1; }
                else { tile = tile - 1; track = 0; }
                if (tile <= -1) tile = (int)[[m_glv m_tilearray] count] - 1;
                ClipObject *t = [[m_glv m_tilearray] objectAtIndex:tile];
                ClipObject *item;
                if ([t m_tracks] != nil) {
                    if (track < 0 || (NSUInteger)track >= [[t m_tracks] count]) item = [[t m_tracks] lastObject];
                    else item = [[t m_tracks] objectAtIndex:track];
                } else item = t;
                if (item != nil) {
                    prev = [[ClipObject alloc] init];
                    [self CopyPropertiesFromObject:item toObject:prev];
                }
            }
            [m_glv releaseArraylock];
            if (prev != nil) {
                [[self m_clips] rfx_insertObject:prev atIndex:1];
                [prev setM_imgv:[[UIImageView alloc] initWithFrame:[self MakeSmallFrame:[self GetFrameForDragPic:1]]]];
                [[prev m_imgv] setImage:[m_glv CreateCDPicture:prev roundpic:YES]];
                [self AddCDPictureToView:prev];
                [[prev m_imgv] release];
                [prev release];
                [[prev m_imgv] setAlpha:0.0f];
                m_ordering = YES;
                [UIView beginAnimations:@"OrderClipsAni" context:NULL];
                [UIView setAnimationDidStopSelector:@selector(OrderClipsReady)];
                [UIView setAnimationDelegate:self];
                [UIView setAnimationDuration:0.4];
                [[prev m_imgv] setAlpha:1.0f];
                [self OrderClipPics:[NSNumber numberWithInt:1]];
                [UIView commitAnimations];
                [self CheckQueueHintLabel];
            }
        }
    } else if (otherAudio == 1) {
        [self PresongTimerFunction];
        m_autoselected = NO;
    } else if (otherAudio == 0) {
        if ([self m_pausebegintime] >= 0) {
            [self ContinueFunction];
            return;
        }
        [self setM_pausebegintime:CACurrentMediaTime()];
        [self PausePlayers];
        [self setM_rotateclip:NO];
        [self setM_shrinkdevider:NO];
        return;
    }
    if ([[self m_clips] count] == 0) return;
    [self setM_presongInitTime:-1.0];
    [self setM_crossfadeInitTime:-1.0];
    [self CheckNextSong:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:0], @"how",
                                      [NSNumber numberWithFloat:1.0f], @"time", nil]];
}

- (void)ContinueFunction {
    [self ContinuePlayers];
    double now = CACurrentMediaTime();
    double paused = now - [self m_pausebegintime];
    [self setM_presongInitTime:[self m_presongInitTime] + paused];
    [self setM_crossfadeInitTime:[self m_crossfadeInitTime] + paused];
    [self setM_clipStartTime:[self m_clipStartTime] + paused];
    [self setM_rotateclip:YES];
    [self setM_shrinkdevider:YES];
    [self setM_pausebegintime:-1.0];
}

- (void)ReStartIfNeeded {
    if (!m_shutdown) {
        if ([m_glv m_selectedfolderid] != -33) {
            if ([self m_pausebegintime] > 0) [self ContinueFunction];
        }
    }
    [m_glv ReInitThread];
}

- (void)TryReleaseMMCMixer {
    if (mMCMixer == nil) return;
    if ([mMCMixer isPlaying]) return;
    [mMCMixer release];
    mMCMixer = nil;
}

- (void)CardReaderOff {
    if (m_glv != nil) [m_glv SwitchCardReaderLight:NO];
}

#pragma mark - divider / rotation

- (void)StartDevider:(int)d {
    [self SetDeviderPlayingPercent:1.0f];
    m_clipDuration = (double)d;
    [self setM_clipStartTime:CACurrentMediaTime()];
    [self setM_shrinkdevider:YES];
}

- (void)DeviderTimerFunc {
    double now = CACurrentMediaTime();
    double start = [self m_clipStartTime];
    if (m_clipDuration <= 0) return;
    [self SetDeviderPlayingPercent:(float)((m_clipDuration - (now - start)) / m_clipDuration)];
    if (((now - start) - 5.0) >= m_clipDuration)
        [self setM_shrinkdevider:NO];
}

- (int)CalcXDiff:(float)pct {
    int thumb = ISIPAD ? 0x52 : 0x38;
    int v = (int)((double)(float)thumb * (1.0 - (double)pct));
    int mx = border + thumb;
    if (v > mx) v = mx;
    return v <= 0 ? 0 : v;
}

- (void)SetDeviderPlayingPercent:(float)pct {
    int xd = [self CalcXDiff:pct];
    if (m_draggingrunningsong) {
        if ([[self m_clips] count] == 0)
            xd = 0;
        else if ([[[self m_clips] rfx_objectAtIndex:0] ID] != [m_draggingobj ID])
            xd = 0;
    }
    if (m_lastCDXDiff == xd || m_ordering) return;
    m_lastCDXDiff = xd;
    [self MoveCDs];
}

- (void)SetDeviderPlayingPercentDelayed:(NSNumber *)pct {
    [self SetDeviderPlayingPercent:[pct floatValue]];
}

- (void)SetDeviderPlayingPercentMT {
    [self SetDeviderPlayingPercent:0.0f];
}

// The spinning CD is a Core Animation rotation on the layer (runs on the render server, so it stays smooth even when the
// main thread is busy and it starts the moment it is added).  This supervisor (a few times per second) makes sure that
// exactly the first clip of the queue spins while a song is playing.
- (void)RotationFrame {
    ClipObject *first = ([[self m_clips] count] > 0) ? [[self m_clips] rfx_objectAtIndex:0] : nil;
    BOOL playing = (mMCMixer != nil && [mMCMixer isPlaying]) || CACurrentMediaTime() < m_spinHold;
    UIImageView *want = (first != nil && playing) ? [first m_imgv] : nil;
    if (want != nil && [want superview] == nil) want = nil;
    if (want != m_spinView) {
        if (m_spinView != nil) {
            [[m_spinView layer] removeAnimationForKey:@"rfxspin"];
            [m_spinView release];
            m_spinView = nil;
        }
        if (want != nil) m_spinView = [want retain];
    }
    if (m_spinView != nil && [[m_spinView layer] animationForKey:@"rfxspin"] == nil) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        [a setFromValue:[NSNumber numberWithFloat:0.0f]];
        [a setToValue:[NSNumber numberWithFloat:(float)(2.0 * M_PI)]];
        [a setDuration:9.0];                       // 40 degrees per second, as before
        [a setRepeatCount:HUGE_VALF];
        [a setRemovedOnCompletion:NO];
        [a setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
        [[m_spinView layer] addAnimation:a forKey:@"rfxspin"];
    }
}

- (void)RotationTimerFunction { [self RotationFrame]; }

- (void)LogoAni:(NSNumber *)logoAni {
    if ([(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] m_isstattalm]) return;
    int v = [logoAni intValue];
    [UIView beginAnimations:@"tobitlogoani" context:NULL];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.3];
    [m_tslogo setAlpha:v > 0 ? 1.0f : 0.0f];
    [UIView commitAnimations];
}

- (void)Restart30secsearchTimer {
    if ([self m_30secsearchInitTime] <= 0) return;
    [self setM_30secsearchInitTime:CACurrentMediaTime()];
}

- (void)ResetTACTime:(double)t {
    [m_glv setM_moveTACInitTime:t];
}

#pragma mark - kiosk shutdown

- (void)StartKioskShutdowntimer:(int)kioskShutdowntimer {
    if (m_shutdowntimer != nil) { [m_shutdowntimer invalidate]; m_shutdowntimer = nil; }
    m_shutdowntimer = [[NSTimer scheduledTimerWithTimeInterval:(double)kioskShutdowntimer
                                                         target:self
                                                       selector:@selector(ShutdownFunction:)
                                                       userInfo:nil repeats:NO] retain];
}

- (void)StopKioskShutdowntimer {
    if (m_shutdowntimer == nil) return;
    [m_shutdowntimer invalidate];
    m_shutdowntimer = nil;
}

- (void)ShutdownFunction:(id)timer {
    if (m_shutdowntimer != nil) { [m_shutdowntimer invalidate]; m_shutdowntimer = nil; }
    if (m_shutdown) return;
    m_shutdown = YES;
    [self setM_rotateclip:NO];
    [self setM_shrinkdevider:NO];
    [self setM_presongInitTime:-1.0];
    [self setM_crossfadeInitTime:-1.0];
    m_cliptorotate = nil;
    if (m_foldertimer != nil) { [m_foldertimer invalidate]; m_foldertimer = nil; }
    [self SetLastVolumeKiosk];
    [self StopPlayers];
    // original then showed the shutdown (TP) animation; dropped, see DEVIATIONS.md
}

- (void)EndFunction {
    gv_kioskflag = 1;
    cancelcopy = YES;
    [m_glv setM_drawempty:YES];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [m_glv ReInitThread];
    [NSThread sleepForTimeInterval:0.2];
    [self SetLastVolumeKiosk];
    [self StopPlayers];
    if (m_foldertimer != nil) { [m_foldertimer invalidate]; m_foldertimer = nil; }
    [self setM_rotateclip:NO];
    [self setM_shrinkdevider:NO];
    [self setM_presongInitTime:-1.0];
    [self setM_crossfadeInitTime:-1.0];
    [m_glv StopIdleTimer];
    [m_glv StopAdvertTimer];
    [m_glv GLVEndFunction];
    m_cliptorotate = nil;
    if (m_clips != nil) { [m_clips release]; m_clips = nil; }
}

#pragma mark - timer thread

- (void)TimerThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSThread setThreadPriority:0.8];
    KeyboardView *kb = [m_glv GetKBView];
    int iter = 0;
    double lastCheck = CACurrentMediaTime();
    RadioAppDelegate *dg = (RadioAppDelegate *)[[UIApplication sharedApplication] delegate];
    while (!gv_kioskflag) {
        if (++iter % 250 == 0) {
            [pool release];
            pool = [[NSAutoreleasePool alloc] init];
        }
        BOOL bg = [dg m_isinbackground];
        if ([self m_shrinkdevider] && !bg)
            [self performSelectorOnMainThread:@selector(DeviderTimerFunc) withObject:nil waitUntilDone:NO];

        if ([self m_presongInitTime] > 0 && [self m_pausebegintime] < 0) {
            if (CACurrentMediaTime() - [self m_presongInitTime] > [self m_presongDuration]) {
                [self setM_presongInitTime:-1.0];
                [self performSelectorOnMainThread:@selector(PresongTimerFunction) withObject:nil waitUntilDone:NO];
            }
        }
        if ([self m_crossfadeInitTime] > 0 && [self m_pausebegintime] < 0) {
            if (CACurrentMediaTime() - [self m_crossfadeInitTime] > [self m_crossfadeDuration]) {
                [self setM_crossfadeInitTime:-1.0];
                [self performSelectorOnMainThread:@selector(CheckNextSong:)
                    withObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithInt:1], @"how",
                                [NSNumber numberWithFloat:5.0f], @"time", nil]
                    waitUntilDone:NO];
            }
        }
        if ([m_glv m_idleinittime] > 0) {
            if (CACurrentMediaTime() - [m_glv m_idleinittime] > 65.0) {
                [m_glv setM_idleinittime:-1.0];
                [m_glv performSelectorOnMainThread:@selector(IdleTimerFunc) withObject:nil waitUntilDone:NO];
            }
        }
        if ([self m_limitinittime] > 0) {
            if (CACurrentMediaTime() - [self m_limitinittime] > [self m_limitduration]) {
                [self setM_limitinittime:-1.0];
                [self performSelectorOnMainThread:@selector(CheckLimitations) withObject:nil waitUntilDone:NO];
            }
        }
        if ([self m_30secsearchInitTime] > 0) {
            if (CACurrentMediaTime() - [self m_30secsearchInitTime] > 30.0) {
                [self setM_30secsearchInitTime:-1.0];
                [m_glv performSelectorOnMainThread:@selector(ForwardDelete30secSearchText) withObject:nil waitUntilDone:NO];
            }
        }
        if ([self m_resetfadeover] > 0 && CACurrentMediaTime() > [self m_resetfadeover]) {
            [self setM_resetfadeover:-1.0];
            m_fadingover = NO;
        }
        if ([kb m_keyboardinittime] > 0) {
            double to = ([kb m_showwhat] == 0) ? 10.0 : 30.0;
            if (CACurrentMediaTime() - [kb m_keyboardinittime] > to) {
                [kb setM_keyboardinittime:-1.0];
                [kb performSelectorOnMainThread:@selector(KBTimerFunc) withObject:nil waitUntilDone:NO];
            }
        }
        if (CACurrentMediaTime() - lastCheck > 1.0) {
            // main thread only: it reads the queue and the dragged clip, which the UI deletes at any time
            [self performSelectorOnMainThread:@selector(CheckRunningSongLeftTime) withObject:nil waitUntilDone:NO];
            lastCheck = CACurrentMediaTime();
        }
        [NSThread sleepForTimeInterval:bg ? 0.3 : 0.05];
    }
    [pool release];
}


// ---- recovered later (used by MTObject / MTScroller) ----

// nil and @"" are considered equal; otherwise plain string equality.
- (BOOL)spotifyIDsMatch:(NSString *)a withsecondid:(NSString *)b {
    if (a == nil && b == nil) return YES;
    if (b == nil)  return [a length] == 0;
    if (a == nil)  return [b length] == 0;
    return [b isEqualToString:a];
}

- (BOOL)selectedSpotifyIDMatches:(NSString *)other {
    return [self spotifyIDsMatch:[m_glv m_selectedspotifyfolderid] withsecondid:other];
}

// Grey-scale version of a tile picture (used for folders that are not the selected one):
// draw the picture, then multiply the "sw-mask" picture with luminosity blending.
- (UIImage *)BlackAndWhitePicture:(UIImage *)pic withfolderid:(long long)folderid {
    RadioAppDelegate *ad = (RadioAppDelegate *)[[UIApplication sharedApplication] delegate];
    float s = [ad m_isipad] ? 190.0f : 120.0f;
    CGContextRef c1 = [ad BeginImageContext:CGSizeMake(s, s)];
    if ([pic CGImage]) CGContextDrawImage(c1, CGRectMake(0, 0, s, s), [pic CGImage]);   // nil guard (deviation)
    UIImage *colored = [ad EndImageContext:c1];

    CGContextRef c2 = [ad BeginImageContext:CGSizeMake(s, s)];
    UIImage *mask = [UIImage imageNamed:((folderid | 2) == 3) ? @"sw-mask-rss.png" : @"sw-mask.png"];
    if ([mask CGImage]) CGContextDrawImage(c2, CGRectMake(0, 0, s, s), [mask CGImage]);
    CGContextSetBlendMode(c2, kCGBlendModeLuminosity);
    CGContextDrawImage(c2, CGRectMake(0, 0, s, s), [colored CGImage]);
    return [[ad EndImageContext:c2] retain];
}


// "*" marks folders of a foreign server; the "Musik" (-44) folder never gets one.
- (NSString *)BuildMTFoldername:(FolderObject *)folder {
    NSString *prefix;
    if ([folder folderid] == -44)                         prefix = @"";
    else if ([folder serverid] == [m_sve serverid])       prefix = @"";
    else                                                   prefix = @"*";
    return [NSString stringWithFormat:@"%@%@", prefix, [folder foldername]];
}

// iPhone only (re-fits the GL view to the radio layout); the iPad build returns at once.
- (void)FitGLViewForiPhone:(BOOL)radio {
    if ([(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] m_isipad]) return;
    // iPhone layout switch is not part of this iPad-only build.
}


// Parses the leading id of a folder/file name: "<id>-name" (or "<id>.xxx" for iPod strings).
- (long long)GetIDFromNSString:(NSString *)str withisipodstring:(BOOL)isipod {
    long long v = -1;
    const char *c = [DEL ConvertNSString:str withorder:0];
    int n = 0;
    if (c != NULL) n = sscanf(c, isipod ? "%lld." : "%lld-", &v);
    return (n != 1) ? -1 : v;
}


#pragma mark - remote control / online leftovers (inert offline)

- (id)GetRCConDeviceID {
    return (m_rcon == nil) ? nil : [m_rcon m_serverdeviceid];
}

// Lazily created (the original builds it in its setup code).
- (NSMutableDictionary *)m_nowdict {
    if (m_nowdict == nil) m_nowdict = [[NSMutableDictionary alloc] init];
    return m_nowdict;
}

// Looked a cover up at the "songdetails" web service; the service is gone.
- (UIImage *)GetSongPictureFor:(NSString *)title withinterpret:(NSString *)interpret {
    return nil;
}

// The original queued an RCQueueObject for the remote-control thread; without a connection
// (m_rcon == nil) it did nothing, which is the only case left.
- (void)InsertIntoRemoteQueue:(int)type withpoint:(CGPoint)point witharg1:(long long)arg1 witharg2:(int)arg2
                     witharg3:(int)arg3 withleaveoutclient:(long)leaveoutclient witharg4:(int)arg4 {
    if (m_rcon == nil) return;
}

// The animated help page (web/video help) is not part of the offline build.
- (void)StartHelpPictureAni { }

#pragma mark - help overlay (light bulb)

static NSArray *TutorialPages(void) {
    return [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"titel-finden", @"Titel auswählen", nil],
        [NSArray arrayWithObjects:@"reihenfolge-aendern", @"Reihenfolge ändern", nil],
        [NSArray arrayWithObjects:@"titel-abwaehlen", @"Titel aus der Queue entfernen", nil],
        [NSArray arrayWithObjects:@"titel-abbrechen", @"Titel abbrechen", nil],
        [NSArray arrayWithObjects:@"titel-loeschen", @"Titel entfernen", nil],
        [NSArray arrayWithObjects:@"lautstaerke-aendern", @"Lautstärke ändern", nil],
        [NSArray arrayWithObjects:@"kollektionen-anzeigen", @"Kollektion auswählen", nil],
        nil];
}

- (void)ShowTutorial {
    if ([self viewWithTag:7731] != nil) return;
    m_tutorialpage = 0;
    CGRect b = [self bounds];
    UIView *ov = [[UIView alloc] initWithFrame:b];
    [ov setTag:7731];
    [ov setBackgroundColor:[UIColor colorWithWhite:0.0f alpha:0.92f]];
    [ov setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake((b.size.width - 508.0f) * 0.5f, (b.size.height - 454.0f) * 0.5f - 30.0f, 508.0f, 454.0f)];
    [iv setTag:7732];
    [iv setContentMode:UIViewContentModeScaleAspectFit];
    [iv setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
    [ov addSubview:iv];
    [iv release];
    UILabel *cap = [[UILabel alloc] initWithFrame:CGRectMake(40.0f, (b.size.height + 454.0f) * 0.5f - 10.0f, b.size.width - 80.0f, 60.0f)];
    [cap setTag:7733];
    [cap setBackgroundColor:[UIColor clearColor]];
    [cap setTextColor:[UIColor whiteColor]];
    [cap setFont:[UIFont systemFontOfSize:22.0f]];
    [cap setTextAlignment:NSTextAlignmentCenter];
    [cap setNumberOfLines:2];
    [cap setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
    [ov addSubview:cap];
    [cap release];
    UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
    [x setFrame:CGRectMake(b.size.width - 70.0f, 20.0f, 50.0f, 50.0f)];
    [x setTitle:@"✕" forState:UIControlStateNormal];
    [x setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [[x titleLabel] setFont:[UIFont systemFontOfSize:26.0f]];
    [x setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin];
    [x addTarget:self action:@selector(CloseTutorial) forControlEvents:UIControlEventTouchUpInside];
    [ov addSubview:x];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(TutorialTap:)];
    [ov addGestureRecognizer:tap];
    [tap release];
    [ov setAlpha:0.0f];
    [self addSubview:ov];
    [ov release];
    [self ShowTutorialPage];
    [UIView animateWithDuration:0.25 animations:^{ [ov setAlpha:1.0f]; }];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(CloseTutorial) object:nil];
    [self performSelector:@selector(CloseTutorial) withObject:nil afterDelay:30.0];
}

- (void)ShowTutorialPage {
    UIView *ov = [self viewWithTag:7731];
    if (ov == nil) return;
    NSArray *pages = TutorialPages();
    if (m_tutorialpage >= (int)[pages count]) { [self CloseTutorial]; return; }
    NSArray *p = [pages objectAtIndex:m_tutorialpage];
    NSString *path = [[NSBundle mainBundle] pathForResource:[p objectAtIndex:0] ofType:@"png"];
    UIImage *img = path ? [UIImage imageWithContentsOfFile:path] : nil;
    [(UIImageView *)[ov viewWithTag:7732] setImage:img];
    [(UILabel *)[ov viewWithTag:7733] setText:[p objectAtIndex:1]];
}

- (void)TutorialTap:(UITapGestureRecognizer *)g {
    m_tutorialpage++;
    [self ShowTutorialPage];
}

- (void)CloseTutorial {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(CloseTutorial) object:nil];
    UIView *ov = [self viewWithTag:7731];
    if (ov == nil) return;
    [ov setTag:0];
    [UIView animateWithDuration:0.25 animations:^{ [ov setAlpha:0.0f]; } completion:^(BOOL f){ [ov removeFromSuperview]; }];
}




// Started the promo-video ("TP") tile animation of the overview; the video tile is not built offline.
- (void)StartTPAni:(id)arg { }
@end
