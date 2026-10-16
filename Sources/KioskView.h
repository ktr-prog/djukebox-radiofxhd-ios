// KioskView : UIView  (recovered; armv7 instance size 564)
// Holds the play queue (m_clips), the divider/progress strip below the coverflow and drives playback.
// Dropped feature groups are listed in DEVIATIONS.md.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class ClipObject, FolderObject, GLView, MultichannelMixerController, ServerEntry, HelpPicture;

@interface KioskView : UIView <UIAlertViewDelegate, AVAudioPlayerDelegate> {
    BOOL m_ignoreXdiff;
    MultichannelMixerController *mMCMixer;
    UILabel *m_label;
    UILabel *m_ratelabel;
    UIView *m_divider;
    GLView *m_glv;
    NSMutableArray *m_clips;
    BOOL m_cantransform;
    BOOL cancelcopy;
    double startTime;
    int border;
    double m_angle;
    double m_lastRotTime;
    UIImageView *m_spinView;
    double m_spinHold;
    BOOL m_restEarly;
    NSString *m_lastrateinfo;
    double m_clipStartTime;
    double m_clipDuration;
    ClipObject *m_draggingobj;
    BOOL m_fadingover;
    ClipObject *m_cliptorotate;
    BOOL m_firstcheck;
    ServerEntry *m_sve;
    UIView *m_blackview;
    NSTimer *m_foldertimer;
    BOOL m_rotateclip;
    BOOL m_shrinkdevider;
    double m_presongInitTime;
    double m_presongDuration;
    double m_crossfadeDuration;
    double m_crossfadeInitTime;
    double m_30secsearchInitTime;
    BOOL m_first_start;
    BOOL m_autoselected;
    BOOL m_updateunzipped;
    BOOL m_didfade;
    int m_oldindex;
    NSTimer *m_shutdowntimer;
    BOOL m_shutdown;
    BOOL m_freespace;
    float m_lastvolume;
    BOOL m_ordering;
    BOOL m_draggingrunningsong;
    HelpPicture *m_helpPicture;
    id m_rcon;                          // remote-control connection (never set offline)
    NSMutableDictionary *m_nowdict;     // "<channel>_picx" -> now-playing picture
    BOOL m_helppicanimating;
    int m_tutorialpage;
    BOOL m_fiveoclockflag;
    double m_limitinittime;
    double m_limitduration;
    BOOL m_copynotifyflag;
    int m_trailerimagetime;
    CGPoint m_starttouchpoint;
    int m_songcounter;
    int m_jingleindex;
    BOOL m_playingjingle;
    UIView *m_blackoverlay;
    NSArray *m_colorarray;
    float m_crossfadetime;
    float m_curfade;   // fade length of the running song (dev menu: Überblendzeit)
    BOOL m_willplayradio;
    UIFont *m_titlefont;
    BOOL m_stopsecondthread;
    BOOL m_lastonline;
    UIPinchGestureRecognizer *m_pinchGesture;
    UIImageView *m_tslogo;
    int m_draggingorigpos;
    int m_dragginposforremotecmds;
    BOOL g_scaling;
    float m_volumebefore;
    AVAudioPlayer *m_wdrplayer;
    BOOL m_errorplayingsong;
    BOOL m_enableddebuggingtext;
    BOOL m_resetangle;
    double m_pausebegintime;
    double m_resetfadeover;
    BOOL m_didstopmanual;
    NSString *m_lastshownNoCoverFor;
    double m_tenmintimer;
    UIView *m_activateView;
    double m_lastsongdragged;
    UIView *m_waitview;
    UIView *m_blackborderview;
    BOOL m_showfirstsongInfos;
    UIImageView *m_loadingscreen;
    UILabel *m_loadinglabel;
    int m_lastCDXDiff;
    BOOL m_threadrunning[2];
}
@property (assign) double m_lastsongdragged;
@property (assign) double m_tenmintimer;
@property (nonatomic, retain) NSString *m_lastshownNoCoverFor;
@property (assign) BOOL m_didstopmanual;
@property (assign) double m_resetfadeover;
@property (assign) double m_clipStartTime;
@property (assign) double m_pausebegintime;
@property (assign) BOOL m_errorplayingsong;
@property (assign) BOOL g_scaling;
@property (nonatomic, retain) MultichannelMixerController *mMCMixer;
@property (nonatomic, retain) ClipObject *m_draggingobj;
@property (assign) BOOL m_stopsecondthread;
@property (assign) BOOL m_willplayradio;
@property (assign) int m_trailerimagetime;
@property (assign) BOOL m_copynotifyflag;
@property (assign) double m_limitduration;
@property (assign) double m_limitinittime;
@property (assign) BOOL m_ordering;
@property (assign) float m_lastvolume;
@property (assign) BOOL m_freespace;
@property (assign) double m_30secsearchInitTime;
@property (assign) double m_crossfadeInitTime;
@property (assign) double m_crossfadeDuration;
@property (assign) double m_presongDuration;
@property (assign) double m_presongInitTime;
@property (assign) BOOL m_shrinkdevider;
@property (assign) BOOL m_rotateclip;
@property (assign) BOOL m_updateunzipped;
@property (assign) BOOL m_autoselected;
@property (assign) BOOL m_first_start;
@property (assign) BOOL cancelcopy;
@property (assign) BOOL m_fadingover;
@property (nonatomic, retain) ServerEntry *m_sve;
@property (nonatomic, retain) NSMutableArray *m_clips;
@property (assign) BOOL m_cantransform;
@property (nonatomic, retain) GLView *m_glv;
@property (assign) BOOL m_ignoreXdiff;

