//
//  pidinfo.m
//  pidinfo
//
//  Created by George Nachman on 1/11/20.
//

#import "pidinfo.h"
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

- (void)getProcessInfoForProcessID:(NSNumber *)pid
                            flavor:(NSNumber *)flavor
                               arg:(NSNumber *)arg
                              size:(NSNumber *)size
                             reqid:(int)reqid
                         withReply:(void (^)(NSNumber *, NSData *))reply {
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
        reply(@-1, [NSData data]);
        self->_numWedged++;
        syslog(LOG_WARNING,
               "pidinfo %d detected wedged proc_pidinfo for process ID %d, flavor %d. Count is %d.",
               reqid, pid.intValue, flavor.intValue, self->_numWedged);

        if (self->_numWedged > 128) {
            syslog(LOG_ERR, "pidinfo %d has more than 128 wedged threads. Restarting.", reqid);
            _exit(0);
        }
    });
    dispatch_async(_queue, ^{
        [self reallyGetProcessInfoForProcessID:pid flavor:flavor arg:arg size:size reqid:reqid withReply:^(NSNumber *number, NSData *data) {
            self->_count--;
            if (wedged) {
              // Finished after timeout.
              self->_numWedged--;
              syslog(LOG_INFO,
                     "pidinfo %d detected slow but not wedged proc_pidinfo. Count is now %d.",
                     reqid, self->_numWedged);
                return;
            }
            done = YES;
            reply(number, data);
        }]; 
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

