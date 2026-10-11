// KeyboardView : UIView -- decompiled from Radiofx_iPad (armv7), ported to arm64 / modern iOS.  Manual reference counting.
#import "KeyboardView.h"
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
}

- (void)ForwardKioskPointer:(KioskView *)forwardKioskPointer {
    m_pkiosk = forwardKioskPointer;
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
    float v = [volSliderAction value];
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
            [img setUserInteractionEnabled:YES];
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
            [l1 setUserInteractionEnabled:YES];
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
            [l2 setUserInteractionEnabled:YES];
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
    if (co == nil) {
        if (itemFromSearchList < 0) return;
        NSMutableArray *src = (section == 0) ? m_srarray : m_srarrayother;
        if ((unsigned)itemFromSearchList >= [src count]) return;
        co = [src objectAtIndex:itemFromSearchList];
    }
    double now = CACurrentMediaTime();
    if ((now - [m_pkiosk m_lastsongdragged]) < (double)[[m_pkiosk m_sve] m_songdragdelay]) {
        [[m_pkiosk m_glv] ToggleKBAndRegister:[NSNumber numberWithInt:2]];
        return;
    }
    ClipObject *added = nil;
    if ([co m_folderid] == -44 || [co m_folderid] == -66 || [[NSFileManager defaultManager] fileExistsAtPath:[co m_filepath]]) {
        [m_pkiosk setM_autoselected:NO];
        ClipObject *n = [[ClipObject alloc] init];
        [m_pkiosk CopyPropertiesFromObject:co toObject:n];
        [n setM_imgv:[[[UIImageView alloc] initWithFrame:CGRectZero] autorelease]];
        UIImage *pic = [[m_pkiosk m_glv] CreateCDPicture:n roundpic:YES];
        [[n m_imgv] setImage:pic];
        [[n m_imgv] setAlpha:0.0f];
        CGRect fr = [m_pkiosk GetFrameForDragPic:(int)[[m_pkiosk m_clips] count]];
        fr = [m_pkiosk MakeSmallFrame:fr];
        [[n m_imgv] setFrame:fr];
        [m_pkiosk AddClip:n atIndex:-1 fromDragging:NO withsendqueue:YES withaddanyway:NO sendremotedelayed:NO];
        added = n;
        [n release];
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
- (id)GetFirstVideo { return nil; }

- (id)GetSecSvr { return m_secsvr; }

// Sends the current volume (0..100) to the remote-control clients.
- (void)RCSendVolume {
    long long vol = (long long)((double)[m_pkiosk m_lastvolume] * 100.0);
    [m_pkiosk InsertIntoRemoteQueue:0xfa4 withpoint:CGPointZero witharg1:vol witharg2:0
                           witharg3:-1 withleaveoutclient:0 witharg4:0];
}

@end
