// main.m -- recovered from _main @ 0x3d6c
#import <UIKit/UIKit.h>
#import "RfxCrashLog.h"

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    RfxCrashLog_Install();
    int retVal = UIApplicationMain(argc, argv, nil, nil);
    [pool release];
    return retVal;
}
