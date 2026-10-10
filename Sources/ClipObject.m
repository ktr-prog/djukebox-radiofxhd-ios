// Recovered from -[ClipObject ...] @0x1c908..0x1d0fe
#import "ClipObject.h"

@implementation ClipObject
@synthesize m_filepath, m_interpret, m_title, ID, m_imgv, m_swapimgv, m_imgvtext, m_picturepath;
@synthesize m_folderid, m_albumname, m_tracknumber, m_tracks, m_duration, m_information;
@synthesize m_starttime, m_channelid, m_epgid, m_filename, m_channel, m_genre, m_filesize;
@synthesize m_serverid, m_ipodid, m_folderipodid, m_spotifyid, m_spotifyfolderid, m_albumid;

- (id)init {
    self = [super init];
    if (self) {
        m_imgv = nil;
        m_imgvtext = nil;
        m_filepath = nil;
        m_folderid = -1;
        m_interpret = nil;
        m_title = nil;
        ID = 0;
        m_picturepath = nil;
        m_albumname = nil;
        m_albumid = 0;
        m_tracknumber = 0;
        m_tracks = nil;
        m_duration = 0;
        m_information = nil;
        m_starttime = 0;
        m_channelid = -1;
        m_epgid = 0;
        m_filename = nil;
        m_channel = nil;
        m_genre = nil;
        m_filesize = 0;
        m_serverid = -1;
        m_swapimgv = nil;
        m_folderipodid = 0;
        m_ipodid = 0;
        m_spotifyid = nil;
        m_spotifyfolderid = nil;
    }
    return self;
}

- (void)dealloc {
    if (m_filepath) { [m_filepath release]; m_filepath = nil; }
    if (m_interpret) { [m_interpret release]; m_interpret = nil; }
    if (m_title) { [m_title release]; m_title = nil; }
    if (m_picturepath) { [m_picturepath release]; m_picturepath = nil; }
    if (m_albumname) { [m_albumname release]; m_albumname = nil; }
    if (m_tracks) { [m_tracks release]; m_tracks = nil; }
    if (m_information) { [m_information release]; m_information = nil; }
    if (m_filename) { [m_filename release]; m_filename = nil; }
    if (m_channel) { [m_channel release]; m_channel = nil; }
    if (m_genre) { [m_genre release]; m_genre = nil; }
    if (m_spotifyid) { [m_spotifyid release]; m_spotifyid = nil; }
    if (m_spotifyfolderid) { [m_spotifyfolderid release]; m_spotifyfolderid = nil; }
    [super dealloc];
}

- (NSInteger)compareTitles:(ClipObject *)other {
    return [[self m_title] caseInsensitiveCompare:[other m_title]];
}

- (NSInteger)compareTracknumbers:(ClipObject *)other {
    if ([self m_tracknumber] == [other m_tracknumber]) return 0;
    return ([self m_tracknumber] > [other m_tracknumber]) ? 1 : -1;
}
@end
