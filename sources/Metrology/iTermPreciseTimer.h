//
//  iTermPreciseTimer.h
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import <Foundation/Foundation.h>

// The mutable fields are _Atomic so the render thread that writes a stats struct
// and the display/log thread that reads it never race in an undefined way (no
// lock is taken on the hot path). Each struct has a single writer (one render
// pass), so the relaxed load/store used for the double fields cannot lose an
// update; the integer counters use true atomic add and are correct regardless.
// `name` and `level` are set once at init before any concurrent use, so they stay
// plain. All these types are naturally lock-free (8 bytes), so _Atomic does not
// change the struct size or layout.
typedef struct {
    _Atomic(uint64_t) start;
    _Atomic(NSTimeInterval) total;
    _Atomic(NSInteger) eventCount;
} iTermPreciseTimer;

typedef struct {
    char name[20];
    iTermPreciseTimer timer;
    _Atomic(NSInteger) n;
    _Atomic(NSInteger) totalEventCount;
    _Atomic(double) mean;
    _Atomic(double) m2;
    _Atomic(double) min;
    _Atomic(double) max;
    int level;
} iTermPreciseTimerStats;

// A shared lock token. The precise-timer internals no longer use it (they are
// lock-free; see iTermPreciseTimer.m), but other subsystems synchronize on it
// (iTermAttributedStringBuilder, PerformanceCounter), so it is kept.
@interface iTermPreciseTimersLock : NSObject
@end

@class NSArray;

#define ENABLE_PRECISE_TIMERS 1

#if ENABLE_PRECISE_TIMERS

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
iTermPreciseTimerStats *iTermPreciseTimerStatsCopy(const iTermPreciseTimerStats *source);

void iTermPreciseTimerPeriodicLog(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  NSTimeInterval interval,
                                  BOOL logToConsole,
                                  NSArray *histograms,
                                  NSString *additional);
void iTermPreciseTimerLogOneEvent(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  BOOL logToConsole,
                                  NSArray *histograms);
void iTermPreciseTimerLog(NSString *identifier,
                          iTermPreciseTimerStats stats[],
                          size_t count,
                          BOOL logToConsole,
                          NSArray *histograms,
                          NSString *additional);
NSString *iTermPreciseTimerLogString(NSString *identifier,
                                     iTermPreciseTimerStats stats[],
                                     size_t count,
                                     NSArray *histograms,
                                     BOOL reset);

NSString *iTermPreciseTimerGetSavedLogs(void);
void iTermPreciseTimerSaveLog(NSString *identifier, NSString *log);
void iTermPreciseTimerClearLogs(void);

#else

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
                                                NSArray *histograms,
                                                NSString *additional) { }
void iTermPreciseTimerPeriodicLog(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  BOOL logToConsole,
                                  NSArray *histograms,
                                  NSString *additional) { }
void iTermPreciseTimerLogOneEvent(NSString *identifier,
                                  iTermPreciseTimerStats stats[],
                                  size_t count,
                                  BOOL logToConsole,
                                  NSArray *histograms) { }
NSString *iTermPreciseTimerGetSavedLogs(void) { }
void iTermPreciseTimerSaveLog(NSString *identifier, NSString *log) { }
void iTermPreciseTimerClearLogs(void);

#endif

NSString *iTermEmojiForDuration(double ms);
