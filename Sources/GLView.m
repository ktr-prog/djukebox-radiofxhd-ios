// GLView : UIView -- decompiled from Radiofx_iPad (armv7), ported to arm64 / modern iOS.
// The OpenGL ES 1.1 coverflow ("rondell") of the cover tiles.  Manual reference counting.
// Feature groups that belong to the dead backend (live-radio channel view -33, Spotify, EPG, card reader,
// advertising, remote control, third-party UI) are not part of this file; see DEVIATIONS.md.
#import "GLView.h"
#import "MultichannelMixerController.h"
#import "KioskView.h"
#import "KeyboardView.h"
#import "MTScroller.h"
#import "MTObject.h"
#import "RadioAppDelegate.h"
#import "DBOperations.h"
#import "FolderObject.h"
#import "ClipObject.h"
#import "CGPointObject.h"
#import "DataCache.h"
#import "FlowCoverRecord.h"
#import "ServerEntry.h"
#import "Globals.h"
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES1/glext.h>

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])
#define ISIPAD ([DEL m_isipad])

// original globals gv_34e760 / gv_34e764 (texture edge for normal tiles / channel tiles) and data_00398838
int  gv_texsize      = 0x200;   // 512 (original: 196; raised so the covers are no longer pixelated; 512*512*4 == the 1 MB GData buffer)
int  gv_texsizeradio = 0x200;   // 512
static BOOL gv_texfallback  = NO;

// texture coordinate tables of the original (data_00305250 / 305290)
static const GLfloat kTexCoordMain[8]    = { 0, 1,  1, 1,  0, 0,  1, 0 };
static const GLfloat kTexCoordReflect[8] = { 0, 0.5f, 1, 0.5f, 0, 0, 1, 0 };

// Water level of the cover that belongs to a plugin title that is loading (see SetWaterForClipID:level:)
BOOL gRfxBetaLook = NO;       // dev menu: layout of the first Tobit Djukebox
static long long gRfxWaterID = 0;
static float gRfxWaterTarget = 0.0f;
static float gRfxWaterShown = 0.0f;
static BOOL gRfxWaterOn = NO;

@implementation GLView

@synthesize context, viewFramebuffer, viewRenderbuffer;
@synthesize m_selectedspotifyfolderid, m_cancelcard, m_autogotofolder, m_autogotoserver, m_id_to_delete;
@synthesize m_oglversion, m_selectedipodid, m_threadwaiting, m_volumepinch, m_sidtexturestodelete;
@synthesize m_moveTACInitTime, m_radioanivar, m_preventdragging, m_selectedserverid, m_lastpinchoffset;
@synthesize m_lastmtovsearchtime, m_lastplayedchannelid, m_advertinittime, m_idleinittime, touchisok, m_idleflag;
@synthesize m_pinchstatus, m_newselectedfolderindex, m_movingup, m_lastflags, m_autoremovekeyboard;
@synthesize m_fingersonscreen, m_pinching, m_executingflags, m_selectedfolderid, m_specialtexture;
@synthesize m_trytorestorespotifyid, m_statusText, m_saStatusID, m_newcardfound;
@synthesize m_clipstodelete, m_yup, m_rotateready, m_drawemptyturn, m_drawempty, m_origarray, m_tilearray, m_autospin;

#pragma mark - init / setup

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) return nil;
    return [self internalInit];
}

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self == nil) return nil;
    return [self internalInit];
}

- (id)internalInit {
    m_selectedspotifyfolderid = nil;
    m_autogotofolder = -1;
    m_autogotoserver = -1;
    m_threadwaiting = NO;
    viewFramebuffer = 0;
    viewRenderbuffer = 0;
    m_sidtexturestodelete = -1;
    m_direction = -1;
    m_directioncounter = 0;
    m_pointbefore = CGPointZero;
    m_id_to_delete = -1;
    m_deleteexplodefactor = 1.0f;
    m_deletestartpoint = CGPointZero;
    m_deletestartpointindex = -1;
    m_moveTACInitTime = -1.0;
    m_radioanivar = 0;
    m_preventdragging = 0;
    m_prescrollerthreaddone = NO;
    m_lastmidindex = -2;
    m_initcd = NO;
    m_parent = nil;
    [self setM_specialtexture:nil];
    m_draggingpicture = NO;
    m_draggingobject = nil;
    m_clipstodelete = [[NSMutableArray alloc] init];
    touchisok = NO;
    m_autospin = NO;
    m_selectedfolderid = -1;
    m_selectedserverid = -1;
    m_selectedipodid = 0;
    m_idleinittime = -1.0;
    m_advertinittime = -1.0;
    m_executingflags = NO;
    m_channelaniimageview = nil;
    m_blackview = nil;
    m_kioskscreenshot = nil;
    m_movingregisters = NO;
    m_pinchstatus = 0;
    m_newselectedfolderindex = 0;
    m_lastpinchoffset = -1;
    m_fingersonscreen = 0;
    m_autoremovekeyboard = NO;
    m_rondell_loaded = NO;
    m_movingup = NO;
    m_mtscroller = nil;
    m_idleflag = NO;
    m_showonlysearch = NO;
    p_newfolder = nil;
    m_blinkpic = NO;
    m_isblinking = NO;
    m_blinkpicsync = NO;
    m_blinkanirunning = NO;
    m_shouldblinksync = 0;
    m_lastplayedchannelid = -1;
    m_lastmetatitle = nil;
    m_lastmetainterpret = nil;
    m_startedpicthread = NO;
    m_memorywarning = NO;
    m_drawemptyturn = NO;
    m_rotateready = NO;
    context = nil;
    m_blacktexture = nil;
    m_blacktextureradio = nil;
    m_placeholdertexture = nil;
    m_placeholdertextureradio = nil;
    m_tryrestoreoffset = -1;
    m_trytorestorespotifyid = nil;
    m_oglversion = 0;
    m_mtoverviewlock = [[NSLock alloc] init];
    m_deletetexturelock = [[NSLock alloc] init];
    m_deletetexqueue = [[NSMutableArray alloc] init];
    m_prescrollerdict = [[NSMutableDictionary alloc] init];
    m_prescrollerlock = [[NSLock alloc] init];
    m_conditioncounter[0] = 0;
    m_tracktable = nil;
    m_tracksong = nil;
    m_dimmview = nil;
    m_notconview = nil;
    m_sapointobject = nil;
    m_sarstatus = 0;
    m_newcardfound = nil;
    m_saDoubleTapCo = nil;
    m_saStatusID = nil;
    m_statusText = nil;
    m_askbox = nil;
    m_brandingpictimer = nil;
    m_condition[0] = [[NSCondition alloc] init];
    GData = (unsigned char *)malloc(1048576);
    GDataThread = (unsigned char *)malloc(1048576);

    [self setBackgroundColor:[UIColor colorWithWhite:0.0f alpha:1.0f]];

    // render scale: the original used 2.0 only when the screen mode is 640x960 (iPhone 4), else 1.0.
    // Everything else (all iPads) renders at 1.0 and is scaled up by the system.
    m_oglscale = 1.0f;
    {
        CGSize sz = [[[UIScreen mainScreen] currentMode] size];
        if ((int)sz.width == 0x280 && (int)sz.height == 0x3c0) m_oglscale = 2.0f;
    }
    if (m_oglscale > 1.0f) {
        [self setContentScaleFactor:m_oglscale];
        [[self layer] setContentsScale:m_oglscale];
    }

    m_tilearray = [[NSMutableArray alloc] init];
    m_origarray = [[NSMutableArray alloc] init];
    m_randomarray = [[NSMutableArray alloc] init];
    m_orderbeforejumping = [[NSMutableArray alloc] init];
    m_arraylock = [[NSLock alloc] init];

    CGSize pad = [DEL GetiPadSize];
    m_ishorizontal = pad.width > pad.height;
    [self SetDrawVars:pad];
    [self SetUpTippRects];
    m_lastTouchTime = CACurrentMediaTime();
    m_idleReturned = YES;
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(CheckReturnToPlaying) userInfo:nil repeats:YES];

    // red-dot (new/unread marker) and "foreground" (flip-side cover) rectangles; [0] = portrait, [1] = landscape
    m_reddotrects[0] = CGRectMake(433.0f, 459.0f, 30.0f, 31.0f);
    m_reddotrects[1] = CGRectMake(578.0f, 226.0f, 38.0f, 40.0f);
    m_reddotrectssmall[0] = CGRectMake(230.0f, 100.0f, 20.0f, 20.0f);
    m_reddotrectssmall[1] = CGRectMake(260.0f, 80.0f, 28.0f, 28.0f);
    [self SetRedDotRect:pad];
    m_foregroundrects[0] = CGRectMake(250.0f, 425.0f, 270.0f, 285.0f);
    m_foregroundrects[1] = CGRectMake(332.0f, 210.0f, 358.0f, 378.0f);
    m_foregroundrectssmall[0] = CGRectMake(50.0f, 425.0f, 200.0f, 200.0f);
    m_foregroundrectssmall[1] = CGRectMake(165.0f, 65.0f, 150.0f, 162.0f);
    [self SetForegroundRect:pad];

    offset = 0;
    m_flipping = NO;
    gRfxBetaLook = [[NSUserDefaults standardUserDefaults] boolForKey:@"RfxDevBetaLook"];
    m_anglediff = 14.583333333333334;           // 0x402CAAAAAAAAAAAB
    cache = [[DataCache alloc] initWithCapacity:0x6e];
    [cache SetGLPointer:self];
    // (all four fade angles are 1.5 degrees lower than the original, matching the centred flow)
    m_transangles[1] = 354.5;
    m_transangles[0] = 354.5 - m_anglediff;
    if (m_transangles[0] < 0) m_transangles[0] += 360.0;
    m_transangles[2] = -1.5;
    m_transangles[3] = m_anglediff + 182.5;

    paintorder = [[NSMutableArray alloc] init];
    pictureorder = [[NSMutableArray alloc] init];
    m_colors = (float *)malloc(0x40);
    // 4 vertices x RGBA: white, with alpha 0,0,0.5,0.5 (the original start values)
    static const float c0[16] = { 1,1,1,0,  1,1,1,0,  1,1,1,0.5f,  1,1,1,0.5f };
    memcpy(m_colors, c0, sizeof(c0));

    [self ReInit:NO];
    [self CreatePlaceholderTextures];

    m_titlelabel = [[UILabel alloc] initWithFrame:[self GetTitleInterpretLabelFrame:pad withtype:0]];
    [m_titlelabel setText:@""];
    [m_titlelabel setTextColor:[UIColor whiteColor]];
    [m_titlelabel setBackgroundColor:[UIColor clearColor]];
    [m_titlelabel setFont:[UIFont boldSystemFontOfSize:ISIPAD ? 22.0f : 16.0f]];
    [m_titlelabel setTextAlignment:NSTextAlignmentCenter];
    [self addSubview:m_titlelabel];
    [m_titlelabel release];

    m_interpretlabel = [[UILabel alloc] initWithFrame:[self GetTitleInterpretLabelFrame:pad withtype:1]];
    [m_interpretlabel setText:@""];
    [m_interpretlabel setTextColor:[UIColor grayColor]];
    [m_interpretlabel setBackgroundColor:[UIColor clearColor]];
    [m_interpretlabel setFont:[UIFont systemFontOfSize:ISIPAD ? 17.0f : 12.0f]];
    [m_interpretlabel setTextAlignment:NSTextAlignmentCenter];
    [self addSubview:m_interpretlabel];
    [m_interpretlabel release];

    [self CreateBlackTexture:&m_blacktexture];
    m_volumepinch = -1.0f;
    m_pinchGesture = nil;
    [self setMultipleTouchEnabled:YES];
    [self setM_pinching:NO];
    [self AddPinch:1];

    m_doubletapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    [m_doubletapGestureRecognizer setDelegate:self];
    [m_doubletapGestureRecognizer setNumberOfTapsRequired:2];
    [self addGestureRecognizer:m_doubletapGestureRecognizer];
    [m_doubletapGestureRecognizer release];

    m_tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    [m_tapGestureRecognizer setNumberOfTapsRequired:1];
    [m_tapGestureRecognizer requireGestureRecognizerToFail:m_doubletapGestureRecognizer];
    [self addGestureRecognizer:m_tapGestureRecognizer];
    [m_tapGestureRecognizer setDelegate:self];
    [m_tapGestureRecognizer release];

    [self performSelector:@selector(RestartIdleTimer) withObject:nil afterDelay:0];
    return self;
}

- (void)dealloc {
    [self StopIdleTimer];
    if (m_brandingpictimer != nil) { [m_brandingpictimer invalidate]; m_brandingpictimer = nil; }
    m_drawempty = YES;
    [self destroyFramebuffer];
    [cache release];
    [paintorder release];
    [pictureorder release];
    if (m_colors != NULL) free(m_colors);
    if (GData != NULL) free(GData);
    if (GDataThread != NULL) free(GDataThread);
    [m_tilearray release];
    [m_origarray release];
    [m_randomarray release];
    [m_orderbeforejumping release];
    [m_arraylock release];
    [m_clipstodelete release];
    [m_blacktexture release];
    [m_blacktextureradio release];
    [m_placeholdertexture release];
    [m_placeholdertextureradio release];
    [m_condition[0] release];
    [m_mtoverviewlock release];
    [m_deletetexturelock release];
    [m_deletetexqueue release];
    [m_prescrollerdict release];
    [m_prescrollerlock release];
    [m_selectedspotifyfolderid release];
    [m_trytorestorespotifyid release];
    [super dealloc];
}

- (void)SetDrawVars:(CGSize)drawVars {
    if (drawVars.width <= drawVars.height) {
        m_yup = 1.5f;
        m_inclineangle = 13.0f;
    } else {
        m_yup = -1.0f;
        if (!ISIPAD) m_yup = m_yup + -0.25f;
        m_inclineangle = 26.0f;
    }
}

// The seven tap-test rectangles of the visible covers.
- (void)SetUpTippRects {
    CGSize pad = [DEL GetiPadSize];
    int r1, r2;
    BOOL landscape = pad.width > pad.height;
    r1 = landscape ? 0xe1 : 0x19f;
    r2 = landscape ? 0x1fe : 0x280;
    if (!ISIPAD) {
        // the original shifted the rectangles for the phone layout
        if (0.5f >= [[UIScreen mainScreen] scale]) { r1 -= 0xa5; r2 -= 0x11d; }
        else                                      { r1 -= 0xe6; r2 -= 0x15e; }
    }
    if (ISIPAD && landscape) {
        // the flow is drawn with a fixed horizontal field of view, so it scales with the width and stays centred vertically
        float k = pad.width / 1024.0f, mid = pad.height * 0.5f;
        r1 = (int)(mid + ((float)r1 - 384.0f) * k);
        r2 = (int)(mid + ((float)r2 - 384.0f) * k);
    }
    if (ISIPAD && !landscape) {
        float k = pad.width / 768.0f, mid = pad.height * 0.5f;
        r1 = (int)(mid + ((float)r1 - 512.0f) * k);
        r2 = (int)(mid + ((float)r2 - 512.0f) * k);
    }
    double w2 = (double)(int)(pad.width * 0.5f);
    static const double fx[7] = { 0.0, 0.12, 0.36, 0.776, 1.224, 1.64, 1.88 };
    static const double fw[7] = { 0.12, 0.24, 0.416, 0.448, 0.416, 0.24, 0.12 };
    static const double bx[7] = { 0.0, 0.12, 0.28, 0.776, 1.224, 1.72, 1.88 };      // beta look: wider rectangles for the neighbours
    static const double bw[7] = { 0.12, 0.16, 0.496, 0.448, 0.496, 0.16, 0.12 };
    for (int i = 0; i < 7; i++)
        m_tipprects[i] = CGRectMake((float)(w2 * (gRfxBetaLook ? bx[i] : fx[i])), (float)r1, (float)(w2 * (gRfxBetaLook ? bw[i] : fw[i])), (float)(r2 - r1));
}

// Original positions (1024x768 design). On other screen sizes the block is scaled about the vertical screen centre
// by the same factor as the covers (width / 1024), so spacing and heights stay in the original proportions.
- (CGRect)GetTitleInterpretLabelFrame:(CGSize)frame withtype:(int)type {
    int y;
    BOOL ipad = ISIPAD;
    int base = (frame.width > frame.height) ? 0x8c : 0x103;
    if (!ipad) base -= 0x69;
    if (type == 1) y = base + (ipad ? 0x1e : 0x19); else y = base;
    float fy = (float)y;
    if (ipad && frame.width > frame.height) {
        float k = frame.width / 1024.0f, mid = frame.height * 0.5f;
        fy = mid + (fy - 384.0f) * k;
    }
    float w = ipad ? 580.0f : 245.0f;
    return CGRectMake((frame.width - w) * 0.5f, fy, w, type != 1 ? 30.0f : 20.0f);
}

