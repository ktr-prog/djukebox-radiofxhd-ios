// GLView, part 2: the row of ten "register" buttons above the coverflow, the sliding keyboard/volume panel
// and the blink animations.  Recovered from -[GLView ...] (see addresses in the comments).
#import "GLView.h"
#import "KioskView.h"
#import "KeyboardView.h"
#import "MTScroller.h"
#import "RegisterImage.h"
#import "RadioAppDelegate.h"
#import "ServerEntry.h"
#import "DBOperations.h"
#import "FolderObject.h"
#import "ClipObject.h"
#import "Globals.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])
#define ISIPAD ([DEL m_isipad])
#define FLAGBYTE(k) ((m_lastflags >> (8 * (k))) & 0xff)

@implementation GLView (Registers)

// ---- geometry -----------------------------------------------------------------------------------------------
// @0x4dcb4: buttons are centred as a row; only the enabled ones take part in the layout.
- (CGRect)GetRegisterFrame:(CGSize)size withindex:(int)indexArg {
    BOOL pad = ISIPAD;
    int w   = pad ? 0x38 : 0x25;
    int gap = pad ? 0xf : 0xa;
    float h = pad ? 48.0f : 32.0f;
    int count, slot;
    if ([m_registers[indexArg] m_enabled]) {
        count = 0;
        for (int i = 0; i < 10; i++) if ([m_registers[i] m_enabled]) count++;
        slot = -1;
        for (int i = 0; i < 10; i++) {
            if (![m_registers[i] m_enabled]) continue;
            slot++;
            if (indexArg == i) break;
        }
    } else {
        count = 10;
        slot = indexArg;
    }
    float x = ((size.width - (float)(count * w + (count - 1) * gap)) * 0.5f) + (float)((w + gap) * slot);
    return CGRectMake(x, 0, (float)w, h);
}

- (CGRect)GetRegisterRect:(int)registerRect { return [m_registers[registerRect] frame]; }

// @0x50a20: frame of the sliding keyboard / volume panel; y depends on the panel that is showing
- (CGRect)GetKBViewFrame:(CGSize)size {
    int y;
    BOOL pad = ISIPAD;
    if (![m_searchview m_keyboardshown]) {
        y = -1000;
    } else {
        switch ([m_searchview m_showwhat]) {
            case 0:  y = pad ? -940 : -955; break;
            case 1:  y = -910; break;
            case 2:  y = (size.width <= size.height) ? -200 : (pad ? -430 : -735); break;
            case 3:  y = -772; break;
            case 5:  y = pad ? -330 : -730; break;
            case 6:  y = pad ? -315 : -730; break;
            case 7:  y = -688; break;
            case 8:
            case 9:  y = pad ? -315 : -730; break;
            default: y = 0; break;
        }
    }
    return CGRectMake(0, (float)y, size.width, 1003.01f);   // 0x447ac0ba
}

// @0x69130: while a panel is open its register button is pushed down to sit on the panel's top edge
- (void)MoveOneRegister:(CGSize)size {
    if (![m_searchview m_keyboardshown]) return;
    int which = [m_searchview m_showwhat];
    BOOL pad = ISIPAD;
    float dy;
    switch (which) {
        case 0:  dy = pad ? 60.0f : 45.0f; break;
        case 1:  dy = 90.0f; break;
        case 2:  dy = (size.width > size.height) ? (pad ? 570.0f : 265.0f) : 800.0f; break;
        case 3:  dy = 228.0f; break;
        case 5:  dy = pad ? 670.0f : 270.0f; break;
        case 6:  dy = pad ? 685.0f : 270.0f; break;
        case 7:  dy = 312.0f; break;
        case 8:
        case 9:  dy = pad ? 685.0f : 270.0f; break;
        default: return;
    }
    CGRect f = [m_registers[which] frame];
    [m_registers[which] setFrame:CGRectMake(f.origin.x, f.origin.y + dy, f.size.width, f.size.height)];
}

// @0x64ac0 / 0x64a14
- (void)SetRedDotRect:(CGSize)size {
    CGRect *src = ISIPAD ? m_reddotrects : m_reddotrectssmall;
    m_reddotrect = src[(size.width > size.height) ? 1 : 0];
}
- (void)SetForegroundRect:(CGSize)size {
    CGRect *src = ISIPAD ? m_foregroundrects : m_foregroundrectssmall;
    m_foregroundrect = src[(size.width > size.height) ? 1 : 0];
}

