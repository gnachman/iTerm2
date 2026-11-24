//
//  iTermUserDefaultsObserver.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/11/18.
//

#import "iTermUserDefaultsObserver.h"

#import "DebugLogging.h"
#import "NSObject+iTerm.h"
#import "iTermUserDefaults.h"

static char iTermAdvancedSettingsModelKVOKey;

@implementation iTermUserDefaultsObserver {
    NSMutableDictionary<NSString *, void (^)(void)> *_blocks;
    NSMutableArray<void (^)(void)> *_allKeysBlocks;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _blocks = [NSMutableDictionary dictionary];
    }
    return self;
}

// _blocks and _allKeysBlocks are accessed from any thread because KVO and
// NSUserDefaultsDidChangeNotification can fire on whatever thread read the
// default. Mutations and reads must be synchronized; we use the dictionary
// itself as the lock object since it is allocated in -init and never replaced.

- (void)dealloc {
    NSArray<NSString *> *keys;
    @synchronized (ITNonnilLock(_blocks)) {
        keys = [[_blocks allKeys] copy];
    }
    for (NSString *key in keys) {
        [[iTermUserDefaults userDefaults] removeObserver:self
                                                   forKeyPath:key
                                                      context:(void *)&iTermAdvancedSettingsModelKVOKey];
    }
}

- (void)observeKey:(NSString *)key block:(void (^)(void))block {
    BOOL needToRegister;
    @synchronized (ITNonnilLock(_blocks)) {
        // -dealloc removes one KVO registration per key, so observing the same
        // key again replaces the block without adding a second registration.
        needToRegister = (_blocks[key] == nil);
        _blocks[key] = [block copy];
    }
    if (needToRegister) {
        [[iTermUserDefaults userDefaults] addObserver:self
                                           forKeyPath:key
                                              options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                                              context:(void *)&iTermAdvancedSettingsModelKVOKey];
    }
}

// This is called when user defaults are changed anywhere.
//
// We dispatch the block async to the main queue rather than running it
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
    if (context == &iTermAdvancedSettingsModelKVOKey) {
        // CFPreferences fires KVO on every write to the defaults domain even
        // when the value is unchanged (e.g., a process rewrites the same
        // value, or another process touches the domain). Drop no-op changes
        // so observers don't pay for the side effects.
        if ([NSObject object:change[NSKeyValueChangeOldKey] isEqualToObject:change[NSKeyValueChangeNewKey]]) {
            return;
        }
        void (^block)(void);
        @synchronized (ITNonnilLock(_blocks)) {
            block = _blocks[keyPath];
        }
        if (block) {
            dispatch_async(dispatch_get_main_queue(), ^{
                block();
            });
        }
    }
}

- (void)observeAllKeysWithBlock:(void (^)(void))block {
    BOOL needToRegister = NO;
    @synchronized (ITNonnilLock(_blocks)) {
        if (!_allKeysBlocks) {
            _allKeysBlocks = [NSMutableArray array];
            needToRegister = YES;
        }
        [_allKeysBlocks addObject:[block copy]];
    }
    if (needToRegister) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(userDefaultsDidChange:)
                                                     name:NSUserDefaultsDidChangeNotification
                                                   object:nil];
    }
}

- (void)userDefaultsDidChange:(NSNotification *)notification {
    NSArray<void (^)(void)> *snapshot;
    @synchronized (ITNonnilLock(_blocks)) {
        snapshot = [_allKeysBlocks copy];
    }
    void (^run)(void) = ^{
        for (void (^block)(void) in snapshot) {
            block();
        }
    };
    if ([NSThread isMainThread]) {
        run();
    } else {
        dispatch_async(dispatch_get_main_queue(), run);
    }
}

@end

