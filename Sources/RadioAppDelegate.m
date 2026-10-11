// RadioAppDelegate.m -- recovered from Radiofx_iPad (armv7), ported to arm64.
// Methods that only served streaming / server sync / remote control / Spotify / version check
// are not part of this port (see DEVIATIONS.md).
#import "RadioAppDelegate.h"
#import "DBOperations.h"
#import "ServerEntry.h"
#import "FolderObject.h"
#import "ClipObject.h"
#import "iPadMainVC.h"
#import "KioskHelper.h"
#import "KioskView.h"
#import "RadioVC.h"
#import "ServerComm.h"
#import "Globals.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <sys/xattr.h>
#import <CommonCrypto/CommonDigest.h>

BOOL g_bShutdown = NO;
int gv_kioskflag = 0;

@implementation RadioAppDelegate

@synthesize mMoviePlayerGlobal;
@synthesize m_spotifypicdir;
@synthesize m_spotifydir;
@synthesize m_advertisingtexts;
@synthesize m_isstattalm;
@synthesize m_ios501min;
@synthesize m_useownvolume;
@synthesize m_ownip;
@synthesize m_stackalbums;
@synthesize m_runhourtimer;
@synthesize mCurrentRemoteCtrlServer;
@synthesize mRemoteCtrlServers;
@synthesize m_dummymoviestarted;
@synthesize g_reduce;
@synthesize g_mute;
@synthesize m_ios;
@synthesize m_isinbackground;
@synthesize m_kioskpresent;
@synthesize m_animatechannelchange;
@synthesize m_iscuedia;
@synthesize m_mutevolume;
@synthesize m_isipad;
@synthesize m_30secactive;
@synthesize m_switching;
@synthesize m_streameraction;
@synthesize m_radiofxchanneltimestamp;
@synthesize m_firststart;
@synthesize m_channelpicturepath;
@synthesize globalFontSizeFactor;
@synthesize m_isedge;
@synthesize m_canrotate;
@synthesize m_volume;
@synthesize g_end;
@synthesize m_oldlastchannelid;
@synthesize m_lastchannelid;
@synthesize tickerURLPrefix;
@synthesize databaseVersionNeeded;
@synthesize currentDatabaseVersion;
@synthesize window;

#pragma mark - launching

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    m_canRotateiPad = YES;
    m_loadeddefaultvalues = NO;
    sendedDeviceToken = NO;
    m_isinbackground = NO;
    didVersionCheck = NO;
    m_dblock = [[NSLock alloc] init];
    m_isipad = NO;
    pthread_mutex_init(&_mutexConnectionInUse, 0);
    if ([[UIDevice currentDevice] respondsToSelector:@selector(userInterfaceIdiom)]) {
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
            m_isipad = YES;
    }
    [self applicationDidFinishLaunching:application];
    return YES;
}

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    m_kh = nil;
    m_vintern = [self CalcVIntern];
    // UIDevice uniqueIdentifier is gone since iOS 7; identifierForVendor is its replacement.
    m_uid = [[[[UIDevice currentDevice] identifierForVendor] UUIDString] retain];
    mCurrentRemoteCtrlServer = nil;
    mRemoteCtrlServers = [[NSMutableArray alloc] initWithCapacity:0];
    mBroadcast = nil;
    g_mute = NO;
    g_reduce = NO;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs integerForKey:@"stattalm"] > 0) {
        m_isstattalm = YES;
        [defs setObject:[NSNumber numberWithDouble:0.0] forKey:@"lighton"];
        [defs setObject:[NSNumber numberWithDouble:0.0] forKey:@"lightoff"];
    } else {
        m_isstattalm = NO;
    }
    m_servercomm = [[ServerComm alloc] init];
    [m_servercomm InitObject];
    m_waslastplaying = 0;
    [self InitAudioSession];
    m_tmpresent = [[NSFileManager defaultManager] fileExistsAtPath:@"./private/var/mobile/Library/TerminalMonitoring/control"];
    m_ipadmainvc = [[iPadMainVC alloc] initWithNibName:nil bundle:nil];
    m_ipadnavi = [[UINavigationController alloc] initWithRootViewController:m_ipadmainvc];
    [m_ipadnavi setNavigationBarHidden:YES];
    // The original did [window addSubview:[m_ipadnavi view]]; current iOS requires a root view controller.
    [window setRootViewController:m_ipadnavi];
    [m_ipadmainvc release];
    m_startimage = [self GetStartImageView];
    if (m_startimage != nil)
        [[m_ipadmainvc view] addSubview:m_startimage];
    [window setBackgroundColor:[UIColor blackColor]];
    [window makeKeyAndVisible];
    currentDatabaseVersion = 0;
    databaseVersionNeeded = 0x44a;
    m_kh = [[KioskHelper alloc] init];
    [self performSelector:@selector(applicationDidFinishLaunchingDelayed) withObject:nil afterDelay:0];
}

