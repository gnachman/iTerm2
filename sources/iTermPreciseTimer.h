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
    double min;
    double max;
    int level;
} iTermPreciseTimerStats;

@class NSArray;

#define ENABLE_PRECISE_TIMERS 1

#if ENABLE_PRECISE_TIMERS

void iTermPreciseTimerSetEnabled(BOOL enabled);
void iTermPreciseTimerStart(iTermPreciseTimer *timer);
NSTimeInterval iTermPreciseTimerAccumulate(iTermPreciseTimer *timer, NSTimeInterval value);
NSTimeInterval iTermPreciseTimerMeasureAndAccumulate(iTermPreciseTimer *timer);
void iTermPreciseTimerReset(iTermPreciseTimer *timer);
NSTimeInterval iTermPreciseTimerMeasure(iTermPreciseTimer *timer);

void iTermPreciseTimerStatsInit(iTermPreciseTimerStats *stats, const char *name);
void iTermPreciseTimerStatsStartTimer(iTermPreciseTimerStats *stats);
double iTermPreciseTimerStatsMeasureAndRecordTimer(iTermPreciseTimerStats *stats);
void iTermPreciseTimerStatsRecordTimer(iTermPreciseTimerStats *stats);

void iTermPreciseTimerStatsMeasureAndAccumulate(iTermPreciseTimerStats *stats);
void iTermPreciseTimerStatsAccumulate(iTermPreciseTimerStats *stats, NSTimeInterval value);
void iTermPreciseTimerStatsRecord(iTermPreciseTimerStats *stats, NSTimeInterval value, int eventCount);
NSInteger iTermPreciseTimerStatsGetCount(iTermPreciseTimerStats *stats);
NSTimeInterval iTermPreciseTimerStatsGetMean(iTermPreciseTimerStats *stats);
NSTimeInterval iTermPreciseTimerStatsGetStddev(iTermPreciseTimerStats *stats);

void iTermPreciseTimerPeriodicLog(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  NSTimeInterval interval,
                                  BOOL logToConsole,
                                  NSArray *histograms);
void iTermPreciseTimerLogOneEvent(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  BOOL logToConsole,
                                  NSArray *histograms);
void iTermPreciseTimerLog(NSString *identifier,
                          iTermPreciseTimerStats stats[],
                          size_t count,
                          BOOL logToConsole,
                          NSArray *histograms);
NSString *iTermPreciseTimerGetSavedLogs(void);
void iTermPreciseTimerSaveLog(NSString *identifier, NSString *log);
void iTermPreciseTimerClearLogs(void);

#else

void iTermPreciseTimerSetEnabled(BOOL enabled) { }
static inline void iTermPreciseTimerStart(iTermPreciseTimer *timer) { }
static inline NSTimeInterval iTermPreciseTimerAccumulate(iTermPreciseTimer *timer) { return 0; }
static inline NSTimeInterval iTermPreciseTimerMeasureAndAccumulate(iTermPreciseTimer *timer) { return 0; }
static inline void iTermPreciseTimerReset(iTermPreciseTimer *timer) { }
static inline NSTimeInterval iTermPreciseTimerMeasure(iTermPreciseTimer *timer) { return 0; }

static inline void iTermPreciseTimerStatsInit(iTermPreciseTimerStats *stats, const char *name) { }
static inline void iTermPreciseTimerStatsStartTimer(iTermPreciseTimerStats *stats) { }
static inline double iTermPreciseTimerStatsMeasureAndRecordTimer(iTermPreciseTimerStats *stats) { }
static inline void iTermPreciseTimerStatsMeasureAndAccumulate(iTermPreciseTimerStats *stats) { }
static inline void iTermPreciseTimerStatsRecordTimer(iTermPreciseTimerStats *stats) { }

static inline void iTermPreciseTimerStatsAccumulate(iTermPreciseTimerStats *stats, NSTimeInterval value) { }
static inline void iTermPreciseTimerStatsRecord(iTermPreciseTimerStats *stats, NSTimeInterval value, int eventCount) { }
static inline NSInteger iTermPreciseTimerStatsGetCount(iTermPreciseTimerStats *stats) { return 0; }
static inline NSTimeInterval iTermPreciseTimerStatsGetMean(iTermPreciseTimerStats *stats) { return 0; }
static inline NSTimeInterval iTermPreciseTimerStatsGetStddev(iTermPreciseTimerStats *stats) { return 0; }

static inline void iTermPreciseTimerPeriodicLog(NSString *identifier,
                                                iTermPreciseTimerStats stats[],
                                                size_t count,
                                                NSTimeInterval interval,
                                                BOOL logToConsole,
                                                NSArray *histograms) { }
void iTermPreciseTimerPeriodicLog(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  BOOL logToConsole,
                                  NSArray *histograms) { }
void iTermPreciseTimerLogOneEvent(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  BOOL logToConsole,
                                  NSArray *histograms) { }
NSString *iTermPreciseTimerGetSavedLogs(void) { }
void iTermPreciseTimerSaveLog(NSString *identifier, NSString *log) { }
void iTermPreciseTimerClearLogs(void);

#endif
