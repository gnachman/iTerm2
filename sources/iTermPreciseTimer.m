//
//  iTermPreciseTimer.m
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import "iTermPreciseTimer.h"

#import "DebugLogging.h"
#include <assert.h>
#include <CoreServices/CoreServices.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <unistd.h>

#if ENABLE_PRECISE_TIMERS
static BOOL gPreciseTimersEnabled;
static NSMutableDictionary *sLogs;

@interface iTermPreciseTimersLock : NSObject
@end

@implementation iTermPreciseTimersLock
@end

void iTermPreciseTimerSetEnabled(BOOL enabled) {
    gPreciseTimersEnabled = enabled;
}

void iTermPreciseTimerStart(iTermPreciseTimer *timer) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    timer->start = mach_absolute_time();
}

NSTimeInterval iTermPreciseTimerMeasureAndAccumulate(iTermPreciseTimer *timer) {
    if (!gPreciseTimersEnabled) {
        return 0;
    }
    timer->total += iTermPreciseTimerMeasure(timer);
    timer->eventCount += 1;
    return timer->total;
}

NSTimeInterval iTermPreciseTimerAccumulate(iTermPreciseTimer *timer, NSTimeInterval value) {
    if (!gPreciseTimersEnabled) {
        return 0;
    }
    return timer->total;
}

void iTermPreciseTimerReset(iTermPreciseTimer *timer) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    timer->total = 0;
    timer->eventCount = 0;
}

NSTimeInterval iTermPreciseTimerMeasure(iTermPreciseTimer *timer) {
    if (!gPreciseTimersEnabled) {
        return 0;
    }
    uint64_t end;
    NSTimeInterval elapsed;

    end = mach_absolute_time();
    elapsed = end - timer->start;

    static mach_timebase_info_data_t sTimebaseInfo;
    if (sTimebaseInfo.denom == 0) {
        mach_timebase_info(&sTimebaseInfo);
    }

    double nanoseconds = elapsed * sTimebaseInfo.numer / sTimebaseInfo.denom;
    return nanoseconds / 1000000000.0;
}

void iTermPreciseTimerStatsInit(iTermPreciseTimerStats *stats, const char *name) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    stats->n = 0;
    stats->totalEventCount = 0;
    stats->mean = 0;
    stats->m2 = 0;
    stats->min = INFINITY;
    stats->max = -INFINITY;
    iTermPreciseTimerReset(&stats->timer);
    if (name) {
        strlcpy(stats->name, name, sizeof(stats->name));
    }
}

NSInteger iTermPreciseTimerStatsGetCount(iTermPreciseTimerStats *stats) {
    if (!gPreciseTimersEnabled) {
        return 0;
    }
    return stats->n;
}

void iTermPreciseTimerStatsStartTimer(iTermPreciseTimerStats *stats) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    iTermPreciseTimerStart(&stats->timer);
}

void iTermPreciseTimerStatsMeasureAndRecordTimer(iTermPreciseTimerStats *stats) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    if (stats->timer.start) {
        NSTimeInterval total = iTermPreciseTimerMeasureAndAccumulate(&stats->timer);
        int eventCount = stats->timer.eventCount;
        iTermPreciseTimerStatsRecord(stats, total, eventCount);
        iTermPreciseTimerReset(&stats->timer);
    }
}

void iTermPreciseTimerStatsRecordTimer(iTermPreciseTimerStats *stats) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    iTermPreciseTimerStatsRecord(stats, stats->timer.total, stats->timer.eventCount);
    iTermPreciseTimerReset(&stats->timer);
}

void iTermPreciseTimerStatsMeasureAndAccumulate(iTermPreciseTimerStats *stats) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    iTermPreciseTimerMeasureAndAccumulate(&stats->timer);
}

void iTermPreciseTimerStatsAccumulate(iTermPreciseTimerStats *stats, NSTimeInterval value) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    iTermPreciseTimerAccumulate(&stats->timer, value);
}

void iTermPreciseTimerStatsRecord(iTermPreciseTimerStats *stats, NSTimeInterval value, int eventCount) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    stats->totalEventCount += eventCount;

    // Welford's online variance algorithm, adopted from:
    // https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Higher-order_statistics
    stats->n += 1;
    double delta = value - stats->mean;
    stats->mean += delta / stats->n;
    stats->m2 += delta * (value - stats->mean);
    stats->min = MIN(stats->min, value);
    stats->max = MAX(stats->max, value);
}