- (void)applicationDidFinishLaunchingDelayed {
    m_cleanview = nil;
    m_runhourtimer = NO;
    m_ownbrowser = nil;
    m_radioVC = nil;
    m_oldlastchannelid = 0;
    m_streamer = nil;
    [self setM_switching:NO];
    g_end = NO;
    m_lastchannelid = 0;
    tickerURLPrefix = nil;
    globalFontSizeFactor = 1.0;
    m_isedge = NO;
    m_firststart = YES;
    m_streameraction = 0;
    m_30secactive = NO;
    m_lastsendchannelid = -1;
    m_ffmpegregistered = NO;
    m_mutevolume = NO;
    m_ipadnavi = nil;
    m_dummymoviestarted = NO;
    m_ownip = nil;
    m_startedpicanimation = NO;
    m_ios501min = NO;
    m_reconnecting[0] = NO;
    m_reconnecting[1] = NO;
    m_connectioninuse[0] = NO;
    m_connectioninuse[1] = NO;
    m_iscuedia = NO;
    m_animatechannelchange = NO;
    m_kioskpresent = NO;
    m_audiotimerdelayed = nil;
    m_printerlock = [[NSLock alloc] init];
    if ([[[UIDevice currentDevice] systemVersion] compare:@"5.0.1" options:NSNumericSearch] != NSOrderedAscending)
        m_ios501min = YES;
    m_ios = 3;
    NSString *vs = [NSString stringWithFormat:@"%@", [[UIDevice currentDevice] systemVersion]];
    if (vs != nil)
        m_ios = [vs intValue];
    sendedDeviceToken = NO;

    // Network reachability, version check, push registration and the OwnIP lookup of the original are not
    // part of this port; the app runs offline-only (IsOnline / isInetAvailable return NO).

    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [self GetStackAlbums:defs];
    [self GetUseOwnVolume:defs];
    m_channelpicturepath = [@"" retain];
    m_possiblechars = [[NSMutableArray alloc] init];
    for (int c = 'A'; c != 'Z' + 1; c++)
        [m_possiblechars addObject:[NSString stringWithFormat:@"%c", c]];
    for (int c = 'a'; c != 'z' + 1; c++)
        [m_possiblechars addObject:[NSString stringWithFormat:@"%c", c]];
    [m_possiblechars addObject:@" "];

    NSFileManager *fm = [NSFileManager defaultManager];
    // The original detected a jailbroken "/var/mobile" home (m_iscuedia) and then used the bundle's
    // resolved path as home. On a normal sideloaded install the home is the app container; everything the
    // user has to provide (Radio.db and the server folder with mp3/jpg files) is looked up below Documents.
    m_homedir = [[NSString stringWithFormat:@"%@", NSHomeDirectory()] retain];
    m_advertsubdir = [[NSString stringWithFormat:@"%@%@", @"Library/Caches/", @"Advertising"] retain];
    [self CreateAdvertisingDir:1];
    m_videotheksubdir = [[NSString stringWithFormat:@"%@%@", @"Library/Caches/", @"Videothek"] retain];
    [self CreateAdvertisingDir:0];
    m_printersubdir = [[NSString stringWithFormat:@"%@%@", @"Library/Caches/", @"Printer"] retain];
    [self CreateAdvertisingDir:2];
    m_iscuedia = YES; // "server folders live in Documents/<SERVERNAME>/" (see CreateServerDir2:withserverid:)

    m_spotifydir = [[self CreateServerDir2:@"spotify" withserverid:0] retain];
    m_spotifypicdir = [[self CreateServerDir2:@"spotifypics" withserverid:0] retain];
    [fm createDirectoryAtPath:m_spotifypicdir withIntermediateDirectories:YES attributes:nil error:nil];
    [self loadValuesFromDefaults];
    m_lastsendchannelid = m_lastchannelid;
    m_formatter = [[NSDateFormatter alloc] init];
    [m_formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    NSArray *wd = [NSArray arrayWithObjects:@"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat", @"Sun", nil];
    [m_formatter setShortStandaloneWeekdaySymbols:wd];
    [m_formatter setShortWeekdaySymbols:wd];
    NSArray *mo = [NSArray arrayWithObjects:@"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun", @"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec", nil];
    [m_formatter setShortStandaloneMonthSymbols:mo];
    [m_formatter setShortMonthSymbols:mo];
    [m_formatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss Z"];
    srandom((unsigned)time(0));
    // DEVIATION: [m_servercomm DeleteOrphanServerFolders] is not called. It deleted every directory below
    // Documents that was not named after a known server -- i.e. the user's music if the names differ.

    NSString *resetDB = [defs stringForKey:@"keyResetDB"];
    NSInteger dbver = [defs integerForKey:@"kcurrentdbversion"];
    if (resetDB != nil && [resetDB isEqualToString:@"1"]) {
        [self ResetKeysForDatabase];
        [defs setObject:@"0" forKey:@"keyResetDB"];
        [defs synchronize];
        [self loadValuesFromDefaults];
    }
    [self checkDatabase];
    [self CheckCleanDataBase];
    if (currentDatabaseVersion < dbver)
        currentDatabaseVersion = (int)dbver;
    [defs setInteger:currentDatabaseVersion forKey:@"kcurrentdbversion"];
    [defs synchronize];
    [self DeleteDoubleEntries];
    mCurrentRemoteCtrlServer = nil;
    m_channelinfos = [[NSMutableArray arrayWithCapacity:0] retain];
    m_newchannelinfos = [[NSMutableArray arrayWithCapacity:0] retain];
    m_loadeddefaultvalues = YES;
    m_advertisingtexts = [[NSMutableArray alloc] init];
    [self LoadAdvertisingTexts];
    [self LaunchIPAD];
    [[self GetiPadMainVC] ShowKioskMode];
    [self ReleaseStartImage];
}

- (void)LaunchIPAD {
    unsigned i = 0;
    while (i < [m_channelinfos count]) {
        i++; // (live radio channels are not part of this port; m_channelinfos stays empty)
    }
    m_radioVC = [[RadioVC alloc] init];
    [m_radioVC SetpChannelInfos:m_channelinfos];
    m_firststart = NO;
    [self performSelector:@selector(SetCanRotateiPad) withObject:nil afterDelay:0];
}

#pragma mark - application state

- (void)applicationDidEnterBackground:(UIApplication *)application {
    UIDevice *dev = [UIDevice currentDevice];
    if ([dev respondsToSelector:@selector(isMultitaskingSupported)]) {
        if ([dev isMultitaskingSupported]) {
            m_isinbackground = YES;
            [m_kh StopOverviewTimer];
        }
    }
}

- (void)applicationWillResignActive:(UIApplication *)application {
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    if (m_isinbackground) {
        m_isinbackground = NO;
        [m_kh ExternDraw:0];
        [m_kh ReStartIfNeeded];
    }
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [self Endfunction];
}

- (void)Endfunction {
    g_end = YES;
    if (m_audiotimerdelayed != nil) {
        [m_audiotimerdelayed invalidate];
        m_audiotimerdelayed = nil;
    }
    if ([self m_isstattalm])
        [m_kh CardReaderOff];
    if (m_ipadmainvc != nil)
        [m_ipadmainvc SetKioskViewEnd];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self StopStreamer];
    if (m_loadeddefaultvalues)
        [self saveValuesToDefaults];
    if (m_servercomm != nil) {
        [m_servercomm release];
        m_servercomm = nil;
    }
}

- (void)HardExit {
    if (m_ipadmainvc != nil)
        [m_ipadmainvc SetKioskViewEnd];
    [self setG_end:YES];
    g_bShutdown = YES;
    exit(0);
}

- (void)ZeroKVC {
    m_ipadmainvc = nil;
}

- (void)dealloc {
    [m_ipadnavi release];
    [window release];
    [m_servercomm release];
    [m_kh release];
    [m_homedir release];
    [m_uid release];
    [m_dblock release];
    [m_printerlock release];
    [m_possiblechars release];
    [m_formatter release];
    [m_advertisingtexts release];
    [m_channelinfos release];
    [m_newchannelinfos release];
    [m_channelpicturepath release];
    [m_advertsubdir release];
    [m_videotheksubdir release];
    [m_printersubdir release];
    [m_spotifydir release];
    [m_spotifypicdir release];
    [mRemoteCtrlServers release];
    [super dealloc];
}

#pragma mark - audio session

// The original used the C AudioSession API (removed from current SDKs); AVAudioSession is its successor.
- (void)InitAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterrupted:)
                                                 name:AVAudioSessionInterruptionNotification object:session];
    [session setActive:YES error:nil];
}

