//
//  iTermProcessCache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermLSOF.h"
#import "iTermProcessCache.h"
#import "iTermProcessMonitor.h"
#import "iTermRateLimitedUpdate.h"
#import "NSArray+iTerm.h"
#import <stdatomic.h>

NSNotificationName const iTermProcessCacheForegroundJobAncestorsDidChangeNotification = @"iTermProcessCacheForegroundJobAncestorsDidChangeNotification";
NSString *const iTermProcessCacheForegroundJobAncestorsPidKey = @"pid";
NSString *const iTermProcessCacheForegroundJobAncestorsKey = @"ancestors";

@interface iTermProcessCache()

// Maps process id to deepest foreground job. _lockQueue
@property (nonatomic) NSDictionary<NSNumber *, iTermProcessInfo *> *cachedDeepestForegroundJobLQ;
// Maps process id to the deepest foreground job actually attached to the
// session's tty (its stdin or stdout is the terminal), falling back to the
// deepest foreground job when nothing qualifies. This is the user-facing job:
// it hides foreground-process-group helpers that are piped to their parent (e.g.
// an MCP server spawned by claude) or have their stdio redirected (e.g.
// caffeinate). _lockQueue
@property (nonatomic) NSDictionary<NSNumber *, iTermProcessInfo *> *cachedDisplayForegroundJobLQ;
@property (atomic) BOOL forcingLQ;
@end

@implementation iTermProcessCache {
    dispatch_queue_t _lockQueue;
    dispatch_queue_t _workQueue;
    iTermProcessCollection *_collectionLQ; // _lockQueue
    NSMutableDictionary<NSNumber *, iTermProcessMonitor *> *_trackedPidsLQ;  // _lockQueue
    NSMutableArray<void (^)(void)> *_blocksLQ; // _lockQueue
    BOOL _needsUpdateFlagLQ;  // _lockQueue
    iTermRateLimitedUpdate *_rateLimit;  // Main queue. keeps updateIfNeeded from eating all the CPU
    NSMutableIndexSet *_dirtyPIDsLQ;  // _lockQueue
    // Caches each tracked root pid's controlling tty (its stdio device rdev) so we
    // derive it just once per session rather than every update. The tty doesn't
    // change for the life of the session. Keyed by pid; the value is
    // @[@(rdev), rootStartTime] so a recycled pid (same number, different process)
    // is detected by its start time and re-derived rather than inheriting the prior
    // session's tty. Also pruned to the live tracked pids each update to bound size.
    // _workQueue only (reallyUpdate always runs there).
    NSMutableDictionary<NSNumber *, NSArray *> *_ttyRdevByPidWQ;
    // Last foreground-job ancestry (deepest first, lowercased) posted for each
    // tracked root pid. Used to diff and emit
    // iTermProcessCacheForegroundJobAncestorsDidChangeNotification. _lockQueue
    NSMutableDictionary<NSNumber *, NSArray<NSString *> *> *_lastAncestorsByPidLQ;
    // Diagnostics (gated by the logForegroundJobAncestryDiagnostics advanced
    // setting). Parallel to _lastAncestorsByPidLQ: the concrete pid that held each
    // ancestor name last cycle, so an ancestry shrink can report what became of the
    // vanished process. Only populated while the setting is on. _lockQueue
    NSMutableDictionary<NSNumber *, NSArray<NSNumber *> *> *_lastChainPidsByPidLQ;
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
        _lastAncestorsByPidLQ = [NSMutableDictionary dictionary];
        _lastChainPidsByPidLQ = [NSMutableDictionary dictionary];  // ancestry diagnostics
        _ttyRdevByPidWQ = [NSMutableDictionary dictionary];
        _blocksLQ = [NSMutableArray array];

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

// Any queue. Returns the precomputed tty-attached foreground job (see
// reallyUpdate). The filtered walk and its proc_pidfdinfo syscalls happen on the
// work queue during the update, not here, so this is just a dictionary read.
- (iTermProcessInfo *)displayForegroundJobForPid:(pid_t)pid {
    __block iTermProcessInfo *result;
    dispatch_sync(_lockQueue, ^{
        result = self.cachedDisplayForegroundJobLQ[@(pid)];
    });
    return result;
}

// Any queue
- (void)registerTrackedPID:(pid_t)pid {
    dispatch_async(_lockQueue, ^{
        __weak __typeof(self) weakSelf = self;
        iTermProcessMonitor *monitor = [[iTermProcessMonitor alloc] initWithQueue:self->_lockQueue
                                                                   callback:
                                  ^(iTermProcessMonitor * monitor, dispatch_source_proc_flags_t flags) {
            [weakSelf processMonitor:monitor didChangeFlags:flags];
        }];
        iTermProcessInfo *info = [self->_collectionLQ infoForProcessID:pid];
        if (!info) {
            RLog(@"Request update for %@", @(pid));
            [self queueRequestUpdateWithCompletionQueue:self->_lockQueue block:^{
                DLog(@"Got update for %@", @(pid));
                [weakSelf didUpdateForPid:pid];
            }];
        } else {
            monitor.processInfo = info;
        }
        self->_trackedPidsLQ[@(pid)] = monitor;
    });
}

// lockQueue
- (void)didUpdateForPid:(pid_t)pid {
    iTermProcessInfo *info = [self->_collectionLQ infoForProcessID:pid];
    if (!info) {
        RLog(@":( no info for %@", @(pid));
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
    _needsUpdateFlagLQ = YES;
    const BOOL wasForced = self.forcingLQ;
    self.forcingLQ = YES;
    if (!wasForced) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"Forcing update");
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
        [self->_trackedPidsLQ removeObjectForKey:@(pid)];
        // The program is gone. Emit a final empty-ancestry change so job-ended
        // triggers fire deterministically even when the process dies together
        // with the session (the case the title poll misses, because polling
        // freezes once the session has exited). Done here rather than relying
        // on a rescan because unregister + reap can race the rescan.
        NSArray<NSString *> *oldAncestors = self->_lastAncestorsByPidLQ[@(pid)];
        [self->_lastAncestorsByPidLQ removeObjectForKey:@(pid)];
        [self->_lastChainPidsByPidLQ removeObjectForKey:@(pid)];  // ancestry diagnostics
        if (oldAncestors.count > 0) {
            [self postForegroundJobAncestorChanges:@{ @(pid): @[] }];
        }
    });
}

