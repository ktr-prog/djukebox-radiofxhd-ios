// GLView_Search.m -- category GLView (Search), recovered from the GLView search group.
// Search is applied to the flow ("tilearray") in a background thread (BeginSearchinBG:),
// and to the overview grid (MTScroller) by MTSearchBackGround:.
#import "GLView.h"
#import "KioskView.h"
#import "KeyboardView.h"
#import "MTScroller.h"
#import "MTObject.h"
#import "DBOperations.h"
#import "ClipObject.h"
#import "FolderObject.h"
#import "CGPointObject.h"
#import "NSString+RfxMatch.h"
#import "RadioAppDelegate.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@implementation GLView (Search)

// Applies `text` to the covers of the selected folder (empty text: show everything again).
- (void)BeginSearchinBG:(NSString *)text {
    NSAutoreleasePool *pool = nil;
    if (![NSThread isMainThread]) pool = [[NSAutoreleasePool alloc] init];

    [self GetArrayLock:NO];
    int oldcount = (int)[[self m_tilearray] count];
    m_flipping = NO;
    if (text == nil || [text length] == 0) {
        [[self m_tilearray] removeAllObjects];
        [[self m_tilearray] addObjectsFromArray:[self m_origarray]];
    } else {
        DBOperations *dbo = [[DBOperations alloc] init];
        NSMutableArray *folders = [[NSMutableArray alloc] init];
        [DEL LockDB:0];
        FolderObject *f = [dbo GetFolderForID:[self m_selectedfolderid] withserverid:[self m_selectedserverid]
                                   withipodid:[self m_selectedipodid] withspotifyid:[self m_selectedspotifyfolderid]];
        [DEL UnlockDB];
        if (f != nil) { [folders addObject:f]; [f release]; }
        NSMutableArray *found = [m_searchview SubBGSearch:text withdbop:dbo withfolders:folders];
        [folders release];
        [[self m_tilearray] removeAllObjects];
        [[self m_tilearray] addObjectsFromArray:found];
        [found release];
        if (dbo != nil) [dbo release];
    }
    int newcount = (int)[[self m_tilearray] count];
    if (newcount == oldcount) {
        // same number of covers: keep the position, just make sure it is in range
        if (offset < 0) offset = 0;
        if (offset >= (double)oldcount) offset = (double)(oldcount - 1);
    } else {
        offset = (double)((unsigned)newcount >> 1);
        if (m_tryrestoreoffset != -1 || [self m_trytorestorespotifyid] != nil) {
            // try to find the song that was playing before the search and centre on it
            for (int i = 0; i < (int)[[self m_tilearray] count]; i++) {
                ClipObject *c = [[self m_tilearray] objectAtIndex:i];
                if ([c ID] == m_tryrestoreoffset &&
                    [m_parent spotifyIDsMatch:[self m_trytorestorespotifyid] withsecondid:[c m_spotifyid]]) {
                    offset = (double)i;
                    break;
                }
            }
            m_tryrestoreoffset = -1;
            [self setM_trytorestorespotifyid:nil];
        }
    }
    [m_arraylock unlock];

    if ([NSThread isMainThread]) [self drawView];
    else [self performSelectorOnMainThread:@selector(drawView) withObject:nil waitUntilDone:YES];
    [self ReInitThread];
    if ([NSThread isMainThread])
        [m_searchview SetUpSearchList:[self m_tilearray]];
    else
        [m_searchview performSelectorOnMainThread:@selector(SetUpSearchList:) withObject:[self m_tilearray] waitUntilDone:YES];
    if (pool != nil) [pool release];
}

- (void)BeginSearch:(NSString *)text {
    [self performSelectorInBackground:@selector(BeginSearchinBG:) withObject:text];
}

- (void)BeginSearchInMTScroller:(NSString *)text {
    [self performSelectorInBackground:@selector(MTSearchBackGround:) withObject:text];
}

- (void)ForwardBeginSearchinMTScroller {
    [self performSelector:@selector(BeginSearchInMTScroller:) withObject:[[m_searchview m_searchlabel] text] afterDelay:0.01];
}

- (void)ForwardRestartOverviewTimer {
    if (m_mtscroller != nil) [m_mtscroller RestartOverviewTimer];
}

