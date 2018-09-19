//
//  NSUserDefaults+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/19/18.
//

#import "NSUserDefaults+iTerm.h"
#import "NSDictionary+iTerm.h"

static char iTermUserDefaultsKVOKey;
typedef void (^iTermUserDefaultsBlock)(id);

@implementation NSUserDefaults (iTerm)

static NSMutableDictionary<NSString *, NSMutableArray<iTermUserDefaultsBlock> *> *iTermUserDefaultsObserverBlocks(void) {
    static NSMutableDictionary<NSString *, NSMutableArray<iTermUserDefaultsBlock> *> *blocks;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blocks = [NSMutableDictionary dictionary];
    });
    return blocks;
}

- (void)it_addObserverForKey:(NSString *)key
                       block:(void (^)(id newValue))block {
    [iTermUserDefaultsObserverBlocks() it_addObject:block toMutableArrayForKey:key];
    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:key
                                               options:NSKeyValueObservingOptionNew
                                               context:(void *)&iTermUserDefaultsKVOKey];
}

// This is called when user defaults are changed anywhere.
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == &iTermUserDefaultsKVOKey) {
        NSMutableDictionary<NSString *, NSMutableArray<iTermUserDefaultsBlock> *> *blocks =
            iTermUserDefaultsObserverBlocks();
        NSMutableArray<iTermUserDefaultsBlock> *array = blocks[keyPath];
        id newValue = change[NSKeyValueChangeNewKey];
        for (iTermUserDefaultsBlock block in array) {
            block(newValue);
        }
    } else {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
    }
}

@end
