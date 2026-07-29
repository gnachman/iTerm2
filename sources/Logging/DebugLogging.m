//
//  DebugLogging.m
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "NSData+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import <Cocoa/Cocoa.h>

#import <os/log.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/sysctl.h>

static NSString *const kDebugLogFilename = @"/tmp/debuglog.txt";
static NSString* gDebugLogHeader = nil;
static NSMutableString* gDebugLogStr = nil;

static NSMutableDictionary *gPinnedMessages;

// Retrospective log: a single, byte-bounded ring of recent RLog lines
// retained while debug logging is OFF, so a low-frequency event's lead-up
// is captured even though nobody enabled logging ahead of time. Guarded by
// GetDebugLogLock(). Deliberately NOT included in ordinary debug logs: the
// user never opted into capturing it, and folding it in would surface lines
// from before they turned logging on. It is surfaced only by the explicit
// Save Retrospective Debug Logs action (via iTermRetrospectiveLogString).
static NSMutableArray<NSString *> *gRetrospectiveLog;
static NSUInteger gRetrospectiveLogBytes;
static const NSUInteger kRetrospectiveLogMaxBytes = 10 * 1024 * 1024;

BOOL gDebugLogging = NO;
// Keys already emitted by DLogOncePerLoggingSession this logging
// session. Guarded by GetDebugLogLock(); cleared in StartDebugLogging.
static NSMutableSet<NSString *> *gOncePerLoggingSessionKeys;

static NSRecursiveLock *GetDebugLogLock(void) {
    static NSRecursiveLock *gDebugLogLock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gDebugLogLock = [[NSRecursiveLock alloc] init];
    });
    return gDebugLogLock;
}

static void AppendWindowDescription(NSWindow *window, NSMutableString *windows) {
    [windows appendFormat:@"\nWindow %@\n%@\n%@\n",
     window,
     [window delegate],
     [window.contentView iterm_recursiveDescription]];

    PseudoTerminal *term = [PseudoTerminal castFrom:window.delegate];
    if (term) {
        for (PTYSession *session in term.allSessions) {
            NSString *itd = [[session screen] intervalTreeDump];
            [windows appendFormat:@"For %@:\n%@\n\n", session, itd];
        }
    }
}

static NSString *iTermMachineInfo(void) {
    char temp[1000];
    size_t tempLen = sizeof(temp) - 1;
    if (sysctlbyname("hw.model", temp, &tempLen, 0, 0)) {
        return @"(unknown)";
    }
    return [NSString stringWithUTF8String:temp];
}

static NSString *iTermScreensInfo(void) {
    NSMutableArray<NSString *> *infos = [NSMutableArray array];
    for (NSScreen *screen in [NSScreen screens]) {
        [infos addObject:[NSString stringWithFormat:@"%@%@: %@ @ %@x",
                          [screen isEqual:NSScreen.mainScreen] ? @"[Main] " : @"",
                          screen.localizedName, NSStringFromRect(screen.frame), @(screen.backingScaleFactor)]];
    }
    return [infos componentsJoinedByString:@"; "];
}

static NSString *iTermOSVersionInfo(void) {
    static NSString *value;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
        value = [dict[@"ProductVersion"] copy];
    });
    return value ?: @"(nil)";
}