- (void)audioSessionInterrupted:(NSNotification *)noti {
    NSUInteger type = [[[noti userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan)
        [self InterruptFunction];
    else
        [self EndInterruptFunction];
}

- (void)InterruptFunction {
    if (![self GetStreamerPlaying]) {
        if ([m_kh IsPlayingClips])
            m_waslastplaying = 2;
    } else {
        m_waslastplaying = 1;
    }
    [self StopStreamer];
    [m_kh StopPlayers];
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
}

- (void)EndInterruptFunction {
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    if (m_waslastplaying != 0) {
        if (m_waslastplaying == 2)
            [m_kh StartFirstFolderSong:[NSNumber numberWithInt:0]];
        else if (m_waslastplaying == 1)
            [self SwitchToChannel:[self GetNumForChannelID:[self m_lastchannelid]] withAni:NO];
        m_waslastplaying = 0;
    }
}

#pragma mark - defaults

- (void)loadValuesFromDefaults {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    m_volume = 1.0f;
    if (defs == nil) return;
    m_radiofxchanneltimestamp = [defs integerForKey:@"k_38_radiofxchanneltimestamp"];
    m_radiofxchanneltimestampselected = [defs integerForKey:@"k_38_radiofxchanneltimestampselected"];
    int fs = (int)[defs doubleForKey:@"keyFontSize"];
    if (fs == 2) globalFontSizeFactor = 1.5;
    else if (fs == 1) globalFontSizeFactor = 1.2;
    else globalFontSizeFactor = 1.0;
    currentDatabaseVersion = (int)[defs integerForKey:@"kcurrentdbversion"];
    m_lastchannelid = (int)[defs integerForKey:@"Lastchannelid"];
    m_channelpicturepath = [[defs objectForKey:@"k_38_channelpicturepath"] retain];
    NSString *prefix = [defs objectForKey:@"ktickerurlprefix"];
    if (prefix != nil && [prefix length] != 0)
        [self setTickerURLPrefix:prefix];
}

- (void)saveValuesToDefaults {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if (defs == nil) return;
    [defs setInteger:currentDatabaseVersion forKey:@"kcurrentdbversion"];
    [defs setInteger:m_lastchannelid forKey:@"Lastchannelid"];
    [defs setObject:tickerURLPrefix forKey:@"ktickerurlprefix"];
    if (m_volume == 0) m_volume = 1.0f;
    [defs removeObjectForKey:@"kvolume"];
    [defs setFloat:m_volume forKey:@"kvolume"];
    [defs synchronize];
}

- (void)ResetKeysForDatabase {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs setInteger:0 forKey:@"k_38_channelinfodate"];
    [defs setInteger:0 forKey:@"k_38_lastloopstreamdate"];
    [defs setInteger:0 forKey:@"k_38_lastcleaned"];
    [defs setInteger:0 forKey:@"k_38_radiofxchanneltimestamp"];
    [defs setInteger:0 forKey:@"kcurrentdbversion"];
    [defs setInteger:0 forKey:@"Lastchannelid"];
    [defs setObject:nil forKey:@"ktickerurlprefix"];
    [defs synchronize];
}

- (void)GetStackAlbums:(NSUserDefaults *)stackAlbums {
    NSUserDefaults *defs = stackAlbums != nil ? stackAlbums : [NSUserDefaults standardUserDefaults];
    NSString *v = [defs stringForKey:@"keystackalbums"];
    [self setM_stackalbums:(v != nil ? [v intValue] : 0)];
}

- (void)GetUseOwnVolume:(NSUserDefaults *)useOwnVolume {
    NSUserDefaults *defs = useOwnVolume != nil ? useOwnVolume : [NSUserDefaults standardUserDefaults];
    NSString *v = [defs stringForKey:@"keyownvolume"];
    [self setM_useownvolume:(v != nil ? [v intValue] : 0)];
}

#pragma mark - database

- (void)checkDatabase {
    NSString *dbpath = [[[[[UIApplication sharedApplication] delegate] GetHomeDir] stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"Radio.db"];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL create = NO;
    if (![fm fileExistsAtPath:dbpath]) {
        create = YES;
    } else {
        // Deviation: a Radio.db that was copied in by the user must not be thrown away just because this
        // install has no "kcurrentdbversion" yet (the original deleted any DB older than databaseVersionNeeded).
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"kcurrentdbversion"] == nil)
            currentDatabaseVersion = databaseVersionNeeded;
        if (currentDatabaseVersion < databaseVersionNeeded) {
            if ([[[UIApplication sharedApplication] delegate] m_isipad])
                [self RemoveOldServer];
            [fm removeItemAtPath:dbpath error:nil];
            [self ResetKeysForDatabase];
            create = YES;
        }
    }
    if (create) {
        [self LockDB:NO];
        DBOperations *dbop = [[DBOperations alloc] init];
        [dbop CreateDatabase];
        [dbop release];
        [self UnlockDB];
        currentDatabaseVersion = databaseVersionNeeded;
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        if (defs != nil) {
            [defs setInteger:currentDatabaseVersion forKey:@"kcurrentdbversion"];
            [defs synchronize];
        }
    }
    if ([self GetVIntern] >= 0x909) {
        [self LockDB:NO];
        DBOperations *dbop = [[DBOperations alloc] init];
        [dbop CreateLimitField];
        if ([self GetVIntern] >= 0x99b) [dbop CreateMTHideField];
        if ([self GetVIntern] >= 0x9dd) [dbop CreateJoinField];
        if ([self GetVIntern] >= 0xa42) [dbop CreateMTSearcKeyField];
        if ([self GetVIntern] >= 0xa8c) [dbop CreateRCMessageField];
        if ([self GetVIntern] >= 0xaca) [dbop CreateMTTimesPlayedField];
        if ([self GetVIntern] >= 0xafb) [dbop CreateSpotifyFields];
        [dbop CreateMixxtapeIndizes];
        [dbop release];
        [self UnlockDB];
    }
}

