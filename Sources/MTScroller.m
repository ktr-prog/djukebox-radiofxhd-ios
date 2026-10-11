// MTScroller.m -- recovered from -[MTScroller ...] (armv7), Radiofx HD.
// Constants (timer intervals, image slices, red-dot geometry, scroll offsets) were read from
// the instruction stream. Dead-backend branches (live radio tile -33, promo video tile -55)
// are kept as in the binary but never trigger in the offline build.
#import "MTScroller.h"
#import "MTObject.h"
#import "ScrollerDictObject.h"
#import "KioskView.h"
#import "GLView.h"
#import "RadioAppDelegate.h"
#import "DBOperations.h"
#import "ClipObject.h"
#import "FolderObject.h"
#import "Globals.h"

#define APPDEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@implementation MyGestureDelegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t { return YES; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o { return YES; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return YES; }
@end

@implementation MTScroller
@synthesize m_isscrolling, m_deletedoverviewcausememwarning, m_willplayradio, m_lastactiveradiochannel, m_isclosing;

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (m_mtobjects != nil)      { [m_mtobjects release];      m_mtobjects = nil; }
    if (m_deleg != nil)          { [m_deleg release];          m_deleg = nil; }
    if (m_placeholderpic != nil) { [m_placeholderpic release]; m_placeholderpic = nil; }
    if (m_midpart != nil)        { [m_midpart release];        m_midpart = nil; }
    if (m_leftpart != nil)       { [m_leftpart release];       m_leftpart = nil; }
    if (m_rightpart != nil)      { [m_rightpart release];      m_rightpart = nil; }
    if (m_midpart_s != nil)      { [m_midpart_s release];      m_midpart_s = nil; }
    if (m_leftpart_s != nil)     { [m_leftpart_s release];     m_leftpart_s = nil; }
    if (m_rightpart_s != nil)    { [m_rightpart_s release];    m_rightpart_s = nil; }
    [super dealloc];
}

#pragma mark - setup

// Cuts a 56x60 red-dot picture into left (27px) / middle (1px) / right (27px) parts so the
// badge can be stretched to the width of the number.
- (void)sliceDot:(UIImage *)src left:(UIImage **)l mid:(UIImage **)m right:(UIImage **)r {
    CGImageRef a = CGImageCreateWithImageInRect([src CGImage], CGRectMake(0.0f, 0.0f, 27.0f, 60.0f));
    *l = [[UIImage imageWithCGImage:a] retain];
    CGImageRelease(a);
    CGImageRef b = CGImageCreateWithImageInRect([src CGImage], CGRectMake(27.0f, 0.0f, 1.0f, 60.0f));
    *m = [[UIImage imageWithCGImage:b] retain];
    CGImageRelease(b);
    CGImageRef c = CGImageCreateWithImageInRect([src CGImage], CGRectMake(28.0f, 0.0f, 27.0f, 60.0f));
    *r = [[UIImage imageWithCGImage:c] retain];
    CGImageRelease(c);
}

- (void)SetKioskVPointer:(id)kioskVPointer {
    m_pkiosk = kioskVPointer;
    m_deletedoverviewcausememwarning = NO;
    m_lastactiveradiochannel = -1;
    m_tapGestureRecognizer = nil;
    m_overviewtimer = nil;
    m_isscrolling = NO;
    m_placeholderpic = [[[m_pkiosk m_glv] CreateNakedImage:[UIImage imageNamed:@"cover-note.png"]
                                                 withNumber:0 withClipArray:nil withclipObject:nil
                                            withtexturesize:kThumbSize onlychannellogo:NO
                                       borderalreadypresent:NO] retain];
    m_deleg = [[MyGestureDelegate alloc] init];
    m_mtobjects = [[NSMutableArray alloc] init];
    [self setBackgroundColor:[UIColor clearColor]];
    m_reddotsize = [APPDEL m_isipad] ? 0x26 : 0x1e;

    // NOTE: the "-new" pictures were never part of the shipped bundle (only roter-kreis-fp.png is,
    // same 56x60 layout); fall back to it so the badge is drawn.  See DEVIATIONS.md.
    UIImage *red = [APPDEL NonCachedImage:@"roter-kreis-fp-new"];
    if (red == nil) red = [APPDEL NonCachedImage:@"roter-kreis-fp"];
    [self sliceDot:red left:&m_leftpart mid:&m_midpart right:&m_rightpart];
    UIImage *spo = [APPDEL NonCachedImage:@"spoti-kreis-fp-new"];
    if (spo == nil) spo = red;
    [self sliceDot:spo left:&m_leftpart_s mid:&m_midpart_s right:&m_rightpart_s];

    [self ReInit];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(MTDeleted:) name:@"MsgMtDeleted" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(SomeFolderRenamed) name:@"MsgOVFolderrenamed" object:nil];
}

