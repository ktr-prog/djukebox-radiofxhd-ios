// KioskHelper : NSObject -- forwarders into the KioskView (recovered)
#import <Foundation/Foundation.h>

@interface KioskHelper : NSObject
- (void)StopOverviewTimer;
- (void)SyncSVEwithUserdef;
- (void)SetRadioAniVar:(int)v;
- (void)RefreshSettings;
- (BOOL)IsThreadRunning;
- (void)StartThread;
- (void)CardReaderOff;
- (void)StartFirstFolderSong:(id)folder;
- (BOOL)IsGLViewShowingChannelView;
- (BOOL)IsPlayingClips;
- (long long)GetSelectedFolderid;
- (int)GetTimeActSongPlayed;
- (void)StopPlayers;
- (void)SetWdrPlayerVolume:(float)v;
- (void)ReStartIfNeeded;
- (void)ExternDraw:(int)v;
- (void)FlushGLForBackground;
- (void)ResetTACTime:(double)t;
- (BOOL)GetCancelCopy;
@end