- (void)RemoveOldServer {
    NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey:@"keyserverlist"];
    if (list != nil && [list count] != 0) {
        NSMutableArray *servers = [[NSMutableArray alloc] init];
        for (NSUInteger i = 0; i < [list count]; i++)
            [servers addObject:[m_servercomm decodeServerEntry:[list objectAtIndex:i]]];
        [self DeleteExistingServerDirs:servers];
        [servers release];
    }
}

- (void)DeleteExistingServerDirs:(NSArray *)existingServerDirs {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSUInteger i = 0; i < [existingServerDirs count]; i++) {
        ServerEntry *se = [existingServerDirs objectAtIndex:i];
        NSString *dir = [self CreateServerDir2:[se servername] withserverid:[se serverid]];
        [fm removeItemAtPath:dir error:nil];
    }
}

- (void)CheckCleanDataBase {
    long now = [[[UIApplication sharedApplication] delegate] ConvertDate:[NSDate date]];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    long last = [defs integerForKey:@"k_38_lastcleaned"];
    if ((now - last) >= 0x15180) {
        [self LockDB:NO];
        DBOperations *dbop = [[DBOperations alloc] init];
        [dbop CleanDataBase];
        [dbop release];
        [self UnlockDB];
        [defs setInteger:now forKey:@"k_38_lastcleaned"];
        [defs synchronize];
        [self CleanTemp];
    }
}

- (void)DeleteDoubleEntries {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs integerForKey:@"keydeldouble"] <= 0x9f1) {
        DBOperations *dbop = [[DBOperations alloc] init];
        [self LockDB:NO];
        [dbop DeleteDoubleEntries];
        [self UnlockDB];
        [dbop release];
        [defs setInteger:m_vintern forKey:@"keydeldouble"];
        [defs synchronize];
    }
}

- (void)UnlockDB {
    [m_dblock unlock];
}

- (void)LockDB:(BOOL)lockDB {
    if (![m_dblock tryLock])
        [m_dblock lock];
}

#pragma mark - version

- (int)CalcVIntern {
    // CFBundleVersion "major.minor" -> major * 1000 + minor
    NSArray *parts = [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] componentsSeparatedByString:@"."];
    int major = 1, minor = 0;
    if (parts != nil && [parts count] != 0) {
        for (NSUInteger i = 0; i < [parts count]; i++) {
            int v = [[parts objectAtIndex:i] intValue];
            if (i == 0) major = v;
            else if (i == 1) minor = v;
        }
    }
    return major * 1000 + minor;
}

- (int)GetVIntern {
    return m_vintern;
}

- (int)GetFlagForIndex:(int)flagForIndex {
    if ((unsigned)flagForIndex > 5)
        return 0;
    return 1 << flagForIndex;
}

- (int)ModifyStateFlags:(int)stateFlags {
    return stateFlags;
}

#pragma mark - simple accessors

