// DataCache.m -- recovered from Radiofx_iPad (armv7)
#import "DataCache.h"

@implementation DataCache

- (int)GetMaxTiles { return fCapacity; }

- (void)Empty {
    [fDictionary removeAllObjects];
    [fAge removeAllObjects];
}

- (void)RemoveObjectsExept:(id)objectsExept {
    int n = (int)[fAge count];
    for (int i = n - 1; i >= 0; i--) {
        NSString *key = [fAge objectAtIndex:i];
        BOOL keep = NO;
        for (NSUInteger j = 0; j < [objectsExept count]; j++) {
            if ([key isEqualToString:[objectsExept objectAtIndex:j]]) { keep = YES; break; }
        }
        if (!keep) {
            [fDictionary removeObjectForKey:key];
            [fAge removeObjectAtIndex:i];
        }
    }
}

- (void)removeObjectwithkey:(id)objectwithkey {
    [fDictionary removeObjectForKey:objectwithkey];
    for (int i = (int)[fAge count] - 1; i >= 0; i--) {
        if ([objectwithkey isEqualToString:[fAge objectAtIndex:i]])
            [fAge removeObjectAtIndex:i];
    }
}

- (void)DeleteServerTextures:(int)serverTextures {
    NSMutableArray *keys = [[NSMutableArray alloc] init];
    NSEnumerator *en = [fDictionary keyEnumerator];
    id k;
    while ((k = [en nextObject])) [keys addObject:k];
    for (NSUInteger i = 0; i < [keys count]; i++) {
        NSString *key = [keys objectAtIndex:i];
        NSArray *parts = [key componentsSeparatedByString:@"-"];
        if ([parts count] >= 3 && [[parts objectAtIndex:2] intValue] == serverTextures) {
            [fDictionary removeObjectForKey:key];
            int idx = [self GetfAgeIndexForKey:key];
            if (idx != 0x7fffffff) [fAge removeObjectAtIndex:idx];
        }
    }
    [keys release];
}

- (void)DeclineCapacity {
    fCapacity = (fCapacity - 10) <= 20 ? 20 : (fCapacity - 10);
}

- (void)setObject:(id)object forKey:(id)key {
    int idx = [self GetfAgeIndexForKey:key];
    if (idx != 0) {
        if (idx != 0x7fffffff) [fAge removeObjectAtIndex:idx];
        [fAge insertObject:key atIndex:0];
        if ((int)[fAge count] > fCapacity) {
            [fDictionary removeObjectForKey:[fAge lastObject]];
            [fAge removeLastObject];
        }
    }
    [fDictionary setObject:object forKey:key];
}

- (id)objectForKey:(id)key {
    int idx = [self GetfAgeIndexForKey:key];
    if (idx == 0x7fffffff) return nil;
    if (idx != 0) {
        [fAge removeObjectAtIndex:idx];
        [fAge insertObject:key atIndex:0];
    }
    return [fDictionary objectForKey:key];
}

- (BOOL)ExistsObjectForKey:(id)key { return [self GetfAgeIndexForKey:key] != 0x7fffffff; }

- (int)GetfAgeIndexForKey:(id)key {
    for (NSUInteger i = 0; i < [fAge count]; i++)
        if ([key isEqualToString:[fAge objectAtIndex:i]]) return (int)i;
    return 0x7fffffff;
}

- (void)dealloc {
    [fDictionary release];
    [fAge release];
    [super dealloc];
}

- (void)SetGLPointer:(id)gLPointer { m_pglv = gLPointer; }

- (id)initWithCapacity:(int)capacity {
    self = [super init];
    if (self) {
        fCapacity = capacity;
        fDictionary = [[NSMutableDictionary alloc] initWithCapacity:capacity];
        fAge = [[NSMutableArray alloc] initWithCapacity:capacity];
    }
    return self;
}
@end
