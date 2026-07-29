//
//  iTermPreciseTimer.m
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import "iTermPreciseTimer.h"

#import "DebugLogging.h"
#import "iTermHistogram.h"
#import "iTermMalloc.h"
#import "NSStringITerm.h"
#include <assert.h>
#include <stdatomic.h>
#include <os/lock.h>
#include <CoreServices/CoreServices.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <unistd.h>

#if ENABLE_PRECISE_TIMERS

// The stats/timer fields are _Atomic (see the header), so the accumulation
// functions below take NO lock: each struct has a single writer (one render
// pass) and any number of readers (the display/log path), and relaxed atomics
// make those cross-thread accesses well-defined without tearing. Integer counters
// use atomic add and are correct even under multiple writers; the double fields
// use relaxed load/store, which is exact given the single-writer invariant. This
// replaces the recursive @synchronized whose per-call id2data class-hash
// dominated the render sample in issue 12763. Only sLogs (a real object) needs a
// lock.
static NSMutableDictionary *sLogs;
static os_unfair_lock gLogsLock = OS_UNFAIR_LOCK_INIT;

// Kept only as a shared lock token for other subsystems (see the header); the
// timer functions here no longer synchronize on it.
@implementation iTermPreciseTimersLock
@end

void iTermPreciseTimerStart(iTermPreciseTimer *timer) {
    atomic_store_explicit(&timer->start, mach_absolute_time(), memory_order_relaxed);
}

NSTimeInterval iTermPreciseTimerMeasure(iTermPreciseTimer *timer) {
    const uint64_t end = mach_absolute_time();
    const uint64_t start = atomic_load_explicit(&timer->start, memory_order_relaxed);
    const uint64_t elapsed = end - start;

    static mach_timebase_info_data_t sTimebaseInfo;
    if (sTimebaseInfo.denom == 0) {
        mach_timebase_info(&sTimebaseInfo);
    }

    const double nanoseconds = elapsed * sTimebaseInfo.numer / sTimebaseInfo.denom;
    return nanoseconds / 1000000000.0;
}

NSTimeInterval iTermPreciseTimerMeasureAndAccumulate(iTermPreciseTimer *timer) {
    const NSTimeInterval measured = iTermPreciseTimerMeasure(timer);
    // Single writer, so load + add + store cannot lose an update.
    const NSTimeInterval total = atomic_load_explicit(&timer->total, memory_order_relaxed) + measured;
    atomic_store_explicit(&timer->total, total, memory_order_relaxed);
    atomic_fetch_add_explicit(&timer->eventCount, 1, memory_order_relaxed);
    return total;
}

NSTimeInterval iTermPreciseTimerAccumulate(iTermPreciseTimer *timer, NSTimeInterval value) {
    return atomic_load_explicit(&timer->total, memory_order_relaxed);
}

void iTermPreciseTimerReset(iTermPreciseTimer *timer) {
    atomic_store_explicit(&timer->total, 0.0, memory_order_relaxed);
    atomic_store_explicit(&timer->eventCount, 0, memory_order_relaxed);
}

void iTermPreciseTimerStatsInit(iTermPreciseTimerStats *stats, const char *name) {
    atomic_store_explicit(&stats->n, 0, memory_order_relaxed);
    atomic_store_explicit(&stats->totalEventCount, 0, memory_order_relaxed);
    atomic_store_explicit(&stats->mean, 0.0, memory_order_relaxed);
    atomic_store_explicit(&stats->m2, 0.0, memory_order_relaxed);
    atomic_store_explicit(&stats->min, INFINITY, memory_order_relaxed);
    atomic_store_explicit(&stats->max, -INFINITY, memory_order_relaxed);
    stats->level = 0;
    iTermPreciseTimerReset(&stats->timer);
    if (name) {
        strlcpy(stats->name, name, sizeof(stats->name));
        const int len = strlen(stats->name);
        for (int i = len - 1; i >= 0; i--) {
            if (name[i] == '<') {
                stats->level++;
                stats->name[i] = '\0';
            } else {
                break;
            }
        }
    }
}

