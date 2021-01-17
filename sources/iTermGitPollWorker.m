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
    return _cache[path].branch;
}

- (void)requestPath:(NSString *)path completion:(void (^)(iTermGitState * _Nullable))completion {
    DLog(@"requestPath:%@", path);
    const NSTimeInterval ttl = 1;

    iTermGitState *existing = _cache[path];
    DLog(@"Existing state %@ has age %@", existing, @(existing.age));
    if (existing != nil && existing.age < ttl) {
        completion(existing);
        return;
    }

    NSMutableArray<iTermGitPollWorkerCompletionBlock> *pending = _pending[path];
    if (pending.count) {
        DLog(@"Add to pending request for %@ with %@ waiting blocks. Pending is now:\n%@", path, @(pending.count), _pending);
        [pending addObject:[completion copy]];
        return;
    }

    _pending[path] = [@[ [completion copy] ] mutableCopy];
    DLog(@"Create pending request for %@ with a single waiter", path);
    DLog(@"Send through gateway with the following pending requests:\n%@", _pending);
    [[iTermSlowOperationGateway sharedInstance] requestGitStateForPath:path completion:^(iTermGitState * _Nullable state) {
        DLog(@"Got response for %@ with state %@", path, state);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self didFetchState:state path:path];
        });
    }];
}

- (void)didFetchState:(iTermGitState *)state path:(NSString *)path {
    DLog(@"Did fetch state %@ for path %@", state, path);
    iTermGitState *cached = _cache[path];
    if (cached != nil &&
        !isnan(cached.creationTime) &&  // just paranoia to avoid unbounded recursion
        cached.creationTime > state.creationTime) {
        DLog(@"Cached entry is newer. Recurse.");
        [self didFetchState:cached path:path];
        return;
    }

    DLog(@"Save to cache");
    _cache[path] = state;

    NSArray<iTermGitPollWorkerCompletionBlock> *blocks = _pending[path];
    DLog(@"Invoke %@ blocks", @(blocks.count));
    [_pending removeObjectForKey:path];
    DLog(@"Remove all waiters from pending for %@. Pending is now\n%@", path, _pending);
    [blocks enumerateObjectsUsingBlock:^(iTermGitPollWorkerCompletionBlock  _Nonnull block, NSUInteger idx, BOOL * _Nonnull stop) {
        DLog(@"Invoke completion block for path %@ with state %@", path, state);
        block(state);
    }];
}

- (void)invalidateCacheForPath:(NSString *)path {
    [_pending removeObjectForKey:path];
}

@end

NS_ASSUME_NONNULL_END