NSString *iTermDebugLogHeaderString(void) {
    NSMutableString *windows = [NSMutableString string];
    for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
        AppendWindowDescription(window, windows);
    }
    NSMutableString *pinnedMessages = [NSMutableString string];
    for (NSString *key in [[gPinnedMessages allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [pinnedMessages appendString:gPinnedMessages[key]];
    }
    NSString *header = [NSString stringWithFormat:
                        @"iTerm2 version: %@\n"
                        @"Date: %@ (%lld)\n"
                        @"Machine: %@\n"
                        @"Screens: %@\n"
                        @"OS version: %@\n"
                        @"Key window: %@\n"
                        @"Windows: %@\n"
                        @"Ordered windows: %@\n"
                        @"Pinned messages: %@\n"
                        @"------ END HEADER ------\n\n",

                        [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"],
                        [NSDate date],
                        (long long)[[NSDate date] timeIntervalSince1970],
                        iTermMachineInfo(),
                        iTermScreensInfo(),
                        iTermOSVersionInfo(),
                        [[NSApplication sharedApplication] keyWindow],
                        windows,
                        [(iTermApplication *)NSApp orderedWindowsPlusAllHotkeyPanels],
                        pinnedMessages];
    return header;
}

static void WriteDebugLogHeader(void) {
    gDebugLogHeader = [iTermDebugLogHeaderString() copy];
}

static NSString *DebugLogFooterString(void) {
  NSMutableString *windows = [NSMutableString string];
  for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
      AppendWindowDescription(window, windows);
  }
  return [NSString stringWithFormat:
          @"------ BEGIN FOOTER -----\n"
          @"Screens: %@\n"
          @"Windows: %@\n"
          @"Ordered windows: %@\n",

          iTermScreensInfo(),
          windows,
          [(iTermApplication *)NSApp orderedWindowsPlusAllHotkeyPanels]];
}

static void FlushDebugLog(void) {
    [GetDebugLogLock() lock];
    // Encode the header, body, and footer as three separate chunks rather than
    // concatenating them into one full-size string (and then a full-size NSData)
    // first. On a large capture that concatenation was the peak-memory spike at
    // stop; three streamed writes keep at most one body-sized copy alive.
    NSData *headerData = [(gDebugLogHeader ?: @"") dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    NSData *bodyData = [(gDebugLogStr ?: @"") dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    NSData *footerData = [DebugLogFooterString() dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];

    const BOOL append = ([iTermAdvancedSettingsModel appendToExistingDebugLog] &&
                         [[NSFileManager defaultManager] fileExistsAtPath:kDebugLogFilename]);
    NSError *error = nil;
    BOOL ok = YES;
    if (!append) {
        // Truncate (or create) the file so we start from empty.
        ok = [[NSFileManager defaultManager] createFileAtPath:kDebugLogFilename contents:nil attributes:nil];
    }
    NSFileHandle *fileHandle = ok ? [NSFileHandle fileHandleForWritingAtPath:kDebugLogFilename] : nil;
    ok = ok && (fileHandle != nil);
    if (ok && append) {
        [fileHandle seekToEndOfFile];
    }
    for (NSData *chunk in @[ headerData, bodyData, footerData ]) {
        if (!ok) {
            break;
        }
        ok = [fileHandle writeData:chunk error:&error];
    }
    [fileHandle closeFile];
    if (!ok) {
        // writeData:error: populates `error`, but a failed createFileAtPath: or a
        // nil file handle leaves it nil; fall back to a concrete message so the
        // user gets an actionable reason instead of "(null)".
        NSString *reason = error.localizedDescription ?: [NSString stringWithFormat:@"could not open %@ for writing", kDebugLogFilename];
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Failed to save debug log: %@", reason] actions:@[ @"OK" ] accessory:nil identifier:nil silenceable:kiTermWarningTypePersistent heading:@"Problem Saving Debug Log" window:nil];
    }

    [gDebugLogStr setString:@""];
    gDebugLogHeader = nil;
    [GetDebugLogLock() unlock];
}

void AppendPinnedDebugLogMessage(NSString *key, NSString *value, ...) {
    struct timeval tv;
    gettimeofday(&tv, NULL);

    va_list args;
    va_start(args, value);
    NSString *s = [[NSString alloc] initWithFormat:value arguments:args];
    va_end(args);

    NSString *log = [NSString stringWithFormat:@"%lld.%06lld [%@]: %@\n", (long long)tv.tv_sec, (long long)tv.tv_usec, key, s];

    [GetDebugLogLock() lock];
    if (!gPinnedMessages) {
        gPinnedMessages = [[NSMutableDictionary alloc] init];
    };
    NSMutableString *prev = gPinnedMessages[key];
    if (prev) {
        [prev appendString:log];
    } else {
        gPinnedMessages[key] = [log mutableCopy];
    }
    [GetDebugLogLock() unlock];
}

void SetPinnedDebugLogMessage(NSString *key, NSString *value, ...) {
    if (value == nil) {
        [gPinnedMessages removeObjectForKey:key];
        return;
    }
    struct timeval tv;
    gettimeofday(&tv, NULL);

    va_list args;
    va_start(args, value);
    NSString *s = [[NSString alloc] initWithFormat:value arguments:args];
    va_end(args);

    NSString *log = [NSString stringWithFormat:@"%lld.%06lld [%@]: %@\n", (long long)tv.tv_sec, (long long)tv.tv_usec, key, s];

    [GetDebugLogLock() lock];
    if (!gPinnedMessages) {
        gPinnedMessages = [[NSMutableDictionary alloc] init];
    };
    gPinnedMessages[key] = log;
    [GetDebugLogLock() unlock];
}

// Defense in depth for the always-on ring: even though callers are expected to
// avoid logging typed characters (see -[NSEvent it_redactedDescription]), a
// stray RLog(@"…%@", event) would otherwise reintroduce chars="…"/unmodchars="…"
// into a buffer the user never opted into. Scrub those values on the way in so a
// future regression cannot silently leak keystrokes. This only runs on the
// debug-logging-off path; when logging is on the caller opted in and we don't
// touch the value.
static NSString *iTermScrubRetrospectiveValue(NSString *value) {
    if ([value rangeOfString:@"chars=\""].location == NSNotFound) {
        // Fast path: the vast majority of RLog lines never mention an NSEvent.
        return value;
    }
    static NSRegularExpression *regex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Matches chars="…" and unmodchars="…" as emitted by -[NSEvent description].
        regex = [NSRegularExpression regularExpressionWithPattern:@"(unmodchars|chars)=\"[^\"]*\""
                                                          options:0
                                                            error:nil];
    });
    return [regex stringByReplacingMatchesInString:value
                                           options:0
                                             range:NSMakeRange(0, value.length)
                                      withTemplate:@"$1=\"[redacted]\""];
}

@interface iTermRedactedLogValue : NSObject
@property (nonatomic, strong) id full;
@property (nonatomic, strong) id redacted;
@end

@implementation iTermRedactedLogValue
- (NSString *)description {
    id value = gDebugLogging ? _full : _redacted;
    return [value description] ?: @"(null)";
}
@end

NSObject *RLogRedact(id full, id redacted) {
    iTermRedactedLogValue *result = [[iTermRedactedLogValue alloc] init];
    result.full = full;
    result.redacted = redacted;
    return result;
}

void RetrospectiveLogImpl(const char *file, int line, const char *function, NSString *value) {
    // When debug logging is on, behave exactly like DLog: the message lands
    // in the live debug log and we keep nothing extra in the ring.
    if (gDebugLogging) {
        DebugLogImpl(file, line, function, value);
        return;
    }
    value = iTermScrubRetrospectiveValue(value);

    struct timeval tv;
    gettimeofday(&tv, NULL);
    const char *lastSlash = strrchr(file, '/');
    if (!lastSlash) {
        lastSlash = file;
    } else {
        lastSlash++;
    }
    NSString *entry = [NSString stringWithFormat:@"%lld.%06lld %s:%d (%s): %@\n",
                       (long long)tv.tv_sec, (long long)tv.tv_usec, lastSlash, line, function, value];

    [GetDebugLogLock() lock];
    if (!gRetrospectiveLog) {
        gRetrospectiveLog = [[NSMutableArray alloc] init];
    }
    [gRetrospectiveLog addObject:entry];
    gRetrospectiveLogBytes += entry.length;
    // Evict oldest lines until back under the cap, but always keep the most
    // recent line even if it alone exceeds the cap.
    while (gRetrospectiveLogBytes > kRetrospectiveLogMaxBytes && gRetrospectiveLog.count > 1) {
        NSString *oldest = gRetrospectiveLog[0];
        gRetrospectiveLogBytes -= oldest.length;
        [gRetrospectiveLog removeObjectAtIndex:0];
    }
    [GetDebugLogLock() unlock];
#if ITERM_DEBUG
    fputs(entry.UTF8String, stderr);
#endif
}

NSString *iTermRetrospectiveLogString(void) {
    [GetDebugLogLock() lock];
    NSString *result = [gRetrospectiveLog componentsJoinedByString:@""] ?: @"";
    [GetDebugLogLock() unlock];
    return result;
}

void iTermClearRetrospectiveLog(void) {
    [GetDebugLogLock() lock];
    [gRetrospectiveLog removeAllObjects];
    gRetrospectiveLogBytes = 0;
    [GetDebugLogLock() unlock];
}

void iTermFatalError(NSString *s) {
    __assert_rtn("iTermFatalError", __FILE__, __LINE__, s.UTF8String);
}


int CDebugLogImpl(const char *file, int line, const char *function, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *stringValue = "";
    vasprintf(&stringValue, format, args);
    NSString *value = [NSString stringWithUTF8String:stringValue] ?: @"utf8 encoding problem in C string";
    free(stringValue);
    va_end(args);
    return DebugLogImpl(file, line, function, value);
}

int DebugLogImpl(const char *file, int line, const char *function, NSString* value)
{
    if (!gDebugLogging) {
        return 1;
    }
    struct timeval tv;
    gettimeofday(&tv, NULL);

    const char *lastSlash = strrchr(file, '/');
    if (!lastSlash) {
        lastSlash = file;
    } else {
        lastSlash++;
    }
    if ([iTermAdvancedSettingsModel logToSyslog]) {
        // Stream with:
        // log stream --predicate 'eventMessage contains "iTerm2DebugLog"' --level=debug
        NSString *message = [NSString stringWithFormat:@"%lld.%06lld %s:%d (%s): ",
                             (long long)tv.tv_sec, (long long)tv.tv_usec, lastSlash, line, function];
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEBUG, "iTerm2DebugLog: %{public}s", message.UTF8String);
    }

    const char *thread;
    if ([iTermGCD onMainQueue]) {
        if ([iTermGCD joined]) {
            thread = "joined";
        } else {
            thread = "main";
        }
    } else if ([iTermGCD onMutationQueue]) {
        if ([iTermGCD joined]) {
            thread = "joined";
        } else {
            thread = "mut";
        }
    } else {
        thread = "other";
    }

    // Format the whole entry up front so the only work done under the lock is
    // mutating the shared string. Everything above (timestamp, thread, syslog)
    // is thread-safe on its own and doesn't touch gDebugLogStr.
    NSString *entry = [NSString stringWithFormat:@"%lld.%06lld %s:%d (%s) %s: %@\n",
                       (long long)tv.tv_sec, (long long)tv.tv_usec, lastSlash, line, function, thread, value];

    [GetDebugLogLock() lock];
    [gDebugLogStr appendString:entry];
    // Cap in-memory use at ~200 MB (matching the Toggle Debug Logging menu tip).
    // On overflow, discard the oldest half: a debug log is captured right after
    // the bug reproduces, so the newest entries are the ones worth keeping.
    static const NSInteger kMaxLogSize = 200 * 1024 * 1024;
    if ([gDebugLogStr length] > kMaxLogSize) {
        [gDebugLogStr replaceCharactersInRange:NSMakeRange(0, kMaxLogSize / 2)
                                    withString:@"*GIANT LOG TRUNCATED*\n"];
    }
    [GetDebugLogLock() unlock];
    return 1;
}