NSTimeInterval iTermPreciseTimerStatsGetMean(iTermPreciseTimerStats *stats) {
    if (!gPreciseTimersEnabled) {
        return 0;
    }
    return stats->mean;
}

NSTimeInterval iTermPreciseTimerStatsGetStddev(iTermPreciseTimerStats *stats) {
    if (!gPreciseTimersEnabled) {
        return 0;
    }
    if (stats->n < 2) {
        return NAN;
    } else {
        return sqrt(stats->m2 / (stats->n - 1));
    }
}

void iTermPreciseTimerPeriodicLog(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  NSTimeInterval interval,
                                  BOOL logToConsole) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    static iTermPreciseTimer gLastLog;
    if (!gLastLog.start) {
        iTermPreciseTimerStart(&gLastLog);
    }

    if (iTermPreciseTimerMeasure(&gLastLog) >= interval) {
        iTermPreciseTimerLog(identifier, stats, count, logToConsole);
        iTermPreciseTimerStart(&gLastLog);
    }
}

static NSString *iTermEmojiForDuration(double ms) {
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

void iTermPreciseTimerLog(NSString *identifier,
                          iTermPreciseTimerStats stats[],
                          size_t count,
                          BOOL logToConsole) {
    NSMutableString *log = [[@"-- Precise Timers --\n" mutableCopy] autorelease];
    for (size_t i = 0; i < count; i++) {
        NSTimeInterval mean = iTermPreciseTimerStatsGetMean(&stats[i]) * 1000.0;
        NSTimeInterval stddev = iTermPreciseTimerStatsGetStddev(&stats[i]) * 1000.0;
        [log appendFormat:@"%@ %20s: µ=%0.3fms σ=%.03fms (95%% CI ≅ %0.3fms–%0.3fms) 𝚺=%.2fms N=%@ avg. events=%01.f\n",
         iTermEmojiForDuration(mean),
         stats[i].name,
         mean,
         stddev,
         MAX(0, mean - stddev),
         mean + stddev,
         stats[i].n * mean,
         @(stats[i].n),
         (double)stats[i].totalEventCount / (double)stats[i].n];
        iTermPreciseTimerStatsInit(&stats[i], NULL);
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
                                  BOOL logToConsole) {
    NSMutableString *log = [[@"-- Precise Timers (One Event) --\n" mutableCopy] autorelease];
    for (size_t i = 0; i < count; i++) {
        if (stats[i].n == 0) {
            continue;
        }
        const char *cname = stats[i].name;
        int length = strlen(cname);
        NSMutableString *name = [NSMutableString string];
        while (length > 1 && cname[length - 1] == '<') {
            length--;
            [name appendString:@"    "];
        }
        NSTimeInterval ms = stats[i].n * iTermPreciseTimerStatsGetMean(&stats[i]) * 1000.0;
        NSString *emoji = iTermEmojiForDuration(ms);
        [name appendString:[[NSString alloc] initWithBytes:cname length:length encoding:NSUTF8StringEncoding]];
        NSString *other = @"";
        if (stats[i].n > 1) {
            int count = iTermPreciseTimerStatsGetCount(&stats[i]);
            double mean = iTermPreciseTimerStatsGetMean(&stats[i]);
            other = [NSString stringWithFormat:@"N=%@ µ=%0.1fms [%0.1fms…%0.1fms]", @(count), mean * 1000, stats[i].min * 1000, stats[i].max * 1000];
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
    @synchronized([iTermPreciseTimersLock class]) {
        if (!sLogs) {
            sLogs = [[NSMutableDictionary alloc] init];
        }
        sLogs[identifier] = log;
    }
}

NSString *iTermPreciseTimerGetSavedLogs(void) {
    @synchronized([iTermPreciseTimersLock class]) {
        NSMutableString *result = [NSMutableString string];
        [sLogs enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            NSInteger numLines = [[obj componentsSeparatedByString:@"\n"] count];
            [result appendFormat:@"Precise timers %@:%@%@\n", key, numLines > 1 ? @"\n" : @"", obj];
        }];
        return result;
    }
}

void iTermPreciseTimerClearLogs(void) {
    @synchronized([iTermPreciseTimersLock class]) {
        [sLogs removeAllObjects];
    }
}

#endif