- (void)layoutSubviews {
    if (m_pinching) return;
    CGSize pad = [DEL GetiPadSize];
    [m_interpretlabel setFrame:[self GetTitleInterpretLabelFrame:pad withtype:1]];
    [m_titlelabel setFrame:[self GetTitleInterpretLabelFrame:pad withtype:0]];
}

- (id)context { return context; }

#pragma mark - OpenGL ES 1.1 setup

- (void)OpenGLInit {
    CAEAGLLayer *l = (CAEAGLLayer *)[self layer];
    [l setOpaque:YES];
    [l setDrawableProperties:[NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking,
                              kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil]];
    m_oglversion = 0;
    context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
    if (context == nil) return;
    if ([EAGLContext setCurrentContext:context]) m_oglversion = 1;
}

- (BOOL)createFramebuffer {
    glGenFramebuffersOES(1, &viewFramebuffer);
    glGenRenderbuffersOES(1, &viewRenderbuffer);
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer *)[self layer]];
    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
    if (glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES)
        return NO;
    glEnable(GL_TEXTURE_2D);
    glEnable(GL_DEPTH_TEST);   // 0xb71 (there is no depth attachment, so this has no visible effect)
    glMatrixMode(GL_PROJECTION);
    float t = tanf(0.9599311f);                              // 0x3f75be0b
    CGRect b = [self bounds];
    float bw = m_oglscale > 1.0f ? b.size.width * m_oglscale : b.size.width;
    float bh = m_oglscale > 1.0f ? b.size.height * m_oglscale : b.size.height;
    float top = t * 0.01f;
    glFrustumf(-top, top, -top / (bw / bh), top / (bw / bh), 0.01f, 1000.0f);
    glViewport(0, 0, (int)bw, (int)bh);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    return YES;
}

- (void)destroyFramebuffer {
    if (viewFramebuffer != 0) { glDeleteFramebuffersOES(1, &viewFramebuffer); viewFramebuffer = 0; }
    if (viewRenderbuffer != 0) { glDeleteRenderbuffersOES(1, &viewRenderbuffer); viewRenderbuffer = 0; }
    if ([EAGLContext currentContext] == context) [EAGLContext setCurrentContext:nil];
    if (context != nil) { [context release]; context = nil; }
}

- (void)ReInit:(BOOL)reInit {
    [self destroyFramebuffer];
    [self OpenGLInit];
    [self createFramebuffer];
}

#pragma mark - drawing

// ---- beat pulse of the playing cover ----------------------------------------------------------------
static float gBeatPulse = 0.0f, gBeatEnv = 0.0f, gBeatAvg = 0.0f;
static double gBeatT = 0;
static BOOL gBeatFrame = NO;           // drawIntern wants another frame although nothing else animates

static void RfxBeatUpdate(BOOL playing) {
    double now = CACurrentMediaTime();
    double dt = now - gBeatT; gBeatT = now;
    if (dt < 0.0 || dt > 0.1) dt = 0.1;
    float lvl = playing ? RfxBeatLevel() : 0.0f;
    gBeatEnv = (lvl > gBeatEnv) ? lvl : gBeatEnv + (lvl - gBeatEnv) * (float)(1.0 - exp(-dt / 0.12));
    gBeatAvg += (lvl - gBeatAvg) * (float)(1.0 - exp(-dt / 1.5));
    float target = (gBeatAvg > 0.003f) ? (gBeatEnv - gBeatAvg * 1.05f) / (gBeatAvg * 0.9f + 0.01f) : 0.0f;
    if (target < 0.0f) target = 0.0f; if (target > 1.0f) target = 1.0f;
    gBeatPulse = (target > gBeatPulse) ? target : gBeatPulse + (target - gBeatPulse) * (float)(1.0 - exp(-dt / 0.09));
    gBeatFrame = playing && (lvl > 0.002f || gBeatPulse > 0.004f);
}

// is this tile the title that is playing (or an album that contains it)?
static BOOL RfxTileIsPlaying(ClipObject *tile, ClipObject *pl) {
    if (tile == nil || pl == nil) return NO;
    if ([tile m_tracks] != nil) {
        for (ClipObject *tr in [tile m_tracks]) {
            if ([tr m_folderid] == -44 ? ([tr m_ipodid] == [pl m_ipodid]) : ([tr ID] == [pl ID])) return YES;
        }
    }
    return [tile m_folderid] == -44 ? ([tile m_ipodid] == [pl m_ipodid]) : ([tile ID] == [pl ID]);
}

- (void)drawView {
    if ([DEL m_isinbackground]) return;
    [self GetArrayLock:NO];
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
    BOOL again = [self drawIntern];
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
    [context presentRenderbuffer:GL_RENDERBUFFER_OES];
    [m_arraylock unlock];
    if (!again && !gBeatFrame) return;
    if ([self m_fingersonscreen] != 0) return;
    if (timer != nil || [self m_autospin]) return;
    // exactly one pending follow-up frame: several callers of drawView used to start a chain each, the chains piled up and
    // the carousel got sluggish after a while.  60 frames per second while something animates.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(drawView) object:nil];
    [self performSelector:@selector(drawView) withObject:nil afterDelay:(again ? 1.0 / 60.0 : 1.0 / 40.0)];
}

// Fills the paint order (the angular slot of every tile) and the picture order (index into the tile array).
// Slots 0..N-1 are the covers on the left, 2N..N+1 the covers on the right and 6 the centre cover.
- (void)FillArrays:(NSMutableArray *)paint withPicOrder:(NSMutableArray *)pics {
    int n = (int)[[self m_tilearray] count];
    if (n == 0) return;
    int N = ([self m_selectedfolderid] == -33) ? 0xc8 : 6;
    int c = (int)offset;
    if (c > n - 1) c = n - 1;
    if (c <= -1) {
        int r = c + n;
        if (r < 0) r = 0;
        c = (r < n) ? r : n - 1;
    }
    int cnt = 2 * N - 1;
    // left side
    {
        int r8 = c - N;
        int r10 = (N - 1) - c;
        int r6 = (c > c + 1 - N) ? c : c + 1 - N;
        do {
            int idx;
            if (r8 > -1) idx = r8;
            else {
                idx = -1;
                if (!(n < cnt)) idx = (n - 1) - (r10 % n);
            }
            r8++;
            r10--;
            [pics addObject:[NSNumber numberWithInt:idx]];
        } while (r6 != r8);
    }
    // right side
    {
        BOOL wrapok = (n >= cnt);
        int r8 = N + c;
        int r1 = (-N - c > ~c) ? (-N - c) : ~c;
        int r5 = ~r1;
        do {
            int m = r8 % n;
            int idx = (r8 < n || wrapok) ? m : -1;
            [pics addObject:[NSNumber numberWithInt:idx]];
            r8--;
        } while (r5 != r8);
    }
    [pics addObject:[NSNumber numberWithInt:c]];
    for (int i = 0; i < N; i++) [paint addObject:[NSNumber numberWithInt:i]];
    if ((unsigned)(2 * N) > (unsigned)N) {
        int r12 = ~N;
        int t = 0 - 2 * N;
        if (t > r12) r12 = t;
        int stop = ~r12;
        int r6 = 2 * N;
        do {
            [paint addObject:[NSNumber numberWithInt:r6]];
            r6--;
        } while (stop != r6);
    }
    [paint addObject:[NSNumber numberWithInt:6]];
}

- (FlowCoverRecord *)getTileAtIndex:(int)tileAtIndex withCreate:(BOOL)create {
    if (tileAtIndex < 0) return nil;
    if ((unsigned)[[self m_tilearray] count] <= (unsigned)tileAtIndex) return nil;
    ClipObject *clip = [[self m_tilearray] objectAtIndex:tileAtIndex];
    [clip retain];
    id key = [DEL CreateTextureKey:clip];
    FlowCoverRecord *rec = [cache objectForKey:key];
    if (rec == nil) {
        if (create) {
            UIImage *img = nil;
            BOOL special = ([clip m_folderid] == 3 || [clip m_folderid] == 1 || [clip m_folderid] == -33) && [clip ID] != -5;
            if (!special) {
                [m_arraylock unlock];
                img = [m_parent GetSongImage:[clip m_picturepath] withclipobject:clip];
                [self GetArrayLock:YES];
                int ntracks = [clip m_tracks] ? (int)[[clip m_tracks] count] : 0;
                GLuint tex = [self imageToTexture:img withNumber:ntracks withClipArray:nil withclipObject:nil borderalreadypresent:NO];
                rec = [[FlowCoverRecord alloc] initWithTexture:tex];
            } else {
                GLuint tex = [self imageToTexture:nil withNumber:0 withClipArray:nil withclipObject:clip borderalreadypresent:NO];
                rec = [[FlowCoverRecord alloc] initWithTexture:tex];
            }
            if ([clip m_tracks] != nil) [rec setPercent:100];
            [cache setObject:rec forKey:key];
            [rec release];
        } else {
            rec = ([self m_selectedfolderid] != -33) ? m_placeholdertexture : m_placeholdertextureradio;
        }
    }
    [clip release];
    return rec;
}

