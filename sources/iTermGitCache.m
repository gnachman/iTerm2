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

- (iTermGitState *)stateForPath:(NSString *)path {
    return _cache[path];
}

@end
