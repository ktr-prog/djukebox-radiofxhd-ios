// GLView_Delete.m -- category GLView (Delete): removing songs/folders from disk and from the
// flow, renaming a folder on disk, and two small geometry helpers of the radio-channel layer.
#import "GLView.h"
#import "KioskView.h"
#import "DBOperations.h"
#import "DataCache.h"
#import "ClipObject.h"
#import "FolderObject.h"
#import "RadioAppDelegate.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@protocol RfxChannelInfo
- (int)_id;
@end

@implementation GLView (Delete)

// Removes the (now empty) server folder on disk if it holds no file any more.
- (void)CheckToDeleteFolder:(FolderObject *)folder {
    if (folder == nil) return;
    if ([folder folderid] == -66) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [NSString stringWithFormat:@"%@%@/",
        [DEL CreateServerDir:[m_parent m_sve] withfolderobject:folder],
        [DEL Buildfoldername:folder]];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:dir];
    if (![fm fileExistsAtPath:dir]) return;
    if ([en nextObject] != nil) return;
    [fm removeItemAtPath:dir error:nil];
}

// Derives the folder from the second-to-last component of the picture path (".../<id>-<name>/pic.jpg").
- (void)CheckToDeleteFolderFromPicPath:(ClipObject *)clip {
    if ([clip m_folderid] == -33) return;
    if ([clip m_folderid] == -33) return;
    NSArray *parts = [[clip m_picturepath] componentsSeparatedByString:@"/"];
    if (parts == nil || [parts count] < 2) return;
    FolderObject *folder = [[FolderObject alloc] init];
    NSString *last = [parts objectAtIndex:[parts count] - 2];
    [folder setFolderid:[m_parent GetIDFromNSString:last withisipodstring:NO]];
    if ([folder folderid] != -1) {
        [folder setFoldername:[last substringFromIndex:
            [[NSString stringWithFormat:@"%lld", [folder folderid]] length] + 1]];
        [folder setServerid:[clip m_serverid]];
        [self CheckToDeleteFolder:folder];
    }
    [folder release];
}

- (void)RenameFolder:(NSNumber *)folderNum {
    long long fid = [folderNum longLongValue];
    NSFileManager *fm = [NSFileManager defaultManager];
    [DEL LockDB:NO];
    DBOperations *db = [[DBOperations alloc] init];
    FolderObject *folder = [db GetFolderForID:fid withserverid:[[m_parent m_sve] serverid]
                                   withipodid:0 withspotifyid:nil];
    [db release];
    [DEL UnlockDB];
    if (folder == nil) return;
    NSString *dir = [NSString stringWithFormat:@"%@%@/",
        [DEL CreateServerDir:[m_parent m_sve] withfolderobject:folder],
        [DEL Buildfoldername:folder]];
    [folder release];

    [m_arraylock lock];
    for (unsigned i = 0; i < [[self m_tilearray] count]; i++) {
        ClipObject *clip = [[self m_tilearray] objectAtIndex:i];
        if ([clip m_folderid] != fid) continue;
        if ([clip m_tracks] == nil) {
            [DEL BuildAndCheckFilePathes:clip withfm:fm withserverdir:dir withCheck:YES];
        } else {
            for (unsigned k = 0; k < [[clip m_tracks] count]; k++) {
                ClipObject *t = [[clip m_tracks] objectAtIndex:k];
                if ([t m_folderid] == fid)
                    [DEL BuildAndCheckFilePathes:t withfm:fm withserverdir:dir withCheck:YES];
                if (k == 0)
                    [clip setM_picturepath:[NSString stringWithFormat:@"%@", [t m_picturepath]]];
            }
        }
    }
    for (unsigned i = 0; i < [m_origarray count]; i++) {
        ClipObject *clip = [m_origarray objectAtIndex:i];
        if ([clip m_folderid] == fid)
            [DEL BuildAndCheckFilePathes:clip withfm:fm withserverdir:dir withCheck:YES];
    }
    [m_arraylock unlock];
    [[NSNotificationCenter defaultCenter] postNotification:
        [NSNotification notificationWithName:@"MsgOVFolderrenamed" object:nil]];
}

// Does `c` belong to the song/folder that is being deleted?
- (BOOL)deleteMatches:(ClipObject *)c single:(ClipObject *)single folder:(FolderObject *)folder {
    if (single != nil) {
        if ([single m_folderid] != -66) return [single ID] == [c ID];
        return [m_parent spotifyIDsMatch:[single m_spotifyid] withsecondid:[c m_spotifyid]];
    }
    if (folder != nil) {
        if ([folder folderid] != -66) return [c m_folderid] == [folder folderid];
        return [m_parent spotifyIDsMatch:[folder spotifyfolderid] withsecondid:[c m_spotifyfolderid]];
    }
    return NO;
}

