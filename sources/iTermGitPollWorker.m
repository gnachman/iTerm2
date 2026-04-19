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

typedef void (^iTermGitPollWorkerCompletionBlock)(iTermGitState * _Nullable);

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
    // Prefer either cache entry — branch is the same in both.
    iTermGitState *cached = _cache[[self cacheKeyForPath:path includeDiffStats:YES]] ?:
                            _cache[[self cacheKeyForPath:path includeDiffStats:NO]];
    return cached.branch;
}

- (NSString *)debugInfoForDirectory:(NSString *)path {
    iTermGitState *basic = _cache[[self cacheKeyForPath:path includeDiffStats:NO]];
    iTermGitState *rich = _cache[[self cacheKeyForPath:path includeDiffStats:YES]];
    NSUInteger pendingCount = _pending[[self cacheKeyForPath:path includeDiffStats:NO]].count +
                              _pending[[self cacheKeyForPath:path includeDiffStats:YES]].count;
    return [NSString stringWithFormat:@"Basic cache: %@\nRich cache: %@\nPending calls: %@\n",
            basic ? [NSString stringWithFormat:@"age %@", @(basic.age)] : @"none",
            rich ? [NSString stringWithFormat:@"age %@", @(rich.age)] : @"none",
            @(pendingCount)];
}

- (NSString *)cacheKeyForPath:(NSString *)path includeDiffStats:(BOOL)includeDiffStats {
    return includeDiffStats ? [path stringByAppendingString:@"\x01stats"] : path;
}

- (void)requestPath:(NSString *)path
   includeDiffStats:(BOOL)includeDiffStats
         completion:(void (^)(iTermGitState * _Nullable))completion {
    DLog(@"requestPath:%@ includeDiffStats:%@", path, @(includeDiffStats));
    const NSTimeInterval ttl = 1;
    NSString *cacheKey = [self cacheKeyForPath:path includeDiffStats:includeDiffStats];

    iTermGitState *existing = _cache[cacheKey];
    DLog(@"Existing state %@ has age %@", existing, @(existing.age));
    if (existing != nil && existing.age < ttl) {
        completion(existing);
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
                                                      includeDiffStats:includeDiffStats
                                                            completion:^(iTermGitState * _Nullable state) {
        DLog(@"Got response for %@ with state %@", cacheKey, state);
        [self didFetchState:state cacheKey:cacheKey];
    }];
}

- (void)didFetchState:(iTermGitState *)state cacheKey:(NSString *)cacheKey {
    DLog(@"Did fetch state %@ for cacheKey %@", state, cacheKey);
    iTermGitState *cached = _cache[cacheKey];
    if (cached != nil &&
        !isnan(cached.creationTime) &&  // just paranoia to avoid unbounded recursion
        cached.creationTime > state.creationTime) {
        DLog(@"Cached entry is newer. Recurse.");
        [self didFetchState:cached cacheKey:cacheKey];
        return;
    }

    DLog(@"Save to cache");
    _cache[cacheKey] = state;

    NSArray<iTermGitPollWorkerCompletionBlock> *blocks = _pending[cacheKey];
    DLog(@"Invoke %@ blocks", @(blocks.count));
    [_pending removeObjectForKey:cacheKey];
    DLog(@"Remove all waiters from pending for %@. Pending is now\n%@", cacheKey, _pending);
    [blocks enumerateObjectsUsingBlock:^(iTermGitPollWorkerCompletionBlock  _Nonnull block, NSUInteger idx, BOOL * _Nonnull stop) {
        DLog(@"Invoke completion block for cacheKey %@ with state %@", cacheKey, state);
        block(state);
    }];
}

- (void)invalidateCacheForPath:(NSString *)path {
    [_pending removeObjectForKey:[self cacheKeyForPath:path includeDiffStats:NO]];
    [_pending removeObjectForKey:[self cacheKeyForPath:path includeDiffStats:YES]];
}

@end

NS_ASSUME_NONNULL_END
