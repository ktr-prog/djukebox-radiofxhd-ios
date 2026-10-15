// KeyboardView : UIView -- recovered from Radiofx_iPad (armv7).
// The sliding panel below the coverflow: volume slider (register 0) and search keyboard + result table (register 2).
// The web/help/menu/second-server panels (registers 1,3,5..9) belong to the dead backend and are not part of this build.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern BOOL gRfxPlayNow;       // set while a title the user chose is put into the queue: it plays right away

@class GLView, KioskView, KeyboardView;

// MenuView -- the small native panels of the original app: type 0 "Newsflash" (hourly time announcement check box),
// type 1 off-timer radio list, type 2 "Videothek" list.  Recovered from -[MenuView ...] of Radiofx_iPad.
@interface MenuView : UIView {
    BOOL m_setupobserver;
    BOOL m_cmset[8];
    KeyboardView *m_kbview;
    KioskView *m_pkiosk;
    int m_type;
    int m_offindex;
    NSMutableArray *m_labels;
    UIImageView *m_topimgv;
    NSMutableArray *m_imgvs;
    NSMutableArray *m_videothek;
}
- (void)Setup:(int)setup;
- (int)RowCount;
- (void)SetParent:(KeyboardView *)parent;
- (void)SetKioskPointer:(KioskView *)kiosk;
- (void)SetBackColor;
- (id)GetFirstVideo;
- (void)AddCheckmark:(int)checkmark withrect:(CGRect)rect;
- (CGRect)GetWDRCheckboxFrame:(int)index;
- (CGRect)GetWDRLabelFrame:(int)index;
- (CGRect)GetWDRSlizerFrame:(int)index;
- (void)StartWDRSoundForLine:(int)line;
- (void)StartVideoForLine:(int)line;
@end

@interface KeyboardView : UIView <UITableViewDelegate, UITableViewDataSource, UIWebViewDelegate> {
    UIImageView *m_keyboardpic;       // +48
    UILabel *m_nonewtitles;           // +52
    UIView *m_sliderbackground;       // +56
    BOOL m_keyboardshown;             // +60
    GLView *m_parent;                 // +64
    UILabel *m_searchlabel;           // +68
    UIImageView *m_xfield;            // +72
    CGRect m_backspacerect;           // +76
    double m_keyboardinittime;        // +92
    int m_showwhat;                   // +100
    UISlider *m_volslider;            // +104
    UIImageView *m_voloverlay;        // +108
    id m_secsvr;                      // second-server table (remote servers; never created offline)
    KioskView *m_pkiosk;              // +128
    UIView *m_cursorview;             // +132
    NSTimer *m_cursortimer;           // +136
    UITableView *m_srtableview;       // +140
    NSMutableArray *m_srarray;        // +144
    NSMutableArray *m_srarrayother;   // +148
    NSMutableDictionary *m_srplatitems;   // plugin id -> hits of that platform (own section each, also when empty)
    NSMutableArray *m_srarrayplugin;  // hits of source plugins (own section in the result list)
    float m_srprog;                   // search progress shown as fill of the plugin section header (< 0: none)
    NSString *m_srprogname;           // source name / id shown in that header while it loads
    NSString *m_srprogid;
    UIView *m_srfill;                 // fill view of the current header (not retained)
    BOOL m_srreloadpending;
    int m_cursoroff;                  // cursor position: characters before the end of the search text
    NSMutableDictionary *m_srshown;   // plugin hit id -> modification time of the thumbnail last shown
    NSLock *m_srlock;                 // +152
    UIView *m_srbgview;               // +156
    BOOL m_srpicthreadstarted[16];     // +160
    BOOL m_resortflag[16];             // +162
    UILabel *m_collectionnamelabel;   // +164
    UILabel *m_founditemslabel;       // +168
    UIImageView *m_collectionicon;    // +172
    BOOL m_gotooverview;              // +176
    BOOL m_draggingvolume;            // +204
    MenuView *m_wdrview;              // +188  register 1  "Newsflash"
    MenuView *m_onoffview;            // +192  register 3  off timer
    MenuView *m_videoview;            // +196  register 7  "Videothek"
    UIWebView *m_webview;             // +112  register 6  settings page
    UIWebView *m_hintwebview;         // +116  register 8  recommendations page
    UIWebView *m_FBwebview;           // +120  register 9  pin-board
    UIActivityIndicatorView *progView;
    UILabel *m_weblabel;              // port: shows why a web panel is empty (back-end gone)
}
@property (assign) BOOL m_draggingvolume;
@property (nonatomic, retain) NSMutableArray *m_srarrayother;
@property (assign) double m_keyboardinittime;
@property (assign) BOOL m_gotooverview;
@property (nonatomic, retain) UIImageView *m_xfield;
@property (assign) int m_showwhat;
@property (nonatomic, retain) UILabel *m_searchlabel;
@property (assign) BOOL m_keyboardshown;