// The drawing routine of the coverflow.  Returns YES while an animation (loading fade-in) needs another frame.
// The seven visible covers are drawn from their angular slot; every cover is followed by its reflection.
- (BOOL)drawIntern {
    int count = (int)[[self m_tilearray] count];
    BOOL again = NO;                                   // [sp+0xc4]
    if (viewRenderbuffer == 0 || viewFramebuffer == 0 || context == nil) return NO;

    glLoadIdentity();
    glClearColor(0, 0, 0, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    if (count == 0) {
        m_lastmidindex = -2;
        [m_interpretlabel setText:@""];
        [m_titlelabel setText:@""];
        return NO;
    }
    if ([self m_drawempty]) return NO;
    if ([self m_drawemptyturn]) return NO;

    // tile half size (the original used other values for the live radio view only)
    const float kA = 1.09f;
    float pinchScale = m_pinchscale;

    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glTranslatef(0, 0, -8.5f);
    glScalef(0.48f, 0.48f, 0.48f);
    glTexCoordPointer(2, GL_FLOAT, 0, kTexCoordMain);

    int mid = (int)(offset + 0.5);
    int floorIdx = (int)offset;
    if (floorIdx > count - 1) floorIdx = count - 1;
    if (mid != m_lastmidindex) {
        m_lastmidindex = mid;
        [self SetLabelTexts:[NSNumber numberWithInt:mid]];
    }
    double offsetD = offset;
    [paintorder removeAllObjects];
    [pictureorder removeAllObjects];
    [self FillArrays:paintorder withPicOrder:pictureorder];
    if ([paintorder count] == 0) return NO;

    ClipObject *playingClip = nil;
    {
        NSArray *pcl = [m_parent m_clips];
        BOOL pl = ([pcl count] > 0 && [m_parent IsPlayingClips] && [self m_selectedfolderid] != -33);
        if (pl) playingClip = [pcl objectAtIndex:0];
        RfxBeatUpdate(pl);
    }
    double frac = offsetD - (double)(float)floorIdx;                 // [sp+16]
    float maxPinch = pinchScale > 0.0f ? pinchScale : 0.0f;           // s0
    float P = maxPinch > 1.0f ? 1.0f : maxPinch;                      // s2
    float pinch2 = maxPinch * maxPinch;
    float P2 = P * P;
    double R1pinch = (double)(P2 * 7.2f);                             // [sp+96]
    double R2pinch = (double)(pinch2 * 8.9f);                         // [sp+104]
    double pm1 = (double)P2 + -1.0;                                   // [sp+24]
    double pm1neg = -pm1;                                             // [sp+40]

    for (int i = 0; i < (int)[paintorder count]; i++) {
        int k = [[paintorder objectAtIndex:i] intValue];
        int tileIdx = [[pictureorder objectAtIndex:i] intValue];
        if (tileIdx == -1) continue;
        glTexCoordPointer(2, GL_FLOAT, 0, kTexCoordMain);
        FlowCoverRecord *tile = [self getTileAtIndex:tileIdx withCreate:NO];

        // angle of this cover
        // DEVIATION: the original constant was 94.0, which puts the middle cover (k = 6) at 271.5 degrees instead of
        // 270 and shifts the whole flow to the right.  92.5 centres it; the fade angles below move with it.
        double ang = ((double)(float)k * m_anglediff + 92.5 + 90.0) - m_anglediff * frac;
        while (ang > 360.0) ang += -360.0;
        double ang2 = ang + 180.0;
        while (ang2 > 360.0) ang2 += -360.0;
        double t1 = m_transangles[1] + 180.0;
        while (t1 > 360.0) t1 += -360.0;
        double t0 = m_transangles[0] + 180.0;
        while (t0 > 360.0) t0 += -360.0;
        double rad  = ang / 180.0 * M_PI;
        double nrad = ang / 180.0 * -M_PI;
        double dT = t1 - ang2;
        BOOL outside = (ang2 <= t0) || (ang2 >= t1);

        // alpha of this cover (fade in/out at the two ends of the rondell)
        double alpha;
        double ta2 = m_transangles[2], ta3 = m_transangles[3];
        if (ang > ta2 && ang < ta3) alpha = (ang - ta2) / m_anglediff;
        else if (!outside)          alpha = dT / m_anglediff;
        else if (ang > ta2)         alpha = 1.0;
        else if (ang < m_transangles[1]) alpha = 1.0;
        else                        alpha = 0.0;
        glColor4f(1.0f, 1.0f, 1.0f, (float)alpha);

        double cs = cos(rad);
        double sn = sin(nrad);
        BOOL pinching = [self m_pinching];
        double R1 = pinching ? R1pinch : 7.2;
        double R2 = pinching ? R2pinch : 8.9;
        double Z = R1 + R1 * sn;                                      // depth of the cover
        if ([self m_pinching]) {
            double q = pm1;
            if (q < 0) q = pm1neg;
            Z += q * 14.4;
        }
        double xc = R2 * cs;                                          // horizontal position
        double betaA = -1.0, betaS = 1.0, betaLift = 0.0;
        if (gRfxBetaLook && ![self m_pinching] && [self m_selectedfolderid] != -33) {
            // dev menu "Beta-Look": the first Tobit Djukebox (see the pictures): the cover in the middle is the biggest, the two
            // neighbours sit right next to it (a little smaller, tiny gap, same baseline), behind each of them the next covers are
            // piled up - every layer a bit further out, a bit higher (it peeks out above the cover in front) and a bit smaller.
            // All covers face the front; every cover keeps its reflection.
            double rel = (double)k - 6.0 - frac;
            double a = fabs(rel), sg = (rel < 0) ? -1.0 : 1.0;
            double layer = fmin(fmax(a - 1.0, 0.0), 2.4);
            betaA = a;
            betaS = (a < 1.0) ? (1.0 - 0.14 * a) : (0.86 - 0.06 * layer);
            betaLift = 0.42 * layer;
            xc = sg * (a < 1.0 ? a * 2.32 : 2.32 + layer * 0.30 + fmax(a - 3.4, 0.0) * 0.3);
            Z = 14.4;      // coplanar: the perspective would otherwise shrink the neighbours/piles a second time on top of betaS (they came out much too small)
            if (a > 3.0) alpha *= fmax(0.0, 1.0 - (a - 3.0) / 0.6);       // the pile ends after three layers
        }
        double yShift = (Z * sin((double)m_inclineangle / 180.0 * -M_PI)) * -0.125;
        if (betaA >= 0.0) yShift += betaLift - (double)kA * (1.0 - betaS);      // bottoms of the neighbours on the baseline, piled covers lifted
        float flipY;
        if (backingWidth > backingHeight) flipY = ISIPAD ? -0.24f : 0.01f;
        else flipY = 0.3f;

        BOOL flipLast = m_flipping && (i == (int)[paintorder count] - 1);
        double fdy = 0, fdz = 0, fx = 0, fz = 0;
        float Zf = (float)Z;
        float Yc = 0;

        if (flipLast) {
            // the flipping cover: turns around its vertical axis to show the track list
            double ff = m_flippingangle / 180.0;
            double frad = ff * M_PI;
            double fc = cos(frad), fs = sin(frad);
            fdy = ff * (double)flipY;
            fdz = ff * 1.1;
            fx = (double)kA * fc;
            fz = (double)kA * fs;
            FlowCoverRecord *tex;
            if (m_flippingangle >= 90.0) {
                if ([self m_specialtexture] == nil) {
                    GLuint t = [self imageToTexture:nil withNumber:0
                                      withClipArray:[[[self m_tilearray] objectAtIndex:tileIdx] m_tracks]
                                      withclipObject:nil borderalreadypresent:NO];
                    [self setM_specialtexture:[[FlowCoverRecord alloc] initWithTexture:t]];
                }
                fz = -fz;
                fx = -fx;
                tex = [self m_specialtexture];
            } else {
                tex = tile;
            }
            glBindTexture(GL_TEXTURE_2D, [tex texture]);
            float zf = (float)(Z + fdz);
            float yup = m_yup;
            Zf = zf;
            float ycf = (float)((yShift + fdy) + (double)yup);
            GLfloat v[12];
            memset(v, 0, sizeof(v));
            float x0 = (float)(xc - fx), z0 = (float)((double)zf - fz);
            float x1 = (float)(fx + xc), z1 = (float)((double)zf + fz);
            float yTop = kA + ycf, yBot = ycf - kA;
            v[0] = x0; v[1] = yTop; v[2] = z0;
            v[3] = x1; v[4] = yTop; v[5] = z1;
            v[6] = x0; v[7] = yBot; v[8] = z0;
            v[9] = x1; v[10] = yBot; v[11] = z1;
            glVertexPointer(3, GL_FLOAT, 0, v);
            Yc = ycf;
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        } else {
            Yc = (float)(yShift + (double)m_yup);
            glEnableClientState(GL_COLOR_ARRAY);
            // depth dimming
            float sh = (float)(((double)Zf - 4.5) / 9.92);
            sh = sh * sh;
            sh = sh * sh;
            double shd = (double)sh;
            if (shd > 1.0) shd = 1.0;
            float shade = (float)shd;
            if (shd < 0.1) shade = 0.1f;
            if (betaA >= 0.0) shade = (betaA <= 1.0) ? 1.0f : (float)fmax(0.45, 1.0 - 0.25 * (betaA - 1.0));

            float hh;
            int pct = [tile percent];
            if (pct > 99) {
                hh = kA;
            } else {
                // not yet loaded: draw the placeholder and let the cover grow into place
                int p1 = [tile percent];
                GLfloat q[12];
                memset(q, 0, sizeof(q));
                float x0 = (float)(-(double)kA + xc), x1 = (float)((double)kA + xc);
                float z = (float)((double)Zf + -0.001);
                float yTop = kA + Yc, yBot = Yc - kA;
                q[0] = x0; q[1] = yTop; q[2] = z;
                q[3] = x1; q[4] = yTop; q[5] = z;
                q[6] = x0; q[7] = yBot; q[8] = z;
                q[9] = x1; q[10] = yBot; q[11] = z;
                int p2 = [tile percent];
                double d = (double)(float)p2 / -100.0 + 1.0;
                d = d * alpha;
                float a = (float)d;
                for (int v = 0; v < 4; v++) {
                    m_colors[v * 4 + 0] = shade;
                    m_colors[v * 4 + 1] = shade;
                    m_colors[v * 4 + 2] = shade;
                    m_colors[v * 4 + 3] = a;
                }
                glColorPointer(4, GL_FLOAT, 0, m_colors);
                glBindTexture(GL_TEXTURE_2D, [m_placeholdertexture texture]);
                glVertexPointer(3, GL_FLOAT, 0, q);
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
                hh = (kA * (float)p1) / 100.0f;
                again = YES;
            }
            glBindTexture(GL_TEXTURE_2D, [tile texture]);
            ClipObject *clipForId = [[self m_tilearray] objectAtIndex:tileIdx];
            if ([clipForId ID] == m_id_to_delete) hh = hh * m_deleteexplodefactor;
            if (betaA >= 0.0) hh *= (float)betaS;
            if (gBeatPulse > 0.001f && RfxTileIsPlaying(clipForId, playingClip)) hh *= 1.0f + 0.055f * gBeatPulse;     // the playing cover beats with the music
            GLfloat q[12];
            memset(q, 0, sizeof(q));
            float x0 = (float)(xc - (double)hh), x1 = (float)((double)hh + xc);
            float yTop = hh + Yc, yBot = Yc - hh;
            q[0] = x0; q[1] = yTop; q[2] = Zf;
            q[3] = x1; q[4] = yTop; q[5] = Zf;
            q[6] = x0; q[7] = yBot; q[8] = Zf;
            q[9] = x1; q[10] = yBot; q[11] = Zf;
            glVertexPointer(3, GL_FLOAT, 0, q);
            int p3 = [tile percent];
            float pa = (float)((double)(float)p3 / 100.0 * alpha);
            if ([clipForId ID] == m_id_to_delete)
                pa = (float)((double)pa * (((double)m_deleteexplodefactor + -1.0) * -0.5 + 1.0));
            for (int v = 0; v < 4; v++) {
                m_colors[v * 4 + 0] = shade;
                m_colors[v * 4 + 1] = shade;
                m_colors[v * 4 + 2] = shade;
                m_colors[v * 4 + 3] = pa;
            }
            glColorPointer(4, GL_FLOAT, 0, m_colors);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            // Water on the cover of a title that is loading: it fills up from the bottom like a glass (the level follows the
            // real progress smoothly), the surface ripples.
            if (gRfxWaterOn && [clipForId ID] == gRfxWaterID && [tile percent] > 99) {
                // time based easing (same speed at any frame rate) towards the real progress
                static double sLastT = 0.0;
                double nowT = CACurrentMediaTime();
                double dt = (sLastT > 0.0 && nowT - sLastT < 0.5) ? (nowT - sLastT) : (1.0 / 60.0);
                sLastT = nowT;
                gRfxWaterShown += (gRfxWaterTarget - gRfxWaterShown) * (float)(1.0 - exp(-dt * 2.2));
                if (gRfxWaterTarget < 0.97f && gRfxWaterShown < gRfxWaterTarget + 0.02f) gRfxWaterShown += (float)(dt * 0.006);   // never stands still while loading
                float lvl = gRfxWaterShown;
                if (lvl < 0.0f) lvl = 0.0f;
                if (lvl > 1.0f) lvl = 1.0f;
                enum { WN = 200 };
                GLfloat wv[(WN + 1) * 2 * 3];
                GLfloat wc[(WN + 1) * 2 * 4];
                float topBase = yBot + lvl * (yTop - yBot);
                float edge = (lvl < 0.08f) ? lvl / 0.08f : ((lvl > 0.92f) ? (1.0f - lvl) / 0.08f : 1.0f);   // calm at both ends
                float amp = 0.030f * hh * edge;
                double ph = nowT * 2.1;
                float wa = (float)alpha * 0.66f;
                for (int wi = 0; wi <= WN; wi++) {
                    float fr = (float)wi / (float)WN;
                    float wx = x0 + (x1 - x0) * fr;
                    float wave = amp * (float)(0.65 * sin(ph + fr * 7.0) + 0.35 * sin(ph * 1.45 - fr * 11.0 + 1.3));
                    float wy = topBase + wave;
                    if (wy > yTop) wy = yTop;
                    if (wy < yBot) wy = yBot;
                    wv[(wi * 2) * 3 + 0] = wx; wv[(wi * 2) * 3 + 1] = wy;   wv[(wi * 2) * 3 + 2] = Zf;
                    wv[(wi * 2 + 1) * 3 + 0] = wx; wv[(wi * 2 + 1) * 3 + 1] = yBot; wv[(wi * 2 + 1) * 3 + 2] = Zf;
                    // gray tones like Radio.fx: light surface, darker ground
                    wc[(wi * 2) * 4 + 0] = 0.80f * shade; wc[(wi * 2) * 4 + 1] = 0.80f * shade; wc[(wi * 2) * 4 + 2] = 0.80f * shade; wc[(wi * 2) * 4 + 3] = wa * 0.85f;
                    wc[(wi * 2 + 1) * 4 + 0] = 0.38f * shade; wc[(wi * 2 + 1) * 4 + 1] = 0.38f * shade; wc[(wi * 2 + 1) * 4 + 2] = 0.38f * shade; wc[(wi * 2 + 1) * 4 + 3] = wa;
                }
                glDisable(GL_TEXTURE_2D);
                glDisableClientState(GL_TEXTURE_COORD_ARRAY);
                glVertexPointer(3, GL_FLOAT, 0, wv);
                glColorPointer(4, GL_FLOAT, 0, wc);
                glDrawArrays(GL_TRIANGLE_STRIP, 0, (WN + 1) * 2);
                // soft highlight on the surface: a band that fades out upwards and downwards (no hard, jagged edge)
                if (lvl > 0.01f && lvl < 0.995f) {
                    float band = 0.035f * hh;
                    for (int pass = 0; pass < 2; pass++) {
                        for (int wi = 0; wi <= WN; wi++) {
                            float sy = wv[(wi * 2) * 3 + 1];
                            if (pass == 0) {      // from the surface up: bright -> transparent
                                wv[(wi * 2) * 3 + 1] = sy + band;
                                wv[(wi * 2 + 1) * 3 + 1] = sy;
                            } else {              // from the surface down: bright -> transparent
                                wv[(wi * 2) * 3 + 1] = sy;
                                wv[(wi * 2 + 1) * 3 + 1] = sy - band;
                            }
                            if (wv[(wi * 2) * 3 + 1] > yTop) wv[(wi * 2) * 3 + 1] = yTop;
                            if (wv[(wi * 2 + 1) * 3 + 1] < yBot) wv[(wi * 2 + 1) * 3 + 1] = yBot;
                            float a0 = (pass == 0) ? 0.0f : wa * 0.55f, a1 = (pass == 0) ? wa * 0.55f : 0.0f;
                            for (int q = 0; q < 3; q++) { wc[(wi * 2) * 4 + q] = 0.96f * shade; wc[(wi * 2 + 1) * 4 + q] = 0.96f * shade; }
                            wc[(wi * 2) * 4 + 3] = a0; wc[(wi * 2 + 1) * 4 + 3] = a1;
                        }
                        glDrawArrays(GL_TRIANGLE_STRIP, 0, (WN + 1) * 2);
                        // restore the surface y for the second pass
                        for (int wi = 0; wi <= WN; wi++) {
                            float fr = (float)wi / (float)WN;
                            float wave = amp * (float)(0.65 * sin(ph + fr * 7.0) + 0.35 * sin(ph * 1.45 - fr * 11.0 + 1.3));
                            float wy = topBase + wave;
                            if (wy > yTop) wy = yTop;
                            if (wy < yBot) wy = yBot;
                            wv[(wi * 2) * 3 + 1] = wy;
                        }
                    }
                }
                glEnableClientState(GL_TEXTURE_COORD_ARRAY);
                glEnable(GL_TEXTURE_2D);
                glTexCoordPointer(2, GL_FLOAT, 0, kTexCoordMain);
                again = YES;                     // keep drawing frames while the water moves
            }
        }
        // the colour array stays enabled for fully loaded covers
        if ([tile percent] <= 99) glDisableClientState(GL_COLOR_ARRAY);

        // reflection: first a black quad, then the mirrored cover fading out
        glTexCoordPointer(2, GL_FLOAT, 0, kTexCoordReflect);
        float alphaHalf = (float)(alpha * 0.5);
        double yr0 = yShift + -0.04;
        float zBlack = (float)(Z + -0.001);
        float zTile = (float)Z;
        for (int r5 = 0; r5 < 2; r5++) {
            GLuint texName;
            if (r5 == 0) {
                if (m_blacktexture == nil) [self CreateBlackTexture:&m_blacktexture];
                texName = [m_blacktexture texture];
            } else if (m_flipping && i == (int)[paintorder count] - 1) {
                texName = (m_flippingangle < 90.0) ? [tile texture] : [[self m_specialtexture] texture];
            } else {
                texName = [tile texture];
            }
            glBindTexture(GL_TEXTURE_2D, texName);
            GLfloat v[12];
            memset(v, 0, sizeof(v));
            float Zr;
            if (flipLast) {
                // reflection of the flipping cover
                float yup = m_yup;
                Zr = (float)(Z + fdz);
                double d13 = (fdy - 0.04) + (double)yup;
                d13 += yShift;
                float Yr = (float)d13;
                float zf = Zr;
                float x0 = (float)(xc - fx), x1 = (float)(xc + fx);
                float z0 = (float)((double)zf - fz), z1 = (float)((double)zf + fz);
                float yLow = (-2.0f * kA) + Yr;
                float yUp = (float)(-(double)kA + (double)Yr);
                v[0] = x0; v[1] = yLow; v[2] = z0;
                v[3] = x1; v[4] = yLow; v[5] = z1;
                v[6] = x0; v[7] = yUp;  v[8] = z0;
                v[9] = x1; v[10] = yUp; v[11] = z1;
            } else {
                float Yr = (float)(yr0 + (double)m_yup);
                Zr = (r5 == 0) ? zBlack : zTile;
                float h28, h30;
                int p = [tile percent];
                if (p > 99) {
                    h28 = kA;
                    h30 = kA;
                } else {
                    h28 = (kA * (float)p) / 100.0f;
                    h30 = (kA * (float)p) / 100.0f;
                    Yr = Yr + (kA - h28) * -2.0f;
                    again = YES;
                }
                if ([[[self m_tilearray] objectAtIndex:tileIdx] ID] == m_id_to_delete) h28 = h28 * m_deleteexplodefactor;
                if (betaA >= 0.0) { h28 *= (float)betaS; h30 *= (float)betaS; }
                if (gBeatPulse > 0.001f && RfxTileIsPlaying([[self m_tilearray] objectAtIndex:tileIdx], playingClip)) { h28 *= 1.0f + 0.055f * gBeatPulse; h30 *= 1.0f + 0.055f * gBeatPulse; }
                float x0 = (float)(xc - (double)h28), x1 = (float)((double)h28 + xc);
                float yLow = ((-h28) - h30) + Yr;
                float yUp = Yr - h28;
                v[0] = x0; v[1] = yLow; v[2] = Zr;
                v[3] = x1; v[4] = yLow; v[5] = Zr;
                v[6] = x0; v[7] = yUp;  v[8] = Zr;
                v[9] = x1; v[10] = yUp; v[11] = Zr;
            }
            glVertexPointer(3, GL_FLOAT, 0, v);
            if (r5 <= 0) {
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            } else {
                glEnableClientState(GL_COLOR_ARRAY);
                float ra;
                if ([self m_pinchstatus] >= 1) {
                    ra = alphaHalf * m_additionalalpha;
                } else {
                    ra = alphaHalf;
                    if ([tile percent] <= 99)
                        ra = (float)((double)alphaHalf * ((double)(float)[tile percent] / 100.0));
                }
                float sh = (float)(((double)Zr - 4.5) / 9.92);
                sh = sh * sh;
                sh = sh * sh;
                double shd = (double)sh;
                if (shd > 1.0) shd = 1.0;
                float shade2 = (float)shd;
                if (shd < 0.1) shade2 = 0.1f;
                if ([[[self m_tilearray] objectAtIndex:tileIdx] ID] == m_id_to_delete)
                    ra = (float)((double)ra * (((double)m_deleteexplodefactor + -1.0) * -0.5 + 1.0));
                float a = ra * shade2;
                // reflection fades out from the cover edge: lower vertices transparent, upper ones at 'a'
                static const float base[16] = { 1,1,1,0, 1,1,1,0, 1,1,1,0, 1,1,1,0 };
                memcpy(m_colors, base, sizeof(base));
                m_colors[11] = a;
                m_colors[15] = a;
                glColorPointer(4, GL_FLOAT, 0, m_colors);
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
                glDisableClientState(GL_COLOR_ARRAY);
            }
        }
        if ([tile percent] <= 99) [tile setPercent:[tile percent] + 12];
    }
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
    return again;
}


#pragma mark - labels

- (void)SetInterpretLabelText:(NSString *)interpretLabelText { [m_interpretlabel setText:interpretLabelText]; }
- (void)SetTitleLabelText:(NSString *)titleLabelText { [m_titlelabel setText:titleLabelText]; }

- (void)SetLabelTexts:(NSNumber *)labelTexts {
    int idx = [labelTexts intValue];
    if ((unsigned)[[self m_tilearray] count] <= (unsigned)idx) {
        [m_interpretlabel setText:@""];
        [m_titlelabel setText:@""];
    } else {
        ClipObject *c = [[self m_tilearray] objectAtIndex:idx];
        [m_interpretlabel setText:[[c m_interpret] uppercaseString]];
        [m_titlelabel setText:[[c m_title] uppercaseString]];
    }
}

#pragma mark - texture creation

- (void)BindTexture:(NSNumber *)bindTexture { glBindTexture(GL_TEXTURE_2D, [bindTexture intValue]); }
- (void)DoTexture:(NSNumber *)doTexture   { glBindTexture(GL_TEXTURE_2D, [doTexture intValue]); }

// Renders the tile image (see CreateNakedImage) into a square RGBA bitmap and uploads it as a GL texture.
- (GLuint)imageToTexture:(UIImage *)image withNumber:(int)number withClipArray:(NSArray *)clipArray
          withclipObject:(ClipObject *)clipObject borderalreadypresent:(BOOL)borderalreadypresent {
    GLuint tex = 0;
    for (;;) {
        glEnable(GL_TEXTURE_2D);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glEnable(GL_BLEND);
        int ts = ([self m_selectedfolderid] == -33) ? gv_texsizeradio : gv_texsize;
        UIImage *naked = [self CreateNakedImage:image withNumber:number withClipArray:clipArray withclipObject:clipObject
                                withtexturesize:ts onlychannellogo:NO borderalreadypresent:borderalreadypresent];
        unsigned char *buf = [NSThread isMainThread] ? GData : GDataThread;
        memset(buf, 0, 0x100000);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(buf, ts, ts, 8, ts * 4, cs, kCGImageAlphaPremultipliedLast);
        CGContextTranslateCTM(ctx, 0, (CGFloat)ts);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGColorSpaceRelease(cs);
        CGContextDrawImage(ctx, CGRectMake(0, 0, ts, ts), [naked CGImage]);
        CGContextRelease(ctx);
        glGenTextures(1, &tex);
        [EAGLContext setCurrentContext:[self contextForCurrentThread]];
        glBindTexture(GL_TEXTURE_2D, tex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, ts, ts, 0, GL_RGBA, GL_UNSIGNED_BYTE, buf);
        if (gv_texfallback) break;
        if (glGetError() != GL_INVALID_VALUE) break;
        // texture too big for this GPU: retry once with smaller edges
        gv_texfallback = YES;
        gv_texsizeradio = 0x100;
        gv_texsize = 0x80;
    }
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, (GLfloat)GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, (GLfloat)GL_CLAMP_TO_EDGE);
    if (![NSThread isMainThread]) glFlush();   // make the texture visible to the shared main context
    return tex;
}