- (void)ReInit {
    m_volumepinch = -1.0f;
    m_isinitialized = NO;
    m_isclosing = NO;
    [self setContentOffset:CGPointZero];
}

#pragma mark - tap / navigation

- (void)handleTap:(id)handleTap {
    if (!m_picreplaced) return;
    if (m_tapGestureRecognizer != handleTap) return;
    if ([self m_isscrolling]) return;
    if (m_overviewtimer != nil) { [m_overviewtimer invalidate]; m_overviewtimer = nil; }
    if (m_isclosing) return;
    CGPoint p = [handleTap locationInView:self];
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        CGRect r = [[m_mtobjects objectAtIndex:i] GetPicFrame];
        if (CGRectContainsPoint(r, p)) {
            [self GotoFolder:(int)i];
            break;
        }
    }
}

- (void)setAlpha2 {
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        if ((int)i != [[m_pkiosk m_glv] m_newselectedfolderindex]) {
            [o SetAlpha:0.0f];
        } else {
            [o PlacePicInMid:(int)[self contentOffset].y withview:self];
            [o SetAlphaMainImg:1.0f];
            [o SetAlphaBorderAndRedDot:0.0f];
            [o SetAlphaText:0.0f];
        }
    }
}

- (void)setAlpha1 {
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        [o SetAlpha:1.0f];
        [o SetFrame:(int)i];
    }
}

- (void)setAlpha0 {
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++)
        [[m_mtobjects objectAtIndex:i] SetAlpha:0.0f];
}

- (MTObject *)GetMTObject:(int)idx {
    if ((NSUInteger)idx >= [m_mtobjects count]) return nil;
    return [m_mtobjects objectAtIndex:idx];
}

- (void)GotoFolderID:(int)folderID {
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        if ([[m_mtobjects objectAtIndex:i] m_id] == (long long)folderID) {
            [self GotoFolder:(int)i];
            return;
        }
    }
}

// A tile was chosen (or -1: close without choosing).
- (void)GotoFolder:(int)gotoFolder {
    if (m_isclosing) return;
    m_isclosing = YES;
    [self setScrollEnabled:NO];

    BOOL kbCleanup = NO;
    if (gotoFolder == 0) {
        if ([m_mtobjects count] != 0 && [[m_mtobjects objectAtIndex:0] m_id] == -33) {
            [self ExchangeChannelLogo:[NSNumber numberWithInt:0]];
            kbCleanup = YES;
        } else {
            kbCleanup = ((NSUInteger)gotoFolder >= [m_mtobjects count]) ||
                        ([[[m_mtobjects objectAtIndex:gotoFolder] GetRedDotImageView] image] == nil);
        }
    } else if (gotoFolder >= 0) {
        kbCleanup = ((NSUInteger)gotoFolder >= [m_mtobjects count]) ||
                    ([[[m_mtobjects objectAtIndex:gotoFolder] GetRedDotImageView] image] == nil);
    }
    if (kbCleanup) {
        [[m_pkiosk m_glv] performSelector:@selector(RemoveKeyBoardDelayed) withObject:nil afterDelay:0.001];
        [[m_pkiosk m_glv] ForwardEmptySearchfield];
    }

    if (gotoFolder == -1) {
        [[m_pkiosk m_glv] setM_newselectedfolderindex:-1];
        [[m_pkiosk m_glv] PinchAniBack];
        return;
    }
    if ([m_mtobjects count] == 0) return;

    MTObject *o = [m_mtobjects objectAtIndex:gotoFolder];
    if ([o m_id] == -55) {                 // "Rfx commercial" tile (promo video) -- dead feature
        [self StopOverviewTimer];
        NSString *mp4 = [[NSBundle mainBundle] pathForResource:@"rfx promo iPod GER" ofType:@"mp4"];
        if ([m_pkiosk respondsToSelector:@selector(StartTPAni:)]) {
            NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:mp4, @"keyfilmdictvideothek",
                               [NSNumber numberWithInt:1], @"keyfilmdictcommercial", nil];
            [m_pkiosk performSelector:@selector(StartTPAni:) withObject:d afterDelay:0.01];
        }
        return;
    }

    GLView *glv = [m_pkiosk m_glv];
    [glv setM_pinchstatus:3];
    [glv setM_newselectedfolderindex:gotoFolder];
    long long oldFolder = [[m_pkiosk m_glv] m_selectedfolderid];
    long long newFolder = [o m_id];
    int  oldServer = [[m_pkiosk m_glv] m_selectedserverid];
    int  newServer = [o m_sid];
    long long oldIpod = [[m_pkiosk m_glv] m_selectedipodid];
    long long newIpod = [o m_ipodid];
    NSString *oldSpot = [NSString stringWithFormat:@"%@",
                         [[m_pkiosk m_glv] m_selectedspotifyfolderid] ? [[m_pkiosk m_glv] m_selectedspotifyfolderid] : @""];
    NSString *newSpot = [NSString stringWithFormat:@"%@",
                         [o m_spotifyfolderid] ? [o m_spotifyfolderid] : @""];

    BOOL same = (newServer == oldServer) && (oldFolder == newFolder) && (oldIpod == newIpod)
                && [oldSpot isEqualToString:newSpot];
    if (same) {
        [[m_pkiosk m_glv] BeginSearch:[[m_pkiosk m_glv] GetSearchText]];
        [[m_pkiosk m_glv] PinchAniBack];
        if (newFolder == -33) goto radioFade;
        [m_pkiosk FadeQueueToBlack:NO];
        return;
    }
    if (newFolder != -33) {
        [m_pkiosk RemoveDirectChannelKey];
        [m_pkiosk FitGLViewForiPhone:NO];
        m_willplayradio = NO;
        (void)[APPDEL m_isstattalm];
        [[m_pkiosk m_glv] PinchAniBack];
        [m_pkiosk FadeQueueToBlack:NO];
        return;
    }
    // live radio tile (-33): unreachable in the offline build
    m_willplayradio = YES;
    [APPDEL setM_animatechannelchange:NO];
    [m_pkiosk FitGLViewForiPhone:YES];
    {
        int num = [APPDEL GetNumForChannelID:m_lastactiveradiochannel];
        if (num < 0) num = 0;
        if ([APPDEL GetStreamer] == nil || ![APPDEL GetStreamerPlaying])
            [m_pkiosk performSelector:@selector(StartDirectChannel2:) withObject:[NSNumber numberWithInt:num] afterDelay:1.1];
        [[m_pkiosk m_glv] PinchAniBack];
    }
