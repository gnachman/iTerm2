//
//  iTermProcessCache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermLSOF.h"
#import "iTermProcessCache.h"
#import "iTermProcessMonitor.h"
#import "iTermRateLimitedUpdate.h"
#import "NSArray+iTerm.h"
#import <stdatomic.h>

// Event bits for coalescer
typedef NS_OPTIONS(unsigned long, iTermProcessCacheCoalescerEvent) {
    iTermProcessCacheCoalescerEventHighPriority = 1 << 0,
    iTermProcessCacheCoalescerEventLowPriority  = 1 << 1,
};

// Per-root tracking with cached subtree and epoch
@interface iTermTrackedRootInfo : NSObject
@property (nonatomic) BOOL isHighPriority;
@property (nonatomic, strong, nullable) iTermProcessMonitor *monitor;  // nil if suspended (background)
@property (nonatomic, strong) NSMutableIndexSet *cachedDescendants;    // PIDs in last snapshot
@property (nonatomic) NSUInteger lastRefreshEpoch;
@property (nonatomic) BOOL isDirty;
@end

@implementation iTermTrackedRootInfo
- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedDescendants = [NSMutableIndexSet indexSet];
        _isHighPriority = YES;  // Default to high priority (foreground)
    }
    return self;
}
@end

@interface iTermProcessCache()

// Maps process id to deepest foreground job. _lockQueue
@property (nonatomic) NSDictionary<NSNumber *, iTermProcessInfo *> *cachedDeepestForegroundJobLQ;
@property (atomic) BOOL forcingLQ;
@end

@implementation iTermProcessCache {
    dispatch_queue_t _lockQueue;
    dispatch_queue_t _workQueue;
    iTermProcessCollection *_collectionLQ; // _lockQueue
    NSMutableDictionary<NSNumber *, iTermProcessMonitor *> *_trackedPidsLQ;  // _lockQueue (legacy, being replaced by _rootsLQ)
    NSMutableArray<void (^)(void)> *_blocksLQ; // _lockQueue
    BOOL _needsUpdateFlagLQ;  // _lockQueue
    iTermRateLimitedUpdate *_rateLimit;  // Main queue. keeps updateIfNeeded from eating all the CPU
    NSMutableIndexSet *_dirtyPIDsLQ;  // _lockQueue

    // Per-root tracking (new coalescing system)
    NSMutableDictionary<NSNumber *, iTermTrackedRootInfo *> *_rootsLQ;  // _lockQueue

    // Global coalescer (dispatch_source DATA_OR)
    dispatch_source_t _coalescer;           // Merges all monitor events (_workQueue)
    NSMutableIndexSet *_dirtyHighRootsLQ;   // High-priority roots needing refresh (_lockQueue)
    NSMutableIndexSet *_dirtyLowRootsLQ;    // Low-priority (background) roots (_lockQueue)
    NSUInteger _currentEpoch;               // Incremented on each refresh cycle (_workQueue)

    // Throttle for background refresh (ensures 0.5s minimum between background refreshes)
    NSTimeInterval _lastBackgroundRefreshTime;
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
        _trackedPidsLQ = [NSMutableDictionary dictionary];
        _dirtyPIDsLQ = [NSMutableIndexSet indexSet];
        _blocksLQ = [NSMutableArray array];

        // Initialize new coalescing system
        _rootsLQ = [NSMutableDictionary dictionary];
        _dirtyHighRootsLQ = [NSMutableIndexSet indexSet];
        _dirtyLowRootsLQ = [NSMutableIndexSet indexSet];
        _currentEpoch = 0;

        // Set up global coalescer (DATA_OR merges concurrent events)
        [self setupCoalescer];

        // I'm not fond of this pattern (code that sometimes is synchronous and sometimes not) but
        // I don't want to break -setNeedsUpdate when called on the main queue and that requires
        // synchronous initialization. Job managers use the process cache on their own queues and
        // sometimes they win a race and call init before anyone else, so it has to work in this
        // case.
        if (dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) != dispatch_queue_get_label(dispatch_get_main_queue())) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishInitialization];
            });
        } else {
            [self finishInitialization];
        }
    }
    return self;
}

