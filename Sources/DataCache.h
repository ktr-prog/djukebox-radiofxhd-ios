// DataCache : NSObject  (recovered; LRU cache of GL textures keyed by string)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class GLView;

@interface DataCache : NSObject {
    int fCapacity;
    NSMutableDictionary *fDictionary;
    NSMutableArray *fAge;
    GLView *m_pglv;
}
- (int)GetMaxTiles;
- (void)Empty;
- (void)RemoveObjectsExept:(id)objectsExept;
- (void)removeObjectwithkey:(id)objectwithkey;
- (void)DeleteServerTextures:(int)serverTextures;
- (void)DeclineCapacity;
- (void)setObject:(id)object forKey:(id)key;
- (id)objectForKey:(id)objectForKey;
- (BOOL)ExistsObjectForKey:(id)existsObjectForKey;
- (int)GetfAgeIndexForKey:(id)getfAgeIndexForKey;
- (void)dealloc;
- (void)SetGLPointer:(id)gLPointer;
- (id)initWithCapacity:(int)capacity;
@end
