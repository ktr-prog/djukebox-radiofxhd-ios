// GLView_Overview.m -- category GLView (Overview): pinch gesture, the flow <-> overview
// ("MTScroller") transition animations and the helpers that (re)load the overview.
#import "GLView.h"
#import "KioskView.h"
#import "KeyboardView.h"
#import "MTScroller.h"
#import "MTObject.h"
#import "DBOperations.h"
#import "ClipObject.h"
#import "FolderObject.h"
#import "RadioAppDelegate.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@implementation GLView (Overview)

- (void)AddPinch:(int)pinch {
    if (pinch == 1) {
        if (m_pinchGesture != nil) return;
        [self setMultipleTouchEnabled:YES];
        [self setM_pinching:NO];
        m_pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(scaleCircle:)];
        [m_pinchGesture setDelegate:(id)self];
        [self addGestureRecognizer:m_pinchGesture];
        [m_pinchGesture release];
        return;
    }
    if (pinch != 0) return;
    if (m_pinchGesture == nil) return;
    [self removeGestureRecognizer:m_pinchGesture];
    m_pinchGesture = nil;
    [self setMultipleTouchEnabled:NO];
    [self setM_pinching:NO];
}

// Pinch handler. Two fingers moving mostly horizontally change the volume, mostly vertically
// pinch the flow into the overview.
- (void)scaleCircle:(UIPinchGestureRecognizer *)gr {
    if ([self m_pinchstatus] == 1 || [self m_pinchstatus] == 3) return;
    float scale = (float)[gr scale];
    UIGestureRecognizerState state = [gr state];

    if (state == UIGestureRecognizerStateEnded) {
        [self setM_fingersonscreen:0];
        [m_parent setG_scaling:NO];
        [self RestartIdleTimer];
        [self RestartAdvertTimer];
        [m_parent Restart30secsearchTimer];
        if (m_volumepinch > 0) {
            [m_searchview RCSendVolume];
            [m_parent SetLastVolumeKiosk];
            [self setM_pinchstatus:0];
            [self setM_pinching:NO];
            [self setM_fingersonscreen:0];
            m_volumepinch = -1.0f;
            [self RemoveDraggingObject];
            [m_searchview RestartKeyboardtimerFast];
            return;
        }
        if ([self m_pinching] && m_pinchscale < 1.0f && [self m_pinchstatus] == 0) {
            [self setM_pinchstatus:1];
            m_lastpinchoffset = (int)offset;
            [self performSelector:@selector(PinchAni) withObject:nil afterDelay:0.01];
            return;
        }
        if ([self m_pinchstatus] == 0) {
            [self setM_pinching:NO];
            [self setM_fingersonscreen:0];
            [self drawView];
        }
        return;
    }

    if (state == UIGestureRecognizerStateChanged) {
        if (!secondgestureflag && [gr numberOfTouches] >= 2) {
            secondgestureflag = YES;
            CGPoint a = [gr locationOfTouch:0 inView:self];
            CGPoint b = [gr locationOfTouch:1 inView:self];
            float sumx = fabsf(a.x - m_cp1.x) + fabsf(b.x - m_cp2.x);
            float sumy = fabsf(a.y - m_cp1.y) + fabsf(b.y - m_cp2.y);
            if (sumx >= sumy) {
                // mostly horizontal -> pinch into the overview
                if (!(m_lastflags & 0x2000)) {
                    [self setM_pinching:YES];
                    m_pinchscale = (scale < 1.0) ? scale : 1.0f;
                    [self RemoveDraggingObject];
                    if (m_flipping) [self FlipBackAni:[NSNumber numberWithInt:1]];
                    offset = floor(offset + 0.5);
                    [self checkOffset];
                    [self drawView];
                }
            } else if (!(m_lastflags & 0x1000)) {
                // mostly vertical -> volume
                if (![DEL m_useownvolume]) {
                    if (m_selectedfolderid == -33)
                        m_volumepinch = [m_parent m_lastvolume];
                    else
                        m_volumepinch = [m_parent GetPlayerVolume];
                    if (m_volumepinch < 0.001) m_volumepinch = 0.001f;
                    [self RemoveDraggingObject];
                    if (![m_searchview m_keyboardshown]) {
                        [m_searchview StopKeyboardtimer];
                        [self performSelector:@selector(ToggleKBAndRegister:)
                                   withObject:[NSNumber numberWithInt:0] afterDelay:0.01];
                    }
                }
            }
        }

        if (m_volumepinch > 0) {
            if (![m_parent m_fadingover]) {
                double factor = [DEL m_isipad] ? 1.0 : 2.0;
                double v = (double)m_volumepinch + (((double)scale - 1.0) * 0.5) * factor;
                float vol = (float)v;
                if (vol < 0.0f) vol = 0.0f;
                if (vol > 1.0f) vol = 1.0f;
                [m_parent setM_lastvolume:vol];
                if (m_selectedfolderid == -33) [DEL SetStreamerVolume:vol];
                [m_parent SetPlayerVolume:vol];
                [m_searchview SetVolSlider:vol];
            }
            [self RemoveDraggingObject];
        } else if ([self m_pinching]) {
            if (m_pinchscale != scale && m_pinchscale != m_lastpinchscale)
                m_lastpinchscale = m_pinchscale;
            m_pinchscale = (scale < 1.0) ? scale : 1.0f;
        }
    } else if (state == UIGestureRecognizerStateBegan) {
        [m_parent setG_scaling:YES];
        [self setTouchisok:NO];
        touchFlag = NO;
        startTime = 0;
        secondgestureflag = NO;
        [self StopIdleTimer];
        [self StopAdvertTimer];
        [m_parent Restart30secsearchTimer];
        if (![self m_pinching] && [gr numberOfTouches] >= 2) {
            m_cp1 = [gr locationOfTouch:0 inView:self];
            m_cp2 = [gr locationOfTouch:1 inView:self];
        }
    }
    [self drawView];
}

