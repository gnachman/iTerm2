//
//  iTermTimerCensus.m
//  iTerm2
//
//  See iTermTimerCensus.h for what this is and why it exists.
//

#import "iTermTimerCensus.h"

#import "DebugLogging.h"

#import <execinfo.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>
#import <os/lock.h>

// Tunables. These are deliberately conservative: the census only runs in a
// diagnostic build with the flag on, so the cost is acceptable, but we still
// bound backtrace capture so a runaway scheduler can't make us allocate without
// limit.
static const NSUInteger kMaxBacktracesPerKey = 8;   // distinct call sites we keep per key
static const NSUInteger kMaxBacktraceFrames = 24;   // frames captured per backtrace
static const NSTimeInterval kWatchdogInterval = 3.0;  // seconds between ticks
static const double kScanCostReportThresholdMS = 25.0;  // full dump when a probe scan is this slow
static const NSUInteger kTopN = 8;  // schedulers listed each tick

// A perform request scheduled while a huge number are already outstanding is the
// bug; make the sentinel delay effectively infinite so our probe never fires.
static const NSTimeInterval kProbeDelay = 1e9;

#pragma mark - Per-key accumulator

@interface iTermTimerCensusEntry : NSObject
@property (nonatomic) uint64_t scheduled;      // cumulative
@property (nonatomic) uint64_t canceled;       // cumulative (selector-specific cancels only)
@property (nonatomic) uint64_t sinceLastDump;  // schedules since the previous tick, for rate
// Raw return addresses of a handful of scheduling call sites. Symbolicated
// lazily at report time so the hot path stays cheap.
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *backtraces;
@end

@implementation iTermTimerCensusEntry
- (instancetype)init {
    self = [super init];
    if (self) {
        _backtraces = [NSMutableArray array];
    }
    return self;
}
@end

#pragma mark - File-scope state

// Original implementations, captured at install time.
static void (*sOrigPerformAfterDelay)(id, SEL, SEL, id, NSTimeInterval);
static void (*sOrigPerformAfterDelayInModes)(id, SEL, SEL, id, NSTimeInterval, NSArray *);
static void (*sOrigCancelSelObj)(Class, SEL, id, SEL, id);
static void (*sOrigCancelTarget)(Class, SEL, id);
static void (*sOrigAddTimer)(id, SEL, NSTimer *, NSRunLoopMode);

static os_unfair_lock sLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, iTermTimerCensusEntry *> *sByKey;
static uint64_t sTotalScheduled;   // cumulative delayed-performs recorded
static uint64_t sTotalTimers;      // cumulative NSRunLoop timers recorded
static uint64_t sTotalCanceled;    // cumulative cancels (both variants)
static mach_timebase_info_data_t sTimebase;

// A private target for the scan-cost probe, excluded from the census so the
// probe never counts itself.
@interface iTermTimerCensusProbe : NSObject
- (void)iterm_censusNoop;
@end
@implementation iTermTimerCensusProbe
- (void)iterm_censusNoop {}
@end
static iTermTimerCensusProbe *sProbe;

// Coalesce nested scheduling so one public call is counted once, even though
// Foundation may implement performSelector:afterDelay: on top of the inModes:
// variant and/or NSRunLoop timers internally.
static __thread int sScheduleRecursion;
static __thread int sCancelRecursion;

static dispatch_source_t sWatchdog;

#pragma mark - Helpers

static double MachToMS(uint64_t elapsed) {
    return (double)elapsed * (double)sTimebase.numer / (double)sTimebase.denom / 1e6;
}

static NSString *KeyForTarget(id target, SEL selector, BOOL isTimer) {
    const char *clsName = target ? class_getName(object_getClass(target)) : "nil";
    const char *where = [NSThread isMainThread] ? "main" : "bg";
    if (isTimer) {
        return [NSString stringWithFormat:@"[%s] NSTimer<-%s", where, clsName];
    }
    return [NSString stringWithFormat:@"[%s] %s %s", where, clsName, sel_getName(selector)];
}

