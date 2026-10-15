// KeyboardView : UIView -- decompiled from Radiofx_iPad (armv7), ported to arm64 / modern iOS.  Manual reference counting.
#import "KeyboardView.h"
#import "RfxCrashLog.h"
#import "GLView.h"
#import "KioskView.h"
#import "RadioAppDelegate.h"
#import "DBOperations.h"
#import "FolderObject.h"
#import "ClipObject.h"
#import "ServerEntry.h"
#import "FMDatabase.h"
#import "FMResultSet.h"
#import "SImage.h"
#import "SLabel.h"
#import "Globals.h"
#import <QuartzCore/QuartzCore.h>

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])
#define ISIPAD ([DEL m_isipad])

static int gv_tablefadetag = 0;   // original data_0034f610 (only used by the removed table cross-fade)

BOOL gRfxPlayNow = NO;

@implementation KeyboardView

@synthesize m_draggingvolume, m_srarrayother, m_keyboardinittime, m_gotooverview, m_xfield, m_showwhat, m_searchlabel, m_keyboardshown;

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self KBVEndFunction];
    [super dealloc];
}

- (void)KBVEndFunction {
    [self setM_keyboardinittime:-1.0];
    if (m_srarray != nil) {
        [m_srarray release];
        m_srarray = nil;
    }
    if (m_srarrayplugin != nil) { [m_srarrayplugin release]; m_srarrayplugin = nil; }
    [m_srprogname release]; m_srprogname = nil;
    [m_srprogid release]; m_srprogid = nil;
    [m_srshown release]; m_srshown = nil;
    if (m_srarrayother != nil) {
        [m_srarrayother release];
        m_srarrayother = nil;
    }
    if (m_srlock != nil) {
        [m_srlock release];
        m_srlock = nil;
    }
}

- (void)EmptySearchfield {
    m_cursoroff = 0;
    [[self m_searchlabel] setText:@""];
    [m_xfield setHidden:YES];
}

- (void)FitSubViews:(CGSize)fitSubViews {
    CGRect r;
    r = [self GetKBPicFrame:fitSubViews];
    [m_keyboardpic setFrame:r];
    r = [self GetTextfieldFrame:fitSubViews];
    [[self m_searchlabel] setFrame:r];
    r = [self GetXFieldFrame];
    [m_xfield setFrame:r];
    r = [self GetCollectionnameFrame:fitSubViews];
    [m_collectionnamelabel setFrame:r];
    r = [self GetFoundItemsFrame:fitSubViews];
    [m_founditemslabel setFrame:r];
    r = [self GetCollectionIconFrame:fitSubViews];
    [m_collectionicon setFrame:r];
    r = [self GetSearchScrollerBGFrame:fitSubViews];
    [m_srbgview setFrame:r];
    r = [self GetSearchScrollerFrame:fitSubViews];
    [m_srtableview setFrame:r];
    m_backspacerect = [self GetBackspaceRect:fitSubViews];
    [self LayoutBackspaceButton];
    [self FitVolumeElements:fitSubViews];
    r = [self GetNoNewTitlesFrame:fitSubViews];
    [m_nonewtitles setFrame:r];
    [self RestartKeyboardtimer];
    [self SetCursorFrame];
    [self LayoutPanels];
}

- (void)FitVolumeElements:(CGSize)fitVolumeElements {
    CGRect r = [self GetSliderBGFrame:fitVolumeElements];
    [m_sliderbackground setFrame:r];
    if (m_volslider != nil) {
        r = [self GetSliderFrame:fitVolumeElements];
        [m_volslider setFrame:r];
    }
    if (m_voloverlay != nil) {
        if ([DEL m_useownvolume] == 0) {
            r = [self GetVolOverlayFrame:fitVolumeElements];
            [m_voloverlay setFrame:r];
        }
    }
}

- (void)touchesEnded:(NSSet *)touchesEnded withEvent:(UIEvent *)event {
    if ([m_parent m_movingup]) return;
    for (UITouch *touch in touchesEnded) {
        CGPoint p = [touch locationInView:self];
        if (m_showwhat == 4) continue;
        CGSize sz = [DEL GetiPadSize];
        CGRect hit = CGRectZero;
        switch (m_showwhat) {
            case 0:
                hit = [self GetSliderBGFrame:sz];
                break;
            case 2: {
                // keyboard picture plus the result area below it
                CGRect kb = [self GetKBPicFrame:sz];
                CGRect bg = [self GetSearchScrollerBGFrame:sz];
                hit = CGRectUnion(kb, bg);
                break;
            }
            default:
                break;
        }
        if (CGRectContainsPoint(hit, p)) continue;
        [m_parent setM_movingup:YES];
        [m_parent performSelector:@selector(ToggleKBAndRegister:) withObject:[NSNumber numberWithInt:[self m_showwhat]] afterDelay:0.1];
        return;
    }
}

- (void)touchesMoved:(NSSet *)touchesMoved withEvent:(UIEvent *)event {
}

// the search is over: no text, no results, no running search
- (void)ClearSearchAll {
    m_cursoroff = 0;
    [self EmptySearchfield];
    [self SetCursorFrame];
    [m_srlock lock];
    [m_srarray removeAllObjects];
    [m_srarrayother removeAllObjects];
    [m_srarrayplugin removeAllObjects];
    [m_srlock unlock];
    [m_srtableview reloadData];
    [[RfxPluginManager shared] SearchText:@"" done:nil];
}

- (void)DeleteSearchText30Sec {
    // DEVIATION: the original cleared the search text 30 s after the last key.  The text and the results now stay until
    // the user clears them, also after the window was closed and opened again.
    return;
    if ([[self m_searchlabel] text] != nil) {
        if ([[[self m_searchlabel] text] length] != 0) {
            [[self m_searchlabel] setText:@""];
            if ([m_parent IsShowingMTScroller]) {
                [m_parent BeginSearchInMTScroller:[[self m_searchlabel] text]];
            } else {
                [m_parent BeginSearch:[[self m_searchlabel] text]];
            }
            [[m_pkiosk m_glv] performSelector:@selector(ReInitThread) withObject:nil afterDelay:0.1];
        }
    }
}

- (void)touchesBegan:(NSSet *)touchesBegan withEvent:(UIEvent *)event {
    NSString *textBefore = [NSString stringWithFormat:@"%@", [[self m_searchlabel] text]];
    CGSize sz = [DEL GetiPadSize];
    [[m_pkiosk m_glv] RestartIdleTimer];
    [[m_pkiosk m_glv] RestartAdvertTimer];
    [m_pkiosk Restart30secsearchTimer];
    if ([[m_pkiosk m_glv] m_pinchstatus] == 2) {
        [[m_pkiosk m_glv] ForwardRestartOverviewTimer];
    }
    BOOL portrait = (sz.width <= sz.height);
    for (UITouch *touch in touchesBegan) {
        CGPoint p = [touch locationInView:self];
        if (![m_xfield isHidden]) {
            CGRect xf = [m_xfield frame];
            if (CGRectContainsPoint(CGRectMake(xf.origin.x - 5.0f, xf.origin.y - 12.0f, xf.size.width + 8.0f, xf.size.height + 15.0f), p)) {
                m_cursoroff = 0;
                [[self m_searchlabel] setText:@""];
                [m_xfield setHidden:YES];
                [self SetCursorFrame];
                break;
            }
        }
        if (m_showwhat == 0) break;
        if (m_showwhat != 2) {
            if (m_showwhat == 3) break;
            continue;
        }
        if ([m_collectionicon image] != nil) {
            if (CGRectContainsPoint([m_collectionicon frame], p)) {
                if ([[m_pkiosk m_glv] m_pinchstatus] == 0) {
                    m_gotooverview = YES;
                    [[m_pkiosk m_glv] performSelector:@selector(ToggleKBAndRegister:) withObject:[NSNumber numberWithInt:m_showwhat] afterDelay:0.01];
                    return;
                }
            }
        }
        {   // tap into the search text: moves the cursor to the nearest letter boundary
            CGRect lf = [[self m_searchlabel] frame];
            NSString *tx = [[self m_searchlabel] text];
            if ([tx length] > 0 && p.x >= lf.origin.x - 4.0f && p.x <= lf.origin.x + lf.size.width + 4.0f && p.y >= lf.origin.y - 4.0f && p.y <= lf.origin.y + lf.size.height + 4.0f) {
                NSDictionary *fa = [NSDictionary dictionaryWithObject:[[self m_searchlabel] font] forKey:NSFontAttributeName];
                float rel = p.x - lf.origin.x, bestd = 1e9f; int best = (int)[tx length];
                for (int i = 0; i <= (int)[tx length]; i++) {
                    float wx = [[tx substringToIndex:i] sizeWithAttributes:fa].width;
                    if (fabsf(wx - rel) < bestd) { bestd = fabsf(wx - rel); best = i; }
                }
                m_cursoroff = (int)[tx length] - best;
                [self SetCursorFrame];
                [self RestartKeyboardtimer];
                break;
            }
        }
        // hit test of the keys in the keyboard picture
        float yoff = ([[m_nonewtitles text] length] == 0) ? 0.0f : 50.0f;
        CGRect kbf = [m_keyboardpic frame];
        float left, right, top, bottom, keyw;
        if (portrait) {
            left = (float)(int)(kbf.origin.x + 13.0f);
            right = left + 583.0f;
            keyw = 42.0f;
            top = (float)(int)(kbf.origin.y + 52.0f + yoff);
            bottom = (float)(int)(kbf.origin.y + 135.0f + yoff);
        } else {
            left = (float)(int)(kbf.origin.x + 10.0f);
            right = left + 893.0f;
            keyw = 47.0f;
            top = (float)(int)(kbf.origin.y + 51.0f + yoff);
            bottom = (float)(int)(kbf.origin.y + 140.0f + yoff);
        }
        BOOL inKeys = !(p.x < left || p.x > right || p.y < top || p.y > bottom);
        if (inKeys) {
            int col = (int)((p.x - left) / keyw);
            int row, idx;
            if (!portrait) {
                int h2 = (int)(bottom - top);
                h2 = (h2 + (h2 >> 31)) >> 1;
                row = (int)((p.y - top) / (float)h2);
                idx = 19 * row + col;
            } else {
                row = (int)((p.y - top) / 42.0f);
                idx = row * 14 + col;
            }
            if (idx != -1) {
                char c;
                if ((unsigned)(idx - 0x1a) < 2u) {
                    c = ' ';
                } else {
                    c = (char)((((unsigned)(idx - 0x1c) < 10u) ? 0x14 : 0x41) + idx);
                }
                NSString *cur0 = [[self m_searchlabel] text] ? [[self m_searchlabel] text] : @"";
                if (m_cursoroff > (int)[cur0 length]) m_cursoroff = (int)[cur0 length];
                int at0 = (int)[cur0 length] - m_cursoroff;
                NSString *nt = [NSString stringWithFormat:@"%@%c%@", [cur0 substringToIndex:at0], c, [cur0 substringFromIndex:at0]];
                [[self m_searchlabel] setText:nt];
                [self SetCursorFrame];
                if ([[self m_searchlabel] text] == nil || [[[self m_searchlabel] text] length] == 0) {
                    [m_pkiosk setM_30secsearchInitTime:-1.0];
                } else {
                    [m_pkiosk setM_30secsearchInitTime:CACurrentMediaTime()];
                }
                break;
            }
        }
        // backspace
        // the key picture is shifted down by 50 when the "no new titles" line is showing, so the backspace key is
        // tested at both heights, with the current frame and a little tolerance
        CGRect bsr = CGRectInset([self GetBackspaceRect:sz], -2.0f, -2.0f);
        if (CGRectContainsPoint(bsr, p)) {
            NSString *cur1 = [[self m_searchlabel] text];
            if ([cur1 length] == 0) break;
            [[self m_searchlabel] setText:[self TextWithoutCharBeforeCursor:cur1]];
            [self SetCursorFrame];
            break;
        }
    }
    if (m_showwhat == 2) {
        NSUInteger len = [[[self m_searchlabel] text] length];
        [m_xfield setHidden:(len == 0)];
        if (![textBefore isEqualToString:[[self m_searchlabel] text]]) {
            [m_parent BeginSearch:[[self m_searchlabel] text]];
            [self RestartKeyboardtimer];
        }
    }
}

