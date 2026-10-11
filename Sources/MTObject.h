// MTObject : NSObject -- recovered (instance size 185 on armv7)
// One tile (folder / mixtape) in the "overview" grid managed by MTScroller.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class KioskView, MTScroller;

@interface MTObject : NSObject {
    long long m_id;
    int m_sid;
    UILabel *m_textlabel;
    UILabel *m_timelabel;
    int m_reddotcount;
    UIImageView *m_mainimgv;
    UIImageView *m_borderimgv;
    UIImageView *m_reddotimgv;
    int m_borderindex;
    KioskView *m_pkiosk;
    CGRect m_midrecthor;
    CGRect m_midrectver;
    CGRect m_midrecthorradio;
    CGRect m_midrectverradio;
    BOOL m_deleteflag;
    NSString *m_foldername;
    long long m_lastsongid;
    long long m_lastipodid;
    int m_reddotsize;
    int m_duration;
    int m_ownindex;
    MTScroller *m_pscroller;
    BOOL m_addedtoview;
    UIImage *m_placeholderpointer;
    BOOL m_observeradded;
    long long m_ipodid;
    BOOL m_iscolorpic;
    NSString *m_spotifyfolderid;
    NSString *m_lastspotifyid;
    BOOL m_renew;
}
@property (nonatomic, retain) NSString *m_lastspotifyid;
@property (nonatomic, retain) NSString *m_spotifyfolderid;
@property (assign) BOOL m_iscolorpic;
@property (assign) long long m_lastipodid;
@property (assign) int m_ownindex;
@property (assign) int m_duration;
@property (assign) int m_reddotsize;
@property (assign) long long m_lastsongid;
@property (assign) BOOL m_deleteflag;
@property (assign) int m_borderindex;
@property (assign) BOOL m_renew;
@property (assign) int m_reddotcount;
@property (assign) long long m_ipodid;
@property (assign) int m_sid;
@property (assign) long long m_id;
- (void)SetPlaceholderpicpointer:(id)placeholderpicpointer;
- (void)SetScrollerPointer:(id)scrollerPointer;
- (void)ReplaceMainImgwith:(id)replaceMainImgwith;
- (void)UpdateCounts:(id)counts;
- (void)CalcFrameForRedDot;
- (id)GetMainImageView;
- (id)GetRedDotImageView;
- (void)PlacePicInMid:(int)placePicInMid withview:(id)view;
- (void)SetLastID:(long long)lastID withipodid:(long long)ipodid withFlag:(BOOL)flag withspotifyid:(id)spotifyid;
- (void)CheckBlackAndWhite;
- (void)Reloadlabel;
- (void)SetFoldername:(id)foldername;
- (void)RemovePics;
- (void)SetAlpha:(float)alpha;
- (void)SetAlphaMainImg:(float)alphaMainImg;
- (void)SetAlphaText:(float)alphaText;
- (void)SetAlphaBorderAndRedDot:(float)alphaBorderAndRedDot;
- (int)compareNames:(id)compareNames;
- (id)GetText;
- (void)SetUp:(id)up withSDO:(id)sDO;
- (void)ResizeBorderFrame:(float)resizeBorderFrame fromImgv:(id)imgv;
- (void)SetFrame:(int)frame;
- (CGRect)CalcBorderFrameFromImgFrame:(CGRect)calcBorderFrameFromImgFrame withSize:(CGSize)size adddist:(float)adddist;
- (void)SetKioskPointer:(id)kioskPointer;
- (void)OverviewNext:(id)overviewNext;
- (void)OverviewNextMT:(id)overviewNextMT;
- (void)SetTimeLabelText:(id)timeLabelText;
- (void)CreateBorderImage;
- (void)AddToView:(id)toView;
- (CGRect)GetFrameForOverViewLabelTime:(int)frameForOverViewLabelTime withsize:(CGSize)size;
- (CGRect)GetFrameForOverViewLabel:(int)frameForOverViewLabel withsize:(CGSize)size;
- (CGRect)GetFrameForOverViewFolder:(int)frameForOverViewFolder withsize:(CGSize)size;
- (CGRect)GetPicFrame;
@end