// The loader thread owns a context in the same sharegroup (the original made the one context current on two threads).
- (EAGLContext *)contextForCurrentThread {
    if ([NSThread isMainThread]) return context;
    EAGLContext *c = [[[NSThread currentThread] threadDictionary] objectForKey:@"rfxglctx"];
    return c ? c : context;
}

// Draws the 2D picture that becomes the texture of one tile.
- (UIImage *)CreateNakedImage:(UIImage *)nakedImage withNumber:(int)number withClipArray:(NSArray *)clipArray
               withclipObject:(ClipObject *)clipObject withtexturesize:(int)texturesize
              onlychannellogo:(BOOL)onlychannellogo borderalreadypresent:(BOOL)borderalreadypresent {
    CGContextRef ctx = [DEL BeginImageContext:CGSizeMake(texturesize, texturesize)];
    UIColor *gray = [UIColor colorWithWhite:0.05098f alpha:1.0f];
    float w = (float)texturesize;
    if (clipObject == nil && clipArray != nil) {
        // back side with the list of tracks of an album: black ground, gray + white inner frame, track count in a red dot
        CGContextSetFillColorWithColor(ctx, [[UIColor colorWithWhite:0.0f alpha:1.0f] CGColor]);
        CGContextFillRect(ctx, CGRectMake(0, 0, w, w));
        CGContextSetFillColorWithColor(ctx, [gray CGColor]);
        CGContextFillRect(ctx, CGRectMake(6.0f, 0, gv_texsize - 12, gv_texsize - 12));
        CGContextSetFillColorWithColor(ctx, [[UIColor whiteColor] CGColor]);
        CGContextFillRect(ctx, CGRectMake(7.0f, 1.0f, gv_texsize - 14, gv_texsize - 14));
        [self AddRedDot:(int)[clipArray count] withContext:ctx];
    } else if (clipObject == nil && nakedImage != nil) {
        // Dev-menu options "RfxDevCoverBorder" (on/off) and "RfxDevCoverBorderWidth" (in units of a 196 px texture, default 2):
        // a thin black frame around the cover; the cover itself fills everything inside the frame.
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        id borderPref = [ud objectForKey:@"RfxDevCoverBorder"];
        BOOL withBorder = (borderPref == nil) ? NO : [borderPref boolValue];
        id widthPref = [ud objectForKey:@"RfxDevCoverBorderWidth"];
        float units = (widthPref == nil) ? 2.0f : [widthPref floatValue];
        float bw = (withBorder && !borderalreadypresent) ? units * (w / 196.0f) : 0.0f;
        if (bw > 0.0f) {
            CGContextSetFillColorWithColor(ctx, [[UIColor colorWithWhite:0.0f alpha:1.0f] CGColor]);
            CGContextFillRect(ctx, CGRectMake(0, 0, w, w));
        }
        CGContextDrawImage(ctx, CGRectMake(bw, bw, w - 2.0f * bw, w - 2.0f * bw), [nakedImage CGImage]);
        [self AddRedDot:number withContext:ctx];
    } else {
        // no cover picture (or a card kind that only existed with the server): the "cover-note" placeholder with a 1px frame
        CGContextDrawImage(ctx, CGRectMake(1.0f, 1.0f, w, w), [[UIImage imageNamed:@"cover-note.png"] CGImage]);
        CGContextSetFillColorWithColor(ctx, [gray CGColor]);
        CGContextFillRect(ctx, CGRectMake(0, 0, w, 1.0f));
        CGContextFillRect(ctx, CGRectMake(0, w - 1.0f, w, 1.0f));
        CGContextFillRect(ctx, CGRectMake(0, 0, 1.0f, w));
        CGContextFillRect(ctx, CGRectMake(w - 1.0f, 0, 1.0f, w));
    }
    return [DEL EndImageContext:ctx];
}

// The red dot with the number of stacked tracks in the lower right corner of a cover.
- (void)AddRedDot:(int)redDot withContext:(CGContextRef)contextArg {
    if (redDot < 1) return;
    BOOL ipad = [DEL m_isipad];
    float f = ipad ? 1.0f : 1.333f;
    UIImage *dot = [UIImage imageNamed:@"roter-kreis.png"];
    int h = (int)(f * 34.0f);
    CGContextDrawImage(contextArg,
                       CGRectMake((float)(gv_texsize - (int)((double)f * 44.0)), (float)((gv_texsize - 1) - h),
                                  (float)(int)(f * 32.0f), (float)h),
                       [dot CGImage]);
    CGContextSetFillColorWithColor(contextArg, [[UIColor whiteColor] CGColor]);
    int fontsize, ydelta;
    float xdelta;
    if (redDot < 10) { fontsize = ipad ? 18 : 25; ydelta = 3; xdelta = ipad ? 0.0f : 10.0f; }
    else             { fontsize = ipad ? 16 : 22; ydelta = 5; xdelta = ipad ? 1.0f : 9.0f; }
    UIFont *font = [UIFont boldSystemFontOfSize:(float)fontsize];
    NSString *txt = [NSString stringWithFormat:@"%i", redDot];
    CGSize sz = [txt sizeWithFont:font];
    float x = (float)(int)((double)(((float)gv_texsize + -27.0f) - xdelta) + (double)sz.width * -0.5);
    float y = (float)(gv_texsize + (~fontsize - ydelta));
    [DEL OwndrawAtPoint:contextArg withtext:txt drawAtPoint:CGPointMake(x, y) forWidth:0 withFont:font lineBreakMode:0];
}

- (void)CreatePlaceholderTextures {
    GLuint t = [self imageToTexture:[UIImage imageNamed:@"cover-note.png"] withNumber:0 withClipArray:nil
                     withclipObject:nil borderalreadypresent:NO];
    if (m_placeholdertexture) [m_placeholdertexture release];
    m_placeholdertexture = [[FlowCoverRecord alloc] initWithTexture:t];
    [m_placeholdertexture setPercent:100];
}

- (void)CreateBlackTexture:(FlowCoverRecord **)blackTexture {
    GLuint t = [self imageToTexture:[DEL NonCachedImage:@"blackPixel"] withNumber:0 withClipArray:nil
                     withclipObject:nil borderalreadypresent:NO];
    *blackTexture = [[FlowCoverRecord alloc] initWithTexture:t];
}

- (void)DeleteTextures {
    [cache Empty];
    if ([self m_specialtexture]) { [[self m_specialtexture] release]; [self setM_specialtexture:nil]; }
    if (m_blacktexture) { [m_blacktexture release]; m_blacktexture = nil; }
    if (m_blacktextureradio) { [m_blacktextureradio release]; m_blacktextureradio = nil; }
    if (m_placeholdertexture) { [m_placeholdertexture release]; m_placeholdertexture = nil; }
    if (m_placeholdertextureradio) { [m_placeholdertextureradio release]; m_placeholdertextureradio = nil; }
}

- (void)EmptyCache { [cache Empty]; }
- (void)ForwardDeclineCache {}

- (void)EmptyAllTextures {
    [self EmptyCache];
    if (m_placeholdertexture) { [m_placeholdertexture release]; m_placeholdertexture = nil; }
    if (m_placeholdertextureradio) { [m_placeholdertextureradio release]; m_placeholdertextureradio = nil; }
    if (m_blacktexture) { [m_blacktexture release]; m_blacktexture = nil; }
    if (m_blacktextureradio) { [m_blacktextureradio release]; m_blacktextureradio = nil; }
    if (m_specialtexture) { [m_specialtexture release]; m_specialtexture = nil; }
}

// Memory warning: keep only the textures of the 15 covers around the current position on either side.
- (void)RemoveTexturesExeptRondell {
    NSMutableArray *keep = [[NSMutableArray alloc] init];
    if ((unsigned)[[self m_tilearray] count] > 9) {
        [self GetArrayLock:NO];
        int n = (int)[[self m_tilearray] count];
        int fwd = (int)offset - 1, back = (int)offset;
        for (int i = 0; i < 15; i++) {
            if (back - 1 > -1) {
                back = back - 1;
                fwd = ((unsigned)(fwd + 1) >= (unsigned)n) ? 0 : fwd + 1;
            } else {
                back = n - 1;
            }
            [keep addObject:[DEL CreateTextureKey:[[self m_tilearray] objectAtIndex:fwd]]];
            [keep addObject:[DEL CreateTextureKey:[[self m_tilearray] objectAtIndex:back]]];
        }
        [cache RemoveObjectsExept:keep];
        [self releaseArraylock];
    }
    [keep release];
}

#pragma mark - loader thread

- (void)GetArrayLock:(BOOL)getArrayLock { [m_arraylock lock]; }
- (void)releaseArraylock { [m_arraylock unlock]; }

- (void)ReInitThread { [self SendSignal:0]; }

- (void)SendSignal:(int)sendSignal {
    [m_condition[sendSignal] lock];
    m_conditioncounter[sendSignal] = 1;
    [m_condition[sendSignal] signal];
    [m_condition[sendSignal] unlock];
}

- (void)WaitForSignal:(int)waitForSignal {
    [m_condition[waitForSignal] lock];
    while (m_conditioncounter[waitForSignal] <= 0)
        [m_condition[waitForSignal] wait];
    m_conditioncounter[waitForSignal] = 0;
    [m_condition[waitForSignal] unlock];
}

- (BOOL)LoaderMustPark {
    return [DEL m_isinbackground] || m_memorywarning || [self m_drawemptyturn];
}

// Builds the texture of tile 'tile' unless it is already cached.  Runs on the loader thread.
- (void)CreateTile:(int)tile withcounter:(int *)counter withEAGLCTX:(EAGLContext *)eAGLCTX {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [self GetArrayLock:YES];
    if ((unsigned)[[self m_tilearray] count] <= (unsigned)tile || tile < 0 || [DEL m_isinbackground]) {
        [m_arraylock unlock];
    } else {
        ClipObject *clip = [[[self m_tilearray] objectAtIndex:tile] retain];
        BOOL exists = [cache ExistsObjectForKey:[DEL CreateTextureKey:clip]];
        [m_arraylock unlock];
        if (exists) {
            [NSThread sleepForTimeInterval:0.01];
        } else {
            (*counter)++;
            [self HelpergetTileatIndex:[NSNumber numberWithInt:tile] withEAGLCTX:eAGLCTX];
        }
        [clip release];
    }
    [pool release];
}

- (void)HelpergetTileatIndex:(NSNumber *)helpergetTileatIndex withEAGLCTX:(EAGLContext *)eAGLCTX {
    [self GetArrayLock:YES];
    [self getTileAtIndex:[helpergetTileatIndex intValue] withCreate:YES];
    [m_arraylock unlock];
    if ([self m_selectedfolderid] != -33 && ![self m_drawempty] && ![self m_drawemptyturn])
        [self performSelectorOnMainThread:@selector(drawView) withObject:nil waitUntilDone:YES];
}

// Thread body: creates the covers' textures around the position the coverflow is at (nearest first) so scrolling never
// has to wait.  Sleeps on condition 0 (ReInitThread) when there is nothing left to do.
// NOTE: the control flow of the original is not recoverable from its (heavily goto-ed) code; this keeps its behaviour:
// wait while the user drags or an animation runs, honour deleted server textures, load ids that did not change,
// alternate right/left of the centre, stop at the cache capacity, park on background / memory warning.
- (void)LoadPicsForRondell:(NSDictionary *)picsForRondell {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSThread setThreadPriority:0.2];
    long long fid = [[picsForRondell objectForKey:@"id"] longLongValue];
    int sid = [[picsForRondell objectForKey:@"sid"] intValue];
    long long iid = [[picsForRondell objectForKey:@"iid"] longLongValue];
    NSString *spot = [picsForRondell objectForKey:@"spotifyfolderid"];
    (void)spot;
    EAGLContext *tctx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1 sharegroup:[context sharegroup]];
    [[[NSThread currentThread] threadDictionary] setObject:tctx forKey:@"rfxglctx"];
    [EAGLContext setCurrentContext:tctx];
    [tctx release];

    BOOL first = YES;
    while (!([DEL g_end] || gv_kioskflag)) {
        if (![self LoaderMustPark]) {
            // wait until the coverflow rests
            while (timer != nil || [self m_fingersonscreen] > 0 || [m_parent GetBlackView] != nil || [self m_pinchstatus] != 0) {
                if (gv_kioskflag) break;
                if ([self LoaderMustPark]) break;
                [NSThread sleepForTimeInterval:0.05];
            }
        }
        if (!gv_kioskflag && ![self LoaderMustPark]) {
            if ([self m_sidtexturestodelete] != -1) {
                int s = [self m_sidtexturestodelete];
                [self setM_sidtexturestodelete:-1];
                [self GetArrayLock:YES];
                [cache DeleteServerTextures:s];
                [m_arraylock unlock];
                [self performSelectorOnMainThread:@selector(drawView) withObject:nil waitUntilDone:YES];
            }
            [self GetArrayLock:YES];
            int n = (int)[[self m_tilearray] count];
            int centre = (int)(offset + 0.5);
            [m_arraylock unlock];
            if (n > 0 && [self m_selectedfolderid] != -33) {
                if (centre < 0) centre = 0;
                if (centre >= n) centre = n - 1;
                int created = 0, fwd = centre, back = centre;
                int maxTiles = [cache GetMaxTiles];
                #define LOADER_STATE_OK ((int)[[self m_tilearray] count] == n && [self m_selectedfolderid] == fid \
                    && [self m_selectedserverid] == sid && [self m_selectedipodid] == iid)
                [self CreateTile:centre withcounter:&created withEAGLCTX:nil];
                for (int step = 0; step <= n / 2 + 1 && created < maxTiles; step++) {
                    if (gv_kioskflag || [DEL g_end] || [self LoaderMustPark] || !LOADER_STATE_OK) break;
                    fwd = ((unsigned)(fwd + 1) >= (unsigned)n) ? 0 : fwd + 1;
                    [self CreateTile:fwd withcounter:&created withEAGLCTX:nil];
                    if (gv_kioskflag || [self LoaderMustPark] || !LOADER_STATE_OK) break;
                    back = (back - 1 > -1) ? back - 1 : n - 1;
                    if (back != fwd) [self CreateTile:back withcounter:&created withEAGLCTX:nil];
                }
                #undef LOADER_STATE_OK
                if (!first || created > 0)
                    [self performSelectorOnMainThread:@selector(drawView) withObject:nil waitUntilDone:YES];
            }
            first = NO;
        }
        if ([DEL g_end] || gv_kioskflag) break;
        // nothing (more) to do: sleep until ReInitThread
        [self setM_threadwaiting:YES];
        [self WaitForSignal:0];
        [self setM_threadwaiting:NO];
        if ([self m_drawemptyturn] && [self m_rotateready]) {
            [self CreatePlaceholderTextures];
            [self setM_drawemptyturn:NO];
            [self performSelectorOnMainThread:@selector(drawView) withObject:nil waitUntilDone:YES];
        }
        if (m_memorywarning) {
            [pool drain];
            pool = [[NSAutoreleasePool alloc] init];
            m_memorywarning = NO;
        }
    }
    [EAGLContext setCurrentContext:nil];
    [pool release];
}

