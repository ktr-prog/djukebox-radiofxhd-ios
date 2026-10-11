// Recovered from the -[DBOperations ...] methods (0x21e48 - 0x2c8c0 in the armv7 slice).
#import "DBOperations.h"
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import "NSString+RfxMatch.h"
#import "NSString+RegexCompat.h"
#import "ServerEntry.h"
#import "RadioAppDelegate.h"

@implementation DBOperations
@synthesize db;

#pragma mark - lifecycle

- (id)init {
    self = [super init];
    if (self) {
        NSString *home = [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] GetHomeDir];
        NSString *path = [[home stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"Radio.db"];
        db = [[FMDatabase alloc] initWithPath:path];
    }
    return self;
}

- (void)dealloc {
    if (db) { [db release]; db = nil; }
    [super dealloc];
}

- (BOOL)dbOpen {
    BOOL ok = [db open];
    if (ok)
        [db setShouldCacheStatements:NO];
    return ok;
}

- (void)dbClose {
    [db close];
}

#pragma mark - schema

- (BOOL)CreateDatabase {
    BOOL ok = NO;
    if ([self dbOpen]) {
        [db executeUpdate:@"CREATE TABLE Radio_Ticker (RealID integer NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE, TickerID integer ,Title varchar,Description varchar,Link varchar,PubDate date,UpdateTimeStamp timestamp,NewsID integer,DeleteFLAG boolean, ImageTicker boolean, ReadFLAG boolean, ChannelID integer)"];
        [db executeUpdate:@"CREATE INDEX IDX_Radio_Ticker_PubDate ON Radio_Ticker(PubDate)"];
        [db executeUpdate:@"CREATE TABLE PodcastCategories (ID integer PRIMARY KEY AUTOINCREMENT,channelid integer,vintern integer,url text,epgkategorieid integer,title text,beschreibung text,offsetsendereihe integer,offsetinhalt integer )"];
        [db executeUpdate:@"CREATE TABLE PodcastCatPictures (ID integer PRIMARY KEY AUTOINCREMENT,url text, picdata blob )"];
        [db executeUpdate:@"CREATE TABLE PodcastItems (ID integer PRIMARY KEY AUTOINCREMENT, url text,title text,description text,pubDate text, enclosureurl text, guid text, link text, date integer, catpicture text)"];
        [db executeUpdate:@"CREATE INDEX IDX_PodcastItems_url ON PodcastItems(url)"];
        [db executeUpdate:@"CREATE TABLE EPGData (ID integer PRIMARY KEY, starttime integer,endtime integer,\t\t\ttitel text,titelurl text, sendereihe text, sendereiheurl text, genreid integer,kategorieid integer,bildurl text, text_ text,channelid integer,genretext text)"];
        [db executeUpdate:@"CREATE TABLE CategorieNames (idx integer PRIMARY KEY, catGer text, catEng text, catFra text, catNed text, catIta text)"];
        [db executeUpdate:@"CREATE TABLE LoopStreams (ID integer PRIMARY KEY AUTOINCREMENT, channelid integer, title text, streamurl text, pictureurl text, description text, picturedata blob )"];
        [db executeUpdate:@"CREATE TABLE SongPictures (SongInfoID integer PRIMARY KEY, picturedata blob )"];
        [db executeUpdate:@"CREATE TABLE ChannelInfosEX (ID integer PRIMARY KEY, sendername text, streamurl text, playlisturl_nonwma text,\t\t\t\t\tcustomurls text, captured integer,\t\t\t\t\tshowmetadata integer, bitrate integer, rating integer, redaktionflag integer,\t\t\t\t\tnewschannelflag integer, sprachelandid integer, musikquote integer, sendeanstalt text, land text, langname text,\t\t\t\t\toptions integer, logodata blob, icondata blob,\t\t\t\t\tsenderlogo text, sendericon text,choosen integer, deleteflag integer, displaycolor integer, metadataregex text,\t\t\t\t\tdescription text, quality integer,ordernumber integer, streamformat text, url text, channelnameshort text,\t\t\t\t\tuseragent text, genres text )"];
        [db executeUpdate:@"CREATE TABLE Genres (GenreID integer PRIMARY KEY, Genrename text, deletedflag integer )"];
        [db executeUpdate:@"CREATE TABLE GenreAssignments ( AutoID integer PRIMARY KEY AUTOINCREMENT, GenreID integer, ChannelID integer )"];
        [db executeUpdate:@"CREATE TABLE Mixxtapes (autoid integer PRIMARY KEY AUTOINCREMENT, ID integer, interpret text, title text, folderid integer, serverid integer, \t\t\t\t\talbumname text, albumid integer, tracknumber integer, duration integer,\t\t\t\t\tinformation text,channelid integer,starttime integer,epgid integer,filename text,channel text,genre text, searchkey text)"];
        [db executeUpdate:@"CREATE TABLE MTFolders ( autoid integer PRIMARY KEY AUTOINCREMENT, folderid integer, foldername text, serverid integer, excluded integer, autoselect integer, flags integer, lastplayed boolean )"];
        [db executeUpdate:@"CREATE TABLE MTChannelpics ( channelid integer PRIMARY KEY, picdata blob )"];
        ok = [db executeUpdate:@"CREATE TABLE RemoteControlServers (ID integer PRIMARY KEY, ip text, deviceid text, devicename text, displayname text, password text, lastconnection integer)"];
        [self dbClose];
    }
    return ok;
}

- (void)CreateMixxtapeIndizes {
    if ([self dbOpen]) {
        [db executeUpdate:@"CREATE INDEX IDX_Mixxtapes_interpret ON Mixxtapes(interpret)"];
        [db executeUpdate:@"CREATE INDEX IDX_Mixxtapes_title ON Mixxtapes(title)"];
        [db executeUpdate:@"CREATE INDEX IDX_Mixxtapes_serverid ON Mixxtapes(serverid)"];
        [db executeUpdate:@"CREATE INDEX IDX_Mixxtapes_filename ON Mixxtapes(filename)"];
        [db executeUpdate:@"CREATE INDEX IDX_Mixxtapes_folderid ON Mixxtapes(folderid)"];
        [db executeUpdate:@"CREATE INDEX IDX_Mixxtapes_serverid ON Mixxtapes(serverid)"];
        [db executeUpdate:@"CREATE INDEX IDX_RemoteControlServers_ip ON RemoteControlServers(ip)"];
        [db executeUpdate:@"CREATE INDEX IDX_RemoteControlServers_deviceid ON RemoteControlServers(deviceid)"];
        [self dbClose];
    }
}