- (CGRect)GetFrameForChannelView:(CGSize)size { return CGRectMake(0, 0, size.width, size.height); }

- (void)FitSubViews:(CGSize)size {
    m_ishorizontal = size.width > size.height;
    for (int i = 0; i < 10; i++)
        [m_registers[i] setFrame:[self GetRegisterFrame:size withindex:i]];
    [m_searchview FitSubViews:size];
    [m_searchview SetElementpositions];
    [m_searchview setFrame:[self GetKBViewFrame:size]];
    [m_searchview SetKBBackGroundPic:size];
    [self MoveOneRegister:size];
    [self SetRedDotRect:size];
    [self SetForegroundRect:size];
    if (m_mtscroller != nil) [m_mtscroller FitScroller];
    [m_interpretlabel setFrame:[self GetTitleInterpretLabelFrame:size withtype:1]];
    [m_titlelabel setFrame:[self GetTitleInterpretLabelFrame:size withtype:0]];
}

// ---- creation -----------------------------------------------------------------------------------------------
- (void)SetParent:(id)parent {
    m_parent = parent;
    m_mtscroller = [[MTScroller alloc] init];
    [m_mtscroller SetKioskVPointer:m_parent];
    [m_mtscroller setDelegate:self];
    [m_mtscroller setFrame:[m_parent frame]];
    [m_parent addSubview:m_mtscroller];
    [m_mtscroller setHidden:YES];
    [m_mtscroller SetUpScroller:[NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSNumber numberWithInt:1], @"nsnum",
                                 [NSNumber numberWithInt:1], @"nsfirst",
                                 [NSNumber numberWithInt:0], @"nsaddfolder", nil]];
    [m_mtscroller release];
}

- (void)AddKBView {
    CGSize pad = [DEL GetiPadSize];
    for (int i = 0; i < 10; i++) {
        m_registers[i] = [[RegisterImage alloc] initWithFrame:CGRectZero];
        [m_registers[i] InitView];
        [m_registers[i] SetGLVPointer:self];
        [m_registers[i] setM_index:i];
        [m_parent addSubview:m_registers[i]];
        [m_registers[i] release];
        [m_registers[i] setUserInteractionEnabled:YES];
        [m_registers[i] setM_enabled:NO];
    }
    for (int i = 0; i < 10; i++) {
        [m_registers[i] setFrame:[self GetRegisterFrame:pad withindex:i]];
        NSString *name = nil;
        switch (i) {
            case 0: name = @"volume"; break;
            case 1: name = @"sprechblase"; break;
            case 2: name = ISIPAD ? @"lupe" : @"songs"; break;
            case 3: name = @"onoff"; break;
            case 4: name = @"kollektionen"; break;
            case 5: name = @"hilfe"; break;
            case 6: name = @"einstellungen"; break;
            case 7: name = @"video"; break;
            case 8: name = @"euro"; break;
            case 9: name = @"pinnwand"; break;
        }
        [m_registers[i] SetImage:[NSString stringWithFormat:@"bmaske-%@", name] withisadditionalimage:NO withcreate:YES];
        [m_registers[i] SetImage:[NSString stringWithFormat:@"bmaske-dunkel-%@", name] withisadditionalimage:YES withcreate:YES];
    }
    [m_registers[2] SetAdditionalWhiteImage];

    m_searchview = [[KeyboardView alloc] initWithFrame:CGRectZero];
    [m_searchview SetParent:self];
    [m_searchview setFrame:[self GetKBViewFrame:pad]];
    [m_searchview FitSubViews:pad];
    [m_searchview setUserInteractionEnabled:YES];
    [m_searchview setClipsToBounds:YES];
    [m_parent addSubview:m_searchview];
    [m_searchview release];
    [m_searchview ForwardKioskPointer:m_parent];
}

- (id)GetRegister0 { return m_registers[0]; }
- (void)SetSearchRegisterActive { [m_registers[2] setM_enabled:YES]; }