- (void)finishInitialization {
    // Perform main-thread-only initialization.
    _rateLimit = [[iTermRateLimitedUpdate alloc] initWithName:@"Process cache"
                                              minimumInterval:0.5];
    [self setNeedsUpdate:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidResignActive:)
                                                 name:NSApplicationDidResignActiveNotification
                                               object:nil];
}

#pragma mark - APIs

// Main queue
- (void)setNeedsUpdate:(BOOL)needsUpdate {
    if (dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) != dispatch_queue_get_label(dispatch_get_main_queue())) {
        DLog(@"Try again on main queue");
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"Trying again on main queue");
            [self setNeedsUpdate:needsUpdate];
        });
        return;
    }

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
    [self requestImmediateUpdateWithCompletionQueue:dispatch_get_main_queue()
                                              block:completion];
}

// main queue
- (void)requestImmediateUpdateWithCompletionQueue:(dispatch_queue_t)queue
                                            block:(void (^)(void))completion {
    __block BOOL needsUpdate;
    dispatch_sync(_lockQueue, ^{
        void (^wrapper)(void) = ^{
            dispatch_async(queue, completion);
        };
        [self->_blocksLQ addObject:[wrapper copy]];
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


// lockQueue
- (void)queueRequestUpdateWithCompletionQueue:(dispatch_queue_t)queue block:(void (^)(void))completion {
    __block BOOL needsUpdate;
    void (^wrapper)(void) = ^{
        dispatch_async(queue, completion);
    };
    [self->_blocksLQ addObject:[wrapper copy]];
    needsUpdate = self->_blocksLQ.count == 1;
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

// main queue
- (void)updateSynchronously {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [self requestImmediateUpdateWithCompletionQueue:_workQueue block:^{
        dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
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

    // NOTE: blocks are called on the work queue, but they should have been wrapped with a
    // dispatch_async to the queue the caller really wants.
    for (void (^block)(void) in blocks) {
        block();
    }
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
        __weak __typeof(self) weakSelf = self;

        // Create monitor with trackedRootPID for new coalescing system
        iTermProcessMonitor *monitor = [[iTermProcessMonitor alloc] initWithQueue:self->_lockQueue
                                                                         callback:^(iTermProcessMonitor *mon, dispatch_source_proc_flags_t flags) {
            [weakSelf processMonitor:mon didChangeFlags:flags];
        }
                                                                   trackedRootPID:pid];

        iTermProcessInfo *info = [self->_collectionLQ infoForProcessID:pid];
        if (!info) {
            DLog(@"Request update for %@", @(pid));
            [self queueRequestUpdateWithCompletionQueue:self->_lockQueue block:^{
                DLog(@"Got update for %@", @(pid));
                [weakSelf didUpdateForPid:pid];
            }];
        } else {
            [monitor setProcessInfo:info];
        }

        // Legacy tracking (for backward compatibility)
        self->_trackedPidsLQ[@(pid)] = monitor;

        // New coalescing system - create iTermTrackedRootInfo
        iTermTrackedRootInfo *rootInfo = [[iTermTrackedRootInfo alloc] init];
        rootInfo.monitor = monitor;
        rootInfo.isHighPriority = YES;  // New registrations are foreground by default
        rootInfo.isDirty = YES;
        self->_rootsLQ[@(pid)] = rootInfo;

        // Trigger initial refresh for this root
        [self->_dirtyHighRootsLQ addIndex:pid];
        dispatch_source_merge_data(self->_coalescer, iTermProcessCacheCoalescerEventHighPriority);
    });
}

// lockQueue
- (void)didUpdateForPid:(pid_t)pid {
    iTermProcessInfo *info = [self->_collectionLQ infoForProcessID:pid];
    if (!info) {
        DLog(@":( no info for %@", @(pid));
        return;
    }
    iTermProcessMonitor *monitor = self->_trackedPidsLQ[@(pid)];
    if (!monitor || monitor.processInfo != nil) {
        DLog(@":( no monitor for %@", @(pid));
        return;
    }
    DLog(@"Set info in monitor to %@", info);
    monitor.processInfo = info;
}

// lockQueue
- (void)processMonitor:(iTermProcessMonitor *)monitor didChangeFlags:(dispatch_source_proc_flags_t)flags {
    DLog(@"Flags changed for %@.", @(monitor.processInfo.processID));

    // New coalescing system: use trackedRootPID to find the root and signal coalescer
    pid_t rootPID = monitor.trackedRootPID;
    if (rootPID > 0) {
        iTermTrackedRootInfo *rootInfo = _rootsLQ[@(rootPID)];
        if (rootInfo) {
            rootInfo.isDirty = YES;

            // Preserve dirty PID signaling for processIsDirty: callers (e.g., session title updates)
            [_dirtyPIDsLQ addIndex:rootPID];

            if (rootInfo.isHighPriority) {
                [_dirtyHighRootsLQ addIndex:rootPID];
                // Signal coalescer (merges with other concurrent events)
                dispatch_source_merge_data(_coalescer, iTermProcessCacheCoalescerEventHighPriority);
            } else {
                // Background root - just mark dirty, will be handled by cadence timer
                [_dirtyLowRootsLQ addIndex:rootPID];
            }
            return;  // New system handled it
        }
    }

    // Legacy path: fall back to old behavior for monitors not in the new system
    _needsUpdateFlagLQ = YES;
    const BOOL wasForced = self.forcingLQ;
    self.forcingLQ = YES;
    if (!wasForced) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"Forcing update (legacy path)");
            [self->_rateLimit performRateLimitedSelector:@selector(updateIfNeeded) onTarget:self withObject:nil];
            [self->_rateLimit performWithinDuration:0.0167];
            self.forcingLQ = NO;
        });
    }
}

