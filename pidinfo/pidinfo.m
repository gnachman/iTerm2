//
//  pidinfo.m
//  pidinfo
//
//  Created by George Nachman on 1/11/20.
//

#import "pidinfo.h"

#import "iTermFileDescriptorServerShared.h"
#include <libproc.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <syslog.h>
#include <time.h>

//#define ENABLE_RANDOM_WEDGING 1
//#define ENABLE_VERY_VERBOSE_LOGGING 1
//#define ENABLE_SLOW_ROOT 1

#if ENABLE_RANDOM_WEDGING || ENABLE_VERY_VERBOSE_LOGGING || ENABLE_SLOW_ROOT
#warning DO NOT SUBMIT - DEBUG SETTING ENABLED
#endif

@implementation pidinfo {
    dispatch_queue_t _queue;
    int _numWedged;
    _Atomic int _count;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.iterm2.pidinfo", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)runShellScript:(NSString *)script
                 shell:(NSString *)shell
             withReply:(void (^)(NSData * _Nullable, NSData * _Nullable, int))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil, nil, 0);
            syslog(LOG_WARNING, "pidinfo wedged");
            return;
        }
        [self reallyRunShellScript:script shell:shell completion:^(NSData *output,
                                                                   NSData *error,
                                                                   int status) {
            if (!completion()) {
                syslog(LOG_INFO, "runShellScript finished after timing out");
                return;
            }
            reply(output, error, status);
        }];
    }];
}

- (NSString *)temporaryFileNameWithPrefix:(NSString *)prefix suffix:(NSString *)suffix {
    assert(strlen(suffix.UTF8String) < INT_MAX);
    NSString *template = [NSString stringWithFormat:@"%@XXXXXX%@", prefix ?: @"", suffix ?: @""];
    NSString *tempFileTemplate =
        [NSTemporaryDirectory() stringByAppendingPathComponent:template];
    const char *tempFileTemplateCString =
        [tempFileTemplate fileSystemRepresentation];
    char *tempFileNameCString = strdup(tempFileTemplateCString);
    int fileDescriptor = mkstemps(tempFileNameCString, (int)strlen(suffix.UTF8String));

    if (fileDescriptor == -1) {
        free(tempFileNameCString);
        return nil;
    }
    close(fileDescriptor);
    NSString *filename = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempFileNameCString
                                                                                     length:strlen(tempFileNameCString)];
    free(tempFileNameCString);
    return filename;
}

static int MakeNonBlocking(int fd) {
    int flags = fcntl(fd, F_GETFL);
    int rc = 0;
    do {
        rc = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    } while (rc == -1 && errno == EINTR);
    return rc == -1;
}

- (void)reallyRunShellScript:(NSString *)script shell:(NSString *)shell completion:(void (^)(NSData * _Nullable, NSData * _Nullable, int))completion {
    @try {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = shell;

        NSString *tempfile = [self temporaryFileNameWithPrefix:@"iTerm2-script" suffix:@"sh"];
        NSError *error = nil;
        [script writeToFile:tempfile atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            completion(nil, nil, 0);
            return;
        }
        chmod(tempfile.UTF8String, 0700);
        task.arguments = @[ @"-c", tempfile ];

        NSPipe *stdinPipe = [[NSPipe alloc] init];
        NSPipe *outputPipe = [[NSPipe alloc] init];
        NSPipe *errorPipe = [[NSPipe alloc] init];
        task.standardInput = stdinPipe;
        task.standardOutput = outputPipe;
        task.standardError = errorPipe;

        [task launch];

        NSFileHandle *outputHandle = outputPipe.fileHandleForReading;
        NSFileHandle *errorHandle = errorPipe.fileHandleForReading;
        NSMutableData *accumulatedOutput = [[NSMutableData alloc] init];
        NSMutableData *accumulatedError = [[NSMutableData alloc] init];

        MakeNonBlocking(outputHandle.fileDescriptor);
        MakeNonBlocking(errorHandle.fileDescriptor);

        while (1) {
            int fds[2] = { outputHandle.fileDescriptor, errorHandle.fileDescriptor };
            int results[2] = { 0, 0 };
            iTermSelect(fds, sizeof(fds) / sizeof(*fds), results, 0);
            if (results[0]) {
                NSData *data = outputHandle.availableData;
                if (data.length == 0) {
                    break;
                }
                [accumulatedOutput appendData:data];
            }
            if (results[1]) {
                NSData *data = errorHandle.availableData;
                if (data.length == 0) {
                    break;
                }
                [accumulatedError appendData:data];
            }
            if (accumulatedOutput.length > 1048576 ||
                accumulatedError.length > 1048576) {
                [task terminate];
                break;
            }
        }

        [task waitUntilExit];
        completion(accumulatedOutput, accumulatedError, task.terminationStatus);
    } @catch (NSException *exception) {
        completion(nil, nil, 0);
    }

}

- (void)getProcessInfoForProcessID:(NSNumber *)pid
                            flavor:(NSNumber *)flavor
                               arg:(NSNumber *)arg
                              size:(NSNumber *)size
                             reqid:(int)reqid
                         withReply:(void (^)(NSNumber *, NSData *))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^completion)(void)) {
        if (!shouldPerform) {
            reply(@-1, [NSData data]);
            syslog(LOG_WARNING,
                   "pidinfo %d detected wedged proc_pidinfo for process ID %d, flavor %d. Count is %d.",
                   reqid, pid.intValue, flavor.intValue, self->_numWedged);
            return;
        }
        [self reallyGetProcessInfoForProcessID:pid flavor:flavor arg:arg size:size reqid:reqid withReply:^(NSNumber *number, NSData *data) {
            if (!completion()) {
                syslog(LOG_INFO, "pidinfo reqid %d finished after timing out", reqid);
                return;
            }
            reply(number, data);
        }];
    }];
}