- (void)CheckToShowRegister6 {
    CGSize pad = [DEL GetiPadSize];
    [m_registers[6] setFrame:[self GetRegisterFrame:pad withindex:6]];
    [m_registers[6] setM_enabled:YES];
    [m_registers[6] setUserInteractionEnabled:YES];
    [m_registers[6] setAlpha:gRfxButtonAlpha];
}

- (void)MoveRegisters:(BOOL)moveRegisters {
    m_movingregisters = YES;
    [m_searchview retain];
    for (int i = 0; i < 10; i++) [m_registers[i] retain];
    UIView *target = (moveRegisters == 1) ? [[DEL GetiPadMainVC] view] : self;
    for (int i = 0; i < 10; i++) {
        [m_registers[i] removeFromSuperview];
        [target addSubview:m_registers[i]];
    }
    [m_searchview removeFromSuperview];
    [target addSubview:m_searchview];
    [m_searchview release];
    for (int i = 0; i < 10; i++) [m_registers[i] release];
    m_movingregisters = NO;
}

// the round menu buttons: more transparent while a video plays behind the coverflow / hidden by the dev menu switch
- (void)DimRegisters {
    for (int i = 0; i < 10; i++) if (m_registers[i] != nil && [m_registers[i] m_enabled]) [m_registers[i] setAlpha:gRfxButtonAlpha];
}
- (void)ApplyButtonVisibility {
    for (int i = 0; i < 10; i++) if (m_registers[i] != nil) [m_registers[i] setHidden:gRfxHideButtons];
}

- (void)HideRegisters:(BOOL)hide {
    for (int i = 0; i < 10; i++) [m_registers[i] setHidden:hide];
    [m_searchview setHidden:hide];
}

// ---- which registers exist (@0x59f..) ------------------------------------------------------------------------
// Every register starts disabled; the server flags (StateFlags of the chosen server entry) switch them on.
- (void)ExecuteServerFlags:(id)executeServerFlags {
    if ([self m_executingflags]) {
        [self performSelector:@selector(ExecuteServerFlags:) withObject:executeServerFlags afterDelay:0.1];
        return;
    }
    [self setM_executingflags:YES];
    ServerEntry *sve = [m_parent m_sve];
    if (sve != nil) m_lastflags = [sve StateFlags];
    int arg = [executeServerFlags intValue];

    if (sve != nil) {
        if ([[m_parent m_sve] reserved_i1] > 0 ||
            ([[m_parent m_sve] adverttexttime] >= 1 && [[DEL m_advertisingtexts] count] != 0)) {
            if ([self m_advertinittime] <= 0) [self RestartAdvertTimer];
        } else {
            [self setM_advertinittime:-1.0];
        }
    }
    if ([m_searchview m_keyboardshown] && [m_searchview m_showwhat] >= 0 && [m_searchview m_showwhat] <= 3) {
        [self ToggleKBAndRegister:[NSNumber numberWithInt:[m_searchview m_showwhat]]];
        if (arg == 1) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.7, false);
    }

    for (int i = 0; i < 10; i++) {
        [m_registers[i] setM_enabled:NO];
        // port: only volume (0), search (2), collections (4) and help (5) exist offline.  The speech bubble (1), the
        // on/off button (3) and the settings / video / euro / pin-board buttons (6-9) belong to the dead backend.
        // dev menu: "RfxDevAllButtons" enables every button, "RfxDevNoVolume" turns the volume button off (the original
        // server flag 0x100, "volume button disabled": the button is simply not there)
        NSUserDefaults *devud = [NSUserDefaults standardUserDefaults];
        BOOL devAll = [devud boolForKey:@"RfxDevAllButtons"], devNoVol = [devud boolForKey:@"RfxDevNoVolume"];
        if (devAll && [self m_pinchstatus] == 0) {
            if (!(i == 0 && devNoVol)) [m_registers[i] setM_enabled:YES];
            continue;
        }
        if ([self m_pinchstatus] != 0) continue;                         // collections view (and while it opens / closes): no search symbol, nothing else
        if (i == 1 || i == 3 || i >= 6) continue;
        BOOL online = [DEL IsOnline];
        switch (i) {
            case 0:
                if (sve != nil && (FLAGBYTE(1) & 0x01) == 0 && !devNoVol) [m_registers[i] setM_enabled:YES];
                break;
            case 1:
                if (sve != nil && (FLAGBYTE(3) & 0x04) != 0) [m_registers[i] setM_enabled:YES];
                break;
            case 2:
                if ([self m_selectedfolderid] == -33 && [self m_pinchstatus] == 0) break;
                if (sve != nil && (FLAGBYTE(0) & 0x02) == 0) [m_registers[i] setM_enabled:YES];
                break;
            case 3:
                if (sve != nil && (FLAGBYTE(1) & 0x40) == 0) [m_registers[i] setM_enabled:YES];
                break;
            case 4:
                if (sve != nil && (FLAGBYTE(2) & 0x02) == 0) [m_registers[i] setM_enabled:YES];
                break;
            case 5:
                if (sve != nil && (FLAGBYTE(2) & 0x04) == 0) [m_registers[i] setM_enabled:YES];
                break;
            case 6:
                if (!online) break;
                if (![DEL m_isipad] && [DEL IsTMPresent]) break;
                if (sve != nil && (FLAGBYTE(2) & 0x10) == 0) [m_registers[i] setM_enabled:YES];
                break;
            case 7:
                if (sve != nil && (FLAGBYTE(2) & 0x80) == 0) {
                    NSMutableArray *videos = [[NSMutableArray alloc] init];
                    [DEL GetVideothek:videos];
                    if ([videos count] != 0) [m_registers[i] setM_enabled:YES];
                    [videos release];
                }
                break;
            case 8: {
                int hosting = sve ? [sve hosting] : 0;
                if (sve != nil && online && hosting != 0 && (FLAGBYTE(3) & 0x01) != 0) [m_registers[i] setM_enabled:YES];
                break;
            }
            case 9:
                if (online && (FLAGBYTE(3) & 0x10) != 0) [m_registers[i] setM_enabled:YES];
                break;
        }
    }
    [self ExecuteServerFlagsRest:arg];
}