NSInteger iTermPreciseTimerStatsGetCount(iTermPreciseTimerStats *stats) {
    return atomic_load_explicit(&stats->n, memory_order_relaxed);
}

void iTermPreciseTimerStatsStartTimer(iTermPreciseTimerStats *stats) {
    iTermPreciseTimerStart(&stats->timer);
}

double iTermPreciseTimerStatsMeasureAndRecordTimer(iTermPreciseTimerStats *stats) {
    if (atomic_load_explicit(&stats->timer.start, memory_order_relaxed)) {
        NSTimeInterval total = iTermPreciseTimerMeasureAndAccumulate(&stats->timer);
        int eventCount = atomic_load_explicit(&stats->timer.eventCount, memory_order_relaxed);
        iTermPreciseTimerStatsRecord(stats, total, eventCount);
        iTermPreciseTimerReset(&stats->timer);
        return total;
    } else {
        return 0;
    }
}

void iTermPreciseTimerStatsRecordTimer(iTermPreciseTimerStats *stats) {
    const NSTimeInterval total = atomic_load_explicit(&stats->timer.total, memory_order_relaxed);
    const int eventCount = atomic_load_explicit(&stats->timer.eventCount, memory_order_relaxed);
    iTermPreciseTimerStatsRecord(stats, total, eventCount);
    iTermPreciseTimerReset(&stats->timer);
}

void iTermPreciseTimerStatsMeasureAndAccumulate(iTermPreciseTimerStats *stats) {
    iTermPreciseTimerMeasureAndAccumulate(&stats->timer);
}

void iTermPreciseTimerStatsAccumulate(iTermPreciseTimerStats *stats, NSTimeInterval value) {
    iTermPreciseTimerAccumulate(&stats->timer, value);
}

void iTermPreciseTimerStatsRecord(iTermPreciseTimerStats *stats, NSTimeInterval value, int eventCount) {
    atomic_fetch_add_explicit(&stats->totalEventCount, eventCount, memory_order_relaxed);

    // Welford's online variance algorithm, adopted from:
    // https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Higher-order_statistics
    // The single-writer invariant lets these dependent load/store steps stay exact.
    const NSInteger n = atomic_fetch_add_explicit(&stats->n, 1, memory_order_relaxed) + 1;
    const double oldMean = atomic_load_explicit(&stats->mean, memory_order_relaxed);
    const double delta = value - oldMean;
    const double newMean = oldMean + delta / n;
    atomic_store_explicit(&stats->mean, newMean, memory_order_relaxed);
    const double newM2 = atomic_load_explicit(&stats->m2, memory_order_relaxed) + delta * (value - newMean);
    atomic_store_explicit(&stats->m2, newM2, memory_order_relaxed);
    if (value < atomic_load_explicit(&stats->min, memory_order_relaxed)) {
        atomic_store_explicit(&stats->min, value, memory_order_relaxed);
    }
    if (value > atomic_load_explicit(&stats->max, memory_order_relaxed)) {
        atomic_store_explicit(&stats->max, value, memory_order_relaxed);
    }
}

NSTimeInterval iTermPreciseTimerStatsGetMean(iTermPreciseTimerStats *stats) {
    return atomic_load_explicit(&stats->mean, memory_order_relaxed);
}

NSTimeInterval iTermPreciseTimerStatsGetStddev(iTermPreciseTimerStats *stats) {
    const NSInteger n = atomic_load_explicit(&stats->n, memory_order_relaxed);
    if (n < 2) {
        return NAN;
    } else {
        return sqrt(atomic_load_explicit(&stats->m2, memory_order_relaxed) / (n - 1));
    }
}

iTermPreciseTimerStats *iTermPreciseTimerStatsCopy(const iTermPreciseTimerStats *source) {
    iTermPreciseTimerStats *copy = iTermMalloc(sizeof(*source));
    memmove(copy, source, sizeof(*source));
    return copy;
}

