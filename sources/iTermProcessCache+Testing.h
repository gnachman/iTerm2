//
//  iTermProcessCache+Testing.h
//  iTerm2SharedARC
//
//  Testing-only interface for iTermProcessCache.
//

#import "iTermProcessCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermProcessCache (Testing)

/// Create a non-singleton instance for testing.
- (instancetype)initForTesting;

/// Number of roots in the dirty low-priority (background) set.
@property (nonatomic, readonly) NSUInteger dirtyLowRootsCount;

/// Number of roots in the dirty high-priority (foreground) set.
@property (nonatomic, readonly) NSUInteger dirtyHighRootsCount;

/// Whether a specific root PID is currently marked as high priority (foreground).
- (BOOL)isRootHighPriority:(pid_t)rootPID;

/// Whether a specific root PID exists in the tracking system.
- (BOOL)isTrackingRoot:(pid_t)rootPID;

/// Force a background refresh tick (normally called by timer).
- (void)forceBackgroundRefreshTick;

/// Register a root PID for tracking (testing only).
- (void)registerTestRoot:(pid_t)rootPID;

/// Unregister a root PID (testing only).
- (void)unregisterTestRoot:(pid_t)rootPID;

@end

NS_ASSUME_NONNULL_END
