// Recovered from -[MultichannelMixerController ...] @0xbdd10..0xbf2c8 and C helper renderInput @0xbdbb4.
#import <math.h>
#import "MultichannelMixerController.h"
#import "ClipObject.h"
#import "RadioAppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#include <unistd.h>
#include <string.h>

// One mutex per bus (global in the original: data_00398850, stride 0x2c on armv7)
static pthread_mutex_t gBusMutex[kMCMNumBuses];

// 8.24 fixed-point, non-interleaved "AudioUnit canonical" format (kAudioFormatFlagsAudioUnitCanonical).
// Literal value used by the original because the constant is deprecated in newer SDKs.
#define kMCMFormatFlags (kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved)  // DEVIATION: was 8.24 (0xc2c)

// ---- C++ CAStreamBasicDescription helpers (0xbdb68 / 0xbf28c) as plain C --------------------
static UInt32 MCM_SampleWordSize(const AudioStreamBasicDescription *d) {
    if (d->mBytesPerFrame == 0) return 0;
    if (d->mFormatID == kAudioFormatLinearPCM && (d->mFormatFlags & kAudioFormatFlagIsNonInterleaved))
        return d->mBytesPerFrame;
    if (d->mChannelsPerFrame == 0) return 0;
    return d->mBytesPerFrame / d->mChannelsPerFrame;
}

static void MCM_ChangeNumberChannels(AudioStreamBasicDescription *d, UInt32 nChannels, bool interleaved) {
    UInt32 wordSize = MCM_SampleWordSize(d);
    if (wordSize == 0) wordSize = (d->mBitsPerChannel + 7) / 8;
    d->mChannelsPerFrame = nChannels;
    d->mFramesPerPacket = 1;
    if (interleaved) {
        d->mBytesPerPacket = d->mBytesPerFrame = nChannels * wordSize;
        d->mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved;
    } else {
        d->mBytesPerPacket = d->mBytesPerFrame = wordSize;
        d->mFormatFlags |= kAudioFormatFlagIsNonInterleaved;
    }
}

// Float32, 2 channels, non-interleaved, 44.1 kHz (what the iOS multichannel mixer accepts)
static void MCM_FloatFormat(AudioStreamBasicDescription *d, double rate) {
    memset(d, 0, sizeof(*d));
    d->mFormatID = kAudioFormatLinearPCM;
    d->mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    d->mSampleRate = rate;
    d->mChannelsPerFrame = 2;
    d->mFramesPerPacket = 1;
    d->mBitsPerChannel = 32;
    d->mBytesPerFrame = 4;
    d->mBytesPerPacket = 4;
}

// the engine / hardware rate the app asks for (every title is 44.1 kHz, so nothing is resampled)
#define kMCMFixedRate 44100.0

volatile float gRfxBeatBus[kMCMNumBuses];
static float gRfxLP[kMCMNumBuses];
volatile float gRfxBeatMax = 0.0f;       // loudest bass peak since the last RfxBeatTake (nothing between two frames gets lost)
float RfxBeatTake(void) { float m = gRfxBeatMax; gRfxBeatMax = 0.0f; return m; }
float RfxBeatLevel(void) { float m = 0; for (int i = 0; i < kMCMNumBuses; i++) if (gRfxBeatBus[i] > m) m = gRfxBeatBus[i]; return m; }