- (void)InitiateOverviewAni {
    [self setM_pinchstatus:1];
    [self setM_pinching:YES];
    m_pinchscale = 0.99f;
    m_lastpinchscale = 1.0f;
    [self drawView];
    m_lastpinchoffset = (int)offset;
    [self performSelector:@selector(PinchAni) withObject:nil afterDelay:0.01];
}

- (void)ForcePinching {
    if ([m_parent ShowingLoadingscreen]) return;
    if ([m_mtscroller GetMTCount] == 0 && ![m_mtscroller m_deletedoverviewcausememwarning]) return;
    if (m_flipping) {
        [self FlipBackAni:[NSNumber numberWithInt:1]];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.35, 0);
    }
    if ([self m_pinching]) return;
    if ([self m_pinchstatus] != 0) return;
    [self setM_pinching:YES];
    [self setM_pinchstatus:1];
    m_lastpinchoffset = (int)offset;
    m_lastpinchscale = 1.0f;
    m_pinchscale = 0.99f;
    [self performSelector:@selector(PinchAni) withObject:nil afterDelay:0.01];
}

// Runs the pinch animation: finishes the shrink (flow -> overview) or reverts it.
- (void)PinchAni {
    if ([m_parent ShowingLoadingscreen]) return;
    m_showonlysearch = NO;
    int mode;   // 1 = shrink into the overview, -1 = revert
    int n;
    if (m_lastpinchscale >= m_pinchscale) {
        n = (int)((double)m_pinchscale / 0.1);
        if ([m_searchview m_keyboardshown]) {
            m_showonlysearch = YES;
            [self performSelector:@selector(ToggleKBAndRegister:)
                       withObject:[NSNumber numberWithInt:[m_searchview m_showwhat]] afterDelay:0.01];
        } else {
            BOOL ipad = NO;
            for (int i = 0; i < 10; i++) {
                ipad = [DEL m_isipad];
                if (!ipad || i != 2) [m_registers[i] setM_enabled:NO];
                ipad = [DEL m_isipad];
            }
            if (ipad && m_selectedfolderid == -33 && !(m_lastflags & 2))
                [m_registers[2] setM_enabled:YES];
            [self ExecuteServerFlagsRest:1];
        }
        mode = 1;
    } else {
        n = (int)((1.0 - (double)m_pinchscale) / 0.1);
        m_additionalalpha = 1.0f;
        mode = -1;
    }

    if (n + 1 >= 1) {
        float steps = (float)(n + 1);
        for (int i = 1; i <= n + 1; i++) {
            if (mode == 1) {
                m_additionalalpha = 1.0f - (float)i / steps;
                m_pinchscale = (float)((double)m_pinchscale - 0.1);
                if (m_pinchscale < 0) m_pinchscale = 0;
                [m_titlelabel setAlpha:m_additionalalpha];
                [m_interpretlabel setAlpha:m_additionalalpha];
            } else {
                m_pinchscale = (float)((double)m_pinchscale + 0.1);
                if (m_pinchscale > 1.0f) m_pinchscale = 1.0f;
            }
            [self drawView];
        }
    }

    if (mode == -1) {
        // reverted: back to the flow
        [self setM_pinchstatus:0];
        [self setM_pinching:NO];
        [self setM_fingersonscreen:0];
        m_volumepinch = -1.0f;
        [self RemoveDraggingObject];
        [self drawView];
        return;
    }

    if (m_selectedfolderid == -33 && [DEL m_lastchannelid] >= 1) {
        [self GetArrayLock:NO];
        for (unsigned i = 0; i < [[self m_tilearray] count]; i++) {
            if ([(ClipObject *)[[self m_tilearray] objectAtIndex:i] ID] == (long long)[DEL m_lastchannelid]) {
                offset = (double)(float)(int)i + 0.001;
                break;
            }
        }
        [m_arraylock unlock];
        [self drawView];
    }
    [m_mtscroller ReInit];
    [m_mtscroller setAlpha0];
    [m_mtscroller ReSetup];
    [m_mtscroller setM_lastactiveradiochannel:[DEL m_lastchannelid]];
    [m_mtscroller setHidden:NO];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, 0);
    [self setM_drawempty:YES];
    [self drawView];
    [m_parent FadeQueueToBlack:YES];
    [UIView beginAnimations:@"pinchani1" context:nil];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(PinchAni1DidStop)];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.6];
    [m_mtscroller setAlpha1];
    [UIView commitAnimations];
    if ([m_mtscroller m_deletedoverviewcausememwarning]) {
        [m_mtscroller setM_deletedoverviewcausememwarning:NO];
        [self performSelector:@selector(ReLoadScrollerDelayed) withObject:nil afterDelay:0.65];
    }
}