- (void)SetMemoryWarning { m_memorywarning = YES; }

#pragma mark - folder / tile list

- (void)EmptyRondell {
    [self GetArrayLock:NO];
    [[self m_origarray] removeAllObjects];
    [[self m_tilearray] removeAllObjects];
    offset = 0;
    [m_arraylock unlock];
    [self drawView];
}

- (void)RemoveVirtBrandingSong:(NSMutableArray *)virtBrandingSong {
    for (int i = (int)[virtBrandingSong count] - 1; i >= 0; i--) {
        ClipObject *c = [virtBrandingSong objectAtIndex:i];
        if ([c ID] == -5) { [virtBrandingSong removeObjectAtIndex:i]; continue; }
        // a plugin title that is still loading has no file: it must never be picked to play by itself
        if ([c m_folderid] == -88 && [[c m_filepath] length] == 0) [virtBrandingSong removeObjectAtIndex:i];
    }
}

// Removes the clips that are in the play queue from a candidate list.
- (void)RemoveQueuedFrom:(NSMutableArray *)cand {
    NSArray *q = [m_parent m_clips];
    for (int i = (int)[cand count] - 1; i >= 0; i--) {
        ClipObject *c = [cand objectAtIndex:i];
        for (ClipObject *queued in q) {
            if ([queued ID] == [c ID] && [queued m_ipodid] == [c m_ipodid]) { [cand removeObjectAtIndex:i]; break; }
        }
    }
}

// A song that was started (by the user or by the shuffle) is not picked again until every song has been played.
- (void)MarkClipPlayed:(ClipObject *)clip {
    if (clip == nil) return;
    for (ClipObject *played in m_randomarray)
        if ([played ID] == [clip ID] && [played m_ipodid] == [clip m_ipodid]) return;
    [m_randomarray addObject:clip];
}

// Picks the next clip for "random"/auto play: a not yet played one of the current list (an album gives a random track).
// Returns a retained copy, nil when there is nothing.
- (ClipObject *)getNextClipObject {
    ClipObject *result = nil;
    if ([[self m_tilearray] count] != 0) {
        [self GetArrayLock:NO];
        NSMutableArray *cand = [[NSMutableArray alloc] init];
        [cand addObjectsFromArray:[self m_tilearray]];
        [self RemoveVirtBrandingSong:cand];
        for (int i = (int)[cand count] - 1; i >= 0; i--) {
            ClipObject *c = [cand objectAtIndex:i];
            for (ClipObject *played in m_randomarray) {
                if ([played ID] == [c ID] && [played m_ipodid] == [c m_ipodid]) {
                    [cand removeObjectAtIndex:i];
                    break;
                }
            }
        }
        // songs waiting in (or playing from) the queue count as played, too
        [self RemoveQueuedFrom:cand];
        if ([cand count] == 0) {
            // everybody has been through: start a new shuffle round
            NSString *st = [self GetSearchText];
            if (st == nil || [st length] == 0) [m_randomarray removeAllObjects];
            [cand addObjectsFromArray:[self m_tilearray]];
            [self RemoveVirtBrandingSong:cand];
            NSMutableArray *keep = [[NSMutableArray alloc] initWithArray:cand];
            [self RemoveQueuedFrom:cand];
            if ([cand count] == 0) [cand addObjectsFromArray:keep];
            [keep release];
        }
        ClipObject *pick = nil;
        if ([cand count] != 0) {
            pick = [cand objectAtIndex:(unsigned)random() % [cand count]];
            if ([pick m_tracks] != nil && [[pick m_tracks] count] != 0)
                pick = [[pick m_tracks] objectAtIndex:(unsigned)random() % [[pick m_tracks] count]];
        }
        [cand release];
        if (pick != nil) {
            [m_randomarray addObject:pick];
        } else if ([[self m_tilearray] count] != 0) {
            pick = [[self m_tilearray] objectAtIndex:0];
            if ([pick m_tracks] != nil && [[pick m_tracks] count] != 0) pick = [[pick m_tracks] objectAtIndex:0];
            if ([pick m_folderid] == -88 && [[pick m_filepath] length] == 0) pick = nil;
        }
        if (pick != nil) {
            result = [[ClipObject alloc] init];
            [m_parent CopyPropertiesFromObject:pick toObject:result];
        }
        [m_arraylock unlock];
    } else if ([[m_parent m_clips] count] != 0) {
        result = [[ClipObject alloc] init];
        [m_parent CopyPropertiesFromObject:[[m_parent m_clips] objectAtIndex:0] toObject:result];
    }
    return result;
}

// Inserts a clip into the list of covers.  Takes ownership of 'clip' (the caller retained it).
// With "stack albums" switched on, clips of one album are collected in the m_tracks of a single cover.
- (void)AddPicture:(ClipObject *)clip {
    if ([m_parent ShowingLoadingscreen]) { [clip release]; return; }
    [self GetArrayLock:NO];
    int found = -1;
    for (unsigned i = 0; i < [[self m_origarray] count]; i++) {
        ClipObject *e = [[self m_origarray] objectAtIndex:i];
        if ([e m_folderid] == -66) continue;
        if ([e ID] == [clip ID] && [e m_ipodid] == [clip m_ipodid]) {   // already in the list
            [m_arraylock unlock];
            [clip release];
            return;
        }
        if ([DEL m_stackalbums] != 0 && [e m_albumid] == [clip m_albumid] && [clip m_albumid] != 0
            && [e m_folderid] == [clip m_folderid]) {
            found = (int)i;
            break;
        }
    }
    if (found == -1) {
        [[self m_origarray] addObject:clip];
        NSString *st = [[m_searchview m_searchlabel] text];
        // a plugin title that is loading is always shown, whatever the search field says
        {   // the carousel is never narrowed by a search text
            int n = (int)[[self m_tilearray] count];
            int at;
            if ([self m_selectedfolderid] != -33) {
                if (n < 8) {
                    at = n;
                } else {
                    at = (int)(offset + 7.0);
                    while (at > n) at -= n;
                    if (at <= -1) at = 0;
                }
            } else {
                at = n;
            }
            [[self m_tilearray] insertObject:clip atIndex:at];
        }
    } else {
        ClipObject *album = [[self m_origarray] objectAtIndex:found];
        if ([album m_tracks] == nil) {
            ClipObject *first = [[ClipObject alloc] init];
            [m_parent CopyPropertiesFromObject:album toObject:first];
            NSMutableArray *tr = [[NSMutableArray alloc] init];
            [album setM_tracks:tr];
            [tr release];
            [[album m_tracks] addObject:first];
            [[album m_tracks] addObject:clip];
            [first release];
            [album setM_filepath:nil];
            [album setM_duration:0];
            [album setM_title:nil];
            [album setM_title:[NSString stringWithFormat:@"%@", [album m_albumname]]];
            if (found == (int)offset) [m_titlelabel setText:[NSString stringWithFormat:@"%@", [album m_albumname]]];
        } else {
            [[album m_tracks] addObject:clip];
        }
        // the album takes over the first picture that any of its tracks has
        BOOL albumHasPic = [album m_picturepath] != nil && [[album m_picturepath] length] != 0;
        BOOL clipHasPic  = [clip m_picturepath] != nil && [[clip m_picturepath] length] != 0;
        if (!albumHasPic && clipHasPic) {
            [album setM_picturepath:[NSString stringWithFormat:@"%@", [clip m_picturepath]]];
            [album setID:[clip ID]];
            for (ClipObject *t in [album m_tracks]) {
                if ([t ID] == [clip ID]) continue;
                if ([t m_picturepath] == nil || [[t m_picturepath] length] == 0)
                    [t setM_picturepath:[NSString stringWithFormat:@"%@", [clip m_picturepath]]];
            }
        } else if (!clipHasPic && albumHasPic) {
            [clip setM_picturepath:[NSString stringWithFormat:@"%@", [album m_picturepath]]];
        }
        [[album m_tracks] sortUsingSelector:@selector(compareTracknumbers:)];
        [cache removeObjectwithkey:[DEL CreateTextureKey:album]];
        if ([self m_specialtexture]) { [[self m_specialtexture] release]; [self setM_specialtexture:nil]; }
    }
    [clip release];
    [m_arraylock unlock];
}

#pragma mark - plugin titles that are loading (water on the cover)

- (void)SetWaterForClipID:(long long)cid level:(float)level {
    if (cid != gRfxWaterID || !gRfxWaterOn) gRfxWaterShown = 0.0f;
    gRfxWaterID = cid;
    gRfxWaterTarget = level < 0.0f ? 0.0f : (level > 1.0f ? 1.0f : level);
    gRfxWaterOn = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(drawView) object:nil];
        [self drawView];
    });
}

- (void)ClearWater {
    gRfxWaterOn = NO;
    gRfxWaterID = 0;
    gRfxWaterShown = 0.0f;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(drawView) object:nil];
        [self drawView];
    });
}

// takes the cover of a title out of the coverflow again (the title could not be loaded)
- (void)RemovePluginPlaceholder:(long long)cid {
    [self GetArrayLock:NO];
    NSArray *lists = [NSArray arrayWithObjects:[self m_tilearray], [self m_origarray], nil];
    for (NSMutableArray *arr in lists) {
        for (int i = (int)[arr count] - 1; i >= 0; i--) {
            ClipObject *c = [arr objectAtIndex:i];
            if ([c ID] == cid && [c m_folderid] == -88 && [[c m_filepath] length] == 0) [arr removeObjectAtIndex:i];
        }
    }
    int n = (int)[[self m_tilearray] count];
    if (n == 0) offset = 0; else if ((int)offset >= n) offset = (double)(n - 1);
    [m_arraylock unlock];
    [self ReInitThread];
    dispatch_async(dispatch_get_main_queue(), ^{ [self drawView]; });
}

// The carousel shows the whole folder again; the search field and the result list stay as they are.
- (void)ShowAllTilesKeepingSearch {
    [self GetArrayLock:NO];
    int n0 = (int)[[self m_tilearray] count];
    ClipObject *center = (n0 > 0 && (int)offset >= 0 && (int)offset < n0) ? [[[self m_tilearray] objectAtIndex:(int)offset] retain] : nil;
    if (n0 != (int)[[self m_origarray] count]) {
        [[self m_tilearray] removeAllObjects];
        [[self m_tilearray] addObjectsFromArray:[self m_origarray]];
        int n = (int)[[self m_tilearray] count];
        if (center != nil) {
            for (int i = 0; i < n; i++) {
                ClipObject *c = [[self m_tilearray] objectAtIndex:i];
                if ([c ID] == [center ID] && [c m_ipodid] == [center m_ipodid]) { offset = (double)i; break; }
            }
        }
        if (n == 0) offset = 0; else if ((int)offset >= n) offset = (double)(n - 1);
    }
    [center release];
    [m_arraylock unlock];
}

// the loaded title (a normal library clip now) takes the place of its tile in the coverflow; nothing else changes in the
// carousel (no narrowing to a folder).  Takes ownership of 'clip' (caller retained it).
- (void)ReplacePluginPlaceholder:(long long)cid withClip:(ClipObject *)clip {
    [self GetArrayLock:NO];
    BOOL exists = NO, replaced = NO;
    for (ClipObject *e in [self m_origarray])
        if ([e ID] == [clip ID] && [e m_ipodid] == [clip m_ipodid] && [e m_folderid] != -88) { exists = YES; break; }
    NSArray *lists = [NSArray arrayWithObjects:[self m_tilearray], [self m_origarray], nil];
    for (NSMutableArray *arr in lists) {
        for (int i = (int)[arr count] - 1; i >= 0; i--) {
            ClipObject *c = [arr objectAtIndex:i];
            if ([c ID] != cid || [c m_folderid] != -88 || [[c m_filepath] length] != 0) continue;
            [cache removeObjectwithkey:[DEL CreateTextureKey:c]];
            if (exists) { [arr removeObjectAtIndex:i]; }
            else { [arr replaceObjectAtIndex:i withObject:clip]; replaced = YES; }
        }
    }
    int n = (int)[[self m_tilearray] count];
    if (n == 0) offset = 0; else if ((int)offset >= n) offset = (double)(n - 1);
    [m_arraylock unlock];
    long long newid = [clip ID];
    if (!replaced && !exists) { [self AddPicture:clip]; }      // placeholder not in the lists (filtered): add normally
    else [clip release];
    [self ReInitThread];
    if (!exists) [self BuildCoverNowForPluginClipID:newid];     // the cover is built right here, not only when the loader thread wakes up
    dispatch_async(dispatch_get_main_queue(), ^{ [self drawView]; });
}

// the file of a title that was loaded: from now on the cover in the coverflow is a normal playable cover
// builds the texture of a plugin tile right now on the main thread (the loader thread may be parked or busy)
- (void)BuildCoverNowForPluginClipID:(long long)cid {
    [EAGLContext setCurrentContext:context];
    [self GetArrayLock:YES];
    int idx = -1;
    for (int i = 0; i < (int)[[self m_tilearray] count]; i++) {
        ClipObject *c = [[self m_tilearray] objectAtIndex:i];
        if ([c ID] == cid) { idx = i; break; }
    }
    if (idx >= 0) {
        ClipObject *c = [[self m_tilearray] objectAtIndex:idx];
        [cache removeObjectwithkey:[DEL CreateTextureKey:c]];
        [self getTileAtIndex:idx withCreate:YES];
    }
    [m_arraylock unlock];
    [self drawView];
}

// the real cover of a title arrived: set it on the tile and let the texture be built again
- (void)SetPicture:(NSString *)path forPluginClipID:(long long)cid {
    [self GetArrayLock:NO];
    for (ClipObject *c in [self m_origarray]) {
        if ([c ID] == cid && [c m_folderid] == -88) {
            [c setM_picturepath:path];
            [cache removeObjectwithkey:[DEL CreateTextureKey:c]];
        }
    }
    [m_arraylock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{ [self ReInitThread]; [self BuildCoverNowForPluginClipID:cid]; });
}

- (void)SetFilepath:(NSString *)path forPluginClipID:(long long)cid {
    [self GetArrayLock:NO];
    NSArray *lists = [NSArray arrayWithObjects:[self m_tilearray], [self m_origarray], nil];
    for (NSMutableArray *arr in lists)
        for (ClipObject *c in arr)
            if ([c ID] == cid && [c m_folderid] == -88) [c setM_filepath:path];
    [m_arraylock unlock];
}

- (void)HelperFuncShowFolder:(FolderObject *)helperFuncShowFolder {
    [self ShowOnlyFolder:helperFuncShowFolder withstartSong:NO channelviewwaspresent:YES];
    [self drawView];
}

- (void)ReShowFolder {
    DBOperations *db = [[DBOperations alloc] init];
    [DEL LockDB:NO];
    FolderObject *f = [db GetFolderForID:[self m_selectedfolderid] withserverid:[self m_selectedserverid]
                                withipodid:[self m_selectedipodid] withspotifyid:[self m_selectedspotifyfolderid]];
    [DEL UnlockDB];
    [db release];
    [self ShowOnlyFolder:f withstartSong:NO channelviewwaspresent:YES];
    [f release];
}

