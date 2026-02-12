//
//  iTermProcessCacheTestHelper.m
//  iTerm2SharedARC
//
//  A Swift-compatible wrapper to expose iTermProcessCache testing methods.
//

#import "iTermProcessCacheTestHelper.h"
#import "iTermProcessCache.h"
#import "iTermProcessCache+Testing.h"
#import "iTermProcessMonitor.h"
#import "iTermProcessMonitor+Testing.h"

// Forward declare iTermTrackedRootInfo for access
@interface iTermTrackedRootInfo : NSObject
@property (nonatomic) BOOL isHighPriority;
@property (nonatomic, strong, nullable) iTermProcessMonitor *monitor;
@end

// Forward declare private ivars we need to access
@interface iTermProcessCache () {
    @public
    dispatch_queue_t _lockQueue;
    NSMutableDictionary *_rootsLQ;
}
@end

@implementation iTermProcessCacheTestHelper

+ (id)createTestCache {
    return [[iTermProcessCache alloc] initForTesting];
}

+ (NSUInteger)dirtyLowRootsCountForCache:(id)cache {
    return [(iTermProcessCache *)cache dirtyLowRootsCount];
}

+ (NSUInteger)dirtyHighRootsCountForCache:(id)cache {
    return [(iTermProcessCache *)cache dirtyHighRootsCount];
}

+ (BOOL)cache:(id)cache isRootHighPriority:(pid_t)rootPID {
    return [(iTermProcessCache *)cache isRootHighPriority:rootPID];
}

+ (BOOL)cache:(id)cache isTrackingRoot:(pid_t)rootPID {
    return [(iTermProcessCache *)cache isTrackingRoot:rootPID];
}

+ (void)forceBackgroundRefreshTickForCache:(id)cache {
    [(iTermProcessCache *)cache forceBackgroundRefreshTick];
}

+ (void)cache:(id)cache registerTestRoot:(pid_t)rootPID {
    [(iTermProcessCache *)cache registerTestRoot:rootPID];
}

+ (void)cache:(id)cache unregisterTestRoot:(pid_t)rootPID {
    [(iTermProcessCache *)cache unregisterTestRoot:rootPID];
}

+ (void)cache:(id)cache setForegroundRootPIDs:(NSSet<NSNumber *> *)foregroundPIDs {
    [(iTermProcessCache *)cache setForegroundRootPIDs:foregroundPIDs];
}

+ (nullable id)cache:(id)cache monitorForRoot:(pid_t)rootPID {
    iTermProcessCache *c = (iTermProcessCache *)cache;
    __block iTermProcessMonitor *monitor = nil;
    dispatch_sync(c->_lockQueue, ^{
        iTermTrackedRootInfo *info = c->_rootsLQ[@(rootPID)];
        monitor = info.monitor;
    });
    return monitor;
}

+ (BOOL)monitorIsPaused:(id)monitor {
    return [(iTermProcessMonitor *)monitor isPaused];
}

+ (NSArray *)childMonitorsForMonitor:(id)monitor {
    return [(iTermProcessMonitor *)monitor childMonitors];
}

@end
