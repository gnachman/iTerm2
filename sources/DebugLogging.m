//
//  DebugLogging.m
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import "DebugLogging.h"
#import "NSView+RecursiveDescription.h"
#import <Cocoa/Cocoa.h>

#include <sys/time.h>

static NSString *const kDebugLogFilename = @"/tmp/debuglog.txt";
static NSString* gDebugLogHeader = nil;
static NSMutableString* gDebugLogStr = nil;
static NSRecursiveLock *gDebugLogLock = nil;
BOOL gDebugLogging = NO;

static void WriteDebugLogHeader() {
  NSMutableString *windows = [NSMutableString string];
  for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
    [windows appendFormat:@"\nWindow %@, frame=%@. isMain=%d  isKey=%d  isVisible=%d\n%@\n",
     window,
     [NSValue valueWithRect:window.frame],
     (int)[window isMainWindow],
     (int)[window isKeyWindow],
     (int)[window isVisible],
     [window.contentView iterm_recursiveDescription]];
  }
  NSString *header = [NSString stringWithFormat:
                      @"iTerm2 version: %@\n"
                      @"Date: %@ (%lld)\n"
                      @"Key window: %@\n"
                      @"Windows: %@\n"
                      @"------ END HEADER ------\n\n",
                      [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"],
                      [NSDate date],
                      (long long)[[NSDate date] timeIntervalSince1970],
                      [[NSApplication sharedApplication] keyWindow],
                      windows];
  [gDebugLogHeader release];
  gDebugLogHeader = [header copy];
}

static void WriteDebugLogFooter() {
  NSMutableString *windows = [NSMutableString string];
  for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
    [windows appendFormat:@"\nWindow %@, frame=%@. isMain=%d  isKey=%d\n%@\n",
     window,
     [NSValue valueWithRect:window.frame],
     (int)[window isMainWindow],
     (int)[window isKeyWindow],
     [window.contentView iterm_recursiveDescription]];
  }
  NSString *footer = [NSString stringWithFormat:
                      @"------ BEGIN FOOTER -----\n"
                      @"Windows: %@\n",
                      windows];
  [gDebugLogStr appendString:footer];
}

static void FlushDebugLog() {
    [gDebugLogLock lock];
    NSMutableString *log = [NSMutableString string];
    [log appendString:gDebugLogHeader ?: @""];
    WriteDebugLogFooter();
    [log appendString:gDebugLogStr ?: @""];

    [log writeToFile:kDebugLogFilename atomically:NO encoding:NSUTF8StringEncoding error:nil];

    [gDebugLogStr setString:@""];
    [gDebugLogHeader release];
    gDebugLogHeader = nil;
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

static void StartDebugLogging() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gDebugLogLock = [[NSRecursiveLock alloc] init];
    });
    [gDebugLogLock lock];
    [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:kDebugLogFilename]
                                              error:nil];
    gDebugLogStr = [[NSMutableString alloc] init];
    gDebugLogging = !gDebugLogging;
    WriteDebugLogHeader();
    [gDebugLogLock unlock];
}

void TurnOnDebugLoggingSilently(void) {
    if (!gDebugLogging) {
        StartDebugLogging();
    }
}

void ToggleDebugLogging(void) {
    if (!gDebugLogging) {
        NSRunAlertPanel(@"Debug Logging Enabled",
                        @"Please reproduce the bug. Then toggle debug logging again to save the log.",
                        @"OK", nil, nil);
        StartDebugLogging();
    } else {
        [gDebugLogLock lock];
        gDebugLogging = !gDebugLogging;
        FlushDebugLog();

        NSRunAlertPanel(@"Debug Logging Stopped",
                        @"Please send /tmp/debuglog.txt to the developers.",
                        @"OK", nil, nil);
        [gDebugLogStr release];
        [gDebugLogLock unlock];
    }
}