void iTermPreciseTimerPeriodicLog(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  NSTimeInterval interval,
                                  BOOL logToConsole,
                                  NSArray *histograms,
                                  NSString *additional) {
    static iTermPreciseTimer gLastLog;
    if (!atomic_load_explicit(&gLastLog.start, memory_order_relaxed)) {
        iTermPreciseTimerStart(&gLastLog);
    }

    if (iTermPreciseTimerMeasure(&gLastLog) >= interval) {
        iTermPreciseTimerLog(identifier, stats, count, logToConsole, histograms, additional);
        iTermPreciseTimerStart(&gLastLog);
    }
}

NSString *iTermPreciseTimerLogString(NSString *identifier,
                                     iTermPreciseTimerStats stats[],
                                     size_t count,
                                     NSArray *histograms,
                                     BOOL reset) {
    const int millisWidth = 7;
    NSString *(^formatMillis)(double) = ^NSString *(double ms) {
        NSString *numeric = [NSString stringWithFormat:@"%0.1fms", ms];
        return [[@" " stringRepeatedTimes:millisWidth - numeric.length] stringByAppendingString:numeric];
    };
    NSMutableString *log = [[[NSString stringWithFormat:@"-- Precise Timers for %@ --\n", identifier] mutableCopy] autorelease];
    int maxlevel = 0;
    for (size_t i = 0; i < count; i++) {
        maxlevel = MAX(maxlevel, stats[i].level);
    }
    if (histograms) {
        [log appendFormat:@"%-20s%@    %@µ      N  %@p50  %@p75  %@p95 [min  distribution  max]\n",
         "Statistic",
         [@"    " stringRepeatedTimes:maxlevel],  // corresponds to dead space for indentation
         [@" " stringRepeatedTimes:millisWidth - 1],  // average
         [@" " stringRepeatedTimes:millisWidth - 3],  // p50
         [@" " stringRepeatedTimes:millisWidth - 3],  // p75
         [@" " stringRepeatedTimes:millisWidth - 3]]; // p95
        [log appendFormat:@"%@%@    %@-  -----  %@---  %@---  %@--- ------------------------\n",
         [@"-" stringRepeatedTimes:20],
         [@"----" stringRepeatedTimes:maxlevel],  // corresponds to dead space for indentation
         [@"-" stringRepeatedTimes:millisWidth - 1],  // average
         [@"-" stringRepeatedTimes:millisWidth - 3],  // p50
         [@"-" stringRepeatedTimes:millisWidth - 3],  // p75
         [@"-" stringRepeatedTimes:millisWidth - 3]]; // p95
    }
    for (size_t i = 0; i < count; i++) {
        if (histograms && [histograms[i] count] == 0) {
            continue;
        }
        NSTimeInterval mean = iTermPreciseTimerStatsGetMean(&stats[i]) * 1000.0;
        if (histograms) {
            double p75 = [histograms[i] valueAtNTile:0.75];
            [log appendFormat:@"%@%@ %-20s%@ %@  %5d  %@  %@  %@ [%@]\n",
             [@"|   " stringRepeatedTimes:stats[i].level],
             iTermEmojiForDuration(p75),
             stats[i].name,
             [@"    " stringRepeatedTimes:maxlevel - stats[i].level],
             formatMillis(mean),
             (int)[histograms[i] count],
             formatMillis([histograms[i] valueAtNTile:0.5]),
             formatMillis(p75),
             formatMillis([histograms[i] valueAtNTile:0.95]),
             [histograms[i] sparklineGraphWithPrecision:2 multiplier:1 units:@"ms"]];
        } else {
            NSTimeInterval stddev = iTermPreciseTimerStatsGetStddev(&stats[i]) * 1000.0;
            const NSInteger n = iTermPreciseTimerStatsGetCount(&stats[i]);
            const NSInteger totalEventCount = atomic_load_explicit(&stats[i].totalEventCount, memory_order_relaxed);
            [log appendFormat:@"%@ %20s: µ=%0.3fms σ=%.03fms (95%% CI ≅ %0.3fms–%0.3fms) 𝚺=%.2fms N=%@ avg. events=%01.f\n",
             iTermEmojiForDuration(mean),
             stats[i].name,
             mean,
             stddev,
             MAX(0, mean - stddev),
             mean + stddev,
             n * mean,
             @(n),
             (double)totalEventCount / (double)n];
        }

        if (reset) {
            iTermPreciseTimerStatsInit(&stats[i], NULL);
        }
    }
    return log;
}