// Main queue
- (BOOL)processIsDirty:(pid_t)pid {
    __block BOOL result;
    dispatch_sync(_lockQueue, ^{
        result = [_dirtyPIDsLQ containsIndex:pid];
        if (result) {
            DLog(@"Found dirty process %@", @(pid));
            [_dirtyPIDsLQ removeIndex:pid];
        }
    });
    return result;
}

// Any queue
- (void)unregisterTrackedPID:(pid_t)pid {
    dispatch_async(_lockQueue, ^{
        // Legacy cleanup
        [self->_trackedPidsLQ removeObjectForKey:@(pid)];

        // New coalescing system cleanup
        iTermTrackedRootInfo *rootInfo = self->_rootsLQ[@(pid)];
        if (rootInfo) {
            // Invalidate the monitor (stops the dispatch source)
            [rootInfo.monitor invalidate];
            [self->_rootsLQ removeObjectForKey:@(pid)];
        }

        // Remove from dirty sets
        [self->_dirtyHighRootsLQ removeIndex:pid];
        [self->_dirtyLowRootsLQ removeIndex:pid];
    });
}

- (void)sendSignal:(int32_t)signal toPID:(int32_t)pid {
    kill(pid, signal);
}

#pragma mark - Private

// Any queue
- (void)updateIfNeeded {
    DLog(@"updateIfNeeded");

    // Process background roots only on ~0.5s cadence (not on every call)
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _lastBackgroundRefreshTime >= 0.5) {
        _lastBackgroundRefreshTime = now;
        [self backgroundRefreshTick];
    }

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

+ (iTermProcessCollection *)newProcessCollection {
    NSArray<NSNumber *> *allPids = [iTermLSOF allPids];
    // pid -> ppid
    NSMutableDictionary<NSNumber *, NSNumber *> *parentmap = [NSMutableDictionary dictionary];
    iTermProcessCollection *collection = [[iTermProcessCollection alloc] initWithDataSource:[iTermLSOF processDataSource]];
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
        trackedPIDs = [self->_trackedPidsLQ.allKeys copy];
    });
    for (NSNumber *root in trackedPIDs) {
        iTermProcessInfo *info = [collection infoForProcessID:root.integerValue].deepestForegroundJob;
        DLog(@"iTermProcessCache: deepest fg job for %@ is %@", @(root.integerValue), @(info.processID));
        if (info) {
            cache[root] = info;
        }
    }
    return cache;
}