- (void)PinchAni1DidStop {
    [self setM_pinchstatus:2];
    if ([self m_selectedfolderid] != -33)
        [m_mtscroller SetPicreplaced];
    else
        [m_mtscroller ExchangeChannelLogo:[NSNumber numberWithInt:1]];
    [m_mtscroller setScrollEnabled:YES];
    if ([self m_autogotofolder] != -1 && [self m_autogotoserver] != -1) {
        int idx = [m_mtscroller HasObject:[self m_autogotofolder] withserverid:[self m_autogotoserver]];
        if (idx != -1) [m_mtscroller GotoFolder:idx];
    }
    [self performSelector:@selector(BeginSearchInMTScroller:)
               withObject:[[m_searchview m_searchlabel] text] afterDelay:0.1];
    [self setM_autogotofolder:-1];
    [self setM_autogotoserver:-1];
}

// Overview -> flow (a folder was chosen in the overview, or none: back to the old one).
- (void)PinchAniBack {
    MTObject *obj = nil;
    int count = 0;
    if (m_newselectedfolderindex != -1) {
        [self LockMTOverview];
        obj = [m_mtscroller GetMTObject:m_newselectedfolderindex];
        count = [m_mtscroller GetMTCount];
        [self UnlockMTOverview];
        if (obj == nil) return;
        if ([obj m_id] == -33) {
            int n = [DEL GetNumForChannelID:[m_mtscroller m_lastactiveradiochannel]];
            if (n >= 0) m_lastpinchoffset = n;
        }
    }
    [UIView beginAnimations:@"pinchani1" context:nil];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(PinchAniBackDidStop)];
    [UIView setAnimationDuration:0.6];
    [m_mtscroller setAlpha2];
    [UIView commitAnimations];
    [self setM_drawempty:YES];
    if (m_newselectedfolderindex == -1) return;

    if ([obj m_id] == [self m_selectedfolderid] &&
        [obj m_sid] == [self m_selectedserverid] &&
        [obj m_ipodid] == [self m_selectedipodid] &&
        [m_parent selectedSpotifyIDMatches:[obj m_spotifyfolderid]])
        return;   // same folder as before: nothing to load

    m_rondell_loaded = NO;
    FolderObject *folder = nil;
    if (m_newselectedfolderindex >= 0 && obj != nil && m_newselectedfolderindex < count) {
        [DEL LockDB:NO];
        DBOperations *db = [[DBOperations alloc] init];
        folder = [db GetFolderForID:[obj m_id] withserverid:[obj m_sid]
                         withipodid:[obj m_ipodid] withspotifyid:[obj m_spotifyfolderid]];
        [db release];
        [DEL UnlockDB];
    } else {
        [DEL LockDB:NO];
        DBOperations *db = [[DBOperations alloc] init];
        NSMutableArray *folders = [db GetFolders:[m_parent m_sve] onlyexclude:NO checkempty:YES
                                      withLimits:YES withremotefolders:YES join:YES];
        [db release];
        [DEL UnlockDB];
        folder = ([folders count] == 0) ? nil : [[folders objectAtIndex:0] retain];
        [folders release];
    }
    [self performSelector:@selector(HelperFuncLoadFolder:) withObject:folder afterDelay:0.03];
}

