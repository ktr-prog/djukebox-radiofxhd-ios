// Globals shared between the recovered classes.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern BOOL g_bShutdown;           // set in applicationWillTerminate
extern int  gv_kioskflag;          // original global at 0x39883c (kiosk/remote "busy" flag)
extern int  gv_texsize;            // original gv_34e760 (texture edge of the normal tiles)
extern int  gv_texsizeradio;       // original gv_34e764

#define kThumbSize   196
#define kCoverSize   512
