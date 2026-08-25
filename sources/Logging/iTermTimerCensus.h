//
//  iTermTimerCensus.h
//  iTerm2
//
//  Diagnostic instrumentation for issue 1765: a main-thread beachball whose
//  sample shows 100% of the time spent inside
//  +[NSObject cancelPreviousPerformRequestsWithTarget:selector:object:], i.e. a
//  linear scan of the main run loop's timer/delayed-perform population. That
//  scan is only slow when that population has grown huge, so this census watches
//  the two things that grow it (NSObject delayed-performs and NSRunLoop timers),
//  tracks who schedules them and how fast, and periodically probes the actual
//  scan cost.
//
//  This is a purpose-built diagnostic build: the census always installs, with no
//  gate. The report is written via RLog, so it lands in the always-on
//  retrospective ring: the user just reproduces the hang and then creates a
//  debug log (Menu > ... > Create Debug Log, or the usual flow). Capture Debug
//  Log does NOT need to be running beforehand, which is what makes this usable
//  for an intermittent hang you can't predict.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermTimerCensus : NSObject

// Installs the instrumentation exactly once. Idempotent. Call early during launch.
+ (void)install;

// Immediately writes a full report (top schedulers, net population estimate,
// current scan cost, and sampled call-site backtraces) via RLog. Used by the
// internal watchdog; also callable by hand from a debugger.
+ (void)logReportNow;

@end

NS_ASSUME_NONNULL_END
