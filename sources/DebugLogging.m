//
//  DebugLogging.m
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "NSFileManager+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import <Cocoa/Cocoa.h>

#include <sys/time.h>

static NSString *const kDebugLogFilename = @"/tmp/debuglog.txt";
static NSString* gDebugLogHeader = nil;
static NSMutableString* gDebugLogStr = nil;
static NSRecursiveLock *gDebugLogLock = nil;

static NSMutableDictionary *gPinnedMessages;
BOOL gDebugLogging = NO;

static void AppendWindowDescription(NSWindow *window, NSMutableString *windows) {
    [windows appendFormat:@"\nWindow %@\n%@\n",
     window,
     [window.contentView iterm_recursiveDescription]];
}

static void WriteDebugLogHeader() {
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
                        @"Key window: %@\n"
                        @"Windows: %@\n"
                        @"Ordered windows: %@\n"
                        @"Pinned messages: %@\n"
                        @"------ END HEADER ------\n\n",
                        [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"],
                        [NSDate date],
                        (long long)[[NSDate date] timeIntervalSince1970],
                        [[NSApplication sharedApplication] keyWindow],
                        windows,
                        [(iTermApplication *)NSApp orderedWindowsPlusAllHotkeyPanels],
                        pinnedMessages];
    [gDebugLogHeader release];
    gDebugLogHeader = [header copy];
}

static void WriteDebugLogFooter() {
  NSMutableString *windows = [NSMutableString string];
  for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
      AppendWindowDescription(window, windows);
  }
  NSString *footer = [NSString stringWithFormat:
                      @"------ BEGIN FOOTER -----\n"
                      @"Windows: %@\n"
                      @"Ordered windows: %@\n",
                      windows,
                      [(iTermApplication *)NSApp orderedWindowsPlusAllHotkeyPanels]];
  [gDebugLogStr appendString:footer];
}

static void FlushDebugLog() {
    [gDebugLogLock lock];
    NSMutableString *log = [NSMutableString string];
    [log appendString:gDebugLogHeader ?: @""];
    WriteDebugLogFooter();
    [log appendString:gDebugLogStr ?: @""];

    if ([iTermAdvancedSettingsModel appendToExistingDebugLog] &&
        [[NSFileManager defaultManager] fileExistsAtPath:kDebugLogFilename]) {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:kDebugLogFilename];
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[log dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        [log writeToFile:kDebugLogFilename atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }

    [gDebugLogStr setString:@""];
    [gDebugLogHeader release];
    gDebugLogHeader = nil;
    [gDebugLogLock unlock];
}

void AppendPinnedDebugLogMessage(NSString *key, NSString *value, ...) {
    struct timeval tv;
    gettimeofday(&tv, NULL);

    va_list args;
    va_start(args, value);
    NSString *s = [[[NSString alloc] initWithFormat:value arguments:args] autorelease];
    va_end(args);

    NSString *log = [NSString stringWithFormat:@"%lld.%06lld [%@]: %@\n", (long long)tv.tv_sec, (long long)tv.tv_usec, key, s];

    [gDebugLogLock lock];
    if (!gPinnedMessages) {
        gPinnedMessages = [[NSMutableDictionary alloc] init];
    };
    NSMutableString *prev = gPinnedMessages[key];
    if (prev) {
        [prev appendString:log];
    } else {
        gPinnedMessages[key] = [[log mutableCopy] autorelease];
    }
    [gDebugLogLock unlock];
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
    NSString *s = [[[NSString alloc] initWithFormat:value arguments:args] autorelease];
    va_end(args);

    NSString *log = [NSString stringWithFormat:@"%lld.%06lld [%@]: %@\n", (long long)tv.tv_sec, (long long)tv.tv_usec, key, s];

    [gDebugLogLock lock];
    if (!gPinnedMessages) {
        gPinnedMessages = [[NSMutableDictionary alloc] init];
    };
    gPinnedMessages[key] = log;
    [gDebugLogLock unlock];
}

int DebugLogImpl(const char *file, int line, const char *function, NSString* value)
{
    if (gDebugLogging) {
        struct timeval tv;
        gettimeofday(&tv, NULL);

        [gDebugLogLock lock];
        const char *lastSlash = strrchr(file, '/');
        if (!lastSlash) {
            lastSlash = file;
        } else {
            lastSlash++;
        }
        [gDebugLogStr appendFormat:@"%lld.%06lld %s:%d (%s): ",
            (long long)tv.tv_sec, (long long)tv.tv_usec, lastSlash, line, function];
        [gDebugLogStr appendString:value];
        [gDebugLogStr appendString:@"\n"];
        static const NSInteger kMaxLogSize = 100000000;
        if ([gDebugLogStr length] > kMaxLogSize) {
            [gDebugLogStr replaceCharactersInRange:NSMakeRange(0, kMaxLogSize / 2)
                                        withString:@"*GIANT LOG TRUNCATED*\n"];
        }
        [gDebugLogLock unlock];
    }
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
            handle = [[NSFileHandle fileHandleForWritingAtPath:path] retain];
            NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
            dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"yyyy-MM-dd HH:mm:ss.SSS ZZZ"
                                                                       options:0
                                                                        locale:nil];
            NSDate *date = [NSDate dateWithTimeIntervalSinceNow:-clock()/CLOCKS_PER_SEC];
            NSString *string = [NSString stringWithFormat:@"%@ %@\n", @(getpid()), [dateFormatter stringFromDate:date]];
            [handle writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
        }
        handleToUse = [[handle retain] autorelease];
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
    }

    AppendPinnedDebugLogMessage(@"CrashLogMessage", string);
}

static void StartDebugLogging() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gDebugLogLock = [[NSRecursiveLock alloc] init];
    });
    [gDebugLogLock lock];
    if (!gDebugLogging) {
        if (![iTermAdvancedSettingsModel appendToExistingDebugLog]) {
            [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:kDebugLogFilename]
                                                      error:nil];
        }
        gDebugLogStr = [[NSMutableString alloc] init];
        gDebugLogging = !gDebugLogging;
        WriteDebugLogHeader();
    }
    [gDebugLogLock unlock];
}

static BOOL StopDebugLogging() {
    BOOL result = NO;
    [gDebugLogLock lock];
    if (gDebugLogging) {
        gDebugLogging = NO;
        FlushDebugLog();

        [gDebugLogStr release];
        result = YES;
    }
    [gDebugLogLock unlock];
    return result;
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
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Debug Logging Enabled";
        alert.informativeText = @"Please reproduce the bug. Then toggle debug logging again to save the log.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        StartDebugLogging();
    } else {
        StopDebugLogging();
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Debug Logging Stopped";
        alert.informativeText = @"Please send /tmp/debuglog.txt to the developers.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}
