//
//  iTermGitCache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitCache.h"

@implementation iTermGitCache {
    NSMutableDictionary *_cache;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setState:(iTermGitState *)state forPath:(NSString *)path ttl:(NSTimeInterval)ttl {
    _cache[path] = state;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ttl * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_cache[path] == state) {
            [self->_cache removeObjectForKey:path];
        }
    });
}

- (iTermGitState *)stateForPath:(NSString *)path maximumAge:(NSTimeInterval)maximumAge {
    iTermGitState *state = _cache[path];
    if (!state) {
        return nil;
    }
    if (state.age > maximumAge) {
        return nil;
    }
    return state;
}

- (void)removeStateForPath:(NSString *)path {
    [_cache removeObjectForKey:path];
}

@end