- (void)CreateMTTimesPlayedField {
    if ([self dbOpen]) {
        [db executeUpdate:@"ALTER TABLE Mixxtapes ADD COLUMN timesplayed integer;"];
        [self dbClose];
    }
}

- (void)CreateMTHideField {
    if ([self dbOpen]) {
        [db executeUpdate:@"ALTER TABLE Mixxtapes ADD COLUMN hidden integer;"];
        [self dbClose];
    }
}

- (void)CreateLimitField {
    if ([self dbOpen]) {
        [db executeUpdate:@"ALTER TABLE MTFolders ADD COLUMN limitations text;"];
        [self dbClose];
    }
}

- (void)CreateSpotifyFields {
    if ([self dbOpen]) {
        [db executeUpdate:@"ALTER TABLE Mixxtapes ADD COLUMN spotifyid text;"];
        [db executeUpdate:@"ALTER TABLE Mixxtapes ADD COLUMN spotifyfolderid text;"];
        [db executeUpdate:@"ALTER TABLE MTFolders ADD COLUMN spotifyfolderid text;"];
        [db executeUpdate:@"ALTER TABLE MTFolders ADD COLUMN spotifydeleteflag integer;"];
        [self dbClose];
    }
}

- (void)CreateJoinField {
    if ([self dbOpen]) {
        [db executeUpdate:@"ALTER TABLE MTFolders ADD COLUMN joinid integer;"];
        [self dbClose];
    }
}

// Adds the "searchkey" column and fills it once (guarded by the user default "keydeletedsearchkeyonce1").
- (void)CreateMTSearcKeyField {
    if ([self dbOpen]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSInteger done = [defaults integerForKey:@"keydeletedsearchkeyonce1"];
        BOOL added = [db executeUpdate:@"ALTER TABLE Mixxtapes ADD COLUMN searchkey text;"];
        if (added || done == 0) {
            NSString *q = [NSString stringWithFormat:@"select interpret, title, serverid, folderid, ID from mixxtapes"];
            FMResultSet *rs = [db executeQuery:q];
            [db beginTransaction];
            while ([rs next]) {
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                NSString *interpret = [rs stringForColumn:@"interpret"];
                NSString *title = [rs stringForColumn:@"title"];
                int serverid = [rs intForColumn:@"serverid"];
                long long folderid = [rs longLongIntForColumn:@"folderid"];
                long long ID = [rs longLongIntForColumn:@"ID"];
                NSString *key = [NSString stringWithFormat:@"%@ %@", interpret, title];
                key = [key stringByReplacingOccurrencesOfRegex:@"[üÜ]" withString:@"ue"];
                key = [key stringByReplacingOccurrencesOfRegex:@"[öÖ]" withString:@"oe"];
                key = [key stringByReplacingOccurrencesOfRegex:@"[äÄ]" withString:@"ae"];
                key = [key stringByReplacingOccurrencesOfRegex:@"ß" withString:@"ss"];
                key = [key stringByReplacingOccurrencesOfRegex:@"[^a-zA-Z0-9 ]" withString:@""];
                NSString *upd = [NSString stringWithFormat:@"UPDATE Mixxtapes SET searchkey = '%@' WHERE serverid = %i AND folderid = %lld AND ID = %lld", key, serverid, folderid, ID];
                [db executeUpdate:upd];
                [pool drain];
            }
            [db commit];
            [defaults setInteger:1 forKey:@"keydeletedsearchkeyonce1"];
            [defaults synchronize];
        }
        [self dbClose];
    }
}

#pragma mark - folders

// Passes: 2 = the server's own folders, 1 = the browsed/remote server's folders.
- (NSMutableArray *)GetFolders:(ServerEntry *)server onlyexclude:(BOOL)onlyexclude checkempty:(BOOL)checkempty
                    withLimits:(BOOL)withLimits withremotefolders:(BOOL)remotefolders join:(BOOL)join {
    NSMutableArray *folders = [[NSMutableArray alloc] init];

    // "Live Radio" pseudo folder (-33), shown when radio channels are chosen
    if ([self GetNumChoosenChannels] >= 1 && !([server StateFlags] & 0x800)) {
        FolderObject *live = [[FolderObject alloc] init];
        [live setServerid:[server serverid]];
        [live setFoldername:@"Live Radio"];
        [live setFolderid:-33];
        [folders addObject:live];
        [live release];
    }

    if ([self dbOpen]) {
        NSString *joinClause = join ? @"AND (joinid = 0 OR joinid is NULL)" : @"";
        int pass;
        for (pass = 2; pass >= 1; pass--) {
            int sid;
            if (pass == 2) {
                sid = [server serverid];
            } else {
                if ([server browseid] >= 1)
                    sid = [server browseid];
                else if ([server remoteserverid] >= 1)
                    sid = [server remoteserverid];
                else
                    sid = -2;
                if (!remotefolders)
                    continue;
            }
            NSString *sql;
            if (onlyexclude)
                sql = [NSString stringWithFormat:@"SELECT * FROM MTFolders WHERE serverid = %i AND excluded = 1 ORDER BY foldername COLLATE NOCASE ASC", sid];
            else
                sql = [NSString stringWithFormat:@"SELECT * FROM MTFolders WHERE serverid = %i %@ AND ( excluded is NULL OR excluded = 0 )  ORDER BY foldername COLLATE NOCASE ASC", sid, joinClause];
            FMResultSet *rs = [db executeQuery:sql];
            while ([rs next]) {
                FolderObject *f = [[FolderObject alloc] init];
                [f setServerid:sid];
                [f setFoldername:[rs stringForColumn:@"foldername"]];
                [f setFolderid:[rs longLongIntForColumn:@"folderid"]];
                [f setAutoselect:[rs intForColumn:@"autoselect"]];
                [f setFlags:[rs intForColumn:@"flags"]];
                [f setLastplayed:[rs boolForColumn:@"lastplayed"]];
                [f setLimitations:[rs stringForColumn:@"limitations"]];
                [f setJoinid:[rs intForColumn:@"joinid"]];
                [f setSpotifyfolderid:[rs stringForColumn:@"spotifyfolderid"]];
                [folders addObject:f];
                [f release];
            }
            [rs close];
        }

        if (checkempty) {
            int i;
            for (i = (int)[folders count] - 1; i >= 0; i--) {
                FolderObject *f = [folders objectAtIndex:i];
                if ([f folderid] == -33) continue;
                if ([f folderid] == -44) continue;
                if ([self IsFolderEmpty:f withServerID:[f serverid]])
                    [folders removeObjectAtIndex:i];
            }
        }
        [self dbClose];
    }

    if (withLimits) {
        int dayIndex;
        long secOfDay;
        [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] GetLimitationVars:&dayIndex withsecofday:&secOfDay];
        int i;
        for (i = (int)[folders count] - 1; i >= 0; i--) {
            FolderObject *f = [folders objectAtIndex:i];
            if ([f folderid] == -33) continue;
            if ([f folderid] == -44) continue;
            if ([f folderid] == -66) continue;
            int start, end;
            [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate]
                GetFolderLimitationForDayIndex:(dayIndex - 1) withstarttime:&start withendtime:&end withFolderobject:f];
            if (secOfDay >= start && secOfDay <= end)
                continue;
            // outside today's window: still allowed if yesterday's window runs past midnight
            [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate]
                GetFolderLimitationForDayIndex:((dayIndex - 1) < 1 ? 6 : (dayIndex - 2)) withstarttime:&start withendtime:&end withFolderobject:f];
            if ((end - 86400) >= 1 && secOfDay <= (end - 86400))
                continue;
            [folders removeObjectAtIndex:i];
        }
    }
    return folders;
}