// ---- Render callback (@0xbdbb4) -------------------------------------------------------------
// refcon points at mSoundBuffer[0]; the bus number selects the entry.
static OSStatus renderInput(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
                            UInt32 inNumberFrames, AudioBufferList *ioData) {
    SoundBuffer *sb = (SoundBuffer *)inRefCon + inBusNumber;
    if (inNumberFrames == 0) return 0;

    float *outA = (float *)ioData->mBuffers[0].mData;
    float *outB = (float *)ioData->mBuffers[1].mData;
    const float *ringL = (const float *)sb->data[0];
    const float *ringR = (const float *)sb->data[1];

    UInt32 w = __atomic_load_n(&sb->wpos, __ATOMIC_ACQUIRE);
    UInt32 r = sb->rpos;
    UInt32 avail = w - r;
    if (avail > kMCMRingFrames) avail = 0;      // inconsistent (bus is being reset): play silence
    UInt32 take = (avail < inNumberFrames) ? avail : inNumberFrames;
    float lp = (inBusNumber < kMCMNumBuses) ? gRfxLP[inBusNumber] : 0.0f, pk = 0.0f;

    for (UInt32 i = 0; i < inNumberFrames; i++) {
        float l = 0.0f, rv = 0.0f;
        if (i < take) {
            UInt32 idx = (r + i) & (kMCMRingFrames - 1);
            l = ringL[idx];
            rv = ringR[idx];
        }
        lp += 0.03f * (0.5f * (l + rv) - lp);                 // one-pole low-pass (~200 Hz): kick / bass
        if (fabsf(lp) > pk) pk = fabsf(lp);
        if (inBusNumber < 2) {
            outA[i] = l;
            outB[i] = sb->isStereo ? rv : (sb->mMixBus ? l : 0.0f);
        } else if (sb->mMixBus) {
            outA[i] = l;
            outB[i] = sb->isStereo ? rv : l;
        } else if (sb->isStereo) {
            outA[i] = l;
            outB[i] = rv;
        } else {
            outA[i] = 0.0f;
            outB[i] = l;
        }
    }
    if (inBusNumber < kMCMNumBuses) { gRfxLP[inBusNumber] = lp; gRfxBeatBus[inBusNumber] = pk; if (pk > gRfxBeatMax) gRfxBeatMax = pk; }
    if (take != 0) __atomic_store_n(&sb->rpos, r + take, __ATOMIC_RELEASE);
    return 0;
}

static void MCM_Status(NSString *text) {
    NSLog(@"[MCM] %@", text);       // on-screen status window removed (log only)
}
static BOOL gMCMReported = NO;   // report only the first play attempt

@implementation MultichannelMixerController
@synthesize isPlaying;

- (id)init {
    self = [super init];
    if (self) {
        mGraph = NULL;
        mSoundBuffer = (SoundBuffer *)calloc(kMCMNumBuses, sizeof(SoundBuffer));
        for (int i = 0; i < kMCMNumBuses; i++) {
            pthread_mutex_init(&gBusMutex[i], NULL);
            sourceURL[i] = NULL;
        }
        pthread_mutex_init(&mMutexExtAudioFileRead, NULL);
        [self initAudioSession];
        mBus = 0;
        [self setPlayStereo];
        [self setAllowPrePlay:NO];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (mGraph) DisposeAUGraph(mGraph);
    for (int i = 0; i < kMCMNumBuses; i++) {
        pthread_mutex_destroy(&gBusMutex[i]);
        if (sourceURL[i]) CFRelease(sourceURL[i]);
    }
    pthread_mutex_destroy(&mMutexExtAudioFileRead);
    free(mSoundBuffer);
    [super dealloc];
}

// ---- bit-perfect bookkeeping -----------------------------------------------------------------
// The graph always runs at 44.1 kHz (CD rate) and the session is asked for 44.1 kHz again on every route change; on AirPlay 1
// (ALAC 44.1/16) the route then runs at exactly that rate, so CD-quality titles pass untouched.  Volume stays at 1.0 when the
// dev switch "Lautstärke dem System überlassen" is on (default), so no sample is scaled outside a crossfade.
- (void)AdaptGraphToRate:(double)rate forBus:(int)bus {
    (void)rate; (void)bus;      // the engine rate is fixed; titles of another rate are converted once (best quality) on load
}

- (NSString *)RouteName {
    AVAudioSessionRouteDescription *rt = [[AVAudioSession sharedInstance] currentRoute];
    AVAudioSessionPortDescription *o = [[rt outputs] firstObject];
    if (o == nil) return @"-";
    NSString *t = [o portType];
    if ([t isEqualToString:AVAudioSessionPortAirPlay]) return @"AirPlay";
    if ([t isEqualToString:AVAudioSessionPortBuiltInSpeaker]) return @"Lautsprecher";
    if ([t isEqualToString:AVAudioSessionPortUSBAudio]) return @"USB";
    if ([t isEqualToString:AVAudioSessionPortHeadphones]) return @"Kopfhörer";
    if ([t hasPrefix:@"Bluetooth"]) return @"Bluetooth";
    return t;
}

- (void)PostRateInfoForFile:(double)fileHz {
    double hwHz = [[AVAudioSession sharedInstance] sampleRate];
    BOOL clean = (fileHz <= 0 || fabs(fileHz - mGraphRate) < 1.0) && fabs(mGraphRate - hwHz) < 1.0;
    NSString *info = [NSString stringWithFormat:@"file %@  |  engine %.0f  |  device %.0f Hz  |  %@%@",
                      fileHz > 0 ? [NSString stringWithFormat:@"%.0f", fileHz] : @"-", mGraphRate, hwHz, [self RouteName],
                      clean ? @"  (bit-perfect path)" : @"  (resampled)"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"RfxSampleRateInfo" object:nil userInfo:[NSDictionary dictionaryWithObject:info forKey:@"text"]];
    });
}

