// MTObject.m -- recovered from -[MTObject ...] (armv7), Radiofx HD.
// One tile of the "overview" grid. All numeric constants below were read from the
// original instruction stream (movw/movt pairs and literal pools), not guessed.
#import "MTObject.h"
#import "MTScroller.h"
#import "KioskView.h"
#import "GLView.h"
#import "RadioAppDelegate.h"
#import "DBOperations.h"
#import "ClipObject.h"
#import "FolderObject.h"
#import "ScrollerDictObject.h"
#import "Globals.h"

#define APPDEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@implementation MTObject
@synthesize m_lastspotifyid, m_spotifyfolderid, m_iscolorpic, m_lastipodid, m_ownindex, m_duration;
@synthesize m_reddotsize, m_lastsongid, m_deleteflag, m_borderindex, m_renew, m_reddotcount;
@synthesize m_ipodid, m_sid, m_id;

- (id)init {
    self = [super init];
    if (self) {
        m_lastspotifyid = nil;
        m_id = -1;
        m_sid = -1;
        m_reddotcount = 0;
        m_spotifyfolderid = nil;
        m_ipodid = 0;
        m_renew = NO;
        m_addedtoview = NO;
        m_foldername = nil;
        m_lastsongid = -1;
        m_lastipodid = 0;
        m_iscolorpic = NO;
        m_textlabel   = [[UILabel alloc] initWithFrame:CGRectZero];
        m_mainimgv    = [[UIImageView alloc] initWithFrame:CGRectZero];
        m_borderimgv  = [[UIImageView alloc] initWithFrame:CGRectZero];
        m_reddotimgv  = [[UIImageView alloc] initWithFrame:CGRectZero];
        m_borderindex = 0;
        m_observeradded = NO;
        [m_textlabel setTextColor:[UIColor whiteColor]];
        [m_textlabel setBackgroundColor:[UIColor clearColor]];
        [m_textlabel setTextAlignment:NSTextAlignmentCenter];
        if (![APPDEL m_isipad]) {
            [m_textlabel setFont:[UIFont boldSystemFontOfSize:12.0f]];
            [m_textlabel setNumberOfLines:2];
        } else {
            [m_textlabel setFont:[UIFont boldSystemFontOfSize:17.0f]];
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (m_foldername != nil)      { [m_foldername release];      m_foldername = nil; }
    if (m_spotifyfolderid != nil) { [m_spotifyfolderid release]; m_spotifyfolderid = nil; }
    if (m_lastspotifyid != nil)   { [m_lastspotifyid release];   m_lastspotifyid = nil; }
    [super dealloc];
}

- (void)SetPlaceholderpicpointer:(id)placeholderpicpointer { m_placeholderpointer = placeholderpicpointer; }
- (void)SetScrollerPointer:(id)scrollerPointer { m_pscroller = scrollerPointer; }

- (void)ReplaceMainImgwith:(id)replaceMainImgwith {
    if (m_mainimgv != nil) {
        if ([m_mainimgv superview] != nil) [m_mainimgv removeFromSuperview];
    }
    m_mainimgv = replaceMainImgwith;
}

- (void)UpdateCounts:(id)counts {
    int lock = [counts intValue];
    if (lock == 1) [[m_pkiosk m_glv] LockMTOverview];
    [m_pscroller SetRedDot:[self m_reddotcount] withindex:m_ownindex];
    if (lock == 1) [[m_pkiosk m_glv] UnlockMTOverview];
}

- (void)CalcFrameForRedDot {
    CGRect mf = [m_mainimgv frame];
    float yoff = [APPDEL m_isipad] ? 2.0f : 0.0f;
    float w;
    if ([m_reddotimgv image] != nil) w = [[m_reddotimgv image] size].width;
    else w = (float)m_reddotsize;
    CGRect mf2 = [m_mainimgv frame];
    CGRect mf3 = [m_mainimgv frame];
    [m_reddotimgv setFrame:CGRectMake(((mf2.origin.x + mf3.size.width) + -8.0f) - w,
                                      mf.origin.y + yoff, w, (float)m_reddotsize)];
}

- (id)GetMainImageView { return m_mainimgv; }
- (id)GetRedDotImageView { return m_reddotimgv; }

- (void)PlacePicInMid:(int)placePicInMid withview:(id)view {
    CGSize sz = [APPDEL GetiPadSize];
    BOOL radio = (m_id == -33);
    CGRect *r;
    if (sz.width > sz.height) r = radio ? &m_midrecthorradio : &m_midrecthor;
    else                      r = radio ? &m_midrectverradio : &m_midrectver;
    [m_mainimgv setFrame:CGRectMake(r->origin.x, r->origin.y + (float)placePicInMid, r->size.width, r->size.height)];
    CGRect b = [self CalcBorderFrameFromImgFrame:[m_mainimgv frame] withSize:sz adddist:(m_id == -33 ? 1.0f : 0.0f)];
    [m_borderimgv setFrame:b];
    [view bringSubviewToFront:m_borderimgv];
    [view bringSubviewToFront:m_mainimgv];
    [self CalcFrameForRedDot];
    [view bringSubviewToFront:m_reddotimgv];
}

// Re-renders the tile picture for the last played song of this folder.
- (void)SetLastID:(long long)lastID withipodid:(long long)ipodid withFlag:(BOOL)flag withspotifyid:(id)spotifyid {
    if (m_lastsongid == lastID) {
        if (!flag && [m_pkiosk spotifyIDsMatch:spotifyid withsecondid:[self m_lastspotifyid]])
            return;
    }
    if (!flag) {
        m_lastsongid = lastID;
        m_lastipodid = ipodid;
        [self setM_lastspotifyid:spotifyid];
    }
    [APPDEL LockDB:0];
    DBOperations *dbo = [[DBOperations alloc] init];
    FolderObject *folder = [dbo GetFolderForID:m_id withserverid:m_sid withipodid:m_ipodid withspotifyid:[self m_spotifyfolderid]];
    NSMutableArray *songs = [dbo GetSongsForFolder:folder withjoin:1];
    [APPDEL UnlockDB];

    NSUInteger i;
    for (i = 0; i < [songs count]; i++) {
        ClipObject *song = [songs objectAtIndex:i];
        if ([song ID] != m_lastsongid) continue;
        if ([song m_ipodid] != m_lastipodid) continue;
        if (![m_pkiosk spotifyIDsMatch:[song m_spotifyid] withsecondid:[self m_lastspotifyid]]) continue;

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *serverdir;
        if ([song m_folderid] == [folder folderid]) {
            serverdir = [NSString stringWithFormat:@"%@%@/",
                         [APPDEL CreateServerDir:[m_pkiosk m_sve] withfolderobject:folder],
                         [APPDEL Buildfoldername:folder]];
        } else {
            [APPDEL LockDB:0];
            FolderObject *f2 = [dbo GetFolderForID:[song m_folderid] withserverid:[song m_serverid]
                                         withipodid:m_ipodid withspotifyid:[song m_spotifyfolderid]];
            [APPDEL UnlockDB];
            serverdir = [NSString stringWithFormat:@"%@%@/",
                         [APPDEL CreateServerDir:[m_pkiosk m_sve] withfolderobject:f2],
                         [APPDEL Buildfoldername:f2]];
            [f2 release];
        }
        [APPDEL BuildAndCheckFilePathes:song withfm:fm withserverdir:serverdir withCheck:1];

        UIImage *naked = nil;
        if (m_id == -33 || m_id == 1 || m_id == 3) {
            if ([song ID] != -1) {
                BOOL logoOnly = (m_id == -33) && ([[m_pkiosk m_glv] GetSelectedFolderid] != -33);
                int tex = logoOnly ? kThumbSize : (m_id == -33 ? kCoverSize : kThumbSize);
                naked = [[m_pkiosk GetGLView] CreateNakedImage:nil withNumber:0 withClipArray:nil
                                                withclipObject:song withtexturesize:tex
                                               onlychannellogo:logoOnly borderalreadypresent:NO];
            }
        } else if ([song ID] != -1) {
            UIImage *pic = [m_pkiosk GetSongImage:[song m_picturepath] withclipobject:song];
            naked = [[m_pkiosk GetGLView] CreateNakedImage:pic withNumber:0 withClipArray:nil
                                            withclipObject:nil withtexturesize:kThumbSize
                                           onlychannellogo:NO borderalreadypresent:NO];
        }

        // draw into a square bitmap (190 pt on iPad, 120 pt on iPhone)
        float s = [APPDEL m_isipad] ? 190.0f : 120.0f;
        CGContextRef ctx = [APPDEL BeginImageContext:CGSizeMake(s, s)];
        if (naked != nil)   // (original did not test for nil)
            CGContextDrawImage(ctx, CGRectMake(0, 0, s, s), [naked CGImage]);
        [m_mainimgv setImage:[APPDEL EndImageContext:ctx]];
        [self setM_iscolorpic:YES];
        break;
    }
    [songs release];
    [folder release];
    [dbo release];
}

- (void)CheckBlackAndWhite {
    if (m_id == -55) return;
    BOOL selected = NO;
    GLView *glv = [m_pkiosk m_glv];
    if ([glv GetSelectedFolderid] == m_id && m_sid == [[m_pkiosk m_glv] GetSelectedServerid]
        && [[m_pkiosk m_glv] GetSelectedIpodid] == m_ipodid)
        selected = [m_pkiosk selectedSpotifyIDMatches:m_spotifyfolderid];
    BOOL colored = [self m_iscolorpic];
    if (!selected) {
        if (colored) {
            [self setM_iscolorpic:NO];
            [[m_mainimgv image] retain];
            UIImage *bw = [m_pkiosk BlackAndWhitePicture:[m_mainimgv image] withfolderid:m_id];
            [[m_mainimgv image] release];
            [m_mainimgv setImage:bw];
            [bw release];
        }
    } else if (!colored) {
        [self setM_iscolorpic:YES];
        [self SetLastID:0 withipodid:0 withFlag:YES withspotifyid:nil];
    }
}

- (void)Reloadlabel { [m_textlabel setText:m_foldername]; }

- (void)SetFoldername:(id)foldername {
    if (m_foldername != nil) { [m_foldername release]; m_foldername = nil; }
    m_foldername = [[NSString stringWithString:foldername] retain];
}

- (void)RemovePics {
    if ([m_borderimgv superview] != nil) { [m_borderimgv removeFromSuperview]; m_borderimgv = nil; }
    if ([m_mainimgv superview] != nil)   { [m_mainimgv removeFromSuperview];   m_mainimgv = nil; }
    if ([m_reddotimgv superview] != nil) { [m_reddotimgv removeFromSuperview]; m_reddotimgv = nil; }
    if ([m_textlabel superview] != nil)  { [m_textlabel removeFromSuperview];  m_textlabel = nil; }
}

- (void)SetAlpha:(float)alpha {
    [self SetAlphaMainImg:alpha];
    [self SetAlphaBorderAndRedDot:alpha];
    [self SetAlphaText:alpha];
}
- (void)SetAlphaMainImg:(float)a { [m_mainimgv setAlpha:a]; }
- (void)SetAlphaText:(float)a { [m_textlabel setAlpha:a]; }
- (void)SetAlphaBorderAndRedDot:(float)a { [m_reddotimgv setAlpha:a]; [m_borderimgv setAlpha:a]; }

- (int)compareNames:(id)other {
    if ([m_textlabel text] == nil) return 0;
    if ([other GetText] == nil) return 0;
    return (int)[[m_textlabel text] caseInsensitiveCompare:[other GetText]];
}
- (id)GetText { return [m_textlabel text]; }

- (void)SetUp:(id)up withSDO:(id)sDO {
    [self AddToView:up];
    [self OverviewNextMT:sDO];
    if (!m_observeradded) {
        m_observeradded = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(OverviewNext:)
                                                     name:@"MsgOverviewNext" object:nil];
    }
}

- (void)ResizeBorderFrame:(float)dist fromImgv:(id)imgv {
    CGSize sz = [APPDEL GetiPadSize];
    CGRect b = [self CalcBorderFrameFromImgFrame:[imgv frame] withSize:sz adddist:dist];
    [m_borderimgv setFrame:b];
}

- (void)SetFrame:(int)frame {
    CGSize sz = [APPDEL GetiPadSize];
    CGRect f = [self GetFrameForOverViewFolder:frame withsize:sz];
    if ([self m_id] == -55)
        f.origin.y = f.origin.y + ([APPDEL m_isipad] ? 8.0f : 5.0f);
    [m_mainimgv setFrame:f];
    float adddist = 0.0f;
    if (frame == 0 && [self m_id] == -33 && [[m_pkiosk m_glv] GetSelectedFolderid] == -33)
        adddist = 1.0f;
    CGRect b = [self CalcBorderFrameFromImgFrame:[m_mainimgv frame] withSize:sz adddist:adddist];
    [m_borderimgv setFrame:b];
    CGRect l = [self GetFrameForOverViewLabel:frame withsize:sz];
    [m_textlabel setFrame:l];
    [self CalcFrameForRedDot];
}

// The tile border ("stapel" picture) is larger than the picture itself.
- (CGRect)CalcBorderFrameFromImgFrame:(CGRect)img withSize:(CGSize)size adddist:(float)adddist {
    BOOL ipad = [APPDEL m_isipad];
    int adj = (int)((ipad ? 26.0f : 18.0f) * adddist);
    BOOL landscape = size.width > size.height;
    BOOL radio = ([[m_pkiosk m_glv] GetSelectedFolderid] == -33);
    CGRect *mid;
    if (landscape) mid = radio ? &m_midrecthorradio : &m_midrecthor;
    else           mid = radio ? &m_midrectverradio : &m_midrectver;

    CGRect out;
    if (fabsf(img.origin.x - mid->origin.x) < 0.01f &&
        fabsf(img.size.width  - mid->size.width)  < 0.01f &&
        fabsf(img.size.height - mid->size.height) < 0.01f) {
        // the picture sits in its "middle" slot: use the hand-tuned border
        if (!landscape) {
            out = CGRectMake((img.origin.x + -22.0f) + (float)adj,
                             img.origin.y + -16.0f,
                             (img.size.width + 44.0f) - (float)(adj << 1),
                             img.size.height + 43.0f);
        } else if (![APPDEL m_isipad]) {
            out = CGRectMake(((img.origin.x + -27.0f) + (float)adj) + 14.0f,
                             img.origin.y + -11.0f,
                             (img.size.width + 55.0f) - (float)(0x1c + (adj << 1)),
                             img.size.height + 28.0f);
        } else {
            out = CGRectMake((img.origin.x + -27.0f) + (float)adj,
                             img.origin.y + -19.0f,
                             (img.size.width + 55.0f) - (float)(adj << 1),
                             img.size.height + 52.0f);
        }
    } else {
        int base = [APPDEL m_isipad] ? 0xe8 : 0x94;
        out = CGRectMake((img.origin.x - ([APPDEL m_isipad] ? 21.0f : 14.0f)) + (float)adj,
                         img.origin.y - ([APPDEL m_isipad] ? 15.0f : 10.0f),
                         (float)(base - (adj << 1)),
                         (float)base);
    }
    return out;
}

static inline float MTBits(uint32_t b) { union { uint32_t u; float f; } c; c.u = b; return c.f; }

- (void)SetKioskPointer:(id)kioskPointer {
    m_pkiosk = kioskPointer;
    if (![APPDEL m_isipad]) {
        m_midrecthor       = CGRectMake(MTBits(0x43390000), MTBits(0x42a60000), MTBits(0x42dc0000), MTBits(0x42de0000));
        m_midrectver       = CGRectMake(MTBits(0x42f60000), MTBits(0x43480000), MTBits(0x42940000), MTBits(0x42940000));
        m_midrectverradio  = CGRectMake(MTBits(0x42e40000), MTBits(0x432d0000), MTBits(0x42b80000), MTBits(0x42b60000));
        m_midrecthorradio  = CGRectMake(MTBits(0x43080000), MTBits(0x42860000), MTBits(0x43500000), MTBits(0x434f0000));
        return;
    }
    m_midrecthor       = CGRectMake(MTBits(0x43c50000), MTBits(0x43620000), MTBits(0x436c0000), MTBits(0x436c0000));
    m_midrectver       = CGRectMake(MTBits(0x43938000), MTBits(0x43e68000), MTBits(0x43320000), MTBits(0x43310000));
    m_midrecthorradio  = CGRectMake(MTBits(0x43b70000), MTBits(0x43828000), MTBits(0x43920000), MTBits(0x43928000));
    m_midrectverradio  = CGRectMake(MTBits(0x43890000), MTBits(0x43c60000), MTBits(0x435c0000), MTBits(0x435b0000));
}

// notification "MsgOverviewNext": a pre-rendered picture for one folder is ready
- (void)OverviewNext:(NSNotification *)note {
    NSDictionary *d = [note object];
    long long folder = [[d objectForKey:@"ffolder"] longLongValue];
    int server = [[d objectForKey:@"fserver"] intValue];
    long long ipod = [[d objectForKey:@"fipod"] longLongValue];
    id spotify = [d objectForKey:@"fspotify"];
    if (m_id != folder) return;
    if (server != m_sid) return;
    if (m_ipodid != ipod) return;
    if (![m_pkiosk spotifyIDsMatch:spotify withsecondid:[self m_spotifyfolderid]]) return;
    [[m_pkiosk m_glv] LockSDC];
    id sdo = [[m_pkiosk m_glv] GetSDC:[APPDEL CreatePrescrollerKey:m_id withserverid:m_sid
                                                       withipodid:m_ipodid withspotifyid:[self m_spotifyfolderid]]];
    [[m_pkiosk m_glv] UnlockSDC];
    [self performSelectorOnMainThread:@selector(OverviewNextMT:) withObject:sdo waitUntilDone:YES];
}

- (void)OverviewNextMT:(id)sdo {
    [m_textlabel setText:m_foldername];
    if (sdo == nil) {
        UIImage *img = (m_id == -55) ? [UIImage imageNamed:@"rfx-icon.png"] : m_placeholderpointer;
        [m_mainimgv setImage:img];
        return;
    }
    [self setM_duration:[sdo seconds]];
    [self setM_lastsongid:[sdo midid]];
    [self setM_lastipodid:[sdo midipodid]];
    [self setM_iscolorpic:[sdo m_iscolorpic]];
    NSString *sid = nil;
    if ([sdo midspotifyid] != nil) sid = [NSString stringWithFormat:@"%@", [sdo midspotifyid]];
    [self setM_lastspotifyid:sid];
    UIImage *pic = [sdo GetPic];
    [m_mainimgv setImage:pic];
    [pic release];
    [self CreateBorderImage];
    [[m_pkiosk m_glv] LockSDC];
    [[m_pkiosk m_glv] DeleteSDC:[APPDEL CreatePrescrollerKey:m_id withserverid:m_sid
                                                  withipodid:m_ipodid withspotifyid:m_spotifyfolderid]];
    [[m_pkiosk m_glv] UnlockSDC];
}

- (void)SetTimeLabelText:(id)t { [m_timelabel setText:t]; }

- (void)CreateBorderImage {
    if (m_id == -55) return;
    int r = (int)random();
    m_borderindex = (r - ((r + ((r >> 31) & 3)) & ~3)) + 1;      // r % 4 + 1
    [m_borderimgv setImage:[APPDEL NonCachedImage:[NSString stringWithFormat:@"stapel%i", m_borderindex]]];
}

- (void)AddToView:(id)toView {
    if (m_addedtoview) return;
    m_addedtoview = YES;
    [toView addSubview:m_textlabel];   [m_textlabel release];
    [toView addSubview:m_mainimgv];    [m_mainimgv release];
    [toView addSubview:m_borderimgv];  [m_borderimgv release];
    [toView addSubview:m_reddotimgv];  [m_reddotimgv release];
}

- (CGRect)GetFrameForOverViewLabelTime:(int)idx withsize:(CGSize)size {
    CGRect r = [self GetFrameForOverViewFolder:idx withsize:size];
    r.origin.y = r.origin.y + (r.size.height + ([APPDEL m_isipad] ? 34.0f : 30.0f));
    r.size.height = 0;
    r.origin.x += 7.0f;
    r.size.width += -14.0f;
    return r;
}

- (CGRect)GetFrameForOverViewLabel:(int)idx withsize:(CGSize)size {
    CGRect r = [self GetFrameForOverViewFolder:idx withsize:size];
    r.origin.y = r.origin.y + (r.size.height + ([APPDEL m_isipad] ? 16.0f : 13.0f));
    r.size.height = [APPDEL m_isipad] ? 26.0f : 30.0f;
    r.origin.x += 7.0f;
    r.size.width += -14.0f;
    return r;
}

// grid cell `idx`: 4 columns (3 in portrait) on iPad, 3 (2) on iPhone
- (CGRect)GetFrameForOverViewFolder:(int)idx withsize:(CGSize)size {
    int cols, top, gap, cell;
    if (![APPDEL m_isipad]) {
        cols = (size.width < size.height) ? 2 : 3;  top = 0x1e; gap = 0x41; cell = 0x78;
    } else {
        cols = (size.width < size.height) ? 3 : 4;  top = 0x6a; gap = 0x51; cell = 0xbe;
    }
    int row = idx / cols;
    int col = idx % cols;
    int margin = (int)((size.width - (float)(cols * cell)) / (float)(cols + 1));
    return CGRectMake((float)(margin + (margin + cell) * col),
                      (float)(top + row * (gap + cell)),
                      (float)cell, (float)cell);
}

- (CGRect)GetPicFrame { return [m_mainimgv frame]; }
@end