radioFade:
    if (oldFolder == -33) {
        if ((double)[m_pkiosk GetBlackOverlayAlpha] < 0.1)
            [m_pkiosk FadeQueueToBlack:YES];
    }
}

- (void)ResetOverviewAfterRfxCommercial {
    m_isclosing = NO;
    [self setScrollEnabled:YES];
    [self RestartOverviewTimer];
}

- (int)GetIndexForID:(long long)folderid withserverid:(int)serverid withipodid:(long long)ipodid {
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        if ([o m_id] != folderid) continue;
        if ([o m_sid] != serverid) continue;
        if ([o m_ipodid] != ipodid) continue;
        if ([m_pkiosk selectedSpotifyIDMatches:[o m_spotifyfolderid]]) return (int)i;
    }
    return -1;
}

#pragma mark - (re)building the grid

- (void)ReSetup {
    if (m_isclosing) return;
    [self performSelectorOnMainThread:@selector(SetUpScroller:)
                           withObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                       [NSNumber numberWithInt:1], @"nsnum",
                                       [NSNumber numberWithInt:0], @"nsfirst",
                                       [NSNumber numberWithInt:0], @"nsaddfolder", nil]
                        waitUntilDone:YES];
}

// nsnum: scroll to the selected folder; nsfirst: first build (no cached pictures);
// nsaddfolder: called because a folder appeared.
- (void)SetUpScroller:(id)upScroller {
    m_picreplaced = NO;
    int nsnum       = [[upScroller valueForKey:@"nsnum"] intValue];
    int nsfirst     = [[upScroller valueForKey:@"nsfirst"] intValue];
    int nsaddfolder = [[upScroller valueForKey:@"nsaddfolder"] intValue];

    long long actSong  = [[m_pkiosk m_glv] GetActSongID];
    long long actIpod  = [[m_pkiosk m_glv] GetActIpodID];
    id        actSpot  = [[m_pkiosk m_glv] GetActSpotifyID];
    CGSize ipadSize = [APPDEL GetiPadSize];

    [[m_pkiosk m_glv] LockMTOverview];
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        [o setM_deleteflag:([o m_id] != -55)];       // everything but the promo tile is "stale" until seen again
    }
    [[m_pkiosk m_glv] UnlockMTOverview];

    [APPDEL LockDB:0];
    DBOperations *dbo = [[DBOperations alloc] init];
    NSMutableArray *folders = [dbo GetFolders:[m_pkiosk m_sve] onlyexclude:NO checkempty:YES
                                   withLimits:YES withremotefolders:YES join:YES];
    [APPDEL UnlockDB];

    BOOL changed = NO;
    NSUInteger fi;
    for (fi = 0; fi < [folders count]; fi++) {
        FolderObject *folder = [folders objectAtIndex:fi];
        [[m_pkiosk m_glv] LockMTOverview];
        MTObject *existing = [self IsFolderInObjects:folder];
        [[m_pkiosk m_glv] UnlockMTOverview];
        if (existing != nil) { [existing setM_deleteflag:NO]; continue; }

        ScrollerDictObject *sdo = nil;
        BOOL owned = NO;
        if (nsfirst == 0) {
            sdo = [[m_pkiosk m_glv] GetSDC:[APPDEL CreatePrescrollerKey:[folder folderid]
                                                          withserverid:[folder serverid]
                                                            withipodid:[folder ipodid]
                                                         withspotifyid:[folder spotifyfolderid]]];
            if (sdo == nil && [[m_pkiosk m_glv] Getprescrollerthreaddone]) {
                // no cached picture yet: build one right now from the first song of the folder
                [APPDEL LockDB:0];
                NSMutableArray *songs = [dbo GetSongsForFolder:folder withjoin:YES];
                [APPDEL UnlockDB];
                if ([songs count] != 0) {
                    ClipObject *song = [songs objectAtIndex:0];
                    sdo = [[ScrollerDictObject alloc] init];
                    owned = YES;
                    FolderObject *songFolder;
                    BOOL songFolderOwned = NO;
                    if ([song m_folderid] == [folder folderid]) {
                        songFolder = folder;
                    } else {
                        [APPDEL LockDB:0];
                        songFolder = [dbo GetFolderForID:[song m_folderid] withserverid:[song m_serverid]
                                              withipodid:[song m_ipodid] withspotifyid:[song m_spotifyfolderid]];
                        [APPDEL UnlockDB];
                        songFolderOwned = YES;
                    }
                    UIImage *naked = nil;
                    long long sf = [song m_folderid];
                    if (sf == 1 || sf == 3 || sf == -33) {
                        if ([song ID] != -1)
                            naked = [[m_pkiosk m_glv] CreateNakedImage:nil withNumber:0 withClipArray:nil
                                                        withclipObject:song withtexturesize:kThumbSize
                                                       onlychannellogo:YES borderalreadypresent:NO];
                    } else {
                        NSString *serverdir = [NSString stringWithFormat:@"%@%@/",
                                               [APPDEL CreateServerDir:[m_pkiosk m_sve] withfolderobject:songFolder],
                                               [APPDEL Buildfoldername:songFolder]];
                        NSFileManager *fm = [NSFileManager defaultManager];
                        [APPDEL BuildAndCheckFilePathes:song withfm:fm withserverdir:serverdir withCheck:1];
                        if ([song ID] != -1) {
                            UIImage *pic = [m_pkiosk GetSongImage:[song m_picturepath] withclipobject:song];
                            naked = [[m_pkiosk m_glv] CreateNakedImage:pic withNumber:0 withClipArray:nil
                                                        withclipObject:nil withtexturesize:kThumbSize
                                                       onlychannellogo:NO borderalreadypresent:NO];
                        }
                    }
                    UIImage *bw = [m_pkiosk BlackAndWhitePicture:naked withfolderid:[songFolder folderid]];
                    if (songFolderOwned) [songFolder release];
                    [sdo SetPic:bw];
                    [sdo setM_iscolorpic:NO];
                    [sdo setMidindex:0];
                    [sdo setMidid:[song ID]];
                    [sdo setMidipodid:[song m_ipodid]];
                    NSString *spot = nil;
                    if ([song m_spotifyid] != nil) spot = [NSString stringWithFormat:@"%@", [song m_spotifyid]];
                    [sdo setMidspotifyid:spot];
                    [sdo setNumsongs:1];
                    [sdo setSeconds:[song m_duration]];
                }
                [songs release];
            }
        }

        MTObject *mto = [[MTObject alloc] init];
        [mto setM_id:[folder folderid]];
        [mto setM_sid:[folder serverid]];
        [mto setM_ipodid:[folder ipodid]];
        if ([folder spotifyfolderid] != nil)
            [mto setM_spotifyfolderid:[NSString stringWithFormat:@"%@", [folder spotifyfolderid]]];
        [mto setM_reddotsize:m_reddotsize];
        [mto setM_deleteflag:NO];
        [mto SetPlaceholderpicpointer:m_placeholderpic];
        [mto SetScrollerPointer:self];
        [mto SetKioskPointer:m_pkiosk];
        [mto SetFoldername:[m_pkiosk BuildMTFoldername:folder]];
        [mto SetUp:self withSDO:sdo];
        [[m_pkiosk m_glv] LockMTOverview];
        [m_mtobjects addObject:mto];
        [[m_pkiosk m_glv] UnlockMTOverview];
        [mto release];
        if (owned) [sdo release];
        changed = YES;
    }
    [dbo release];
    if (folders != nil) [folders release];

    [[m_pkiosk m_glv] LockMTOverview];
    for (NSInteger i = (NSInteger)[m_mtobjects count] - 1; i > -1; i--) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        if ([o m_deleteflag]) {
            [o RemovePics];
            [m_mtobjects removeObjectAtIndex:i];
            changed = YES;
        }
    }
    if (changed || nsfirst == 1) [self FitScroller];

    if (nsfirst == 0) {
        MTObject *sel = nil;
        int idx = [self GetIndexForID:[[m_pkiosk m_glv] GetSelectedFolderid]
                         withserverid:[[m_pkiosk m_glv] GetSelectedServerid]
                           withipodid:[[m_pkiosk m_glv] GetSelectedIpodid]];
        if (idx != -1) {
            sel = [m_mtobjects objectAtIndex:idx];
            [sel SetAlphaMainImg:1.0f];
            float a = nsaddfolder ? 1.0f : 0.0f;
            [sel SetAlphaBorderAndRedDot:a];
            [sel SetAlphaText:a];
            [sel SetLastID:actSong withipodid:actIpod withFlag:NO withspotifyid:actSpot];
        }
        for (NSUInteger i = 0; i < [m_mtobjects count]; i++)
            [[m_mtobjects objectAtIndex:i] CheckBlackAndWhite];

        if (nsnum >= 1 && idx != -1) {
            CGRect r = [sel GetFrameForOverViewFolder:idx withsize:ipadSize];
            BOOL ipad = [APPDEL m_isipad];
            CGSize cs = [self contentSize];
            CGRect fr = [self frame];
            int off = (int)(r.origin.y - (ipad ? 260.0f : 70.0f));
            if (off < 0) off = 0;
            int result;
            if (cs.height < fr.size.height) {
                result = 0;
            } else {
                int maxoff = (int)([self contentSize].height - [self frame].size.height);
                result = (off > maxoff) ? maxoff : off;
            }
            [self setContentOffset:CGPointMake(0.0f, (float)result) animated:NO];
            [sel PlacePicInMid:result withview:self];
        }
    }
    [[m_pkiosk m_glv] UnlockMTOverview];

    if (m_tapGestureRecognizer == nil) {
        m_tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [m_tapGestureRecognizer setDelegate:m_deleg];
        [self addGestureRecognizer:m_tapGestureRecognizer];
        [m_tapGestureRecognizer release];
    }
    m_lpGestureRecognizer = nil;
    m_isinitialized = YES;
    if ((nsaddfolder | nsfirst) == 0) [self RestartOverviewTimer];
    if (nsaddfolder != 0) {
        m_picreplaced = YES;
        [[m_pkiosk m_glv] BeginSearchInMTScroller:[[m_pkiosk m_glv] GetSearchText]];
    }
}

