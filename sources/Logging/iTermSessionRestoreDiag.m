//
//  iTermSessionRestoreDiag.m
//  iTerm2
//

#import "iTermSessionRestoreDiag.h"

#import "DebugLogging.h"
#import "NSFileManager+iTerm.h"

#import <unistd.h>

static const unsigned long long kSessionRestoreDiagMaxBytes = 256ULL * 1024ULL;
static const unsigned long long kSessionRestoreDiagRetainBytes = 128ULL * 1024ULL;

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

// queue
static void RotateIfNeededLocked(NSString *path) {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attrs) {
        return;
    }
    const unsigned long long size = [attrs fileSize];
    if (size <= kSessionRestoreDiagMaxBytes) {
        return;
    }
    NSData *all = [NSData dataWithContentsOfFile:path];
    if (all.length <= kSessionRestoreDiagRetainBytes) {
        return;
    }
    NSData *tail = [all subdataWithRange:NSMakeRange(all.length - (NSUInteger)kSessionRestoreDiagRetainBytes,
                                                     (NSUInteger)kSessionRestoreDiagRetainBytes)];
    // Advance past the first partial line so the rotated file starts on a line boundary.
    const char *bytes = tail.bytes;
    NSUInteger start = NSNotFound;
    for (NSUInteger i = 0; i < tail.length; i++) {
        if (bytes[i] == '\n') {
            start = i + 1;
            break;
        }
    }
    if (start != NSNotFound && start < tail.length) {
        tail = [tail subdataWithRange:NSMakeRange(start, tail.length - start)];
    }
    NSString *header = [NSString stringWithFormat:@"--- rotated %@ ---\n",
                        [NSDate date]];
    NSMutableData *out = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [out appendData:tail];
    [out writeToFile:path atomically:YES];
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

        // Ensure the parent directory exists. applicationSupportDirectoryWithoutCreating
        // returns the path even if the directory is missing.
        NSString *dir = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        RotateIfNeededLocked(path);

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

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!fh) {
                return;
            }
        }
        @try {
            [fh seekToEndOfFile];
            [fh writeData:data];
        } @catch (NSException *exc) {
            // Best-effort: a write failure here must never break iTerm2.
        }
        @try {
            [fh closeFile];
        } @catch (NSException *exc) {
        }
    });
}
