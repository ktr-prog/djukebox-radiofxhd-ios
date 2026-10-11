// ServerEntry : NSObject  (recovered, instance size 148 on armv7)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ServerEntry : NSObject <NSCoding> {
    NSString *servername;  // +4
    NSString *lastpassword;  // +8
    int serverid;  // +12
    NSString *serverip;  // +16
    int choosen;  // +20
    int StateFlags;  // +24
    int reserved_i1;  // +28
    int reserved_i2;  // +32
    NSString *reserved_s1;  // +36
    NSString *reserved_s2;  // +40
    int useremote;  // +44
    NSString *remotesvr;  // +48
    NSString *remotepwd;  // +52
    int remoteserverid;  // +56
    NSString *browsedserver;  // +60
    NSString *browsedserverip;  // +64
    int browseid;  // +68
    BOOL isnewkeyentry;  // +72
    int trailerimagetime;  // +76
    NSString *displayname;  // +80
    NSString *remotecontrolpwd;  // +84
    int hosting;  // +88
    NSString *rcdeviceid;  // +92
    int origserverid;  // +96
    NSString *fbweekday;  // +100
    int adverttexttime;  // +104
    NSString *printerip;  // +108
    NSString *printfootertext;  // +112
    NSString *printheadertext;  // +116
    NSString *printheaderimage;  // +120
    NSString *printfooterimage;  // +124
    NSString *spotifyuser;  // +128
    NSString *spotifypassword;  // +132
    int m_useAmbience;  // +136
    int m_ambienceCollectionID;  // +140
    int m_songdragdelay;  // +144
}
@property (assign) int m_songdragdelay;
@property (assign) int m_ambienceCollectionID;
@property (assign) int m_useAmbience;
@property (nonatomic, retain) NSString *spotifypassword;
@property (nonatomic, retain) NSString *spotifyuser;
@property (nonatomic, retain) NSString *printfooterimage;
@property (nonatomic, retain) NSString *printheaderimage;
@property (nonatomic, retain) NSString *printheadertext;
@property (nonatomic, retain) NSString *printfootertext;
@property (nonatomic, retain) NSString *printerip;
@property (assign) int adverttexttime;
@property (nonatomic, retain) NSString *fbweekday;
@property (assign) int origserverid;
@property (nonatomic, retain) NSString *rcdeviceid;
@property (assign) int hosting;
@property (nonatomic, retain) NSString *remotecontrolpwd;
@property (nonatomic, retain) NSString *displayname;
@property (assign) int trailerimagetime;
@property (assign) BOOL isnewkeyentry;
@property (assign) int browseid;
@property (nonatomic, retain) NSString *browsedserverip;
@property (nonatomic, retain) NSString *browsedserver;
@property (assign) int remoteserverid;
@property (nonatomic, retain) NSString *remotepwd;
@property (nonatomic, retain) NSString *remotesvr;
@property (assign) int useremote;
@property (nonatomic, retain) NSString *reserved_s2;
@property (nonatomic, retain) NSString *reserved_s1;
@property (assign) int reserved_i2;
@property (assign) int reserved_i1;
@property (assign) int StateFlags;
@property (assign) int choosen;
@property (nonatomic, retain) NSString *serverip;
@property (assign) int serverid;
@property (nonatomic, retain) NSString *lastpassword;
@property (nonatomic, retain) NSString *servername;
- (void)dealloc;
- (id)initWithCoder:(NSCoder *)coder;
- (void)encodeWithCoder:(NSCoder *)coder;
- (id)init;
@end
