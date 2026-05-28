//
//  iTermSessionRestoreDiag.m
//  iTerm2
//

#import "iTermSessionRestoreDiag.h"

#import "DebugLogging.h"
#import "NSFileManager+iTerm.h"

#import <unistd.h>

// Full-trace diagnostic for issue 12866. The log is append-only and never
// rotated or truncated: we would rather grow a large file than risk dropping
// the one event that explains the bug. The user can delete the file manually
// once 12866 is resolved.

static dispatch_queue_t SessionRestoreDiagQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.iterm2.session-restore-diag", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSString *SessionRestoreDiagPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *dir = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutCreating];
        if (dir.length == 0) {
            return;
        }
        path = [[dir stringByAppendingPathComponent:@"SessionRestoreDiag.log"] copy];
    });
    return path;
}

// Everything below the queue comment runs on SessionRestoreDiagQueue, so the
// cached handle and byte counter need no further synchronization.

// queue
static NSFileHandle *gHandle;

// queue
static void CloseHandleLocked(void) {
    if (!gHandle) {
        return;
    }
    @try {
        [gHandle closeFile];
    } @catch (NSException *exc) {
    }
    gHandle = nil;
}

// queue
static void OpenHandleLocked(NSString *path) {
    if (gHandle) {
        return;
    }
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    }
    gHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    @try {
        [gHandle seekToEndOfFile];
    } @catch (NSException *exc) {
    }
}

void iTermSessionRestoreDiagLog(NSString *format, ...) {
    if (!format) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // Capture pid and timestamp on the caller's thread so the queued write
    // reflects when the event actually happened, not when the queue drained.
    const pid_t pid = getpid();
    NSDate *when = [NSDate date];

    dispatch_async(SessionRestoreDiagQueue(), ^{
        NSString *path = SessionRestoreDiagPath();
        if (path.length == 0) {
            return;
        }

        OpenHandleLocked(path);
        if (!gHandle) {
            return;
        }

        static NSDateFormatter *fmt;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            fmt = [[NSDateFormatter alloc] init];
            fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
            fmt.timeZone = [NSTimeZone localTimeZone];
        });
        NSString *stamp = [fmt stringFromDate:when];

        NSString *line = [NSString stringWithFormat:@"%@ pid=%d %@\n", stamp, pid, body];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (data.length == 0) {
            return;
        }
        @try {
            [gHandle writeData:data];
        } @catch (NSException *exc) {
            // Best-effort: a write failure here must never break iTerm2.
            CloseHandleLocked();
        }
    });
}
