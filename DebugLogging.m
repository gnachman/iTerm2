//
//  DebugLogging.m
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import "DebugLogging.h"
#import <Cocoa/Cocoa.h>
#include <sys/time.h>

NSMutableString* gDebugLogStr = nil;
NSMutableString* gDebugLogStr2 = nil;
BOOL gDebugLogging = NO;
int gDebugLogFile = -1;

static void SwapDebugLog() {
    NSMutableString* temp;
    temp = gDebugLogStr;
    gDebugLogStr = gDebugLogStr2;
    gDebugLogStr2 = temp;
}

static void FlushDebugLog() {
    NSData* data = [gDebugLogStr dataUsingEncoding:NSUTF8StringEncoding];
    size_t written = write(gDebugLogFile, [data bytes], [data length]);
    assert(written == [data length]);
    [gDebugLogStr setString:@""];
}

int DebugLogImpl(const char *file, int line, const char *function, NSString* value)
{
    if (gDebugLogging) {
        struct timeval tv;
        gettimeofday(&tv, NULL);

        [gDebugLogStr appendFormat:@"%lld.%08lld %s:%d (%s): ", (long long)tv.tv_sec, (long long)tv.tv_usec, file, line, function];
        [gDebugLogStr appendString:value];
        [gDebugLogStr appendString:@"\n"];
        if ([gDebugLogStr length] > 100000000) {
            SwapDebugLog();
            [gDebugLogStr2 setString:@""];
        }
    }
    return 1;
}

void ToggleDebugLogging() {
    if (!gDebugLogging) {
        NSRunAlertPanel(@"Debug Logging Enabled",
                        @"Writing to /tmp/debuglog.txt",
                        @"OK", nil, nil);
        gDebugLogFile = open("/tmp/debuglog.txt", O_TRUNC | O_CREAT | O_WRONLY, S_IRUSR | S_IWUSR);
        gDebugLogStr = [[NSMutableString alloc] init];
        gDebugLogStr2 = [[NSMutableString alloc] init];
        gDebugLogging = !gDebugLogging;
    } else {
        gDebugLogging = !gDebugLogging;
        SwapDebugLog();
        FlushDebugLog();
        SwapDebugLog();
        FlushDebugLog();

        close(gDebugLogFile);
        gDebugLogFile=-1;
        NSRunAlertPanel(@"Debug Logging Stopped",
                        @"Please compress and send /tmp/debuglog.txt to the developers.",
                        @"OK", nil, nil);
        [gDebugLogStr release];
        [gDebugLogStr2 release];
    }
}