// Progress of the plugin search: the header of the source's section ("Qobuz") is the bar itself - a fill grows behind
// the header text.  fraction < 0 ends it.  Nothing else in the window shows progress.
- (void)SetSearchProgress:(float)fraction label:(NSString *)label {
    [self SetSearchProgress:fraction label:label pluginId:nil];
}

- (void)SetSearchProgress:(float)fraction label:(NSString *)label pluginId:(NSString *)pid {
    BOOL wasVisible = (m_srprog >= 0.0f);
    if (fraction < 0.0f) {
        m_srprog = -1.0f;
        if (wasVisible) [m_srtableview reloadData];
        return;
    }
    if (fraction > 1.0f) fraction = 1.0f;
    if (label != nil) { [m_srprogname release]; m_srprogname = [[[label componentsSeparatedByString:@" ("] objectAtIndex:0] copy]; }
    if (pid != nil) { [m_srprogid release]; m_srprogid = [pid copy]; }
    m_srprog = fraction;
    if (!wasVisible && [m_srarrayplugin count] == 0) {      // the section appears with its header
        [m_srtableview reloadData];
        return;
    }
    UIView *fill = [m_srtableview viewWithTag:7791];
    if (fill != nil && [fill superview] != nil) {
        float w = [[fill superview] bounds].size.width * fraction;
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
            [fill setFrame:CGRectMake(0, 0, w, [[fill superview] bounds].size.height)];
        } completion:nil];
    }
}

// Covers arrive one by one: the visible thumbnails of the source section are swapped with a cross dissolve, without
// reloading the table (a reload cut running fades short, which looked like popping).
- (void)ReloadResults {
    if (m_srreloadpending) return;
    m_srreloadpending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        m_srreloadpending = NO;
        if (m_srshown == nil) m_srshown = [[NSMutableDictionary alloc] init];
        for (UITableViewCell *cell in [m_srtableview visibleCells]) {
            for (int c = 0; c < 6; c++) {
                SImage *img = (SImage *)[cell viewWithTag:c + 100];
                if (img == nil || [img m_section] != 2 || [img m_id] == -1) continue;
                ClipObject *co = nil;
                [m_srlock lock];
                for (ClipObject *o in m_srarrayplugin) if ([o ID] == [img m_id]) { co = [[o retain] autorelease]; break; }
                [m_srlock unlock];
                if (co == nil || [co m_picturepath] == nil) continue;
                NSDate *mod = [[[NSFileManager defaultManager] attributesOfItemAtPath:[DEL BuildSmallPicpath:[co m_picturepath]] error:nil] fileModificationDate];
                NSNumber *key = [NSNumber numberWithLongLong:[co ID]];
                if (mod == nil || [mod isEqualToDate:[m_srshown objectForKey:key]]) continue;
                UIImage *ni = [m_pkiosk GetSmallImage:co];
                if (ni == nil) continue;
                [m_srshown setObject:mod forKey:key];
                [UIView transitionWithView:img duration:0.6 options:(UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction)
                                animations:^{ [img setImage:ni]; } completion:nil];
            }
        }
    });
}

// full reload (a source icon arrived)
- (void)ReloadAll {
    [m_srtableview reloadData];
}

// transparent button over the backspace key: works whatever else is going on in the window (search running, bars shown)
- (void)BackspacePressed {
    NSString *cur = [[self m_searchlabel] text];
    if ([cur length] == 0) return;
    [[self m_searchlabel] setText:[self TextWithoutCharBeforeCursor:cur]];
    [self SetCursorFrame];
    [m_xfield setHidden:([[[self m_searchlabel] text] length] == 0)];
    [m_parent BeginSearch:[[self m_searchlabel] text]];
    [self RestartKeyboardtimer];
}

- (void)LayoutBackspaceButton {
    if (m_showwhat != 2) { [[self viewWithTag:7790] setHidden:YES]; return; }
    CGSize sz = [DEL GetiPadSize];
    UIButton *b = (UIButton *)[self viewWithTag:7790];
    if (b == nil) {
        b = [UIButton buttonWithType:UIButtonTypeCustom];
        [b setTag:7790];
        [b setBackgroundColor:[UIColor clearColor]];
        [b addTarget:self action:@selector(BackspacePressed) forControlEvents:UIControlEventTouchDown];
        [self addSubview:b];
    }
    CGRect r = CGRectInset([self GetBackspaceRect:sz], -2.0f, -2.0f);   // stays clear of the clear-all (X) field
    [b setFrame:r];
    [b setHidden:NO];
    [self bringSubviewToFront:b];
}

- (void)ShowElements:(int)elements {
    [self HideAll];
    switch (elements) {
        case 0:
            [m_sliderbackground setHidden:NO];
            if (m_volslider != nil) [m_volslider setHidden:NO];
            if (m_voloverlay != nil) [m_voloverlay setHidden:NO];
            break;
        case 1: [m_wdrview setHidden:NO]; break;
        case 3: [m_onoffview setHidden:NO]; break;
        case 7: [self ResetupVideoView]; [m_videoview setHidden:NO]; break;
        case 6: [m_webview setHidden:NO]; [self LayoutPanels]; break;
        case 8: [m_hintwebview setHidden:NO]; [self LayoutPanels]; break;
        case 9: [m_FBwebview setHidden:NO]; [self LayoutPanels]; break;
        case 5:
            break;
        case 2: {
            double last = [[NSUserDefaults standardUserDefaults] doubleForKey:@"keylastcopiedsong"];
            if (last <= 0) {
                [m_nonewtitles setText:@""];
            } else {
                double now = (double)time(NULL);
                if ((now - last) <= 345600.0) {
                    [m_nonewtitles setText:@""];
                } else {
                    int days = (int)((now - last) / 86400.0);
                    if (days < 0) days = 0;
                    if (days > 1000) days = 1000;
                    [m_nonewtitles setText:[NSString stringWithFormat:@"Keine neuen Titel seit %i Tagen!", days]];
                    [m_nonewtitles setHidden:NO];
                }
            }
            if (ISIPAD) {
                [m_searchlabel setHidden:NO];
                [m_keyboardpic setHidden:NO];
                [m_collectionnamelabel setHidden:NO];
                [m_founditemslabel setHidden:NO];
                [m_collectionicon setHidden:NO];
            }
            [m_srtableview setHidden:NO];
            [m_srbgview setHidden:NO];
            BOOL hideX;
            if (!ISIPAD) hideX = YES;
            else if ([[self m_searchlabel] text] == nil) hideX = YES;
            else hideX = ([[[self m_searchlabel] text] length] == 0);
            [m_xfield setHidden:hideX];
            CGSize sz = [DEL GetiPadSize];
            CGRect r = [self GetKBPicFrame:sz];
            [m_keyboardpic setFrame:r];
            r = [self GetSearchScrollerBGFrame:sz];
            [m_srbgview setFrame:r];
            r = [self GetSearchScrollerFrame:sz];
            [m_srtableview setFrame:r];
            r = [self GetNoNewTitlesFrame:sz];
            [m_nonewtitles setFrame:r];
            [self LayoutBackspaceButton];
            break;
        }
        default:
            break;
    }
}

- (void)HideAll {
    [m_sliderbackground setHidden:YES];
    if (m_volslider != nil) [m_volslider setHidden:YES];
    if (m_voloverlay != nil) [m_voloverlay setHidden:YES];
    [m_searchlabel setHidden:YES];
    [m_keyboardpic setHidden:YES];
    [m_xfield setHidden:YES];
    [m_srtableview setHidden:YES];
    [m_srbgview setHidden:YES];
    [m_collectionnamelabel setHidden:YES];
    [m_founditemslabel setHidden:YES];
    [m_collectionicon setHidden:YES];
    [m_nonewtitles setHidden:YES];
    [m_wdrview setHidden:YES];
    [m_onoffview setHidden:YES];
    [m_videoview setHidden:YES];
    [m_webview setHidden:YES];
    [m_hintwebview setHidden:YES];
    [m_FBwebview setHidden:YES];
    [m_weblabel setHidden:YES];
}

- (void)ForwardKioskPointer:(KioskView *)forwardKioskPointer {
    m_pkiosk = forwardKioskPointer;
    [m_wdrview SetKioskPointer:forwardKioskPointer];
    [m_onoffview SetKioskPointer:forwardKioskPointer];
    [m_videoview SetKioskPointer:forwardKioskPointer];
    if (m_volslider != nil) {
        [m_volslider setValue:[m_pkiosk m_lastvolume] animated:NO];
    }
}

- (void)volSliderTouchUp:(id)volSliderTouchUp {
    [self setM_keyboardinittime:(CACurrentMediaTime() - 8.5)];
    [self setM_draggingvolume:NO];
    [m_pkiosk SetLastVolumeKiosk];
}

- (void)volSliderDown:(id)volSliderDown {
    [self StopKeyboardtimer];
    [self setM_draggingvolume:YES];
}

- (void)volSliderAction:(id)volSliderAction {
    float v = [(UISlider *)volSliderAction value];
    [m_pkiosk setM_lastvolume:v];
    [m_pkiosk SetPlayerVolume:v];
}