// Makes 'onlyFolder' the shown folder.  (The original first cross-faded a screenshot of the previous folder
// when the channel view was not shown; that transition is left out, see DEVIATIONS.md.)
- (void)ShowOnlyFolder:(FolderObject *)onlyFolder withstartSong:(BOOL)startSong channelviewwaspresent:(BOOL)channelviewwaspresent {
    m_rondell_loaded = NO;
    m_startsong = startSong;
    p_newfolder = [[FolderObject alloc] init];
    [p_newfolder setFolderid:[onlyFolder folderid]];
    [p_newfolder setFoldername:[NSString stringWithFormat:@"%@", [onlyFolder foldername]]];
    [p_newfolder setServerid:[onlyFolder serverid]];
    [p_newfolder setAutoselect:[onlyFolder autoselect]];
    [p_newfolder setFlags:[onlyFolder flags]];
    [p_newfolder setTimediff:[onlyFolder timediff]];
    [p_newfolder setLastplayed:[onlyFolder lastplayed]];
    [p_newfolder setExcluded:[onlyFolder excluded]];
    [p_newfolder setLimitations:[NSString stringWithFormat:@"%@", [onlyFolder limitations]]];
    [p_newfolder setJoinid:[onlyFolder joinid]];
    [p_newfolder setIpodid:[onlyFolder ipodid]];
    [p_newfolder setSpotifyfolderid:[onlyFolder spotifyfolderid] ? [NSString stringWithFormat:@"%@", [onlyFolder spotifyfolderid]] : nil];

    [self setM_selectedfolderid:[onlyFolder folderid]];
    [self setM_selectedserverid:[onlyFolder serverid]];
    [self setM_selectedipodid:[onlyFolder ipodid]];
    [self setM_selectedspotifyfolderid:[onlyFolder spotifyfolderid] ? [NSString stringWithFormat:@"%@", [onlyFolder spotifyfolderid]] : nil];
    for (int i = 0; i < 2; i++) [m_searchview SetPicThreadStarted:i withval:NO];
    [self setM_moveTACInitTime:-1.0];
    [self ShowFolderRest];
}

// Reads the songs of p_newfolder from the database, checks their files and fills the coverflow.
- (void)ShowFolderRest {
    long long folderid = [p_newfolder folderid];
    [m_randomarray removeAllObjects];
    [DEL LockDB:NO];
    DBOperations *db = [[DBOperations alloc] init];
    NSMutableArray *songs = [db GetSongsForFolder:p_newfolder withjoin:YES];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (folderid == -44) {
        [db SetFolderLastPlayed:-1 withServerID:-1 withspotifyfolderid:nil];
        [ud setObject:[NSString stringWithFormat:@"%lld", [p_newfolder ipodid]] forKey:@"k_lastdirectfolderid"];
    } else if (folderid != -33) {
        [ud removeObjectForKey:@"k_lastdirectfolderid"];
        [db SetFolderLastPlayed:folderid withServerID:[p_newfolder serverid] withspotifyfolderid:[p_newfolder spotifyfolderid]];
    }
    [DEL UnlockDB];
    [ud synchronize];

    if (folderid != -33) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *ownDir = [NSString stringWithFormat:@"%@%@/", [DEL CreateServerDir:[m_parent m_sve] withfolderobject:p_newfolder],
                            [DEL Buildfoldername:p_newfolder]];
        NSMutableDictionary *dirs = [[NSMutableDictionary alloc] init];   // folder directories of songs of other folders
        for (ClipObject *c in songs) {
            NSString *dir;
            if ([c m_folderid] == [p_newfolder folderid]) {
                dir = ownDir;
            } else {
                dir = [dirs objectForKey:[NSNumber numberWithLongLong:[c m_folderid]]];
                if (dir == nil) {
                    [DEL LockDB:NO];
                    FolderObject *of = [db GetFolderForID:[c m_folderid] withserverid:[c m_serverid]
                                               withipodid:[c m_ipodid] withspotifyid:[c m_spotifyfolderid]];
                    [DEL UnlockDB];
                    dir = [NSString stringWithFormat:@"%@%@/", [DEL CreateServerDir:[m_parent m_sve] withfolderobject:of],
                           [DEL Buildfoldername:of]];
                    [dirs setObject:dir forKey:[NSNumber numberWithLongLong:[c m_folderid]]];
                    [of release];
                }
            }
            [DEL BuildAndCheckFilePathes:c withfm:fm withserverdir:dir withCheck:YES];
        }
        [p_newfolder release];
        p_newfolder = nil;
        [dirs release];
    } else if (p_newfolder) {
        [p_newfolder release];
        p_newfolder = nil;
    }
    [db release];

    [self GetArrayLock:NO];
    if (m_specialtexture) { [m_specialtexture release]; m_specialtexture = nil; }
    [[self m_origarray] removeAllObjects];
    [[self m_tilearray] removeAllObjects];
    [m_arraylock unlock];
    for (unsigned i = 0; i < [songs count]; i++) {
        ClipObject *c = [[songs objectAtIndex:i] retain];
        [self AddPicture:c];
    }
    [songs release];

    [self GetArrayLock:NO];
    if ([[self m_tilearray] count] == 0 && [[self m_origarray] count] != 0) {
        NSString *st = [[m_searchview m_searchlabel] text];
        if (st != nil && [st length] != 0) {
            [self ForwardEmptySearchfield];
            [[self m_tilearray] addObjectsFromArray:m_origarray];
        }
    }
    [m_arraylock unlock];

    // start position: the song last played in this folder if the overview knows it, else the middle of the list
    offset = (double)([[self m_tilearray] count] >> 1);
    if (m_mtscroller != nil) {
        int idx = [m_mtscroller GetIndexForID:[self m_selectedfolderid] withserverid:[self m_selectedserverid]
                                   withipodid:[self m_selectedipodid]];
        if (idx != -1) {
            [self LockMTOverview];
            MTObject *mt = [m_mtscroller GetMTObject:idx];
            [self UnlockMTOverview];
            if (mt != nil && [mt m_lastsongid] != -1) {
                offset = 0;
                for (unsigned i = 0; i < [[self m_tilearray] count]; i++) {
                    ClipObject *c = [[self m_tilearray] objectAtIndex:i];
                    if ([c ID] == [mt m_lastsongid] && [c m_ipodid] == [mt m_lastipodid]) { offset = (double)i; break; }
                }
            }
        }
    }
    [self drawView];
    if (offset >= (double)[[self m_tilearray] count]) {
        [m_interpretlabel setText:@""];
        [m_titlelabel setText:@""];
    } else {
        ClipObject *c = [[self m_tilearray] objectAtIndex:(unsigned)offset];
        [m_interpretlabel setText:[[c m_interpret] uppercaseString]];
        [m_titlelabel setText:[[c m_title] uppercaseString]];
    }
    if (folderid != -33 && m_startsong && ![DEL m_isstattalm])
        [m_parent StartFirstFolderSong:[NSNumber numberWithInt:0]];
    m_rondell_loaded = YES;
    if (m_startedpicthread) {
        [self performSelector:@selector(ReInitThread) withObject:nil afterDelay:0.01];
    } else {
        m_startedpicthread = YES;
        NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithLongLong:[self m_selectedfolderid]], @"id",
            [NSNumber numberWithInt:[self m_selectedserverid]], @"sid",
            [NSNumber numberWithLongLong:[self m_selectedipodid]], @"iid",
            [self m_selectedspotifyfolderid] ? [self m_selectedspotifyfolderid] : (id)[NSNull null], @"spotifyfolderid", nil];
        [NSThread detachNewThreadSelector:@selector(LoadPicsForRondell:) toTarget:self withObject:d];
    }
}

- (void)RemoveDraggingObject {
    if (!m_draggingpicture) return;
    if ([m_parent mMCMixer] != nil) [[m_parent mMCMixer] StopPreplay];
    m_draggingpicture = NO;
    if ([m_draggingobject m_imgv] && [[m_draggingobject m_imgv] superview]) [[m_draggingobject m_imgv] removeFromSuperview];
    if ([m_draggingobject m_imgvtext] && [[m_draggingobject m_imgvtext] superview]) [[m_draggingobject m_imgvtext] removeFromSuperview];
    if ([m_draggingobject m_swapimgv] && [[m_draggingobject m_swapimgv] superview]) [[m_draggingobject m_swapimgv] removeFromSuperview];
    if (m_draggingobject) { [m_draggingobject release]; m_draggingobject = nil; }
}

- (void)CheckDraggingObjectForWaiting {
    if (m_draggingobject != nil && [m_draggingobject ID] == -6) [self RemoveDraggingObject];
}

#pragma mark - pictures of the play queue

// The round "CD" picture of a song in the play queue (roundpic) or the big drag picture (not roundpic).
- (UIImage *)CreateCDPicture:(ClipObject *)cDPicture roundpic:(BOOL)roundpic {
    if ([cDPicture m_folderid] == -33) return nil;
    float size = 164.0f;
    int inset = 0;
    NSString *suffix = @"-big";
    if (roundpic) {
        size = ISIPAD ? 82.0f : 56.0f;
        inset = 1;
        suffix = ISIPAD ? @"" : @"-small";
    }
    if ([cDPicture m_folderid] == 3 && [cDPicture ID] != -5) return [UIImage imageNamed:@"rss-round.png"];
    UIImage *cover = [m_parent GetSongImage:[cDPicture m_picturepath] withclipobject:cDPicture];
    CGContextRef ctx = [DEL BeginImageContext:CGSizeMake(size, size)];
    if ([cDPicture ID] == -6) {
        CGContextSetFillColorWithColor(ctx, [[UIColor colorWithWhite:0.0f alpha:1.0f] CGColor]);
        CGContextDrawImage(ctx, CGRectMake(0, 0, size, size), [[UIImage imageNamed:@"waiting.png"] CGImage]);
        return [DEL EndImageContext:ctx];
    }
    BOOL tape = ([cDPicture m_folderid] == 1 && [cDPicture ID] != -5);
    UIImage *mask = [UIImage imageNamed:[NSString stringWithFormat:tape ? @"tape-cut%@.png" : @"circle-white%@.png", suffix]];
    float side = size - (float)(inset * 2);
    CGRect inner = CGRectMake((float)inset, (float)inset, side, side);
    // Port fix: CGContextClipToMask with an RGBA picture no longer uses the picture's alpha on current iOS (the disc came
    // out as a black square).  Draw the cover and keep only the pixels that the ring/disc picture covers instead.
    if (tape) {
        CGContextSetFillColorWithColor(ctx, [[self GetColorForProg:cDPicture] CGColor]);
        CGContextFillRect(ctx, inner);
    } else {
        CGContextDrawImage(ctx, inner, [cover CGImage]);
    }
    CGContextSetBlendMode(ctx, kCGBlendModeDestinationIn);
    CGContextDrawImage(ctx, inner, [mask CGImage]);
    CGContextSetBlendMode(ctx, kCGBlendModeNormal);
    UIImage *masked = [DEL EndImageContext:ctx];
    ctx = [DEL BeginImageContext:CGSizeMake(size, size)];
    CGContextDrawImage(ctx, inner, [masked CGImage]);
    NSString *ov = [NSString stringWithFormat:tape ? @"tape-overlay%@.png" : @"circle-overlap%@.png", suffix];
    CGContextDrawImage(ctx, inner, [[UIImage imageNamed:ov] CGImage]);
    return [DEL EndImageContext:ctx];
}

// Wide transparent text strip above a queue picture: remaining time, title and artist.
- (UIImage *)CreateTextPicture:(ClipObject *)textPicture withtime:(int)time maxWidthPointer:(int *)maxWidthPointer {
    if (textPicture == nil || [textPicture m_folderid] == -33 || [textPicture ID] == -6) return nil;
    BOOL ipad = ISIPAD;
    float base = ipad ? 82.0f : 56.0f;
    float W = base + 700.0f;
    CGContextRef ctx = [DEL BeginImageContext:CGSizeMake(W, (float)((double)base * 3.0 * 0.25))];
    UIFont *small = [UIFont systemFontOfSize:ipad ? 12.0f : 9.0f];
    CGContextSetFillColorWithColor(ctx, [[UIColor colorWithRed:0.0f green:0.0f blue:0.0f alpha:0.0f] CGColor]);
    CGContextFillRect(ctx, CGRectMake(0, 0, W, (float)((double)base * 3.0 * 0.25)));
    CGContextSetFillColorWithColor(ctx, [[UIColor whiteColor] CGColor]);
    float maxw = 0;
    if (time >= 1) {
        CGContextSetFillColorWithColor(ctx, [[UIColor colorWithWhite:0.6f alpha:1.0f] CGColor]);
        NSString *t = [NSString stringWithFormat:@"-%i:%02i", time / 60, time % 60];
        float tw = MIN([t sizeWithFont:small].width, W);
        [DEL OwndrawAtPoint:ctx withtext:t drawAtPoint:CGPointMake((W - tw) * 0.5f, base * 0.5f + (ipad ? 4.0f : 0.0f))
                   forWidth:(int)tw withFont:small lineBreakMode:0];
        if (tw > maxw) maxw = tw;
    }
    if ([[textPicture m_title] length] != 0) {
        UIFont *bold = [UIFont boldSystemFontOfSize:ipad ? 16.0f : 12.0f];
        CGContextSetFillColorWithColor(ctx, [[UIColor whiteColor] CGColor]);
        NSString *t = [[textPicture m_title] uppercaseString];
        float tw = MIN([t sizeWithFont:bold].width, W);
        [DEL OwndrawAtPoint:ctx withtext:t drawAtPoint:CGPointMake((W - tw) * 0.5f, base * 0.5f - 15.0f)
                   forWidth:(int)tw withFont:bold lineBreakMode:0];
        if (tw > maxw) maxw = tw;
    }
    if ([[textPicture m_interpret] length] != 0) {
        CGContextSetFillColorWithColor(ctx, [[UIColor colorWithWhite:0.7f alpha:1.0f] CGColor]);
        NSString *t = [[textPicture m_interpret] uppercaseString];
        float tw = MIN([t sizeWithFont:small].width, W);
        [DEL OwndrawAtPoint:ctx withtext:t drawAtPoint:CGPointMake((W - tw) * 0.5f, (base * 0.5f - 15.0f) - (ipad ? 17.0f : 12.0f))
                   forWidth:(int)tw withFont:small lineBreakMode:0];
        if (tw > maxw) maxw = tw;
    }
    if (maxWidthPointer) *maxWidthPointer = (int)maxw;
    return [DEL EndImageContext:ctx];
}

// Color of a recorded programme's tape.  The genre-dependent hue of the original belonged to the radio program data.
- (UIColor *)GetColorForProg:(ClipObject *)colorForProg {
    return [UIColor colorWithRed:0.13f green:0.173f blue:0.255f alpha:1.0f];
}

#pragma mark - touch handling

// A horizontal drag turns the coverflow, a vertical drag that starts on a cover pulls it into the play queue,
// a zig-zag with a pulled cover hides the song.  Taps come from the gesture recognizers.
- (void)touchesBegan:(NSSet *)touchesBegan withEvent:(UIEvent *)event {
    m_lastTouchTime = CACurrentMediaTime(); m_idleReturned = NO;
    m_directioncounter = 0;
    m_direction = -1;
    [self setM_moveTACInitTime:-1.0];
    if ([touchesBegan count] > 2) return;
    if ([DEL m_isstattalm] && m_sapointobject != nil) return;
    [self setM_fingersonscreen:[self m_fingersonscreen] + 1];
    UITouch *t = [touchesBegan anyObject];
    if (t == nil) return;
    CGPoint p = [t locationInView:self];
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    if (([[m_parent m_sve] StateFlags] & 0x10000) == 0 && [self m_selectedfolderid] != -33) {
        m_deletestartpoint = p;
        m_pointbefore = p;
        m_deletestartpointindex = -1;
        m_deletestarttime = CACurrentMediaTime();
        for (int i = 2; i < 5; i++) {      // the three covers in the middle
            if (CGRectContainsPoint(m_tipprects[i], p)) { m_deletestartpointindex = i; break; }
        }
        if (m_deletestartpointindex == -1) {
            m_deletestartpoint = CGPointZero;
            m_pointbefore = CGPointZero;
        }
    }
    m_directioncounter = 0;
    [self performSelector:@selector(touchesBeganDelayed:) withObject:po afterDelay:0];
}

