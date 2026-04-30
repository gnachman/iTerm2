//
//  NSUserDefaults+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/19/18.
//

#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSUserDefaults+iTerm.h"
#import "iTermUserDefaults.h"

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
    NSMutableDictionary *blocks = iTermUserDefaultsObserverBlocks();
    // KVO can fire on any thread (CFPreferences delivers buffered notifications
    // on whatever thread reads a default), so dict mutation must be
    // synchronized against the read in -observeValueForKeyPath:.
    @synchronized (blocks) {
        [blocks it_addObject:block toMutableArrayForKey:key];
    }
    [[iTermUserDefaults userDefaults] addObserver:self
                                            forKeyPath:key
                                               options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                                               context:(void *)&iTermUserDefaultsKVOKey];
}

// This is called when user defaults are changed anywhere.
//
// We dispatch blocks async to the main queue rather than running them
// synchronously. CFPreferences delivers buffered KVO notifications inline on
// whatever thread reads a default, so a synchronous block here would (a) run
// on whatever thread happened to read a pref, and (b) re-enter arbitrary code
// during a pref read — which previously crashed when a side effect read a
// pref, the KVO chain reached -[NSApp setAppearance:], and the appearance
// change tried to join screen threads while a side effect was still running.
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == &iTermUserDefaultsKVOKey) {
        // CFPreferences fires KVO on every write to the defaults domain even
        // when the value is unchanged (e.g., a process rewrites the same
        // value, or another process touches the domain). Drop no-op changes
        // so observers don't pay for the side effects.
        id oldValue = change[NSKeyValueChangeOldKey];
        id newValue = change[NSKeyValueChangeNewKey];
        if ([NSObject object:oldValue isEqualToObject:newValue]) {
            return;
        }
        NSMutableDictionary<NSString *, NSMutableArray<iTermUserDefaultsBlock> *> *blocks =
            iTermUserDefaultsObserverBlocks();
        NSArray<iTermUserDefaultsBlock> *array;
        @synchronized (blocks) {
            // -copy snapshots while the lock is held so the async block iterates
            // an immutable copy even if the inner array is mutated later.
            array = [blocks[keyPath] copy];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            for (iTermUserDefaultsBlock block in array) {
                block(newValue);
            }
        });
    } else {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
    }
}

@end