- (void)SetFoundItemsLabelText:(NSNotification *)foundItemsLabelText {
    NSDictionary *d = [foundItemsLabelText object];
    NSString *left = [d objectForKey:@"left"];
    NSString *right = [d objectForKey:@"right"];
    [m_collectionnamelabel setText:left];
    [m_founditemslabel setText:right];
    [m_collectionicon setImage:([right length] != 0) ? [UIImage imageNamed:@"kollektion.png"] : nil];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        m_keyboardshown = NO;
        m_parent = nil;
        CGSize sz = [DEL GetiPadSize];
        m_keyboardinittime = -1.0;
        m_showwhat = -1;
        m_cursortimer = nil;
        m_draggingvolume = NO;
        m_srpicthreadstarted[0] = m_srpicthreadstarted[1] = NO;
        m_resortflag[0] = m_resortflag[1] = YES;
        m_gotooverview = NO;
        UIColor *darkgray = [UIColor colorWithWhite:0.251f alpha:1.0f];
        m_srlock = [[NSLock alloc] init];
        [self setBackgroundColor:[UIColor clearColor]];
        [self SetKBBackGroundPic:sz];
        m_backspacerect = [self GetBackspaceRect:sz];

        CGRect r = [self GetSliderBGFrame:sz];
        m_sliderbackground = [[UIView alloc] initWithFrame:r];
        [m_sliderbackground setBackgroundColor:darkgray];
        [self addSubview:m_sliderbackground];
        [m_sliderbackground release];
        m_voloverlay = nil;
        m_volslider = nil;
        [self InstallVolumeSlider:sz];

        r = [self GetTextfieldFrame:sz];
        m_searchlabel = [[UILabel alloc] initWithFrame:r];
        [self addSubview:m_searchlabel];
        [m_searchlabel setBackgroundColor:[UIColor clearColor]];
        [m_searchlabel setTextColor:[UIColor colorWithWhite:0.784f alpha:1.0f]];
        [m_searchlabel setFont:[UIFont boldSystemFontOfSize:21.0f]];
        [m_searchlabel setText:@""];
        [m_searchlabel release];

        UIColor *gray4 = [UIColor colorWithWhite:0.4f alpha:1.0f];
        UIColor *shadow = [UIColor colorWithWhite:0.078f alpha:1.0f];
        r = [self GetCollectionnameFrame:sz];
        m_collectionnamelabel = [[UILabel alloc] initWithFrame:r];
        [self addSubview:m_collectionnamelabel];
        [m_collectionnamelabel setBackgroundColor:[UIColor clearColor]];
        [m_collectionnamelabel setTextColor:gray4];
        [m_collectionnamelabel setTextAlignment:NSTextAlignmentLeft];
        [m_collectionnamelabel release];
        [m_collectionnamelabel setFont:[UIFont boldSystemFontOfSize:14.0f]];
        [m_collectionnamelabel setShadowColor:shadow];
        [m_collectionnamelabel setShadowOffset:CGSizeMake(0, -1)];

        r = [self GetFoundItemsFrame:sz];
        m_founditemslabel = [[UILabel alloc] initWithFrame:r];
        [self addSubview:m_founditemslabel];
        [m_founditemslabel setBackgroundColor:[UIColor clearColor]];
        [m_founditemslabel setTextColor:gray4];
        [m_founditemslabel setTextAlignment:NSTextAlignmentRight];
        [m_founditemslabel release];
        [m_founditemslabel setFont:[UIFont boldSystemFontOfSize:14.0f]];
        [m_founditemslabel setShadowColor:shadow];
        [m_founditemslabel setShadowOffset:CGSizeMake(0, -1)];

        r = [self GetCollectionIconFrame:sz];
        m_collectionicon = [[UIImageView alloc] initWithFrame:r];
        [self addSubview:m_collectionicon];
        [m_collectionicon release];

        m_cursorview = [[UIView alloc] initWithFrame:CGRectZero];
        [m_cursorview setHidden:YES];
        [m_cursorview setBackgroundColor:[m_searchlabel textColor]];
        [m_cursorview setAlpha:0.0f];
        [m_cursorview setUserInteractionEnabled:NO];
        [self addSubview:m_cursorview];
        [m_cursorview release];

        r = [self GetXFieldFrame];
        m_xfield = [[UIImageView alloc] initWithFrame:r];
        [m_xfield setHidden:YES];
        [m_xfield setImage:[UIImage imageNamed:@"textfeld-x.png"]];
        [self addSubview:m_xfield];
        [m_xfield release];

        m_srarray = [[NSMutableArray alloc] init];
        m_srarrayother = [[NSMutableArray alloc] init];
        m_srarrayplugin = [[NSMutableArray alloc] init];
        m_srprog = -1.0f;
        m_srbgview = [[UIView alloc] initWithFrame:CGRectZero];
        [self addSubview:m_srbgview];
        [m_srbgview setBackgroundColor:darkgray];
        [m_srbgview release];

        m_srtableview = [[UITableView alloc] initWithFrame:CGRectZero];
        [self addSubview:m_srtableview];
        [m_srtableview release];
        [m_srtableview setDelegate:self];
        [m_srtableview setDataSource:self];
        [m_srtableview setAllowsSelection:NO];
        // port: taps are resolved from the touch position (row + column), not from the cell subviews
        UITapGestureRecognizer *srtap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(SRTapped:)];
        [srtap setCancelsTouchesInView:NO];
        [m_srtableview addGestureRecognizer:srtap];
        [srtap release];
        [m_srtableview setSeparatorStyle:UITableViewCellSeparatorStyleNone];
        [m_srtableview setBackgroundColor:darkgray];

        m_nonewtitles = [[UILabel alloc] initWithFrame:CGRectZero];
        [self addSubview:m_nonewtitles];
        [m_nonewtitles release];
        [m_nonewtitles setHidden:YES];
        [m_nonewtitles setTextAlignment:NSTextAlignmentCenter];
        [m_nonewtitles setBackgroundColor:[UIColor clearColor]];
        [m_nonewtitles setTextColor:[UIColor colorWithRed:0.65f green:0.65f blue:0.65f alpha:1.0f]];
        [m_nonewtitles setFont:[UIFont boldSystemFontOfSize:20.0f]];

        // ---- panels of registers 1, 3, 6, 7, 8, 9 (restored; they show their native content without a back-end)
        m_wdrview = [[MenuView alloc] initWithFrame:CGRectMake(0, 910, 330, 90)];
        [self addSubview:m_wdrview]; [m_wdrview release];
        [m_wdrview setBackgroundColor:darkgray];
        [m_wdrview Setup:0]; [m_wdrview SetParent:self];
        m_onoffview = [[MenuView alloc] initWithFrame:CGRectMake(0, 772, 220, 228)];
        [self addSubview:m_onoffview]; [m_onoffview release];
        [m_onoffview setBackgroundColor:darkgray];
        [m_onoffview Setup:1]; [m_onoffview SetParent:self];
        m_videoview = [[MenuView alloc] initWithFrame:CGRectMake(0, 688, 220, 312)];
        [self addSubview:m_videoview]; [m_videoview release];
        [m_videoview setBackgroundColor:darkgray];
        [m_videoview Setup:2]; [m_videoview SetParent:self];
        UIWebView **wv[3] = { &m_webview, &m_hintwebview, &m_FBwebview };
        for (int i = 0; i < 3; i++) {
            *wv[i] = [[UIWebView alloc] initWithFrame:CGRectMake(0, 315, 760, 685)];
            [self addSubview:*wv[i]]; [*wv[i] release];
            [*wv[i] setDelegate:self];
            [*wv[i] setBackgroundColor:[UIColor blackColor]];
            [*wv[i] setOpaque:NO];
            [*wv[i] setHidden:YES];
        }
        progView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        [progView setHidden:YES];
        [self addSubview:progView]; [progView release];
        m_weblabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 600, 120)];
        [m_weblabel setNumberOfLines:0];
        [m_weblabel setTextAlignment:NSTextAlignmentCenter];
        [m_weblabel setBackgroundColor:[UIColor clearColor]];
        [m_weblabel setTextColor:[UIColor colorWithWhite:0.55f alpha:1.0f]];
        [m_weblabel setFont:[UIFont boldSystemFontOfSize:18.0f]];
        [m_weblabel setHidden:YES];
        [self addSubview:m_weblabel]; [m_weblabel release];

        [self ShowElements:1];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(SetFoundItemsLabelText:) name:@"MsgTextFoundItemsLabel" object:nil];
    }
    return self;
}

- (void)InstallVolumeSlider:(CGSize)installVolumeSlider {
    if (m_voloverlay != nil) {
        [m_voloverlay removeFromSuperview];
        m_voloverlay = nil;
    }
    if ([DEL m_useownvolume] != 0) {
        if (m_volslider != nil) {
            [m_volslider removeFromSuperview];
            m_volslider = nil;
        }
        [m_pkiosk setM_lastvolume:1.0f];
        [m_pkiosk SetPlayerVolume:[m_pkiosk m_lastvolume]];
    } else if (m_volslider == nil) {
        CGRect r = [self GetSliderFrame:installVolumeSlider];
        m_volslider = [[UISlider alloc] initWithFrame:r];
        [m_volslider setMinimumValue:0.0f];
        [m_volslider setMaximumValue:1.0f];
        [self SetImagesOnSlider:m_volslider];
        [self addSubview:m_volslider];
        [m_volslider release];
        [m_volslider addTarget:self action:@selector(volSliderAction:) forControlEvents:UIControlEventValueChanged];
        [m_volslider addTarget:self action:@selector(volSliderDown:) forControlEvents:UIControlEventTouchDown];
        [m_volslider addTarget:self action:@selector(volSliderTouchUp:) forControlEvents:UIControlEventTouchUpInside];
        [m_volslider addTarget:self action:@selector(volSliderTouchUp:) forControlEvents:UIControlEventTouchUpOutside];
    }
    CGRect ov = [self GetVolOverlayFrame:installVolumeSlider];
    m_voloverlay = [[UIImageView alloc] initWithFrame:ov];
    [m_voloverlay setHidden:YES];
    [m_volslider setUserInteractionEnabled:YES];
    [m_voloverlay setImage:[DEL CreateStretchedImage:nil withImage:[DEL NonCachedImage:@"volume-overlay"] withLeftCap:12.0f withTopCap:0.0f withInvert:NO]];
    if ([DEL m_useownvolume] != 0) {
        [m_sliderbackground addSubview:m_voloverlay];
    } else {
        [self addSubview:m_voloverlay];
    }
    [m_voloverlay release];
}

- (void)StopKeyboardtimer {
    [self setM_keyboardinittime:-1.0];
}

- (void)SetElementpositions {
    CGSize sz = [DEL GetiPadSize];
    CGRect r = [self GetTextfieldFrame:sz];
    [m_searchlabel setFrame:r];
    m_backspacerect = [self GetBackspaceRect:sz];
    r = [self GetXFieldFrame];
    [m_xfield setFrame:r];
}

- (void)SetKBBackGroundPic:(CGSize)kBBackGroundPic {
    if (m_keyboardpic == nil) {
        CGRect r = [self GetKBPicFrame:kBBackGroundPic];
        m_keyboardpic = [[UIImageView alloc] initWithFrame:r];
        [self addSubview:m_keyboardpic];
        [m_keyboardpic release];
    }
    [m_keyboardpic setImage:[DEL CreateStretchedImage:(kBBackGroundPic.width > kBBackGroundPic.height ? @"hintergrund-tastatur.png" : @"hintergrund-tastatur-vert.png") withImage:nil withLeftCap:0.0f withTopCap:46.0f withInvert:NO]];
}

- (void)RestartKeyboardtimerFast {
    [self setM_keyboardinittime:(CACurrentMediaTime() - 8.5)];
}

