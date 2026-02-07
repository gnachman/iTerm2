//
//  iTermProcessMonitor.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/21/19.
//

#import <Foundation/Foundation.h>

@class iTermProcessInfo;
@class iTermProcessMonitor;

NS_ASSUME_NONNULL_BEGIN

// Watches a process and its children for fork, exec, signals, and terminate.
@interface iTermProcessMonitor : NSObject

@property (nullable, nonatomic, readonly) iTermProcessInfo *processInfo;
@property (nonatomic, readonly) void (^callback)(iTermProcessMonitor *, dispatch_source_proc_flags_t);
@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nullable, nonatomic, weak, readonly) iTermProcessMonitor *parent;

// The root PID that this monitor (or its ancestor) was created to track.
// Set at creation time and propagated to children for O(1) lookup in callbacks.
@property (nonatomic, readonly) pid_t trackedRootPID;

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                     callback:(void (^)(iTermProcessMonitor *, dispatch_source_proc_flags_t))callback
               trackedRootPID:(pid_t)trackedRootPID NS_DESIGNATED_INITIALIZER;

// Legacy initializer - creates a monitor without trackedRootPID (defaults to 0)
- (instancetype)initWithQueue:(dispatch_queue_t)queue
                     callback:(void (^)(iTermProcessMonitor *, dispatch_source_proc_flags_t))callback;

- (instancetype)init NS_UNAVAILABLE;

// Stops monitoring permanently.
- (void)invalidate;

// Temporarily pauses monitoring (dispatch source suspended). Call resumeMonitoring to resume.
- (void)pauseMonitoring;

// Resumes monitoring after pauseMonitoring was called.
- (void)resumeMonitoring;

- (void)addChild:(iTermProcessMonitor *)child;

// Returns whether this or any child changed. Begins monitoring if nonnil.
- (BOOL)setProcessInfo:(nullable iTermProcessInfo *)processInfo;

@end

NS_ASSUME_NONNULL_END