- (void)SetFrames {
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++)
        [[m_mtobjects objectAtIndex:i] SetFrame:(int)i];
}

- (MTObject *)IsFolderInObjects:(id)folder {
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        if ([o m_id] != [folder folderid]) continue;
        if ([folder serverid] != [o m_sid]) continue;
        if ([o m_ipodid] != [folder ipodid]) continue;
        if ([m_pkiosk spotifyIDsMatch:[o m_spotifyfolderid] withsecondid:[folder spotifyfolderid]]) return o;
    }
    return nil;
}

#pragma mark - overview timer

- (void)StopOverviewTimer {
    if (m_overviewtimer == nil) return;
    [m_overviewtimer invalidate];
    m_overviewtimer = nil;
}

- (void)RestartOverviewTimer {
    if (m_overviewtimer != nil) { [m_overviewtimer invalidate]; m_overviewtimer = nil; }
    // 15 s normally, 20 s while a search text is entered
    NSTimeInterval t = ([[m_pkiosk m_glv] GetSearchTextLen] > 0) ? 20.0 : 15.0;
    m_overviewtimer = [NSTimer scheduledTimerWithTimeInterval:t target:self
                                                     selector:@selector(OverviewTimerFunc:)
                                                     userInfo:nil repeats:NO];
    [m_pkiosk Restart30secsearchTimer];
}