// _workQueue
- (void)reallyUpdate {
    DLog(@"* DOING THE EXPENSIVE THING * Process cache reallyUpdate starting");

    @autoreleasepool {
        // Do expensive stuff
        iTermProcessCollection *collection = [self.class newProcessCollection];

        // Save the tracked PIDs in the cache
        NSDictionary<NSNumber *, iTermProcessInfo *> *cachedDeepestForegroundJob = [self newDeepestForegroundJobCacheWithCollection:collection];

        // Flip to the new state.
        dispatch_sync(_lockQueue, ^{
            self->_cachedDeepestForegroundJobLQ = cachedDeepestForegroundJob;
            self->_collectionLQ = collection;
            self->_needsUpdateFlagLQ = NO;
            [_trackedPidsLQ enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, iTermProcessMonitor * _Nonnull monitor, BOOL * _Nonnull stop) {
                iTermProcessInfo *info = [collection infoForProcessID:key.intValue];
                if ([monitor setProcessInfo:info]) {
                    DLog(@"%@ changed! Set dirty", @(info.processID));
                    [_dirtyPIDsLQ addIndex:key.intValue];
                }
            }];
        });
    }
}

#pragma mark - Coalescer

- (void)setupCoalescer {
    _coalescer = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_OR, 0, 0, _workQueue);

    __weak __typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_coalescer, ^{
        [weakSelf handleCoalescedEvents];
    });
    dispatch_resume(_coalescer);
}

// _workQueue
- (void)handleCoalescedEvents {
    unsigned long data = dispatch_source_get_data(_coalescer);
    BOOL hasHighPriority = (data & iTermProcessCacheCoalescerEventHighPriority) != 0;

    if (hasHighPriority) {
        // Immediate incremental refresh for dirty high-priority roots
        [self refreshDirtyHighPriorityRoots];
    }
    // Low-priority handled by 0.5s cadence timer (backgroundRefreshTick), not here
}

// _workQueue
- (void)refreshDirtyHighPriorityRoots {
    _currentEpoch++;

    __block NSMutableArray<NSNumber *> *dirtyRoots = [NSMutableArray array];
    __block iTermProcessCollection *collection;

    dispatch_sync(_lockQueue, ^{
        [self->_dirtyHighRootsLQ enumerateIndexesUsingBlock:^(NSUInteger pid, BOOL *stop) {
            [dirtyRoots addObject:@(pid)];
        }];
        [self->_dirtyHighRootsLQ removeAllIndexes];
        collection = self->_collectionLQ;  // Capture reference under lock
    });

    if (!collection || dirtyRoots.count == 0) {
        return;
    }

    NSMutableDictionary<NSNumber *, iTermProcessInfo *> *newCache = [NSMutableDictionary dictionary];
    NSMutableArray<NSNumber *> *confirmedDeadRoots = [NSMutableArray array];

    for (NSNumber *rootPidNum in dirtyRoots) {
        pid_t rootPid = rootPidNum.intValue;
        iTermProcessInfo *result = [self refreshRootCollectionFirst:rootPid
                                                         collection:collection
                                                              epoch:_currentEpoch];
        if (result) {
            newCache[rootPidNum] = result;
        } else {
            // Refresh returned nil - check if process is actually dead before removing cache entry.
            // This avoids dropping cached data due to collection staleness.
            if (![self processIsAlive:rootPid]) {
                [confirmedDeadRoots addObject:rootPidNum];
            }
            // If process is still alive, preserve existing cache entry (don't add to newCache or deadRoots)
        }
    }

    dispatch_sync(_lockQueue, ^{
        // Merge new cache entries into existing cache
        NSMutableDictionary *mutableCache = [self->_cachedDeepestForegroundJobLQ mutableCopy] ?: [NSMutableDictionary dictionary];
        [mutableCache addEntriesFromDictionary:newCache];

        // Only remove entries for roots confirmed dead (not just fallback/stale)
        for (NSNumber *deadPid in confirmedDeadRoots) {
            [mutableCache removeObjectForKey:deadPid];
        }

        self->_cachedDeepestForegroundJobLQ = [mutableCache copy];

        // Evict unseen nodes from per-root caches
        for (NSNumber *rootPidNum in dirtyRoots) {
            [self evictUnseenNodesForRoot:rootPidNum.intValue epoch:self->_currentEpoch];
        }
    });
}