- (void)RestartKeyboardtimer {
    [self setM_keyboardinittime:CACurrentMediaTime()];
}

- (void)KBTimerFunc {
    if (!m_keyboardshown) return;
    [m_parent ToggleKBAndRegister:[NSNumber numberWithInt:m_showwhat]];
}

#pragma mark - search result table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self getNumberOfRowsInSection:[self LogicalSection:section]];
}

- (void)SRTapped:(UITapGestureRecognizer *)g {
    RfxCrumb("SRTapped begin");
    if ([g state] != UIGestureRecognizerStateEnded) return;
    CGPoint p = [g locationInView:m_srtableview];
    NSIndexPath *ip = [m_srtableview indexPathForRowAtPoint:p];
    if (ip == nil) { [RfxPluginManager Toast:@"Tipp neben die Liste."]; return; }
    RfxCrumb("SRTapped indexpath");
    int section = [self LogicalSection:[ip section]];
    int row = (int)[ip row];
    NSMutableArray *src = [self SRArray:section];
    int count = (src != nil) ? (int)[src count] : 0;
    int rows = 0, cols = 0;
    RfxCrumb("SRTapped matrix");
    [self GetTableMatrix:count withitemsincolum:&rows withcolumcount:&cols];
    if (cols < 1) return;
    int colw = (int)([m_srtableview frame].size.width / (float)cols);
    int col = (colw > 0) ? (int)(p.x / (float)colw) : 0;
    if (col >= cols) col = cols - 1;
    int idx = row + rows * col;
    if (idx < 0 || idx >= count) { [RfxPluginManager Toast:[NSString stringWithFormat:@"Leeres Feld (Liste %d, Eintrag %d von %d).", section, idx, count]]; return; }
    RfxCrumb("SRTapped -> AddItem");
    [self AddItemFromSearchList:idx withsection:section withdirectClipObject:nil];
    RfxCrumb("SRTapped done");
}

- (void)SRPictureThread:(NSNumber *)sRPictureThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    long long folderid = [[m_pkiosk m_glv] m_selectedfolderid];
    long long ipodid = [[m_pkiosk m_glv] m_selectedipodid];
    int section = [sRPictureThread intValue];
    [NSThread setThreadPriority:0.4];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *arr = [self GetReSortedArray:section];
    for (unsigned i = 0; i < [arr count]; i++) {
        if (![self m_keyboardshown]) break;
        if ([DEL g_end] || gv_kioskflag) break;
        if ([[m_pkiosk m_glv] m_selectedfolderid] != folderid) break;
        if ([[m_pkiosk m_glv] m_selectedipodid] != ipodid) break;
        if (m_resortflag[section]) {
            m_resortflag[section] = NO;
            [arr release];
            arr = [self GetReSortedArray:section];
        }
        if ([arr count] == 0) break;
        if (i >= [arr count]) break;
        ClipObject *co = [arr objectAtIndex:i];
        if ([co m_picturepath] != nil) {
            NSString *small = [DEL BuildSmallPicpath:[co m_picturepath]];
            if ([fm fileExistsAtPath:small]) continue;
        }
        NSAutoreleasePool *p2 = [[NSAutoreleasePool alloc] init];
        [m_pkiosk CreateSmallPic:[m_pkiosk GetSongImage:nil withclipobject:co] withClipObject:co];
        [p2 release];
        if (![self m_keyboardshown]) break;
        if ([DEL g_end] || gv_kioskflag) break;
        if ([[m_pkiosk m_glv] m_selectedfolderid] != folderid) break;
        if ([[m_pkiosk m_glv] m_selectedipodid] != ipodid) break;
        [m_srlock lock];
        NSMutableArray *src = [self SRArray:section];
        int found = -1;
        for (int k = 0; k < (int)[src count]; k++) {
            ClipObject *o = [src objectAtIndex:k];
            if ([o ID] != [co ID]) continue;
            if ([o m_ipodid] != [co m_ipodid]) continue;
            if ([o m_serverid] != [co m_serverid]) continue;
            found = k;
            break;
        }
        [m_srlock unlock];
        if (found == -1) {
            [NSThread sleepForTimeInterval:0.01];
            continue;
        }
        if (![self m_keyboardshown]) break;
        if ([DEL g_end] || gv_kioskflag) break;
        if ([[m_pkiosk m_glv] m_selectedfolderid] != folderid) break;
        if ([[m_pkiosk m_glv] m_selectedipodid] != ipodid) break;
        [m_srtableview performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
        [NSThread sleepForTimeInterval:0.01];
    }
    [arr release];
    [[[m_pkiosk m_glv] GetKBView] SetPicThreadStarted:section withval:NO];
    [pool release];
}

// +1: rows of the result grid in reading order (top rows first), then (section 0) the rest of the folder
- (NSMutableArray *)GetReSortedArray:(int)reSortedArray {
    NSMutableArray *out = [[NSMutableArray alloc] init];
    NSMutableArray *src = [self SRArray:reSortedArray];
    [m_srlock lock];
    int count = (int)[src count];
    int rows = 0, cols = 0;
    [self GetTableMatrix:count withitemsincolum:&rows withcolumcount:&cols];
    for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
            int idx = r + rows * c;
            if (idx < count) [out addObject:[src objectAtIndex:idx]];
        }
    }
    [m_srlock unlock];
    if (reSortedArray == 0) {
        [[m_pkiosk m_glv] GetArrayLock:YES];
        [out addObjectsFromArray:[[m_pkiosk m_glv] m_origarray]];
        [[m_pkiosk m_glv] releaseArraylock];
    }
    return out;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGSize sz = [DEL GetiPadSize];
    int section = [self LogicalSection:[indexPath section]];
    NSMutableArray *src = [self SRArray:section];
    [m_srlock lock];
    int count = (int)[src count];
    [m_srlock unlock];
    int rows = 0, cols = 0;
    [self GetTableMatrix:count withitemsincolum:&rows withcolumcount:&cols];
    CGRect tf = [tableView frame];
    NSString *cid = (sz.width <= sz.height) ? @"cellid_h" : @"cellid_w";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (cell == nil) {
        UIColor *clear = [UIColor clearColor];
        UIColor *light = [UIColor colorWithWhite:0.7f alpha:1.0f];
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid] autorelease];
        [cell setBackgroundColor:clear];
        for (int c = 0; c < cols; c++) {
            float colx = (float)((int)(tf.size.width / (float)cols) * c);
            SImage *img = [[SImage alloc] initWithFrame:CGRectMake(colx + 15.0f, 10.0f, 40.0f, 40.0f)];
            [cell addSubview:img];
            [img release];
            [img setTag:c + 100];
            [img setM_section:section];
            [img setBackgroundColor:clear];
            [img setUserInteractionEnabled:NO];
            [img setContentMode:UIViewContentModeScaleAspectFit];
            [img SetKBPointer:self];

            BOOL pad = ISIPAD;
            float ly = pad ? 11.0f : 9.0f;
            float lh = pad ? 22.0f : 28.0f;
            SLabel *l1 = [[SLabel alloc] initWithFrame:CGRectMake(colx + 65.0f, ly, (float)((int)(tf.size.width / (float)cols) - 65), lh)];
            [cell addSubview:l1];
            [l1 release];
            [l1 setM_section:section];
            [l1 setTag:c + 1000];
            [l1 setFont:[UIFont boldSystemFontOfSize:(pad ? 18.0f : 12.0f)]];
            [l1 setTextColor:[UIColor whiteColor]];
            [l1 setBackgroundColor:clear];
            [l1 setUserInteractionEnabled:NO];
            [l1 SetKBPointer:self];
            if (!pad) [l1 setNumberOfLines:2];

            CGRect f1 = [l1 frame];
            SLabel *l2 = [[SLabel alloc] initWithFrame:CGRectMake(f1.origin.x, f1.origin.y + (pad ? 22.0f : 26.0f), f1.size.width, pad ? (f1.size.height - 5.0f) : (f1.size.height - 10.0f))];
            [cell addSubview:l2];
            [l2 release];
            [l2 setTag:c + 2000];
            [l2 setM_section:section];
            [l2 setFont:[UIFont systemFontOfSize:(pad ? 12.0f : 10.0f)]];
            [l2 setTextColor:light];
            [l2 setBackgroundColor:clear];
            [l2 setUserInteractionEnabled:NO];
            [l2 SetKBPointer:self];
            [cell bringSubviewToFront:l1];
        }
    }
    for (int c = 0; c < cols; c++) {
        int idx = (int)[indexPath row] + rows * c;
        long long cid64 = -1;
        NSString *title = @"";
        NSString *interpret = @"";
        UIImage *image = nil;
        NSDate *modk = nil;
        [m_srlock lock];
        if (idx >= 0 && idx < (int)[src count]) {
            ClipObject *co = [src objectAtIndex:idx];
            if (co != nil) {
                cid64 = [co ID];
                title = [NSString stringWithString:([co m_title] ? [co m_title] : @"")];
                interpret = [NSString stringWithString:([co m_interpret] ? [co m_interpret] : @"")];
                image = [m_pkiosk GetSmallImage:co];
                if (section == 2 && [co m_picturepath] != nil)
                    modk = [[[NSFileManager defaultManager] attributesOfItemAtPath:[DEL BuildSmallPicpath:[co m_picturepath]] error:nil] fileModificationDate];
                if (image == nil) {
                    image = [UIImage imageNamed:@"cover-note-40x40.png"];
                    if (!m_srpicthreadstarted[section]) {
                        m_srpicthreadstarted[section] = YES;
                        [NSThread detachNewThreadSelector:@selector(SRPictureThread:) toTarget:self withObject:[NSNumber numberWithInt:section]];
                    }
                }
            }
        }
        [m_srlock unlock];
        SImage *img = (SImage *)[cell viewWithTag:c + 100];
        if (img != nil) {
            // a cover that arrives later (plugin hits) blends in instead of popping in
            BOOL blend = NO;
            if (section == 2 && cid64 != -1 && modk != nil && image != nil) {
                if (m_srshown == nil) m_srshown = [[NSMutableDictionary alloc] init];
                NSNumber *key = [NSNumber numberWithLongLong:cid64];
                NSDate *prev = [m_srshown objectForKey:key];
                blend = (prev != nil && ![prev isEqualToDate:modk]);     // the thumbnail changed since it was last shown
                [m_srshown setObject:modk forKey:key];
            }
            [img setM_id:cid64];
            [img setM_index:idx];
            [img setM_section:section];
            if (blend) {
                [UIView transitionWithView:img duration:0.45 options:(UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction)
                                animations:^{ [img setImage:image]; } completion:nil];
            } else {
                [img setImage:image];
            }
        }
        SLabel *l1 = (SLabel *)[cell viewWithTag:c + 1000];
        if (l1 != nil) {
            [l1 setM_index:idx];
            [l1 setM_section:section];
            [l1 setText:title];
        }
        SLabel *l2 = (SLabel *)[cell viewWithTag:c + 2000];
        if (l2 != nil) {
            [l2 setText:interpret];
            [l2 setM_section:section];
            [l2 setM_index:idx];
        }
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60.0f;
}