void LogForNextCrash(const char *file, int line, const char *function, NSString* value, BOOL force) {
    static NSFileHandle *handle;
    NSFileHandle *handleToUse;
    static dispatch_once_t onceToken;
    static NSObject *object;
    dispatch_once(&onceToken, ^{
        object = [[NSObject alloc] init];
    });
    @synchronized (object) {
        static NSInteger numLines;
        if (force || (numLines % 100 == 0)) {
            static NSInteger fileNumber;
            NSString *path = [[[NSFileManager defaultManager] applicationSupportDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"log.%ld.txt", fileNumber]];
            fileNumber = (fileNumber + 1) % 3;
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
            handle = [NSFileHandle fileHandleForWritingAtPath:path];
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"yyyy-MM-dd HH:mm:ss.SSS ZZZ"
                                                                       options:0
                                                                        locale:nil];
            NSDate *date = [NSDate dateWithTimeIntervalSinceNow:-clock()/CLOCKS_PER_SEC];
            NSString *string = [NSString stringWithFormat:@"%@ %@\n", @(getpid()), [dateFormatter stringFromDate:date]];
            [handle writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
        }
        handleToUse = handle;
        numLines++;
    }

    struct timeval tv;
    gettimeofday(&tv, NULL);
    const char *lastSlash = strrchr(file, '/');
    if (!lastSlash) {
        lastSlash = file;
    } else {
        lastSlash++;
    }
    NSString *string = [NSString stringWithFormat:@"%lld.%06lld %s:%d (%s): %@\n",
                        (long long)tv.tv_sec, (long long)tv.tv_usec, lastSlash, line, function, value];
    @synchronized (object) {
        [handleToUse writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
        [handleToUse synchronizeFile];
    }

    AppendPinnedDebugLogMessage(@"CrashLogMessage", @"%@", string);
}

static void StartDebugLogging(void) {
    [GetDebugLogLock() lock];
    if (!gDebugLogging) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            iTermCallbackLogging.callback = ^(NSString *message) {
                DLog(@"%@", message);
            };
        });
        if (![iTermAdvancedSettingsModel appendToExistingDebugLog]) {
            [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:kDebugLogFilename]
                                                      error:nil];
        }
        gDebugLogStr = [[NSMutableString alloc] init];
        gDebugLogging = !gDebugLogging;
        // A new logging session re-arms every once-per-session
        // diagnostic: whatever was emitted into a previous capture
        // left with that capture.
        [gOncePerLoggingSessionKeys removeAllObjects];
        WriteDebugLogHeader();
    }
    [GetDebugLogLock() unlock];
}