- (void)KBVEndFunction;
- (void)EmptySearchfield;
- (void)FitSubViews:(CGSize)fitSubViews;
- (void)FitVolumeElements:(CGSize)fitVolumeElements;
- (void)DeleteSearchText30Sec;
- (void)ShowElements:(int)elements;
- (void)HideAll;
- (void)ForwardKioskPointer:(KioskView *)forwardKioskPointer;
- (void)volSliderTouchUp:(id)volSliderTouchUp;
- (void)volSliderDown:(id)volSliderDown;
- (void)volSliderAction:(id)volSliderAction;
- (void)SetFoundItemsLabelText:(NSNotification *)foundItemsLabelText;
- (void)InstallVolumeSlider:(CGSize)installVolumeSlider;
- (void)StopKeyboardtimer;
- (void)SetElementpositions;
- (void)SetKBBackGroundPic:(CGSize)kBBackGroundPic;
- (void)RestartKeyboardtimerFast;
- (void)RestartKeyboardtimer;
- (void)KBTimerFunc;
- (void)SRPictureThread:(NSNumber *)sRPictureThread;
- (NSMutableArray *)GetReSortedArray:(int)reSortedArray;
- (void)RefreshSettings;
- (void)SetUpSearchList:(NSArray *)upSearchList;
- (void)BeginSearchOtherArray;
- (void)BeginSearchOtherArrayBackGround;
- (NSMutableArray *)SubBGSearch:(NSString *)subBGSearch withdbop:(id)dbop withfolders:(NSArray *)folders;
- (int)getNumberOfRowsInSection:(int)numberOfRowsInSection;
- (void)SetParent:(GLView *)parent;
- (CGRect)GetBackspaceRect:(CGSize)backspaceRect;
- (CGRect)GetXFieldFrame;
- (CGRect)GetFoundItemsFrame:(CGSize)foundItemsFrame;
- (CGRect)GetCollectionIconFrame:(CGSize)collectionIconFrame;
- (CGRect)GetCollectionnameFrame:(CGSize)collectionnameFrame;
- (CGRect)GetTextfieldFrame:(CGSize)textfieldFrame;
- (CGRect)GetVolOverlayFrame:(CGSize)volOverlayFrame;
- (CGRect)GetSliderFrame:(CGSize)sliderFrame;
- (CGRect)GetSliderBGFrame:(CGSize)sliderBGFrame;
- (CGRect)GetKBPicFrame:(CGSize)kBPicFrame;
- (CGRect)GetSearchScrollerFrame:(CGSize)searchScrollerFrame;
- (CGRect)GetSearchScrollerBGFrame:(CGSize)searchScrollerBGFrame;
- (CGRect)GetNoNewTitlesFrame:(CGSize)noNewTitlesFrame;
- (void)StopCursorblinking;
- (void)StartCursorBlinking;
- (void)SetCursorFrame;
- (void)CursorTimerFunction:(NSTimer *)cursorTimerFunction;
- (void)SetVolSlider:(float)volSlider;
- (void)SpinDelayed:(id)spinDelayed;
- (void)AddItemFromSearchList:(int)itemFromSearchList withsection:(int)section withdirectClipObject:(id)directClipObject;
- (void)GetTableMatrix:(int)tableMatrix withitemsincolum:(int *)itemsincolum withcolumcount:(int *)columcount;
- (void)SetPicThreadStarted:(int)picThreadStarted withval:(BOOL)val;
- (void)SetImagesOnSlider:(UISlider *)imagesOnSlider;
- (void)SetResortFlag:(int)resortFlag withval:(BOOL)val;
- (void)SetSearchProgress:(float)fraction label:(NSString *)label;
- (void)SetSearchProgress:(float)fraction label:(NSString *)label pluginId:(NSString *)pid;
- (void)ReloadResults;
- (void)ReloadAll;
- (void)ClearSearchAll;
- (NSString *)TextWithoutCharBeforeCursor:(NSString *)cur;
- (void)LayoutBackspaceButton;
- (void)BackspacePressed;
- (NSMutableArray *)SRArray:(int)section;
- (int)LogicalSection:(NSInteger)tableSection;
- (void)OpenConfigUrl:(NSURLRequest *)openConfigUrl;
- (void)OpenHintUrl:(NSURLRequest *)openHintUrl;
- (void)OpenFBWallUrl:(NSURLRequest *)openFBWallUrl;
- (void)ShutDownRest:(NSNumber *)shutDownRest;
- (void)ResetupVideoView;
- (BOOL)HasVideos;
- (void)startAni;
- (void)stopAni;
- (void)LayoutPanels;

// panels of the dead web back-end: kept as inert hooks so the original call sites stay intact
- (void)SetWebViewsBlack;
- (void)InitHelpPic;
- (id)GetFirstVideo;
- (id)GetSecSvr;
- (void)RCSendVolume;
@end
