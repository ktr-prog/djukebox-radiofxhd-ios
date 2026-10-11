// GLView_Backend.m -- category GLView (Backend): remote/online glue of the original.
// The Tobit servers are gone; every path below stays reachable in code but is inert at
// runtime (no server entry, no EPG, no advertising, no card reader), see DEVIATIONS.md.
#import "GLView.h"
#import "Globals.h"
#import "KioskView.h"
#import "KeyboardView.h"
#import "DBOperations.h"
#import "ClipObject.h"
#import "ServerComm.h"
#import "ServerEntry.h"
#import "RadioAppDelegate.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@protocol RfxChannelInfo2
- (int)_id;
@end

@implementation GLView (Backend)

#pragma mark - "not connected" screen

- (void)AddDisconnView:(float)alpha {
    if (m_notconview != nil) return;
    BOOL ipad = [DEL m_isipad];
    m_notconview = [[UIImageView alloc] initWithFrame:
        CGRectMake(0.0f, 0.0f, [self frame].size.width, [self frame].size.height + (ipad ? 126.0f : 90.0f))];
    [m_notconview setAlpha:alpha];
    [m_notconview setImage:[DEL NonCachedImage:ipad ? @"djukeboxfx-startscreen-Landscape"
                                                      : @"Default_djukeboxiphone_ver"]];
    [self insertSubview:m_notconview belowSubview:[self GetRegister0]];
    [m_notconview release];
    [m_parent SendCDsToBackGround];
}

- (void)ShowDisconnectedPicture:(NSNumber *)show {
    float target;
    if ([show intValue] != 0) {
        [self AddDisconnView:0.0f];
        [self SetRegisterToSync:NO];
        target = 1.0f;
    } else {
        if (m_notconview == nil) return;
        target = 0.0f;
    }
    [UIView beginAnimations:@"discon_ani1" context:nil];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(ShowDisconPicAniFinished)];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.3];
    if (m_notconview != nil) [m_notconview setAlpha:target];
    [UIView commitAnimations];
}

- (void)ShowDisconPicAniFinished {
    if (m_notconview == nil) return;
    if ([m_notconview alpha] >= 0.5f) return;
    [m_notconview removeFromSuperview];
    m_notconview = nil;
}

- (void)InsertIntoRemoteQueue:(int)a withpoint:(CGPoint)point witharg1:(long long)arg1 witharg2:(int)arg2
                     witharg3:(int)arg3 withleaveoutclient:(long)leaveout witharg4:(int)arg4 {
    [m_parent InsertIntoRemoteQueue:a withpoint:point witharg1:arg1 witharg2:arg2
                           witharg3:arg3 withleaveoutclient:leaveout witharg4:arg4];
}

#pragma mark - advertising ticker

- (void)AdvertTimerFunc {
    [self setM_advertinittime:-1.0];
    if ([[m_parent m_sve] reserved_i1] > 0) {
        [self performSelector:@selector(AdvertTimerFuncDelayed) withObject:nil afterDelay:0.01];
        return;
    }
    if ([[m_parent m_sve] adverttexttime] < 1) return;
    if ([[DEL m_advertisingtexts] count] == 0) return;
    [self performSelector:@selector(AdvertTimerFuncDelayed) withObject:nil afterDelay:0.01];
}

- (void)AdvertTimerFuncDelayed {
    if (!([[m_parent m_sve] reserved_i1] > 0)) {
        if ([[m_parent m_sve] adverttexttime] < 1) return;
        if ([[DEL m_advertisingtexts] count] == 0) return;
    }
    if ([self m_autospin]) {
        [self performSelector:@selector(AdvertTimerFuncDelayed) withObject:nil afterDelay:2.0];
    } else if (![m_searchview m_keyboardshown]) {
        [m_parent performSelector:@selector(StartTPAni:) withObject:nil afterDelay:0.01];
    } else {
        [self RestartAdvertTimer];
    }
}

#pragma mark - servers / channels

- (void)CheckChannelsInRondell {
    NSArray *infos = [DEL GetChannelInfos];
    NSMutableArray *clips = [[NSMutableArray alloc] init];
    for (unsigned i = 0; i < [infos count]; i++) {
        id<RfxChannelInfo2> ci = [infos objectAtIndex:i];
        ClipObject *c = [[ClipObject alloc] init];
        [c setID:[ci _id]];
        [c setM_folderid:-33];
        [c setM_serverid:[[m_parent m_sve] serverid]];
        [clips addObject:c];
        [c release];
    }
    [self GetArrayLock:NO];
    [m_origarray removeAllObjects];
    [m_origarray addObjectsFromArray:clips];
    [[self m_tilearray] removeAllObjects];
    [[self m_tilearray] addObjectsFromArray:clips];
    [m_arraylock unlock];
    [self ReInitThread];
    [clips release];
}

- (void)ReloadSecSvrTable { [[m_searchview GetSecSvr] ReloadTable]; }

- (void)CheckToStartServerConnection {
    [self performSelector:@selector(CheckForNewChoosenServer) withObject:nil afterDelay:0];
}

- (void)CheckForNewChoosenServer {
    ServerEntry *sve = [[DEL GetServerComm] GetChoosenRfxServer:[m_parent GetRCConDeviceID]];
    if (sve == nil) return;
    [m_parent setM_sve:sve];
    [sve release];
    [m_parent FolderTimerfunc:nil];
    [m_parent StartThread];
}

- (void)CheckToStartServerDialog { }

- (int)GetlastplayedChannelindex {
    NSArray *infos = [DEL GetChannelInfos];
    for (unsigned i = 0; i < [infos count]; i++)
        if ([(id<RfxChannelInfo2>)[infos objectAtIndex:i] _id] == m_lastplayedchannelid) return (int)i;
    return 0;
}