// Must be called with sLock held.
static void MaybeCaptureBacktrace(iTermTimerCensusEntry *entry) {
    if (entry.backtraces.count >= kMaxBacktracesPerKey) {
        return;
    }
    void *frames[kMaxBacktraceFrames];
    const int n = backtrace(frames, (int)kMaxBacktraceFrames);
    NSMutableArray<NSNumber *> *addrs = [NSMutableArray arrayWithCapacity:n];
    for (int i = 0; i < n; i++) {
        [addrs addObject:@((uintptr_t)frames[i])];
    }
    [entry.backtraces addObject:addrs];
}

static void RecordSchedule(id target, SEL selector, BOOL isTimer) {
    NSString *key = KeyForTarget(target, selector, isTimer);
    os_unfair_lock_lock(&sLock);
    if (isTimer) {
        sTotalTimers++;
    } else {
        sTotalScheduled++;
    }
    iTermTimerCensusEntry *entry = sByKey[key];
    if (!entry) {
        entry = [[iTermTimerCensusEntry alloc] init];
        sByKey[key] = entry;
    }
    entry.scheduled++;
    entry.sinceLastDump++;
    MaybeCaptureBacktrace(entry);
    os_unfair_lock_unlock(&sLock);
}

static void RecordCancel(id target, SEL selector) {
    // A selector-specific cancel; attribute it so net population reads sensibly.
    NSString *key = KeyForTarget(target, selector, NO);
    os_unfair_lock_lock(&sLock);
    sTotalCanceled++;
    iTermTimerCensusEntry *entry = sByKey[key];
    if (entry) {
        entry.canceled++;
    }
    os_unfair_lock_unlock(&sLock);
}

#pragma mark - Swizzled implementations

static void census_performAfterDelay(id self, SEL _cmd, SEL aSelector, id anArgument, NSTimeInterval delay) {
    const BOOL record = (self != sProbe) && (sScheduleRecursion == 0);
    if (record) {
        RecordSchedule(self, aSelector, NO);
    }
    sScheduleRecursion++;
    sOrigPerformAfterDelay(self, _cmd, aSelector, anArgument, delay);
    sScheduleRecursion--;
}

static void census_performAfterDelayInModes(id self, SEL _cmd, SEL aSelector, id anArgument, NSTimeInterval delay, NSArray *modes) {
    const BOOL record = (self != sProbe) && (sScheduleRecursion == 0);
    if (record) {
        RecordSchedule(self, aSelector, NO);
    }
    sScheduleRecursion++;
    sOrigPerformAfterDelayInModes(self, _cmd, aSelector, anArgument, delay, modes);
    sScheduleRecursion--;
}

static void census_addTimer(id self, SEL _cmd, NSTimer *timer, NSRunLoopMode mode) {
    const BOOL record = (sScheduleRecursion == 0);
    if (record) {
        // NSTimer doesn't expose its target/selector publicly; attribute by
        // call site (captured backtrace) instead.
        RecordSchedule(nil, NULL, YES);
    }
    sScheduleRecursion++;
    sOrigAddTimer(self, _cmd, timer, mode);
    sScheduleRecursion--;
}

static void census_cancelSelObj(Class self, SEL _cmd, id target, SEL selector, id anArgument) {
    const BOOL record = (target != sProbe) && (sCancelRecursion == 0);
    if (record) {
        RecordCancel(target, selector);
    }
    sCancelRecursion++;
    sOrigCancelSelObj(self, _cmd, target, selector, anArgument);
    sCancelRecursion--;
}

static void census_cancelTarget(Class self, SEL _cmd, id target) {
    const BOOL record = (target != sProbe) && (sCancelRecursion == 0);
    if (record) {
        os_unfair_lock_lock(&sLock);
        sTotalCanceled++;
        os_unfair_lock_unlock(&sLock);
    }
    sCancelRecursion++;
    sOrigCancelTarget(self, _cmd, target);
    sCancelRecursion--;
}

#pragma mark - Scan-cost probe

