// Recovered from class MultichannelMixerController (armv7 @0xbdd10..0xbf2c8).
// Derived from Apple's MultichannelMixer sample: 5 mixer buses (0/1 = main crossfade pair,
// 2 = preview/"pre-play", 3/4 unused), each fed from a double-buffered ExtAudioFile reader thread.
//
// 64-bit notes: the original embedded the five 3.2 MB SoundBuffers directly in the object
// (16 MB instance) and used a C++ CAStreamBasicDescription helper; both are replaced by an
// equivalent calloc'd array and plain C functions. Behaviour is unchanged.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <pthread.h>

#define kMCMNumBuses       5
#define kMCMBufFrames      100000          // SInt32 samples per channel-plane pair, per half buffer
#define kMCMPlaneSamples   200000          // offset of the right-channel plane inside data[x]

typedef struct SoundBuffer {
    AudioStreamBasicDescription asbd;
    SInt32   data[2][400000];              // two halves; [left plane | right plane]
    UInt32   BufNo;                        // half currently being rendered
    Boolean  inUse[2];                     // half filled by the reader thread, not yet consumed
    UInt32   numFrames;                    // frames per half
    UInt32   sampleNum;                    // render cursor
    Boolean  isStereo;
    Boolean  mMixBus;
} SoundBuffer;

@interface MultichannelMixerController : NSObject {
    BOOL mPlayMono;
    BOOL mAllowPrePlay;
    CFURLRef sourceURL[kMCMNumBuses];
    ExtAudioFileRef mxafref[kMCMNumBuses];
    pthread_mutex_t mMutexExtAudioFileRead;
    int mDuration[kMCMNumBuses];
    AUGraph mGraph;
    AudioUnit mMixer;
    SoundBuffer *mSoundBuffer;             // kMCMNumBuses entries
    unsigned char isPlaying;
    int mBus;
    int m_playid[kMCMNumBuses];
}
@property (nonatomic, readonly) unsigned char isPlaying;

- (int)duration;
- (BOOL)GetAllowPreplay;
- (void)setAllowPrePlay:(BOOL)value;
- (void)setPlayStereo;
- (void)setPlayMono;
- (BOOL)GetPlayMono;
- (void)stopAUGraph;
- (void)startAUGraph;
- (void)setOutputVolume:(float)value;
- (float)getOutputVolume;
- (void)setInputVolume:(float)value;
- (void)setInputVolume:(unsigned long)inputVolume value:(float)value;
- (float)getInputVolume;
- (void)enableMixBusInput:(unsigned long)bus isOn:(BOOL)isOn;
- (void)enableInput:(unsigned long)bus isOn:(float)isOn;
- (void)StopPreplay;
- (void)StopPlayingBus:(int)bus;
- (void)PlayPrePlay:(id)clip;              // ClipObject *
- (void)FadeOut:(float)seconds;
- (void)FadeOutInBackground:(id)seconds;
- (void)PlayFile:(id)file atBus:(int)bus;
- (void)PlayFile:(id)file widthCrossfadeTime:(float)t inSteps:(int)steps;
- (int)GetNextBus;
- (int)GetCurrentBus;
- (void)PlayFileInBackground:(id)bus;
- (void)ErrorPlayingFile:(int)bus;
- (void)setupMonoStreamFormat:(AudioStreamBasicDescription *)asbd;
- (void)setupStereoStreamFormat:(AudioStreamBasicDescription *)asbd;
- (OSStatus)initializeAUGraph;
- (void)initAudioSession;
@end