- (void)RestartOverviewTimerWithTimeout:(double)timeout {
    if (m_overviewtimer != nil) { [m_overviewtimer invalidate]; m_overviewtimer = nil; }
    m_overviewtimer = [NSTimer scheduledTimerWithTimeInterval:timeout target:self
                                                     selector:@selector(OverviewTimerFunc:)
                                                     userInfo:nil repeats:NO];
}

// Nobody tapped: close the overview again, keeping the current folder.
- (void)OverviewTimerFunc:(id)timer {
    if (m_overviewtimer != nil) { [m_overviewtimer invalidate]; m_overviewtimer = nil; }
    if ([[m_pkiosk m_glv] m_pinchstatus] != 2) return;
    NSUInteger found = 0;
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        if (![m_pkiosk selectedSpotifyIDMatches:[o m_spotifyfolderid]]) continue;
        if ([[m_pkiosk m_glv] m_selectedfolderid] != [o m_id]) continue;
        if ([o m_sid] != [[m_pkiosk m_glv] m_selectedserverid]) continue;
        if ([[m_pkiosk m_glv] m_selectedipodid] == [o m_ipodid]) { found = i; break; }
    }
    if ([m_mtobjects count] <= found) return;
    [self GotoFolder:([[m_mtobjects objectAtIndex:found] m_id] == -55 ? -1 : (int)found)];
}

