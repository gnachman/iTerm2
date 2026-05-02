//
//  iTermGitPollWorker.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitPollWorker.h"

#import "DebugLogging.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermCommandRunner.h"
#import "iTermCommandRunnerPool.h"
#import "iTermGitState+MainApp.h"
#import "iTermSlowOperationGateway.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^iTermGitPollWorkerCompletionBlock)(iTermGitState * _Nullable, BOOL timedOut);

@implementation iTermGitPollWorker {
    NSMutableDictionary<NSString *, iTermGitState *> *_cache;
    NSMutableDictionary<NSString *, NSMutableArray<iTermGitPollWorkerCompletionBlock> *> *_pending;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
        _pending = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)cachedBranchForPath:(NSString *)path {
    // Branch is the same regardless of gitBase or includeDiffStats
    // — scan every key that could belong to this path. Three key
    // shapes exist: bare `path` (basic, HEAD), `path\x01stats`
    // (rich, HEAD or with `\x02<base>` suffix when non-HEAD), and
    // `path\x02<base>` (basic, non-HEAD). All three prefixes
    // need a hasPrefix check or the function under-reports when
    // only base-keyed entries are cached.
    NSString *statsPrefix = [path stringByAppendingString:@"\x01"];
    NSString *basePrefix = [path stringByAppendingString:@"\x02"];
    for (NSString *key in _cache) {
        if ([key isEqualToString:path] ||
            [key hasPrefix:statsPrefix] ||
            [key hasPrefix:basePrefix]) {
            iTermGitState *state = _cache[key];
            if (state.branch) {
                return state.branch;
            }
        }
    }
    return nil;
}

- (NSString *)debugInfoForDirectory:(NSString *)path {
    iTermGitState *basic = _cache[[self cacheKeyForPath:path
                                                gitBase:nil
                                       includeDiffStats:NO]];
    iTermGitState *rich = _cache[[self cacheKeyForPath:path
                                               gitBase:nil
                                      includeDiffStats:YES]];
    NSUInteger pendingCount =
        _pending[[self cacheKeyForPath:path gitBase:nil includeDiffStats:NO]].count +
        _pending[[self cacheKeyForPath:path gitBase:nil includeDiffStats:YES]].count;
    return [NSString stringWithFormat:@"Basic cache: %@\nRich cache: %@\nPending calls: %@\n",
            basic ? [NSString stringWithFormat:@"age %@", @(basic.age)] : @"none",
            rich ? [NSString stringWithFormat:@"age %@", @(rich.age)] : @"none",
            @(pendingCount)];
}

// Cache key is path + gitBase + stats flag. Empty/nil/"HEAD"
// gitBase all collapse to the same key so the existing HEAD-only
// callers keep hitting the same cache slot they always have.
// \x01 is the legacy separator the stats variant used; the
// gitBase segment uses \x02 to keep the HEAD-default key
// byte-identical to the pre-change one (= bare path, optionally
// with "\x01stats").
- (NSString *)cacheKeyForPath:(NSString *)path
                      gitBase:(NSString * _Nullable)gitBase
             includeDiffStats:(BOOL)includeDiffStats {
    NSString *key = path;
    if (includeDiffStats) {
        key = [key stringByAppendingString:@"\x01stats"];
    }
    if (gitBase.length > 0 && ![gitBase isEqualToString:@"HEAD"]) {
        key = [key stringByAppendingFormat:@"\x02%@", gitBase];
    }
    return key;
}