- (void)sendSignal:(int32_t)signal toPID:(int32_t)pid {
    kill(pid, signal);
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

// _workQueue. Builds both the raw deepest-foreground-job cache and the
// tty-attached display-job cache. The proc_pidfdinfo syscalls behind the display
// job happen here (work queue), with the collection alive for the tree walk, so
// the cache reads on other queues stay cheap. Each tracked root pid's controlling
// tty is derived once from its own stdio and remembered in _ttyRdevByPidWQ.
- (void)buildForegroundJobCachesWithCollection:(iTermProcessCollection *)collection
                                       deepest:(NSDictionary<NSNumber *, iTermProcessInfo *> **)deepestOut
                                       display:(NSDictionary<NSNumber *, iTermProcessInfo *> **)displayOut {
    NSMutableDictionary<NSNumber *, iTermProcessInfo *> *deepest = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, iTermProcessInfo *> *display = [NSMutableDictionary dictionary];
    __block NSSet<NSNumber *> *trackedPIDs;
    dispatch_sync(_lockQueue, ^{
        trackedPIDs = [self->_trackedPidsLQ.allKeys copy];
    });
    for (NSNumber *root in trackedPIDs) {
        iTermProcessInfo *rootInfo = [collection infoForProcessID:root.integerValue];
        iTermProcessInfo *deepestInfo = rootInfo.deepestForegroundJob;
        DLog(@"iTermProcessCache: deepest fg job for %@ is %@", @(root.integerValue), @(deepestInfo.processID));
        if (deepestInfo) {
            deepest[root] = deepestInfo;
        }
        // The session's controlling tty doesn't change for its lifetime, so derive
        // it once and remember it. Validate the cached entry against the root's
        // start time so a recycled pid (a new session that reuses the numeric pid)
        // re-derives rather than inheriting the previous session's tty.
        NSDate *rootStartTime = rootInfo.startTime;
        NSArray *cached = _ttyRdevByPidWQ[root];
        NSNumber *rdevNumber = nil;
        if (cached && rootStartTime && [cached[1] isEqual:rootStartTime]) {
            rdevNumber = cached[0];
        } else {
            const dev_t derived = rootInfo.sessionControllingTTYRdev;
            if (derived != 0) {
                rdevNumber = @(derived);
                if (rootStartTime) {
                    _ttyRdevByPidWQ[root] = @[rdevNumber, rootStartTime];
                }
                DLog(@"iTermProcessCache: derived controlling tty rdev %d for session rooted at pid %@ (%@)", (int)derived, root, rootInfo.name);
            } else {
                // Don't keep a stale entry; re-derive next update in case the tty
                // becomes readable later.
                [_ttyRdevByPidWQ removeObjectForKey:root];
                DLog(@"iTermProcessCache: could not derive controlling tty rdev for session rooted at pid %@ (%@); display job will fall back to the deepest foreground job", root, rootInfo.name);
            }
        }
        iTermProcessInfo *displayInfo = [rootInfo deepestForegroundJobAttachedToTTYRdev:(dev_t)rdevNumber.intValue];
        DLog(@"iTermProcessCache: display fg job for %@ (tty rdev %d) is %@ (%@)", @(root.integerValue), (int)rdevNumber.intValue, @(displayInfo.processID), displayInfo.name);
        if (displayInfo) {
            display[root] = displayInfo;
        }
    }
    // Drop cached ttys for pids that are no longer tracked to bound the map's
    // size. This is not what protects against pid reuse (an unregister/re-register
    // could both happen between updates, leaving the pid tracked here the whole
    // time); the start-time check above is what handles that.
    NSMutableArray<NSNumber *> *staleKeys = [NSMutableArray array];
    for (NSNumber *key in _ttyRdevByPidWQ) {
        if (![trackedPIDs containsObject:key]) {
            [staleKeys addObject:key];
        }
    }
    [_ttyRdevByPidWQ removeObjectsForKeys:staleKeys];
    *deepestOut = deepest;
    *displayOut = display;
}

// _workQueue
- (void)reallyUpdate {
    DLog(@"* DOING THE EXPENSIVE THING * Process cache reallyUpdate starting");

    @autoreleasepool {
        // Do expensive stuff
        iTermProcessCollection *collection = [self.class newProcessCollection];

        // Save the tracked PIDs in the cache
        NSDictionary<NSNumber *, iTermProcessInfo *> *cachedDeepestForegroundJob = nil;
        NSDictionary<NSNumber *, iTermProcessInfo *> *cachedDisplayForegroundJob = nil;
        [self buildForegroundJobCachesWithCollection:collection
                                             deepest:&cachedDeepestForegroundJob
                                             display:&cachedDisplayForegroundJob];

        // Flip to the new state.
        NSMutableDictionary<NSNumber *, NSArray<NSString *> *> *ancestorChanges = [NSMutableDictionary dictionary];
        dispatch_sync(_lockQueue, ^{
            self->_cachedDeepestForegroundJobLQ = cachedDeepestForegroundJob;
            self->_cachedDisplayForegroundJobLQ = cachedDisplayForegroundJob;
            self->_collectionLQ = collection;
            self->_needsUpdateFlagLQ = NO;
            [_trackedPidsLQ enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, iTermProcessMonitor * _Nonnull monitor, BOOL * _Nonnull stop) {
                iTermProcessInfo *info = [collection infoForProcessID:key.intValue];
                if ([monitor setProcessInfo:info]) {
                    DLog(@"%@ changed! Set dirty", @(info.processID));
                    [_dirtyPIDsLQ addIndex:key.intValue];
                }
                // Diff the foreground-job ancestry so we can emit an
                // event-driven notification (job started/ended) without
                // waiting for the consumer's title poll.
                NSArray<NSString *> *newAncestors = cachedDeepestForegroundJob[key].foregroundJobAncestorNames ?: @[];
                NSArray<NSString *> *oldAncestors = self->_lastAncestorsByPidLQ[key] ?: @[];
                // Optional deep diagnostics for a foreground-job ancestry that shrinks
                // (an intermediate ancestor like the claude CLI vanishing for a single
                // update). Gated behind the logForegroundJobAncestryDiagnostics advanced
                // setting and off by default, so there is no per-cycle cost in normal
                // use. The chain pids let a shrink name the concrete pid that held each
                // vanished ancestor; they are only captured while the setting is on.
                const BOOL logAncestryDiag = [iTermAdvancedSettingsModel logForegroundJobAncestryDiagnostics];
                NSArray<NSNumber *> *newChainPids = logAncestryDiag ? (cachedDeepestForegroundJob[key].foregroundJobAncestorChainPids ?: @[]) : @[];
                NSArray<NSNumber *> *oldChainPids = logAncestryDiag ? (self->_lastChainPidsByPidLQ[key] ?: @[]) : @[];
                if (![newAncestors isEqualToArray:oldAncestors]) {
                    if (logAncestryDiag) {
                        // When a name present last cycle vanishes this cycle we may be
                        // about to fire a bogus job-ended / claudeCode-workgroup teardown
                        // for a process that never exited. Dump the exact tree state that
                        // produced the short ancestry so a repro explains itself (see
                        // foregroundJobAncestryDiagnostic). Only fires on a real shrink,
                        // so it is naturally rate-limited to the anomaly.
                        NSMutableArray<NSString *> *removedNames = [oldAncestors mutableCopy];
                        [removedNames removeObjectsInArray:newAncestors];
                        if (removedNames.count > 0) {
                            iTermProcessInfo *deepest = cachedDeepestForegroundJob[key];
                            RLog(@"[ANCESTRYDIAG] tracked pid %@: ancestry shrank %@ -> %@ (removed %@); deepest fg job pid=%@",
                                 key, oldAncestors, newAncestors, removedNames,
                                 deepest ? @(deepest.processID) : @"nil");
                            // For each vanished ancestor, report what became of the pid
                            // that held it last cycle. "ABSENT from collection but
                            // aliveNow=YES" is the fingerprint of the allPids/ppid TOCTOU
                            // in newProcessCollection (a live process dropped because its
                            // ppid read failed after the pid snapshot).
                            for (NSString *removedName in removedNames) {
                                const NSUInteger idx = [oldAncestors indexOfObject:removedName];
                                if (idx == NSNotFound || idx >= oldChainPids.count) {
                                    RLog(@"[ANCESTRYDIAG]   removed \"%@\": no pid recorded for it last cycle", removedName);
                                    continue;
                                }
                                const pid_t droppedPid = oldChainPids[idx].intValue;
                                iTermProcessInfo *stillHere = [collection infoForProcessID:droppedPid];
                                const BOOL aliveNow = (kill(droppedPid, 0) == 0);
                                if (stillHere) {
                                    RLog(@"[ANCESTRYDIAG]   removed \"%@\" was pid %@: STILL in this cycle's collection (name=%@ ppid=%@ parentPtr=%@ fg=%@) aliveNow=%@ -- it left the parent chain without leaving the process table",
                                         removedName, @(droppedPid), stillHere.name ?: @"(nil)", @(stillHere.parentProcessID),
                                         stillHere.parent ? @(stillHere.parent.processID) : @"nil",
                                         @(stillHere.isForegroundJob), @(aliveNow));
                                } else {
                                    RLog(@"[ANCESTRYDIAG]   removed \"%@\" was pid %@: ABSENT from this cycle's collection; aliveNow=%@ -- if YES, we dropped a live process (allPids/ppid TOCTOU in newProcessCollection)",
                                         removedName, @(droppedPid), @(aliveNow));
                                }
                            }
                            if (deepest) {
                                RLog(@"[ANCESTRYDIAG] upward walk from deepest fg job pid=%@:\n%@",
                                     @(deepest.processID), [deepest foregroundJobAncestryDiagnostic]);
                            } else {
                                RLog(@"[ANCESTRYDIAG] no deepest fg job this cycle (whole chain gone)");
                            }
                        }
                    }
                    self->_lastAncestorsByPidLQ[key] = newAncestors;
                    ancestorChanges[key] = newAncestors;
                }
                if (logAncestryDiag) {
                    self->_lastChainPidsByPidLQ[key] = newChainPids;
                }
            }];
        });
        // Computing the ancestries above records resolved process names in the name
        // cache; drop entries for pids that are no longer alive so it stays bounded.
        [iTermProcessNameCache.shared pruneToLivePids:collection.processIDs];
        [self postForegroundJobAncestorChanges:ancestorChanges];
    }
}

// Any queue. Posts one notification per changed tracked pid on the main queue.
- (void)postForegroundJobAncestorChanges:(NSDictionary<NSNumber *, NSArray<NSString *> *> *)changes {
    if (changes.count == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [changes enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull pid, NSArray<NSString *> * _Nonnull ancestors, BOOL * _Nonnull stop) {
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermProcessCacheForegroundJobAncestorsDidChangeNotification
                                                                object:self
                                                              userInfo:@{ iTermProcessCacheForegroundJobAncestorsPidKey: pid,
                                                                          iTermProcessCacheForegroundJobAncestorsKey: ancestors }];
        }];
    });
}

#pragma mark - Notifications

// Main queue
- (void)applicationDidResignActive:(NSNotification *)notification {
    _rateLimit.minimumInterval = 5;
}

// Main queue
- (void)applicationDidBecomeActive:(NSNotification *)notification {
    RLog(@"Application did become active (process cache)");
    _rateLimit.minimumInterval = 0.5;
}

@end