#pragma mark - channel logo (live radio tile; unreachable offline)

- (void)ExchangeChannelLogo:(id)flag {
    int f = [flag intValue];
    MTObject *o = [m_mtobjects objectAtIndex:0];
    ClipObject *c = [[ClipObject alloc] init];
    [c setID:[APPDEL m_lastchannelid]];
    [c setM_folderid:-33];
    UIImage *logo = [[m_pkiosk m_glv] CreateNakedImage:nil withNumber:0 withClipArray:nil withclipObject:c
                                       withtexturesize:(f != 0 ? kThumbSize : kCoverSize)
                                       onlychannellogo:(f != 0) borderalreadypresent:NO];
    [c release];
    UIImageView *old = [o GetMainImageView];
    m_newimageview = [[UIImageView alloc] initWithImage:logo];
    [m_newimageview setAlpha:0.0f];
    [m_newimageview setFrame:[old frame]];
    [self addSubview:m_newimageview];
    [m_newimageview release];
    [self bringSubviewToFront:[o GetRedDotImageView]];
    [UIView beginAnimations:@"exchangeani_34" context:NULL];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(ExchangeAniFinished)];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.4];
    [old setAlpha:0.0f];
    [m_newimageview setAlpha:1.0f];
    [o ResizeBorderFrame:(f == 0 ? 1.0f : 0.0f) fromImgv:m_newimageview];
    [UIView commitAnimations];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
}

- (void)ExchangeAniFinished {
    [[m_mtobjects objectAtIndex:0] ReplaceMainImgwith:m_newimageview];
    m_newimageview = nil;
    m_picreplaced = YES;
}

#pragma mark - red dots (badge with the number of new songs)

- (void)SetRedDots:(id)redDots {
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        int v = 0;
        if ([redDots count] > i) {
            v = [[redDots objectAtIndex:i] intValue];
            if (v < 0) v = 0;
        }
        [self SetRedDot:v withindex:(int)i];
    }
}