void iTermPreciseTimerLog(NSString *identifier,
                          iTermPreciseTimerStats stats[],
                          size_t count,
                          BOOL logToConsole,
                          NSArray *histograms,
                          NSString *additional) {
    NSString *log = iTermPreciseTimerLogString(identifier, stats, count, histograms, YES);
    if (additional) {
        log = [log stringByAppendingFormat:@"\n%@", additional];
    }
    if (logToConsole) {
        NSLog(@"%@", log);
    }
    iTermPreciseTimerSaveLog(identifier, log);
    DLog(@"%@", log);
}

void iTermPreciseTimerLogOneEvent(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  BOOL logToConsole,
                                  NSArray *histograms) {
    NSMutableString *log = [[@"-- Precise Timers (One Event) --\n" mutableCopy] autorelease];
    for (size_t i = 0; i < count; i++) {
        const NSInteger n = iTermPreciseTimerStatsGetCount(&stats[i]);
        if (n == 0) {
            continue;
        }
        const char *cname = stats[i].name;
        int length = strlen(cname);
        NSMutableString *name = [NSMutableString string];
        while (length > 1 && cname[length - 1] == '<') {
            length--;
            [name appendString:@"    "];
        }
        NSTimeInterval ms = n * iTermPreciseTimerStatsGetMean(&stats[i]) * 1000.0;
        NSString *emoji = iTermEmojiForDuration(ms);
        [name appendString:[[[NSString alloc] initWithBytes:cname length:length encoding:NSUTF8StringEncoding] autorelease]];
        NSString *other = @"";
        if (n > 1) {
            double mean = iTermPreciseTimerStatsGetMean(&stats[i]);
            if (histograms) {
                other = [NSString stringWithFormat:@"N=%@ µ=%0.1fms p50=%@ p95=%@ | %@",
                         @(n), mean * 1000, @([histograms[i] valueAtNTile:0.5]),
                         @([histograms[i] valueAtNTile:0.95]), [histograms[i] sparklines]];
            } else {
                const double mn = atomic_load_explicit(&stats[i].min, memory_order_relaxed);
                const double mx = atomic_load_explicit(&stats[i].max, memory_order_relaxed);
                other = [NSString stringWithFormat:@"N=%@ µ=%0.1fms [%0.1fms…%0.1fms]", @(n), mean * 1000, mn * 1000, mx * 1000];
            }
        }
        [log appendFormat:@"%@ %0.1fms %@ %@\n", emoji, ms, name, other];
    }
    if (logToConsole) {
        NSLog(@"%@", log);
    }
    iTermPreciseTimerSaveLog(identifier, log);

    DLog(@"%@", log);
}

void iTermPreciseTimerSaveLog(NSString *identifier, NSString *log) {
    os_unfair_lock_lock(&gLogsLock);
    if (!sLogs) {
        sLogs = [[NSMutableDictionary alloc] init];
    }
    sLogs[identifier] = log;
    os_unfair_lock_unlock(&gLogsLock);
}

NSString *iTermPreciseTimerGetSavedLogs(void) {
    os_unfair_lock_lock(&gLogsLock);
    NSMutableString *result = [NSMutableString string];
    [sLogs enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        NSInteger numLines = [[obj componentsSeparatedByString:@"\n"] count];
        [result appendFormat:@"Precise timers %@:%@%@\n", key, numLines > 1 ? @"\n" : @"", obj];
    }];
    os_unfair_lock_unlock(&gLogsLock);
    return result;
}

void iTermPreciseTimerClearLogs(void) {
    os_unfair_lock_lock(&gLogsLock);
    [sLogs removeAllObjects];
    os_unfair_lock_unlock(&gLogsLock);
}

#endif

NSString *iTermEmojiForDuration(double ms) {
    if (ms > 100) {
        return @"😱";
    } else if (ms > 10) {
        return @"😳";
    } else if (ms > 5) {
        return @"😢";
    } else if (ms > 1) {
        return @"🙁";
    } else if (ms > 0.5) {
        return @"🤔";
    } else {
        return @"  ";
    }
}