- (id)GetFormatter { return m_formatter; }
- (id)GetRadioVC { return m_radioVC; }
- (id)GetChannelInfos { return m_channelinfos; }
- (id)GetStreamer { return m_streamer; }
- (id)GetUID { return m_uid; }
- (id)GetServerComm { return m_servercomm; }
- (id)GetiPadMainVC { return m_ipadmainvc; }
- (id)GetBroadcast { return mBroadcast; }
- (id)GetPrinterSubDir { return m_printersubdir; }
- (id)GetVideothekSubDir { return m_videotheksubdir; }
- (id)GetAdvertSubDir { return m_advertsubdir; }
- (id)GetHomeDir { return m_homedir; }
- (BOOL)IsTMPresent { return m_tmpresent; }
- (void)SetCanRotateiPad { }
- (BOOL)canRotateiPad { return m_canRotateiPad; }
- (id)mMoviePlayerGlobal { return mMoviePlayerGlobal; }
- (BOOL)shouldAutorotateTo:(int)shouldAutorotateTo { return shouldAutorotateTo == 3; }
- (void)Registerffmpeg { }
- (void)PostAK:(id)postAK { }
- (void)SetWebViewBlack:(id)webViewBlack { }
- (void)AirplayRestart { }
- (void)SendChangesToRemoteApps { }
- (void)GetDetailsForChoosenChannels:(BOOL)detailsForChoosenChannels { }
- (void)ipadCheckChannels { }
- (id)GetOldRunningSongInfos:(int)oldRunningSongInfos { return [[[NSMutableArray alloc] init] autorelease]; }
- (void)RemoteCtrl_UpdateCurrentServer { }
- (void)RemoteCtrl_UpdateServer:(id)remoteCtrl_UpdateServer { }
- (id)RemoteCtrl_LastConnectedServer { return nil; }
- (void)GetPasswordsForRCServer:(id)passwordsForRCServer { }
- (void)FilteroutLocalServer:(id)filteroutLocalServer { }
- (id)IsCurrentRCServer:(id)currentRCServer { return nil; }
- (id)GetBroadcastServers { return nil; }
- (id)GetNameForCurrentRemoteDB { return nil; }
- (void)DeleteSpotifyFolder:(id)spotifyFolder { }
- (long long)GetULLVal:(id)uLLVal { return [uLLVal longLongValue]; }
- (BOOL)IsActivated:(id)activated { return ([activated StateFlags] >> 27) & 1; }
- (void)SetDeliveredStatus { [[NSUserDefaults standardUserDefaults] setInteger:-1 forKey:@"TMDeliveryStatus"]; }
- (int)GetDeliveredStatus { return (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"TMDeliveryStatus"]; }
- (void)GetVideothek:(id)videothek { }
- (BOOL)CheckGlobalUrl:(id)globalUrl { return globalUrl != nil && [globalUrl length] != 0; }
- (id)AddStandardParameterAndEscape:(id)standardParameterAndEscape {
    NSRange q = [standardParameterAndEscape rangeOfString:@"?"];
    return [[NSString stringWithFormat:@"%@%@vintern=%i&id=%@&currentchl=%i&appname=%@", standardParameterAndEscape, (q.location == NSNotFound ? @"?" : @"&"), [self GetVIntern], [self GetUID], m_lastchannelid, @"RadiofxHD"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - reachability (offline-only port)

- (BOOL)IsOnline { return NO; }
- (BOOL)isInetAvailable { return NO; }

#pragma mark - streamer (live radio streaming is not part of this port)

- (void)StopStreamer {
    if (m_streamer != nil) {
        [m_streamer release];
        m_streamer = nil;
    }
}

- (BOOL)GetStreamerPlaying { return NO; }

- (void)SetStreamerVolume:(float)streamerVolume {
    m_volume = streamerVolume;
    if ([[[UIApplication sharedApplication] delegate] g_reduce])
        m_volume = streamerVolume * 0.25f;
    if ([[[UIApplication sharedApplication] delegate] g_mute])
        m_volume = 0;
    [m_kh SetWdrPlayerVolume:streamerVolume];
}

- (void)SetMp3Metadata:(id)mp3Metadata {
    if (m_radioVC != nil)
        [m_radioVC SetMp3Metadata:mp3Metadata];
}

- (void)PlayPauseFromExtern { }

- (int)GetNumForChannelID:(int)numForChannelID {
    if (m_channelinfos == nil) return -1;
    return -1;
}

- (void)SwitchToChannel:(int)switchToChannel withAni:(BOOL)ani { }

- (id)createMD5HashForTitle:(id)title withInterpret:(id)interpret {
    NSString *s = [NSString stringWithFormat:@"klf89%@b$345fsd%@", title, interpret];
    const char *c = [s cStringUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(c, (CC_LONG)strlen(c), digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [out appendFormat:@"%02x", digest[i]];
    return out;
}

#pragma mark - file / path helpers

- (void)CreateAdvertisingDir:(int)advertisingDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *sub = nil;
    if (advertisingDir == 0) sub = m_videotheksubdir;
    else if (advertisingDir == 1) sub = m_advertsubdir;
    else if (advertisingDir == 2) sub = m_printersubdir;
    NSString *path = [NSString stringWithFormat:@"%@/%@", m_homedir, sub];
    if (![fm fileExistsAtPath:path])
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

- (id)GetBrandingPicturePath {
    return [NSString stringWithFormat:@"%@/%@/brandingimage.png", [self GetHomeDir], [self GetAdvertSubDir]];
}

- (BOOL)IsBrandingPicturePresent {
    NSString *p = [self GetBrandingPicturePath];
    if (p == nil) return NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:p];
}

- (id)SubReplace:(id)subReplace {
    return [[[subReplace stringByReplacingOccurrencesOfString:@":" withString:@"_"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@"\\" withString:@"_"];
}

- (id)Buildfoldername:(id)buildfoldername {
    if ([buildfoldername folderid] == -44)
        return @"IPODLIB";
    return [NSString stringWithFormat:@"%lld-%@", [buildfoldername folderid], [self SubReplace:[buildfoldername foldername]]];
}

- (id)CreateServerDir2:(id)serverDir2 withserverid:(int)serverid {
    return [NSString stringWithFormat:@"%@/%@/%@/", [self GetHomeDir], ([[[UIApplication sharedApplication] delegate] m_iscuedia] ? @"Documents" : @"Library/Caches"), [serverDir2 uppercaseString]];
}

- (id)CreateServerDir:(id)serverDir withfolderobject:(id)folderobject {
    id name; int sid;
    if ([folderobject serverid] == [serverDir serverid]) {
        name = [serverDir servername];
        sid = [serverDir serverid];
    } else if ([serverDir remotesvr] != nil && [[serverDir remotesvr] length] != 0) {
        name = [serverDir remotesvr];
        sid = [serverDir remoteserverid];
    } else {
        name = [serverDir browsedserver];
        sid = [serverDir browseid];
    }
    return [self CreateServerDir2:name withserverid:sid];
}

- (void)BuildAndCheckFilePathes:(id)co withfm:(id)fm withserverdir:(id)serverdir withCheck:(BOOL)check {
    if ([co m_folderid] == -33) return;
    if ([co ID] == -5) {
        [co setM_picturepath:[[[UIApplication sharedApplication] delegate] GetBrandingPicturePath]];
        return;
    }
    if ([co m_folderid] == -66) {
        [co setM_filepath:@"d"];
        [co setM_picturepath:[NSString stringWithFormat:@"%@%@.jpg", [[[UIApplication sharedApplication] delegate] m_spotifypicdir], [co m_spotifyid]]];
        return;
    }
    NSString *title = [self SubReplace:[co m_title]];
    if ([title length] >= 0x1f) title = [title substringToIndex:0x1e];
    NSString *interpret = [self SubReplace:([co m_folderid] == 3 ? [co m_albumname] : [co m_interpret])];
    if ([interpret length] >= 0x1f) interpret = [interpret substringToIndex:0x1e];
    NSString *pic;
    if ([co m_folderid] == -44) {
        pic = [NSString stringWithFormat:@"%@%lld.jpg", serverdir, [co m_ipodid]];
    } else {
        [co setM_filepath:[NSString stringWithFormat:@"%@%lld-%@-%@.mp3", serverdir, [co ID], interpret, title]];
        pic = [NSString stringWithFormat:@"%@%lld-%@-%@.jpg", serverdir, [co ID], interpret, title];
    }
    [co setM_picturepath:pic];
    if (check) {
        if (![fm fileExistsAtPath:[co m_picturepath]])
            [co setM_picturepath:nil];
        if ([co m_folderid] != -44) {
            if (![fm fileExistsAtPath:[co m_filepath]])
                [co setM_filepath:nil];
        }
    }
}

- (id)BuildSmallPicpath:(id)buildSmallPicpath {
    if (buildSmallPicpath == nil) return nil;
    return [NSString stringWithFormat:@"%@_.jpg", [buildSmallPicpath stringByDeletingPathExtension]];
}

- (id)CreatePrescrollerKey:(long long)prescrollerKey withserverid:(int)serverid withipodid:(long long)ipodid withspotifyid:(id)spotifyid {
    return [NSString stringWithFormat:@"%lld-%i-%lld-%@", prescrollerKey, serverid, ipodid, spotifyid];
}

- (id)CreateTextureKey:(id)textureKey {
    return [NSString stringWithFormat:@"%lld-%lld-%i-%lld-%@", [textureKey ID], [textureKey m_folderid], [textureKey m_serverid], [textureKey m_ipodid], [textureKey m_spotifyid]];
}

- (void)AddSkipBackupAttributeToFile:(id)skipBackupAttributeToFile {
    if (m_ios501min) {
        u_int8_t attr = 1;
        setxattr([skipBackupAttributeToFile fileSystemRepresentation], "com.apple.MobileBackup", &attr, 1, 0, 0);
    }
}

- (void)DeleteSnapShots {
    NSString *bid = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
    NSString *dir = [NSString stringWithFormat:@"%@/%@/Snapshots/%@/", [self GetHomeDir], @"Library/Caches", bid];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:dir];
    NSString *f;
    while ((f = [en nextObject]) != nil) {
        [en skipDescendents];
        if (![[[en fileAttributes] fileType] isEqualToString:NSFileTypeDirectory]) {
            if ([f length] > 4) {
                if ([@".JPG" caseInsensitiveCompare:[f substringFromIndex:[f length] - 4]] == NSOrderedSame)
                    [fm removeItemAtPath:[NSString stringWithFormat:@"%@%@", dir, f] error:nil];
            }
        }
    }
}

- (void)CleanTemp {
    NSArray *dirs = [NSArray arrayWithObjects:@"tmp", nil];
    for (NSString *sub in dirs) {
        NSString *dir = [NSString stringWithFormat:@"%@/%@/", [self GetHomeDir], sub];
        NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:dir];
        NSString *f;
        while ((f = [en nextObject]) != nil) {
            [en skipDescendents];
            if (![[[en fileAttributes] fileType] isEqualToString:NSFileTypeDirectory])
                [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@%@", dir, f] error:nil];
        }
    }
}

- (void)RemoveVirtFolder:(NSMutableArray *)virtFolder alsoIPOD:(BOOL)alsoIPOD alsospotify:(BOOL)alsospotify {
    NSInteger i = (NSInteger)[virtFolder count] - 1;
    while (i >= 0) {
        id f = [virtFolder objectAtIndex:i];
        if ([f folderid] == -33)
            [virtFolder removeObjectAtIndex:i];
        else if ([f folderid] == -44 && alsoIPOD)
            [virtFolder removeObjectAtIndex:i];
        else if ([f folderid] == -66 && alsospotify)
            [virtFolder removeObjectAtIndex:i];
        i--;
    }
}

- (void)CheckJoinFolder:(id)joinFolder withszfoldername:(char *)szfoldername {
    if ([joinFolder joinid] == 0) return;
    if ([joinFolder folderid] != [joinFolder joinid]) return;
    if (szfoldername != 0 && *szfoldername != 0) {
        size_t len = strlen(szfoldername);
        for (size_t i = 0; i < len; i++) {
            if ((unsigned char)szfoldername[i] == 0xa0) {
                szfoldername[i] = 0;
                [joinFolder setFoldername:[[[UIApplication sharedApplication] delegate] ConvertNSStringFromC:szfoldername]];
                return;
            }
        }
    }
    NSRange r = [[joinFolder foldername] rangeOfString:@" " options:NSBackwardsSearch];
    if (r.location != NSNotFound)
        [joinFolder setFoldername:[[joinFolder foldername] substringToIndex:r.location]];
}

- (id)ConvertNSStringFromC:(char *)s {
    return [NSString stringWithCString:s encoding:NSISOLatin1StringEncoding];
}

- (const char *)ConvertNSString:(id)nSString withorder:(int)order {
    NSStringEncoding e1, e2, e3;
    if (order == 0) { e1 = NSISOLatin1StringEncoding; e2 = NSUTF8StringEncoding; e3 = NSUTF8StringEncoding; }
    else if (order == 4) { e1 = NSUTF8StringEncoding; e2 = NSISOLatin1StringEncoding; e3 = NSISOLatin1StringEncoding; }
    else { e1 = NSUTF8StringEncoding; e2 = NSISOLatin1StringEncoding; e3 = NSISOLatin1StringEncoding; }
    const char *c = [nSString cStringUsingEncoding:e1];
    if (c != 0) return c;
    c = [nSString cStringUsingEncoding:e2];
    if (c != 0) return c;
    return [nSString cStringUsingEncoding:e3];
}

#pragma mark - time helpers

- (id)ConvertTime:(long)time {
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:(double)time];
    NSInteger off = [[NSTimeZone defaultTimeZone] secondsFromGMTForDate:d];
    return [d dateByAddingTimeInterval:(double)(0 - off)];
}

- (long)ConvertDate:(id)date {
    NSInteger off = [[NSTimeZone defaultTimeZone] secondsFromGMTForDate:date];
    return (long)[[date dateByAddingTimeInterval:(double)off] timeIntervalSince1970];
}

- (void)GetLimitationVars:(int *)limitationVars withsecofday:(long *)secofday {
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *c = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitWeekday) fromDate:[NSDate date]];
    [cal release];
    NSInteger wd = [c weekday];
    *limitationVars = (int)((wd - 1) == 0 ? 7 : (wd - 1));
    *secofday = (long)([c hour] * 3600 + [c minute] * 60 + [c second]);
}

- (void)GetFolderLimitationForDayIndex:(int)dayIndex withstarttime:(int *)starttime withendtime:(int *)endtime withFolderobject:(id)folderobject {
    *starttime = 0;
    *endtime = 0x15180;
    if (folderobject == nil) return;
    if ([folderobject limitations] == nil || [[folderobject limitations] length] == 0) return;
    NSArray *days = [[folderobject limitations] componentsSeparatedByString:@","];
    if (days == nil || (NSUInteger)dayIndex >= [days count]) return;
    const char *c = [self ConvertNSString:[days objectAtIndex:dayIndex] withorder:0];
    if (c == 0) return;
    int h1, m1, h2, m2;
    if (sscanf(c, "%02d:%02d-%02d:%02d", &h1, &m1, &h2, &m2) != 4) return;
    *starttime = h1 * 3600 + m1 * 60;
    *endtime = h2 * 3600 + m2 * 60;
    if (*endtime < *starttime)
        *endtime += 0x5180 + 0x10000; // 86400 (next day)
}

#pragma mark - connection flags

- (void)setm_connectioninuse:(BOOL)inuse withconnindex:(int)connindex {
    pthread_mutex_lock(&_mutexConnectionInUse);
    m_connectioninuse[connindex] = inuse;
    pthread_mutex_unlock(&_mutexConnectionInUse);
}

- (BOOL)getm_connectioninuse:(int)connindex {
    pthread_mutex_lock(&_mutexConnectionInUse);
    pthread_mutex_unlock(&_mutexConnectionInUse);
    return m_connectioninuse[connindex];
}

- (BOOL)LockConnection:(int)lockConnection observeValues:(int)observeValues {
    for (;;) {
        if ([self g_end]) return NO;
        pthread_mutex_lock(&_mutexConnectionInUse);
        if (!m_connectioninuse[lockConnection]) {
            m_connectioninuse[lockConnection] = YES;
            pthread_mutex_unlock(&_mutexConnectionInUse);
            return YES;
        }
        pthread_mutex_unlock(&_mutexConnectionInUse);
        [NSThread sleepForTimeInterval:0.1];
        BOOL stop;
        if (observeValues == 2) {
            if ([self g_end]) return NO;
            if ([m_kh GetCancelCopy]) return NO;
            stop = [self getm_reconnecting:lockConnection];
        } else if (observeValues == 1) {
            stop = g_bShutdown;
        } else {
            continue;
        }
        if (stop) return NO;
    }
}

- (void)setm_reconnecting:(BOOL)reconnecting withconnindex:(int)connindex {
    m_reconnecting[connindex] = reconnecting;
}

- (BOOL)getm_reconnecting:(int)connindex {
    return m_reconnecting[connindex];
}

#pragma mark - advertising texts

- (id)GetNextAdvertisingText:(char *)nextAdvertisingText {
    if ([m_advertisingtexts count] == 0) return nil;
    NSMutableString *s = [NSMutableString stringWithCapacity:0];
    for (int rep = 0; rep < 1; rep++) {
        for (NSUInteger i = 0; i < [m_advertisingtexts count]; i++)
            [s appendString:[NSString stringWithFormat:@"%@  ++  ", [m_advertisingtexts objectAtIndex:i]]];
    }
    if ([s length] >= 6)
        [s deleteCharactersInRange:NSMakeRange([s length] - 6, 6)];
    return [s length] != 0 ? s : nil;
}

- (void)SaveAdvertisingTexts {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if (defs != nil) {
        [defs setObject:m_advertisingtexts forKey:@"keyadvertisingtexts"];
        [defs synchronize];
    }
}

- (void)LoadAdvertisingTexts {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if (defs != nil) {
        NSArray *a = [defs arrayForKey:@"keyadvertisingtexts"];
        if (a != nil) {
            [m_advertisingtexts removeAllObjects];
            [m_advertisingtexts addObjectsFromArray:a];
        }
    }
}

- (void)LockPrinter:(BOOL)lockPrinter {
    if (lockPrinter) [m_printerlock lock];
    else [m_printerlock unlock];
}

#pragma mark - wait view

- (void)ShowCleanView {
    m_cleanview = [[UIView alloc] initWithFrame:[[m_ipadmainvc view] frame]];
    [m_cleanview setBackgroundColor:[UIColor clearColor]];
    CGRect vf = [[m_ipadmainvc view] frame];
    UIActivityIndicatorView *ai = [[UIActivityIndicatorView alloc] initWithFrame:
        CGRectMake((vf.size.width - 25.0f) * 0.5f, (vf.size.height - 25.0f) * 0.5f, 25.0f, 25.0f)];
    [ai setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhite];
    [m_cleanview addSubview:ai];
    [ai release];
    [ai startAnimating];
    CGRect af = [ai frame];
    CGRect cf = [m_cleanview frame];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, (af.origin.y - 30.0f) - 10.0f, cf.size.width, 30.0f)];
    [l setBackgroundColor:[UIColor clearColor]];
    [l setTextColor:[UIColor whiteColor]];
    [l setFont:[UIFont boldSystemFontOfSize:20.0f]];
    [l setTextAlignment:NSTextAlignmentCenter];
    [l setText:@"Cleaning, please wait..."];
    [m_cleanview addSubview:l];
    [l release];
    [[m_ipadmainvc view] addSubview:m_cleanview];
    [m_cleanview release];
}