- (GLView *)m_glv;
- (GLView *)GetGLView;
- (id)GetBlackView;
- (BOOL)ShowingLoadingscreen;
- (void)CheckLoadingscreen;
- (void)SetDebugText:(NSString *)debugText;
- (void)CheckDebugTextEnabled;
- (void)ExternDraw:(int)externDraw;
- (void)ExternDrawInMT:(NSNumber *)externDrawInMT;
- (void)FitSubViews:(CGSize)fitSubViews;
- (void)CreateFonts;
- (CGRect)GetOpenGLFrame:(CGSize)openGLFrame;
- (CGRect)GetDividerFrame:(CGSize)dividerFrame;
- (CGRect)GetDebugLabelFrame:(CGSize)debugLabelFrame;
- (CGRect)GetBlackBorderViewRect;
- (CGRect)GetBlackOverLayViewRect;
- (float)GetBlackOverlayAlpha;
- (CGRect)GetFrameForDragPic:(int)frameForDragPic;
- (CGRect)GetFrameForDragPicText:(int)frameForDragPicText;
- (CGRect)MakeSmallFrame:(CGRect)makeSmallFrame;

// folders
- (void)FolderTimerfunc:(id)timer;
- (void)StartDirectFolder:(FolderObject *)directFolder;
- (long long)GetSelectedFolderid;
- (int)GetSelectedServerid;
- (void)StartFirstFolderSong:(NSNumber *)firstFolderSong;
- (void)StartveryfirstSong;
- (BOOL)IsInArray:(FolderObject *)inArray witharray:(NSArray *)array;
- (BOOL)FolderInArray:(FolderObject *)folderInArray withArray:(NSArray *)array;
- (void)CheckNoFolders;
- (void)CheckLimitations;
- (void)CheckLimitationsLater;
- (void)CheckNextTime:(int *)nextTime withchecktime:(int)checktime withsecofday:(int)secofday;
- (BOOL)SongFitsInRondell:(ClipObject *)song;
- (void)CheckQueueInMainThread:(NSNumber *)queueInMainThread;
- (void)RemoveDirectChannelKey;

