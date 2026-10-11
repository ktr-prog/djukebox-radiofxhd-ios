// ServerComm : NSObject  (recovered; armv7 size 36)
// Reduced to the server-list bookkeeping.  All network code (StartConnection:, GetRfxFolders:,
// GetServerStateFlags:..., EPG, adverts, Spotify/Facebook data, remote-control packets, ...) is dropped
// because the backend no longer exists; see DEVIATIONS.md.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class ServerEntry;

@interface ServerComm : NSObject {
    NSMutableArray *m_serverEntryList;
    NSString *m_nspw;
    NSString *m_initgroup;
    int m_groupflags;
}
@property (nonatomic, retain) NSMutableArray *m_serverEntryList;
@property (assign) int m_groupflags;

- (void)InitObject;
- (void)LoadServerList;
- (void)SaveServerList;
- (NSMutableArray *)GetPacketServerArray:(int)forWire;
- (id)encodeServerEntry:(ServerEntry *)serverEntry;
- (ServerEntry *)decodeServerEntry:(NSData *)data;
- (int)GetHighestServerID;
- (ServerEntry *)GetServerWithID:(int)serverID;
- (BOOL)AddMTServer:(ServerEntry *)server;
- (NSMutableArray *)getMTServer;
- (NSMutableArray *)GetListPointer;
- (ServerEntry *)GetChoosenRfxServer:(id)rcDeviceID;
- (void)CopyPropertiesFromServer:(ServerEntry *)from toServer:(ServerEntry *)to;
- (NSString *)getNameForServer:(int)serverID;
- (NSString *)getPasswordForServer:(ServerEntry *)server;
- (BOOL)UpdateMTServer:(ServerEntry *)server;
- (BOOL)UpdateStateFlags:(int)flags withServerID:(int)serverID;
- (BOOL)DeleteMTServer:(ServerEntry *)server;
- (BOOL)AdaptToLocalLibrary;   // port addition, see DEVIATIONS.md
@end
