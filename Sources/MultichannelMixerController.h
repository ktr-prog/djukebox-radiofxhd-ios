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

// DEVIATION: the original double buffer (two halves flipped by the render callback, no handshake with the
// reader thread) glitched on current iOS.  Each bus now owns a single-producer / single-consumer ring buffer:
// data[0] = left plane, data[1] = right plane (Float32 samples), wpos/rpos are monotonically increasing frame
// counters (reader thread writes wpos, render callback writes rpos).
#define kMCMRingFrames     262144          // power of two, <= 400000
typedef struct SoundBuffer {
    AudioStreamBasicDescription asbd;
    SInt32   data[2][400000];              // ring planes (Float32 bit patterns)
    volatile UInt32 wpos;                  // frames written by the reader thread
    volatile UInt32 rpos;                  // frames consumed by the render callback
    UInt32   BufNo;                        // unused (kept from the original layout)
    Boolean  inUse[2];                     // unused
    UInt32   numFrames;                    // unused
    UInt32   sampleNum;                    // unused
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
    volatile int m_gen[kMCMNumBuses];      // play generation per bus: a reader thread only touches its own generation
    volatile int m_fadeSerial;             // newest crossfade wins when requests overlap
    double mGraphRate;                     // sample rate of the whole graph (= hardware rate)
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