// the result list is divided into "Lokal" (shown folder), "Weitere Ordner" and one section per source plugin
- (NSMutableArray *)SRArray:(int)section {
    return (section == 0) ? m_srarray : ((section == 1) ? m_srarrayother : m_srarrayplugin);
}

- (int)LogicalSection:(NSInteger)tableSection {
    // only sections that really have results are shown (an empty list still has its one section 0)
    int seen = -1;
    for (int s = 0; s < 3; s++) {
        if ([[self SRArray:s] count] > 0 || (s == 2 && m_srprog >= 0.0f)) seen++;
        if (seen == (int)tableSection) return s;
    }
    return 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    int n = ([m_srarray count] > 0 ? 1 : 0) + ([m_srarrayother count] > 0 ? 1 : 0) + (([m_srarrayplugin count] > 0 || m_srprog >= 0.0f) ? 1 : 0);
    return n > 0 ? n : 1;
}

- (NSString *)SRSourceName {
    ClipObject *c = [m_srarrayplugin count] ? [m_srarrayplugin objectAtIndex:0] : nil;
    NSData *j = [[c m_information] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *d = (j != nil) ? [NSJSONSerialization JSONObjectWithData:j options:0 error:nil] : nil;
    NSString *n = [d isKindOfClass:[NSDictionary class]] ? [d objectForKey:@"_source"] : nil;
    NSString *nt = [d isKindOfClass:[NSDictionary class]] ? [d objectForKey:@"_note"] : nil;
    if (![n isKindOfClass:[NSString class]] || [n length] == 0) return @"Quelle";
    return ([nt isKindOfClass:[NSString class]] && [nt length]) ? [n stringByAppendingFormat:@" \u00B7 %@", nt] : n;
}

// Icon of a source that is built into the app (PNG, 96 px, base64); sources can also bring their own icon_url.
static UIImage *SRBuiltinIcon(NSString *pid) {
    if (![[pid lowercaseString] isEqualToString:@"qobuz"]) return nil;
    static NSString *b64 = @"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";
    NSData *d = [[[NSData alloc] initWithBase64EncodedString:b64 options:0] autorelease];
    return (d != nil) ? [UIImage imageWithData:d scale:3.0f] : nil;
}

// small round badge: a note for local hits, the first letter of the source for plugin hits
static UIImage *SRBadge(NSString *glyph, UIColor *color) {
    CGSize sz = CGSizeMake(20.0f, 20.0f);
    UIGraphicsBeginImageContextWithOptions(sz, NO, 0.0f);
    [color setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 20.0f, 20.0f)] fill];
    NSDictionary *at = [NSDictionary dictionaryWithObjectsAndKeys:[UIFont boldSystemFontOfSize:10.0f], NSFontAttributeName, [UIColor whiteColor], NSForegroundColorAttributeName, nil];
    CGSize ts = [glyph sizeWithAttributes:at];
    [glyph drawAtPoint:CGPointMake((20.0f - ts.width) * 0.5f, (20.0f - ts.height) * 0.5f) withAttributes:at];
    UIImage *im = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return im;
}

- (NSString *)SRSourceId {
    ClipObject *c = [m_srarrayplugin count] ? [m_srarrayplugin objectAtIndex:0] : nil;
    NSData *j = [[c m_information] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *d = (j != nil) ? [NSJSONSerialization JSONObjectWithData:j options:0 error:nil] : nil;
    NSString *n = [d isKindOfClass:[NSDictionary class]] ? [d objectForKey:@"_plugin"] : nil;
    return [n isKindOfClass:[NSString class]] ? n : @"";
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)tsection {
    int section = [self LogicalSection:tsection];
    if ([[self SRArray:section] count] == 0 && !(section == 2 && m_srprog >= 0.0f)) return nil;
    NSString *name; UIImage *icon = nil;
    if (section == 0) { name = @"Lokal"; icon = SRBadge(@"\u266A", [UIColor colorWithWhite:0.45f alpha:1.0f]); }
    else if (section == 1) { name = @"Weitere Ordner"; icon = SRBadge(@"\u266A", [UIColor colorWithWhite:0.35f alpha:1.0f]); }
    else {
        name = [m_srarrayplugin count] ? [self SRSourceName] : (m_srprogname ? m_srprogname : @"Quelle");
        // the plugin's own icon: Documents/Plugins/<plugin id>.png (put there by the user); otherwise a round badge with the first letter
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *ip = [[[docs stringByAppendingPathComponent:@"Plugins"] stringByAppendingPathComponent:([m_srarrayplugin count] ? [self SRSourceId] : (m_srprogid ? m_srprogid : @""))] stringByAppendingPathExtension:@"png"];
        icon = [UIImage imageWithContentsOfFile:ip];
        if (icon == nil) {      // icon shipped with the app (Plugins/<id>.png in the bundle)
            NSString *bp = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Plugins"] stringByAppendingPathComponent:([m_srarrayplugin count] ? [self SRSourceId] : (m_srprogid ? m_srprogid : @""))];
            icon = [UIImage imageWithContentsOfFile:[bp stringByAppendingPathExtension:@"png"]];
        }
        if (icon == nil) icon = SRBuiltinIcon([m_srarrayplugin count] ? [self SRSourceId] : (m_srprogid ? m_srprogid : @""));
        if (icon == nil) icon = SRBadge([[name substringToIndex:1] uppercaseString], [UIColor colorWithRed:0.20f green:0.45f blue:0.75f alpha:1.0f]);
    }
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, [tableView frame].size.width, 26.0f)] autorelease];
    [v setBackgroundColor:[UIColor colorWithWhite:0.15f alpha:1.0f]];
    if (section == 2 && m_srprog >= 0.0f) {
        UIView *fill = [[[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, [tableView frame].size.width * m_srprog, 26.0f)] autorelease];
        [fill setBackgroundColor:[UIColor colorWithWhite:0.38f alpha:1.0f]];
        [fill setUserInteractionEnabled:NO];
        [fill setTag:7791];
        [v addSubview:fill];
    }
    UIImageView *iv = [[[UIImageView alloc] initWithImage:icon] autorelease];
    [iv setContentMode:UIViewContentModeScaleAspectFit];
    [iv setFrame:CGRectMake(12.0f, 3.0f, 20.0f, 20.0f)];
    [v addSubview:iv];
    UILabel *l = [[[UILabel alloc] initWithFrame:CGRectMake(40.0f, 3.0f, [tableView frame].size.width - 52.0f, 20.0f)] autorelease];
    [l setText:name];
    [l setFont:[UIFont boldSystemFontOfSize:13.0f]];
    [l setTextColor:[UIColor colorWithWhite:0.8f alpha:1.0f]];
    [l setBackgroundColor:[UIColor clearColor]];
    [v addSubview:l];
    return v;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    int ls = [self LogicalSection:section];
    return ([[self SRArray:ls] count] > 0 || (ls == 2 && m_srprog >= 0.0f)) ? 26.0f : 0.0f;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    [self RestartKeyboardtimer];
    [[m_pkiosk m_glv] RestartIdleTimer];
    [[m_pkiosk m_glv] RestartAdvertTimer];
    [m_pkiosk Restart30secsearchTimer];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self StopKeyboardtimer];
    [[m_pkiosk m_glv] StopIdleTimer];
    [[m_pkiosk m_glv] StopAdvertTimer];
}

- (void)RefreshSettings {
}

- (void)TablefadeAniDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context {
    UIView *v = [self viewWithTag:[animationID intValue]];
    if (v != nil) [v removeFromSuperview];
}

// result list of the coverflow search (BeginSearchinBG:) arrives here on the main thread
- (void)SetUpSearchList:(NSArray *)upSearchList {
    gv_tablefadetag++;
    [m_srlock lock];
    [[m_pkiosk m_glv] GetArrayLock:NO];
    [m_srarray removeAllObjects];
    [m_srtableview reloadData];
    if ([[m_pkiosk m_glv] m_selectedfolderid] != -33) {
        for (unsigned i = 0; i < [upSearchList count]; i++) {
            ClipObject *co = [upSearchList objectAtIndex:i];
            if ([co ID] != -5) {
                if ([co m_tracks] == nil) [m_srarray addObject:co];
                else [m_srarray addObjectsFromArray:[co m_tracks]];
            }
        }
    }
    [[m_pkiosk m_glv] releaseArraylock];
    DBOperations *dbop = [[DBOperations alloc] init];
    [DEL LockDB:YES];
    NSString *fname = [dbop GetFoldername:[[m_pkiosk m_glv] m_selectedfolderid]
                             withserverid:[[m_pkiosk m_glv] m_selectedserverid]
                               withipodid:[[m_pkiosk m_glv] m_selectedipodid]
                      withspotifyfolderid:nil];
    [DEL UnlockDB];
    [dbop release];
    int total = 0;
    NSMutableArray *orig = [[m_pkiosk m_glv] m_origarray];
    for (unsigned i = 0; i < [orig count]; i++) {
        ClipObject *co = [orig objectAtIndex:i];
        total += ([co m_tracks] == nil) ? 1 : (int)[[co m_tracks] count];
    }
    NSString *right;
    if ((int)[m_srarray count] != total) right = [NSString stringWithFormat:@"%i|%i", (int)[m_srarray count], total];
    else right = [NSString stringWithFormat:@"%i", total];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MsgTextFoundItemsLabel"
        object:[NSDictionary dictionaryWithObjectsAndKeys:(fname ? fname : @""), @"left", right, @"right", nil]];
    [m_srarray sortUsingSelector:@selector(compareTitles:)];
    int cnt = (int)[m_srarray count];
    [m_srlock unlock];
    [m_srtableview reloadData];
    if (cnt >= 1) {
        [m_srtableview scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
    }
    [self SetResortFlag:0 withval:YES];
    [self BeginSearchOtherArray];
}

- (void)BeginSearchOtherArray {
    [self performSelectorInBackground:@selector(BeginSearchOtherArrayBackGround) withObject:nil];
}