- (void)RouteChanged:(NSNotification *)n {
    AVAudioSession *as = [AVAudioSession sharedInstance];
    [as setPreferredSampleRate:kMCMFixedRate error:nil];
    [as setActive:YES error:nil];
    [self PostRateInfoForFile:0];
}

- (void)initAudioSession {
    isPlaying = 0;
    memset(mSoundBuffer, 0, kMCMNumBuses * sizeof(SoundBuffer));
    for (int i = 0; i < kMCMNumBuses; i++) {
        mxafref[i] = NULL;
        mDuration[i] = 0;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(RouteChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
    OSStatus gr = [self initializeAUGraph];
    if (gr != noErr) { gMCMReported = YES; MCM_Status([NSString stringWithFormat:@"audio graph setup failed: %d", (int)gr]); }
}

// ---- trivial accessors ---------------------------------------------------------------------
- (BOOL)GetPlayMono { return mPlayMono; }
- (void)setPlayMono { mPlayMono = YES; }
- (void)setPlayStereo { mPlayMono = NO; }
- (void)setAllowPrePlay:(BOOL)value { mAllowPrePlay = value; }
- (BOOL)GetAllowPreplay { return mAllowPrePlay; }
- (int)GetCurrentBus { return mBus; }
- (int)GetNextBus {
    mBus++;
    if (mBus >= 2) mBus = 0;
    return mBus;
}
- (int)duration { return mDuration[[self GetCurrentBus]]; }

- (void)enableMixBusInput:(unsigned long)bus isOn:(BOOL)isOn {
    mSoundBuffer[bus].mMixBus = isOn;
}

// ---- stream formats ------------------------------------------------------------------------
- (void)setupStereoStreamFormat:(AudioStreamBasicDescription *)d {
    d->mFormatID = kAudioFormatLinearPCM;
    d->mFormatFlags = kMCMFormatFlags;
    d->mSampleRate = (mGraphRate > 0) ? mGraphRate : 44100.0;
    d->mBytesPerPacket = 4;
    d->mFramesPerPacket = 1;
    d->mBytesPerFrame = 4;
    d->mChannelsPerFrame = 2;
    d->mBitsPerChannel = 32;
}

- (void)setupMonoStreamFormat:(AudioStreamBasicDescription *)d {
    d->mFormatID = kAudioFormatLinearPCM;
    d->mFormatFlags = kMCMFormatFlags;
    d->mSampleRate = (mGraphRate > 0) ? mGraphRate : 44100.0;
    d->mBytesPerPacket = 4;
    d->mFramesPerPacket = 1;
    d->mBytesPerFrame = 4;
    d->mChannelsPerFrame = 1;
    d->mBitsPerChannel = 32;
}

// ---- graph ---------------------------------------------------------------------------------
- (OSStatus)initializeAUGraph {
    AudioStreamBasicDescription desc;
    memset(&desc, 0, sizeof(desc));
    OSStatus r;
    // The graph runs at the hardware rate, so a file is resampled at most once (and not at all when it already
    // has that rate); everything inside is 32-bit float.
    [[AVAudioSession sharedInstance] setPreferredSampleRate:kMCMFixedRate error:nil];    // ask for 44.1 kHz right away
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    // DEVIATION: the engine always runs at 44.1 kHz.  When the hardware stays at 48 kHz the system converts at the very end
    // (RemoteIO); the app itself never resamples 44.1 kHz titles.
    mGraphRate = kMCMFixedRate;

    AUNode outputNode, mixerNode;
    AudioComponentDescription outDesc = { kAudioUnitType_Output, kAudioUnitSubType_RemoteIO, kAudioUnitManufacturer_Apple, 0, 0 };
    AudioComponentDescription mixDesc = { kAudioUnitType_Mixer, kAudioUnitSubType_MultiChannelMixer, kAudioUnitManufacturer_Apple, 0, 0 };

    if ((r = NewAUGraph(&mGraph))) return r;
    if ((r = AUGraphAddNode(mGraph, &outDesc, &outputNode))) return r;
    if ((r = AUGraphAddNode(mGraph, &mixDesc, &mixerNode))) return r;
    if ((r = AUGraphConnectNodeInput(mGraph, mixerNode, 0, outputNode, 0))) return r;
    if ((r = AUGraphOpen(mGraph))) return r;
    if ((r = AUGraphNodeInfo(mGraph, mixerNode, NULL, &mMixer))) return r;

    // Port fix: with the screen locked iOS renders in 4096-frame slices; the mixer default (1156) makes every render call
    // fail with kAudioUnitErr_TooManyFramesToProcess, i.e. the music goes silent when the device sleeps.
    {
        UInt32 maxFrames = 4096;
        AudioUnitSetProperty(mMixer, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, sizeof(maxFrames));
        AudioUnit outUnit = NULL;
        if (AUGraphNodeInfo(mGraph, outputNode, NULL, &outUnit) == noErr && outUnit != NULL)
            AudioUnitSetProperty(outUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, sizeof(maxFrames));
    }

    UInt32 numBuses = kMCMNumBuses;
    if ((r = AudioUnitSetProperty(mMixer, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &numBuses, sizeof(numBuses)))) return r;

    for (UInt32 i = 0; i < numBuses; i++) {
        AURenderCallbackStruct cb = { renderInput, mSoundBuffer };
        if ((r = AUGraphSetNodeInputCallback(mGraph, mixerNode, i, &cb))) return r;
        MCM_FloatFormat(&desc, mGraphRate);
        if ((r = AudioUnitSetProperty(mMixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, i, &desc, sizeof(desc)))) return r;
    }

    MCM_FloatFormat(&desc, mGraphRate);
    if ((r = AudioUnitSetProperty(mMixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &desc, sizeof(desc)))) return r;

    if ((r = AUGraphInitialize(mGraph))) return r;
    for (UInt32 i = 0; i < numBuses; i++)
        [self setInputVolume:i value:1.0f];
    return 0;
}

- (void)startAUGraph {
    if (!mGraph) return;
    Boolean running = false;
    if (AUGraphIsRunning(mGraph, &running) == noErr && !running) {
        OSStatus st = AUGraphStart(mGraph);
        if (st == noErr) isPlaying = 1;
        else if (!gMCMReported) { gMCMReported = YES; MCM_Status([NSString stringWithFormat:@"AUGraphStart failed: %d", (int)st]); }
    }
}

- (void)stopAUGraph {
    if (!mGraph) return;
    Boolean running = false;
    if (AUGraphIsRunning(mGraph, &running) == noErr && running) {
        if (AUGraphStop(mGraph) == noErr) isPlaying = 0;
    }
}

// ---- volumes (kMultiChannelMixerParam_Volume = 0, _Enable = 1) -------------------------------
- (void)setOutputVolume:(float)value {
    AudioUnitSetParameter(mMixer, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, value, 0);
}
- (float)getOutputVolume {
    float v = 1.0f;
    AudioUnitGetParameter(mMixer, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, &v);
    return v;
}
- (void)setInputVolume:(float)value {   // both buses of the crossfade pair
    AudioUnitSetParameter(mMixer, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, value, 0);
    AudioUnitSetParameter(mMixer, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 1, value, 0);
}
- (void)setInputVolume:(unsigned long)bus value:(float)value {
    AudioUnitSetParameter(mMixer, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, (UInt32)bus, value, 0);
}
- (float)getInputVolume {   // volume of the current bus
    float v = 1.0f;
    AudioUnitGetParameter(mMixer, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, (UInt32)[self GetCurrentBus], &v);
    return v;
}
- (void)enableInput:(unsigned long)bus isOn:(float)isOn {
    AudioUnitSetParameter(mMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, (UInt32)bus, isOn, 0);
}

// ---- play / stop ---------------------------------------------------------------------------
- (void)StopPreplay { [self StopPlayingBus:2]; }

- (void)StopPlayingBus:(int)bus {
    if (bus < 0 || bus >= kMCMNumBuses) return;
    pthread_mutex_lock(&gBusMutex[bus]);
    m_gen[bus]++;                       // any reader thread of the previous play must stop touching this bus
    if (mxafref[bus]) {
        [self enableInput:bus isOn:0.0f];
        usleep(25000);   // let the render callback leave this bus before it is wiped
        ExtAudioFileDispose(mxafref[bus]);
        mxafref[bus] = NULL;
    }
    memset(&mSoundBuffer[bus], 0, sizeof(SoundBuffer));
    pthread_mutex_unlock(&gBusMutex[bus]);

    if ([(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] m_isstattalm]) {
        if (bus == 2 && mxafref[0] == NULL && mxafref[1] == NULL)
            isPlaying = 0;
    }
}

- (void)PlayPrePlay:(id)clip {
    ClipObject *c = (ClipObject *)clip;
    if ([c m_folderid] == -44) return;
    if ([c m_folderid] == -66) return;
    if (!mAllowPrePlay) return;
    if ([c m_filepath] == nil) return;
    [self PlayFile:[c m_filepath] atBus:2];
    for (int i = 0; i < 100; i++) {          // wait until the reader thread opened the file
        if (mxafref[2] != NULL) break;
        usleep(10000);
    }
}

- (void)FadeOut:(float)seconds {
    [self performSelectorInBackground:@selector(FadeOutInBackground:)
                           withObject:[[[NSNumber alloc] initWithFloat:seconds] autorelease]];
}

- (void)FadeOutInBackground:(id)seconds {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int bus = [self GetCurrentBus];
    float t = [seconds floatValue];
    float v = [self getInputVolume];
    int steps = (t > 3.0f) ? 20 : 10;
    float step = v / steps;
    useconds_t sleepUs = (useconds_t)(t / steps * 1000000.0f);
    for (int i = 0; i < steps; i++) {
        v -= step;
        [self setInputVolume:bus value:v];
        usleep(sleepUs);
    }
    [self StopPlayingBus:bus];
    usleep(50000);
    [self setInputVolume:bus value:0.0f];
    [self stopAUGraph];
    [pool release];
}

- (void)PlayFile:(id)file atBus:(int)bus {
    if (bus < 0 || bus > 4 || file == nil) return;
    [self StopPlayingBus:bus];
    pthread_mutex_lock(&gBusMutex[bus]);
    int gen = ++m_gen[bus];
    pthread_mutex_unlock(&gBusMutex[bus]);
    // Each play gets its own job (bus, generation, URL) so a late-starting reader can never pick up a newer
    // song's URL or file reference.
    NSDictionary *job = [NSDictionary dictionaryWithObjectsAndKeys:
                         [NSNumber numberWithInt:bus], @"bus",
                         [NSNumber numberWithInt:gen], @"gen",
                         [NSURL fileURLWithPath:file], @"url", nil];
    [self performSelectorInBackground:@selector(PlayFileInBackground:) withObject:job];
}

- (void)PlayFile:(id)file widthCrossfadeTime:(float)t inSteps:(int)steps {
    static int sPlayIdCounter = 0;            // data_0034f6e8
    int myFade = ++m_fadeSerial;
    int cur = [self GetCurrentBus];
    int next = [self GetNextBus];
    m_playid[next] = ++sPlayIdCounter;
    [self setInputVolume:next value:0.0f];
    [self PlayFile:file atBus:next];

    // DEVIATION: the volume ramp runs on its own thread (about 40 steps per second).  It used to run in a nested run loop of
    // the main thread for the whole cross fade, which made the UI stutter while a song changed and moved the volume in a
    // few coarse steps.
    NSDictionary *fj = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:cur], @"cur", [NSNumber numberWithInt:next], @"next",
                        [NSNumber numberWithFloat:t], @"t", [NSNumber numberWithInt:myFade], @"fade", nil];
    [NSThread detachNewThreadSelector:@selector(FadeThread:) toTarget:self withObject:fj];
}

