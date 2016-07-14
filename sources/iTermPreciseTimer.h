//
//  iTermPreciseTimer.h
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import <Foundation/Foundation.h>

typedef struct {
    uint64_t start;
    NSTimeInterval total;
} iTermPreciseTimer;

typedef struct {
    char name[20];
    iTermPreciseTimer timer;
    NSInteger n;
    double mean;
    double m2;
} iTermPreciseTimerStats;

// #define ENABLE_PRECISE_TIMERS

#if ENABLE_PRECISE_TIMERS
void iTermPreciseTimerStart(iTermPreciseTimer *timer);
NSTimeInterval iTermPreciseTimerAccumulate(iTermPreciseTimer *timer);
void iTermPreciseTimerReset(iTermPreciseTimer *timer);
NSTimeInterval iTermPreciseTimerMeasure(iTermPreciseTimer *timer);

void iTermPreciseTimerStatsInit(iTermPreciseTimerStats *stats, char *name);
void iTermPreciseTimerStatsStartTimer(iTermPreciseTimerStats *stats);
void iTermPreciseTimerStatsMeasureAndRecordTimer(iTermPreciseTimerStats *stats);
void iTermPreciseTimerStatsRecordTimer(iTermPreciseTimerStats *stats);

void iTermPreciseTimerStatsAccumulate(iTermPreciseTimerStats *stats);
void iTermPreciseTimerStatsRecord(iTermPreciseTimerStats *stats, NSTimeInterval value);
NSInteger iTermPreciseTimerStatsGetCount(iTermPreciseTimerStats *stats);
NSTimeInterval iTermPreciseTimerStatsGetMean(iTermPreciseTimerStats *stats);
NSTimeInterval iTermPreciseTimerStatsGetStddev(iTermPreciseTimerStats *stats);

void iTermPreciseTimerPeriodicLog(iTermPreciseTimerStats stats[],
                                  size_t count,
                                  NSTimeInterval interval);
#else
static void iTermPreciseTimerStart(iTermPreciseTimer *timer) { }
static NSTimeInterval iTermPreciseTimerAccumulate(iTermPreciseTimer *timer) { return 0; }
static void iTermPreciseTimerReset(iTermPreciseTimer *timer) { }
static NSTimeInterval iTermPreciseTimerMeasure(iTermPreciseTimer *timer) { return 0; }

static void iTermPreciseTimerStatsInit(iTermPreciseTimerStats *stats, char *name) { }
static void iTermPreciseTimerStatsStartTimer(iTermPreciseTimerStats *stats) { }
static void iTermPreciseTimerStatsMeasureAndRecordTimer(iTermPreciseTimerStats *stats) { }
static void iTermPreciseTimerStatsRecordTimer(iTermPreciseTimerStats *stats) { }

static void iTermPreciseTimerStatsAccumulate(iTermPreciseTimerStats *stats) { }
static void iTermPreciseTimerStatsRecord(iTermPreciseTimerStats *stats, NSTimeInterval value) { }
static NSInteger iTermPreciseTimerStatsGetCount(iTermPreciseTimerStats *stats) { return 0; }
static NSTimeInterval iTermPreciseTimerStatsGetMean(iTermPreciseTimerStats *stats) { return 0; }
static NSTimeInterval iTermPreciseTimerStatsGetStddev(iTermPreciseTimerStats *stats) { return 0; }

static void iTermPreciseTimerPeriodicLog(iTermPreciseTimerStats stats[],
                                  size_t count,
                                  NSTimeInterval interval) { }
#endif
