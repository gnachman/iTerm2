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

void iTermPreciseTimerStatsInit(iTermPreciseTimerStats *stats, char *name) {
    if (!gPreciseTimersEnabled) {
        return;
    }
    stats->n = 0;
    stats->totalEventCount = 0;
    stats->mean = 0;
    stats->m2 = 0;
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

void iTermPreciseTimerPeriodicLog(iTermPreciseTimerStats stats[],
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
        NSMutableString *log = [[@"-- Precise Timers --\n" mutableCopy] autorelease];
        for (size_t i = 0; i < count; i++) {
            NSTimeInterval mean = iTermPreciseTimerStatsGetMean(&stats[i]) * 1000.0;
            NSTimeInterval stddev = iTermPreciseTimerStatsGetStddev(&stats[i]) * 1000.0;
            [log appendFormat:@"%20s: µ=%0.3fms σ=%.03fms (95%% CI ≅ %0.3fms–%0.3fms) 𝚺=%.2fms N=%@ avg. events=%01.f\n",
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
            ELog(@"%@", log);
        } else {
            DLog(@"%@", log);
        }
        iTermPreciseTimerStart(&gLastLog);
    }
}
#endif