- (void)FadeThread:(NSDictionary *)fj {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int cur = [[fj objectForKey:@"cur"] intValue], next = [[fj objectForKey:@"next"] intValue], myFade = [[fj objectForKey:@"fade"] intValue];
    float t = [[fj objectForKey:@"t"] floatValue];
    int steps = (int)(t * 40.0f); if (steps < 20) steps = 20;
    for (int i = 1; i <= steps; i++) {
        usleep((useconds_t)(t / steps * 1000000.0f));
        if (myFade != m_fadeSerial) { [pool release]; return; }   // a newer song request took over (it handles the buses now)
        float x = (float)i / (float)steps;
        [self setInputVolume:cur value:1.0f - x];
        [self setInputVolume:next value:x];
    }
    [self StopPlayingBus:cur];
    usleep(100000);
    if (myFade == m_fadeSerial) {
        [self setInputVolume:cur value:1.0f];
        [self setInputVolume:next value:1.0f];
    }
    [pool release];
}

- (void)PlayFileInBackground:(id)job {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int bus = [[job objectForKey:@"bus"] intValue];
    int gen = [[job objectForKey:@"gen"] intValue];
    NSURL *fileURL = [job objectForKey:@"url"];
    SoundBuffer *sb = &mSoundBuffer[bus];
    int playid = m_playid[bus];

    pthread_mutex_lock(&gBusMutex[bus]);
    if (m_gen[bus] != gen) {                 // superseded before this thread even started
        pthread_mutex_unlock(&gBusMutex[bus]);
        [pool release];
        return;
    }
    if (mxafref[bus]) {
        ExtAudioFileDispose(mxafref[bus]);
        mxafref[bus] = NULL;
    }
    memset(sb, 0, sizeof(SoundBuffer));

    AudioBufferList *abl0 = NULL, *abl1 = NULL;
    AudioStreamBasicDescription fileFmt;
    SInt64 fileFrames = 0;
    UInt32 size;

    OSStatus stOpen = ExtAudioFileOpenURL((CFURLRef)fileURL, &mxafref[bus]);
    if (stOpen != noErr || mxafref[bus] == NULL) {
        if (!gMCMReported) { gMCMReported = YES; MCM_Status([NSString stringWithFormat:@"open failed: %d\n%@", (int)stOpen, [fileURL path]]); }
        goto fail;
    }

    memset(&fileFmt, 0, sizeof(fileFmt));
    size = sizeof(fileFmt);
    if (ExtAudioFileGetProperty(mxafref[bus], kExtAudioFileProperty_FileDataFormat, &size, &fileFmt) != noErr)
        goto fail;

    [self AdaptGraphToRate:fileFmt.mSampleRate forBus:bus];
    {
        double fileHz = fileFmt.mSampleRate;
        [self PostRateInfoForFile:fileHz];
    }
    double ratio = ((mGraphRate > 0) ? mGraphRate : 44100.0) / fileFmt.mSampleRate;       // computed before the format is overridden
    AudioStreamBasicDescription client = fileFmt;
    if (mPlayMono) {
        [self setupMonoStreamFormat:&client];
    } else {
        [self setupStereoStreamFormat:&client];
        sb->isStereo = 1;
        sb->mMixBus = 1;
    }
    OSStatus stFmt = ExtAudioFileSetProperty(mxafref[bus], kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client);
    if (stFmt == noErr && fabs(fileFmt.mSampleRate - client.mSampleRate) > 1.0) {
        // unavoidable conversion (device cannot run at the file's rate): use the best sample-rate converter
        AudioConverterRef conv = NULL;
        UInt32 csz = sizeof(conv);
        if (ExtAudioFileGetProperty(mxafref[bus], kExtAudioFileProperty_AudioConverter, &csz, &conv) == noErr && conv != NULL) {
            UInt32 q = kAudioConverterQuality_Max, cx = kAudioConverterSampleRateConverterComplexity_Mastering;
            AudioConverterSetProperty(conv, kAudioConverterSampleRateConverterQuality, sizeof(q), &q);
            AudioConverterSetProperty(conv, kAudioConverterSampleRateConverterComplexity, sizeof(cx), &cx);
            CFArrayRef cfg = NULL;
            ExtAudioFileSetProperty(mxafref[bus], kExtAudioFileProperty_ConverterConfig, sizeof(cfg), &cfg);
        }
    }
    if (stFmt != noErr) {
        if (!gMCMReported) { gMCMReported = YES; MCM_Status([NSString stringWithFormat:@"client format rejected: %d", (int)stFmt]); }
        goto fail;
    }

    size = sizeof(fileFrames);
    if (ExtAudioFileGetProperty(mxafref[bus], kExtAudioFileProperty_FileLengthFrames, &size, &fileFrames) != noErr)
        goto fail;

    UInt32 channels = client.mChannelsPerFrame;
    UInt32 convertedFrames = (UInt32)((double)fileFrames * ratio);
    mDuration[bus] = (int)((double)convertedFrames / (client.mSampleRate / client.mFramesPerPacket));

    sb->asbd = client;
    sb->wpos = 0;
    sb->rpos = 0;

    const UInt32 chunk = 8192;                       // frames per ExtAudioFileRead
    float *tmp[2] = { (float *)calloc(chunk, sizeof(float)), (float *)calloc(chunk, sizeof(float)) };
    abl0 = (AudioBufferList *)calloc(1, offsetof(AudioBufferList, mBuffers) + channels * sizeof(AudioBuffer));
    abl0->mNumberBuffers = channels;
    float *ringL = (float *)sb->data[0];
    float *ringR = (float *)sb->data[1];

    [self startAUGraph];
    [self enableInput:bus isOn:1.0f];
    pthread_mutex_unlock(&gBusMutex[bus]);

    BOOL eof = NO;
    while (!eof) {
        if (mxafref[bus] == NULL || m_gen[bus] != gen) break;
        UInt32 w = sb->wpos;                          // only this thread writes wpos
        UInt32 used = w - __atomic_load_n(&sb->rpos, __ATOMIC_ACQUIRE);
        if (used > kMCMRingFrames) used = kMCMRingFrames;
        if (kMCMRingFrames - used < chunk) { usleep(5000); continue; }   // ring is full enough
        if (pthread_mutex_lock(&gBusMutex[bus]) != 0) { usleep(100); continue; }
        if (mxafref[bus] == NULL || m_gen[bus] != gen) { pthread_mutex_unlock(&gBusMutex[bus]); break; }
        for (UInt32 c = 0; c < channels; c++) {
            abl0->mBuffers[c].mNumberChannels = 1;
            abl0->mBuffers[c].mDataByteSize = chunk * sizeof(float);
            abl0->mBuffers[c].mData = tmp[c < 2 ? c : 1];
        }
        UInt32 n = chunk;
        pthread_mutex_lock(&mMutexExtAudioFileRead);
        OSStatus e = ExtAudioFileRead(mxafref[bus], &n, abl0);
        pthread_mutex_unlock(&mMutexExtAudioFileRead);
        if (e != noErr) { pthread_mutex_unlock(&gBusMutex[bus]); [self ErrorPlayingFile:bus]; break; }
        if (n == 0) { eof = YES; pthread_mutex_unlock(&gBusMutex[bus]); break; }
        // Tail fade: the last 1.5 s of every file fade to silence in the data itself, so a song never stops abruptly
        // while still loud, even when the cross fade started too late (or the file is shorter than its tags say).
        UInt32 tailFrames = (UInt32)(1.5 * client.mSampleRate);
        for (UInt32 i = 0; i < n; i++) {
            UInt32 idx = (w + i) & (kMCMRingFrames - 1);
            float g = 1.0f;
            UInt64 pos = (UInt64)w + i;
            if (convertedFrames > tailFrames && pos + tailFrames > convertedFrames) {
                UInt64 left = (pos >= convertedFrames) ? 0 : (convertedFrames - pos);
                g = (float)left / (float)tailFrames;
            }
            ringL[idx] = tmp[0][i] * g;
            ringR[idx] = ((channels > 1) ? tmp[1][i] : tmp[0][i]) * g;
        }
        __atomic_store_n(&sb->wpos, w + n, __ATOMIC_RELEASE);
        if (!gMCMReported) {
            gMCMReported = YES;
            float peak = 0;
            for (UInt32 q = 0; q < n; q++) if (fabsf(tmp[0][q]) > peak) peak = fabsf(tmp[0][q]);
            Boolean run = false; if (mGraph) AUGraphIsRunning(mGraph, &run);
            MCM_Status([NSString stringWithFormat:@"first read: %u frames, peak %.3f\ngraph running: %d\nout vol %.2f\nfile %.0f Hz, %u ch\ngraph %.0f Hz (%@)",
                (unsigned)n, peak, (int)run, [self getOutputVolume], fileFmt.mSampleRate, (unsigned)fileFmt.mChannelsPerFrame, mGraphRate, (fabs(mGraphRate - fileFmt.mSampleRate) < 1.0) ? @"native, no resampling" : @"resampled once"]);
        }
        pthread_mutex_unlock(&gBusMutex[bus]);
    }

    if (eof) {                                        // let the buffered audio play out (ring holds up to ~6 s)
        for (int k = 0; k < 900; k++) {
            if (mxafref[bus] == NULL || m_gen[bus] != gen) break;
            if ((SInt32)(sb->wpos - sb->rpos) <= 0) break;
            usleep(10000);
        }
    }

    free(tmp[0]);
    free(tmp[1]);
    free(abl0);
    pthread_mutex_lock(&gBusMutex[bus]);
    BOOL mine = (m_gen[bus] == gen);          // only the newest play of this bus may clean it up
    if (mine) {
        mDuration[bus] = 0;
        if (mxafref[bus]) ExtAudioFileDispose(mxafref[bus]);
        mxafref[bus] = NULL;
    }
    pthread_mutex_unlock(&gBusMutex[bus]);
    if (mine && bus != 2) {
        usleep(1000000);
        if (m_gen[bus] == gen && playid == m_playid[[self GetCurrentBus]])
            [self StopPlayingBus:bus];
    }
    [pool release];
    return;

fail:
    if (m_gen[bus] == gen) [self ErrorPlayingFile:bus];
    pthread_mutex_unlock(&gBusMutex[bus]);
    [pool release];
}
@end