- (void)HideCleanView {
    if (m_cleanview != nil) {
        [m_cleanview removeFromSuperview];
        m_cleanview = nil;
    }
}

#pragma mark - start image

- (id)GetStartImageView {
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    UIImage *img = [self NonCachedImage:@"Defaultipad-Landscape"];
    if (img == nil) return nil;
    BOOL ipad = [self m_isipad];
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, ipad ? 1024.0f : 480.0f, ipad ? 768.0f : 320.0f)];
    [iv setImage:img];
    return iv;
}

- (void)ReleaseStartImage {
    if (m_startimage != nil) {
        [m_startimage removeFromSuperview];
        m_startimage = nil;
    }
}

- (void)StartPicAnimation {
    if (m_startedpicanimation) return;
    m_startedpicanimation = YES;
    [UIView beginAnimations:@"ipadstartanimation0" context:0];
    [UIView setAnimationDuration:1.0];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(ReleaseStartImage)];
    [m_startimage setAlpha:0.0f];
    [UIView commitAnimations];
}

- (CGSize)GetiPadSize {
    if (m_isipad) return CGSizeMake(1024.0f, 768.0f);
    return CGSizeMake(480.0f, 320.0f);
}

- (id)NonCachedImage:(id)nonCachedImage {
    return [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:nonCachedImage ofType:@"png"]];
}

