// FolderObject : NSObject  (recovered, instance size 60 on armv7)
#import <Foundation/Foundation.h>

@interface FolderObject : NSObject <NSCoding> {
    NSString *foldername;       // +4
    long long folderid;         // +8
    int serverid;               // +16
    int flags;                  // +20
    int autoselect;             // +24
    int timediff;               // +28
    char lastplayed;            // +32
    int excluded;               // +36
    NSString *limitations;      // +40
    int joinid;                 // +44
    long long ipodid;           // +48
    NSString *spotifyfolderid;  // +56
}
@property (nonatomic, retain) NSString *foldername;
@property (nonatomic, assign) long long folderid;
@property (nonatomic, assign) int serverid;
@property (nonatomic, assign) int flags;
@property (nonatomic, assign) int autoselect;
@property (nonatomic, assign) int timediff;
@property (nonatomic, assign) char lastplayed;
@property (nonatomic, assign) int excluded;
@property (nonatomic, retain) NSString *limitations;
@property (nonatomic, assign) int joinid;
@property (nonatomic, assign) long long ipodid;
@property (nonatomic, retain) NSString *spotifyfolderid;

- (NSInteger)compareIDs:(FolderObject *)other;
- (NSInteger)compareTimediffs:(FolderObject *)other;
@end