// Returns the time, in milliseconds, to scan+cancel one sentinel delayed-perform
// on the main run loop. That cost is proportional to the total timer/perform
// population, so it's a direct proxy for how bad the beachball would be right
// now. Runs on the main thread only.
static double ProbeScanCostMS(void) {
    SEL noop = @selector(iterm_censusNoop);
    [sProbe performSelector:noop withObject:nil afterDelay:kProbeDelay];
    const uint64_t t0 = mach_absolute_time();
    [iTermTimerCensusProbe cancelPreviousPerformRequestsWithTarget:sProbe selector:noop object:nil];
    const uint64_t t1 = mach_absolute_time();
    return MachToMS(t1 - t0);
}

#pragma mark - Reporting

static NSString *SymbolicateBacktrace(NSArray<NSNumber *> *frames) {
    const NSUInteger n = frames.count;
    if (n == 0) {
        return @"(no backtrace)";
    }
    void **addrs = malloc(sizeof(void *) * n);
    for (NSUInteger i = 0; i < n; i++) {
        addrs[i] = (void *)(uintptr_t)frames[i].unsignedLongLongValue;
    }
    char **symbols = backtrace_symbols(addrs, (int)n);
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    // Skip our own frames (MaybeCaptureBacktrace, RecordSchedule, and the
    // swizzled trampoline); frame 3 onward is the real scheduler. Cap the depth
    // so the log stays legible.
    const NSUInteger firstInteresting = MIN((NSUInteger)3, n);
    const NSUInteger last = MIN(n, firstInteresting + 14);
    for (NSUInteger i = firstInteresting; i < last; i++) {
        [lines addObject:[NSString stringWithFormat:@"      %s", symbols[i]]];
    }
    free(symbols);
    free(addrs);
    return [lines componentsJoinedByString:@"\n"];
}

@implementation iTermTimerCensus

+ (void)logReportNow {
    NSArray<NSString *> *keys;
    NSMutableDictionary<NSString *, iTermTimerCensusEntry *> *snapshot;
    uint64_t totalScheduled;
    uint64_t totalTimers;
    uint64_t totalCanceled;

    os_unfair_lock_lock(&sLock);
    snapshot = [sByKey mutableCopy];
    totalScheduled = sTotalScheduled;
    totalTimers = sTotalTimers;
    totalCanceled = sTotalCanceled;
    keys = [snapshot keysSortedByValueUsingComparator:^NSComparisonResult(iTermTimerCensusEntry *a, iTermTimerCensusEntry *b) {
        // Sort by net outstanding (scheduled - canceled), descending.
        const int64_t na = (int64_t)a.scheduled - (int64_t)a.canceled;
        const int64_t nb = (int64_t)b.scheduled - (int64_t)b.canceled;
        return [@(nb) compare:@(na)];
    }];
    os_unfair_lock_unlock(&sLock);

    // RLog, not DLog: this must land in the always-on retrospective ring so an
    // intermittent hang can be diagnosed from a debug log pulled after the fact,
    // without the user having had Capture Debug Log running beforehand.
    RLog(@"=== iTermTimerCensus report ===");
    RLog(@"cumulative delayed-performs=%llu timers=%llu cancels=%llu distinctKeys=%lu",
         totalScheduled, totalTimers, totalCanceled, (unsigned long)snapshot.count);
    const NSUInteger n = MIN((NSUInteger)kTopN, keys.count);
    for (NSUInteger i = 0; i < n; i++) {
        NSString *key = keys[i];
        iTermTimerCensusEntry *entry = snapshot[key];
        const int64_t net = (int64_t)entry.scheduled - (int64_t)entry.canceled;
        RLog(@"  #%lu net=%lld scheduled=%llu canceled=%llu  %@",
             (unsigned long)(i + 1), net, entry.scheduled, entry.canceled, key);
        for (NSArray<NSNumber *> *bt in entry.backtraces) {
            RLog(@"    call site:\n%@", SymbolicateBacktrace(bt));
        }
    }
    RLog(@"=== end iTermTimerCensus report ===");
}

