//
//  iTermProcessCacheTestHelper.h
//  iTerm2SharedARC
//
//  A Swift-compatible wrapper to expose iTermProcessCache testing methods.
//  This avoids the circular header dependency between iTermProcessCache.h and Swift.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Helper class to access iTermProcessCache testing methods from Swift.
/// This wrapper avoids the circular dependency caused by importing iTermProcessCache.h
/// directly into the Swift bridging header.
@interface iTermProcessCacheTestHelper : NSObject

/// Create a new iTermProcessCache instance for testing (not the singleton).
+ (id)createTestCache;

/// Number of roots in the dirty low-priority (background) set.
+ (NSUInteger)dirtyLowRootsCountForCache:(id)cache;

/// Number of roots in the dirty high-priority (foreground) set.
+ (NSUInteger)dirtyHighRootsCountForCache:(id)cache;

/// Whether a specific root PID is currently marked as high priority (foreground).
+ (BOOL)cache:(id)cache isRootHighPriority:(pid_t)rootPID;

/// Whether a specific root PID exists in the tracking system.
+ (BOOL)cache:(id)cache isTrackingRoot:(pid_t)rootPID;

/// Force a background refresh tick (normally called by timer).
+ (void)forceBackgroundRefreshTickForCache:(id)cache;

/// Register a root PID for tracking (testing only).
+ (void)cache:(id)cache registerTestRoot:(pid_t)rootPID;

/// Unregister a root PID (testing only).
+ (void)cache:(id)cache unregisterTestRoot:(pid_t)rootPID;

/// Set foreground root PIDs.
+ (void)cache:(id)cache setForegroundRootPIDs:(NSSet<NSNumber *> *)foregroundPIDs;

/// Get the monitor for a root PID (returns id to avoid header dependency).
+ (nullable id)cache:(id)cache monitorForRoot:(pid_t)rootPID;

/// Check if a monitor is paused.
+ (BOOL)monitorIsPaused:(id)monitor;

/// Get child monitors from a monitor.
+ (NSArray *)childMonitorsForMonitor:(id)monitor;

@end

NS_ASSUME_NONNULL_END
