// Recovered from the -[ServerEntry ...] methods (0x204b0 - 0x21786).
#import "ServerEntry.h"
#import "RadioAppDelegate.h"

@implementation ServerEntry
@synthesize m_songdragdelay, m_ambienceCollectionID, m_useAmbience, spotifypassword, spotifyuser, printfooterimage, printheaderimage, printheadertext, printfootertext, printerip, adverttexttime, fbweekday, origserverid, rcdeviceid, hosting, remotecontrolpwd, displayname, trailerimagetime, isnewkeyentry, browseid, browsedserverip, browsedserver, remoteserverid, remotepwd, remotesvr, useremote, reserved_s2, reserved_s1, reserved_i2, reserved_i1, StateFlags, choosen, serverip, serverid, lastpassword, servername;

- (id)init {
    self = [super init];
    if (self) {
        servername = nil;
        lastpassword = nil;
        serverid = 0;
        choosen = 0;
        serverip = nil;
        StateFlags = [(RadioAppDelegate *)[[UIApplication sharedApplication] delegate] ModifyStateFlags:0];
        reserved_i1 = 0;
        reserved_i2 = 0;
        reserved_s1 = nil;
        reserved_s2 = nil;
        useremote = 0;
        remotesvr = nil;
        remotepwd = nil;
        remoteserverid = -1;
        browsedserver = nil;
        browseid = -1;
        browsedserverip = nil;
        isnewkeyentry = 0;
        trailerimagetime = 0;
        displayname = nil;
        remotecontrolpwd = nil;
        hosting = 0;
        rcdeviceid = nil;
        origserverid = -1;
        fbweekday = nil;
        adverttexttime = 0;
        printerip = nil;
        printfootertext = nil;
        printheadertext = nil;
        printheaderimage = nil;
        printfooterimage = nil;
        spotifyuser = nil;
        spotifypassword = nil;
        m_useAmbience = 0;
        m_ambienceCollectionID = 0;
        m_songdragdelay = 0;
    }
    return self;
}

- (void)dealloc {
    if (fbweekday) { [fbweekday release]; fbweekday = nil; }
    if (lastpassword) { [lastpassword release]; lastpassword = nil; }
    if (servername) { [servername release]; servername = nil; }
    if (serverip) { [serverip release]; serverip = nil; }
    if (reserved_s1) { [reserved_s1 release]; reserved_s1 = nil; }
    if (reserved_s2) { [reserved_s2 release]; reserved_s2 = nil; }
    if (remotesvr) { [remotesvr release]; remotesvr = nil; }
    if (remotepwd) { [remotepwd release]; remotepwd = nil; }
    if (browsedserver) { [browsedserver release]; browsedserver = nil; }
    if (browsedserverip) { [browsedserverip release]; browsedserverip = nil; }
    if (displayname) { [displayname release]; displayname = nil; }
    if (remotecontrolpwd) { [remotecontrolpwd release]; remotecontrolpwd = nil; }
    if (rcdeviceid) { [rcdeviceid release]; rcdeviceid = nil; }
    if (printerip) { [printerip release]; printerip = nil; }
    if (printfootertext) { [printfootertext release]; printfootertext = nil; }
    if (printheadertext) { [printheadertext release]; printheadertext = nil; }
    if (printheaderimage) { [printheaderimage release]; printheaderimage = nil; }
    if (printfooterimage) { [printfooterimage release]; printfooterimage = nil; }
    if (spotifyuser) { [spotifyuser release]; spotifyuser = nil; }
    if (spotifypassword) { [spotifypassword release]; spotifypassword = nil; }
    [super dealloc];
}

