// CGPointObject : NSObject  (recovered, instance size 12 on armv7)
// Boxes a touch location so it can be handed to performSelector:.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CGPointObject : NSObject {
    float x;  // +4
    float y;  // +8
}
@property (assign) float x;
@property (assign) float y;
- (id)init;
@end
