//
//  DebugLogging.m
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import "DebugLogging.h"
#import "FileProviderService/FileProviderService-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "NSData+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import <Cocoa/Cocoa.h>

#include <sys/time.h>
#include <sys/types.h>
#include <sys/sysctl.h>

static NSString *const kDebugLogFilename = @"/tmp/debuglog.txt";
static NSString* gDebugLogHeader = nil;
static NSMutableString* gDebugLogStr = nil;

static NSMutableDictionary *gPinnedMessages;
BOOL gDebugLogging = NO;

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
        [infos addObject:NSStringFromRect(screen.frame)];
    }
    return [infos componentsJoinedByString:@"     "];
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

static void WriteDebugLogHeader(void) {
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
    gDebugLogHeader = [header copy];
}

static void WriteDebugLogFooter(void) {
  NSMutableString *windows = [NSMutableString string];
  for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
      AppendWindowDescription(window, windows);
  }
  NSString *footer = [NSString stringWithFormat:
                      @"------ BEGIN FOOTER -----\n"
                      @"Screens: %@\n"
                      @"Windows: %@\n"
                      @"Ordered windows: %@\n",
                      iTermScreensInfo(),
                      windows,
                      [(iTermApplication *)NSApp orderedWindowsPlusAllHotkeyPanels]];
  [gDebugLogStr appendString:footer];
}

static void FlushDebugLog(void) {
    [GetDebugLogLock() lock];
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
    if (gDebugLogging) {
        struct timeval tv;
        gettimeofday(&tv, NULL);

        [GetDebugLogLock() lock];
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
        static const NSInteger kMaxLogSize = 1000000000;
        if ([gDebugLogStr length] > kMaxLogSize) {
            [gDebugLogStr replaceCharactersInRange:NSMakeRange(0, kMaxLogSize / 2)
                                        withString:@"*GIANT LOG TRUNCATED*\n"];
        }
        [GetDebugLogLock() unlock];
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

    AppendPinnedDebugLogMessage(@"CrashLogMessage", string);
}

static void StartDebugLogging(void) {
    [GetDebugLogLock() lock];
    if (!gDebugLogging) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            FileProviderLogging.callback = ^(NSString *message) {
                DLog(@"%@", message);
            };
        });
        if (![iTermAdvancedSettingsModel appendToExistingDebugLog]) {
            [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:kDebugLogFilename]
                                                      error:nil];
        }
        gDebugLogStr = [[NSMutableString alloc] init];
        gDebugLogging = !gDebugLogging;
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
    @throw [NSException exceptionWithName:self.name
                                   reason:[NSString stringWithFormat:@"%@:\n%@", string, self.reason]
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

