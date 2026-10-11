// GLView_Flip.m -- category GLView (Flip): turning a cover around to show its track list
// (only for covers whose ClipObject carries m_tracks), plus the table that lists the tracks
// and the scroll delegate of the overview.
#import "GLView.h"
#import "KioskView.h"
#import "KeyboardView.h"
#import "MTScroller.h"
#import "ClipObject.h"
#import "FlowCoverRecord.h"
#import "RadioAppDelegate.h"

#define DEL ((RadioAppDelegate *)[[UIApplication sharedApplication] delegate])

@implementation GLView (Flip)

- (void)InitFlipping:(CGPoint)pt {
    if (!m_flipping) {
        if (CGRectContainsPoint(m_reddotrect, pt)) {
            int idx = (int)floor(offset + 0.01);
            if ((unsigned)idx >= [[self m_tilearray] count]) return;
            ClipObject *clip = [[self m_tilearray] objectAtIndex:idx];
            if ([clip m_tracks] == nil) return;
            m_tracksong = [clip retain];
            m_tracknumberpresent = NO;
            for (unsigned i = 0; i < [[clip m_tracks] count]; i++) {
                ClipObject *t = [[clip m_tracks] objectAtIndex:i];
                [t retain];
                if ([t m_tracknumber] != 0) m_tracknumberpresent = YES;
            }
            BOOL ipad = [DEL m_isipad];
            float inset = ipad ? 23.0f : 4.0f;
            m_tracktable = [[UITableView alloc] initWithFrame:
                CGRectMake(m_foregroundrect.origin.x + inset,
                           m_foregroundrect.origin.y + (ipad ? 75.0f : 39.0f),
                           m_foregroundrect.size.width - inset * 2,
                           m_foregroundrect.size.height - (ipad ? 100.0f : 39.0f))
                                                        style:UITableViewStylePlain];
            [m_tracktable setAlpha:0.0f];
            [m_tracktable setSeparatorStyle:UITableViewCellSeparatorStyleNone];
            [m_tracktable setDelegate:self];
            [m_tracktable setDataSource:self];
            [self addSubview:m_tracktable];
            [m_tracktable release];
            [self performSelector:@selector(FlipAni) withObject:nil afterDelay:0.01];
            return;
        }
    }
    // already flipped: a tap outside of the list turns the cover back
    if (!m_flipping) return;
    if (m_flippingangle < 180.0) return;
    if (!CGRectContainsPoint(m_foregroundrect, pt)) return;
    [self performSelector:@selector(FlipBackAni:) withObject:[NSNumber numberWithInt:1] afterDelay:0.01];
}

- (void)FlipAni {
    if (m_flipping) return;
    m_flipping = YES;
    for (int a = 0; a <= 180; a += 12) {
        m_flippingangle = a;
        [self drawView];
    }
    [self TrackTableAni:1.0f];
}

- (void)FlipBackAni:(NSNumber *)animated {
    if (!m_flipping) return;
    int fade = [animated intValue];
    if (m_tracktable != nil) [m_tracktable setUserInteractionEnabled:NO];
    if (fade == 1) {
        [self TrackTableAni:0.0f];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, 0);
    }
    for (int i = 0, a = 180; i < 16; i++, a -= 12) {
        m_flippingangle = a;
        [self drawView];
    }
    [self flipCleanup];
}

- (void)FlipBack2 {
    for (int i = 0, a = 180; i < 16; i++, a -= 12) {
        m_flippingangle = a;
        [self drawView];
    }
    [self flipCleanup];
}

// shared tail of FlipBackAni: / FlipBack2 (duplicated inline in the original)
- (void)flipCleanup {
    m_flipping = NO;
    if (m_specialtexture != nil) {
        [m_specialtexture release];
        m_specialtexture = nil;
    }
    if (m_tracktable != nil) {
        [m_tracktable removeFromSuperview];
        m_tracktable = nil;
    }
    if (m_tracksong != nil) {
        if ([m_tracksong m_tracks] != nil)
            for (unsigned i = 0; i < [[m_tracksong m_tracks] count]; i++)
                [[[m_tracksong m_tracks] objectAtIndex:i] release];
        [m_tracksong release];
        m_tracksong = nil;
    }
}