- (FolderObject *)GetFolderForID:(long long)folderid withserverid:(int)serverid withipodid:(long long)ipodid withspotifyid:(NSString *)spotifyid {
    FolderObject *folder = nil;
    if (folderid == -44) {
        folder = [[FolderObject alloc] init];
        [folder setFolderid:folderid];
        [folder setServerid:serverid];
        [folder setIpodid:ipodid];
        if (ipodid == -22)
            [folder setFoldername:@"Musik"];
        return folder;
    }
    if (folderid == -33) {
        folder = [[FolderObject alloc] init];
        [folder setFolderid:folderid];
        [folder setServerid:serverid];
        [folder setFoldername:@"Live Radio"];
        return folder;
    }
    if ([self dbOpen]) {
        NSNumber *sid = [NSNumber numberWithInt:serverid];
        NSNumber *fid = [NSNumber numberWithLongLong:folderid];
        FMResultSet *rs;
        if (folderid == -66)
            rs = [db executeQuery:@"SELECT * FROM MTFolders WHERE serverid = ? AND folderid = ? AND spotifyfolderid = ?", sid, fid, spotifyid];
        else
            rs = [db executeQuery:@"SELECT * FROM MTFolders WHERE serverid = ? AND folderid = ?", sid, fid];
        if ([rs next]) {
            folder = [[FolderObject alloc] init];
            [folder setFolderid:folderid];
            [folder setServerid:serverid];
            [folder setLastplayed:[rs boolForColumn:@"lastplayed"]];
            [folder setFlags:[rs intForColumn:@"flags"]];
            [folder setAutoselect:[rs intForColumn:@"autoselect"]];
            [folder setFoldername:[rs stringForColumn:@"foldername"]];
            [folder setExcluded:[rs intForColumn:@"excluded"]];
            [folder setLimitations:[rs stringForColumn:@"limitations"]];
            [folder setJoinid:[rs intForColumn:@"joinid"]];
            [folder setSpotifyfolderid:[rs stringForColumn:@"spotifyfolderid"]];
        }
        [rs close];
        [self dbClose];
    }
    return folder;
}

- (NSString *)GetFoldername:(long long)folderid withserverid:(int)serverid withipodid:(long long)ipodid withspotifyfolderid:(NSString *)spotifyfolderid {
    if (folderid == -33)
        return @"Live Radio";
    if (folderid == -44)
        return (ipodid == -22) ? @"Musik" : nil;
    NSString *name = nil;
    if ([self dbOpen]) {
        NSNumber *sid = [NSNumber numberWithInt:serverid];
        NSNumber *fid = [NSNumber numberWithLongLong:folderid];
        FMResultSet *rs;
        if (folderid == -66)
            rs = [db executeQuery:@"SELECT foldername FROM MTFolders WHERE serverid = ? AND folderid = ? AND spotifyfolderid = ?", sid, fid, spotifyfolderid];
        else
            rs = [db executeQuery:@"SELECT foldername FROM MTFolders WHERE serverid = ? AND folderid = ?", sid, fid];
        if ([rs next])
            name = [rs stringForColumn:@"foldername"];
        [rs close];
        [self dbClose];
    }
    return name;
}

- (int)GetLastPlayedFolder:(int)serverid withspotifyfolderid:(NSString **)spotifyfolderid {
    int folderid = -1;
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT folderid,spotifyfolderid FROM MTFolders WHERE lastplayed = ? AND serverid = ? AND ( excluded is NULL OR excluded = 0)",
                           [NSNumber numberWithBool:YES], [NSNumber numberWithInt:serverid]];
        if ([rs next]) {
            folderid = [rs intForColumn:@"folderid"];
            *spotifyfolderid = [rs stringForColumn:@"spotifyfolderid"];
        }
        [rs close];
        [self dbClose];
    }
    return folderid;
}

- (BOOL)SetFolderLastPlayed:(long long)folderid withServerID:(int)serverid withspotifyfolderid:(NSString *)spotifyfolderid {
    BOOL ok = NO;
    if ([self dbOpen]) {
        if (serverid == -1) {
            ok = [db executeUpdate:@"UPDATE MTFolders SET lastplayed = ?", [NSNumber numberWithBool:NO]];
        } else {
            NSNumber *sid = [NSNumber numberWithLong:serverid];
            [db executeUpdate:@"UPDATE MTFolders SET lastplayed = ? WHERE serverid = ?", [NSNumber numberWithBool:NO], sid];
            if (spotifyfolderid && [spotifyfolderid length])
                ok = [db executeUpdate:@"UPDATE MTFolders SET lastplayed = ? WHERE serverid = ? AND folderid = ? AND spotifyfolderid = ?",
                      [NSNumber numberWithBool:YES], sid, [NSNumber numberWithLongLong:folderid], spotifyfolderid];
            else
                ok = [db executeUpdate:@"UPDATE MTFolders SET lastplayed = ? WHERE serverid = ? AND folderid = ?",
                      [NSNumber numberWithBool:YES], sid, [NSNumber numberWithLongLong:folderid]];
        }
        [self dbClose];
    }
    return ok;
}