- (void)BeginSearchOtherArrayBackGround {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    DBOperations *dbop = [[DBOperations alloc] init];
    NSString *text = nil;
    if ([[self m_searchlabel] text] != nil && [[[self m_searchlabel] text] length] != 0) {
        text = [NSString stringWithString:[[self m_searchlabel] text]];
    }
    if ([text length] != 0) {
        [DEL LockDB:YES];
        NSMutableArray *folders = [dbop GetFolders:[m_pkiosk m_sve] onlyexclude:NO checkempty:YES withLimits:YES withremotefolders:YES join:NO];
        [DEL UnlockDB];
        // drop live radio and the currently shown folder
        for (int i = (int)[folders count] - 1; i >= 0; i--) {
            FolderObject *fo = [folders objectAtIndex:i];
            if ([fo folderid] == -33) {
                [folders removeObjectAtIndex:i];
            } else if ([fo folderid] == [[m_pkiosk m_glv] m_selectedfolderid]) {
                if ([fo folderid] == -44) {
                    if ([fo ipodid] == [[m_pkiosk m_glv] m_selectedipodid]) [folders removeObjectAtIndex:i];
                } else {
                    [folders removeObjectAtIndex:i];
                }
            }
        }
        NSMutableArray *found = [self SubBGSearch:text withdbop:dbop withfolders:folders];
        [dbop release];
        if ([[self m_searchlabel] text] == nil || [[[self m_searchlabel] text] isEqualToString:text]) {
            [m_srlock lock];
            [m_srarrayother removeAllObjects];
            [m_srarrayother addObjectsFromArray:found];
            [m_srlock unlock];
            [self SetResortFlag:1 withval:YES];
        }
        [found release];
        [m_srtableview performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
        // source plugins that are loaded (Quellen > Autostart) add their hits to the same list
        [[RfxPluginManager shared] SearchText:text done:^(NSString *t, NSArray *clips) {
            if ([[self m_searchlabel] text] == nil || ![[[self m_searchlabel] text] isEqualToString:t]) return;
            [m_srlock lock];
            [m_srarrayplugin removeAllObjects];
            [m_srarrayplugin addObjectsFromArray:clips];
            [m_srlock unlock];
            [self SetResortFlag:2 withval:YES];
            [m_srtableview reloadData];
        }];
    } else {
        [m_srlock lock];
        [m_srarrayother removeAllObjects];
        [m_srarrayplugin removeAllObjects];
        [m_srlock unlock];
        [m_srtableview performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
        [[RfxPluginManager shared] SearchText:@"" done:nil];      // ends a running search bar
        [dbop release];
    }
    [pool release];
}

// +1
- (NSMutableArray *)SubBGSearch:(NSString *)subBGSearch withdbop:(DBOperations *)dbop withfolders:(NSArray *)folders {
    NSMutableArray *result = [[NSMutableArray alloc] init];
    NSFileManager *fm = [NSFileManager defaultManager];
    [DEL LockDB:YES];
    if ([dbop dbOpen]) {
        FMResultSet *rs = [[dbop db] executeQuery:[NSString stringWithFormat:@"select * from mixxtapes where searchkey LIKE '%%%@%%' and hidden is NULL AND COALESCE(hidden,0)=0  ORDER BY interpret COLLATE NOCASE ASC", subBGSearch]];
        while ([rs next]) {
            ClipObject *co = [[ClipObject alloc] init];
            [dbop ReadCO:co withRSet:rs];
            BOOL abort = NO;
            for (unsigned i = 0; i < [folders count]; i++) {
                if ([[self m_searchlabel] text] != nil && ![[[self m_searchlabel] text] isEqualToString:subBGSearch]) {
                    abort = YES;
                    break;
                }
                FolderObject *fo = [folders objectAtIndex:i];
                if ([co m_folderid] != [fo folderid]) continue;
                if ([fo serverid] != [co m_serverid]) continue;
                NSString *dir = [NSString stringWithFormat:@"%@%@/", [DEL CreateServerDir:[m_pkiosk m_sve] withfolderobject:fo], [DEL Buildfoldername:fo]];
                [DEL BuildAndCheckFilePathes:co withfm:fm withserverdir:dir withCheck:YES];
                [result addObject:co];
                break;
            }
            [co release];
            if (abort) break;
            if ([[self m_searchlabel] text] != nil && ![[[self m_searchlabel] text] isEqualToString:subBGSearch]) break;
        }
        [rs close];
        [dbop dbClose];
    }
    [DEL UnlockDB];
    return result;
}

- (int)getNumberOfRowsInSection:(int)numberOfRowsInSection {
    NSArray *a = [self SRArray:numberOfRowsInSection];
    int rows = 0, cols = 0;
    [self GetTableMatrix:(int)[a count] withitemsincolum:&rows withcolumcount:&cols];
    return rows;
}

- (void)SetParent:(GLView *)parent {
    m_parent = parent;
    [self LayoutPanels];
}

#pragma mark - frames (panel coordinate system is 1000 points tall; the GLView slides it up)

- (CGRect)GetBackspaceRect:(CGSize)backspaceRect {
    CGRect kb = [m_keyboardpic frame];
    if (backspaceRect.width > backspaceRect.height) {
        return CGRectMake(kb.origin.x + 525.0f, kb.origin.y + 8.0f, 46.0f, 34.0f);
    }
    return CGRectMake(kb.origin.x + 371.0f, kb.origin.y + 8.0f, 40.0f, 38.0f);
}

- (CGRect)GetXFieldFrame {
    CGRect l = [[self m_searchlabel] frame];
    return CGRectMake((l.origin.x + l.size.width) - 18.0f, l.origin.y + 3.0f, 40.0f, 20.0f);
}

- (CGRect)GetFoundItemsFrame:(CGSize)foundItemsFrame {
    CGRect l = [[self m_searchlabel] frame];
    CGRect kb = [m_keyboardpic frame];
    float x = (float)(int)((l.origin.x + l.size.width) + 100.0f);
    return CGRectMake(x, l.origin.y, ((kb.origin.x + kb.size.width) - x) - 15.0f, 25.0f);
}

- (CGRect)GetCollectionIconFrame:(CGSize)collectionIconFrame {
    CGRect kb = [m_keyboardpic frame];
    CGRect l = [[self m_searchlabel] frame];
    return CGRectMake((float)(int)(kb.origin.x + 11.0f), l.origin.y + 3.0f, 23.0f, 21.0f);
}

- (CGRect)GetCollectionnameFrame:(CGSize)collectionnameFrame {
    CGRect kb = [m_keyboardpic frame];
    CGRect l = [[self m_searchlabel] frame];
    float x = (float)(int)(((kb.origin.x + 11.0f) + 23.0f) + 8.0f);
    return CGRectMake(x, l.origin.y, (l.origin.x - x) - 10.0f, 25.0f);
}

- (CGRect)GetTextfieldFrame:(CGSize)textfieldFrame {
    CGRect kb = [m_keyboardpic frame];
    if (textfieldFrame.width <= textfieldFrame.height) {
        return CGRectMake(kb.origin.x + 202.0f, kb.origin.y + 13.0f, 137.0f, 26.0f);
    }
    return CGRectMake(kb.origin.x + 357.0f, kb.origin.y + 14.0f, 137.0f, 26.0f);
}

- (CGRect)GetVolOverlayFrame:(CGSize)volOverlayFrame {
    CGRect r = [self GetSliderFrame:volOverlayFrame];
    r.origin.y += 2.0f;
    r.size.height += -3.0f;
    r.origin.x += 2.0f;
    r.size.width += -4.0f;
    if (!ISIPAD) {
        r.size.height = (r.size.height - 4.0f) - 1.0f;
    }
    return r;
}

- (CGRect)GetSliderFrame:(CGSize)sliderFrame {
    CGRect bg = [self GetSliderBGFrame:sliderFrame];
    int inset = ISIPAD ? 0x12 : 0xa;
    return CGRectMake(bg.origin.x + 20.0f, bg.origin.y + (float)inset, (bg.size.width - 20.0f) - 20.0f, bg.size.height - (float)(inset << 1));
}

- (CGRect)GetSliderBGFrame:(CGSize)sliderBGFrame {
    CGRect reg = [m_parent GetRegisterRect:0];
    float w = ISIPAD ? 500.0f : 440.0f;
    float h = ISIPAD ? 60.0f : 45.0f;
    int x = (int)(((sliderBGFrame.width - w) * 0.5f) - (float)(int)((sliderBGFrame.width * 0.5f) - (reg.origin.x + (reg.size.width * 0.5f))));
    return CGRectMake(x < 20 ? 20.0f : (float)x, 1000.0f - h, w, h);
}

- (CGRect)GetKBPicFrame:(CGSize)kBPicFrame {
    BOOL hidden = [m_nonewtitles isHidden];
    BOOL land = (kBPicFrame.width > kBPicFrame.height);
    int base;
    if (!land) base = 0x320;
    else base = ISIPAD ? 0x23a : 0x109;
    float w = land ? 908.0f : 606.0f;
    int h = land ? 0x96 : 0x8c;
    return CGRectMake((kBPicFrame.width - w) * 0.5f, (float)(1000 - base), w, (float)(hidden ? h : (h + 0x32)));
}

- (CGRect)GetSearchScrollerFrame:(CGSize)searchScrollerFrame {
    CGRect bg = [self GetSearchScrollerBGFrame:searchScrollerFrame];
    float top, bottom;
    if (ISIPAD) {
        top = 20.0f;
        bottom = 50.0f;
    } else {
        top = [m_nonewtitles isHidden] ? 10.0f : 60.0f;
        bottom = 15.0f;
    }
    return CGRectMake(bg.origin.x + 10.0f, bg.origin.y + top, bg.size.width - 20.0f, (bg.size.height - top) - bottom);
}

- (CGRect)GetSearchScrollerBGFrame:(CGSize)searchScrollerBGFrame {
    BOOL land = (searchScrollerBGFrame.width > searchScrollerBGFrame.height);
    int r10;
    float width;
    if (ISIPAD) {
        int base = land ? 0x96 : 0x8c;
        r10 = ([[m_nonewtitles text] length] == 0) ? base : (base + 0x32);
        width = land ? 908.0f : 606.0f;
    } else {
        r10 = 0;
        width = 440.0f;
    }
    int r1;
    if (!land) r1 = 0x320;
    else r1 = ISIPAD ? 0x23a : 0x109;
    return CGRectMake((searchScrollerBGFrame.width - width) * 0.5f, (float)((r10 + 0x3e8) - r1), width, (float)(r1 - r10));
}

- (CGRect)GetNoNewTitlesFrame:(CGSize)noNewTitlesFrame {
    if (!ISIPAD) {
        CGRect bg = [m_srbgview frame];
        return CGRectMake(bg.origin.x, bg.origin.y + 7.0f, bg.size.width, 48.0f);
    }
    CGRect kb = [m_keyboardpic frame];
    CGRect l = [m_searchlabel frame];
    return CGRectMake(kb.origin.x, (l.origin.y + l.size.height) + 7.0f, kb.size.width, 48.0f);
}

#pragma mark - cursor

- (void)StopCursorblinking {
    if (!ISIPAD) return;
    if (m_cursortimer != nil) {
        [m_cursortimer invalidate];
        m_cursortimer = nil;
    }
    [m_cursorview setHidden:YES];
    [m_cursorview setAlpha:0.0f];
}

- (void)StartCursorBlinking {
    if (!ISIPAD) return;
    if (m_cursortimer != nil) {
        [m_cursortimer invalidate];
        m_cursortimer = nil;
    }
    [self SetCursorFrame];
    [m_cursorview setHidden:NO];
    [m_cursorview setAlpha:1.0f];
    m_cursortimer = [NSTimer scheduledTimerWithTimeInterval:0.7 target:self selector:@selector(CursorTimerFunction:) userInfo:nil repeats:NO];
}

// the cursor sits m_cursoroff characters before the end of the text (0: at the end); a tap into the text moves it
- (NSString *)TextWithoutCharBeforeCursor:(NSString *)cur {
    if (m_cursoroff > (int)[cur length]) m_cursoroff = (int)[cur length];
    int at = (int)[cur length] - m_cursoroff;
    if (at <= 0) return cur;
    return [[cur substringToIndex:at - 1] stringByAppendingString:[cur substringFromIndex:at]];
}

- (void)SetCursorFrame {
    CGRect lf = [[self m_searchlabel] frame];
    NSString *t = [[self m_searchlabel] text] ? [[self m_searchlabel] text] : @"";
    if (m_cursoroff > (int)[t length]) m_cursoroff = (int)[t length];
    if ([t length] == 0) m_cursoroff = 0;
    NSString *pre = [t substringToIndex:[t length] - m_cursoroff];
    CGSize ts = [pre sizeWithAttributes:[NSDictionary dictionaryWithObject:[[self m_searchlabel] font] forKey:NSFontAttributeName]];
    float x = lf.origin.x + ts.width;
    float w = ((x + 3.0f) < (lf.origin.x + lf.size.width)) ? 2.0f : 0.0f;
    [m_cursorview setFrame:CGRectMake(x, lf.origin.y + 3.0f, w, lf.size.height - 6.0f)];
}

- (void)CursorTimerFunction:(NSTimer *)cursorTimerFunction {
    [cursorTimerFunction invalidate];
    m_cursortimer = nil;
    NSTimeInterval next;
    if ((double)[m_cursorview alpha] <= 0.9) {
        [m_cursorview setAlpha:1.0f];
        next = 0.7;
    } else {
        [m_cursorview setAlpha:0.0f];
        next = 0.5;
    }
    m_cursortimer = [NSTimer scheduledTimerWithTimeInterval:next target:self selector:@selector(CursorTimerFunction:) userInfo:nil repeats:NO];
}

- (void)SetVolSlider:(float)volSlider {
    if (m_volslider == nil) return;
    [m_volslider setValue:volSlider];
}

- (void)SpinDelayed:(id)spinDelayed {
    [[m_pkiosk m_glv] SpinAutomaticToClip:spinDelayed orIndex:0];
}

- (void)AddItemFromSearchList:(int)itemFromSearchList withsection:(int)section withdirectClipObject:(id)directClipObject {
    ClipObject *co = directClipObject;
    RfxCrumb("AddItem begin");
    if (co == nil) {
        if (itemFromSearchList < 0) return;
        NSMutableArray *src = [self SRArray:section];
        if ((unsigned)itemFromSearchList >= [src count]) { [RfxPluginManager Toast:@"Eintrag nicht mehr vorhanden."]; return; }
        co = [src objectAtIndex:itemFromSearchList];
    }
    RfxCrumb("AddItem got clip");
    if ([co m_folderid] == -88 && [co m_filepath] == nil) {      // hit of a source plugin: load + import first
        RfxCrumb("AddItem plugin import");
        [[RfxPluginManager shared] ImportClip:co];
        // a jukebox: the window closes (search text and results stay), the title is loaded and queued in the background
        if (directClipObject == nil) [[m_pkiosk m_glv] ToggleKBAndRegister:[NSNumber numberWithInt:2]];
        return;
    }
    double now = CACurrentMediaTime();
    if (!gRfxPlayNow && (now - [m_pkiosk m_lastsongdragged]) < (double)[[m_pkiosk m_sve] m_songdragdelay]) {
        [RfxPluginManager Toast:@"Zu schnell hintereinander (Drag-Verzögerung)."];
        [[m_pkiosk m_glv] ToggleKBAndRegister:[NSNumber numberWithInt:2]];
        return;
    }
    ClipObject *added = nil;
    RfxCrumb("AddItem file check");
    if (!([co m_folderid] == -44 || [co m_folderid] == -66 || ([co m_filepath] != nil && [[NSFileManager defaultManager] fileExistsAtPath:[co m_filepath]])))
        [RfxPluginManager Toast:[NSString stringWithFormat:@"Datei nicht gefunden: %@", [co m_filepath] ? [[co m_filepath] lastPathComponent] : @"(kein Pfad)"]];
    if ([co m_folderid] == -44 || [co m_folderid] == -66 || ([co m_filepath] != nil && [[NSFileManager defaultManager] fileExistsAtPath:[co m_filepath]])) {
        [m_pkiosk setM_autoselected:NO];
        RfxCrumb("AddItem copy");
        ClipObject *n = [[ClipObject alloc] init];
        [m_pkiosk CopyPropertiesFromObject:co toObject:n];
        RfxCrumb("AddItem cdpicture");
        [n setM_imgv:[[[UIImageView alloc] initWithFrame:CGRectZero] autorelease]];
        UIImage *pic = [[m_pkiosk m_glv] CreateCDPicture:n roundpic:YES];
        [[n m_imgv] setImage:pic];
        [[n m_imgv] setAlpha:0.0f];
        CGRect fr = [m_pkiosk GetFrameForDragPic:(int)[[m_pkiosk m_clips] count]];
        fr = [m_pkiosk MakeSmallFrame:fr];
        [[n m_imgv] setFrame:fr];
        RfxCrumb("AddItem AddClip");
        [m_pkiosk AddClip:n atIndex:-1 fromDragging:NO withsendqueue:YES withaddanyway:NO sendremotedelayed:NO];
        RfxCrumb("AddItem AddClip done");
        added = n;
        // no [n release] here: AddClip takes over the reference (it releases the clip itself and the queue array owns it);
        // an extra release freed the clip while it was still in the queue (crash right after AddClip)
    }
    if (directClipObject == nil) {
        [[m_pkiosk m_glv] ToggleKBAndRegister:[NSNumber numberWithInt:2]];
        if (added != nil) {
            [self performSelector:@selector(SpinDelayed:) withObject:added afterDelay:0.1];
        }
    }
}

- (void)GetTableMatrix:(int)tableMatrix withitemsincolum:(int *)itemsincolum withcolumcount:(int *)columcount {
    CGSize sz = [DEL GetiPadSize];
    *columcount = 2;
    if (sz.width > sz.height) {
        if (ISIPAD) *columcount = 3;
    }
    *itemsincolum = (int)ceilf((float)tableMatrix / (float)*columcount);
}

- (void)SetPicThreadStarted:(int)picThreadStarted withval:(BOOL)val {
    m_srpicthreadstarted[picThreadStarted] = val;
}

- (void)SetImagesOnSlider:(UISlider *)imagesOnSlider {
    UIImage *l = [DEL CreateStretchedImage:@"volume-links-neu.png" withImage:nil withLeftCap:10.0f withTopCap:0.0f withInvert:NO];
    UIImage *r = [DEL CreateStretchedImage:@"volume-rechts-neu.png" withImage:nil withLeftCap:10.0f withTopCap:0.0f withInvert:YES];
    [imagesOnSlider setThumbImage:[UIImage imageNamed:@"volume-knopf-neu.png"] forState:UIControlStateNormal];
    [imagesOnSlider setMinimumTrackImage:l forState:UIControlStateNormal];
    [imagesOnSlider setMaximumTrackImage:r forState:UIControlStateNormal];
    [imagesOnSlider setBackgroundColor:[UIColor clearColor]];
}

- (void)SetResortFlag:(int)resortFlag withval:(BOOL)val {
    m_resortflag[resortFlag] = val;
}


// The original forwards these to the web/hint view, the help picture and the video shelf.
// Those panels are not part of this build (no server), so there is nothing to forward to.
- (void)SetWebViewsBlack { }
- (void)InitHelpPic { }
- (id)GetFirstVideo { [self ResetupVideoView]; return [m_videoview GetFirstVideo]; }
- (void)ResetupVideoView { [m_videoview Setup:2]; }
- (BOOL)HasVideos { [m_videoview Setup:2]; return [m_videoview RowCount] > 0; }

#pragma mark - restored panels (registers 1, 3, 6, 7, 8, 9)

// panel x: centred under its register button (original GetWDRViewFrame: / GetOnOffViewFrame: / GetVideoViewFrame:)
- (CGRect)PanelFrame:(int)which width:(float)w height:(float)h {
    CGSize sz = [DEL GetiPadSize];
    CGRect rr = (m_parent != nil) ? [m_parent GetRegisterRect:which] : CGRectZero;
    float x = rr.origin.x + rr.size.width * 0.5f - w * 0.5f;
    if (x > sz.width - 20.0f - w) x = sz.width - 20.0f - w;
    if (x < 20.0f) x = 20.0f;
    return CGRectMake(x, 1000.0f - h, w, h);
}

- (CGRect)GetWDRViewFrame:(CGSize)s { return [self PanelFrame:1 width:330 height:90]; }
- (CGRect)GetOnOffViewFrame:(CGSize)s { return [self PanelFrame:3 width:220 height:228]; }
- (CGRect)GetVideoViewFrame:(CGSize)s { return [self PanelFrame:7 width:220 height:312]; }
// web panels: 685 pt tall (iPad), hanging from the top of the screen, centred
- (CGRect)GetWebViewFrame:(CGSize)s {
    float w = MIN(760.0f, s.width), h = 685.0f;
    return CGRectMake((s.width - w) * 0.5f, 1000.0f - h, w, h);
}

- (void)LayoutPanels {
    CGSize sz = [DEL GetiPadSize];
    [m_wdrview setFrame:[self GetWDRViewFrame:sz]];
    [m_onoffview setFrame:[self GetOnOffViewFrame:sz]];
    [m_videoview setFrame:[self GetVideoViewFrame:sz]];
    CGRect wf = [self GetWebViewFrame:sz];
    [m_webview setFrame:wf]; [m_hintwebview setFrame:wf]; [m_FBwebview setFrame:wf];
    [progView setCenter:CGPointMake(CGRectGetMidX(wf), CGRectGetMidY(wf))];
    [m_weblabel setFrame:CGRectMake(CGRectGetMidX(wf) - 300, CGRectGetMidY(wf) + 30, 600, 120)];
}

- (void)startAni {
    [m_weblabel setHidden:YES];
    [progView setHidden:NO];
    [progView startAnimating];
    [self bringSubviewToFront:progView];
}

- (void)stopAni {
    [progView stopAnimating];
    [progView setHidden:YES];
}

- (void)LoadWeb:(UIWebView *)wv request:(NSURLRequest *)req {
    [self startAni];
    [wv stopLoading];
    [wv loadRequest:req];
}
- (void)OpenConfigUrl:(NSURLRequest *)openConfigUrl { [self LoadWeb:m_webview request:openConfigUrl]; }
- (void)OpenHintUrl:(NSURLRequest *)openHintUrl { [self LoadWeb:m_hintwebview request:openHintUrl]; }
- (void)OpenFBWallUrl:(NSURLRequest *)openFBWallUrl { [self LoadWeb:m_FBwebview request:openFBWallUrl]; }

- (void)webViewDidStartLoad:(UIWebView *)webView { [m_weblabel setHidden:YES]; }
- (void)webViewDidFinishLoad:(UIWebView *)webView { [self stopAni]; }
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    [self stopAni];
    if ([error code] == NSURLErrorCancelled) return;
    // port: the Tobit servers are gone; say so instead of showing an empty black page
    NSString *u = [[[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey] description];
    [m_weblabel setText:[NSString stringWithFormat:@"Der Server ist nicht erreichbar.\n%@", (u != nil ? u : @"")]];
    [m_weblabel setHidden:NO];
    [self bringSubviewToFront:m_weblabel];
}

// original: sets the off timer (seconds) and closes the panel
- (void)ShutDownRest:(NSNumber *)shutDownRest {
    int secs = [shutDownRest intValue];
    [m_parent setM_movingup:YES];
    [[m_pkiosk m_glv] performSelector:@selector(ToggleKBAndRegister:) withObject:[NSNumber numberWithInt:m_showwhat] afterDelay:0.3];
    [m_pkiosk StartKioskShutdowntimer:secs];
}

- (id)GetSecSvr { return m_secsvr; }

// Sends the current volume (0..100) to the remote-control clients.
- (void)RCSendVolume {
    long long vol = (long long)((double)[m_pkiosk m_lastvolume] * 100.0);
    [m_pkiosk InsertIntoRemoteQueue:0xfa4 withpoint:CGPointZero witharg1:vol witharg2:0
                           witharg3:-1 withleaveoutclient:0 witharg4:0];
}

@end


#pragma mark - MenuView

@implementation MenuView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        m_setupobserver = NO;
        memset(m_cmset, 0, sizeof(m_cmset));
        m_kbview = nil;
        m_pkiosk = nil;
        m_type = -1;
        m_offindex = -1;
        m_labels = [[NSMutableArray alloc] init];
        m_topimgv = nil;
        m_imgvs = [[NSMutableArray alloc] init];
        m_videothek = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [m_labels release];
    [m_imgvs release];
    [m_videothek release];
    [super dealloc];
}

- (void)SetParent:(KeyboardView *)parent { m_kbview = parent; }
- (void)SetKioskPointer:(KioskView *)kiosk { m_pkiosk = kiosk; }
- (void)StartWDRSoundForLine:(int)line { }

- (CGRect)GetWDRCheckboxFrame:(int)index {
    float w = [self frame].size.width;
    return CGRectMake(w - 40.0f, (float)((m_type == 1 ? 13 : 55) + index * 45), 22.0f, 22.0f);
}

- (CGRect)GetWDRLabelFrame:(int)index {
    CGRect cb = [self GetWDRCheckboxFrame:index];
    float w = [self frame].size.width;
    if (m_type == 2) return CGRectMake(5.0f, cb.origin.y, w - 10.0f, cb.size.height);
    float x = cb.origin.x - (m_type == 1 ? 150.0f : 275.0f);
    return CGRectMake(x, cb.origin.y, cb.origin.x - x - 5.0f, cb.size.height);
}

- (CGRect)GetWDRSlizerFrame:(int)index {
    CGRect cb = [self GetWDRCheckboxFrame:index];
    return CGRectMake(0.0f, cb.origin.y + cb.size.height + 9.0f, [self frame].size.width, 2.0f);
}

- (void)SetBackColor {
    for (UILabel *l in m_labels) [l setTextColor:[UIColor colorWithWhite:0.35f alpha:1.0f]];
}

- (void)AddCheckmark:(int)checkmark withrect:(CGRect)rect {
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"haken.png"]];
    [iv setFrame:CGRectMake(rect.origin.x + 4.0f, rect.origin.y - 1.0f, 23.0f, 18.0f)];
    [self addSubview:iv];
    [iv setTag:checkmark + 2000];
    [iv release];
}

