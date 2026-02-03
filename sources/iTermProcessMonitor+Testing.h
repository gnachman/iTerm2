//
//  iTermProcessMonitor+Testing.h
//  iTerm2SharedARC
//
//  Testing-only interface for iTermProcessMonitor.
//

#import "iTermProcessMonitor.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermProcessMonitor (Testing)

/// Returns YES if the monitor's dispatch source is currently suspended.
@property (nonatomic, readonly) BOOL isPaused;

/// Returns the child monitors (for testing child pause state).
@property (nonatomic, readonly) NSArray<iTermProcessMonitor *> *childMonitors;

@end

NS_ASSUME_NONNULL_END