- (void)touchesBeganDelayed:(CGPointObject *)touchesBeganDelayed {
    float x = [touchesBeganDelayed x];
    float y = [touchesBeganDelayed y];
    [touchesBeganDelayed release];
    if ([self m_fingersonscreen] >= 2) [self RemoveDraggingObject];
    [self setM_idleinittime:-1.0];
    [self setM_advertinittime:-1.0];
    if ([self m_autospin] || [self m_pinching]) return;
    if ([DEL m_isstattalm] && [self IsShowingAskBox]) { [self setM_cancelcard:YES]; return; }
    int hit = -1;
    for (int i = 0; i < 7; i++) {
        if (CGRectContainsPoint(m_tipprects[i], CGPointMake(x, y))) { hit = i; break; }
    }
    if (!m_flipping || hit != -1) {
        CGRect b = [self bounds];
        [self setTouchisok:YES];
        double pos = (double)(x / b.size.width) * 5.4 + -5.0;
        startPos = pos;
        startOff = offset;
        touchFlag = YES;
        startTime = CACurrentMediaTime();
        startTouch = CGPointMake(x, y);
        lastPos = pos;
    }
}

- (void)touchesMoved:(NSSet *)touchesMoved withEvent:(UIEvent *)event {
    m_lastTouchTime = CACurrentMediaTime(); m_idleReturned = NO;
    if ([self m_fingersonscreen] > 1) return;
    if (![self touchisok]) return;
    if ([self m_autospin] || [self m_pinching]) return;
    if ([touchesMoved count] > 2) return;
    if ([DEL m_isstattalm] && m_sapointobject != nil) return;
    UITouch *t = [touchesMoved anyObject];
    if (t == nil) return;
    CGPoint p = [t locationInView:self];
    if (m_deletestartpointindex != -1) {          // count the direction changes of a zig-zag
        if (m_direction == 0) {
            if (p.x > m_pointbefore.x) { m_directioncounter++; m_direction = 1; }
        } else if (m_direction == 1) {
            if (p.x < m_pointbefore.x) { m_directioncounter++; m_direction = 0; }
        } else {
            m_direction = (p.x > m_pointbefore.x) ? 1 : 0;
        }
        m_pointbefore = p;
    }
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    [self performSelector:@selector(touchesMovedDelayed:) withObject:po afterDelay:0];
}

- (void)touchesMovedDelayed:(CGPointObject *)touchesMovedDelayed {
    float x = [touchesMovedDelayed x];
    float y = [touchesMovedDelayed y];
    [touchesMovedDelayed release];
    CGRect b = [self bounds];
    int thumb = ISIPAD ? 0x52 : 0x38;
    if (m_draggingpicture) {          // the pulled cover follows the finger
        UIImageView *iv = [m_draggingobject m_imgv];
        [iv setFrame:CGRectMake(x - (float)(thumb >> 1), y - (float)(thumb >> 1), (float)thumb, (float)thumb)];
        CGRect f = [iv frame];
        [[m_draggingobject m_imgvtext] setFrame:CGRectMake(f.origin.x - 350.0f, (f.origin.y - f.size.height) - 23.0f,
                                                           (float)(thumb + 0x2bc), (float)((double)thumb * 3.0 * 0.25))];
        [[m_draggingobject m_swapimgv] setFrame:CGRectMake(f.origin.x + f.size.width * -0.5f, f.origin.y + f.size.height * -0.5f,
                                                           f.size.width + f.size.width, f.size.height + f.size.height)];
        return;
    }
    if (touchFlag) {
        int dx = (int)fabsf(x - startTouch.x);
        int dy = (int)fabsf(y - startTouch.y);
        if (dx <= 9 && dy < 10) return;                       // finger has not moved enough yet
        if ((double)dy * 1.1 > (double)dx) {                  // mostly vertical: try to pull a cover
            if (m_flipping && !CGRectContainsPoint(m_foregroundrect, CGPointMake(x, y))) return;
            int slot = -1;
            for (int i = 0; i < 7; i++) {
                if (CGRectContainsPoint(m_tipprects[i], startTouch)) { slot = i; break; }
            }
            if (slot != -1) {
                if (m_initcd) return;
                m_initcd = YES;
                NSMutableArray *paint = [[NSMutableArray alloc] init];
                NSMutableArray *pics = [[NSMutableArray alloc] init];
                [self GetArrayLock:NO];
                [self FillArrays:paint withPicOrder:pics];
                [m_arraylock unlock];
                int tileIdx = -1;
                if ([paint count] > (unsigned)(slot + 3))
                    tileIdx = [[pics objectAtIndex:[[paint objectAtIndex:slot + 3] intValue]] intValue];
                [paint release];
                [pics release];
                if (tileIdx == -1) { m_initcd = NO; goto scroll; }
                ClipObject *clip = [[self m_tilearray] objectAtIndex:tileIdx];
                if ([clip m_tracks] != nil && [[clip m_tracks] count] != 0) clip = [[clip m_tracks] objectAtIndex:0];
                if ([clip m_tracks] != nil) { m_initcd = NO; goto scroll; }
                if (m_draggingpicture) { m_initcd = NO; return; }
                if (CACurrentMediaTime() - [self m_preventdragging] < 1.1) { m_initcd = NO; return; }
                m_draggingpicture = YES;
                if ([m_parent mMCMixer] != nil) [[m_parent mMCMixer] PlayPrePlay:clip];
                m_draggingobject = [[ClipObject alloc] init];
                UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(x - (float)(thumb >> 1), y - (float)(thumb >> 1), (float)thumb, (float)thumb)];
                [m_draggingobject setM_imgv:iv];
                CGRect f = [iv frame];
                UIImageView *tv = [[UIImageView alloc] initWithFrame:CGRectMake(f.origin.x - 350.0f, (f.origin.y - f.size.height) - 23.0f,
                                                                                (float)(thumb + 0x2bc), (float)((double)thumb * 3.0 * 0.25))];
                [m_draggingobject setM_imgvtext:tv];
                [m_parent CopyPropertiesFromObject:clip toObject:m_draggingobject];
                [tv setImage:[self CreateTextPicture:clip withtime:-1 maxWidthPointer:NULL]];
                [iv setImage:[self CreateCDPicture:clip roundpic:YES]];
                [iv setAlpha:0.0f];
                [tv setAlpha:0.5f];
                [self addSubview:iv];
                [self addSubview:tv];
                [iv release];
                [tv release];
                UIImageView *sw = [[UIImageView alloc] initWithImage:[self CreateCDPicture:clip roundpic:NO]];
                [m_draggingobject setM_swapimgv:sw];
                [sw setFrame:CGRectMake(f.origin.x + f.size.width * -0.5f, f.origin.y + f.size.height * -0.5f,
                                        f.size.width + f.size.width, f.size.height + f.size.height)];
                [sw setAlpha:0.5f];
                [self addSubview:sw];
                [sw release];
                [m_parent SendCDsToBackGround];
                m_initcd = NO;
                return;
            }
            // vertical move that did not start on a cover: scrolls like a horizontal one
        } else {
            [self performSelector:@selector(LabelAni:) withObject:[NSNumber numberWithInt:0] afterDelay:0.01];
        }
    }
scroll:
    touchFlag = NO;
    {
        double pos = (double)(x / b.size.width) * 5.4 + -5.0;
        offset = startOff + (startPos - pos);
        [self checkOffset];
        [self drawView];
        double now = CACurrentMediaTime();
        if (now - startTime > 0.2) { startTime = now; lastPos = pos; }
    }
}

- (void)touchesEnded:(NSSet *)touchesEnded withEvent:(UIEvent *)event {
    m_lastTouchTime = CACurrentMediaTime(); m_idleReturned = NO;
    [self setM_fingersonscreen:0];
    if ([self m_pinching]) return;
    UITouch *t = [touchesEnded anyObject];
    if (t == nil) return;
    CGPoint p = [t locationInView:self];
    CGPointObject *po = [[CGPointObject alloc] init];
    [po setX:p.x];
    [po setY:p.y];
    [self performSelector:@selector(touchesEndedDelayed:) withObject:po afterDelay:0];
}

- (void)touchesCancelled:(NSSet *)touchesCancelled withEvent:(UIEvent *)event { m_lastTouchTime = CACurrentMediaTime(); m_idleReturned = NO; [self touchesCancelleddelayed]; }

- (void)touchesCancelleddelayed {
    [self setM_fingersonscreen:0];
    [self setTouchisok:NO];
    m_direction = -1;
    m_pointbefore = CGPointZero;
    m_id_to_delete = -1;
    m_directioncounter = 0;
    m_deletestartpoint = CGPointZero;
    m_deletestartpointindex = -1;
}

- (void)touchesEndedDelayed:(CGPointObject *)touchesEndedDelayed {
    [self RestartIdleTimer];
    [self RestartAdvertTimer];
    if (![m_parent g_scaling]) [self CheckToRemoveRegister];
    CGSize screen = [DEL GetiPadSize];
    BOOL ipad = ISIPAD;
    float x = [touchesEndedDelayed x];
    float y = [touchesEndedDelayed y];
    [touchesEndedDelayed release];
    float queueTop = (screen.height - (ipad ? 126.0f : 90.0f)) + 4.0f;   // upper edge of the play queue strip

    // zig-zag with a pulled cover: hide the song
    if (m_directioncounter >= 5 && m_draggingobject != nil && m_deletestartpointindex != -1
        && [self m_selectedfolderid] != -33 && [self m_selectedfolderid] != -66 && [self m_selectedfolderid] != -44
        && y < queueTop
        && fabsf(x - m_deletestartpoint.x) < 200.0f && fabsf(y - m_deletestartpoint.y) < 200.0f
        && CACurrentMediaTime() - m_deletestarttime < 5.0) {
        m_direction = -1;
        m_pointbefore = CGPointZero;
        m_directioncounter = 0;
        m_deletestartpoint = CGPointZero;
        m_id_to_delete = [m_draggingobject ID];
        [self RemoveDraggingObject];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, 0);
        if (m_id_to_delete != -6 && m_id_to_delete != -5) {
            BOOL stacked = NO;
            for (unsigned i = 0; i < [[self m_tilearray] count]; i++) {
                ClipObject *c = [[self m_tilearray] objectAtIndex:i];
                if ([c ID] == m_id_to_delete) { stacked = ([c m_tracks] != nil); break; }
            }
            if (!stacked) [self HideSongFunc:YES];
        }
        m_id_to_delete = -1;
        m_deletestartpointindex = -1;
        return;
    }
    m_direction = -1;
    m_pointbefore = CGPointZero;
    m_id_to_delete = -1;
    m_directioncounter = 0;
    m_deletestartpoint = CGPointZero;
    m_deletestartpointindex = -1;
    if ([self m_autospin]) return;
    CGRect b = [self bounds];
    if (!m_draggingpicture) {
        if (touchFlag) {
            // a tap without moving; the tap gesture recognizers do the work on iOS 4 and later
            if ([DEL m_ios] <= 3) [self InitFlipping:CGPointMake(x, y)];
        } else if ([self touchisok]) {
            startOff = offset;
            double pos = (double)(x / b.size.width) * 5.4 + -5.0;
            double v = (lastPos - pos) / (CACurrentMediaTime() - startTime);
            if (v > 10.0) v = 10.0;
            if (v < -10.0) v = -10.0;
            [self startCircleAnimation:v];
        }
        return;
    }
    // a pulled cover was let go
    [m_parent performSelector:@selector(SendCDsToBackGround) withObject:nil afterDelay:0.01];
    if ([m_draggingobject ID] == -5 || [m_draggingobject ID] == -6) {
        ClipObject *d = m_draggingobject;
        m_draggingobject = nil;
        [m_parent performSelector:@selector(DeleteCDAni:) withObject:d afterDelay:0.01];
        m_draggingpicture = NO;
        return;
    }
    [[m_draggingobject m_imgv] retain];
    [[m_draggingobject m_imgv] removeFromSuperview];
    [[m_draggingobject m_imgvtext] retain];
    [[m_draggingobject m_imgvtext] removeFromSuperview];
    [[m_draggingobject m_swapimgv] retain];
    [[m_draggingobject m_swapimgv] removeFromSuperview];
    if (y > queueTop && ![m_parent m_ordering]) {
        int at = [m_parent GetInsertIndex:CGPointMake(x, y)];
        BOOL fading = [m_parent m_fadingover];
        [m_parent setM_autoselected:NO];
        [m_parent setM_tenmintimer:CACurrentMediaTime()];
        ClipObject *d = m_draggingobject;
        m_draggingobject = nil;
        if (d != nil)
            [m_parent AddClip:d atIndex:((fading && at < 2) ? 2 : at) fromDragging:YES withsendqueue:YES withaddanyway:NO sendremotedelayed:NO];
    }
    if (m_draggingobject != nil) {
        [[m_draggingobject m_imgv] release];
        if ([m_draggingobject m_imgvtext]) [[m_draggingobject m_imgvtext] release];
        if ([m_draggingobject m_swapimgv]) [[m_draggingobject m_swapimgv] release];
        m_draggingobject = nil;
    }
    m_draggingpicture = NO;
    if ([m_parent mMCMixer] != nil)
        [[m_parent mMCMixer] performSelectorInBackground:@selector(StopPreplay) withObject:nil];
}

// Removes the clip m_id_to_delete from the lists, hides it in the database (the title stays on disk) and tells the overview.
- (void)HideSongFunc:(BOOL)songFunc {
    for (int i = 0; i < 20; i++) {
        m_deleteexplodefactor = (float)((double)m_deleteexplodefactor + 0.1);
        [self drawView];
    }
    [self GetArrayLock:NO];
    for (unsigned i = 0; i < [[self m_tilearray] count]; i++) {
        if ([[[self m_tilearray] objectAtIndex:i] ID] == m_id_to_delete) { [[self m_tilearray] removeObjectAtIndex:i]; break; }
    }
    ClipObject *removed = nil;
    for (unsigned i = 0; i < [[self m_origarray] count]; i++) {
        if ([[[self m_origarray] objectAtIndex:i] ID] == m_id_to_delete) {
            removed = [[[self m_origarray] objectAtIndex:i] retain];
            [[self m_origarray] removeObjectAtIndex:i];
            break;
        }
    }
    m_deleteexplodefactor = 1.0f;
    [m_arraylock unlock];
    [self checkOffset];
    m_lastmidindex = -2;
    [self drawView];
    if (removed != nil) {
        [DEL LockDB:NO];
        DBOperations *db = [[DBOperations alloc] init];
        [db HideTitle:removed];
        [db release];
        [DEL UnlockDB];
        [m_mtscroller DeleteClipObject:removed];
        [removed release];
    }
    if ([[self m_tilearray] count] == 0)
        [self performSelector:@selector(ChooseOtherMixtape:) withObject:[NSNumber numberWithLongLong:-1] afterDelay:0.01];
}

- (void)RemoveDraggingObjectIfSpotify {}

#pragma mark - gesture recognizers

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)shouldReceiveTouch {
    if ([shouldReceiveTouch view] != self) return NO;
    if (m_tapGestureRecognizer == gestureRecognizer) return [self m_pinchstatus] == 0;
    if (m_pinchGesture == gestureRecognizer) return YES;
    return m_doubletapGestureRecognizer == gestureRecognizer;
}

- (void)handleSingleTap:(UITapGestureRecognizer *)handleSingleTap {
    [self SingleTapFunc:[handleSingleTap locationInView:self]];
}

- (void)SingleTapFunc:(CGPoint)singleTapFunc {
    [self endCircleAnimation:YES];
    m_fingersonscreen = 0;
    [self RemoveDraggingObject];
    [self SnapRondell];
    if ([DEL m_ios] >= 4) {
        [self CheckToRemoveRegister];
        [self InitFlipping:singleTapFunc];
    }
    [self RestartIdleTimer];
    [self performSelector:@selector(PitchAni) withObject:nil afterDelay:0.1];
}

- (void)PitchAni { CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, 0); }