// queue
- (void)AddClip:(ClipObject *)clip atIndex:(int)indexArg fromDragging:(BOOL)dragging withsendqueue:(BOOL)sendqueue withaddanyway:(BOOL)addanyway sendremotedelayed:(BOOL)sendremotedelayed;
- (void)AddClipInMainthread:(id)clipInMainthread;
- (void)AddCDPictureToView:(ClipObject *)cDPictureToView;
- (void)AddPictureToKiosk:(id)pictureToKiosk;
- (void)OrderClipPics:(NSNumber *)orderClipPics;
- (void)MoveCDs;
- (void)StartOrderAni:(ClipObject *)orderAni;
- (void)OrderClipsReady;
- (void)CorrectZindexComplete:(ClipObject *)correctZindexComplete;
- (void)CorrectZindex:(UIView *)correctZindex;
- (int)GetInsertIndex:(CGPoint)insertIndex;
- (void)CheckInsertPosition:(int *)insertPosition;
- (void)FinalDelete:(ClipObject *)finalDelete;
- (void)DeleteCDAni:(ClipObject *)cDAni;
- (void)StartNotAcceptedAni:(ClipObject *)notAcceptedAni withqueuecd:(ClipObject *)queuecd;
- (void)SimpleDeleteWithOrder:(NSNumber *)simpleDeleteWithOrder;
- (void)RemoveAndOrderImage:(ClipObject *)andOrderImage;
- (void)RemoveDragginObjInMT;
- (void)DelPicInMainThread:(ClipObject *)delPicInMainThread;
- (void)RemoveImageInMainThread:(UIView *)imageInMainThread;
- (void)SendCDsToBackGround;
- (void)OrderGLVAndBlackView;
- (BOOL)spotifyIDsMatch:(NSString *)a withsecondid:(NSString *)b;
- (NSString *)BuildMTFoldername:(FolderObject *)folder;
- (void)FitGLViewForiPhone:(BOOL)radio;
- (BOOL)selectedSpotifyIDMatches:(NSString *)other;
- (UIImage *)BlackAndWhitePicture:(UIImage *)pic withfolderid:(long long)folderid;
- (void)EmptyQueue;
- (void)SwapImage:(ClipObject *)swapImage withalpha:(float)alpha;
- (ClipObject *)IsClipInList:(ClipObject *)clipInList;
- (void)CopyPropertiesFromObject:(ClipObject *)from toObject:(ClipObject *)to;
- (void)CheckPendingSong;
- (void)RemoveOnlyFirstClip;
- (void)SetupRemoteCommands;
- (void)UpdateNowPlayingRate;
- (void)UpdateNowPlayingForClip:(ClipObject *)clip;
- (void)RefreshNowPlayingDuration;
- (void)CheckQueueHintLabel;
- (void)SetLeftTimeInMTFirstObject:(UIImage *)leftTimeInMTFirstObject;
- (void)SetLeftTimeInMT:(UIImage *)leftTimeInMT;
- (void)CheckRunningSongLeftTime;
- (int)GetSongTimeLeft:(ClipObject *)songTimeLeft;
- (int)GetTimeActSongPlayed;
- (int)GetTimeGone;

// pictures
- (UIImage *)GetSongImage:(NSString *)songImage withclipobject:(ClipObject *)clipobject;
- (NSString *)ExtractPicture:(NSString *)extractPicture;
- (void)BrightenPicture:(NSData *)brightenPicture;
- (void)CreateSmallPic:(UIImage *)smallPic withClipObject:(ClipObject *)clipObject;
- (UIImage *)GetSmallImage:(ClipObject *)smallImage;
- (BOOL)CreateFolder:(NSString *)folder;

// touches
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesBeganDelayed:(id)touchesBeganDelayed;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMovedDelayed:(id)touchesMovedDelayed;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEndedDelayed:(id)touchesEndedDelayed;
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)scaleVolume:(UIPinchGestureRecognizer *)scaleVolume;

// playback
- (void)StartAudioPlayer:(ClipObject *)audioPlayer withAniNext:(BOOL)aniNext witharg1:(int)arg1;
- (BOOL)AniToNextSong:(ClipObject *)aniToNextSong withjingle:(NSString *)jingle;
- (void)StartAudioPlayerRest;
- (void)StartOnePlayer:(int)onePlayer withVolume:(float)volume withurl:(NSURL *)url withclipobject:(ClipObject *)clipobject;
- (void)PlayFileOnBackground:(NSString *)fileOnBackground;
- (void)SetMixerFlags;
- (void)CheckNextSong:(NSDictionary *)nextSong;
- (void)PresongTimerFunction;
- (void)StartPresongTimer:(int)presongTimer;
- (void)StartCrossFadeTimer:(int)crossFadeTimer;
- (void)FadeOverProcess:(id)fadeOverProcess;
- (void)SpinWhenNoAdvertising:(ClipObject *)spinWhenNoAdvertising;
- (void)StopPlayers;
- (void)ContinuePlayers;
- (void)PausePlayers;
- (BOOL)IsPlayingClips;
- (BOOL)WillPlayJingle;
- (void)SetPlayerVolume:(float)playerVolume;
- (void)SetWdrPlayerVolume:(float)wdrPlayerVolume;
- (float)GetPlayerVolume;
- (void)LowerVolume:(BOOL)lowerVolume;
- (void)RaiseVolume;
- (void)SetLastVolumeKiosk;
- (void)ErrorPlayingSong;
- (void)OtherAudio:(int)otherAudio;
- (void)ContinueFunction;
- (void)ReStartIfNeeded;
- (void)TryReleaseMMCMixer;
- (void)EndFunction;
- (void)CardReaderOff;
- (void)StartKioskShutdowntimer:(int)kioskShutdowntimer;
- (void)OpenSourcesPanel;
- (void)StopKioskShutdowntimer;
- (void)ShutdownFunction:(id)shutdownFunction;
- (void)Restart30secsearchTimer;
- (void)ResetTACTime:(double)tACTime;
- (void)LogoAni:(NSNumber *)logoAni;

