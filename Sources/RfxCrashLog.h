// Port addition: writes a crash report to Documents/RFX_crash.txt (visible in the Files app) and shows it on the next launch.
#import <Foundation/Foundation.h>
void RfxCrashLog_Install(void);
void RfxCrashLog_ShowPrevious(void);

// last step marker, written into the crash report (async-signal-safe: plain char buffer)
void RfxCrumb(const char *step);
