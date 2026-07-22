//
//  DebugLogging.h
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#include <assert.h>

#ifndef __OBJC__
#include "iTermCLogging.h"
#else
// Rest of the file is Obj-C code path
#import <Foundation/Foundation.h>
extern BOOL gDebugLogging;

// Logs the result of `messageBlock` once per (key, debug-logging
// session). The key set clears each time logging starts, so a
// diagnosis emitted into an earlier, discarded capture re-emits into
// the next one. While logging is off this neither logs nor consumes
// the key, so the one-shot can't be burned before the user enables
// logging to capture it. The block runs only when the message will
// actually be logged; expensive diagnostics belong inside it. Dedup
// is global (one emission per key across all views/windows).
void DLogOncePerLoggingSession(NSString *key, NSString *(^messageBlock)(void));
#include "iTermCLogging.h"

#define USE_STOPWATCH 0

#define ENABLE_EXTRA_DEBUGGING 0
#if ENABLE_EXTRA_DEBUGGING
#define ITExtraDebugAssert assert
#else
#define ITExtraDebugAssert(condition)
#endif

#if ITERM_DEBUG
#define ITDebugAssert assert
#else
// Cast condition to void to avoid unused variable warnings.
#define ITDebugAssert(condition) ((void)(condition))
#endif

#if !ITERM_DEBUG && USE_STOPWATCH
#define STOPWATCH_START(name) \
  NSTimeInterval start_##name = [NSDate timeIntervalSinceReferenceDate]; \
  static int count_##name; \
  static double sum_##name

#define STOPWATCH_LAP(name) \
  do { \
    count_##name++; \
    sum_##name += [NSDate timeIntervalSinceReferenceDate] - start_##name; \
    if (count_##name % 10000 == 0) { \
      NSLog(@"%s: %fms (%d)", #name, 1000.0 * sum_##name / count_##name, count_##name); \
    } \
  } while (0)
#else
#define STOPWATCH_START(name)
#define STOPWATCH_LAP(name)
#endif


// I use a variadic macro here because of an apparent compiler bug in XCode 4.2 that thinks a
// variadic objc call as an argument is not a single value.
#define DebugLog(args...) DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, args)

//#define GENERAL_VERBOSE_LOGGING
#ifdef GENERAL_VERBOSE_LOGGING
#define DLog NSLog
#define ELog NSLog
#else
#define DLog(args...) \
    do { \
        if (gDebugLogging) { \
            DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args]); \
        } \
    } while (0)

// Write to crash log immediately and unconditionally. Use this when you expect to crash right away.
#define CrashLog(args...) \
    do { \
        LogForNextCrash(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args], YES); \
    } while (0)

// Info log: no private info. Low-volume. Logged to crash reports.
#define ILog(args...) \
    do { \
        DLog(args); \
        LogForNextCrash(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args], NO); \
    } while (0)

// Error log: no private info. Low-volume. Logged to crash reports.
#define ELog(args...) \
    do { \
        DLog(args); \
        LogForNextCrash(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args], NO); \
        NSLog(args); \
    } while (0)

// Private error log. May contain private info. Logged to syslog, but not crash reports.
#define XLog(args...) \
    do { \
        DLog(args); \
        NSLog(args); \
    } while (0)

// Retrospective log: like DLog, but when debug logging is OFF the message is
// retained in a byte-bounded in-memory ring (instead of being dropped) so the
// lead-up to a low-frequency event can be recovered after the fact. The ring is
// deliberately NOT included in debug logs (the user never opted into capturing
// it); retrieve it explicitly via iTermRetrospectiveLogString when you have a
// specific reason to surface it. When debug logging is already on, this behaves
// identically to DLog. Use for low-frequency events only; the format string is
// always evaluated.
#define RLog(args...) \
    RetrospectiveLogImpl(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args])
#endif

// For use as an RLog format argument. Resolves to `full` when debug logging is
// enabled and `redacted` when it is not. RLog feeds the live debug log when the
// user has opted into debug logging and the always-on retrospective ring
// otherwise; this lets a value be complete in the opt-in log but redacted in the
// ring (which must not accumulate private data). Both arguments are evaluated
// eagerly, so keep them cheap. Example:
//   RLog(@"Key up: %@", RLogRedact(event, event.it_redactedDescription));
NSObject *RLogRedact(id full, id redacted);

