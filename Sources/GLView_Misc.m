// GLView_Misc.m -- category GLView (Misc): dimm view, register helpers, prescroller dictionary
// accessors and the OpenGL screenshot.
#import "GLView.h"
#import "RegisterImage.h"
#import "ClipObject.h"
#import <OpenGLES/ES1/gl.h>

@implementation GLView (Misc)

- (void)FadeDimmViewForBox:(BOOL)on {
    [UIView beginAnimations:@"dimmviewani" context:nil];
    [UIView setAnimationDuration:0.5];
    if (!on) {
        [UIView setAnimationDidStopSelector:@selector(FadeDimmViewForBoxDidStop)];
        [UIView setAnimationDelegate:self];
    }
    if (m_dimmview) m_dimmview.alpha = on ? 0.7f : 0.0f;
    [UIView commitAnimations];
}

- (void)FadeDimmViewForBoxDidStop {
    if (m_dimmview) {
        [m_dimmview removeFromSuperview];
        m_dimmview = nil;
    }
}

- (void)RemoveGlass {
    [m_registers[2] setM_enabled:NO];
    [self ExecuteServerFlagsRest:1];
}

- (BOOL)GetRegisterFBWALLenabled {
    return [m_registers[9] m_enabled];
}

- (NSString *)GetActSpotifyID {
    NSString *result = nil;
    [self GetArrayLock:NO];
    int idx = (int)offset;
    if (idx >= 0 && idx < (int)[m_tilearray count]) {
        ClipObject *clip = [m_tilearray objectAtIndex:idx];
        result = [NSString stringWithFormat:@"%@", [clip m_spotifyid]];
    }
    [self releaseArraylock];
    return result;
}

- (void)DoRegisterTouch:(NSNumber *)index {
    int i = [index intValue];
    if (i >= 0 && i < 10 && m_registers[i] && [m_registers[i] m_enabled])
        [m_registers[i] touchesEndedFunc];
}

- (id)GetSDC:(id)key { return [m_prescrollerdict objectForKey:key]; }
- (void)DeleteSDC:(id)key { [m_prescrollerdict removeObjectForKey:key]; }
- (NSMutableDictionary *)GetPreScrollerDict { return m_prescrollerdict; }
- (BOOL)Getprescrollerthreaddone { return m_prescrollerthreaddone; }
- (void)StartPreScrollerThread {
    [NSThread detachNewThreadSelector:@selector(PrescrollerThread) toTarget:self withObject:nil];
}

- (BOOL)IsInAlbumArray:(NSNumber *)albumid witharray:(NSArray *)array {
    long long want = [albumid longLongValue];
    for (id o in array)
        if ([o longLongValue] == want) return YES;
    return NO;
}

- (UIImage *)GetOGLScreenshot {
    CGRect b = self.frame;
    int w = (int)(b.size.width * m_oglscale);
    int h = (int)(b.size.height * m_oglscale);
    size_t len = (size_t)w * h * 4;
    GLubyte *buf = (GLubyte *)malloc(len);
    GLubyte *flip = (GLubyte *)malloc(len);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, buf);
    for (int y = 0; y < h; y++)
        memcpy(flip + (size_t)(h - 1 - y) * w * 4, buf + (size_t)y * w * 4, (size_t)w * 4);
    free(buf);
    CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, flip, len, NULL);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGImageRef img = CGImageCreate(w, h, 8, 32, (size_t)w * 4, cs,
                                   kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast,
                                   prov, NULL, NO, kCGRenderingIntentDefault);
    UIImage *ui = [[UIImage alloc] initWithCGImage:img];
    CGImageRelease(img);
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(prov);
    // note: `flip` leaks with the provider in the original (no release callback)
    return ui;
}

@end