- (void)SetRedDot:(int)redDot withindex:(int)indexArg {
    MTObject *o = [m_mtobjects objectAtIndex:indexArg];
    UIImageView *dotv = [o GetRedDotImageView];
    [o setM_reddotcount:redDot];
    BOOL spotify = NO;
    if ([o m_spotifyfolderid] != nil) spotify = ([[o m_spotifyfolderid] length] != 0);
    if (redDot == 0) { [dotv setImage:nil]; return; }

    BOOL ipad = [APPDEL m_isipad];
    UIFont *font = [UIFont boldSystemFontOfSize:(ipad ? 21.0f : 17.0f)];
    NSString *txt = [NSString stringWithFormat:@"%i", redDot];
    CGSize tsz = [txt sizeWithAttributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]];
    int extra = 1;
    if (redDot >= 10) extra = (int)(tsz.width + -13.0f);

    CGContextRef ctx = [APPDEL BeginImageContext:CGSizeMake((float)(extra + m_reddotsize), (float)m_reddotsize)];
    int leftw = (int)(((double)(float)m_reddotsize / 56.0) * 27.0);
    float h = (float)m_reddotsize;
    CGContextDrawImage(ctx, CGRectMake(0.0f, 0.0f, (float)leftw, h), [(spotify ? m_leftpart_s : m_leftpart) CGImage]);
    CGContextDrawImage(ctx, CGRectMake((float)leftw, 0.0f, (float)extra, h), [(spotify ? m_midpart_s : m_midpart) CGImage]);
    CGContextDrawImage(ctx, CGRectMake((float)(extra + leftw), 0.0f, (float)leftw, h), [(spotify ? m_rightpart_s : m_rightpart) CGImage]);
    CGContextSetFillColorWithColor(ctx, [[UIColor whiteColor] CGColor]);
    [APPDEL OwndrawAtPoint:ctx withtext:txt
               drawAtPoint:CGPointMake(((float)(extra + m_reddotsize) - tsz.width) * 0.5f + -1.0f, ipad ? 13.0f : 11.0f)
                  forWidth:0 withFont:font lineBreakMode:0];
    [dotv setImage:[APPDEL EndImageContext:ctx]];
    [[m_mtobjects objectAtIndex:indexArg] CalcFrameForRedDot];
}

#pragma mark - notifications from the database layer

- (void)MTDeleted:(NSNotification *)n {
    id key = [n object];
    [[m_pkiosk m_glv] LockSDC];
    [[m_pkiosk m_glv] DeleteSDC:key];
    [[m_pkiosk m_glv] UnlockSDC];
    [self performSelectorOnMainThread:@selector(SetUpScroller:)
                           withObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                       [NSNumber numberWithInt:0], @"nsnum",
                                       [NSNumber numberWithInt:0], @"nsfirst",
                                       [NSNumber numberWithInt:1], @"nsaddfolder", nil]
                        waitUntilDone:YES];
}

- (void)SomeFolderRenamed {
    DBOperations *dbo = [[DBOperations alloc] init];
    [APPDEL LockDB:0];
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        FolderObject *f = [dbo GetFolderForID:[o m_id] withserverid:[o m_sid] withipodid:[o m_ipodid]
                                 withspotifyid:[o m_spotifyfolderid]];
        if (f != nil) {
            [o SetFoldername:[m_pkiosk BuildMTFoldername:f]];
            [o Reloadlabel];
        }
        [f release];
    }
    [APPDEL UnlockDB];
    [dbo release];
}

// A song of an already known folder was added: bump the counters or, for an unknown folder, rebuild.
- (void)CheckIfFolderPresent:(id)clip {
    [[m_pkiosk m_glv] LockMTOverview];
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        if ([o m_id] != [clip m_folderid]) continue;
        if ([o m_sid] != [clip m_serverid]) continue;
        if (![m_pkiosk spotifyIDsMatch:[clip m_spotifyfolderid] withsecondid:[o m_spotifyfolderid]]) continue;
        [o setM_duration:([o m_duration] + [clip m_duration])];
        NSString *txt = [[m_pkiosk m_glv] GetSearchText];
        if (txt == nil || [txt length] == 0 || [[m_pkiosk m_glv] IsClipInSearchrange:clip withsearchtext:txt])
            [o setM_reddotcount:([o m_reddotcount] + 1)];
        [o setM_ownindex:(int)i];
        [o performSelectorOnMainThread:@selector(UpdateCounts:) withObject:[NSNumber numberWithInt:1] waitUntilDone:NO];
        [[m_pkiosk m_glv] UnlockMTOverview];
        return;
    }
    [[m_pkiosk m_glv] UnlockMTOverview];
    [self performSelectorOnMainThread:@selector(SetUpScroller:)
                           withObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                       [NSNumber numberWithInt:0], @"nsnum",
                                       [NSNumber numberWithInt:0], @"nsfirst",
                                       [NSNumber numberWithInt:1], @"nsaddfolder", nil]
                        waitUntilDone:YES];
}

- (NSMutableArray *)GetMTObjects { return m_mtobjects; }

- (void)DeleteClipObject:(id)clip {
    if (clip == nil) return;
    [[m_pkiosk m_glv] LockMTOverview];
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        if ([o m_id] == [clip m_folderid] && [o m_sid] == [clip m_serverid]) {
            [o setM_duration:([o m_duration] - [clip m_duration])];
            if ([o m_duration] < 0) [o setM_duration:0];
            [o setM_reddotcount:([o m_reddotcount] - 1)];
            if ([o m_reddotcount] < 0) [o setM_reddotcount:0];
            [o UpdateCounts:[NSNumber numberWithInt:0]];
        }
    }
    [[m_pkiosk m_glv] UnlockMTOverview];
}

