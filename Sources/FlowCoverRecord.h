// FlowCoverRecord : NSObject  (recovered, instance size 12 on armv7)
#import <Foundation/Foundation.h>
#import <OpenGLES/ES1/gl.h>

@interface FlowCoverRecord : NSObject {
    GLuint texture;     // +4
    int    percent;     // +8
}
@property (nonatomic, assign) GLuint texture;
@property (nonatomic, assign) int percent;
- (id)initWithTexture:(GLuint)tex;
@end