// A double tap on a cover puts the song into the play queue.
- (void)handleDoubleTap:(UITapGestureRecognizer *)handleDoubleTap {
    CGPoint p = [handleDoubleTap locationInView:self];
    [self endCircleAnimation:YES];
    int slot = -1;
    for (int i = 0; i < 7; i++) {
        if (CGRectContainsPoint(m_tipprects[i], p)) { slot = i; break; }
    }
    if (slot != -1) {
        NSMutableArray *paint = [[NSMutableArray alloc] init];
        NSMutableArray *pics = [[NSMutableArray alloc] init];
        [self GetArrayLock:NO];
        [self FillArrays:paint withPicOrder:pics];
        [m_arraylock unlock];
        int tileIdx = -1;
        if ([paint count] > (unsigned)(slot + 3))
            tileIdx = [[pics objectAtIndex:[[paint objectAtIndex:slot + 3] intValue]] intValue];
        [paint release];
        [pics release];
        if (tileIdx != -1) {
            ClipObject *c = [[self m_tilearray] objectAtIndex:tileIdx];
            if ([c ID] != -5 && [c m_folderid] != -33) {
                ClipObject *src = ([c m_tracks] == nil) ? c : [[c m_tracks] objectAtIndex:0];
                ClipObject *copy = [[ClipObject alloc] init];
                [m_parent CopyPropertiesFromObject:src toObject:copy];
                [self DoubleTapFunc:copy withpoint:p];
            }
        }
    }
    [self SnapRondell];
    m_fingersonscreen = 0;
    [self RemoveDraggingObject];
}

- (void)DoubleTapFunc:(ClipObject *)doubleTapFunc withpoint:(CGPoint)point {
    int thumb = ISIPAD ? 0x52 : 0x38;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(point.x - (float)(thumb >> 1), point.y - (float)(thumb >> 1), (float)thumb, (float)thumb)];
    [doubleTapFunc setM_imgv:iv];
    [iv setImage:[self CreateCDPicture:doubleTapFunc roundpic:YES]];
    [iv setAlpha:1.0f];
    [m_parent AddClip:doubleTapFunc atIndex:-1 fromDragging:NO withsendqueue:YES withaddanyway:NO sendremotedelayed:YES];
    [iv release];
    [m_parent setM_autoselected:NO];
    [m_parent setM_tenmintimer:CACurrentMediaTime()];
    if ([DEL m_isstattalm]) [m_parent StartFirstFolderSong:[NSNumber numberWithInt:0]];
}



// Port addition: centres the cover of a clip without any animation (used when the app autoplays at startup).
- (void)SelectClipImmediately:(ClipObject *)clip {
    if (clip == nil) return;
    [m_arraylock lock];
    int found = -1;
    NSArray *tiles = [self m_tilearray];
    for (unsigned i = 0; i < [tiles count] && found < 0; i++) {
        ClipObject *c = [tiles objectAtIndex:i];
        if ([c ID] == [clip ID]) { found = (int)i; break; }
        NSArray *tr = [c m_tracks];
        for (unsigned k = 0; tr != nil && k < [tr count]; k++)
            if ([[tr objectAtIndex:k] ID] == [clip ID]) { found = (int)i; break; }
    }
    [m_arraylock unlock];
    if (found < 0) return;
    if (timer != nil) [self endCircleAnimation:NO];
    offset = (double)found;
    [self checkOffset];
    [self drawView];
    ClipObject *c = [[self m_tilearray] objectAtIndex:(unsigned)found];
    [m_interpretlabel setText:[[c m_interpret] uppercaseString]];
    [m_titlelabel setText:[[c m_title] uppercaseString]];
    [self ReInitThread];
}

static double gRfxLeftT0 = 0;          // when the app was left / the screen locked (0 = in front)

// After a longer lock iOS may have dropped GL resources or sent memory warnings (which also clear the textures); the covers
// vanished until the next app start.  Rebuild everything the covers need and restart the loader.
- (void)ResumeAfterBackground {
    double away = (gRfxLeftT0 > 0) ? (CACurrentMediaTime() - gRfxLeftT0) : 0;
    gRfxLeftT0 = 0;
    m_memorywarning = NO;
    if (context == nil) return;
    [EAGLContext setCurrentContext:context];
    if (away > 20.0) {
        [self EmptyAllTextures];
        [self CreatePlaceholderTextures];
    }
    [self ReInitThread];
    [self drawView];
    [self performSelector:@selector(ReInitThread) withObject:nil afterDelay:0.5];
}

- (void)FinishGL {
    if (context == nil) return;
    if (gRfxLeftT0 == 0) gRfxLeftT0 = CACurrentMediaTime();
    EAGLContext *old = [EAGLContext currentContext];
    [EAGLContext setCurrentContext:context];
    glFinish();
    if (old != context) [EAGLContext setCurrentContext:old];
}

// Port addition: 10 s without touch input -> the coverflow scrolls back to the song that is playing.
- (void)CheckReturnToPlaying {
    if (m_idleReturned || gv_kioskflag || [DEL m_isinbackground]) return;
    if (CACurrentMediaTime() - m_lastTouchTime < 10.0) return;
    if ([self m_fingersonscreen] > 0 || timer != nil || [self m_autospin] || [self m_pinching] || [self m_pinchstatus] != 0) return;
    if ([m_searchview m_keyboardshown] || [m_parent g_scaling] || [m_parent m_draggingobj] != nil) return;
    if ([self m_selectedfolderid] == -33) return;
    NSArray *clips = [m_parent m_clips];
    if (clips == nil || [clips count] == 0 || ![m_parent IsPlayingClips]) return;
    m_idleReturned = YES;
    ClipObject *playing = [clips objectAtIndex:0];
    [self SpinAutomaticToClip:playing orIndex:-1];
}

// Dev menu: re-render all cover textures (e.g. after the border option changed).
- (void)RefreshCoverTextures {
    [self EmptyAllTextures];
    [self CreatePlaceholderTextures];
    [self ReInitThread];
    [self drawView];
}

#pragma mark - turning animation

- (void)startCircleAnimation:(double)circleAnimation {
    if (timer != nil) [self endCircleAnimation:NO];
    double travel = (circleAnimation * circleAnimation) / 18.0;
    if (circleAnimation < 0) travel = -travel;
    double target = floor((startOff + travel) + 0.5);
    startSpeed = sqrt(fabs(target - startOff) * 9.0 + fabs(target - startOff) * 9.0);   // constant deceleration of 9 covers/s^2
    if (target < startOff) startSpeed = -startSpeed;
    runDelta = fabs(startSpeed / 9.0);
    startTime = CACurrentMediaTime();
    CADisplayLink *dl = [CADisplayLink displayLinkWithTarget:self selector:@selector(driveCircleAnimation)];
    [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    timer = dl;
}

- (void)driveCircleAnimation {
    double t = CACurrentMediaTime() - startTime;
    if (t >= runDelta) { [self endCircleAnimation:YES]; return; }
    if ([self m_fingersonscreen] < 1) [self updateCircleAnimationAtTime:t];
    else [self endCircleAnimation:YES];
}

- (void)updateCircleAnimationAtTime:(double)t {
    if (runDelta < t) t = runDelta;
    double d = fabs(startSpeed) * t + (t * 9.0 * t) * -0.5;
    if (startSpeed < 0) d = -d;
    offset = startOff + d;
    [self checkOffset];
    [self drawView];
}

- (void)endCircleAnimation:(BOOL)endCircleAnimation {
    if (timer == nil) return;
    [timer invalidate];
    timer = nil;
    offset = floor(offset + 0.5);
    [self checkOffset];
    [self drawView];
    [self ReInitThread];
    [self performSelector:@selector(LabelAni:) withObject:[NSNumber numberWithInt:1] afterDelay:0.01];
}

- (void)SnapRondell {
    offset = nearbyint(offset);
    [self checkOffset];
    [self drawView];
    [self performSelector:@selector(LabelAni:) withObject:[NSNumber numberWithInt:1] afterDelay:0.01];
}

// Keeps 'offset' inside the list: lists up to 10 covers stop at the ends, longer ones wrap around.
- (void)checkOffset {
    int n = (int)[[self m_tilearray] count];
    if (n < 11) {
        if (offset > (double)(n - 1)) offset = (double)(n - 1);
        if (offset < 0) offset = 0;
        return;
    }
    if (offset >= (double)n) offset = offset - (double)n;
    if (offset < 0) offset = offset + (double)n;
}

// Fades title and interpret label out while turning (0) and in again when the flow rests (1).
- (void)LabelAni:(NSNumber *)labelAni {
    if ([self m_pinchstatus] > 0) return;
    int v = [labelAni intValue];
    [UIView beginAnimations:@"labelanimation" context:NULL];
    [UIView setAnimationCurve:UIViewAnimationCurveLinear];
    [UIView setAnimationDuration:0.3];
    float a = (v == 1) ? 1.0f : 0.0f;
    [m_titlelabel setAlpha:a];
    [m_interpretlabel setAlpha:a];
    [UIView commitAnimations];
}

// Turns the coverflow to a clip (or an index) with the speed-up / cruise / slow-down animation of the original.
- (void)SpinAutomaticToClip:(ClipObject *)spinAutomaticToClip orIndex:(int)orIndex {
    if ([self m_fingersonscreen] > 0 || timer != nil || [self m_pinching] || [self m_pinchstatus] != 0 || [m_parent g_scaling]) return;
    [self GetArrayLock:YES];
    int n = (int)[[self m_tilearray] count];
    int target = -1;
    if (spinAutomaticToClip != nil) {
        for (int i = 0; i < n && target == -1; i++) {
            ClipObject *c = [[self m_tilearray] objectAtIndex:i];
            if ([c m_tracks] != nil) {
                for (ClipObject *tr in [c m_tracks]) {
                    if ([tr m_folderid] == -44 ? ([tr m_ipodid] == [spinAutomaticToClip m_ipodid]) : ([tr ID] == [spinAutomaticToClip ID])) {
                        target = i;
                        break;
                    }
                }
            }
            if (target == -1) {
                if ([c m_folderid] == -44 ? ([c m_ipodid] == [spinAutomaticToClip m_ipodid]) : ([c ID] == [spinAutomaticToClip ID]))
                    target = i;
            }
        }
    } else if (orIndex >= 0 && orIndex < n) {
        target = orIndex;
    }
    int dist = -1;
    float dir = 1.0f;
    int cur = (int)offset;
    if (target != -1 && target != cur) {
        int fwd = (cur <= target) ? target - cur : (n < 11 ? -1 : n + target - cur);
        int back = (target <= cur) ? cur - target : (n < 11 ? -1 : n - target + cur);
        if (fwd != -1 && (back == -1 || fwd <= back)) { dist = fwd; dir = 1.0f; }
        else if (back != -1) { dist = back; dir = -1.0f; }
        if (dist != -1) {
            [self setM_autospin:YES];
            [self Setspinaddlock:YES];
        }
    }
    [m_arraylock unlock];
    if (dist == -1) return;
    [self performSelector:@selector(LabelAni:) withObject:[NSNumber numberWithInt:0] afterDelay:0.01];
    if (dist >= 21) {
        // far away: jump to 13 covers in front of the target so the animation stays short
        // (the original moved the covers in between out of the list for this, see DEVIATIONS.md)
        double s = (double)target - (double)dir * 13.0;
        if (s < 0) s += n;
        if (s >= n) s -= n;
        offset = s;
        dist = 13;
    }
    // Port change: the turn is driven by a display link on the main run loop.  It used to be a loop that blocked the main thread for
    // 2-3 seconds, so taps (search button, keyboard), the search list and the tutorial froze while the coverflow turned by itself.
    // Time based, slow ease-in/ease-out (the original ran at a fixed step per frame and peaked at ~36 covers/s).
    // Fix: offset is usually fractional (the flow was resting between two covers or came from a drag); the old code moved by a whole
    // number of covers and so ended on the same fraction = hanging between two covers.  Now the distance is corrected so it lands exactly.
    double frac = (double)offset - floor((double)offset);
    m_spinDist = (double)dist - (double)dir * frac; m_spinDir = (double)dir; m_spinStartOff = offset;
    m_spinDur = (1.3 + 0.3 * sqrt((double)dist) * 2.0) * 0.9;           // 1 cover ~1.9 s, 5 covers ~2.6 s, 13 covers ~3.5 s
    m_spinT0 = CACurrentMediaTime();
    [m_spinLink invalidate];
    m_spinLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(SpinTick:)];
    [m_spinLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)SpinSetOffsetFrom:(double)startOff moved:(double)moved {
    int n = (int)[[self m_tilearray] count];
    if (n <= 0) return;
    double o = startOff + m_spinDir * moved;
    while (o >= (double)n) o -= (double)n;
    while (o < 0) o += (double)n;
    offset = o;
}

- (void)SpinTick:(CADisplayLink *)link {
    if (!m_autospin) { [link invalidate]; if (m_spinLink == link) m_spinLink = nil; return; }
    double t = (CACurrentMediaTime() - m_spinT0) / m_spinDur;
    BOOL done = (t >= 1.0 || [DEL g_end] || gv_kioskflag || [self m_fingersonscreen] > 0);
    if (!done) {
        double e = t * t * t * (t * (t * 6.0 - 15.0) + 10.0);     // smootherstep
        [self SpinSetOffsetFrom:m_spinStartOff moved:e * m_spinDist];
        [self drawView];
        return;
    }
    [link invalidate];
    if (m_spinLink == link) m_spinLink = nil;
    if (t >= 1.0) [self SpinSetOffsetFrom:m_spinStartOff moved:m_spinDist];
    { double r = floor((double)offset + 0.5); int nn = (int)[[self m_tilearray] count]; if (nn > 0 && fabs((double)offset - r) < 0.2 && [self m_fingersonscreen] == 0) { if (r >= nn) r -= nn; offset = r; } }   // snap to the cover
    [self setM_autospin:NO];
    [self drawView];                      // restarts the frame chain (water, covers that are still loading)
    [self performSelector:@selector(LabelAni:) withObject:[NSNumber numberWithInt:1] afterDelay:0.01];
    [self ReInitThread];
}

- (void)Setspinaddlock:(BOOL)setspinaddlock {}

#pragma mark - idle timers and small accessors

- (void)RestartIdleTimer { m_idleflag = NO; [self setM_idleinittime:CACurrentMediaTime()]; }
- (void)IdleTimerFunc { m_idleflag = YES; }
- (void)StopIdleTimer { m_idleflag = NO; [self setM_idleinittime:-1.0]; }
- (void)RestartAdvertTimer { [self setM_advertinittime:CACurrentMediaTime()]; }
- (void)StopAdvertTimer { [self setM_advertinittime:-1.0]; }

- (id)getScroller { return m_mtscroller; }
- (void)UnlockMTOverview { [m_mtoverviewlock unlock]; }
- (void)LockMTOverview { [m_mtoverviewlock lock]; }
- (BOOL)CanShowOverview { return !((m_lastflags >> 13) & 1); }
- (void)SetLastmidindex:(int)lastmidindex { m_lastmidindex = lastmidindex; }
- (float)Getoglscale { return m_oglscale; }
- (long long)GetSelectedIpodid { return [self m_selectedipodid]; }
- (int)GetSelectedServerid { return [self m_selectedserverid]; }
- (long long)GetSelectedFolderid { return [self m_selectedfolderid]; }
- (id)GetKBView { return m_searchview; }
- (BOOL)IsShowingChannelView { return [self m_selectedfolderid] == -33; }
- (BOOL)IsShowingAskBox { return NO; }
- (BOOL)isShowingDimmViewOrNoConnView { return NO; }
- (BOOL)IsShowingMTScroller { return m_mtscroller != nil && ![m_mtscroller isHidden]; }
- (void)SwitchCardReaderLight:(BOOL)on {}
- (void)ReleaseLastPlayingInfos {}
- (void)ForwardEmptySearchfield { [m_searchview EmptySearchfield]; }
- (void)ForwardDelete30secSearchText { [m_searchview DeleteSearchText30Sec]; }
- (void)LockSDC { [m_prescrollerlock lock]; }
- (void)UnlockSDC { [m_prescrollerlock unlock]; }

- (long long)GetActSongID {
    [self GetArrayLock:NO];
    long long r = -1;
    if ((unsigned)[[self m_tilearray] count] > (unsigned)(int)offset) r = [[[self m_tilearray] objectAtIndex:(int)offset] ID];
    [m_arraylock unlock];
    return r;
}

- (long long)GetActIpodID {
    [self GetArrayLock:NO];
    long long r = 0;
    if ((unsigned)[[self m_tilearray] count] > (unsigned)(int)offset) r = [[[self m_tilearray] objectAtIndex:(int)offset] m_ipodid];
    [m_arraylock unlock];
    return r;
}

- (NSString *)GetSearchText {
    if (m_searchview == nil) return nil;
    return [[m_searchview m_searchlabel] text];
}

- (int)GetSearchTextLen {
    NSString *t = [self GetSearchText];
    return t ? (int)[t length] : 0;
}

- (void)GLVEndFunction {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [m_searchview KBVEndFunction];
    if (m_mtscroller != nil) [m_mtscroller StopOverviewTimer];
}

@end