- (void)checkIfDirectoryExists:(NSString *)directory withReply:(void (^)(NSNumber * _Nullable))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil);
            return;
        }
        BOOL isDirectory = NO;
        const BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&isDirectory];
        if (!completion()) {
            return;
        }
        NSNumber *result = @(exists && isDirectory);
        reply(result);
    }];
}

// Usage:
// [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^completion)(void)) {
//   if (!shouldPerform) {
//     reply(FAILURE);
//     return;
//   }
//   [self doSlowOperationWithCompletion:^{
//     if (!completion()) {
//       return;
//     }
//     reply(SUCCESS);
//   }];
// }];
- (void)performRiskyBlock:(void (^)(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)))block {
    const NSTimeInterval timeout = 10;
    __block _Atomic BOOL done = NO;
    __block _Atomic BOOL wedged = NO;
    _count++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(timeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (done) {
            return;
        }
        wedged = YES;
        block(NO, nil);
        self->_numWedged++;

        if (self->_numWedged > 128) {
            syslog(LOG_ERR, "There are more than 128 wedged threads. Restarting.");
            _exit(0);
        }
    });
    dispatch_async(_queue, ^{
        block(YES, ^{
            self->_count--;
            if (wedged) {
              // Finished after timeout.
              self->_numWedged--;
              syslog(LOG_INFO,
                     "pidinfo detected slow but not wedged proc_pidinfo. Count is now %d.",
                     self->_numWedged);
                return NO;
            }
            done = YES;
            return YES;
        });
    });
}

- (void)handshakeWithReply:(void (^)(void))reply {
    reply();
}

#if ENABLE_VERY_VERBOSE_LOGGING
static double TimespecToSeconds(struct timespec* ts) {
    return (double)ts->tv_sec + (double)ts->tv_nsec / 1000000000.0;
}
#endif

#if ENABLE_SLOW_ROOT
- (void)maybeDelayWithFlavor:(int)flavor
                       reqid:(int)reqid
                      result:(NSData *)result {
    if (flavor != PROC_PIDVNODEPATHINFO) {
        return;
    }
    if (result.length != sizeof(struct proc_vnodepathinfo)) {
        return;
    }
    struct proc_vnodepathinfo *vpiPtr = (struct proc_vnodepathinfo *)result.bytes;
    NSString *rawDir = [NSString stringWithUTF8String:vpiPtr->pvi_cdir.vip_path];
    if (![rawDir isEqualToString:@"/"]) {
        return;
    }
    syslog(LOG_ERR, "pidinfo %d responding slowly because directory is root.", reqid);
    [NSThread sleepForTimeInterval:0.25];
}
#endif

- (void)reallyGetProcessInfoForProcessID:(NSNumber *)pid
                                  flavor:(NSNumber *)flavor
                                     arg:(NSNumber *)arg
                                    size:(NSNumber *)size
                                   reqid:(int)reqid
                               withReply:(void (^)(NSNumber *, NSData *))reply {
    if (size.doubleValue > 1024 * 1024 || size.doubleValue < 0) {
        dispatch_async(dispatch_get_main_queue(), ^{ reply(@-2, [NSData data]); });
        return;
    }
    const int safeLength = size.intValue;
    NSMutableData *result = [NSMutableData dataWithLength:size.unsignedIntegerValue];
#if ENABLE_VERY_VERBOSE_LOGGING
    syslog(LOG_DEBUG, "pidinfo %d will call proc_pidinfo(pid=%d, flavor=%d). wedged=%d count=%d",
           reqid, pid.intValue, flavor.intValue, _numWedged, _count);
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
#endif
#if ENABLE_RANDOM_WEDGING
    if (random() % 10 == 0) {
        syslog(LOG_WARNING, "pidinfo will wedge this thread intentionally.");
        while (1) {
            sleep(1);
        }
    }
#endif
    const int rc = proc_pidinfo(pid.intValue,
                                flavor.intValue,
                                arg.unsignedIntegerValue,
                                (size.integerValue > 0) ? result.mutableBytes : NULL,
                                safeLength);
    if (rc <= 0) {
        const int copyOfErrno = errno;
        NSString *message = [NSString stringWithFormat:@"proc_pidinfo flavor=%@ pid=%@ arg=%@ size=%@ returned %@ with errno %@",
                             flavor, pid, arg, size, @(rc), @(copyOfErrno)];
        syslog(LOG_WARNING, "%s", message.UTF8String);
    }
#if ENABLE_SLOW_ROOT
    if (rc > 0) {
        [self maybeDelayWithFlavor:flavor.intValue
                             reqid:reqid
                            result:result];
    }
#endif
    struct timespec end;
    clock_gettime(CLOCK_MONOTONIC, &end);
#if ENABLE_VERY_VERBOSE_LOGGING
    const int ms = (TimespecToSeconds(&end)-TimespecToSeconds(&start)) * 1000;
    syslog(LOG_DEBUG, "pidinfo %d finished proc_pidinfo(pid=%d, flavor=%d) in %dms",
           reqid, pid.intValue, flavor.intValue, ms);
#endif
    dispatch_async(dispatch_get_main_queue(), ^{ reply(@(rc), result); });
}

@end

