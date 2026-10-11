// KioskHelper -- decompiled from Radiofx_iPad.
// Spotify/airplay/remote-app forwarders are dropped (see DEVIATIONS.md).
#import "KioskHelper.h"
#import "KioskView.h"
#import "GLView.h"
#import "iPadMainVC.h"
#import "RadioAppDelegate.h"

#define KV ((KioskView *)[[(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] GetiPadMainVC] GetKioskView])

@implementation KioskHelper
- (void)StopOverviewTimer {
    [KV StopOverviewTimer];
}
- (void)SyncSVEwithUserdef {
    [KV SyncSVEwithUserdef];
}
- (void)SetRadioAniVar:(int)radioAniVar {
    [KV SetRadioAniVar:radioAniVar];
}
- (void)RefreshSettings {
    [KV RefreshSettings];
}
- (BOOL)IsThreadRunning {
    return [KV IsThreadRunning];
}
- (void)StartThread {
    [KV StartThread];
}
- (void)CardReaderOff {
    [KV CardReaderOff];
}
- (void)StartFirstFolderSong:(id)firstFolderSong {
    [KV StartFirstFolderSong:firstFolderSong];
}
- (BOOL)IsPlayingClips {
    return [KV IsPlayingClips];
}
- (long long)GetSelectedFolderid {
    return [KV GetSelectedFolderid];
}
- (int)GetTimeActSongPlayed {
    return [KV GetTimeActSongPlayed];
}
- (void)StopPlayers {
    [KV StopPlayers];
}
- (void)SetWdrPlayerVolume:(float)wdrPlayerVolume {
    [KV SetWdrPlayerVolume:wdrPlayerVolume];
}
- (void)ReStartIfNeeded {
    [KV ReStartIfNeeded];
}
- (void)FlushGLForBackground {
    [KV FlushGLForBackground];
}

- (void)ExternDraw:(int)externDraw {
    [KV ExternDraw:externDraw];
}
- (void)ResetTACTime:(double)tACTime {
    [KV ResetTACTime:tACTime];
}
- (BOOL)IsGLViewShowingChannelView {
    KioskView *kv = KV;
    if ([kv m_glv] == nil) return NO;
    return [[kv m_glv] IsShowingChannelView];
}
- (BOOL)GetCancelCopy {
    return [KV cancelcopy];
}
@end
