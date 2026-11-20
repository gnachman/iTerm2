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
// Unlike DLog, this takes one NSString, not a format, and evaluates it even when debug logging
// is off (DebugLogImpl checks gDebugLogging only after the argument has been computed).
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
// The arguments are evaluated once for the crash log and once more for DLog when debug logging
// is on, so an argument with a side effect runs once or twice. A Swift function evaluates it
// exactly once, which is equivalent only for arguments without side effects.
#define ILog(args...) \
    do { \
        DLog(args); \
        LogForNextCrash(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args], NO); \
    } while (0)

// Error log: no private info. Low-volume. Logged to crash reports.
// The arguments are evaluated twice (crash log and NSLog), or three times when debug logging is
// on (DLog as well). An argument like strerror(errno) is read again after the earlier logging
// calls, which may have changed errno. A Swift replacement evaluates each argument once.
#define ELog(args...) \
    do { \
        DLog(args); \
        LogForNextCrash(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args], NO); \
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

// Nothing uses ITAssert, and a use would not compile: it passes two arguments to assert(),
// which takes one. Code that wants this behavior uses ITAssertWithMessage.
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

// The break below leaves only this macro's own do/while, never a loop in the caller. Each use
// has its own static haveAlerted, so the alert appears at most once per call site per launch;
// a Swift port needs state per call site, not one flag. The first failure turns debug logging
// on before ELog, so the message arguments are evaluated three times then (once if logging is
// on for a later failure, zero times if it is off).
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

// Which definition applies depends on the target as well as the configuration: the app targets
// define BETA in Development, Beta and Nightly, but ModernTests and pidinfo do not, so code they
// compile logs and continues even in a Development build. The message arguments are evaluated
// only on failure, two or three times (ELog). The Swift form is it_betaAssert.
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

// Without BETA this expands to nothing: neither the condition nor the message is evaluated, so a
// condition with a side effect behaves differently by build. it_conservativeBetaAssert keeps
// that by taking both as autoclosures.
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

// YES when this code was compiled with BETA defined (the Development, Beta and Nightly
// configurations), where ITBetaAssert crashes; NO in Deployment, where it logs and continues.
// Swift cannot see the BETA macro, so it_betaAssert and the other Swift migration helpers read
// this instead. It is not const only so that tests can check the Deployment behavior of the
// Swift helpers; nothing else assigns it.
extern BOOL iTermBetaAssertionsCrash;

// Wraps the lock expression of a @synchronized statement:
//   @synchronized(ITNonnilLock(_lock)) { ... }
// @synchronized(nil) runs its block with no lock and no error. This evaluates the expression once,
// beta-asserts that the result is not nil (crash in Development, Beta and Nightly builds; log in
// Deployment, which then does what it always did), and yields that same object to lock. See
// docs/swift-migration/concurrency.md section 2.
#define ITNonnilLock(lockExpression) \
  ({ \
    id it_nonnilLock_ = (lockExpression); \
    ITBetaAssert(it_nonnilLock_ != nil, @"@synchronized(%s) at %s:%d has a nil lock and runs unprotected", \
                 #lockExpression, __FILE__, __LINE__); \
    it_nonnilLock_; \
  })

// Crashes in every build: it calls __assert_rtn directly, so NDEBUG does not remove it. The
// condition's source text is pasted into a format string, so a % in the condition would be read
// as a format specifier, and args must begin with a string literal. On failure the message
// arguments are evaluated three or four times; the condition is evaluated once.
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

// Any thread. Adds `provider`'s description of a subsystem's state, under `name`, to the header
// and footer of debug logs. The provider is called with the debug log lock held, so it must not
// log, and must not take a lock that is held anywhere logging happens.
void iTermRegisterDebugLogStateProvider(NSString *name, NSString *(^provider)(void));

void SetPinnedDebugLogMessage(NSString *key, NSString *value, ...) NS_FORMAT_FUNCTION(2,3);
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
