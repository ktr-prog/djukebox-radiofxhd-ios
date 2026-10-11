// ServerComm -- decompiled from Radiofx_iPad (armv7), server-list part only.
#import "ServerComm.h"
#import "ServerEntry.h"
#import "DBOperations.h"
#import "RadioAppDelegate.h"

@implementation ServerComm
@synthesize m_serverEntryList, m_groupflags;

- (void)dealloc {
    if (m_nspw != nil) { [m_nspw release]; m_nspw = nil; }
    if (m_serverEntryList != nil) { [m_serverEntryList release]; m_serverEntryList = nil; }
    if (m_initgroup != nil) { [m_initgroup release]; m_initgroup = nil; }
    [super dealloc];
}

- (void)InitObject {
    m_nspw = nil;
    m_initgroup = nil;
    m_groupflags = 0;
    m_serverEntryList = [[NSMutableArray alloc] init];
    [self LoadServerList];
}

- (void)LoadServerList {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [[self m_serverEntryList] removeAllObjects];
    NSArray *list = [defs arrayForKey:@"keyserverlist"];
    if (list == nil || [list count] == 0) return;
    for (NSUInteger i = 0; i < [list count]; i++) {
        ServerEntry *se = [self decodeServerEntry:[list objectAtIndex:i]];
        if (se == nil) continue;
        [[self m_serverEntryList] addObject:se];
        [se setStateFlags:[(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] ModifyStateFlags:[se StateFlags]]];
    }
}

- (void)SaveServerList {
    NSMutableArray *packed = [self GetPacketServerArray:0];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if (defs != nil) {
        [defs setObject:packed forKey:@"keyserverlist"];
        [defs synchronize];
    }
    [packed release];
}

// The original returns a +1 array (alloc/init); the caller releases it.
- (NSMutableArray *)GetPacketServerArray:(int)forWire {
    NSMutableArray *a = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < [[self m_serverEntryList] count]; i++)
        [a addObject:[self encodeServerEntry:[[self m_serverEntryList] objectAtIndex:i]]];
    return a;
}

- (id)encodeServerEntry:(ServerEntry *)serverEntry {
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *ar = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [ar encodeObject:serverEntry forKey:@"ServerEntry"];
    [ar finishEncoding];
    [ar release];
    return data;
}

- (ServerEntry *)decodeServerEntry:(NSData *)data {
    NSKeyedUnarchiver *un = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [un setRequiresSecureCoding:NO];
    ServerEntry *se = [un decodeObjectForKey:@"ServerEntry"];
    [un release];
    return se;
}

- (int)GetHighestServerID {
    int best = 0;
    for (NSUInteger i = 0; i < [[self m_serverEntryList] count]; i++) {
        int sid = [[[self m_serverEntryList] objectAtIndex:i] serverid];
        if (sid > best) best = sid;
    }
    return best;
}

- (ServerEntry *)GetServerWithID:(int)serverID {
    for (NSUInteger i = 0; i < [[self m_serverEntryList] count]; i++) {
        ServerEntry *se = [[self m_serverEntryList] objectAtIndex:i];
        if ([se serverid] == serverID) return se;
    }
    return nil;
}

- (BOOL)AddMTServer:(ServerEntry *)server {
    [server setServerid:[self GetHighestServerID] + 1];
    [[self m_serverEntryList] addObject:server];
    return YES;
}

- (NSMutableArray *)getMTServer { return [self m_serverEntryList]; }
- (NSMutableArray *)GetListPointer { return m_serverEntryList; }

// Returns a +1 copy, like the original (callers release it).
- (ServerEntry *)GetChoosenRfxServer:(id)rcDeviceID {
    for (NSUInteger i = 0; i < [[self m_serverEntryList] count]; i++) {
        ServerEntry *se = [[self m_serverEntryList] objectAtIndex:i];
        if ([se choosen] == 1) {
            ServerEntry *copy = [[ServerEntry alloc] init];
            [self CopyPropertiesFromServer:se toServer:copy];
            return copy;
        }
    }
    return nil;
}

#define CPSTR(prop, setter) if ([from prop] != nil) [to setter:[NSString stringWithFormat:@"%@", [from prop]]];