// divider / timers
- (void)StartDevider:(int)devider;
- (void)DeviderTimerFunc;
- (void)SetDeviderPlayingPercent:(float)deviderPlayingPercent;
- (void)SetDeviderPlayingPercentDelayed:(NSNumber *)deviderPlayingPercentDelayed;
- (void)SetDeviderPlayingPercentMT;
- (int)CalcXDiff:(float)calcXDiff;
- (void)RotationTimerFunction;
- (void)RotationFrame;
- (void)TimerThread;

// unchanged helpers used by the forwarders
- (void)StartThread;
- (BOOL)IsThreadRunning;
- (void)SyncSVEwithUserdef;
- (void)RefreshSettings;
- (void)SetRadioAniVar:(int)radioAniVar;
- (void)StopOverviewTimer;
- (void)AirplayRestart;
- (void)SendChangesToRemoteApps;
- (void)HandleQueueTapAtX:(float)x;
- (void)SpinToBrandingPic;
- (long long)GetIDFromNSString:(NSString *)str withisipodstring:(BOOL)isipod;
- (id)GetRCConDeviceID;
- (UIImage *)GetSongPictureFor:(NSString *)title withinterpret:(NSString *)interpret;
- (void)StartHelpPictureAni;
- (void)FlushGLForBackground;
- (void)ShowDevMenu;
- (void)CloseDevMenu;
- (void)DevSwitchChanged:(UISwitch *)sw;
- (void)UpdateBackdropForClip:(ClipObject *)c;
- (void)DevSliderDone:(UISlider *)sl;
- (void)ShowTutorial;
- (void)ShowTutorialPage;
- (void)TutorialTap:(UITapGestureRecognizer *)g;
- (void)CloseTutorial;
- (NSMutableDictionary *)m_nowdict;
- (void)InsertIntoRemoteQueue:(int)type withpoint:(CGPoint)point witharg1:(long long)arg1 witharg2:(int)arg2
                     witharg3:(int)arg3 withleaveoutclient:(long)leaveoutclient witharg4:(int)arg4;
- (void)StartTPAni:(id)arg;
@end


// Plugin manager (implementation in KioskView.m): autostart of source plugins, their results in the normal search,
// import of plugin titles into the library.
@class ClipObject;
@interface RfxPluginManager : NSObject
+ (RfxPluginManager *)shared;
+ (void)Toast:(NSString *)t;
- (void)setKiosk:(KioskView *)kv;
- (void)StartAutoload;
- (void)SearchText:(NSString *)text done:(void (^)(NSString *text, NSArray *clips))done;
- (void)ImportClip:(ClipObject *)co;
- (NSArray *)AllNames;
- (void)MovePlugin:(NSString *)name by:(int)delta;
- (void)StreamVideoForTitle:(NSString *)title artist:(NSString *)artist videoId:(NSString *)vid done:(void (^)(NSDictionary *))done;
- (void)ResolveRedirect:(NSDictionary *)red fallback:(NSDictionary *)fb exclude:(NSString *)ex done:(void (^)(id, NSString *))done;
- (NSArray *)SearchPlatforms;   // {id, name, note} of every loaded plugin that can search (sorted by name)
- (BOOL)IsAutostart:(NSString *)name;
- (void)SetAutostart:(BOOL)on forName:(NSString *)name;
- (void)FinishImportQueue:(BOOL)queue;
- (void)PlaybackStarted:(ClipObject *)c;
- (void)PlaybackEnded;
@end
