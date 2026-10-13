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

- (void)DeleteSearchText30Sec {
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
        // hit test of the keys in the keyboard picture
        float yoff = ([[m_nonewtitles text] length] == 0) ? 0.0f : 50.0f;
        CGRect kbf = [m_keyboardpic frame];
        float left, right, top, bottom, keyw;
        if (portrait) {
            left = 94.0f;
            right = 677.0f;
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
                NSString *nt = [NSString stringWithFormat:@"%@%@", [[self m_searchlabel] text], [NSString stringWithFormat:@"%c", c]];
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
        if (CGRectContainsPoint(m_backspacerect, p)) {
            if ([[[self m_searchlabel] text] length] == 0) break;
            NSString *s = [NSString stringWithFormat:@"%@", [[[self m_searchlabel] text] substringToIndex:([[[self m_searchlabel] text] length] - 1)]];
            [[self m_searchlabel] setText:s];
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
    return [self getNumberOfRowsInSection:(int)section];
}

- (void)SRTapped:(UITapGestureRecognizer *)g {
    RfxCrumb("SRTapped begin");
    if ([g state] != UIGestureRecognizerStateEnded) return;
    CGPoint p = [g locationInView:m_srtableview];
    NSIndexPath *ip = [m_srtableview indexPathForRowAtPoint:p];
    if (ip == nil) { [RfxPluginManager Toast:@"Tipp neben die Liste."]; return; }
    RfxCrumb("SRTapped indexpath");
    int section = (int)[ip section];
    int row = (int)[ip row];
    NSMutableArray *src = (section == 0) ? m_srarray : m_srarrayother;
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
        NSMutableArray *src = (section == 0) ? m_srarray : m_srarrayother;
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
    NSMutableArray *src = (reSortedArray == 0) ? m_srarray : m_srarrayother;
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
    int section = (int)[indexPath section];
    NSMutableArray *src = (section == 0) ? m_srarray : m_srarrayother;
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
        [m_srlock lock];
        if (idx >= 0 && idx < (int)[src count]) {
            ClipObject *co = [src objectAtIndex:idx];
            if (co != nil) {
                cid64 = [co ID];
                title = [NSString stringWithString:([co m_title] ? [co m_title] : @"")];
                interpret = [NSString stringWithString:([co m_interpret] ? [co m_interpret] : @"")];
                image = [m_pkiosk GetSmallImage:co];
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
            [img setM_id:cid64];
            [img setM_index:idx];
            [img setM_section:section];
            [img setImage:image];
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

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section != 1) return nil;
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 100.0f, 4.0f)] autorelease];
    [v setBackgroundColor:[UIColor colorWithWhite:0.15f alpha:1.0f]];
    return v;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return (section == 1) ? 4.0f : 0.0f;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return ([[self m_srarrayother] count] > 0) ? 2 : 1;
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
            for (int i = (int)[m_srarrayother count] - 1; i >= 0; i--)
                if ([[m_srarrayother objectAtIndex:i] m_folderid] == -88) [m_srarrayother removeObjectAtIndex:i];
            [m_srarrayother addObjectsFromArray:clips];
            [m_srlock unlock];
            [self SetResortFlag:1 withval:YES];
            [m_srtableview reloadData];
        }];
    } else {
        [m_srlock lock];
        [m_srarrayother removeAllObjects];
        [m_srlock unlock];
        [m_srtableview performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
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
    NSArray *a = (numberOfRowsInSection != 0) ? [self m_srarrayother] : m_srarray;
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
        return CGRectMake(586.0f, kb.origin.y + 5.0f, 55.0f, 38.0f);
    }
    return CGRectMake(454.0f, kb.origin.y + 15.0f, 37.0f, 35.0f);
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

- (void)SetCursorFrame {
    CGRect lf = [[self m_searchlabel] frame];
    NSString *t = [[self m_searchlabel] text];
    CGSize ts = [t sizeWithAttributes:[NSDictionary dictionaryWithObject:[[self m_searchlabel] font] forKey:NSFontAttributeName]];
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
        NSMutableArray *src = (section == 0) ? m_srarray : m_srarrayother;
        if ((unsigned)itemFromSearchList >= [src count]) { [RfxPluginManager Toast:@"Eintrag nicht mehr vorhanden."]; return; }
        co = [src objectAtIndex:itemFromSearchList];
    }
    RfxCrumb("AddItem got clip");
    if ([co m_folderid] == -88 && [co m_filepath] == nil) {      // hit of a source plugin: load + import first
        RfxCrumb("AddItem plugin import");
        [[RfxPluginManager shared] ImportClip:co];
        return;
    }
    double now = CACurrentMediaTime();
    if ((now - [m_pkiosk m_lastsongdragged]) < (double)[[m_pkiosk m_sve] m_songdragdelay]) {
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