- (void)ExecuteServerFlagsRest:(int)arg {
    if (arg == 1) {
        [UIView beginAnimations:@"serverflagsanimation2" context:NULL];
        [UIView setAnimationDuration:0.6];
        [UIView setAnimationRepeatCount:1.0f];
        [UIView setAnimationDidStopSelector:@selector(ExecuteFlagsRest)];
        [UIView setAnimationDelegate:self];
    }
    CGSize pad = [DEL GetiPadSize];
    for (int i = 0; i < 10; i++) {
        [m_registers[i] setFrame:[self GetRegisterFrame:pad withindex:i]];
        BOOL on = [m_registers[i] m_enabled];
        [m_registers[i] setUserInteractionEnabled:on];
        [m_registers[i] setAlpha:on ? gRfxButtonAlpha : 0.0f];
    }
    [self ApplyButtonVisibility];
    [self MoveOneRegister:pad];
    if (arg != 1) {
        [m_searchview FitSubViews:pad];
        [self setM_executingflags:NO];
    } else {
        [UIView commitAnimations];
    }
}

- (void)ExecuteFlagsRest {
    CGSize pad = [DEL GetiPadSize];
    [m_searchview FitSubViews:pad];
    [self setM_executingflags:NO];
    if (![self IsShowingMTScroller]) return;
    if ([[m_searchview m_searchlabel] text] == nil) return;
    if ([[[m_searchview m_searchlabel] text] length] == 0) return;
    if (([[m_parent m_sve] StateFlags] & 2) != 0) return;
    if ([m_searchview m_keyboardshown]) return;
    [self performSelector:@selector(ToggleKBAndRegister:) withObject:[NSNumber numberWithInt:2] afterDelay:0.7];
}

- (void)CheckToRemoveRegister {
    if ([self m_movingup]) return;
    if (![m_searchview m_keyboardshown]) return;
    if ([m_searchview m_showwhat] == 1) return;
    [self performSelector:@selector(ToggleKBAndRegister:)
               withObject:[NSNumber numberWithInt:[m_searchview m_showwhat]] afterDelay:0.01];
}