- (BOOL)InsertFolder:(FolderObject *)folder {
    BOOL ok = NO;
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT folderid FROM MTFolders WHERE folderid = ? AND foldername = ? AND serverid = ?",
                           [NSNumber numberWithLongLong:[folder folderid]], [folder foldername], [NSNumber numberWithInt:[folder serverid]]];
        BOOL exists = [rs next];
        [rs close];
        if (exists) {
            ok = YES;
        } else {
            ok = [db executeUpdate:@"INSERT INTO MTFolders (foldername,folderid,serverid,flags,autoselect,lastplayed,limitations,joinid ) \t\t\t\t\t   VALUES  (?, ?, ?, ?, ?, ?, ?, ?)",
                  [folder foldername],
                  [NSNumber numberWithLongLong:[folder folderid]],
                  [NSNumber numberWithInt:[folder serverid]],
                  [NSNumber numberWithInt:[folder flags]],
                  [NSNumber numberWithInt:[folder autoselect]],
                  [NSNumber numberWithBool:[folder lastplayed]],
                  [folder limitations],
                  [NSNumber numberWithInt:[folder joinid]]];
        }
        [self dbClose];
    }
    return ok;
}

- (BOOL)UpdateFolder:(FolderObject *)folder withServerid:(int)serverid {
    BOOL ok = NO;
    if ([self dbOpen]) {
        long long folderid = [folder folderid];
        NSString *name = [folder foldername];
        NSNumber *autoselect = [NSNumber numberWithInt:[folder autoselect]];
        NSNumber *flags = [NSNumber numberWithInt:[folder flags]];
        NSNumber *lastplayed = [NSNumber numberWithBool:[folder lastplayed]];
        NSString *limitations = [folder limitations];
        NSNumber *joinid = [NSNumber numberWithInt:[folder joinid]];
        NSNumber *sid = [NSNumber numberWithInt:serverid];
        NSNumber *fid = [NSNumber numberWithLongLong:[folder folderid]];
        if (folderid == -66)
            ok = [db executeUpdate:@"UPDATE MTFolders SET foldername = ?, autoselect = ?, flags = ?, lastplayed = ?, limitations = ?, joinid = ? WHERE serverid = ? AND folderid = ? AND spotifyfolderid = ?",
                  name, autoselect, flags, lastplayed, limitations, joinid, sid, fid, [folder spotifyfolderid]];
        else
            ok = [db executeUpdate:@"UPDATE MTFolders SET foldername = ?, autoselect = ?, flags = ?, lastplayed = ?, limitations = ?, joinid = ? WHERE serverid = ? AND folderid = ?",
                  name, autoselect, flags, lastplayed, limitations, joinid, sid, fid];
        [self dbClose];
    }
    return ok;
}

- (BOOL)IsFolderEmpty:(FolderObject *)folder withServerID:(int)serverid {
    NSString *sql;
    if ([folder folderid] == -66)
        sql = [NSString stringWithFormat:@"SELECT ID FROM Mixxtapes WHERE serverid = %i AND folderid = %lld AND hidden is NULL AND spotifyfolderid = '%@' AND COALESCE(hidden,0)=0 LIMIT 1",
               serverid, [folder folderid], [folder spotifyfolderid]];
    else
        sql = [NSString stringWithFormat:@"SELECT ID FROM Mixxtapes WHERE serverid = %i AND folderid = %lld AND hidden is NULL AND COALESCE(hidden,0)=0 LIMIT 1",
               serverid, [folder folderid]];
    FMResultSet *rs = [db executeQuery:sql];
    BOOL hasRow = [rs next];
    [rs close];
    return !hasRow;
}

- (BOOL)HasFolderSongs:(FolderObject *)folder {
    BOOL found = NO;
    if ([folder folderid] == -33) {
        // live radio folder: removed (server / streaming support dropped)
        return NO;
    }
    if ([folder folderid] == -66) {
        if ([self dbOpen]) {
            NSString *sql = [NSString stringWithFormat:@"SELECT ID FROM Mixxtapes WHERE serverid = %i AND folderid = %lld AND spotifyfolderid = '%@' AND hidden is NULL AND COALESCE(hidden,0)=0 LIMIT 1",
                             [folder serverid], [folder folderid], [folder spotifyfolderid]];
            FMResultSet *rs = [db executeQuery:sql];
            found = [rs next];
            [rs close];
            [self dbClose];
        }
        return found;
    }
    if ([folder folderid] == -44) {
        // iPod music library
        if ([folder ipodid] == -22) {
            return [[[MPMediaQuery songsQuery] items] count] != 0;
        }
        MPMediaQuery *query = [[MPMediaQuery alloc] init];
        [query addFilterPredicate:[MPMediaPropertyPredicate predicateWithValue:[NSNumber numberWithLongLong:[folder ipodid]]
                                                                   forProperty:MPMediaPlaylistPropertyPersistentID]];
        [query setGroupingType:MPMediaGroupingPlaylist];
        NSArray *collections = [query collections];
        if (collections && [collections count]) {
            for (MPMediaItemCollection *c in collections) {
                if ([c items] && [[c items] count] != 0)
                    found = YES;
            }
        }
        [query release];
        return found;
    }
    if ([self dbOpen]) {
        NSString *sql = [NSString stringWithFormat:@"SELECT ID FROM Mixxtapes WHERE serverid = %i AND folderid = %lld AND hidden is NULL AND COALESCE(hidden,0)=0 LIMIT 1",
                         [folder serverid], [folder folderid]];
        FMResultSet *rs = [db executeQuery:sql];
        found = [rs next];
        [rs close];
        [self dbClose];
    }
    return found;
}

// Builds "(id,id,...)" -- the folder itself plus every folder joined into it.
- (NSString *)GetJoinedFolders:(long long)folderid withserverid:(int)serverid withjoin:(BOOL)join {
    NSMutableString *ids = [NSMutableString stringWithCapacity:0];
    [ids appendString:[NSString stringWithFormat:@"(%lld", folderid]];
    if (join && folderid != 0) {
        FMResultSet *rs = [db executeQuery:[NSString stringWithFormat:@"SELECT folderid FROM MTFolders WHERE serverid = %i AND joinid = %lld", serverid, folderid]];
        while ([rs next])
            [ids appendString:[NSString stringWithFormat:@",%lld", [rs longLongIntForColumn:@"folderid"]]];
        [rs close];
    }
    [ids appendString:@")"];
    return [NSString stringWithFormat:@"%@", ids];
}

