// Recovered from -[MultichannelMixerController ...] @0xbdd10..0xbf2c8 and C helper renderInput @0xbdbb4.
#import "MultichannelMixerController.h"
#import "ClipObject.h"
#import "RadioAppDelegate.h"
#include <unistd.h>
#include <string.h>

// One mutex per bus (global in the original: data_00398850, stride 0x2c on armv7)
static pthread_mutex_t gBusMutex[kMCMNumBuses];

// 8.24 fixed-point, non-interleaved "AudioUnit canonical" format (kAudioFormatFlagsAudioUnitCanonical).
// Literal value used by the original because the constant is deprecated in newer SDKs.
#define kMCMFormatFlags 0xc2c

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
static void MCM_FloatFormat(AudioStreamBasicDescription *d) {
    memset(d, 0, sizeof(*d));
    d->mFormatID = kAudioFormatLinearPCM;
    d->mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    d->mSampleRate = 44100.0;
    d->mChannelsPerFrame = 2;
    d->mFramesPerPacket = 1;
    d->mBitsPerChannel = 32;
    d->mBytesPerFrame = 4;
    d->mBytesPerPacket = 4;
}

// ---- Render callback (@0xbdbb4) -------------------------------------------------------------
// refcon points at mSoundBuffer[0]; the bus number selects the entry.
static OSStatus renderInput(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
                            UInt32 inNumberFrames, AudioBufferList *ioData) {
    SoundBuffer *sb = (SoundBuffer *)inRefCon + inBusNumber;
    UInt32 sample = sb->sampleNum;
    if (inNumberFrames == 0) return 0;

    // DEVIATION: the original handed 8.24 fixed-point samples to the mixer.  Current iOS mixers only take
    // Float32 (non-interleaved), so the samples are converted here (8.24: 1.0 == 1 << 24).
    float *outA = (float *)ioData->mBuffers[0].mData;
    float *outB = (float *)ioData->mBuffers[1].mData;
    const float k = 1.0f / 16777216.0f;
    SInt32 *left  = sb->data[sb->BufNo];
    SInt32 *right = left + kMCMPlaneSamples;

    for (UInt32 i = 0; i < inNumberFrames; i++) {
        float l = (float)left[sample] * k;
        if (inBusNumber < 2) {
            outA[i] = l;
            outB[i] = sb->isStereo ? (float)right[sample] * k : (sb->mMixBus ? l : 0.0f);
        } else if (sb->mMixBus) {
            outA[i] = l;
            outB[i] = sb->isStereo ? (float)right[sample] * k : l;
        } else if (sb->isStereo) {
            outA[i] = l;
            outB[i] = (float)right[sample] * k;
        } else {
            outA[i] = 0.0f;
            outB[i] = l;
        }
        sample++;
        if (sb->numFrames != 0 && sample >= sb->numFrames) {
            sb->inUse[sb->BufNo] = 0;
            sb->BufNo ^= 1;
            sample = 0;
            left  = sb->data[sb->BufNo];
            right = left + kMCMPlaneSamples;
        }
    }
    sb->sampleNum = sample;
    return 0;
}

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
    if (mGraph) DisposeAUGraph(mGraph);
    for (int i = 0; i < kMCMNumBuses; i++) {
        pthread_mutex_destroy(&gBusMutex[i]);
        if (sourceURL[i]) CFRelease(sourceURL[i]);
    }
    pthread_mutex_destroy(&mMutexExtAudioFileRead);
    free(mSoundBuffer);
    [super dealloc];
}

- (void)initAudioSession {
    isPlaying = 0;
    memset(mSoundBuffer, 0, kMCMNumBuses * sizeof(SoundBuffer));
    for (int i = 0; i < kMCMNumBuses; i++) {
        mxafref[i] = NULL;
        mDuration[i] = 0;
    }
    OSStatus gr = [self initializeAUGraph];
    if (gr != noErr) NSLog(@"[MCM] initializeAUGraph failed: %d", (int)gr);
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
    d->mSampleRate = 44100.0;
    d->mBytesPerPacket = 4;
    d->mFramesPerPacket = 1;
    d->mBytesPerFrame = 4;
    d->mChannelsPerFrame = 2;
    d->mBitsPerChannel = 32;
}