- (void)ShowVolumeForOverview {
    if ([m_registers[0] m_enabled]) return;
    [UIView beginAnimations:@"volaniX" context:NULL];
    [UIView setAnimationDuration:0.6];
    [m_registers[0] setM_enabled:YES];
    [m_registers[0] setAlpha:1.0f];
    CGSize pad = [DEL GetiPadSize];
    [m_registers[0] setFrame:[self GetRegisterFrame:pad withindex:0]];
    if ([m_registers[2] m_enabled])
        [m_registers[2] setFrame:[self GetRegisterFrame:pad withindex:2]];
    [UIView commitAnimations];
}

// ---- opening / closing the panel ------------------------------------------------------------------------------
- (void)ToggleKBAndRegister:(id)toggleKBAndRegister {
    if (m_movingregisters) {
        [self performSelector:@selector(ToggleKBAndRegister:) withObject:toggleKBAndRegister afterDelay:0.1];
        return;
    }
    int which = [toggleKBAndRegister intValue];
    switch (which) {
        case 0: case 1: case 2: case 3:
            if (![m_searchview m_keyboardshown]) {
                [m_searchview setM_showwhat:which];
                [m_searchview ShowElements:[m_searchview m_showwhat]];
            }
            [self ToggleAni];
            break;
        case 5:
            if ([m_searchview m_keyboardshown]) [self ToggleAni];
            [m_parent ShowTutorial];
            break;
        case 6:
            if (![m_searchview m_keyboardshown]) {
                [m_parent SendCDsToBackGround];
                [m_parent OrderGLVAndBlackView];
                [self OpenConfigUrl];
                [m_searchview setM_showwhat:which];
                [m_searchview ShowElements:[m_searchview m_showwhat]];
            }
            [self ToggleAni];
            break;
        case 7:
            if ([m_searchview m_keyboardshown]) {
                [self ToggleAni];
            } else if (![m_searchview HasVideos]) {
                [m_parent OpenSourcesPanel];         // port: no films in the Videothek -> the button opens the source plugins panel
            } else {
                id video = [m_searchview GetFirstVideo];
                if (video == nil) {
                    [m_searchview setM_showwhat:which];
                    [m_searchview ShowElements:[m_searchview m_showwhat]];
                    [self ToggleAni];
                } else {
                    [m_parent performSelector:@selector(StartTPAni:)
                                   withObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                               video, @"keyfilmdictvideothek",
                                               [NSNumber numberWithInt:0], @"keyfilmdictcommercial", nil]
                                   afterDelay:0.01];
                }
            }
            break;
        case 8:
        case 9:
            if (![m_searchview m_keyboardshown]) {
                [m_parent SendCDsToBackGround];
                [m_parent OrderGLVAndBlackView];
                if (which == 8) [self OpenHintUrl];
                if (which == 9) [self OpenFBWallUrl];
                [m_searchview setM_showwhat:which];
                [m_searchview ShowElements:[m_searchview m_showwhat]];
            }
            [self ToggleAni];
            break;
        default:        // 4 (collections) is handled by ForcePinching; anything else is ignored
            break;
    }
}

- (void)ToggleAni {
    [m_searchview setM_keyboardshown:![m_searchview m_keyboardshown]];
    if (![m_searchview m_keyboardshown]) [self setM_movingup:YES];
    CGSize pad = [DEL GetiPadSize];
    if (![m_searchview m_keyboardshown]) {
        [m_searchview StopCursorblinking];
    } else {
        if ([m_searchview m_showwhat] == 0)
            [m_searchview FitVolumeElements:[DEL GetiPadSize]];
        if ([m_searchview m_showwhat] == 6 || [m_searchview m_showwhat] == 8 || [m_searchview m_showwhat] == 9) {
            [m_searchview StopKeyboardtimer];
        } else if (![m_parent g_scaling]) {
            [m_searchview RestartKeyboardtimer];
        }
        if ([m_searchview m_showwhat] == 2) {
            // with a search text the results stay as they were (they are not searched again)
            if ([[[m_searchview m_searchlabel] text] length] == 0) [m_searchview SetUpSearchList:[self m_tilearray]];
            [m_searchview StartCursorBlinking];
        }
        [self ReInitDimmView];
    }
    [UIView beginAnimations:@"togglekeyboard" context:NULL];
    [UIView setAnimationDuration:0.5];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(KBToggleDidStop)];
    [m_searchview setFrame:[self GetKBViewFrame:pad]];
    if (m_dimmview != nil) {
        if ([m_searchview m_keyboardshown]) {
            [m_dimmview setAlpha:0.7f];
        } else if (![DEL m_isstattalm] || [m_searchview m_showwhat] != 2) {
            [m_dimmview setAlpha:0.0f];
        }
    }
    for (int i = 0; i < 10; i++)
        [m_registers[i] setFrame:[self GetRegisterFrame:pad withindex:i]];
    [self MoveOneRegister:pad];
    if ([m_searchview m_keyboardshown]) {
        [m_registers[[m_searchview m_showwhat]] ShowDarkImage:0.0f];
    } else {
        for (int n = 0; n < 10; n++)       // sic: the binary repeats this on the same register ten times
            [m_registers[[m_searchview m_showwhat]] ShowDarkImage:1.0f];
    }
    [UIView commitAnimations];
}