- (BOOL)SaveExcludefolders:(NSArray *)folders forServer:(ServerEntry *)server {
    BOOL ok = NO;
    if ([self dbOpen]) {
        [db beginTransaction];
        ok = [db executeUpdate:@"UPDATE MTFolders SET excluded = 0 WHERE serverid = ?", [NSNumber numberWithInt:[server serverid]]];
        NSUInteger i;
        for (i = 0; i < [folders count]; i++) {
            FolderObject *f = [folders objectAtIndex:i];
            FMResultSet *rs = [db executeQuery:@"SELECT autoid FROM MTFolders WHERE folderid = ? AND serverid = ?",
                               [NSNumber numberWithLongLong:[f folderid]], [NSNumber numberWithInt:[server serverid]]];
            int autoid = -1;
            if ([rs next])
                autoid = [rs intForColumn:@"autoid"];
            [rs close];
            if (autoid != -1)
                ok = [db executeUpdate:@"UPDATE MTFolders SET excluded = 1 WHERE autoid = ?", [NSNumber numberWithInt:autoid]];
            else
                ok = [db executeUpdate:@"INSERT INTO MTFolders (foldername,folderid,serverid,excluded ) \t\t\t\t\tVALUES  (?, ?, ?, ?)",
                      [f foldername], [NSNumber numberWithLongLong:[f folderid]], [NSNumber numberWithInt:[server serverid]], [NSNumber numberWithInt:1]];
        }
        [db commit];
        [self dbClose];
    }
    return ok;
}

- (BOOL)DeleteMTFolder:(FolderObject *)folder withServerid:(int)serverid deleteFolderItself:(BOOL)deleteItself {
    BOOL ok = NO;
    if ([self dbOpen]) {
        [db beginTransaction];
        NSNumber *fid = [NSNumber numberWithLongLong:[folder folderid]];
        NSNumber *sid = [NSNumber numberWithLong:serverid];
        if ([folder folderid] == -66)
            ok = [db executeUpdate:@"DELETE FROM Mixxtapes WHERE folderid = ? AND serverid = ? AND spotifyfolderid =?", fid, sid, [folder spotifyfolderid]];
        else
            ok = [db executeUpdate:@"DELETE FROM Mixxtapes WHERE folderid = ? AND serverid = ?", fid, sid];
        if (deleteItself) {
            if ([folder folderid] == -66)
                ok = [db executeUpdate:@"DELETE FROM MTFolders WHERE folderid = ? AND serverid = ? AND spotifyfolderid = ?", fid, sid, [folder spotifyfolderid]];
            else
                ok = [db executeUpdate:@"DELETE FROM MTFolders WHERE folderid = ? AND serverid = ?", fid, sid];
        }
        [db commit];
        [self dbClose];
        id key = [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate]
                  CreatePrescrollerKey:[folder folderid] withserverid:serverid withipodid:[folder ipodid] withspotifyid:[folder spotifyfolderid]];
        [self performSelectorOnMainThread:@selector(PostDeleteMTNotiInMainThread:) withObject:key waitUntilDone:NO];
    }
    return ok;
}

- (void)PostDeleteMTNotiInMainThread:(id)object {
    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"MsgMtDeleted" object:object]];
}

- (BOOL)DeleteMTServerDB:(ServerEntry *)server {
    BOOL ok = NO;
    if ([self dbOpen]) {
        [db beginTransaction];
        NSNumber *sid = [NSNumber numberWithLong:[server serverid]];
        [db executeUpdate:@"DELETE FROM Mixxtapes WHERE serverid = ?", sid];
        ok = [db executeUpdate:@"DELETE FROM MTFolders WHERE serverid = ?", sid];
        [db commit];
        [self dbClose];
    }
    return ok;
}

#pragma mark - songs

- (NSMutableArray *)GetSongsForFolder:(FolderObject *)folder withjoin:(BOOL)join {
    NSMutableArray *songs = [[NSMutableArray alloc] init];
    if ([folder folderid] == -33) {
        // live radio channel list: removed (server / streaming support dropped)
        return songs;
    }
    if ([folder folderid] != -44 && [self dbOpen]) {
        NSString *sql;
        if ([folder folderid] == -66) {
            sql = [NSString stringWithFormat:@"SELECT * FROM Mixxtapes WHERE serverid = %i AND folderid = %i AND spotifyfolderid = '%@' AND hidden is NULL AND COALESCE(hidden,0)=0  ORDER BY interpret COLLATE NOCASE ASC",
                   [folder serverid], -66, [folder spotifyfolderid]];
        } else {
            NSString *joined = [self GetJoinedFolders:[folder folderid] withserverid:[folder serverid] withjoin:join];
            sql = [NSString stringWithFormat:@"SELECT * FROM Mixxtapes WHERE serverid = %i AND folderid in %@ AND hidden is NULL AND COALESCE(hidden,0)=0  ORDER BY interpret COLLATE NOCASE ASC",
                   [folder serverid], joined];
        }
        FMResultSet *rs = [db executeQuery:sql];
        while ([rs next]) {
            ClipObject *co = [[ClipObject alloc] init];
            [self ReadCO:co withRSet:rs];
            [songs addObject:co];
            [co release];
        }
        [rs close];
        [self dbClose];
    }
    if ([(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] IsBrandingPicturePresent]) {
        ClipObject *branding = [[ClipObject alloc] init];
        [branding setM_title:@" "];
        [branding setM_interpret:@" "];
        [branding setM_folderid:[folder folderid]];
        [branding setM_serverid:[folder serverid]];
        [branding setM_duration:30];
        [branding setID:-5];
        [songs addObject:branding];
        [branding release];
    }
    return songs;
}

- (ClipObject *)GetSongWithID:(long long)songID withServerid:(int)serverid {
    ClipObject *co = nil;
    if ([self dbOpen]) {
        NSString *sql = [NSString stringWithFormat:@"SELECT * FROM Mixxtapes WHERE ID = %lld AND serverid = %i;", songID, serverid];
        FMResultSet *rs = [db executeQuery:sql];
        if ([rs next]) {
            co = [[ClipObject alloc] init];
            [self ReadCO:co withRSet:rs];
        }
        [rs close];
        [self dbClose];
    }
    return co;
}

