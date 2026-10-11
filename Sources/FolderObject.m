// Recovered from -[FolderObject ...] @0x1d3d8..0x1db48
#import "FolderObject.h"

@implementation FolderObject
@synthesize foldername, folderid, serverid, flags, autoselect, timediff, lastplayed;
@synthesize excluded, limitations, joinid, ipodid, spotifyfolderid;

- (id)init {
    self = [super init];
    if (self) {
        foldername = nil;
        folderid = 0;
        serverid = 0;
        autoselect = 0;
        flags = 0;
        timediff = 0;
        lastplayed = 0;
        excluded = 0;
        limitations = nil;
        joinid = 0;
        ipodid = 0;
        spotifyfolderid = nil;
    }
    return self;
}

- (void)dealloc {
    if (foldername)       { [foldername release];       foldername = nil; }
    if (limitations)      { [limitations release];      limitations = nil; }
    if (spotifyfolderid)  { [spotifyfolderid release];  spotifyfolderid = nil; }
    [super dealloc];
}

// Folders with id -44 are sorted by ipodid, everything else by folderid.
- (NSInteger)compareTimediffs:(FolderObject *)other {
    if (timediff == [other timediff]) return 0;
    return timediff > [other timediff] ? 1 : -1;
}

- (NSInteger)compareIDs:(FolderObject *)other {
    if ([self folderid] == -44 && [other folderid] == -44) {
        long long a = [self ipodid], b = [other ipodid];
        if (a == b) return 0;
        return (a > b) ? 1 : -1;
    }
    long long a = [self folderid], b = [other folderid];
    if (a == b) return 0;
    return (a > b) ? 1 : -1;
}

- (id)initWithCoder:(NSCoder *)coder {
    // Original: [[FolderObject alloc] init] returned instead of self.
    FolderObject *o = [[FolderObject alloc] init];
    [o setFoldername:[coder decodeObjectForKey:@"foldername"]];
    [o setFolderid:[coder decodeInt64ForKey:@"folderid"]];
    [o setServerid:[coder decodeIntForKey:@"serverid"]];
    // original called decodeObjectForKey: here although encodeWithCoder: wrote an int
    [o setAutoselect:[coder decodeIntForKey:@"autoselect"]];
    [o setFlags:[coder decodeIntForKey:@"flags"]];
    [o setLastplayed:(char)[coder decodeIntForKey:@"lastplayed"]];
    [o setExcluded:[coder decodeIntForKey:@"excluded"]];
    [o setLimitations:[coder decodeObjectForKey:@"limitations"]];
    [o setJoinid:[coder decodeIntForKey:@"joinid"]];
    [o setIpodid:[coder decodeInt64ForKey:@"ipodid"]];
    [o setSpotifyfolderid:[coder decodeObjectForKey:@"spotifyfolderid"]];
    return o;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:foldername forKey:@"foldername"];
    [coder encodeInt64:folderid forKey:@"folderid"];
    [coder encodeInt:serverid forKey:@"serverid"];
    [coder encodeInt:autoselect forKey:@"autoselect"];
    [coder encodeInt:flags forKey:@"flags"];
    [coder encodeInt:lastplayed forKey:@"lastplayed"];
    [coder encodeInt:excluded forKey:@"excluded"];
    [coder encodeObject:limitations forKey:@"limitations"];
    [coder encodeInt:joinid forKey:@"joinid"];
    [coder encodeInt64:ipodid forKey:@"ipodid"];
    [coder encodeObject:spotifyfolderid forKey:@"spotifyfolderid"];
}
@end