static BOOL StopDebugLogging(void) {
    BOOL result = NO;
    [GetDebugLogLock() lock];
    if (gDebugLogging) {
        gDebugLogging = NO;
        FlushDebugLog();

        gDebugLogStr = nil;
        result = YES;
    }
    [GetDebugLogLock() unlock];
    return result;
}

void DLogOncePerLoggingSession(NSString *key, NSString *(^messageBlock)(void)) {
    if (!gDebugLogging) {
        return;
    }
    BOOL shouldLog = NO;
    [GetDebugLogLock() lock];
    if (gDebugLogging) {
        if (!gOncePerLoggingSessionKeys) {
            gOncePerLoggingSessionKeys = [NSMutableSet set];
        }
        if (![gOncePerLoggingSessionKeys containsObject:key]) {
            [gOncePerLoggingSessionKeys addObject:key];
            shouldLog = YES;
        }
    }
    [GetDebugLogLock() unlock];
    if (shouldLog) {
        DLog(@"%@", messageBlock());
    }
}

void TurnOnDebugLoggingSilently(void) {
    if (!gDebugLogging) {
        StartDebugLogging();
    }
}

BOOL TurnOffDebugLoggingSilently(void) {
    return StopDebugLogging();
}

void ToggleDebugLogging(void) {
    if (!gDebugLogging) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Debug Logging Enabled";
        alert.informativeText = @"Please reproduce the bug. Then toggle debug logging again to save the log.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        StartDebugLogging();
    } else {
        StopDebugLogging();
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Debug Logging Stopped";
        alert.informativeText = @"Please send /tmp/debuglog.txt to the developers.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}

void DLogC(const char *format, va_list args) {
    char *temp = NULL;
    vasprintf(&temp, format, args);
    DLog(@"%@", [NSString stringWithUTF8String:temp]);
    free(temp);
}

@implementation NSException(iTerm)

- (NSException *)it_rethrowWithMessage:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    NSDictionary *userInfo = self.userInfo;
    NSString *const stackKey = @"original stack";
    if (!userInfo[stackKey]) {
        NSMutableDictionary *temp = [userInfo mutableCopy];
        temp[stackKey] = self.callStackSymbols;
        userInfo = temp;
    }
    NSString *reason = [NSString stringWithFormat:@"%@:\n%@", string, self.reason];
    DLog(@"Rethrow name=%@ reason=%@ userInfo=%@", self.name, reason, userInfo);
    @throw [NSException exceptionWithName:self.name
                                   reason:reason
                                 userInfo:userInfo];
}

- (NSArray<NSString *> *)it_originalCallStackSymbols {
    return self.userInfo[@"original stack"];
}

- (NSString *)it_compressedDescription {
    NSString *uncompressed = [NSString stringWithFormat:@"%@:\n%@\n%@", self.name, self.reason, [self.it_originalCallStackSymbols componentsJoinedByString:@"\n"]];
    return [[[uncompressed dataUsingEncoding:NSUTF8StringEncoding] it_compressedData] stringWithBase64EncodingWithLineBreak:@""];
}

@end