- (void)setupMonoStreamFormat:(AudioStreamBasicDescription *)d {
    d->mFormatID = kAudioFormatLinearPCM;
    d->mFormatFlags = kMCMFormatFlags;
    d->mSampleRate = 44100.0;
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

    AUNode outputNode, mixerNode;
    AudioComponentDescription outDesc = { kAudioUnitType_Output, kAudioUnitSubType_RemoteIO, kAudioUnitManufacturer_Apple, 0, 0 };
    AudioComponentDescription mixDesc = { kAudioUnitType_Mixer, kAudioUnitSubType_MultiChannelMixer, kAudioUnitManufacturer_Apple, 0, 0 };

    if ((r = NewAUGraph(&mGraph))) return r;
    if ((r = AUGraphAddNode(mGraph, &outDesc, &outputNode))) return r;
    if ((r = AUGraphAddNode(mGraph, &mixDesc, &mixerNode))) return r;
    if ((r = AUGraphConnectNodeInput(mGraph, mixerNode, 0, outputNode, 0))) return r;
    if ((r = AUGraphOpen(mGraph))) return r;
    if ((r = AUGraphNodeInfo(mGraph, mixerNode, NULL, &mMixer))) return r;

    UInt32 numBuses = kMCMNumBuses;
    if ((r = AudioUnitSetProperty(mMixer, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &numBuses, sizeof(numBuses)))) return r;

    for (UInt32 i = 0; i < numBuses; i++) {
        AURenderCallbackStruct cb = { renderInput, mSoundBuffer };
        if ((r = AUGraphSetNodeInputCallback(mGraph, mixerNode, i, &cb))) return r;
        MCM_FloatFormat(&desc);
        if ((r = AudioUnitSetProperty(mMixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, i, &desc, sizeof(desc)))) return r;
    }

    MCM_FloatFormat(&desc);
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
        if (AUGraphStart(mGraph) == noErr) isPlaying = 1;
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
    pthread_mutex_lock(&gBusMutex[bus]);
    if (mxafref[bus]) {
        [self enableInput:bus isOn:0.0f];
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
    if (bus > 4 || file == nil) return;
    [self StopPlayingBus:bus];
    sourceURL[bus] = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)file, kCFURLPOSIXPathStyle, false);
    [self performSelectorInBackground:@selector(PlayFileInBackground:)
                           withObject:[NSNumber numberWithInt:bus]];
}

- (void)PlayFile:(id)file widthCrossfadeTime:(float)t inSteps:(int)steps {
    static int sPlayIdCounter = 0;            // data_0034f6e8
    int cur = [self GetCurrentBus];
    int next = [self GetNextBus];
    m_playid[next] = ++sPlayIdCounter;
    [self setInputVolume:next value:0.0f];
    [self PlayFile:file atBus:next];

    float curVol = 1.0f, nextVol = 0.0f;
    for (int i = 0; i < steps; i++) {
        curVol  -= 1.0f / steps;
        nextVol += 1.0f / steps;
        [self setInputVolume:cur value:curVol];
        [self setInputVolume:next value:nextVol];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, t / steps, false);
    }
    [self StopPlayingBus:cur];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
    [self setInputVolume:cur value:1.0f];
    [self setInputVolume:next value:1.0f];
}

- (void)ErrorPlayingFile:(int)bus {
    if (bus == 2) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MCM_MSG_ERROR_PLAYING_FILE" object:nil];
}