// _workQueue - Fast path: walk existing collection (no PID enumeration syscalls)
- (iTermProcessInfo *)refreshRootCollectionFirst:(pid_t)rootPid
                                      collection:(iTermProcessCollection *)collection
                                           epoch:(NSUInteger)epoch {
    __block iTermTrackedRootInfo *rootInfo;
    dispatch_sync(_lockQueue, ^{
        rootInfo = self->_rootsLQ[@(rootPid)];
    });

    if (!rootInfo) {
        return nil;
    }

    iTermProcessInfo *root = [collection infoForProcessID:rootPid];
    if (!root) {
        // Root disappeared - fall back to kernel query
        return [self refreshRootWithKernelFallback:rootPid epoch:epoch];
    }

    // Walk foreground chain preferentially (root → fg child → fg grandchild)
    // Collect PIDs to mark as seen (batched to avoid per-PID dispatch_sync)
    NSMutableIndexSet *seenPIDs = [NSMutableIndexSet indexSet];
    iTermProcessInfo *candidate = root;
    int depth = 0;
    while (depth < 50) {
        [seenPIDs addIndex:candidate.processID];

        iTermProcessInfo *fgChild = [self findForegroundChildOf:candidate inCollection:collection];
        if (!fgChild) {
            break;
        }

        // Verify child still exists in collection
        if (![collection infoForProcessID:fgChild.processID]) {
            // Inconsistency detected - bounded kernel fallback
            return [self refreshRootWithKernelFallback:rootPid epoch:epoch];
        }

        candidate = fgChild;
        depth++;
    }

    // Single dispatch_sync to mark all seen PIDs and clear dirty flag
    dispatch_sync(_lockQueue, ^{
        [rootInfo.cachedDescendants addIndexes:seenPIDs];
        rootInfo.lastRefreshEpoch = epoch;
        rootInfo.isDirty = NO;
    });

    return candidate;  // Deepest foreground job
}

// _workQueue - Find foreground child using collection's cached foreground state
- (iTermProcessInfo *)findForegroundChildOf:(iTermProcessInfo *)parent
                               inCollection:(iTermProcessCollection *)collection {
    // iTermProcessInfo has children and isForegroundJob properties
    for (iTermProcessInfo *child in parent.children) {
        if (child.isForegroundJob) {
            return child;
        }
    }
    return nil;
}

// _workQueue - Fallback: bounded kernel queries for this root only
- (iTermProcessInfo *)refreshRootWithKernelFallback:(pid_t)rootPid epoch:(NSUInteger)epoch {
    // Query kernel for root's immediate children only (bounded)
    NSArray<NSNumber *> *children = [iTermLSOF childPidsForPid:rootPid];

    __block iTermTrackedRootInfo *rootInfo;
    dispatch_sync(_lockQueue, ^{
        rootInfo = self->_rootsLQ[@(rootPid)];
    });

    if (!rootInfo) {
        return nil;
    }

    // Collect all PIDs to mark as seen (batched to avoid per-PID dispatch_sync)
    NSMutableIndexSet *seenPIDs = [NSMutableIndexSet indexSet];
    [seenPIDs addIndex:rootPid];
    for (NSNumber *childPid in children) {
        [seenPIDs addIndex:childPid.unsignedIntegerValue];
    }

    // Single dispatch_sync to mark all seen PIDs and clear dirty flag
    dispatch_sync(_lockQueue, ^{
        [rootInfo.cachedDescendants addIndexes:seenPIDs];
        rootInfo.lastRefreshEpoch = epoch;
        rootInfo.isDirty = NO;
    });

    return nil;  // Let the regular cadence update provide the full answer
}

