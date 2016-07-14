//
//  iTermPreciseTimer.m
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import "iTermPreciseTimer.h"

#include <assert.h>
#include <CoreServices/CoreServices.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <unistd.h>

#if ENABLE_PRECISE_TIMERS
void iTermPreciseTimerStart(iTermPreciseTimer *timer) {
    timer->start = mach_absolute_time();
}

NSTimeInterval iTermPreciseTimerAccumulate(iTermPreciseTimer *timer) {
    timer->total += iTermPreciseTimerMeasure(timer);
    return timer->total;
}

void iTermPreciseTimerReset(iTermPreciseTimer *timer) {
    timer->total = 0;
}

NSTimeInterval iTermPreciseTimerMeasure(iTermPreciseTimer *timer) {
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
    stats->n = 0;
    stats->mean = 0;
    stats->m2 = 0;
    iTermPreciseTimerReset(&stats->timer);
    if (name) {
        strlcpy(stats->name, name, sizeof(stats->name));
    }
}

NSInteger iTermPreciseTimerStatsGetCount(iTermPreciseTimerStats *stats) {
    return stats->n;
}

void iTermPreciseTimerStatsStartTimer(iTermPreciseTimerStats *stats) {
    iTermPreciseTimerStart(&stats->timer);
}

void iTermPreciseTimerStatsMeasureAndRecordTimer(iTermPreciseTimerStats *stats) {
    iTermPreciseTimerStatsRecord(stats, iTermPreciseTimerAccumulate(&stats->timer));
    iTermPreciseTimerReset(&stats->timer);
}

void iTermPreciseTimerStatsRecordTimer(iTermPreciseTimerStats *stats) {
    iTermPreciseTimerStatsRecord(stats, stats->timer.total);
    iTermPreciseTimerReset(&stats->timer);
}

void iTermPreciseTimerStatsAccumulate(iTermPreciseTimerStats *stats) {
    iTermPreciseTimerAccumulate(&stats->timer);
}

void iTermPreciseTimerStatsRecord(iTermPreciseTimerStats *stats, NSTimeInterval value) {
    // Welford's online variance algorithm, adopted from:
    // https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Higher-order_statistics
    stats->n += 1;
    double delta = value - stats->mean;
    stats->mean += delta / stats->n;
    stats->m2 += delta * (value - stats->mean);
}

NSTimeInterval iTermPreciseTimerStatsGetMean(iTermPreciseTimerStats *stats) {
    return stats->mean;
}

NSTimeInterval iTermPreciseTimerStatsGetStddev(iTermPreciseTimerStats *stats) {
    if (stats->n < 2) {
        return NAN;
    } else {
        return sqrt(stats->m2 / (stats->n - 1));
    }
}

void iTermPreciseTimerPeriodicLog(iTermPreciseTimerStats stats[],
                                  size_t count,
                                  NSTimeInterval interval) {
    static iTermPreciseTimer gLastLog;
    if (!gLastLog.start) {
        iTermPreciseTimerStart(&gLastLog);
    }
    
    if (iTermPreciseTimerMeasure(&gLastLog) >= interval) {
        for (size_t i = 0; i < count; i++) {
            NSLog(@"%20s: %0.3fms ±%.03fms (2σ) n=%@",
                  stats[i].name,
                  iTermPreciseTimerStatsGetMean(&stats[i]) * 1000.0,
                  iTermPreciseTimerStatsGetStddev(&stats[i]) * 1000.0 * 2,
                  @(stats[i].n));
            iTermPreciseTimerStatsInit(&stats[i], NULL);
        }
        NSLog(@"");
        iTermPreciseTimerStart(&gLastLog);
    }
}
#endif