// Deletes the files of a clip (or queues it when it is still in the play list).
- (void)deleteFilesOfClip:(ClipObject *)c fm:(NSFileManager *)fm {
    NSError *err = nil;
    if (![m_parent IsClipInList:c]) {
        if ([c m_filepath] != nil && [c m_folderid] != -66)
            [fm removeItemAtPath:[c m_filepath] error:&err];
        if ([c m_picturepath] != nil)
            [fm removeItemAtPath:[c m_picturepath] error:&err];
        NSString *small = [DEL BuildSmallPicpath:[c m_picturepath]];
        if (small != nil) [fm removeItemAtPath:small error:&err];
    } else {
        [m_clipstodelete addObject:c];
    }
}

- (void)DeleteSongsWithFolder:(FolderObject *)songsWithFolder justSingleSong:(ClipObject *)justSingleSong {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (int i = (int)[[self m_tilearray] count] - 1; i >= 0; i--) {
        ClipObject *clip = [[self m_tilearray] objectAtIndex:i];
        if ([clip m_tracks] == nil) {
            if ([self deleteMatches:clip single:justSingleSong folder:songsWithFolder]) {
                [self deleteFilesOfClip:clip fm:fm];
                [self GetArrayLock:YES];
                [[self m_tilearray] removeObjectAtIndex:i];
                [cache removeObjectwithkey:[DEL CreateTextureKey:clip]];
                [m_origarray removeObject:clip];
                [m_arraylock unlock];
            }
            continue;
        }
        // stacked album: remove the matching tracks
        for (int k = (int)[[clip m_tracks] count] - 1; k >= 0; k--) {
            ClipObject *t = [[clip m_tracks] objectAtIndex:k];
            if ([self deleteMatches:t single:justSingleSong folder:songsWithFolder]) {
                [self deleteFilesOfClip:t fm:fm];
                [m_origarray removeObject:[[clip m_tracks] objectAtIndex:k]];
                [[clip m_tracks] removeObjectAtIndex:k];
                [self GetArrayLock:YES];
                [cache removeObjectwithkey:[DEL CreateTextureKey:clip]];
                [m_arraylock unlock];
                if ([self m_specialtexture] != nil) {
                    [[self m_specialtexture] release];
                    [self setM_specialtexture:nil];
                }
            }
        }
        if ([[clip m_tracks] count] == 0) {
            [self GetArrayLock:YES];
            [[self m_tilearray] removeObjectAtIndex:i];
            [cache removeObjectwithkey:[DEL CreateTextureKey:clip]];
            [m_origarray removeObject:clip];
            [m_arraylock unlock];
            continue;
        }
        // is the clip's own song still one of the tracks?
        BOOL found = NO;
        for (unsigned j = 0; j < [[clip m_tracks] count]; j++)
            if ([[[clip m_tracks] objectAtIndex:j] ID] == [clip ID]) { found = YES; break; }
        if (!found) {
            [self GetArrayLock:NO];
            [cache removeObjectwithkey:[DEL CreateTextureKey:clip]];
            ClipObject *t0 = [[clip m_tracks] objectAtIndex:0];
            [cache removeObjectwithkey:[DEL CreateTextureKey:t0]];
            [m_arraylock unlock];
            [clip setID:[t0 ID]];
            [clip setM_picturepath:[NSString stringWithFormat:@"%@", [t0 m_picturepath]]];
        }
        if ([[clip m_tracks] count] == 1) {
            // only one track left: the album turns back into a plain song
            ClipObject *t = [[clip m_tracks] objectAtIndex:0];
            [clip setM_folderid:[t m_folderid]];
            if ([t m_spotifyfolderid] != nil)
                [clip setM_spotifyfolderid:[NSString stringWithFormat:@"%@", [t m_spotifyfolderid]]];
            if ([t m_spotifyid] != nil)
                [clip setM_spotifyid:[NSString stringWithFormat:@"%@", [t m_spotifyid]]];
            [clip setM_albumid:[t m_albumid]];
            [clip setM_picturepath:[NSString stringWithFormat:@"%@", [t m_picturepath]]];
            [clip setM_filepath:[NSString stringWithFormat:@"%@", [t m_filepath]]];
            [clip setM_title:[NSString stringWithFormat:@"%@", [t m_title]]];
            [clip setM_duration:[t m_duration]];
            [clip setID:[t ID]];
            if ([clip m_tracks] != nil) {
                [[clip m_tracks] release];
                [clip setM_tracks:nil];
            }
            if (i == (int)offset)
                [m_titlelabel setText:[NSString stringWithFormat:@"%@", [clip m_title]]];
        }
    }

    if ([[self m_tilearray] count] == 0) {
        offset = 0;
    } else if (offset > (double)([[self m_tilearray] count] - 1)) {
        offset = (double)([[self m_tilearray] count] - 1);
    }
    if ([self m_pinchstatus] == 0) {
        [self performSelectorOnMainThread:@selector(drawView) withObject:nil waitUntilDone:YES];
        [self ReInitThread];
    }

    if (justSingleSong == nil) {
        if (songsWithFolder != nil) {
            [DEL LockDB:YES];
            DBOperations *db = [[DBOperations alloc] init];
            NSMutableArray *songs = [db GetSongsForFolder:songsWithFolder withjoin:NO];
            [db release];
            [DEL UnlockDB];
            for (unsigned i = 0; i < [songs count]; i++) {
                ClipObject *s = [songs objectAtIndex:i];
                if (![m_parent IsClipInList:s]) {
                    NSString *dir = [NSString stringWithFormat:@"%@%@/",
                        [DEL CreateServerDir:[m_parent m_sve] withfolderobject:songsWithFolder],
                        [DEL Buildfoldername:songsWithFolder]];
                    [DEL BuildAndCheckFilePathes:s withfm:fm withserverdir:dir withCheck:YES];
                    if ([s m_filepath] != nil && [s m_folderid] != -66)
                        [fm removeItemAtPath:[s m_filepath] error:nil];
                    if ([s m_picturepath] != nil)
                        [fm removeItemAtPath:[s m_picturepath] error:nil];
                    NSString *small = [DEL BuildSmallPicpath:[s m_picturepath]];
                    if (small != nil) [fm removeItemAtPath:small error:nil];
                } else {
                    [m_clipstodelete addObject:s];
                }
            }
            [songs release];
            [self CheckToDeleteFolder:songsWithFolder];
        }
    } else {
        if (![m_parent IsClipInList:justSingleSong]) {
            if ([justSingleSong m_filepath] != nil && [justSingleSong m_folderid] != -66)
                [fm removeItemAtPath:[justSingleSong m_filepath] error:nil];
            if ([justSingleSong m_picturepath] != nil)
                [fm removeItemAtPath:[justSingleSong m_picturepath] error:nil];
            NSString *small = [DEL BuildSmallPicpath:[justSingleSong m_picturepath]];
            if (small != nil) [fm removeItemAtPath:small error:nil];
        } else {
            [m_clipstodelete addObject:justSingleSong];
        }
        if ([justSingleSong m_folderid] != -66)
            [self CheckToDeleteFolderFromPicPath:justSingleSong];
    }

    if (m_draggingpicture) {
        BOOL remove = NO;
        if (songsWithFolder != nil &&
            [songsWithFolder folderid] == [m_draggingobject m_folderid] &&
            [m_parent spotifyIDsMatch:[songsWithFolder spotifyfolderid]
                         withsecondid:[m_draggingobject m_spotifyfolderid]])
            remove = YES;
        else if (justSingleSong != nil &&
                 [justSingleSong m_folderid] == [m_draggingobject m_folderid] &&
                 [m_parent spotifyIDsMatch:[justSingleSong m_spotifyfolderid]
                              withsecondid:[m_draggingobject m_spotifyfolderid]])
            remove = YES;
        if (remove)
            [self performSelectorOnMainThread:@selector(RemoveDraggingObject) withObject:nil waitUntilDone:NO];
    }
    [self ChooseOtherMixtape:[NSNumber numberWithLongLong:[songsWithFolder folderid]]];
}