+ (void)tick {
    // Runs on the main thread via the watchdog dispatch source.
    const double scanMS = ProbeScanCostMS();

    // Per-key rate since the last tick, plus a reset.
    NSArray<NSString *> *byRate;
    NSMutableDictionary<NSString *, NSNumber *> *rates = [NSMutableDictionary dictionary];
    os_unfair_lock_lock(&sLock);
    for (NSString *key in sByKey) {
        iTermTimerCensusEntry *entry = sByKey[key];
        rates[key] = @(entry.sinceLastDump);
        entry.sinceLastDump = 0;
    }
    const uint64_t totalScheduled = sTotalScheduled;
    const uint64_t totalTimers = sTotalTimers;
    os_unfair_lock_unlock(&sLock);
    byRate = [rates keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [b compare:a];
    }];

    NSMutableString *top = [NSMutableString string];
    const NSUInteger n = MIN((NSUInteger)kTopN, byRate.count);
    for (NSUInteger i = 0; i < n; i++) {
        NSString *key = byRate[i];
        const double perSec = rates[key].doubleValue / kWatchdogInterval;
        if (rates[key].doubleValue == 0) {
            break;
        }
        [top appendFormat:@"\n    %6.1f/s  %@", perSec, key];
    }

    RLog(@"iTermTimerCensus tick: scanCost=%.1fms cumulativePerforms=%llu cumulativeTimers=%llu top-by-rate:%@",
         scanMS, totalScheduled, totalTimers, top.length ? top : @" (idle)");

    if (scanMS >= kScanCostReportThresholdMS) {
        RLog(@"iTermTimerCensus: scan cost %.1fms crossed threshold; dumping full report", scanMS);
        [self logReportNow];
    }
}

#pragma mark - Install

static void Swizzle(Class cls, SEL selector, IMP replacement, BOOL isClassMethod, void *origStore) {
    Method method = isClassMethod ? class_getClassMethod(cls, selector)
                                  : class_getInstanceMethod(cls, selector);
    if (!method) {
        NSLog(@"iTermTimerCensus: could not find %@%@ to swizzle",
              isClassMethod ? @"+" : @"-", NSStringFromSelector(selector));
        return;
    }
    IMP original = method_setImplementation(method, replacement);
    *(IMP *)origStore = original;
}

+ (void)install {
    // This build exists solely to collect this diagnostic, so there is no gate:
    // the census always installs. dispatch_once keeps it idempotent.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self reallyInstall];
    });
}

+ (void)reallyInstall {
    mach_timebase_info(&sTimebase);
    sByKey = [NSMutableDictionary dictionary];
    sProbe = [[iTermTimerCensusProbe alloc] init];

    Swizzle([NSObject class], @selector(performSelector:withObject:afterDelay:),
            (IMP)census_performAfterDelay, NO, &sOrigPerformAfterDelay);
    Swizzle([NSObject class], @selector(performSelector:withObject:afterDelay:inModes:),
            (IMP)census_performAfterDelayInModes, NO, &sOrigPerformAfterDelayInModes);
    Swizzle([NSObject class], @selector(cancelPreviousPerformRequestsWithTarget:selector:object:),
            (IMP)census_cancelSelObj, YES, &sOrigCancelSelObj);
    Swizzle([NSObject class], @selector(cancelPreviousPerformRequestsWithTarget:),
            (IMP)census_cancelTarget, YES, &sOrigCancelTarget);
    Swizzle([NSRunLoop class], @selector(addTimer:forMode:),
            (IMP)census_addTimer, NO, &sOrigAddTimer);

    // Watchdog on the main queue so the scan-cost probe measures the main run
    // loop, which is where the pathological population lives.
    sWatchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    const uint64_t interval = (uint64_t)(kWatchdogInterval * NSEC_PER_SEC);
    dispatch_source_set_timer(sWatchdog,
                              dispatch_time(DISPATCH_TIME_NOW, interval),
                              interval,
                              (uint64_t)(0.5 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(sWatchdog, ^{
        [iTermTimerCensus tick];
    });
    dispatch_resume(sWatchdog);

    // Loud on purpose: this build has instrumentation that adds overhead, and
    // whoever is looking at a debug log should know it was active.
    NSLog(@"iTermTimerCensus: INSTALLED. Delayed-perform and NSTimer scheduling is now being censused. "
          @"Reproduce the hang, then create a debug log (the report is written to the always-on "
          @"retrospective ring; Capture Debug Log is not required).");
    // RLog so the banner is visible in a retrospective debug log too.
    RLog(@"iTermTimerCensus installed.");
}

@end
