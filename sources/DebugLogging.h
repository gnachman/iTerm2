//
//  DebugLogging.h
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import <Foundation/Foundation.h>
#include <assert.h>

extern BOOL gDebugLogging;

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
// variadaic objc call as an argument is not a single value.
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

// Info log: no private info. Low-volume. Logged to crash reports.
#define ILog(args...) \
    do { \
        DLog(args); \
        LogForNextCrash(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args]); \
    } while (0)

// Error log: no private info. Low-volume. Logged to crash reports.
#define ELog(args...) \
    do { \
        DLog(args); \
        LogForNextCrash(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args]); \
        NSLog(args); \
    } while (0)

// Private error log. May contain private info. Logged to syslog, but not crash reports.
#define XLog(args...) \
    do { \
        DLog(args); \
        NSLog(args); \
    } while (0)
#endif

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
          NSAlert *alert = [[NSAlert alloc] init]; \
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

void ToggleDebugLogging(void);
int DebugLogImpl(const char *file, int line, const char *function, NSString* value);
void LogForNextCrash(const char *file, int line, const char *function, NSString* value);
void TurnOnDebugLoggingSilently(void);
BOOL TurnOffDebugLoggingSilently(void);

void SetPinnedDebugLogMessage(NSString *key, NSString *value, ...);
void AppendPinnedDebugLogMessage(NSString *key, NSString *value, ...);