- (id)GetBlueColor {
    return [UIColor colorWithRed:0.24f green:0.3f blue:0.42f alpha:1.0f];
}

- (void)ShowErrorAndWait:(id)errorAndWait withType:(int)type {
    m_errorpressed = NO;
    UIAlertView *av;
    if (type != 0)
        av = [[UIAlertView alloc] initWithTitle:@"Wiedergabe nicht möglich!" message:errorAndWait delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
    else
        av = [[UIAlertView alloc] initWithTitle:@"Achtung!" message:errorAndWait delegate:self cancelButtonTitle:@"Beenden" otherButtonTitles:nil];
    [av autorelease];
    [av setDelegate:self];
    [av show];
    int n = 1;
    while (!m_errorpressed) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, 0);
        if (m_errorpressed) break;
        if (n >= 0x12c) break;
        n++;
    }
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (m_uial_nointernet != alertView) {
        m_errorpressed = YES;
        return;
    }
    [[[UIApplication sharedApplication] delegate] DeleteSnapShots];
    exit(0);
}

- (BOOL)IsInArray:(id)inArray withsearchstring:(id)searchstring {
    for (NSUInteger i = 0; i < [inArray count]; i++) {
        if ([[inArray objectAtIndex:i] isEqualToString:searchstring])
            return YES;
    }
    return NO;
}

- (BOOL)IsPossibleChar:(id)possibleChar {
    NSString *last = [possibleChar substringFromIndex:[possibleChar length] - 1];
    for (NSUInteger i = 0; i < [m_possiblechars count]; i++) {
        if ([last caseInsensitiveCompare:[m_possiblechars objectAtIndex:i]] == NSOrderedSame)
            return YES;
    }
    return NO;
}

