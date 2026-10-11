// RegisterImage : UIView -- one of the ten round "register" buttons above the coverflow
// (volume, speech bubble, search, on/off, collections, help, settings, video, euro, wall).
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class GLView;

@interface RegisterImage : UIView {
    int m_index;
    GLView *m_pglv;
    BOOL m_enabled;
    UIView *m_additionalimage;
    UIImageView *m_mainimage;
    UIImageView *m_darkimage;
}
@property (assign) BOOL m_enabled;
@property (assign) int m_index;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEndedFunc;
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)SetGLVPointer:(id)gLVPointer;
- (void)SetImage:(id)image withisadditionalimage:(BOOL)isadditionalimage withcreate:(BOOL)create;
- (void)SetAdditionalWhiteImage;
- (void)ShowDarkImage:(float)darkImage;
- (void)SetSyncImage:(id)syncImage;
- (void)SetAdditionalAlpha:(float)additionalAlpha;
- (void)InitView;
@end