- (void)PinchAniBackDidStop {
    if ([self m_newselectedfolderindex] != -1 && !m_rondell_loaded && ![DEL g_end]) {
        // the new folder is still loading: wait
        [self performSelector:@selector(PinchAniBackDidStop) withObject:nil afterDelay:0.2];
        return;
    }
    if ([DEL g_end]) return;
    m_pinchscale = 0;
    m_additionalalpha = 0;
    [self setM_drawempty:NO];
    [self drawView];
    m_lastpinchoffset = -1;
    if (m_mtscroller != nil) [m_mtscroller setHidden:YES];
    for (int i = 0; i < 10; i++) {
        m_additionalalpha = (float)((double)m_additionalalpha + 0.1);
        m_pinchscale = (float)((double)m_pinchscale + 0.1);
        [self drawView];
        [m_titlelabel setAlpha:m_additionalalpha];
        [m_interpretlabel setAlpha:m_additionalalpha];
    }
    // little bounce at the end
    for (int i = 0; i < 8; i++) {
        m_pinchscale = (float)((double)m_pinchscale + (i <= 3 ? 0.005 : -0.005));
        [self drawView];
    }
    [m_titlelabel setAlpha:1.0f];
    [m_interpretlabel setAlpha:1.0f];
    [self setM_pinching:NO];
    [self setM_pinchstatus:0];
    [self setM_fingersonscreen:0];
    [self ExecuteServerFlags:[NSNumber numberWithInt:1]];
}

- (void)HelperFuncLoadFolder:(FolderObject *)folder {
    if (folder == nil) {
        m_rondell_loaded = YES;
        return;
    }
    [self ShowOnlyFolder:folder withstartSong:YES channelviewwaspresent:YES];
    [folder release];
}