#define ITAssert(condition) \
  do { \
    if (!(condition)) { \
      DLog(@"Crashing because %s from:\n%@", #condition, [NSThread callStackSymbols]); \
      if (TurnOffDebugLoggingSilently()) { \
        NSRunAlertPanel(@"Critical Error", @"A critical error occurred and a debug log was created. Please send /tmp/debuglog.txt to the developers.", @"OK", nil, nil); \
      } \
      assert(NO, "ITAssert: " #condition); \
    } \
  } while (0)

#if __has_feature(objc_arc)
#define ITCriticalErrorCreateAlert [[NSAlert alloc] init]
#else
#define ITCriticalErrorCreateAlert [[[NSAlert alloc] init] autorelease]
#endif

#define ITCriticalError(condition, args...) \
  do { \
    if (!(condition)) { \
      static BOOL haveAlerted; \
      if (haveAlerted) { \
        DLog(@"Critical error %s from:\n%@", #condition, [NSThread callStackSymbols]); \
        DLog(args); \
        break; \
      } \
      haveAlerted = YES; \
      TurnOnDebugLoggingSilently(); \
      ELog(@"Critical error %s from:\n%@", #condition, [NSThread callStackSymbols]); \
      ELog(args); \
      if (TurnOffDebugLoggingSilently()) { \
        dispatch_async(dispatch_get_main_queue(), ^{ \
          NSAlert *alert = ITCriticalErrorCreateAlert; \
          alert.messageText = @"Critical Error"; \
          alert.informativeText =  @"A critical error occurred and a debug log was created. Please send /tmp/debuglog.txt to the developers."; \
          [alert addButtonWithTitle:@"OK"]; \
          [alert runModal]; \
        }); \
      } \
    } \
  } while (0)

#define IT_STRINGIFY(x) #x

#if BETA
#define ITBetaAssertSampled(percentage, condition, args...) \
  do { \
    if (!(condition) && arc4random_uniform(100) < percentage) { \
      DLog(@"Crashing because %s from:\n%@", #condition, [NSThread callStackSymbols]); \
      ELog(args); \
      assert(NO); \
    } \
  } while (0)
#else  // BETA
#define ITBetaAssertSampled(percentage, condition, args...) \
  do { \
    if (!(condition) && arc4random_uniform(100) < percentage) { \
      ELog(@"BETA ASSERT: Failed beta assert because %s from:\n%@", #condition, [NSThread callStackSymbols]); \
      ELog(args); \
    } \
  } while (0)
#endif

#if BETA
#define ITBetaAssert(condition, args...) \
  do { \
    if (!(condition)) { \
      DLog(@"Crashing because %s from:\n%@", #condition, [NSThread callStackSymbols]); \
      ELog(args); \
      assert(NO); \
    } \
  } while (0)
#else  // BETA
#define ITBetaAssert(condition, args...) \
  do { \
    if (!(condition)) { \
      ELog(@"BETA ASSERT: Failed beta assert because %s from:\n%@", #condition, [NSThread callStackSymbols]); \
      ELog(args); \
    } \
  } while (0)
#endif

#if BETA
#define ITConservativeBetaAssert(condition, args...) \
  do { \
    if (!(condition)) { \
      DLog(@"Crashing because %s from:\n%@", #condition, [NSThread callStackSymbols]); \
      ELog(args); \
      assert(NO); \
    } \
  } while (0)
#else  // BETA
#define ITConservativeBetaAssert(condition, args...)
#endif

#define ITAssertWithMessage(condition, args...) \
    do { \
        if (!(condition)) { \
            DLog(@"Crashing because %s from:\n%@", #condition, [NSThread callStackSymbols]); \
            ELog(args); \
            __assert_rtn(__func__, __FILE__, __LINE__, [[NSString stringWithFormat:@#condition ": " args] UTF8String]); \
        } \
    } while (0)

void iTermFatalError(NSString *s) __attribute__((noreturn));

NSString *iTermDebugLogHeaderString(void);
void ToggleDebugLogging(void);
int DebugLogImpl(const char *file, int line, const char *function, NSString* value);
void RetrospectiveLogImpl(const char *file, int line, const char *function, NSString *value);
// Returns the current contents of the retrospective ring (lines retained by
// RLog while debug logging was off). Deliberately NOT included in debug logs,
// since the user never opted into capturing it; surface it only when you have a
// specific reason to. iTermClearRetrospectiveLog empties the ring.
NSString *iTermRetrospectiveLogString(void);
void iTermClearRetrospectiveLog(void);
void LogForNextCrash(const char *file, int line, const char *function, NSString* value, BOOL force);
void TurnOnDebugLoggingSilently(void);
BOOL TurnOffDebugLoggingSilently(void);
void TurnOnDebugLoggingAutomatically(void);

void SetPinnedDebugLogMessage(NSString *key, NSString *value, ...);
void AppendPinnedDebugLogMessage(NSString *key, NSString *value, ...);

_Noreturn NS_INLINE void iTermCrashWithMessage(const char *file,
                                               int line,
                                               const char  *function,
                                               const char  *message) {
    __assert_rtn(function, file, line, message);
}

@interface NSException(iTerm)
@property (nonatomic, readonly) NSArray<NSString *> *it_originalCallStackSymbols;
@property (nonatomic, readonly) NSString *it_compressedDescription;
- (NSException *)it_rethrowWithMessage:(NSString *)format, ...;
@end

#endif  // __OBJC__

#define VLog(args...)
//#define VLog(args...) NSLog(args)