// _lockQueue - Remove PIDs that weren't seen in the current epoch
- (void)evictUnseenNodesForRoot:(pid_t)rootPid epoch:(NSUInteger)epoch {
    iTermTrackedRootInfo *info = _rootsLQ[@(rootPid)];
    if (!info) {
        return;
    }

    // If this root's last refresh epoch is older than current, it wasn't refreshed
    // In that case, don't evict (it might be a background root)
    if (info.lastRefreshEpoch < epoch) {
        return;
    }

    // For now, we don't track per-PID epochs, so we can't selectively evict
    // The epoch system mainly prevents drift when roots become stale
    // A more sophisticated implementation could track (pid -> lastSeenEpoch) in cachedDescendants
}

// Check if a process is still alive using kill(pid, 0)
// Returns YES if process exists, NO if confirmed dead
- (BOOL)processIsAlive:(pid_t)pid {
    if (pid <= 0) {
        return NO;
    }
    int result = kill(pid, 0);
    if (result == 0) {
        return YES;  // Process exists and we have permission to signal it
    }
    // Check errno: ESRCH means no such process, EPERM means exists but no permission
    return (errno == EPERM);
}

#pragma mark - Background Monitor Suspension

// _lockQueue - Called when a tab loses foreground
- (void)suspendMonitorForRootLQ:(pid_t)rootPid {
    iTermTrackedRootInfo *info = _rootsLQ[@(rootPid)];
    if (!info) {
        return;
    }

    DLog(@"Suspending monitor for root %@", @(rootPid));
    if (info.monitor) {
        [info.monitor pauseMonitoring];
    }
    info.isHighPriority = NO;
    [_dirtyLowRootsLQ addIndex:rootPid];
}

// _lockQueue - Called when a tab becomes foreground
- (void)resumeMonitorForRootLQ:(pid_t)rootPid {
    iTermTrackedRootInfo *info = _rootsLQ[@(rootPid)];
    if (!info) {
        return;
    }

    DLog(@"Resuming monitor for root %@", @(rootPid));
    info.isHighPriority = YES;

    if (info.monitor) {
        [info.monitor resumeMonitoring];
    } else {
        [self createMonitorForRootLQ:rootPid info:info];
    }

    // Immediate refresh for newly-foregrounded root
    info.isDirty = YES;
    [_dirtyHighRootsLQ addIndex:rootPid];
    dispatch_source_merge_data(_coalescer, iTermProcessCacheCoalescerEventHighPriority);
}

// _lockQueue - Create a new monitor for a root PID
- (void)createMonitorForRootLQ:(pid_t)rootPid info:(iTermTrackedRootInfo *)info {
    __weak __typeof(self) weakSelf = self;
    iTermProcessMonitor *monitor = [[iTermProcessMonitor alloc] initWithQueue:_lockQueue
                                                                     callback:^(iTermProcessMonitor *mon, dispatch_source_proc_flags_t flags) {
        [weakSelf processMonitor:mon didChangeFlags:flags];
    }
                                                               trackedRootPID:rootPid];

    iTermProcessInfo *processInfo = [_collectionLQ infoForProcessID:rootPid];
    if (processInfo) {
        [monitor setProcessInfo:processInfo];
    }

    info.monitor = monitor;
}

// Any queue - Public API for tab selection
- (void)setForegroundRootPIDs:(NSSet<NSNumber *> *)foregroundPIDs {
    dispatch_async(_lockQueue, ^{
        [self setForegroundRootPIDsLQ:foregroundPIDs];
    });
}