- (void)ReadCO:(ClipObject *)co withRSet:(FMResultSet *)rs {
    [co setM_interpret:[rs stringForColumn:@"interpret"]];
    [co setM_title:[rs stringForColumn:@"title"]];
    [co setID:[rs longLongIntForColumn:@"ID"]];
    [co setM_folderid:[rs longLongIntForColumn:@"folderid"]];
    [co setM_albumid:[rs longLongIntForColumn:@"albumid"]];
    [co setM_albumname:[rs stringForColumn:@"albumname"]];
    [co setM_tracknumber:[rs intForColumn:@"tracknumber"]];
    [co setM_duration:[rs intForColumn:@"duration"]];
    [co setM_information:[rs stringForColumn:@"information"]];
    [co setM_channelid:[rs intForColumn:@"channelid"]];
    [co setM_starttime:[rs intForColumn:@"starttime"]];
    [co setM_epgid:[rs intForColumn:@"epgid"]];
    [co setM_filename:[rs stringForColumn:@"filename"]];
    [co setM_channel:[rs stringForColumn:@"channel"]];
    [co setM_genre:[rs stringForColumn:@"genre"]];
    [co setM_serverid:[rs intForColumn:@"serverid"]];
    [co setM_spotifyid:[rs stringForColumn:@"spotifyid"]];
    [co setM_spotifyfolderid:[rs stringForColumn:@"spotifyfolderid"]];
}

