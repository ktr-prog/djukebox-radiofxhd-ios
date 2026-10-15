// GLView : UIView -- OpenGL ES 1.x coverflow (recovered; layout re-derived for 64-bit)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <QuartzCore/QuartzCore.h>

extern BOOL gRfxBetaLook;          // dev menu: layout of the first Tobit Djukebox

@class CGPointObject, ClipObject, DataCache, FlowCoverRecord, FolderObject, KeyboardView, KioskView, MTScroller, RegisterImage;

@interface GLView : UIView <UIGestureRecognizerDelegate, UIScrollViewDelegate, UITableViewDelegate, UITableViewDataSource, NSCoding> {
    double offset;  // +48
    int backingWidth;  // +56
    int backingHeight;  // +60
    float m_oglscale;  // +64
    EAGLContext *context;  // +68
    GLuint viewRenderbuffer;  // +72
    GLuint viewFramebuffer;  // +76
    DataCache *cache;  // +80
    NSMutableArray *paintorder;  // +84
    NSMutableArray *pictureorder;  // +88
    unsigned char *GData;          // malloc(1 MB) scratch for texture upload  // +92
    unsigned char *GDataThread;    // malloc(1 MB), used by the loader thread  // +1048668
    id timer;  // CADisplayLink, +2097244
    double startTime;  // +2097248
    double startOff;  // +2097256
    double startPos;  // +2097264
    double startSpeed;  // +2097272
    double runDelta;  // +2097280
    BOOL touchFlag;  // +2097288
    BOOL secondgestureflag;  // +2097289
    CGPoint m_cp1;  // +2097292
    CGPoint m_cp2;  // +2097300
    CGPoint startTouch;  // +2097308
    double lastPos;  // +2097316
    BOOL touchisok;  // +2097324
    float *m_colors;  // +2097328
    double m_transangles[4];  // +2097332
    double m_anglediff;  // +2097364
    BOOL m_flipping;  // +2097372
    double m_flippingangle;  // +2097376
    NSMutableArray *m_tilearray;  // +2097384
    NSMutableArray *m_randomarray;  // +2097388
    NSLock *m_arraylock;  // +2097392
    NSMutableArray *m_orderbeforejumping;  // +2097396
    FlowCoverRecord *m_specialtexture;  // +2097400
    BOOL m_draggingpicture;  // +2097404
    ClipObject *m_draggingobject;  // +2097408
    BOOL m_drawempty;  // +2097412
    BOOL m_drawemptyturn;  // +2097413
    BOOL m_rotateready;  // +2097414
    BOOL m_initcd;  // +2097415
    KioskView *m_parent;  // +2097416
    UILabel *m_titlelabel;  // +2097420
    UILabel *m_interpretlabel;  // +2097424
    int m_lastmidindex;  // +2097428
    CGRect m_tipprects[7];  // +2097432
    CGRect m_radiotipprects[7];  // +2097544
    float m_yup;  // +2097656
    float m_inclineangle;  // +2097660
    NSMutableArray *m_clipstodelete;  // +2097664
    KeyboardView *m_searchview;  // +2097668
    RegisterImage *m_registers[10];  // +2097672
    NSMutableArray *m_origarray;  // +2097712
    CGRect m_reddotrects[2];  // +2097716
    CGRect m_reddotrectssmall[2];  // +2097748
    CGRect m_reddotrect;  // +2097780
    CGRect m_foregroundrects[2];  // +2097796
    CGRect m_foregroundrectssmall[2];  // +2097828
    CGRect m_foregroundrect;  // +2097860
    BOOL m_ishorizontal;  // +2097876
    BOOL m_autospin;  // +2097877
    long long m_selectedfolderid;  // +2097880
    NSString *m_selectedspotifyfolderid;  // +2097888
    int m_selectedserverid;  // +2097892
    long long m_selectedipodid;  // +2097896
    double m_idleinittime;  // +2097904
    double m_moveTACInitTime;  // +2097912
    double m_advertinittime;  // +2097920
    BOOL m_executingflags;  // +2097928
    UIImageView *m_channelaniimageview;  // +2097932
    UIImageView *m_kioskscreenshot;  // +2097936
    UIView *m_blackview;  // +2097940
    BOOL m_movingregisters;  // +2097944
    FlowCoverRecord *m_blacktexture;  // +2097948
    FlowCoverRecord *m_blacktextureradio;  // +2097952
    FlowCoverRecord *m_placeholdertexture;  // +2097956
    FlowCoverRecord *m_placeholdertextureradio;  // +2097960
    NSArray *m_genrearray;  // +2097964
    BOOL m_pinching;  // +2097968
    float m_pinchscale;  // +2097972
    float m_additionalalpha;  // +2097976
    int m_pinchstatus;  // +2097980
    int m_newselectedfolderindex;  // +2097984
    int m_lastpinchoffset;  // +2097988
    int m_fingersonscreen;  // +2097992
    int m_lastflags;  // +2097996
    UIPinchGestureRecognizer *m_pinchGesture;  // +2098000
    BOOL m_rondell_loaded;  // +2098004
    MTScroller *m_mtscroller;  // +2098008
    float m_volumepinch;  // +2098012
    BOOL m_movingup;  // +2098016
    float m_lastpinchscale;  // +2098020
    double m_lastTouchTime;
    BOOL m_idleReturned;
    BOOL m_idleflag;  // +2098024
    BOOL m_startsong;  // +2098025
    UIImageView *m_folderscreenshot;  // +2098028
    FolderObject *p_newfolder;  // +2098032
    BOOL m_showonlysearch;  // +2098036
    BOOL m_blinkpic;  // +2098037
    BOOL m_isblinking;  // +2098038
    BOOL m_blinkpicsync;  // +2098039
    int m_shouldblinksync;  // +2098040
    int m_lastplayedchannelid;  // +2098044
    UITapGestureRecognizer *m_tapGestureRecognizer;  // +2098048
    UITapGestureRecognizer *m_doubletapGestureRecognizer;  // +2098052
    NSString *channelswithepg;  // +2098056
    NSString *m_lastmetatitle;  // +2098060
    NSString *m_lastmetainterpret;  // +2098064
    BOOL m_startedpicthread;  // +2098068
    NSCondition *m_condition[1];  // +2098072
    int m_conditioncounter[1];  // +2098076
    BOOL m_memorywarning;  // +2098080
    NSLock *m_deletetexturelock;  // +2098084
    NSMutableArray *m_deletetexqueue;  // +2098088
    long long m_tryrestoreoffset;  // +2098092
    NSString *m_trytorestorespotifyid;  // +2098100
    NSLock *m_mtoverviewlock;  // +2098104
    double m_lastmtovsearchtime;  // +2098108
    NSMutableDictionary *m_prescrollerdict;  // +2098116
    NSLock *m_prescrollerlock;  // +2098120
    BOOL m_prescrollerthreaddone;  // +2098124
    double m_preventdragging;  // +2098128
    int m_direction;  // +2098136
    int m_directioncounter;  // +2098140
    CGPoint m_pointbefore;  // +2098144
    float m_deleteexplodefactor;  // +2098152
    long long m_id_to_delete;  // +2098156
    CGPoint m_deletestartpoint;  // +2098164
    double m_deletestarttime;  // +2098172
    int m_deletestartpointindex;  // +2098180
    CGPoint m_oldpicposition;  // +2098184
    int m_radioanivar;  // +2098192
    int m_sidtexturestodelete;  // +2098196
    BOOL m_threadwaiting;  // +2098200
    int m_oglversion;  // +2098204
    UITableView *m_tracktable;  // +2098208
    ClipObject *m_tracksong;  // +2098212
    BOOL m_tracknumberpresent;  // +2098216
    UIView *m_dimmview;  // +2098220
    UIImageView *m_notconview;  // +2098224
    BOOL m_blinkanirunning;  // +2098228
    long long m_autogotofolder;  // +2098232
    int m_autogotoserver;  // +2098240
    CGPointObject *m_sapointobject;  // +2098244
    int m_sarstatus;  // +2098248
    id mCE;  // TCardReaderEvents (hardware card reader; unused)  // +2098252
    NSString *m_newcardfound;  // +2098256
    ClipObject *m_saDoubleTapCo;  // +2098260
    NSNumber *m_saStatusID;  // +2098264
    NSString *m_statusText;  // +2098268
    id m_askbox;  // LoginView (server login; unused)  // +2098272
    BOOL m_cancelcard;  // +2098276
    NSTimer *m_brandingpictimer;  // +2098280
    BOOL m_autoremovekeyboard;  // +2098284
}
@property (nonatomic, retain) NSString *m_trytorestorespotifyid;
@property (nonatomic, retain) NSString *m_selectedspotifyfolderid;
@property (assign) BOOL m_cancelcard;
@property (nonatomic, retain) NSString *m_statusText;
@property (nonatomic, retain) NSNumber *m_saStatusID;
@property (nonatomic, retain) NSString *m_newcardfound;
@property (assign) long long m_autogotofolder;
@property (assign) int m_autogotoserver;
@property (assign) long long m_id_to_delete;
@property (assign) int m_oglversion;
@property (assign) long long m_selectedipodid;
@property (assign) BOOL m_threadwaiting;
@property (assign) float m_volumepinch;
@property (assign) int m_sidtexturestodelete;
@property (assign) double m_moveTACInitTime;
@property (assign) int m_radioanivar;
@property (assign) double m_preventdragging;
@property (assign) int m_selectedserverid;
@property (assign) int m_lastpinchoffset;
@property (assign) double m_lastmtovsearchtime;
@property (assign) int m_lastplayedchannelid;
@property (assign) double m_advertinittime;
@property (assign) double m_idleinittime;
@property (assign) BOOL touchisok;
@property (assign) BOOL m_idleflag;
@property (assign) int m_pinchstatus;
@property (assign) int m_newselectedfolderindex;
@property (assign) BOOL m_movingup;
@property (assign) int m_lastflags;
@property (assign) BOOL m_autoremovekeyboard;
@property (assign) int m_fingersonscreen;
@property (assign) BOOL m_pinching;
@property (assign) BOOL m_executingflags;
@property (assign) long long m_selectedfolderid;
@property (nonatomic, assign) FlowCoverRecord *m_specialtexture;
@property (nonatomic, assign) NSMutableArray *m_clipstodelete;
@property (assign) float m_yup;
@property (assign) BOOL m_rotateready;
@property (assign) BOOL m_drawemptyturn;
@property (assign) BOOL m_drawempty;
@property (nonatomic, retain) NSMutableArray *m_origarray;
@property (nonatomic, retain) NSMutableArray *m_tilearray;
@property (nonatomic, retain) EAGLContext *context;
@property (readonly) GLuint viewFramebuffer;
@property (readonly) GLuint viewRenderbuffer;
@property (assign) BOOL m_autospin;
- (void)SetLastmidindex:(int)lastmidindex;
- (void)AddFromSearchList:(id)fromSearchList;
- (BOOL)IsShowingAskBox;
- (void)SetRegisterToSync:(int)registerToSync;
- (void)ShowDisconPicAniFinished;
- (void)ShowDisconnectedPicture:(id)disconnectedPicture;
- (void)AddDisconnView:(float)disconnView;
- (void)InsertIntoRemoteQueue:(int)intoRemoteQueue withpoint:(CGPoint)point witharg1:(long long)arg1 witharg2:(int)arg2 witharg3:(int)arg3 withleaveoutclient:(long)leaveoutclient witharg4:(int)arg4;
- (void)DoRegisterTouch:(id)doRegisterTouch;
- (void)EmptyAllTextures;
- (void)ReShowFolder;
- (id)getScroller;
- (void)UnlockMTOverview;
- (void)LockMTOverview;
- (BOOL)CanShowOverview;
- (long long)GetActIpodID;
- (long long)GetActSongID;
- (id)GetActSpotifyID;
- (long long)GetSelectedIpodid;
- (int)GetSelectedServerid;
- (long long)GetSelectedFolderid;
- (void)ForwardDeclineCache;
- (void)dealloc;
- (void)RemoveTexturesExeptRondell;
- (void)ForwardDelete30secSearchText;
- (void)SetMemoryWarning;
- (void)StopIdleTimer;
- (void)StopAdvertTimer;
- (void)releaseArraylock;
- (id)GetOGLScreenshot;
- (BOOL)isShowingDimmViewOrNoConnView;
- (float)Getoglscale;
- (void)UnlockSDC;
- (void)LockSDC;
- (id)GetSDC:(id)sDC;
- (void)DeleteSDC:(id)sDC;
- (id)GetPreScrollerDict;
- (void)ExecuteFlagsRest;
- (void)ExecuteServerFlagsRest:(int)executeServerFlagsRest;
- (BOOL)GetRegisterFBWALLenabled;
- (void)ExecuteServerFlags:(id)executeServerFlags;
- (void)Setspinaddlock:(BOOL)setspinaddlock;
- (void)SpinAutomaticToClip:(id)spinAutomaticToClip orIndex:(int)orIndex;
- (void)RemoveGlass;
- (void)touchesMovedDelayed:(id)touchesMovedDelayed;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (id)CreateCDPicture:(id)cDPicture roundpic:(BOOL)roundpic;
- (id)CreateTextPicture:(id)textPicture withtime:(int)time maxWidthPointer:(int *)maxWidthPointer;
- (void)CheckDraggingObjectForWaiting;
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesCancelleddelayed;
- (void)touchesEndedDelayed:(id)touchesEndedDelayed;
- (void)AskForCard;
- (void)FadeDimmViewForBox:(BOOL)fadeDimmViewForBox;
- (void)FadeDimmViewForBoxDidStop;
- (void)SARequestThread;
- (void)HideSongFunc:(BOOL)songFunc;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)CheckToRemoveRegister;
- (void)FlipBackAni:(id)flipBackAni;
- (void)FlipBack2;
- (void)flipCleanup;   // helper (shared tail of FlipBackAni:/FlipBack2)
- (BOOL)deleteMatches:(ClipObject *)c single:(ClipObject *)single folder:(FolderObject *)folder;   // helper (inlined in the original)
- (void)deleteFilesOfClip:(ClipObject *)c fm:(NSFileManager *)fm;   // helper (inlined in the original)
- (void)FlipAni;
- (void)TrackTableAni:(float)trackTableAni;
- (void)SetParent:(id)parent;
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesBeganDelayed:(id)touchesBeganDelayed;
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)willDecelerate;
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
- (void)RestartIdleTimer;
- (void)RestartAdvertTimer;
- (void)AdvertTimerFunc;
- (void)ShowVolumeForOverview;
- (void)AdvertTimerFuncDelayed;
- (void)IdleTimerFunc;
- (id)GetSearchText;
- (int)GetSearchTextLen;
- (void)CheckReturnToPlaying;
- (void)RefreshCoverTextures;
- (void)RemoveQueuedFrom:(NSMutableArray *)cand;
- (void)MarkClipPlayed:(ClipObject *)clip;
- (void)FinishGL;
- (void)SelectClipImmediately:(ClipObject *)clip;
- (void)startCircleAnimation:(double)circleAnimation;
- (void)driveCircleAnimation;
- (void)updateCircleAnimationAtTime:(double)circleAnimationAtTime;
- (void)checkOffset;
- (GLuint)imageToTexture:(id)imageToTexture withNumber:(int)number withClipArray:(id)clipArray withclipObject:(id)clipObject borderalreadypresent:(BOOL)borderalreadypresent;
- (void)BindTexture:(id)bindTexture;
- (void)DoTexture:(id)doTexture;
- (id)CreateNakedImage:(id)nakedImage withNumber:(int)number withClipArray:(id)clipArray withclipObject:(id)clipObject withtexturesize:(int)texturesize onlychannellogo:(BOOL)onlychannellogo borderalreadypresent:(BOOL)borderalreadypresent;
- (void)ReleaseLastPlayingInfos;
- (void)CheckChannelsInRondell;
- (id)GetColorForProg:(id)colorForProg;
- (BOOL)IsShowingChannelView;
- (void)AddRedDot:(int)redDot withContext:(CGContextRef )contextArg;
- (void)destroyFramebuffer;
- (BOOL)createFramebuffer;
- (void)layoutSubviews;
- (void)SetUpTippRects;
- (void)SetForegroundRect:(CGSize)foregroundRect;
- (void)SetRedDotRect:(CGSize)redDotRect;
- (void)DeleteTextures;
- (void)ReInit:(BOOL)reInit;
- (void)drawView;
- (BOOL)drawIntern;
- (void)RestrictXValue:(float *)restrictXValue withzintern:(float)zintern;
- (void)CalcRadioAniValues:(float *)calcRadioAniValues withy:(float *)y withChannelinfo:(id)channelinfo;
- (void)SetInterpretLabelText:(id)interpretLabelText;
- (void)SetTitleLabelText:(id)titleLabelText;
- (void)SetLabelTexts:(id)labelTexts;
- (void)FillArrays:(id)fillArrays withPicOrder:(id)picOrder;
- (id)getTileAtIndex:(int)tileAtIndex withCreate:(BOOL)create;
- (id)initWithCoder:(NSCoder *)coder;
- (id)initWithFrame:(CGRect)frame;
- (void)RemoveDraggingObjectIfSpotify;
- (void)RemoveDraggingObject;
- (void)CheckToDeleteFolderFromPicPath:(id)toDeleteFolderFromPicPath;
- (void)HelperFuncShowFolder:(id)helperFuncShowFolder;
- (void)ChooseOtherMixtape:(id)chooseOtherMixtape;
- (void)DeleteSongsWithFolder:(id)songsWithFolder justSingleSong:(id)justSingleSong;
- (void)EmptyRondell;
- (void)LoadPicsForRondell:(id)picsForRondell;
- (void)ReInitThread;
- (void)SendSignal:(int)sendSignal;
- (void)WaitForSignal:(int)waitForSignal;
- (void)CreateTile:(int)tile withcounter:(int *)counter withEAGLCTX:(id)eAGLCTX;
- (void)HelpergetTileatIndex:(id)helpergetTileatIndex withEAGLCTX:(id)eAGLCTX;
- (void)EmptyCache;
- (void)ShowOnlyFolder:(id)onlyFolder withstartSong:(BOOL)startSong channelviewwaspresent:(BOOL)channelviewwaspresent;
- (void)ShrinkAniDidStop;
- (void)ForwardBeginSearchinMTScroller;
- (void)ShowFolderRest;
- (void)RenameFolder:(id)renameFolder;
- (void)RemoveKeyBoardDelayed;
- (void)ForwardHelppicAni;
- (void)CheckToDeleteFolder:(id)toDeleteFolder;
- (id)getNextClipObject;
- (void)RemoveVirtBrandingSong:(id)virtBrandingSong;
- (void)BeginSearchinBG:(id)beginSearchinBG;
- (void)BeginSearch:(id)beginSearch;
- (void)BeginSearchInMTScroller:(id)beginSearchInMTScroller;
- (void)ReloadSecSvrTable;
- (void)MTSearchBackGround:(id)mTSearchBackGround;
- (BOOL)IsShowingMTScroller;
- (void)ForwardRestartOverviewTimer;
- (BOOL)IsClipInSearchrange:(id)clipInSearchrange withsearchtext:(id)searchtext;
- (BOOL)SubSearch:(id)subSearch withsearchtext:(id)searchtext;
- (CGRect)GetRegisterRect:(int)registerRect;
- (BOOL)Getprescrollerthreaddone;
- (void)AddPicture:(id)picture;
// Plugin titles that are being loaded: the cover shows water that fills up from the bottom (level 0..1)
- (void)SetWaterForClipID:(long long)cid level:(float)level;
- (void)ClearWater;
- (void)BuildCoverNowForPluginClipID:(long long)cid;
- (void)SetPicture:(NSString *)path forPluginClipID:(long long)cid;
- (void)RemovePluginPlaceholder:(long long)cid;
- (void)ShowAllTilesKeepingSearch;
- (void)ReplacePluginPlaceholder:(long long)cid withClip:(ClipObject *)clip;
- (void)SetFilepath:(NSString *)path forPluginClipID:(long long)cid;
- (void)LabelAni:(id)labelAni;
- (void)ToggleKBAndRegister:(id)toggleKBAndRegister;
- (void)OpenFBWallUrl;
- (void)OpenHintUrl;
- (void)OpenConfigUrl;
- (void)ToggleAni;
- (void)ReInitDimmView;
- (void)MoveOneRegister:(CGSize)moveOneRegister;
- (void)StartSyncBlinkAni;
- (void)SyncBlinkAniEnd;
- (void)KBToggleDidStop;
- (void)StartBlinkAni;
- (void)BlinkAniEnd;
- (void)ReturnToLastSelectedFolder;
- (void)ResetupMTScroller;
- (void)ForcePinching;
- (void)MoveRegisters:(BOOL)moveRegisters;
- (void)HideRegisters:(BOOL)registers;
- (void)CheckToStartServerConnection;
- (void)CheckForNewChoosenServer;
- (void)CheckToStartServerDialog;
- (id)GetKBView;
- (CGRect)GetKBViewFrame:(CGSize)kBViewFrame;
- (void)FitSubViews:(CGSize)fitSubViews;
- (void)scaleCircle:(id)scaleCircle;
- (void)ForwardSetVolSlider:(float)forwardSetVolSlider;
- (void)PinchAni1DidStop;
- (void)HelperFuncLoadFolder:(id)helperFuncLoadFolder;
- (void)PinchAniBack;
- (void)ReStartMTScroller;
- (void)ReLoadScrollerInMT;
- (void)ReLoadScrollerDelayed;
- (void)PinchAniBackDidStop;
- (void)PrepareCloseScroller;
- (void)PinchAni;
- (void)AddPinch:(int)pinch;
- (void)EPGNowNoti:(id)ePGNowNoti;
- (int)GetlastplayedChannelindex;
- (void)NewMetaInterpret:(id)newMetaInterpret;
- (void)NewMetaTitle:(id)newMetaTitle;
- (void)EPGNowNotiInMainThread:(id)ePGNowNotiInMainThread;
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch;
- (void)PrescrollerThread;
- (BOOL)IsInAlbumArray:(id)inAlbumArray witharray:(id)array;
- (void)handleDoubleTap:(UITapGestureRecognizer *)gr;
- (void)DoubleTapFunc:(id)doubleTapFunc withpoint:(CGPoint)point;
- (void)handleSingleTap:(UITapGestureRecognizer *)gr;
- (void)PitchAni;
- (void)SingleTapFunc:(CGPoint)singleTapFunc;
- (void)BrandingTimerFunc:(id)brandingTimerFunc;
- (void)endCircleAnimation:(BOOL)endCircleAnimation;
- (void)SnapRondell;
- (void)InitFlipping:(CGPoint)initFlipping;
- (void)StartPreScrollerThread;
- (void)AddKBView;
- (void)SetSearchRegisterActive;
- (id)GetRegister0;
- (void)NewCard:(id)newCard;
- (void)CardRemoved:(id)cardRemoved;
- (void)CardFound:(id)cardFound;
- (void)SwitchCardReaderLight:(BOOL)switchCardReaderLight;
- (void)SpotifyPicSaved:(id)spotifyPicSaved;
- (void)DeleteSpotifySong:(id)spotifySong;
- (id)internalInit;
- (void)GetArrayLock:(BOOL)arrayLock;
- (void)CreatePlaceholderTextures;
- (void)CreateBlackTexture:(id *)blackTexture;
- (void)ReloadBrandingInMT;
- (void)InitiateOverviewAni;
- (void)CheckToShowRegister6;
- (void)SetDrawVars:(CGSize)drawVars;
- (CGRect)GetFrameForChannelView:(CGSize)frameForChannelView;
- (CGRect)GetRegisterFrame:(CGSize)registerFrame withindex:(int)indexArg;
- (void)MoveToActiveChannel;
- (CGRect)GetTitleInterpretLabelFrame:(CGSize)titleInterpretLabelFrame withtype:(int)type;
- (void)ForwardEmptySearchfield;
- (void)GLVEndFunction;
- (BOOL)IsEPGChannel:(int)ePGChannel;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)OpenGLInit;
+ (Class)layerClass;
@end