// ---- reader thread -------------------------------------------------------------------------
- (void)PlayFileInBackground:(id)busNumber {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int bus = [busNumber intValue];
    SoundBuffer *sb = &mSoundBuffer[bus];
    int playid = m_playid[bus];

    pthread_mutex_lock(&gBusMutex[bus]);
    if (mxafref[bus]) {
        ExtAudioFileDispose(mxafref[bus]);
        while (mxafref[bus] != NULL) usleep(10000);
    }
    memset(sb, 0, sizeof(SoundBuffer));

    AudioBufferList *abl0 = NULL, *abl1 = NULL;
    AudioStreamBasicDescription fileFmt;
    SInt64 fileFrames = 0;
    UInt32 size;

    if (ExtAudioFileOpenURL(sourceURL[bus], &mxafref[bus]) != noErr || mxafref[bus] == NULL)
        goto fail;

    memset(&fileFmt, 0, sizeof(fileFmt));
    size = sizeof(fileFmt);
    if (ExtAudioFileGetProperty(mxafref[bus], kExtAudioFileProperty_FileDataFormat, &size, &fileFmt) != noErr)
        goto fail;

    double ratio = 44100.0 / fileFmt.mSampleRate;       // computed before the format is overridden
    AudioStreamBasicDescription client = fileFmt;
    if (mPlayMono) {
        [self setupMonoStreamFormat:&client];
    } else {
        [self setupStereoStreamFormat:&client];
        sb->isStereo = 1;
        sb->mMixBus = 1;
    }
    if (ExtAudioFileSetProperty(mxafref[bus], kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client) != noErr)
        goto fail;

    size = sizeof(fileFrames);
    if (ExtAudioFileGetProperty(mxafref[bus], kExtAudioFileProperty_FileLengthFrames, &size, &fileFrames) != noErr)
        goto fail;

    UInt32 channels = client.mChannelsPerFrame;
    UInt32 convertedFrames = (UInt32)((double)fileFrames * ratio);
    mDuration[bus] = (int)((double)convertedFrames / (client.mSampleRate / client.mFramesPerPacket));

    sb->numFrames = 100000 / channels;
    sb->asbd = client;
    sb->sampleNum = 0;

    // Two AudioBufferLists (one per half), one mono buffer per channel plane.
    abl0 = (AudioBufferList *)calloc(1, offsetof(AudioBufferList, mBuffers) + channels * sizeof(AudioBuffer));
    abl1 = (AudioBufferList *)calloc(1, offsetof(AudioBufferList, mBuffers) + channels * sizeof(AudioBuffer));
    UInt32 planeBytes = 400000 / channels;
    abl0->mNumberBuffers = channels;
    abl1->mNumberBuffers = channels;
    for (UInt32 c = 0; c < channels; c++) {
        abl0->mBuffers[c].mNumberChannels = 1;
        abl0->mBuffers[c].mDataByteSize = planeBytes;
        abl0->mBuffers[c].mData = sb->data[0] + (c ? kMCMPlaneSamples : 0);
        abl1->mBuffers[c].mNumberChannels = 1;
        abl1->mBuffers[c].mDataByteSize = planeBytes;
        abl1->mBuffers[c].mData = sb->data[1] + (c ? kMCMPlaneSamples : 0);
    }

    [self startAUGraph];
    [self enableInput:bus isOn:1.0f];
    pthread_mutex_unlock(&gBusMutex[bus]);

    UInt32 total = 0;
    while (total < convertedFrames * channels) {
        if (mxafref[bus] == NULL) break;
        if (pthread_mutex_lock(&gBusMutex[bus]) != 0) { usleep(100); continue; }

        if (!sb->inUse[0]) {
            memset(sb->data[0], 0, 400000);
            if (mxafref[bus] == NULL) goto locked_break;
            UInt32 n = sb->numFrames;                    // original requested 100000; clamped to buffer capacity
            pthread_mutex_lock(&mMutexExtAudioFileRead);
            OSStatus e = ExtAudioFileRead(mxafref[bus], &n, abl0);
            pthread_mutex_unlock(&mMutexExtAudioFileRead);
            if (e != noErr) { [self ErrorPlayingFile:bus]; goto locked_break; }
            sb->inUse[0] = 1;
            if (n == 0) goto locked_break;               // end of file
            total += n;
        }
        if (sb->inUse[1]) {
            pthread_mutex_unlock(&gBusMutex[bus]);
            usleep(1000);
            continue;
        }
        memset(sb->data[1], 0, 400000);
        if (mxafref[bus] == NULL) {
            pthread_mutex_unlock(&gBusMutex[bus]);
            usleep(1000);
            continue;
        }
        {
            UInt32 n = sb->numFrames;
            pthread_mutex_lock(&mMutexExtAudioFileRead);
            OSStatus e = ExtAudioFileRead(mxafref[bus], &n, abl1);
            pthread_mutex_unlock(&mMutexExtAudioFileRead);
            if (e != noErr) { [self ErrorPlayingFile:bus]; goto locked_break; }
            sb->inUse[1] = 1;
            total += kMCMBufFrames;                      // quirk preserved: counts a full 100000 even when short
        }
        pthread_mutex_unlock(&gBusMutex[bus]);
        usleep(1000);
        continue;
    locked_break:
        pthread_mutex_unlock(&gBusMutex[bus]);
        break;
    }

    mDuration[bus] = 0;
    free(abl0);
    free(abl1);
    pthread_mutex_lock(&gBusMutex[bus]);
    if (mxafref[bus]) ExtAudioFileDispose(mxafref[bus]);
    mxafref[bus] = NULL;
    pthread_mutex_unlock(&gBusMutex[bus]);
    if (bus != 2) {
        usleep(1000000);
        if (playid == m_playid[[self GetCurrentBus]])
            [self StopPlayingBus:bus];
    }
    [pool release];
    return;

fail:
    [self ErrorPlayingFile:bus];
    pthread_mutex_unlock(&gBusMutex[bus]);
    [pool release];
}
@end