- (void)CopyPropertiesFromServer:(ServerEntry *)from toServer:(ServerEntry *)to {
    CPSTR(servername, setServername)
    CPSTR(lastpassword, setLastpassword)
    CPSTR(serverip, setServerip)
    CPSTR(reserved_s1, setReserved_s1)
    CPSTR(reserved_s2, setReserved_s2)
    [to setServerid:[from serverid]];
    [to setChoosen:[from choosen]];
    [to setReserved_i1:[from reserved_i1]];
    [to setReserved_i2:[from reserved_i2]];
    [to setStateFlags:[from StateFlags]];
    CPSTR(remotepwd, setRemotepwd)
    CPSTR(remotesvr, setRemotesvr)
    [to setUseremote:[from useremote]];
    [to setRemoteserverid:[from remoteserverid]];
    [to setBrowseid:[from browseid]];
    CPSTR(browsedserver, setBrowsedserver)
    CPSTR(browsedserverip, setBrowsedserverip)
    [to setTrailerimagetime:[from trailerimagetime]];
    CPSTR(displayname, setDisplayname)
    CPSTR(remotecontrolpwd, setRemotecontrolpwd)
    [to setHosting:[from hosting]];
    [to setOrigserverid:[from origserverid]];
    CPSTR(rcdeviceid, setRcdeviceid)
    CPSTR(fbweekday, setFbweekday)
    [to setAdverttexttime:[from adverttexttime]];
    CPSTR(printerip, setPrinterip)
    CPSTR(printfootertext, setPrintfootertext)
    CPSTR(printheadertext, setPrintheadertext)
    CPSTR(printheaderimage, setPrintheaderimage)
    CPSTR(printfooterimage, setPrintfooterimage)
    CPSTR(spotifyuser, setSpotifyuser)
    CPSTR(spotifypassword, setSpotifypassword)
    [to setM_useAmbience:[from m_useAmbience]];
    [to setM_ambienceCollectionID:[from m_ambienceCollectionID]];
    [to setM_songdragdelay:[from m_songdragdelay]];
}

- (NSString *)getNameForServer:(int)serverID {
    ServerEntry *se = [self GetServerWithID:serverID];
    if (se == nil || [se servername] == nil) return @"";
    return [NSString stringWithFormat:@"%@", [se servername]];
}

- (NSString *)getPasswordForServer:(ServerEntry *)server {
    ServerEntry *se = [self GetServerWithID:[server serverid]];
    if (se == nil || [se lastpassword] == nil) return nil;
    return [NSString stringWithFormat:@"%@", [se lastpassword]];
}

- (BOOL)UpdateMTServer:(ServerEntry *)server {
    ServerEntry *se = [self GetServerWithID:[server serverid]];
    if (se == nil) return NO;
    [self CopyPropertiesFromServer:server toServer:se];
    [self SaveServerList];
    return YES;
}

- (BOOL)UpdateStateFlags:(int)flags withServerID:(int)serverID {
    ServerEntry *se = [self GetServerWithID:serverID];
    if (se == nil) return NO;
    [se setStateFlags:flags];
    [self SaveServerList];
    return YES;
}

- (BOOL)DeleteMTServer:(ServerEntry *)server {
    int wasChoosen = [server choosen];
    DBOperations *dbop = [[DBOperations alloc] init];
    [dbop DeleteMTServerDB:server];
    [dbop release];
    for (NSInteger i = (NSInteger)[[self m_serverEntryList] count] - 1; i >= 0; i--) {
        if ([server serverid] == [[[self m_serverEntryList] objectAtIndex:i] serverid])
            [[self m_serverEntryList] removeObjectAtIndex:i];
    }
    if (wasChoosen == 1) {
        NSMutableArray *rest = [self getMTServer];
        if ([rest count] != 0) [[rest objectAtIndex:0] setChoosen:1];
    }
    [self SaveServerList];
    return YES;
}

// Port addition: a library copied from the original app carries the server id of the (now dead) server it
// was synced with.  If the chosen server entry uses a different id nothing would be listed, so the entry
// adopts the id the library actually uses.  Returns YES if the entry was changed.
- (BOOL)AdaptToLocalLibrary {
    ServerEntry *chosen = nil;
    for (NSUInteger i = 0; i < [[self m_serverEntryList] count]; i++) {
        ServerEntry *se = [[self m_serverEntryList] objectAtIndex:i];
        if ([se choosen] == 1) { chosen = se; break; }
    }
    if (chosen == nil) return NO;
    RadioAppDelegate *ad = (RadioAppDelegate *)[[UIApplication sharedApplication] delegate];
    [ad LockDB:NO];
    DBOperations *db = [[DBOperations alloc] init];
    NSArray *ids = [db GetLibraryServerIDs];
    [db release];
    [ad UnlockDB];
    if ([ids count] == 0) return NO;
    for (NSNumber *n in ids)
        if ([n intValue] == [chosen serverid]) return NO;
    [chosen setServerid:[[ids objectAtIndex:0] intValue]];
    [self SaveServerList];
    return YES;
}
@end
