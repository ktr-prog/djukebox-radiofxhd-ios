// GLView_Prescroller.m -- category GLView (Prescroller): background thread that renders
// one black-and-white cover per folder for the overview grid (MTScroller) and keeps the
// result in m_prescrollerdict, announcing each folder with "MsgOverviewNext".
#import "GLView.h"
#import "Globals.h"
#import "KioskView.h"
#import "DBOperations.h"
#import "ClipObject.h"
#import "FolderObject.h"
#import "ScrollerDictObject.h"
#import "RadioAppDelegate.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@implementation GLView (Prescroller)

- (void)PrescrollerThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [DEL LockDB:NO];
    DBOperations *db = [[DBOperations alloc] init];
    NSMutableArray *folders = [db GetFolders:[m_parent m_sve] onlyexclude:NO checkempty:YES
                                  withLimits:YES withremotefolders:YES join:YES];
    NSMutableArray *clips = [[NSMutableArray alloc] init];     // one song per album
    NSMutableArray *albums = [[NSMutableArray alloc] init];

    if ([folders count] == 0) {
        [DEL UnlockDB];
    } else {
        for (unsigned fi = 0; fi < [folders count]; fi++) {
            if ([DEL g_end] || (gv_kioskflag & 0xff)) {
                [DEL UnlockDB];
                break;
            }
            [clips removeAllObjects];
            [albums removeAllObjects];
            FolderObject *folder = [folders objectAtIndex:fi];
            if ([db HasFolderSongs:folder]) {
                NSMutableArray *songs = [db GetSongsForFolder:folder withjoin:YES];
                [DEL UnlockDB];
                int seconds = 0;
                for (unsigned i = 0; i < [songs count]; i++) {
                    ClipObject *song = [songs objectAtIndex:i];
                    int dur = [song m_duration];
                    NSNumber *albumNum = [NSNumber numberWithLongLong:[song m_albumid]];
                    seconds += dur;
                    if ([song m_albumid] == 0 || ![self IsInAlbumArray:albumNum witharray:albums]) {
                        [clips addObject:song];
                        [albums addObject:albumNum];
                    }
                }
                int idx = 0;
                if ([songs count] <= 14) idx = (int)([clips count] >> 1);
                if ([folder folderid] == -33) idx = 0;
                ClipObject *clip = [clips objectAtIndex:idx];

                UIImage *naked;
                FolderObject *usedFolder = folder;
                BOOL ownFolder = NO;
                if ([clip m_folderid] == 1 || [clip m_folderid] == 3 || [clip m_folderid] == -33) {
                    // internet-radio / special folders: use the channel logo
                    naked = nil;
                    if ([clip ID] != -1)
                        naked = [self CreateNakedImage:nil withNumber:0 withClipArray:nil withclipObject:clip
                                       withtexturesize:gv_texsize onlychannellogo:YES borderalreadypresent:NO];
                } else {
                    if ([clip m_folderid] != [folder folderid]) {
                        [DEL LockDB:NO];
                        usedFolder = [db GetFolderForID:[clip m_folderid] withserverid:[clip m_serverid]
                                             withipodid:[clip m_ipodid] withspotifyid:[clip m_spotifyfolderid]];
                        [DEL UnlockDB];
                        ownFolder = YES;
                    }
                    NSString *serverdir = [NSString stringWithFormat:@"%@%@/",
                        [DEL CreateServerDir:[m_parent m_sve] withfolderobject:usedFolder],
                        [DEL Buildfoldername:usedFolder]];
                    [DEL BuildAndCheckFilePathes:clip withfm:[NSFileManager defaultManager]
                                    withserverdir:serverdir withCheck:YES];
                    naked = nil;
                    if ([clip ID] != -1)
                        naked = [self CreateNakedImage:[m_parent GetSongImage:[clip m_picturepath] withclipobject:clip]
                                           withNumber:0 withClipArray:nil withclipObject:nil
                                       withtexturesize:gv_texsize onlychannellogo:NO borderalreadypresent:NO];
                }
                UIImage *bw = [m_parent BlackAndWhitePicture:naked withfolderid:[usedFolder folderid]];
                if (ownFolder) [usedFolder release];

                ScrollerDictObject *sdo = [[ScrollerDictObject alloc] init];
                [sdo SetPic:bw];
                [sdo setM_iscolorpic:NO];
                [sdo setMidindex:idx];
                [sdo setMidid:[clip ID]];
                [sdo setMidipodid:[clip m_ipodid]];
                [sdo setMidspotifyid:([clip m_spotifyid] == nil) ? nil
                                      : [NSString stringWithFormat:@"%@", [clip m_spotifyid]]];
                [sdo setNumsongs:(int)[songs count]];
                if ([folder folderid] != -33 && [DEL IsBrandingPicturePresent]) {
                    [sdo setNumsongs:[sdo numsongs] - 1];
                    if ([sdo numsongs] <= 0) [sdo setNumsongs:1];
                }
                [sdo setSeconds:seconds];
                [self LockSDC];
                [m_prescrollerdict setObject:sdo forKey:[DEL CreatePrescrollerKey:[folder folderid]
                                                                   withserverid:[folder serverid]
                                                                    withipodid:[folder ipodid]
                                                                   withspotifyid:[folder spotifyfolderid]]];
                [self UnlockSDC];
                [sdo release];

                NSString *sp = ([folder spotifyfolderid] == nil) ? @""
                                : [NSString stringWithFormat:@"%@", [folder spotifyfolderid]];
                NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithLongLong:[folder folderid]], @"ffolder",
                    [NSNumber numberWithInt:[folder serverid]], @"fserver",
                    [NSNumber numberWithLongLong:[folder ipodid]], @"fipod",
                    sp, @"fspotify", nil];
                [[NSNotificationCenter defaultCenter] postNotification:
                    [NSNotification notificationWithName:@"MsgOverviewNext" object:info]];
                [songs release];
                if (fi < [folders count] - 1) [DEL LockDB:YES];
            }
        }
    }
    [db release];
    [clips release];
    [albums release];
    [folders release];
    m_prescrollerthreaddone = YES;
    [pool release];
}

@end