- (void)TrackTableAni:(float)alpha {
    if (m_tracktable == nil) return;
    [UIView beginAnimations:@"tracktableani" context:nil];
    [UIView setAnimationRepeatCount:1.0f];
    [UIView setAnimationDuration:0.2];
    [m_tracktable setAlpha:alpha];
    [UIView commitAnimations];
}

#pragma mark - UITableView (track list)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (m_tracksong == nil || [m_tracksong m_tracks] == nil) return 0;
    return [[m_tracksong m_tracks] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [DEL m_isipad] ? 45.0f : 30.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL ipad = [DEL m_isipad];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cellid_w"];
    int firstCol = m_tracknumberpresent ? 0 : 1;
    int lastCol = MAX(m_tracknumberpresent ? 1 : 2, ipad ? 3 : 2);   // exclusive
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:@"cellid_w"] autorelease];
        [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
        int cellH = ipad ? (int)[cell frame].size.height : 0;
        UIView *back = [[UIView alloc] initWithFrame:
            CGRectMake(0.0f, 3.0f, [tableView frame].size.width, (float)(cellH - (ipad ? 8 : 7)))];
        [back setBackgroundColor:[UIColor colorWithWhite:0.831f alpha:1.0f]];
        [cell addSubview:back];
        [back release];

        float numW = m_tracknumberpresent ? (ipad ? 29.0f : 25.0f) : 0.0f;
        float durW = ipad ? 56.0f : -10.0f;
        float labH = (float)(cellH - 5);
        for (int col = firstCol; col < lastCol; col++) {
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
            [l setTag:10 + col];
            [l setFont:[UIFont boldSystemFontOfSize:ipad ? 21.0f : 15.0f]];
            [l setTextColor:[UIColor blackColor]];
            [l setBackgroundColor:[UIColor clearColor]];
            [cell addSubview:l];
            [l release];
            float tw = [tableView frame].size.width;
            if (col == 2) {
                [l setFrame:CGRectMake((tw - durW) + -5.0f, 3.0f, durW, labH)];
                [l setTextAlignment:NSTextAlignmentRight];
            } else if (col == 1) {
                [l setFrame:CGRectMake(numW + 5, 3.0f,
                                       (float)(int)((((tw - numW) + -5.0f) - durW) + -10.0f), labH)];
                [l setTextAlignment:NSTextAlignmentLeft];
            } else {
                [l setFrame:CGRectMake(0.0f, 3.0f, numW, labH)];
                [l setTextAlignment:NSTextAlignmentCenter];
            }
        }
    }
    if (m_tracksong != nil && [m_tracksong m_tracks] != nil &&
        [[m_tracksong m_tracks] count] > (unsigned)[indexPath row]) {
        ClipObject *track = [[m_tracksong m_tracks] objectAtIndex:[indexPath row]];
        if (track != nil) {
            for (int col = firstCol; col < lastCol; col++) {
                UILabel *l = (UILabel *)[cell viewWithTag:10 + col];
                if (l == nil) continue;
                NSString *text;
                if (col == 2) {
                    int d = [track m_duration];
                    text = [NSString stringWithFormat:@"%i:%02i", d / 60, d % 60];
                } else if (col == 1) {
                    text = [track m_title];
                } else {
                    text = ([track m_tracknumber] != 0)
                         ? [NSString stringWithFormat:@"%i", [track m_tracknumber]] : @"";
                }
                [l setText:text];
            }
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (m_tracksong != nil && [m_tracksong m_tracks] != nil &&
        [[m_tracksong m_tracks] count] > (unsigned)[indexPath row]) {
        [m_tracktable setUserInteractionEnabled:NO];
        [m_searchview AddItemFromSearchList:0 withsection:0
                        withdirectClipObject:[[m_tracksong m_tracks] objectAtIndex:[indexPath row]]];
    }
    [self performSelector:@selector(FlipBackAni:) withObject:[NSNumber numberWithInt:1] afterDelay:0.01];
}

#pragma mark - UIScrollView (overview)

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [m_mtscroller setM_isscrolling:YES];
    if (m_mtscroller == (MTScroller *)scrollView) [m_mtscroller StopOverviewTimer];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    [m_mtscroller setM_isscrolling:decelerate];
    if (m_mtscroller == (MTScroller *)scrollView) [m_mtscroller RestartOverviewTimer];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [m_mtscroller setM_isscrolling:NO];
}

@end