// Updates the row if the clip already exists (same folder / server / ID), inserts otherwise.
- (BOOL)InsertClip:(ClipObject *)co withserverid:(int)serverid {
    BOOL ok = NO;
    if ([self dbOpen]) {
        int autoid = -1;
        FMResultSet *rs = [db executeQuery:@"SELECT autoid FROM Mixxtapes WHERE folderid = ? AND serverid = ? AND ID = ?",
                           [NSNumber numberWithLongLong:[co m_folderid]], [NSNumber numberWithInt:serverid], [NSNumber numberWithLongLong:[co ID]]];
        if (rs) {
            if ([rs next])
                autoid = [rs intForColumn:@"autoid"];
            [rs close];
        }
        NSString *key = [NSString stringWithFormat:@"%@ %@", [co m_interpret], [co m_title]];
        key = [key stringByReplacingOccurrencesOfRegex:@"[üÜ]" withString:@"ue"];
        key = [key stringByReplacingOccurrencesOfRegex:@"[öÖ]" withString:@"oe"];
        key = [key stringByReplacingOccurrencesOfRegex:@"[äÄ]" withString:@"ae"];
        key = [key stringByReplacingOccurrencesOfRegex:@"ß" withString:@"ss"];
        key = [key stringByReplacingOccurrencesOfRegex:@"[^a-zA-Z0-9 ]" withString:@""];
        NSNumber *nID = [NSNumber numberWithLongLong:[co ID]];
        NSString *interpret = [co m_interpret];
        NSString *title = [co m_title];
        NSNumber *nFolder = [NSNumber numberWithLongLong:[co m_folderid]];
        NSNumber *nServer = [NSNumber numberWithInt:serverid];
        NSNumber *nAlbumid = [NSNumber numberWithLongLong:[co m_albumid]];
        NSString *albumname = [co m_albumname];
        NSNumber *nTrack = [NSNumber numberWithInt:[co m_tracknumber]];
        NSNumber *nDuration = [NSNumber numberWithInt:[co m_duration]];
        NSString *information = [co m_information];
        NSNumber *nChannel = [NSNumber numberWithInt:[co m_channelid]];
        NSNumber *nStart = [NSNumber numberWithInt:[co m_starttime]];
        NSNumber *nEpg = [NSNumber numberWithInt:[co m_epgid]];
        NSString *filename = [co m_filename];
        NSString *channel = [co m_channel];
        NSString *genre = [co m_genre];
        if (autoid != -1)
            ok = [db executeUpdate:@"UPDATE Mixxtapes SET ID = ?, interpret = ?,title = ?,folderid = ?,serverid = ?,albumid = ?,albumname = ?,tracknumber = ?,duration = ?,\t\t\t\t\t   information = ?,channelid = ?,starttime = ?,epgid = ?,filename = ?,channel = ?,genre = ?, searchkey = ? WHERE autoid = ?",
                  nID, interpret, title, nFolder, nServer, nAlbumid, albumname, nTrack, nDuration, information, nChannel, nStart, nEpg, filename, channel, genre, key, [NSNumber numberWithInt:autoid]];
        else
            ok = [db executeUpdate:@"INSERT INTO Mixxtapes (ID,interpret,title,folderid,serverid,albumid,albumname,tracknumber,duration,\t\t\t\t\t   information,channelid,starttime,epgid,filename,channel,genre,searchkey) \t\t\t\t\t   VALUES  (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                  nID, interpret, title, nFolder, nServer, nAlbumid, albumname, nTrack, nDuration, information, nChannel, nStart, nEpg, filename, channel, genre, key];
        [self dbClose];
    }
    return ok;
}

- (BOOL)IsSongPresent:(id)unused1 withSongname:(id)unused2 withfolderid:(long long)folderid withserverid:(int)serverid withID:(long long)songID {
    BOOL present = NO;
    if ([self dbOpen]) {
        int autoid = -1;
        FMResultSet *rs = [db executeQuery:@"SELECT autoid FROM Mixxtapes WHERE folderid = ? AND serverid = ? AND ID = ?",
                           [NSNumber numberWithLongLong:folderid], [NSNumber numberWithInt:serverid], [NSNumber numberWithLongLong:songID]];
        if (rs) {
            if ([rs next])
                autoid = [rs intForColumn:@"autoid"];
            [rs close];
        }
        [self dbClose];
        present = (autoid != -1);
    }
    return present;
}

- (BOOL)DeleteSongFromDB:(ClipObject *)co withServer:(ServerEntry *)server {
    BOOL ok = NO;
    if ([self dbOpen]) {
        ok = [db executeUpdate:@"DELETE FROM Mixxtapes WHERE ID = ? AND serverid = ? AND folderid = ?",
              [NSNumber numberWithLongLong:[co ID]], [NSNumber numberWithInt:[server serverid]], [NSNumber numberWithLongLong:[co m_folderid]]];
        [self dbClose];
    }
    return ok;
}

- (BOOL)DeleteAllSongsFromDB {
    BOOL ok = NO;
    if ([self dbOpen]) {
        [db executeUpdate:@"DELETE FROM Mixxtapes"];
        ok = [db executeUpdate:@"DELETE FROM MTFolders"];
        [self dbClose];
    }
    return ok;
}

- (BOOL)DeleteDoubleEntries {
    BOOL ok = NO;
    if ([self dbOpen]) {
        ok = [db executeUpdate:@"DELETE FROM Mixxtapes WHERE autoid IN \t\t( SELECT tmp.autoid FROM Mixxtapes t \t\tLEFT JOIN Mixxtapes tmp ON t.ID = tmp.ID AND t.folderid = tmp.folderid AND t.serverid = tmp.serverid \t\tGROUP BY t.ID, t.folderid, t.serverid, tmp.autoid \t\tHAVING COUNT(t.autoid) > 1 AND tmp.autoid != MIN(t.autoid))"];
        [self dbClose];
    }
    return ok;
}

// Looks a clip up by its "<n>-<interpret> - <title>.mp3" file name; falls back to the name after the last backslash.
- (ClipObject *)FindInterpretAndSong:(ClipObject *)co withserverid:(int *)serverid {
    ClipObject *found = nil;
    if ([self dbOpen]) {
        NSString *interpret = [[co m_interpret] stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
        NSString *title = [[co m_title] stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
        NSString *sql = [NSString stringWithFormat:@"SELECT * FROM Mixxtapes WHERE \t\t\t\t\t\t\t\t\t\t\t\t\t   filename LIKE '%%-%@ - %@.mp3'", interpret, title];
        FMResultSet *rs = [db executeQuery:sql];
        if ([rs next]) {
            found = [[ClipObject alloc] init];
            [self ReadCO:found withRSet:rs];
            *serverid = [rs intForColumn:@"serverid"];
            [rs close];
        } else {
            [rs close];
        }
        if (found == nil) {
            NSRange bs = [[co m_filename] rangeOfString:@"\\" options:NSBackwardsSearch];
            if (bs.location != NSNotFound && bs.location < [[co m_filename] length] - 1) {
                NSString *tail = [[co m_filename] substringFromIndex:bs.location + 1];
                if (tail != nil) {
                    NSRange dash = [tail rangeOfString:@"-"];
                    NSString *name = tail;
                    if (dash.location != NSNotFound && dash.location < [tail length] - 1)
                        name = [tail substringFromIndex:dash.location + 1];
                    name = [name stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
                    sql = [NSString stringWithFormat:@"SELECT * FROM Mixxtapes WHERE \t\t\t\t\t\t filename LIKE '%%%@'", name];
                    FMResultSet *rs2 = [db executeQuery:sql];
                    while ([rs2 next]) {
                        found = [[ClipObject alloc] init];
                        [self ReadCO:found withRSet:rs2];
                        *serverid = [rs2 intForColumn:@"serverid"];
                        if ([co m_duration] == [found m_duration])
                            break;
                        if (found != nil) { [found release]; found = nil; }
                    }
                    [rs2 close];
                }
            }
        }
        [self dbClose];
    }
    return found;
}

- (int)GetCompleteSongCount {
    int count = 0;
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT COUNT(ID) as founditems FROM Mixxtapes"];
        if ([rs next])
            count = [rs intForColumn:@"founditems"];
        [rs close];
        [self dbClose];
    }
    return count;
}

- (int)GetNumSongsForFolderLimit10:(long long)folderid withServerid:(int)serverid {
    int count = 0;
    if ([self dbOpen]) {
        NSString *sql = [NSString stringWithFormat:@"SELECT COUNT(ID) as founditems FROM Mixxtapes WHERE \t\t\t\t\t\t   serverid = %i AND folderid = %lld LIMIT 10", serverid, folderid];
        FMResultSet *rs = [db executeQuery:sql];
        if ([rs next])
            count = [rs intForColumn:@"founditems"];
        [rs close];
        [self dbClose];
    }
    return count;
}

// Number of rows (no search string) or number of matching rows (with search string) for a folder.
- (int)GetNumMatchingEntries:(long long)folderid withServerid:(int)serverid withsearchstring:(NSString *)search
                  withipodid:(long long)ipodid withspotifyfolderid:(NSString *)spotifyfolderid {
    int searchLen = search ? (int)[search length] : 0;
    if (folderid == -55) return 0;
    if (folderid == -44) return 0;
    if (folderid == -33) return 0;      // live radio channel count: removed
    int rows = 0, matches = 0;
    if ([self dbOpen]) {
        NSString *joined = [self GetJoinedFolders:folderid withserverid:serverid withjoin:YES];
        NSString *sql;
        if (spotifyfolderid && [spotifyfolderid length])
            sql = [NSString stringWithFormat:@"SELECT interpret,title FROM Mixxtapes WHERE                serverid = %i AND folderid in %@ AND spotifyfolderid ='%@' AND hidden is NULL AND COALESCE(hidden,0)=0", serverid, joined, spotifyfolderid];
        else
            sql = [NSString stringWithFormat:@"SELECT interpret,title FROM Mixxtapes WHERE                serverid = %i AND folderid in %@ AND hidden is NULL AND COALESCE(hidden,0)=0", serverid, joined];
        FMResultSet *rs = [db executeQuery:sql];
        while ([rs next]) {
            rows++;
            matches += [self CheckMatching:search withinterpret:[rs stringForColumn:@"interpret"] withtitle:[rs stringForColumn:@"title"]];
        }
        [rs close];
        [self dbClose];
    }
    return (searchLen == 0) ? rows : matches;
}

- (int)CheckMatching:(NSString *)search withinterpret:(NSString *)interpret withtitle:(NSString *)title {
    if (search != nil && [search length] == 0)
        return 0;
    if ([title RfxMatchString:search])
        return 1;
    return [interpret RfxMatchString:search] ? 1 : 0;
}

#pragma mark - play counts / hiding

- (NSMutableArray *)GetCharts {
    NSMutableArray *charts = [[NSMutableArray alloc] init];
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT timesplayed,interpret, title  FROM Mixxtapes WHERE timesplayed IS NOT NULL ORDER BY timesplayed DESC LIMIT 5"];
        while ([rs next]) {
            ClipObject *co = [[ClipObject alloc] init];
            [co setM_serverid:[rs intForColumn:@"timesplayed"]];
            [co setM_title:[rs stringForColumn:@"title"]];
            [co setM_interpret:[rs stringForColumn:@"interpret"]];
            [charts addObject:co];
            [co release];
        }
        [rs close];
        [self dbClose];
    }
    return charts;
}

- (BOOL)IncTimesPlayed:(ClipObject *)co {
    BOOL ok = NO;
    if ([self dbOpen]) {
        BOOL bySpotify = ([co m_spotifyid] != nil && [[co m_spotifyid] length] != 0 &&
                          [co m_spotifyfolderid] != nil && [[co m_spotifyfolderid] length] != 0);
        FMResultSet *rs;
        if (bySpotify)
            rs = [db executeQuery:@"SELECT timesplayed FROM Mixxtapes WHERE spotifyid = ? AND spotifyfolderid = ?", [co m_spotifyid], [co m_spotifyfolderid]];
        else
            rs = [db executeQuery:@"SELECT timesplayed FROM Mixxtapes WHERE ID = ? AND serverid = ?",
                  [NSNumber numberWithLongLong:[co ID]], [NSNumber numberWithInt:[co m_serverid]]];
        int times = 1;
        if ([rs next])
            times = [rs intForColumn:@"timesplayed"] + 1;
        [rs close];
        NSNumber *n = [NSNumber numberWithInt:times];
        if (bySpotify)
            ok = [db executeUpdate:@"UPDATE Mixxtapes SET timesplayed = ? WHERE spotifyid = ? AND spotifyfolderid = ?", n, [co m_spotifyid], [co m_spotifyfolderid]];
        else
            ok = [db executeUpdate:@"UPDATE Mixxtapes SET timesplayed = ? WHERE ID = ? AND serverid = ?",
                  n, [NSNumber numberWithLongLong:[co ID]], [NSNumber numberWithInt:[co m_serverid]]];
        [self dbClose];
    }
    return ok;
}

- (void)ResetTimesPlayed {
    if ([self dbOpen]) {
        [db executeUpdate:@"UPDATE Mixxtapes SET timesplayed = 0"];
        [self dbClose];
    }
}

- (void)HideTitle:(ClipObject *)co {
    if ([self dbOpen]) {
        NSString *sql = [NSString stringWithFormat:@"UPDATE Mixxtapes SET hidden = 1 WHERE serverid = %i AND folderid = %lld AND ID = %lld",
                         [co m_serverid], [co m_folderid], [co ID]];
        [db executeUpdate:sql];
        [self dbClose];
    }
}

- (void)UndeleteTitle {
    if ([self dbOpen]) {
        [db executeUpdate:@"UPDATE Mixxtapes SET hidden = NULL"];
        [self dbClose];
    }
}

- (int)GetNumChoosenChannels {
    int count = 0;
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT COUNT (ID) AS idx FROM ChannelInfosEx WHERE choosen > 0"];
        if ([rs next])
            count = [rs intForColumn:@"idx"];
        [rs close];
        [self dbClose];
    }
    return count;
}

- (void)CleanDataBase {
    long cutoff = [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] ConvertDate:[[NSDate date] dateByAddingTimeInterval:-86400.0]];
    if ([self dbOpen]) {
        [[self db] beginTransaction];
        [db executeUpdate:@"DELETE FROM EPGData WHERE endtime < ?", [NSNumber numberWithLong:cutoff]];
        [[self db] commit];
        [db executeUpdate:@"VACUUM"];
        [self dbClose];
    }
}