- (void)requestPath:(NSString *)path
            gitBase:(NSString * _Nullable)gitBase
   includeDiffStats:(BOOL)includeDiffStats
         completion:(void (^)(iTermGitState * _Nullable, BOOL timedOut))completion {
    DLog(@"requestPath:%@ gitBase:%@ includeDiffStats:%@", path, gitBase, @(includeDiffStats));
    const NSTimeInterval ttl = 1;
    NSString *cacheKey = [self cacheKeyForPath:path
                                       gitBase:gitBase
                              includeDiffStats:includeDiffStats];

    iTermGitState *existing = _cache[cacheKey];
    DLog(@"Existing state %@ has age %@", existing, @(existing.age));
    if (existing != nil && existing.age < ttl) {
        completion(existing, NO);
        return;
    }

    NSMutableArray<iTermGitPollWorkerCompletionBlock> *pending = _pending[cacheKey];
    if (pending.count) {
        DLog(@"Add to pending request for %@ with %@ waiting blocks. Pending is now:\n%@", cacheKey, @(pending.count), _pending);
        [pending addObject:[completion copy]];
        return;
    }

    _pending[cacheKey] = [@[ [completion copy] ] mutableCopy];
    DLog(@"Create pending request for %@ with a single waiter", cacheKey);
    DLog(@"Send through gateway with the following pending requests:\n%@", _pending);
    [[iTermSlowOperationGateway sharedInstance] requestGitStateForPath:path
                                                               gitBase:gitBase
                                                      includeDiffStats:includeDiffStats
                                                            completion:^(iTermGitState * _Nullable state, BOOL timedOut) {
        DLog(@"Got response for %@ with state %@ timedOut=%@", cacheKey, state, @(timedOut));
        [self didFetchState:state timedOut:timedOut cacheKey:cacheKey];
    }];
}

- (void)didFetchState:(iTermGitState *)state timedOut:(BOOL)timedOut cacheKey:(NSString *)cacheKey {
    DLog(@"Did fetch state %@ timedOut=%@ for cacheKey %@", state, @(timedOut), cacheKey);
    iTermGitState *cached = _cache[cacheKey];
    if (cached != nil &&
        !isnan(cached.creationTime) &&  // just paranoia to avoid unbounded recursion
        cached.creationTime > state.creationTime) {
        DLog(@"Cached entry is newer. Recurse.");
        // A stale cached state is preferable to a nil reply, but preserve the timeout signal so
        // callers can distinguish "we have no info" from "we have stale info because of a timeout".
        [self didFetchState:cached timedOut:timedOut cacheKey:cacheKey];
        return;
    }

    DLog(@"Save to cache");
    _cache[cacheKey] = state;

    NSArray<iTermGitPollWorkerCompletionBlock> *blocks = _pending[cacheKey];
    DLog(@"Invoke %@ blocks", @(blocks.count));
    [_pending removeObjectForKey:cacheKey];
    DLog(@"Remove all waiters from pending for %@. Pending is now\n%@", cacheKey, _pending);
    [blocks enumerateObjectsUsingBlock:^(iTermGitPollWorkerCompletionBlock  _Nonnull block, NSUInteger idx, BOOL * _Nonnull stop) {
        DLog(@"Invoke completion block for cacheKey %@ with state %@ timedOut=%@", cacheKey, state, @(timedOut));
        block(state, timedOut);
    }];
}

- (void)invalidateCacheForPath:(NSString *)path {
    // Wipe both the cache and the pending dict for every key that
    // belongs to this path. Three key shapes:
    //   `path`                       — basic, HEAD
    //   `path\x01stats[\x02<base>]`  — rich, HEAD or non-HEAD base
    //   `path\x02<base>`             — basic, non-HEAD base
    // A prefix sweep on `\x01` and `\x02` catches the latter two,
    // and an exact match catches the bare-path key.
    NSString *statsPrefix = [path stringByAppendingString:@"\x01"];
    NSString *basePrefix = [path stringByAppendingString:@"\x02"];
    NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
    for (NSString *key in _pending) {
        if ([key isEqualToString:path] ||
            [key hasPrefix:statsPrefix] ||
            [key hasPrefix:basePrefix]) {
            [toRemove addObject:key];
        }
    }
    for (NSString *key in toRemove) {
        [_pending removeObjectForKey:key];
    }
    [toRemove removeAllObjects];
    for (NSString *key in _cache) {
        if ([key isEqualToString:path] ||
            [key hasPrefix:statsPrefix] ||
            [key hasPrefix:basePrefix]) {
            [toRemove addObject:key];
        }
    }
    for (NSString *key in toRemove) {
        [_cache removeObjectForKey:key];
    }
}

@end

NS_ASSUME_NONNULL_END