#pragma mark - radio layer geometry

// Keeps the x position of a tile inside the visible range when it is far back (z > 11.9).
- (void)RestrictXValue:(float *)x withzintern:(float)zintern {
    if (((double)zintern + -0.1) <= 11.8) return;
    BOOL ipad = [DEL m_isipad];
    double t = ((double)zintern + -11.8) / (ipad ? 2.5 : 2.75);
    float ft = (float)t;
    double b = ipad ? 3.799999952316284 : 2.799999952316284;
    float limit = (float)(b + (1.0 - (double)ft) * (7.0 - b));
    float v = (*x < limit) ? *x : limit;
    double r = (double)v;
    if (r < -(double)limit) r = -(double)limit;
    *x = (float)r;
}

// Moves the active channel's tile while the radio "slide" animation (m_radioanivar 0..100) runs.
- (void)CalcRadioAniValues:(float *)x withy:(float *)y withChannelinfo:(id)channelinfo {
    BOOL ipad = [DEL m_isipad];
    float A = ipad ? 2.5f : 2.75f;
    float B = ipad ? -1.12f : -2.2f;
    int cid = [(id<RfxChannelInfo>)channelinfo _id];
    if (m_radioanivar == 0) {
        if ([DEL m_lastchannelid] == cid) {
            *x = *x + A;
            *y = *y + B;
            return;
        }
    }
    if (m_radioanivar >= 1 && m_radioanivar <= 50) {
        if ([DEL m_oldlastchannelid] == cid) {
            float t = (float)((double)(50 - m_radioanivar) / 50.0);
            *y = *y + B * t;
            *x = *x + A * t;
            return;
        }
    }
    if (m_radioanivar >= 51 && m_radioanivar <= 100) {
        if ([DEL m_lastchannelid] == cid) {
            float t = (float)((double)(m_radioanivar - 50) / 50.0);
            *y = *y + B * t;
            *x = *x + A * t;
        }
    }
}

@end
