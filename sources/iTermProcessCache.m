//
//  iTermProcessCache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "iTermLSOF.h"
#import "iTermProcessCache.h"
#import "iTermRateLimitedUpdate.h"
#import "NSArray+iTerm.h"
#import <stdatomic.h>

@interface iTermProcessCache()

// Maps process id to deepest foreground job. _lockQueue
@property (nonatomic) NSDictionary<NSNumber *, iTermProcessInfo *> *cachedDeepestForegroundJobLQ;

@end

@implementation iTermProcessCache {
    dispatch_queue_t _lockQueue;
    dispatch_queue_t _workQueue;
    iTermProcessCollection *_collectionLQ; // _lockQueue
    NSMutableSet<NSNumber *> *_trackedPidsLQ;  // _lockQueue
    NSMutableArray<void (^)(void)> *_blocksLQ; // _lockQueue
    BOOL _needsUpdateFlagLQ;  // _lockQueue
    iTermRateLimitedUpdate *_rateLimit;  // Main queue. keeps updateIfNeeded from eating all the CPU
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lockQueue = dispatch_queue_create("com.iterm2.process-cache-lock", DISPATCH_QUEUE_SERIAL);
        _workQueue = dispatch_queue_create("com.iterm2.process-cache-work", DISPATCH_QUEUE_SERIAL);
        _rateLimit = [[iTermRateLimitedUpdate alloc] init];
        _rateLimit.minimumInterval = 0.5;
        _trackedPidsLQ = [NSMutableSet set];
        [self setNeedsUpdate:YES];
        _blocksLQ = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];
    }
    return self;
}

#pragma mark - APIs

// Main queue
- (void)setNeedsUpdate:(BOOL)needsUpdate {
    DLog(@"setNeedsUpdate:%@", @(needsUpdate));
    dispatch_sync(_lockQueue, ^{
        self->_needsUpdateFlagLQ = needsUpdate;
    });
    if (needsUpdate) {
        [_rateLimit performRateLimitedSelector:@selector(updateIfNeeded) onTarget:self withObject:nil];
    }
}

// main queue
- (void)requestImmediateUpdateWithCompletionBlock:(void (^)(void))completion {
    __block BOOL needsUpdate;
    dispatch_sync(_lockQueue, ^{
        [self->_blocksLQ addObject:[completion copy]];
        needsUpdate = self->_blocksLQ.count == 1;
    });
    if (!needsUpdate) {
        DLog(@"request immediate update just added block to queue");
        return;
    }
    DLog(@"request immediate update scheduling update");
    __weak __typeof(self) weakSelf = self;
    dispatch_async(_workQueue, ^{
        [weakSelf collectBlocksAndUpdate];
    });
}

// _workQueue
- (void)collectBlocksAndUpdate {
    __block NSArray<void (^)(void)> *blocks;
    dispatch_sync(_lockQueue, ^{
        blocks = self->_blocksLQ.copy;
        [self->_blocksLQ removeAllObjects];
    });
    assert(blocks.count > 0);
    DLog(@"collecting blocks and updating");
    [self reallyUpdate];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (void (^block)(void) in blocks) {
            block();
        }
    });
}

// Any queue
- (iTermProcessInfo *)processInfoForPid:(pid_t)pid {
    __block iTermProcessInfo *info = nil;
    dispatch_sync(_lockQueue, ^{
        info = [self->_collectionLQ infoForProcessID:pid];
    });
    return info;
}

// Any queue
- (iTermProcessInfo *)deepestForegroundJobForPid:(pid_t)pid {
    __block iTermProcessInfo *result;
    dispatch_sync(_lockQueue, ^{
        result = self.cachedDeepestForegroundJobLQ[@(pid)];
    });
    return result;
}

// Any queue
- (void)registerTrackedPID:(pid_t)pid {
    dispatch_async(_lockQueue, ^{
        [self->_trackedPidsLQ addObject:@(pid)];
    });
}

// Any queue
- (void)unregisterTrackedPID:(pid_t)pid {
    dispatch_async(_lockQueue, ^{
        [self->_trackedPidsLQ removeObject:@(pid)];
    });
}

#pragma mark - Private

// Any queue
- (void)updateIfNeeded {
    DLog(@"updateIfNeeded");
    __block BOOL needsUpdate;
    dispatch_sync(_lockQueue, ^{
        needsUpdate = self->_needsUpdateFlagLQ;
    });
    if (!needsUpdate) {
        DLog(@"** Returning early!");
        return;
    }
    __weak __typeof(self) weakSelf = self;
    dispatch_async(_workQueue, ^{
        [weakSelf reallyUpdate];
    });
}

// _workQueue
+ (iTermProcessCollection *)newProcessCollection {
    NSArray<NSNumber *> *allPids = [iTermLSOF allPids];
    // pid -> ppid
    NSMutableDictionary<NSNumber *, NSNumber *> *parentmap = [NSMutableDictionary dictionary];
    iTermProcessCollection *collection = [[iTermProcessCollection alloc] init];
    for (NSNumber *pidNumber in allPids) {
        pid_t pid = pidNumber.intValue;

        pid_t ppid = [iTermLSOF ppidForPid:pid];
        if (!ppid) {
            continue;
        }

        parentmap[@(pid)] = @(ppid);
        [collection addProcessWithProcessID:pid parentProcessID:ppid];
    }
    [collection commit];
    return collection;
}

- (NSDictionary<NSNumber *, iTermProcessInfo *> *)newDeepestForegroundJobCacheWithCollection:(iTermProcessCollection *)collection {
    NSMutableDictionary<NSNumber *, iTermProcessInfo *> *cache = [NSMutableDictionary dictionary];
    __block NSSet<NSNumber *> *trackedPIDs;
    dispatch_sync(_lockQueue, ^{
        trackedPIDs = [self->_trackedPidsLQ copy];
    });
    for (NSNumber *root in trackedPIDs) {
        iTermProcessInfo *info = [collection infoForProcessID:root.integerValue].deepestForegroundJob;
        if (info) {
            cache[root] = info;
        }
    }
    return cache;
}

// _workQueue
- (void)reallyUpdate {
    DLog(@"Process cache reallyUpdate starting");

    // Do expensive stuff
    iTermProcessCollection *collection = [self.class newProcessCollection];

    // Save the tracked PIDs in the cache
    NSDictionary<NSNumber *, iTermProcessInfo *> *cachedDeepestForegroundJob = [self newDeepestForegroundJobCacheWithCollection:collection];

    // Flip to the new state.
    dispatch_sync(_lockQueue, ^{
        self->_cachedDeepestForegroundJobLQ = cachedDeepestForegroundJob;
        self->_collectionLQ = collection;
        self->_needsUpdateFlagLQ = NO;
    });
}

#pragma mark - Notifications

// Main queue
- (void)applicationDidResignActive:(NSNotification *)notification {
    _rateLimit.minimumInterval = 5;
}

// Main queue
- (void)applicationDidBecomeActive:(NSNotification *)notification {
    _rateLimit.minimumInterval = 0.5;
}

@end