- (id)GetFirstVideo {
    if ([m_videothek count] != 1) return nil;
    return [NSString stringWithFormat:@"%@", [m_videothek objectAtIndex:0]];
}

- (int)RowCount {
    if (m_type == 0) return 1;
    if (m_type == 1) return 5;
    return (int)[m_videothek count];
}

- (void)Setup:(int)setup {
    m_type = setup;
    if (m_type == 2 && !m_setupobserver) {
        m_setupobserver = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(SetBackColor) name:@"MsgSetBackColor" object:nil];
    }
    float w = [self frame].size.width;
    if (m_topimgv != nil) {
        [m_topimgv removeFromSuperview];
        m_topimgv = nil;
    }
    if (m_type != 1) {
        UIImage *cap = [DEL CreateStretchedImage:nil withImage:[DEL NonCachedImage:@"caption"] withLeftCap:10.0f withTopCap:0.0f withInvert:NO];
        m_topimgv = [[UIImageView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, w, 41.0f)];
        [m_topimgv setImage:cap];
        [self addSubview:m_topimgv];
        [m_topimgv release];
    }
    for (UIView *v in m_labels) [v removeFromSuperview];
    [m_labels removeAllObjects];
    for (UIView *v in m_imgvs) [v removeFromSuperview];
    [m_imgvs removeAllObjects];
    for (UIView *v in [NSArray arrayWithArray:[self subviews]]) {
        if ([v tag] >= 2000 && [v tag] < 2100) [v removeFromSuperview];
    }
    if (m_type == 2) {
        [m_videothek removeAllObjects];
        [DEL GetVideothek:m_videothek];
    }
    if (m_type != 1) {
        UILabel *head = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 10.0f, w, 20.0f)];
        [head setText:(m_type == 2 ? @"Videothek" : @"Newsflash")];
        [head setFont:[UIFont boldSystemFontOfSize:19.0f]];
        [head setTextColor:[UIColor colorWithWhite:0.35f alpha:1.0f]];
        [head setBackgroundColor:[UIColor clearColor]];
        [head setShadowColor:[UIColor colorWithWhite:0.102f alpha:1.0f]];
        [head setShadowOffset:CGSizeMake(0, -1)];
        [head setTextAlignment:NSTextAlignmentCenter];
        [self addSubview:head];
        [m_labels addObject:head];
        [head release];
    }
    int rows = [self RowCount];
    NSArray *offTitles = [NSArray arrayWithObjects:@"Ausschalten", @"In 15 Min.", @"In 30 Min.", @"In 60 Min.", @"In 90 Min.", nil];
    int flags = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"keywdrflags"];
    for (int i = 0; i < rows; i++) {
        if (m_type <= 1) {
            UIImageView *box = [[UIImageView alloc] initWithFrame:[self GetWDRCheckboxFrame:i]];
            [box setImage:[UIImage imageNamed:(m_type == 0 ? @"checkbox.png" : @"radiobutton.png")]];
            [self addSubview:box];
            [box release];
        }
        UILabel *l = [[UILabel alloc] initWithFrame:[self GetWDRLabelFrame:i]];
        if (m_type == 2) {
            NSString *name = [[NSString stringWithFormat:@"%@", [m_videothek objectAtIndex:i]] lastPathComponent];
            if ([[name pathExtension] length] != 0) name = [name stringByDeletingPathExtension];
            [l setText:name];
        } else if (m_type == 1) {
            [l setText:[offTitles objectAtIndex:i]];
        } else {
            [l setText:@"Stündliche Zeitansage"];
        }
        [self addSubview:l];
        [l setFont:[UIFont boldSystemFontOfSize:18.0f]];
        [l setTextColor:[UIColor colorWithWhite:0.651f alpha:1.0f]];
        [l setBackgroundColor:[UIColor clearColor]];
        [l setShadowColor:[UIColor colorWithWhite:0.102f alpha:1.0f]];
        [l setShadowOffset:CGSizeMake(0, -1)];
        if (m_type == 2) {
            [l setAdjustsFontSizeToFitWidth:YES];
            [l setTextAlignment:NSTextAlignmentCenter];
        }
        [m_labels addObject:l];
        [l release];
        if (m_type == 0) {
            m_cmset[i] = (flags & (1 << i)) != 0;
            if (m_cmset[i]) [self AddCheckmark:i withrect:[self GetWDRCheckboxFrame:i]];
        }
        if (i + 1 < rows || m_type == 2) {
            UIImageView *sep = [[UIImageView alloc] initWithFrame:[self GetWDRSlizerFrame:i]];
            [sep setImage:[UIImage imageNamed:@"trennlinie.png"]];
            [self addSubview:sep];
            [m_imgvs addObject:sep];
            [sep release];
        }
    }
    if (m_type == 1 && m_offindex >= 0 && m_offindex < 5)
        [self AddCheckmark:m_offindex withrect:[self GetWDRCheckboxFrame:m_offindex]];
}

