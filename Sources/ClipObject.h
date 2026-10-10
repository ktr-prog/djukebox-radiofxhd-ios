// ClipObject : NSObject  (recovered, instance size 140 on armv7)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ClipObject : NSObject {
    NSString *m_filepath;           // +4
    NSString *m_interpret;          // +8
    NSString *m_title;              // +12
    long long ID;                   // +16
    UIImageView *m_imgv;            // +24
    UIImageView *m_swapimgv;        // +28
    UIImageView *m_imgvtext;        // +32
    NSString *m_picturepath;        // +36
    long long m_folderid;           // +40
    long long albumid;              // +48 (unused ivar, no property)
    NSString *m_albumname;          // +56
    int m_tracknumber;              // +60
    NSMutableArray *m_tracks;       // +64
    int m_duration;                 // +68
    NSString *m_information;        // +72
    int m_starttime;                // +76
    int m_channelid;                // +80
    int m_epgid;                    // +84
    NSString *m_filename;           // +88
    NSString *m_channel;            // +92
    NSString *m_genre;              // +96
    unsigned long m_filesize;       // +100 (4 bytes on armv7)
    int m_serverid;                 // +104
    long long m_ipodid;             // +108
    long long m_folderipodid;       // +116
    NSString *m_spotifyid;          // +124
    NSString *m_spotifyfolderid;    // +128
    long long m_albumid;            // +132
}
@property (nonatomic, retain) NSString *m_filepath;
@property (nonatomic, retain) NSString *m_interpret;
@property (nonatomic, retain) NSString *m_title;
@property (nonatomic, assign) long long ID;
@property (nonatomic, assign) UIImageView *m_imgv;
@property (nonatomic, assign) UIImageView *m_swapimgv;
@property (nonatomic, assign) UIImageView *m_imgvtext;
@property (nonatomic, retain) NSString *m_picturepath;
@property (nonatomic, assign) long long m_folderid;
@property (nonatomic, retain) NSString *m_albumname;
@property (nonatomic, assign) int m_tracknumber;
@property (nonatomic, assign) NSMutableArray *m_tracks;
@property (nonatomic, assign) int m_duration;
@property (nonatomic, retain) NSString *m_information;
@property (nonatomic, assign) int m_starttime;
@property (nonatomic, assign) int m_channelid;
@property (nonatomic, assign) int m_epgid;
@property (nonatomic, retain) NSString *m_filename;
@property (nonatomic, retain) NSString *m_channel;
@property (nonatomic, retain) NSString *m_genre;
@property (nonatomic, assign) unsigned long m_filesize;
@property (nonatomic, assign) int m_serverid;
@property (nonatomic, assign) long long m_ipodid;
@property (nonatomic, assign) long long m_folderipodid;
@property (nonatomic, retain) NSString *m_spotifyid;
@property (nonatomic, retain) NSString *m_spotifyfolderid;
@property (nonatomic, assign) long long m_albumid;

- (NSInteger)compareTitles:(ClipObject *)other;
- (NSInteger)compareTracknumbers:(ClipObject *)other;
@end
