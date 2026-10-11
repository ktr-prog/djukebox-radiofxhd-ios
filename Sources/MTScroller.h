// MTScroller : UIScrollView -- recovered (instance size 470 on armv7)
// The "overview" grid of folders / mixtapes that is opened with the pinch gesture.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class KioskView, MyGestureDelegate, MTObject;

@interface MTScroller : UIScrollView <UIGestureRecognizerDelegate> {
    KioskView *m_pkiosk;
    UITapGestureRecognizer *m_tapGestureRecognizer;
    UILongPressGestureRecognizer *m_lpGestureRecognizer;
    NSTimer *m_overviewtimer;
    BOOL m_isclosing;
    BOOL m_isinitialized;
    float m_volumepinch;
    UIImage *m_leftpart;
    UIImage *m_rightpart;
    UIImage *m_midpart;
    UIImage *m_leftpart_s;
    UIImage *m_rightpart_s;
    UIImage *m_midpart_s;
    int m_reddotsize;
    BOOL m_willplayradio;
    UIImageView *m_newimageview;
    int m_lastactiveradiochannel;
    BOOL m_picreplaced;
    NSMutableArray *m_mtobjects;
    MyGestureDelegate *m_deleg;
    UIImage *m_placeholderpic;
    BOOL m_deletedoverviewcausememwarning;
    BOOL m_isscrolling;
}
@property (assign) BOOL m_isscrolling;
@property (assign) BOOL m_deletedoverviewcausememwarning;
@property (assign) BOOL m_willplayradio;
@property (assign) int m_lastactiveradiochannel;
@property (assign) BOOL m_isclosing;
- (void)handleTap:(id)handleTap;
- (void)setAlpha2;
- (void)setAlpha1;
- (void)setAlpha0;
- (MTObject *)GetMTObject:(int)mTObject;
- (void)GotoFolderID:(int)gotoFolderID;
- (void)GotoFolder:(int)gotoFolder;
- (void)ResetOverviewAfterRfxCommercial;
- (int)GetIndexForID:(long long)indexForID withserverid:(int)serverid withipodid:(long long)ipodid;
- (void)ReSetup;
- (void)SetUpScroller:(id)upScroller;
- (void)SetFrames;
- (MTObject *)IsFolderInObjects:(id)folderInObjects;
- (void)StopOverviewTimer;
- (void)ExchangeAniFinished;
- (void)ExchangeChannelLogo:(id)exchangeChannelLogo;
- (void)RestartOverviewTimer;
- (void)RestartOverviewTimerWithTimeout:(double)restartOverviewTimerWithTimeout;
- (void)OverviewTimerFunc:(id)overviewTimerFunc;
- (void)SetRedDots:(id)redDots;
- (void)SetRedDot:(int)redDot withindex:(int)indexArg;
- (void)MTDeleted:(id)mTDeleted;
- (void)SomeFolderRenamed;
- (void)SetKioskVPointer:(id)kioskVPointer;
- (void)CheckIfFolderPresent:(id)ifFolderPresent;
- (NSMutableArray *)GetMTObjects;
- (void)ReInit;
- (void)DeleteClipObject:(id)clipObject;
- (void)deleteMTOswithSid:(int)mTOswithSid;
- (void)completeDelete;
- (void)FitScroller;
- (void)CalcContentsize:(CGSize)calcContentsize;
- (int)HasObject:(long long)object withserverid:(int)serverid;
- (void)SetPicreplaced;
- (int)GetMTCount;
@end

// tiny delegate that lets the tap recogniser coexist with the scroll view's own recognisers
@interface MyGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@end