#pragma mark - drawing helpers

- (CGContextRef)BeginImageContext:(CGSize)size {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)size.width, (size_t)size.height, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CGContextClearRect(ctx, CGRectMake(0, 0, size.width, size.height));
    return ctx;
}

- (id)EndImageContext:(CGContextRef)endImageContext {
    CGImageRef cgi = CGBitmapContextCreateImage(endImageContext);
    UIImage *img = [UIImage imageWithCGImage:cgi];
    CGImageRelease(cgi);
    CGContextRelease(endImageContext);
    return img;
}

- (void)OwndrawAtPoint:(CGContextRef)ctx withtext:(id)text drawAtPoint:(CGPoint)pt forWidth:(int)width withFont:(id)font lineBreakMode:(int)lineBreakMode {
    NSString *s = [NSString stringWithString:text];
    if (width >= 1) {
        BOOL cut = NO;
        CGSize sz = [s sizeWithFont:font constrainedToSize:CGSizeMake(600.0f, 600.0f)];
        while (sz.width > (float)width && [s length] >= 3) {
            s = [NSString stringWithFormat:@"%@", [s substringToIndex:[s length] - 1]];
            sz = [[NSString stringWithFormat:@"%@...", s] sizeWithFont:font constrainedToSize:CGSizeMake(600.0f, 600.0f)];
            cut = YES;
        }
        if (cut)
            s = [NSString stringWithFormat:@"%@...", s];
    }
    const char *cs = [self ConvertNSString:s withorder:4];
    const char *fn = [self ConvertNSString:[font fontName] withorder:0];
    if (text != nil && fn != 0) {
        CGContextSelectFont(ctx, fn, [font pointSize], kCGEncodingMacRoman);
        CGContextShowTextAtPoint(ctx, pt.x, pt.y, cs, strlen(cs));
    }
}

- (id)CreateStretchedImage:(id)stretchedImage withImage:(id)image withLeftCap:(float)leftCap withTopCap:(float)topCap withInvert:(BOOL)invert {
    UIImage *img = image != nil ? image : [UIImage imageNamed:stretchedImage];
    if (img == nil) return nil;
    if (m_ios < 5)
        return [img stretchableImageWithLeftCapWidth:(int)leftCap topCapHeight:(int)topCap];
    float l = leftCap, t = topCap;
    if (topCap > 0) t = MIN(topCap, [img size].height);
    if (leftCap > 0) l = MIN(leftCap, [img size].width);
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(t, l, t, l)];
}

- (void)HSVtoRGB:(float *)r withgreen:(float *)g withblue:(float *)b withhue:(float)h withsat:(float)s withval:(float)v {
    if (s == 0) { *r = v; *g = v; *b = v; return; }
    float hh = h / 60.0f;
    int i = (int)floorf(hh);
    float f = hh - (float)i;
    float p = (1.0f - s) * v;
    float q = (1.0f - (f * s)) * v;
    float t = (1.0f - ((1.0f - f) * s)) * v;
    switch (i) {
        case 0: *r = v; *g = t; *b = p; break;
        case 1: *r = q; *g = v; *b = p; break;
        case 2: *r = p; *g = v; *b = t; break;
        case 3: *r = p; *g = q; *b = v; break;
        case 4: *r = t; *g = p; *b = v; break;
        default: *r = v; *g = p; *b = q; break;
    }
}

- (void)RGBtoHSV:(float)r withgreen:(float)g withblue:(float)b withue:(float *)h withsat:(float *)s withval:(float *)v {
    float mx = r > g ? r : g; if (b > mx) mx = b;
    float mn = r < g ? r : g; if (b < mn) mn = b;
    *v = mx;
    if (mx == 0) { *s = 0; *h = -1.0f; return; }
    *s = (mx - mn) / mx;
    float d = mx - mn;
    if (r == mx) *h = (g - b) / d;
    else if (g == mx) *h = 2.0f + (b - r) / d;
    else *h = 4.0f + (r - g) / d;
    *h *= 60.0f;
    if (*h < 0) *h += 360.0f;
}

- (void)HSLtoRGB:(float *)r withgreen:(float *)g withblue:(float *)b withhue:(double)h withsat:(double)s withlum:(double)l {
    double rr, gg, bb;
    if (s > 0) {
        double q = (l < 0.5) ? l * (1.0 + s) : (l + s) - (l * s);
        double p = 2.0 * l - q;
        double hh = h * 6.0;
        int i = (int)hh;
        double f = hh - (double)i;
        double qq = q, pp = p;
        double tmp1 = pp + (qq - pp) * f;
        double tmp2 = pp + (qq - pp) * (1.0 - f);
        switch (i) {
            case 0: rr = qq; gg = tmp1; bb = pp; break;
            case 1: rr = tmp2; gg = qq; bb = pp; break;
            case 2: rr = pp; gg = qq; bb = tmp1; break;
            case 3: rr = pp; gg = tmp2; bb = qq; break;
            case 4: rr = tmp1; gg = pp; bb = qq; break;
            default: rr = qq; gg = pp; bb = tmp2; break;
        }
    } else {
        rr = gg = bb = l;
    }
    *r = (float)rr; *g = (float)gg; *b = (float)bb;
}

- (id)CreateTableCellBackgroundImage:(CGRect)rect selected:(BOOL)selected {
    size_t w = (size_t)rect.size.width, h = (size_t)rect.size.height;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGContextSetRenderingIntent(ctx, kCGRenderingIntentAbsoluteColorimetric);
    CGFloat comps[8];
    if (selected) { comps[0]=0.25; comps[1]=0.35; comps[2]=0.55; comps[3]=1; comps[4]=0.15; comps[5]=0.2; comps[6]=0.35; comps[7]=1; }
    else          { comps[0]=0.2;  comps[1]=0.2;  comps[2]=0.2;  comps[3]=1; comps[4]=0.1;  comps[5]=0.1;  comps[6]=0.1;  comps[7]=1; }
    CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, h), 0);
    CGImageRef cgi = CGBitmapContextCreateImage(ctx);
    UIImage *img = [[UIImage alloc] initWithCGImage:cgi];
    CGImageRelease(cgi);
    CGGradientRelease(grad);
    CGColorSpaceRelease(cs);
    CGContextRelease(ctx);
    return [img autorelease];
}

@end
