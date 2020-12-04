//
//  iTermUserDefaultsObserver.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/11/18.
//

#import "iTermUserDefaultsObserver.h"

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

- (void)dealloc {
    for (NSString *key in _blocks) {
        [[NSUserDefaults standardUserDefaults] removeObserver:self
                                                   forKeyPath:key
                                                      context:(void *)&iTermAdvancedSettingsModelKVOKey];
    }
}

- (void)observeKey:(NSString *)key block:(void (^)(void))block {
    _blocks[key] = [block copy];
    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:key
                                               options:NSKeyValueObservingOptionNew
                                               context:(void *)&iTermAdvancedSettingsModelKVOKey];
}

// This is called when user defaults are changed anywhere.
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == &iTermAdvancedSettingsModelKVOKey) {
        void (^block)(void) = _blocks[keyPath];
        if (block) {
            block();
        }
    }
}

- (void)observeAllKeysWithBlock:(void (^)(void))block {
    if (!_allKeysBlocks) {
        _allKeysBlocks = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(userDefaultsDidChange:)
                                                     name:NSUserDefaultsDidChangeNotification
                                                   object:nil];
    }
    [_allKeysBlocks addObject:[block copy]];
}

- (void)userDefaultsDidChange:(NSNotification *)notification {
    for (void (^block)(void) in _allKeysBlocks) {
        block();
    }
}

@end

