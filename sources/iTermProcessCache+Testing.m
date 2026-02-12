//
//  iTermProcessCache+Testing.m
//  iTerm2SharedARC
//
//  Testing-only implementation for iTermProcessCache.
//

#import "iTermProcessCache+Testing.h"
#import "iTermProcessMonitor.h"

// Forward declare private ivars we need to access
@interface iTermProcessCache () {
    @public
    dispatch_queue_t _lockQueue;
    dispatch_queue_t _workQueue;
    NSMutableDictionary *_rootsLQ;
    NSMutableIndexSet *_dirtyHighRootsLQ;
    NSMutableIndexSet *_dirtyLowRootsLQ;
}
- (void)backgroundRefreshTick;
@end

// Forward declare iTermTrackedRootInfo for access
@interface iTermTrackedRootInfo : NSObject
@property (nonatomic) BOOL isHighPriority;
@property (nonatomic, strong, nullable) iTermProcessMonitor *monitor;
@property (nonatomic, strong) NSMutableIndexSet *cachedDescendants;
@property (nonatomic) NSUInteger lastRefreshEpoch;
@property (nonatomic) BOOL isDirty;
@end

@implementation iTermProcessCache (Testing)

- (instancetype)initForTesting {
    return [self init];
}

- (NSUInteger)dirtyLowRootsCount {
    __block NSUInteger count = 0;
    dispatch_sync(_lockQueue, ^{
        count = self->_dirtyLowRootsLQ.count;
    });
    return count;
}

- (NSUInteger)dirtyHighRootsCount {
    __block NSUInteger count = 0;
    dispatch_sync(_lockQueue, ^{
        count = self->_dirtyHighRootsLQ.count;
    });
    return count;
}

- (BOOL)isRootHighPriority:(pid_t)rootPID {
    __block BOOL result = NO;
    dispatch_sync(_lockQueue, ^{
        iTermTrackedRootInfo *info = self->_rootsLQ[@(rootPID)];
        result = info.isHighPriority;
    });
    return result;
}

- (BOOL)isTrackingRoot:(pid_t)rootPID {
    __block BOOL result = NO;
    dispatch_sync(_lockQueue, ^{
        result = self->_rootsLQ[@(rootPID)] != nil;
    });
    return result;
}

- (void)forceBackgroundRefreshTick {
    [self backgroundRefreshTick];
}

- (void)registerTestRoot:(pid_t)rootPID {
    dispatch_sync(_lockQueue, ^{
        if (self->_rootsLQ[@(rootPID)] == nil) {
            iTermTrackedRootInfo *info = [[iTermTrackedRootInfo alloc] init];
            info.isHighPriority = YES;  // Default to foreground
            self->_rootsLQ[@(rootPID)] = info;
        }
    });
}

- (void)unregisterTestRoot:(pid_t)rootPID {
    dispatch_sync(_lockQueue, ^{
        iTermTrackedRootInfo *info = self->_rootsLQ[@(rootPID)];
        if (info) {
            [info.monitor invalidate];
            [self->_rootsLQ removeObjectForKey:@(rootPID)];
            [self->_dirtyHighRootsLQ removeIndex:rootPID];
            [self->_dirtyLowRootsLQ removeIndex:rootPID];
        }
    });
}

@end