// _lockQueue
- (void)setForegroundRootPIDsLQ:(NSSet<NSNumber *> *)foregroundPIDs {
    for (NSNumber *pidNum in _rootsLQ) {
        iTermTrackedRootInfo *info = _rootsLQ[pidNum];
        BOOL shouldBeForeground = [foregroundPIDs containsObject:pidNum];

        if (shouldBeForeground && !info.isHighPriority) {
            [self resumeMonitorForRootLQ:pidNum.intValue];
        } else if (!shouldBeForeground && info.isHighPriority) {
            [self suspendMonitorForRootLQ:pidNum.intValue];
        }
    }
}

#pragma mark - Amortized Background Refresh

// Called by 0.5s cadence timer - refresh 1-2 background roots per tick
- (void)backgroundRefreshTick {
    __block NSArray<NSNumber *> *toRefresh = nil;
    __block iTermProcessCollection *collection = nil;
    __block NSUInteger epoch = 0;

    dispatch_sync(_lockQueue, ^{
        if (self->_dirtyLowRootsLQ.count == 0) {
            return;
        }

        NSMutableArray<NSNumber *> *picked = [NSMutableArray array];
        __block NSUInteger remaining = 2;  // Process at most 2 background roots per tick
        [self->_dirtyLowRootsLQ enumerateIndexesUsingBlock:^(NSUInteger pid, BOOL *stop) {
            [picked addObject:@(pid)];
            if (--remaining == 0) {
                *stop = YES;
            }
        }];

        for (NSNumber *pidNum in picked) {
            [self->_dirtyLowRootsLQ removeIndex:pidNum.unsignedIntegerValue];
        }

        toRefresh = [picked copy];
        collection = self->_collectionLQ;  // Capture under lock
        // Reuse current epoch (background refreshes don't advance epoch)
        epoch = self->_currentEpoch;
    });

    if (toRefresh.count == 0) {
        return;
    }

    dispatch_async(_workQueue, ^{
        NSMutableArray<NSNumber *> *confirmedDeadRoots = [NSMutableArray array];
        NSMutableDictionary<NSNumber *, iTermProcessInfo *> *newCache = [NSMutableDictionary dictionary];

        for (NSNumber *pidNum in toRefresh) {
            iTermProcessInfo *result = [self refreshRootCollectionFirst:pidNum.intValue
                                                             collection:collection
                                                                  epoch:epoch];
            if (result) {
                newCache[pidNum] = result;
            } else {
                // Only remove cache entry if process is confirmed dead
                if (![self processIsAlive:pidNum.intValue]) {
                    [confirmedDeadRoots addObject:pidNum];
                }
            }
        }

        // Update cache with results and remove confirmed dead entries
        NSSet<NSNumber *> *deadSet = [NSSet setWithArray:confirmedDeadRoots];
        dispatch_sync(self->_lockQueue, ^{
            if (newCache.count > 0 || confirmedDeadRoots.count > 0) {
                NSMutableDictionary *mutableCache = [self->_cachedDeepestForegroundJobLQ mutableCopy] ?: [NSMutableDictionary dictionary];
                [mutableCache addEntriesFromDictionary:newCache];
                for (NSNumber *deadPid in confirmedDeadRoots) {
                    [mutableCache removeObjectForKey:deadPid];
                }
                self->_cachedDeepestForegroundJobLQ = [mutableCache copy];
            }

            // Re-add ALL alive roots that are still background (low priority)
            // so they continue getting periodic updates on the 0.5s cadence.
            // This includes roots where refresh returned nil due to stale collection.
            for (NSNumber *pidNum in toRefresh) {
                if ([deadSet containsObject:pidNum]) {
                    continue;  // Don't re-add confirmed dead roots
                }
                iTermTrackedRootInfo *info = self->_rootsLQ[pidNum];
                if (info && !info.isHighPriority) {
                    [self->_dirtyLowRootsLQ addIndex:pidNum.unsignedIntegerValue];
                }
            }
        });
    });
}

#pragma mark - Notifications

// Main queue
- (void)applicationDidResignActive:(NSNotification *)notification {
    _rateLimit.minimumInterval = 5;
}

// Main queue
- (void)applicationDidBecomeActive:(NSNotification *)notification {
    DLog(@"Application did become active (process cache)");
    _rateLimit.minimumInterval = 0.5;
}

@end