- (id)initWithCoder:(NSCoder *)coder {
    ServerEntry *obj = [[ServerEntry alloc] init];
    [obj setServername:[coder decodeObjectForKey:@"servername"]];
    [obj setLastpassword:[coder decodeObjectForKey:@"lastpassword"]];
    [obj setServerid:[coder decodeIntForKey:@"serverid"]];
    [obj setChoosen:[coder decodeIntForKey:@"choosen"]];
    [obj setServerip:[coder decodeObjectForKey:@"serverip"]];
    [obj setStateFlags:[coder decodeIntForKey:@"StateFlags"]];
    [obj setReserved_i1:[coder decodeIntForKey:@"reserved_i1"]];
    [obj setReserved_i2:[coder decodeIntForKey:@"reserved_i2"]];
    [obj setReserved_s1:[coder decodeObjectForKey:@"reserved_s1"]];
    [obj setReserved_s2:[coder decodeObjectForKey:@"reserved_s2"]];
    [obj setUseremote:[coder decodeIntForKey:@"useremote"]];
    [obj setRemotesvr:[coder decodeObjectForKey:@"remotesvr"]];
    [obj setRemotepwd:[coder decodeObjectForKey:@"remotepwd"]];
    [obj setRemoteserverid:[coder decodeIntForKey:@"remotesvrid"]];
    [obj setBrowsedserver:[coder decodeObjectForKey:@"kbrowsedserver"]];
    [obj setBrowseid:[coder decodeIntForKey:@"kbrowseid"]];
    [obj setBrowsedserverip:[coder decodeObjectForKey:@"kbrowsedserverip"]];
    [obj setTrailerimagetime:[coder decodeIntForKey:@"ktrailerimagetime"]];
    [obj setDisplayname:[coder decodeObjectForKey:@"kdisplayname"]];
    [obj setRemotecontrolpwd:[coder decodeObjectForKey:@"keyremotecontrolpwd"]];
    [obj setHosting:[coder decodeIntForKey:@"keyhosting"]];
    [obj setOrigserverid:[coder decodeIntForKey:@"keyorigserverid"]];
    [obj setRcdeviceid:[coder decodeObjectForKey:@"keyrcdeviceid"]];
    [obj setFbweekday:[coder decodeObjectForKey:@"keyfbweekday2"]];
    [obj setAdverttexttime:[coder decodeIntForKey:@"keyadverttexttime"]];
    [obj setPrinterip:[coder decodeObjectForKey:@"keyprinterip"]];
    [obj setPrintfootertext:[coder decodeObjectForKey:@"keypftext"]];
    [obj setPrintheadertext:[coder decodeObjectForKey:@"keyphtext"]];
    [obj setPrintheaderimage:[coder decodeObjectForKey:@"keyphimage"]];
    [obj setPrintfooterimage:[coder decodeObjectForKey:@"keypfimage"]];
    [obj setSpotifyuser:[coder decodeObjectForKey:@"keyspotifyuser"]];
    [obj setSpotifypassword:[coder decodeObjectForKey:@"keyspotifypassword"]];
    [obj setM_useAmbience:[coder decodeIntForKey:@"keyuseambience"]];
    [obj setM_ambienceCollectionID:[coder decodeIntForKey:@"keyambiencecollectionid"]];
    [obj setM_songdragdelay:[coder decodeIntForKey:@"keysongdragdelay"]];
    return obj;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:servername forKey:@"servername"];
    [coder encodeObject:lastpassword forKey:@"lastpassword"];
    [coder encodeInt:serverid forKey:@"serverid"];
    [coder encodeInt:choosen forKey:@"choosen"];
    [coder encodeObject:serverip forKey:@"serverip"];
    [coder encodeInt:StateFlags forKey:@"StateFlags"];
    [coder encodeInt:reserved_i1 forKey:@"reserved_i1"];
    [coder encodeInt:reserved_i2 forKey:@"reserved_i2"];
    [coder encodeObject:reserved_s1 forKey:@"reserved_s1"];
    [coder encodeObject:reserved_s2 forKey:@"reserved_s2"];
    [coder encodeInt:useremote forKey:@"useremote"];
    [coder encodeObject:remotesvr forKey:@"remotesvr"];
    [coder encodeObject:remotepwd forKey:@"remotepwd"];
    [coder encodeInt:remoteserverid forKey:@"remotesvrid"];
    [coder encodeInt:browseid forKey:@"kbrowseid"];
    [coder encodeObject:browsedserver forKey:@"kbrowsedserver"];
    [coder encodeObject:browsedserverip forKey:@"kbrowsedserverip"];
    [coder encodeInt:trailerimagetime forKey:@"ktrailerimagetime"];
    [coder encodeObject:displayname forKey:@"kdisplayname"];
    [coder encodeObject:remotecontrolpwd forKey:@"keyremotecontrolpwd"];
    [coder encodeInt:hosting forKey:@"keyhosting"];
    [coder encodeInt:origserverid forKey:@"keyorigserverid"];
    [coder encodeObject:rcdeviceid forKey:@"keyrcdeviceid"];
    [coder encodeObject:fbweekday forKey:@"keyfbweekday2"];
    [coder encodeInt:adverttexttime forKey:@"keyadverttexttime"];
    [coder encodeObject:printerip forKey:@"keyprinterip"];
    [coder encodeObject:printfootertext forKey:@"keypftext"];
    [coder encodeObject:printheadertext forKey:@"keyphtext"];
    [coder encodeObject:printheaderimage forKey:@"keyphimage"];
    [coder encodeObject:printfooterimage forKey:@"keypfimage"];
    [coder encodeObject:spotifyuser forKey:@"keyspotifyuser"];
    [coder encodeObject:spotifypassword forKey:@"keyspotifypassword"];
    [coder encodeInt:m_useAmbience forKey:@"keyuseambience"];
    [coder encodeInt:m_ambienceCollectionID forKey:@"keyambiencecollectionid"];
}

@end
