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
    NSInteger eventCount;
} iTermPreciseTimer;

typedef struct {
    char name[20];
    iTermPreciseTimer timer;
    NSInteger n;
    NSInteger totalEventCount;
    double mean;
    double m2;
} iTermPreciseTimerStats;

#define ENABLE_PRECISE_TIMERS 0

#if ENABLE_PRECISE_TIMERS
void iTermPreciseTimerStart(iTermPreciseTimer *timer);
NSTimeInterval iTermPreciseTimerAccumulate(iTermPreciseTimer *timer, NSTimeInterval value);
NSTimeInterval iTermPreciseTimerMeasureAndAccumulate(iTermPreciseTimer *timer);
void iTermPreciseTimerReset(iTermPreciseTimer *timer);
NSTimeInterval iTermPreciseTimerMeasure(iTermPreciseTimer *timer);

void iTermPreciseTimerStatsInit(iTermPreciseTimerStats *stats, char *name);
void iTermPreciseTimerStatsStartTimer(iTermPreciseTimerStats *stats);
void iTermPreciseTimerStatsMeasureAndRecordTimer(iTermPreciseTimerStats *stats);
void iTermPreciseTimerStatsRecordTimer(iTermPreciseTimerStats *stats);

void iTermPreciseTimerStatsMeasureAndAccumulate(iTermPreciseTimerStats *stats);
void iTermPreciseTimerStatsAccumulate(iTermPreciseTimerStats *stats, NSTimeInterval value);
void iTermPreciseTimerStatsRecord(iTermPreciseTimerStats *stats, NSTimeInterval value, int eventCount);
NSInteger iTermPreciseTimerStatsGetCount(iTermPreciseTimerStats *stats);
NSTimeInterval iTermPreciseTimerStatsGetMean(iTermPreciseTimerStats *stats);
NSTimeInterval iTermPreciseTimerStatsGetStddev(iTermPreciseTimerStats *stats);

void iTermPreciseTimerPeriodicLog(iTermPreciseTimerStats stats[],
                                  size_t count,
                                  NSTimeInterval interval);
#else
static inline void iTermPreciseTimerStart(iTermPreciseTimer *timer) { }
static inline NSTimeInterval iTermPreciseTimerAccumulate(iTermPreciseTimer *timer) { return 0; }
static inline NSTimeInterval iTermPreciseTimerMeasureAndAccumulate(iTermPreciseTimer *timer) { return 0; }
static inline void iTermPreciseTimerReset(iTermPreciseTimer *timer) { }
static inline NSTimeInterval iTermPreciseTimerMeasure(iTermPreciseTimer *timer) { return 0; }

static inline void iTermPreciseTimerStatsInit(iTermPreciseTimerStats *stats, char *name) { }
static inline void iTermPreciseTimerStatsStartTimer(iTermPreciseTimerStats *stats) { }
static inline void iTermPreciseTimerStatsMeasureAndRecordTimer(iTermPreciseTimerStats *stats) { }
static inline void iTermPreciseTimerStatsRecordTimer(iTermPreciseTimerStats *stats) { }

static inline void iTermPreciseTimerStatsMeasureAndAccumulate(iTermPreciseTimerStats *stats) { }
static inline void iTermPreciseTimerStatsAccumulate(iTermPreciseTimerStats *stats, NSTimeInterval value) { }
static inline void iTermPreciseTimerStatsRecord(iTermPreciseTimerStats *stats, NSTimeInterval value, int eventCount) { }
static inline NSInteger iTermPreciseTimerStatsGetCount(iTermPreciseTimerStats *stats) { return 0; }
static inline NSTimeInterval iTermPreciseTimerStatsGetMean(iTermPreciseTimerStats *stats) { return 0; }
static inline NSTimeInterval iTermPreciseTimerStatsGetStddev(iTermPreciseTimerStats *stats) { return 0; }

static inline void iTermPreciseTimerPeriodicLog(iTermPreciseTimerStats stats[],
                                                size_t count,
                                                NSTimeInterval interval) { }
#endif