- (void)deleteMTOswithSid:(int)sid {
    NSMutableArray *keys = [[NSMutableArray alloc] init];
    [[m_pkiosk m_glv] LockSDC];
    NSEnumerator *en = [[[m_pkiosk m_glv] GetPreScrollerDict] keyEnumerator];
    id k;
    while ((k = [en nextObject]) != nil) [keys addObject:k];
    for (NSUInteger i = 0; i < [keys count]; i++) {
        NSString *key = [keys objectAtIndex:i];
        NSArray *parts = [key componentsSeparatedByString:@"-"];
        if ([parts count] >= 2 && [[parts objectAtIndex:1] intValue] == sid)
            [[m_pkiosk m_glv] DeleteSDC:key];
    }
    [[m_pkiosk m_glv] UnlockSDC];
    [keys release];

    [[m_pkiosk m_glv] LockMTOverview];
    for (NSInteger i = (NSInteger)[m_mtobjects count] - 1; i >= 0; i--) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        if ([o m_sid] == sid) {
            [o performSelectorOnMainThread:@selector(RemovePics) withObject:nil waitUntilDone:YES];
            [m_mtobjects removeObjectAtIndex:i];
        }
    }
    [self performSelectorOnMainThread:@selector(FitScroller) withObject:nil waitUntilDone:YES];
    [[m_pkiosk m_glv] UnlockMTOverview];
}

- (void)completeDelete {
    [[m_pkiosk m_glv] LockSDC];
    [[[m_pkiosk m_glv] GetPreScrollerDict] removeAllObjects];
    [[m_pkiosk m_glv] UnlockSDC];
    [[m_pkiosk m_glv] LockMTOverview];
    for (NSInteger i = (NSInteger)[m_mtobjects count] - 1; i >= 0; i--) {
        [[m_mtobjects objectAtIndex:i] performSelectorOnMainThread:@selector(RemovePics) withObject:nil waitUntilDone:YES];
        [m_mtobjects removeObjectAtIndex:i];
    }
    [self performSelectorOnMainThread:@selector(FitScroller) withObject:nil waitUntilDone:YES];
    [[m_pkiosk m_glv] UnlockMTOverview];
}

#pragma mark - layout

// Sort by name, radio tile (-33) first, promo tile (-55) last, then lay out.
- (void)FitScroller {
    [m_mtobjects sortUsingSelector:@selector(compareNames:)];
    for (NSInteger i = (NSInteger)[m_mtobjects count] - 1; i > 0; i--) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        if ([o m_id] == -33) {
            [o retain];
            [m_mtobjects removeObjectAtIndex:i];
            [m_mtobjects insertObject:o atIndex:0];
            [o release];
            break;
        }
    }
    for (NSUInteger j = 0; j < [m_mtobjects count]; j++) {
        MTObject *o = [m_mtobjects objectAtIndex:j];
        if ([o m_id] == -55) {
            [o retain];
            [m_mtobjects removeObjectAtIndex:j];
            [m_mtobjects addObject:o];
            [o release];
            break;
        }
    }
    for (NSUInteger i = 0; i < [m_mtobjects count]; i++)
        [[m_mtobjects objectAtIndex:i] setM_ownindex:(int)i];
    [self SetFrames];
    [self CalcContentsize:[APPDEL GetiPadSize]];
}

- (void)CalcContentsize:(CGSize)size {
    float h = size.height;
    if ([m_mtobjects count] != 0) {
        CGRect last = [[m_mtobjects lastObject] GetPicFrame];
        h = (last.origin.y + last.size.height) + 70.0f;
    }
    [self setContentSize:CGSizeMake(size.width, h)];
}

- (int)HasObject:(long long)object withserverid:(int)serverid {
    int result = -1;
    [[m_pkiosk m_glv] LockMTOverview];
    for (NSInteger i = (NSInteger)[m_mtobjects count] - 1; i > -1; i--) {
        MTObject *o = [m_mtobjects objectAtIndex:i];
        if ([o m_id] == object && [o m_sid] == serverid) { result = (int)i; break; }
    }
    [[m_pkiosk m_glv] UnlockMTOverview];
    return result;
}

- (void)SetPicreplaced { m_picreplaced = YES; }
- (int)GetMTCount { return (int)[m_mtobjects count]; }
@end