- (void)KBToggleDidStop {
    BOOL shown = [m_searchview m_keyboardshown];
    BOOL wasOnlySearch = m_showonlysearch;
    m_showonlysearch = NO;
    if (!shown) {
        m_movingup = NO;
        if (m_dimmview != nil && (![DEL m_isstattalm] || [m_searchview m_showwhat] != 2)) {
            [m_dimmview removeFromSuperview];
            m_dimmview = nil;
        }
        if ([m_registers[0] m_enabled] && [self m_pinchstatus] == 2) {
            [UIView beginAnimations:@"volaniX" context:NULL];
            [UIView setAnimationDuration:0.6];
            [m_registers[0] setM_enabled:NO];
            [m_registers[0] setAlpha:0.0f];
            CGSize pad = [DEL GetiPadSize];
            [m_registers[0] setFrame:[self GetRegisterFrame:pad withindex:0]];
            if ([m_registers[2] m_enabled])
                [m_registers[2] setFrame:[self GetRegisterFrame:pad withindex:2]];
            [UIView commitAnimations];
        }
        [m_searchview SetWebViewsBlack];
        if ([m_registers[6] m_enabled])
            [self ExecuteServerFlags:[NSNumber numberWithInt:1]];
        if ([[self m_tilearray] count] == 0 &&
            [[m_searchview m_searchlabel] text] != nil &&
            [[[m_searchview m_searchlabel] text] length] != 0 &&
            ![self IsShowingMTScroller]) {
            // DEVIATION: the original cleared the search text here.  The text and the result list stay; the carousel just shows
            // everything again (the search narrows it only while it is being typed).
            [self ShowAllTilesKeepingSearch];
            [self ReInitThread];
            [self drawView];
        }
    }
    if (wasOnlySearch) {
        for (int i = 0; i < 10; i++) {
            if (i == 1) continue;
            [m_registers[i] setM_enabled:NO];
        }
        [self ExecuteServerFlagsRest:1];
    }
    if (!m_isblinking) [self StartBlinkAni];
    if ([m_searchview m_gotooverview]) {
        [m_searchview setM_gotooverview:NO];
        [self ForcePinching];
    }
}

- (void)ReInitDimmView {
    [m_parent SendCDsToBackGround];
    if (m_dimmview != nil) {
        [m_dimmview removeFromSuperview];
        m_dimmview = nil;
    }
    m_dimmview = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, [self frame].size.width, [self frame].size.height + 126.0f + 20.0f)];
    [m_dimmview setAlpha:0.0f];
    [m_dimmview setBackgroundColor:[UIColor blackColor]];
    UIView *above = (m_notconview != nil) ? (UIView *)m_notconview : (UIView *)[self GetRegister0];
    [self insertSubview:m_dimmview belowSubview:above];
    [m_dimmview release];
}

// ---- blinking of the search / sync register -------------------------------------------------------------------
- (void)StartBlinkAni {
    NSString *txt = [[m_searchview m_searchlabel] text];
    BOOL go;
    if (txt != nil && [txt length] != 0 && ![m_searchview m_keyboardshown]) go = YES;
    else go = m_blinkpic;
    if (!go) { m_isblinking = NO; return; }
    m_isblinking = YES;
    [UIView beginAnimations:@"blinkani" context:NULL];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.5];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(BlinkAniEnd)];
    [m_registers[2] SetAdditionalAlpha:m_blinkpic ? 0.0f : 1.0f];
    [UIView commitAnimations];
    m_blinkpic = !m_blinkpic;
}
- (void)BlinkAniEnd { [self performSelector:@selector(StartBlinkAni) withObject:nil afterDelay:0.01]; }