- (void)StartVideoForLine:(int)line {
    if ((NSUInteger)line >= [m_videothek count]) return;
    [[m_pkiosk m_glv] ToggleKBAndRegister:[NSNumber numberWithInt:7]];
    if ((NSUInteger)(line + 1) < [m_labels count]) [[m_labels objectAtIndex:line + 1] setTextColor:[UIColor whiteColor]];
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%@", [m_videothek objectAtIndex:line]],
                       @"keyfilmdictvideothek", [NSNumber numberWithInt:0], @"keyfilmdictcommercial", nil];
    [m_pkiosk performSelector:@selector(StartTPAni:) withObject:d afterDelay:0.01];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    if (t == nil) return;
    [m_kbview RestartKeyboardtimer];
    [[m_pkiosk m_glv] RestartIdleTimer];
    [[m_pkiosk m_glv] RestartAdvertTimer];
    CGPoint p = [t locationInView:self];
    if (p.y <= 41.0f && m_type != 1) {          // caption bar closes the panel
        [[m_pkiosk m_glv] ToggleKBAndRegister:[NSNumber numberWithInt:[m_kbview m_showwhat]]];
        return;
    }
    float base = (m_type == 1) ? 13.0f : 55.0f;
    int row = (int)floorf((p.y - base + 12.0f) / 45.0f);
    if (row < 0 || row >= [self RowCount]) return;
    if (m_type == 2) {
        [self StartVideoForLine:row];
    } else if (m_type == 0) {
        m_cmset[row] = !m_cmset[row];
        UIView *old = [self viewWithTag:row + 2000];
        if (m_cmset[row]) { if (old == nil) [self AddCheckmark:row withrect:[self GetWDRCheckboxFrame:row]]; }
        else [old removeFromSuperview];
        int flags = 0;
        for (int i = 0; i < 8; i++) if (m_cmset[i]) flags |= (1 << i);
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setInteger:flags forKey:@"keywdrflags"];
        [ud synchronize];
        // original forwards the flags to the hourly announcement timer
        [DEL setM_runhourtimer:(flags != 0)];
    } else {
        for (int i = 0; i < 5; i++) [[self viewWithTag:i + 2000] removeFromSuperview];
        if (row == m_offindex) {                // second tap on the active entry cancels the timer
            m_offindex = -1;
            [m_pkiosk StopKioskShutdowntimer];
            [[m_pkiosk m_glv] performSelector:@selector(ToggleKBAndRegister:) withObject:[NSNumber numberWithInt:3] afterDelay:0.3];
        } else {
            m_offindex = row;
            static const int secs[5] = { 1, 900, 1800, 3600, 5400 };
            [self AddCheckmark:row withrect:[self GetWDRCheckboxFrame:row]];
            [m_kbview performSelector:@selector(ShutDownRest:) withObject:[NSNumber numberWithInt:secs[row]] afterDelay:0.3];
        }
    }
}

@end