- (void)MoveToActiveChannel {
    NSArray *infos = [DEL GetChannelInfos];
    for (unsigned i = 0; i < [infos count]; i++) {
        if ([DEL m_lastchannelid] == [(id<RfxChannelInfo2>)[infos objectAtIndex:i] _id]) {
            [self SpinAutomaticToClip:nil orIndex:(int)i];
            return;
        }
    }
}

- (BOOL)IsEPGChannel:(int)channel {
    NSRange r = [channelswithepg rangeOfString:[NSString stringWithFormat:@",%i,", channel]];
    return r.location != NSNotFound;
}

#pragma mark - EPG / stream meta notifications

- (void)EPGNowNoti:(NSNotification *)noti {
    if ([self m_selectedfolderid] != -33) return;
    [self performSelectorOnMainThread:@selector(EPGNowNotiInMainThread:) withObject:[noti object] waitUntilDone:NO];
}

- (void)EPGNowNotiInMainThread:(id)obj {
    for (int i = 0; ; i++) {
        if (![DEL m_switching] && [self m_fingersonscreen] <= 0 && [self m_radioanivar] == 0) break;
        if ([DEL g_end] || (gv_kioskflag & 0xff)) return;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, 0);
        if (i > 0xc8 - 1) break;
    }
    [m_deletetexturelock lock];
    [m_deletetexqueue addObject:obj];
    [m_deletetexturelock unlock];
    [self ReInitThread];
}

- (void)NewMetaTitle:(NSNotification *)noti {
    if (m_lastmetatitle != nil) {
        [m_lastmetatitle release];
        m_lastmetatitle = nil;
    }
    id o = [noti object];
    if (o == nil) return;
    m_lastmetatitle = [[NSString stringWithFormat:@"%@", o] retain];
}

- (void)NewMetaInterpret:(NSNotification *)noti {
    if (m_lastmetainterpret != nil) {
        [m_lastmetainterpret release];
        m_lastmetainterpret = nil;
    }
    id o = [noti object];
    if (o != nil) m_lastmetainterpret = [[NSString stringWithFormat:@"%@", o] retain];
    if ([self m_selectedfolderid] != -33) return;
    NSString *key = [NSString stringWithFormat:@"%i_picx", [DEL m_lastchannelid]];
    UIImage *pic = nil;
    if (m_lastmetainterpret != nil && [m_lastmetainterpret length] != 0 &&
        m_lastmetatitle != nil && [m_lastmetatitle length] != 0)
        pic = [m_parent GetSongPictureFor:m_lastmetatitle withinterpret:m_lastmetainterpret];
    if (pic != nil) [[m_parent m_nowdict] setObject:pic forKey:key];
    else            [[m_parent m_nowdict] removeObjectForKey:key];
    [self performSelectorOnMainThread:@selector(EPGNowNotiInMainThread:)
                           withObject:[NSNumber numberWithInt:[DEL m_lastchannelid]] waitUntilDone:NO];
}

- (void)BrandingTimerFunc:(NSTimer *)t {
    if (m_brandingpictimer != nil) {
        [m_brandingpictimer invalidate];
        m_brandingpictimer = nil;
    }
    [m_parent SpinToBrandingPic];
}

- (void)ReloadBrandingInMT {
    [self GetArrayLock:YES];
    ClipObject *c = [[ClipObject alloc] init];
    [c setID:-5];
    [c setM_folderid:[self m_selectedfolderid]];
    [c setM_serverid:[self m_selectedserverid]];
    [cache removeObjectwithkey:[DEL CreateTextureKey:c]];
    [c release];
    [m_arraylock unlock];
    [self ReInitThread];
}

#pragma mark - card reader (pay-per-song kiosk)

- (void)NewCard:(NSNotification *)n { }
- (void)CardRemoved:(NSNotification *)n { }
- (void)CardFound:(NSNotification *)n {
    if (m_sarstatus != 1) return;
    if ([self m_newcardfound] != nil) return;
    [self setM_newcardfound:[NSString stringWithFormat:@"%@", [n object]]];
}

#pragma mark - spotify (scrapped beta feature)

- (void)SpotifyPicSaved:(NSNotification *)n {
    NSDictionary *info = [n object];
    if (info == nil) return;
    NSString *sid = [info objectForKey:@"sp_id"];
    NSString *fid = [info objectForKey:@"sp_fid"];
    DBOperations *db = [[DBOperations alloc] init];
    [DEL LockDB:YES];
    ClipObject *clip = [db GetClipObjectForTrackURI:sid withfolderuri:fid];
    [DEL UnlockDB];
    [db release];
    [info release];
    if (clip == nil) return;
    [self GetArrayLock:YES];
    [cache removeObjectwithkey:[DEL CreateTextureKey:clip]];
    [m_arraylock unlock];
    [self ReInitThread];
    [clip release];
}

- (void)DeleteSpotifySong:(NSNotification *)n {
    NSDictionary *info = [n object];
    if (info == nil) return;
    NSString *sid = [info objectForKey:@"sp_id"];
    NSString *fid = [info objectForKey:@"sp_fid"];
    ClipObject *c = [[ClipObject alloc] init];
    [c setM_folderid:-66];
    [c setM_spotifyid:sid];
    [c setM_spotifyfolderid:fid];
    [c setM_serverid:[[m_parent m_sve] serverid]];
    if ([m_parent spotifyIDsMatch:[self m_selectedspotifyfolderid] withsecondid:fid])
        [self DeleteSongsWithFolder:nil justSingleSong:c];
    [c release];
    [info release];
}

- (void)ForwardHelppicAni { [m_parent StartHelpPictureAni]; }

@end
