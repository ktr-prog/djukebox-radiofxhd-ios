#import "RfxCrashLog.h"
#import <UIKit/UIKit.h>
#include <execinfo.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <mach-o/dyld.h>

static char gCrashPath[1024];
static char gCrumb[96];

void RfxCrumb(const char *step) { strlcpy(gCrumb, step, sizeof(gCrumb)); }

static void RfxWrite(int fd, const char *s) { if (fd >= 0) write(fd, s, strlen(s)); }

static void RfxSignal(int sig) {
    int fd = open(gCrashPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    char buf[160];
    snprintf(buf, sizeof(buf), "SIGNAL %d\nimage0 slide: 0x%lx\n", sig, (unsigned long)_dyld_get_image_vmaddr_slide(0));
    RfxWrite(fd, buf);
    RfxWrite(fd, "step: "); RfxWrite(fd, gCrumb); RfxWrite(fd, "\n");
    void *frames[48];
    int n = backtrace(frames, 48);
    for (int i = 0; i < n; i++) {
        snprintf(buf, sizeof(buf), "%d 0x%lx\n", i, (unsigned long)frames[i]);
        RfxWrite(fd, buf);
    }
    if (fd >= 0) { backtrace_symbols_fd(frames, n, fd); close(fd); }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void RfxException(NSException *e) {
    NSString *t = [NSString stringWithFormat:@"EXCEPTION %@\n%@\nslide: 0x%lx\n%@\n", [e name], [e reason],
                   (unsigned long)_dyld_get_image_vmaddr_slide(0), [[e callStackSymbols] componentsJoinedByString:@"\n"]];
    [t writeToFile:[NSString stringWithUTF8String:gCrashPath] atomically:NO encoding:NSUTF8StringEncoding error:nil];
}

void RfxCrashLog_Install(void) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    strlcpy(gCrashPath, [[dir stringByAppendingPathComponent:@"RFX_crash.txt"] fileSystemRepresentation], sizeof(gCrashPath));
    NSSetUncaughtExceptionHandler(&RfxException);
    int sigs[] = { SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGTRAP, SIGFPE };
    for (unsigned i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) signal(sigs[i], RfxSignal);
}

void RfxCrashLog_ShowPrevious(void) {
    NSString *path = [NSString stringWithUTF8String:gCrashPath];
    NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if ([txt length] == 0) return;
    NSString *prev = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"RFX_crash_previous.txt"];
    [[NSFileManager defaultManager] removeItemAtPath:prev error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:path toPath:prev error:nil];
    if ([txt length] > 1800) txt = [txt substringToIndex:1800];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        while ([vc presentedViewController]) vc = [vc presentedViewController];
        if (vc == nil) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Last crash (also saved as RFX_crash_previous.txt)" message:txt preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}