- (void)SetRegisterToSync:(int)registerToSync {
    m_shouldblinksync = registerToSync;
    if (registerToSync != 1) return;
    if (m_blinkanirunning) return;
    [m_registers[6] performSelectorOnMainThread:@selector(SetSyncImage:) withObject:[NSNumber numberWithInt:registerToSync] waitUntilDone:YES];
    m_blinkpicsync = NO;
    [self performSelectorOnMainThread:@selector(StartSyncBlinkAni) withObject:nil waitUntilDone:NO];
}
- (void)StartSyncBlinkAni {
    if (m_shouldblinksync != 1) return;
    m_blinkanirunning = YES;
    [UIView beginAnimations:@"blinkanisync" context:NULL];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.6];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(SyncBlinkAniEnd)];
    [m_registers[6] SetAdditionalAlpha:m_blinkpicsync ? 0.0f : 1.0f];
    [UIView commitAnimations];
    m_blinkpicsync = !m_blinkpicsync;
}
- (void)SyncBlinkAniEnd {
    if (m_shouldblinksync != 1) {
        [m_registers[6] SetAdditionalAlpha:0.0f];
        [m_registers[6] SetSyncImage:[NSNumber numberWithInt:m_shouldblinksync]];
        m_blinkanirunning = NO;
    } else {
        [self performSelector:@selector(StartSyncBlinkAni) withObject:nil afterDelay:0.01];
    }
}

// ---- panel hooks that belonged to the dead web back-end ------------------------------------------------------------
// URLs of the original (back-end gone: the web panels will report that instead of showing a page)
- (NSArray *)SerialParts {
    NSString *sn = [[NSUserDefaults standardUserDefaults] stringForKey:@"SerialNumber"];
    return (sn != nil) ? [sn componentsSeparatedByString:@"-"] : nil;
}
- (void)OpenConfigUrl {
    NSArray *p = [self SerialParts];
    NSString *dev = ([p count] >= 2) ? [NSString stringWithFormat:@"%@-%@", [p objectAtIndex:0], [p objectAtIndex:1]] : @"";
    NSString *pw = ([p count] >= 3) ? [p objectAtIndex:2] : @"";
    NSString *extra = (p != nil) ? [NSString stringWithFormat:@"&deviceid=%@&password=%@", dev, pw] : @"";
    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.tobit.com/rfx-cloud1/index.aspx?radiofxview=true%@", extra]];
    [m_searchview OpenConfigUrl:[NSURLRequest requestWithURL:u]];
}
- (void)OpenHintUrl {
    NSArray *p = [self SerialParts];
    NSString *site = ([p count] >= 2) ? [NSString stringWithFormat:@"%@-%@", [p objectAtIndex:0], [p objectAtIndex:1]] : @"";
    NSString *s = [NSString stringWithFormat:@"http://www.tobit.com/rfx-cloud1dev/dev/Index.aspx?radiofxview=true&page=Empfehlungen.aspx&siteid=%@&vintern=%i&id=%@", site, [DEL GetVIntern], [DEL GetUID]];
    [m_searchview OpenHintUrl:[NSURLRequest requestWithURL:[NSURL URLWithString:s]]];
}
- (void)OpenFBWallUrl {
    NSArray *p = [self SerialParts];
    NSString *dev = ([p count] >= 2) ? [NSString stringWithFormat:@"%@-%@", [p objectAtIndex:0], [p objectAtIndex:1]] : @"";
    NSString *pw = ([p count] >= 3) ? [p objectAtIndex:2] : @"";
    NSString *s = [NSString stringWithFormat:@"http://www.tobit.com/rfx-cloud1/djukeboxFacebookWall/?dId=%@&pw=%@", dev, pw];
    [m_searchview OpenFBWallUrl:[NSURLRequest requestWithURL:[NSURL URLWithString:s]]];
}
@end