- (void)ReStartMTScroller {
    [m_mtscroller completeDelete];
    [m_mtscroller setM_deletedoverviewcausememwarning:YES];
    m_prescrollerthreaddone = NO;
    if ([self m_pinchstatus] != 2) return;
    [m_mtscroller RestartOverviewTimer];
    [self performSelectorOnMainThread:@selector(ReLoadScrollerInMT) withObject:nil waitUntilDone:NO];
}

- (void)ReLoadScrollerInMT {
    [self EmptyRondell];
    [self setM_selectedipodid:0];
    [self setM_selectedfolderid:-1];
    [self setM_selectedspotifyfolderid:nil];
    [self performSelector:@selector(ReLoadScrollerDelayed) withObject:nil afterDelay:0];
}

- (void)ReLoadScrollerDelayed {
    [m_mtscroller ReInit];
    [self StartPreScrollerThread];
    [m_mtscroller SetUpScroller:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:1], @"nsnum",
        [NSNumber numberWithInt:1], @"nsfirst",
        [NSNumber numberWithInt:0], @"nsaddfolder", nil]];
    [m_mtscroller SetPicreplaced];
    if ([self m_pinchstatus] != 2) return;
    [self performSelector:@selector(BeginSearchInMTScroller:)
               withObject:[[m_searchview m_searchlabel] text] afterDelay:0.1];
}

- (void)ResetupMTScroller {
    [m_mtscroller RestartOverviewTimer];
    [m_mtscroller ReSetup];
    [m_mtscroller setAlpha1];
    [self performSelector:@selector(BeginSearchInMTScroller:)
               withObject:[[m_searchview m_searchlabel] text] afterDelay:0.1];
    [m_mtscroller SetPicreplaced];
}

- (void)PrepareCloseScroller {
    [m_mtscroller StopOverviewTimer];
    [m_mtscroller setM_isclosing:YES];
}

- (void)ReturnToLastSelectedFolder {
    if (m_searchview == nil) return;
    [m_searchview performSelector:@selector(ReturnToLastSelectedFolder) withObject:nil afterDelay:0.1];
}

- (void)ChooseOtherMixtape:(NSNumber *)mixtapeid {
    long long want = [mixtapeid longLongValue];
    if ([self m_pinchstatus] != 0) return;
    if ([[self m_tilearray] count] != 0) {
        [self performSelectorOnMainThread:@selector(SetLabelTexts:)
                               withObject:[NSNumber numberWithInt:(int)offset] waitUntilDone:NO];
        return;
    }
    [DEL LockDB:YES];
    DBOperations *db = [[DBOperations alloc] init];
    NSMutableArray *folders = [db GetFolders:[m_parent m_sve] onlyexclude:NO checkempty:YES
                                  withLimits:YES withremotefolders:YES join:YES];
    [db release];
    [DEL UnlockDB];
    FolderObject *pick = nil;
    if ([folders count] != 0) {
        // the list is [first, second ...]: prefer the second entry unless it is the wanted one
        if ([folders count] >= 2 && [(FolderObject *)[folders objectAtIndex:1] folderid] != want)
            pick = [folders objectAtIndex:1];
        else if ([(FolderObject *)[folders objectAtIndex:0] folderid] != want)
            pick = [folders objectAtIndex:0];
    }
    if (pick != nil) {
        [self performSelectorOnMainThread:@selector(HelperFuncShowFolder:) withObject:pick waitUntilDone:YES];
        [folders release];
        return;
    }
    [folders release];
    [self performSelectorOnMainThread:@selector(SetLabelTexts:)
                           withObject:[NSNumber numberWithInt:(int)offset] waitUntilDone:NO];
}

- (void)ForwardSetVolSlider:(float)vol {
    [m_searchview SetVolSlider:vol];
}

- (void)ShrinkAniDidStop {
    [m_folderscreenshot removeFromSuperview];
    [self ShowFolderRest];
}

@end