- (void)CreateRCMessageField {
    if ([self dbOpen]) {
        [db executeUpdate:@"ALTER TABLE RemoteControlServers ADD COLUMN transfercomplete integer;"];
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        if ([defs integerForKey:@"keysettransfercompleteonce1"] == 0) {
            [db executeUpdate:@"UPDATE RemoteControlServers set transfercomplete = 1;"];
            [defs setInteger:1 forKey:@"keysettransfercompleteonce1"];
            [defs synchronize];
        }
        [self dbClose];
    }
}

- (ClipObject *)GetClipObjectForTrackURI:(NSString *)trackuri withfolderuri:(NSString *)folderuri {
    ClipObject *co = nil;
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT * FROM Mixxtapes WHERE spotifyid = ? AND spotifyfolderid = ? LIMIT 1", trackuri, folderuri];
        if ([rs next]) {
            co = [[ClipObject alloc] init];
            [self ReadCO:co withRSet:rs];
        }
        [rs close];
        [self dbClose];
    }
    return co;
}


// Port addition: the server ids found in the local library, most used first.
- (NSArray *)GetLibraryServerIDs {
    NSMutableArray *ids = [NSMutableArray array];
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT serverid, COUNT(*) AS c FROM MTFolders GROUP BY serverid ORDER BY c DESC"];
        while ([rs next]) [ids addObject:[NSNumber numberWithInt:[rs intForColumnIndex:0]]];
        [rs close];
        [self dbClose];
    }
    return ids;
}

// port addition: number of songs in the whole library (any server)
- (int)CountAllSongs {
    int n = 0;
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT COUNT(*) FROM Mixxtapes"];
        if ([rs next]) n = [rs intForColumnIndex:0];
        [rs close];
        [self dbClose];
    }
    return n;
}

// port additions for the Documents/Import importer
- (long long)MaxClipID {
    long long n = 0;
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT MAX(ID) FROM Mixxtapes"];
        if ([rs next]) n = [rs longLongIntForColumnIndex:0];
        [rs close];
        [self dbClose];
    }
    return n;
}

- (long long)MaxFolderID {
    long long n = 0;
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT MAX(folderid) FROM MTFolders"];
        if ([rs next]) n = [rs longLongIntForColumnIndex:0];
        [rs close];
        [self dbClose];
    }
    return n;
}

// folder id of a folder with this name on this server, or -1
- (long long)FolderIDForName:(NSString *)name serverid:(int)serverid {
    long long n = -1;
    if ([self dbOpen]) {
        FMResultSet *rs = [db executeQuery:@"SELECT folderid FROM MTFolders WHERE foldername = ? AND serverid = ? AND folderid >= 100", name, [NSNumber numberWithInt:serverid]];
        if ([rs next]) n = [rs longLongIntForColumnIndex:0];
        [rs close];
        [self dbClose];
    }
    return n;
}

// port addition: removes the "Test Songs" demo folder of earlier builds
- (void)DeleteDemoFolder {
    if ([self dbOpen]) {
        [db executeUpdate:@"DELETE FROM Mixxtapes WHERE folderid = 100 AND interpret LIKE 'Test Artist %'"];
        [db executeUpdate:@"DELETE FROM MTFolders WHERE folderid = 100 AND foldername = 'Test Songs'"];
        [self dbClose];
    }
}

// port addition: removes the demo rows an earlier build stored under the reserved folder id 1
- (void)DeleteLegacyDemoRows {
    if ([self dbOpen]) {
        [db executeUpdate:@"DELETE FROM Mixxtapes WHERE folderid = 1 AND interpret LIKE 'Test Artist %'"];
        [db executeUpdate:@"DELETE FROM MTFolders WHERE folderid = 1 AND foldername = 'Test Songs'"];
        [self dbClose];
    }
}
@end
