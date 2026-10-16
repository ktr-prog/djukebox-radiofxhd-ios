// DBOperations : NSObject  (recovered, instance size 9 on armv7)
// Wraps the local SQLite database Documents/Radio.db through FMDB.
//
// NOT ported (server / streaming / Spotify / EPG / remote-control parts of the original):
//   Spotify*, RemoteCtrl*, Channel*/EPG*/Genre*/Podcast* methods and the live radio (-33) folder.
#import <Foundation/Foundation.h>
#import "FMDatabase.h"
#import "FMResultSet.h"
#import "ClipObject.h"
#import "FolderObject.h"

@class ServerEntry;

@interface DBOperations : NSObject {
    FMDatabase *db;         // +4
    BOOL dbConnectionOK;    // +8
}
@property (nonatomic, retain) FMDatabase *db;

- (id)init;
- (BOOL)dbOpen;
- (void)dbClose;

// schema
- (BOOL)CreateDatabase;
- (void)CreateMixxtapeIndizes;
- (void)CreateMTTimesPlayedField;
- (void)CreateMTHideField;
- (void)CreateLimitField;
- (void)CreateSpotifyFields;
- (void)CreateJoinField;
- (void)CreateRCMessageField;
- (void)CleanDataBase;
- (void)CreateMTSearcKeyField;

// folders
- (NSMutableArray *)GetFolders:(ServerEntry *)server onlyexclude:(BOOL)onlyexclude checkempty:(BOOL)checkempty
                    withLimits:(BOOL)withLimits withremotefolders:(BOOL)remotefolders join:(BOOL)join;
- (FolderObject *)GetFolderForID:(long long)folderid withserverid:(int)serverid withipodid:(long long)ipodid withspotifyid:(NSString *)spotifyid;
- (NSString *)GetFoldername:(long long)folderid withserverid:(int)serverid withipodid:(long long)ipodid withspotifyfolderid:(NSString *)spotifyfolderid;
- (int)GetLastPlayedFolder:(int)serverid withspotifyfolderid:(NSString **)spotifyfolderid;
- (BOOL)SetFolderLastPlayed:(long long)folderid withServerID:(int)serverid withspotifyfolderid:(NSString *)spotifyfolderid;
- (BOOL)InsertFolder:(FolderObject *)folder;
- (long long)CreatePlaylistNamed:(NSString *)name withServerid:(int)serverid;
- (void)DeleteDemoFolder;
- (long long)MaxClipID;
- (long long)MaxFolderID;
- (long long)FolderIDForName:(NSString *)name serverid:(int)serverid;
- (BOOL)UpdateFolder:(FolderObject *)folder withServerid:(int)serverid;
- (BOOL)IsFolderEmpty:(FolderObject *)folder withServerID:(int)serverid;
- (BOOL)HasFolderSongs:(FolderObject *)folder;
- (NSString *)GetJoinedFolders:(long long)folderid withserverid:(int)serverid withjoin:(BOOL)join;
- (BOOL)SaveExcludefolders:(NSArray *)folders forServer:(ServerEntry *)server;
- (BOOL)DeleteMTFolder:(FolderObject *)folder withServerid:(int)serverid deleteFolderItself:(BOOL)deleteItself;
- (void)PostDeleteMTNotiInMainThread:(id)object;
- (BOOL)DeleteMTServerDB:(ServerEntry *)server;

// songs
- (NSMutableArray *)GetSongsForFolder:(FolderObject *)folder withjoin:(BOOL)join;
- (ClipObject *)GetSongWithID:(long long)songID withServerid:(int)serverid;
- (void)ReadCO:(ClipObject *)co withRSet:(FMResultSet *)rs;
- (BOOL)InsertClip:(ClipObject *)co withserverid:(int)serverid;
- (BOOL)IsSongPresent:(id)unused1 withSongname:(id)unused2 withfolderid:(long long)folderid withserverid:(int)serverid withID:(long long)songID;
- (BOOL)DeleteSongFromDB:(ClipObject *)co withServer:(ServerEntry *)server;
- (BOOL)DeleteAllSongsFromDB;
- (BOOL)DeleteDoubleEntries;
- (ClipObject *)FindInterpretAndSong:(ClipObject *)co withserverid:(int *)serverid;
- (int)GetCompleteSongCount;
- (int)GetNumSongsForFolderLimit10:(long long)folderid withServerid:(int)serverid;
- (int)GetNumMatchingEntries:(long long)folderid withServerid:(int)serverid withsearchstring:(NSString *)search
                  withipodid:(long long)ipodid withspotifyfolderid:(NSString *)spotifyfolderid;
- (int)CheckMatching:(NSString *)search withinterpret:(NSString *)interpret withtitle:(NSString *)title;

// play counts / hiding
- (NSMutableArray *)GetCharts;
- (BOOL)IncTimesPlayed:(ClipObject *)co;
- (void)ResetTimesPlayed;
- (void)HideTitle:(ClipObject *)co;
- (void)UndeleteTitle;

// radio channel table (only the count is needed by GetFolders)
- (int)GetNumChoosenChannels;
- (ClipObject *)GetClipObjectForTrackURI:(NSString *)trackuri withfolderuri:(NSString *)folderuri;
- (void)DeleteLegacyDemoRows;       // port addition
- (int)CountAllSongs;               // port addition
- (NSArray *)GetLibraryServerIDs;   // port addition: serverids used by the folders of the local library
@end