// Counts the entries of every overview tile and hands the numbers to the scroller (red badges).
// The text parameter is not used by the original (the count is requested with an empty string).
- (void)MTSearchBackGround:(NSString *)text {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [self setM_lastmtovsearchtime:CACurrentMediaTime()];
    double mytime = [self m_lastmtovsearchtime];
    NSMutableArray *counts = [[NSMutableArray alloc] init];
    DBOperations *dbo = [[DBOperations alloc] init];
    NSMutableArray *objs = [[NSMutableArray alloc] init];
    [DEL LockDB:0];

    BOOL completed = NO;
    MTObject *selected = nil;
    if (!(([self m_lastmtovsearchtime] - mytime) > 0.001)) {
        [objs addObjectsFromArray:[m_mtscroller GetMTObjects]];
        NSUInteger i;
        for (i = 0; i < [objs count]; i++) {
            if (([self m_lastmtovsearchtime] - mytime) > 0.001) break;     // a newer search started
            MTObject *o = [objs objectAtIndex:i];
            [counts addObject:[NSNumber numberWithInt:
                [dbo GetNumMatchingEntries:[o m_id] withServerid:[o m_sid] withsearchstring:@""
                                withipodid:[o m_ipodid] withspotifyfolderid:[o m_spotifyfolderid]]]];
            if ([o m_id] == m_selectedfolderid && [o m_sid] == m_selectedserverid &&
                [o m_ipodid] == m_selectedipodid &&
                [m_parent selectedSpotifyIDMatches:[o m_spotifyfolderid]]) {
                selected = [[objs objectAtIndex:i] retain];
            }
        }
        completed = (i >= [objs count]);
    }
    [objs release];
    [dbo release];
    [DEL UnlockDB];

    if (m_mtscroller != nil && completed)
        [m_mtscroller performSelectorOnMainThread:@selector(SetRedDots:) withObject:counts waitUntilDone:YES];
    [counts release];

    if ([self m_selectedfolderid] != -33 && completed) {
        if (selected != nil) {
            m_tryrestoreoffset = [selected m_lastsongid];
            NSString *sp = nil;
            if ([selected m_lastspotifyid] != nil) sp = [NSString stringWithFormat:@"%@", [selected m_lastspotifyid]];
            [self setM_trytorestorespotifyid:sp];
            [selected release];
        }
    } else if (selected != nil) {
        [selected release];
    }
    [pool release];
}

// YES if the clip (or one of its tracks) matches the search text.
- (BOOL)IsClipInSearchrange:(ClipObject *)clip withsearchtext:(NSString *)searchtext {
    if ([clip m_tracks] == nil)
        return [self SubSearch:clip withsearchtext:searchtext];
    for (NSUInteger i = 0; i < [[clip m_tracks] count]; i++) {
        if ([self SubSearch:[[clip m_tracks] objectAtIndex:i] withsearchtext:searchtext]) return YES;
    }
    return NO;
}

- (BOOL)SubSearch:(ClipObject *)clip withsearchtext:(NSString *)searchtext {
    if ([[clip m_title] RfxMatchString:searchtext]) return YES;
    if ([clip m_folderid] == 3 && [[clip m_albumname] RfxMatchString:searchtext]) return YES;
    if ([clip m_folderid] == -33) return YES;
    return [[clip m_interpret] RfxMatchString:searchtext];
}

- (void)RemoveKeyBoardDelayed {
    if ([m_searchview m_keyboardshown])
        [self ToggleKBAndRegister:[NSNumber numberWithInt:[m_searchview m_showwhat]]];
}

#pragma mark - pay-per-song flow (stationary installations with a card reader; unavailable)

// Only reached from the search list when `m_isstattalm` is set.
- (void)AddFromSearchList:(ClipObject *)fromSearchList {
    if (m_sapointobject != nil) return;
    if ([m_parent ShowingLoadingscreen]) return;
    if (fromSearchList == nil) return;
    if (m_saDoubleTapCo != nil) return;
    m_saDoubleTapCo = [fromSearchList retain];
    m_sapointobject = [[CGPointObject alloc] init];
    [m_sapointobject setX:[self frame].size.width * 0.5f];
    [m_sapointobject setY:[self frame].size.height * 0.5f];
    m_sarstatus = 1;
    [self performSelector:@selector(AskForCard) withObject:nil afterDelay:0.1];
}

// The original shows a "hold your card to the reader" dialog (0.10 EUR per song) and talks to the
// payment web service. Neither exists any more, so the request is simply cancelled: this is what
// the original does when the dialog times out (state is reset, nothing is played).
- (void)AskForCard {
    if (![DEL m_isstattalm]) return;
    m_sarstatus = 0;
    if (m_draggingobject != nil) [self RemoveDraggingObject];
    if (m_sapointobject != nil) { [m_sapointobject release]; m_sapointobject = nil; }
    if (m_saDoubleTapCo != nil) { [m_saDoubleTapCo release]; m_saDoubleTapCo = nil; }
    [m_parent CheckQueueHintLabel];
}

- (void)SARequestThread { /* payment web service is gone */ }
@end
