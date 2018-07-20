//
//  iTermCPUUtilization.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/19/18.
//

#import "iTermCPUUtilization.h"

#include <mach/mach.h>
#include <mach/mach_init.h>
#include <mach/mach_error.h>
#include <mach/mach_host.h>
#include <mach/mach_time.h>
#include <mach/vm_map.h>

typedef struct {
    double idle;
    double total;
} iTermCPUTicks;


@implementation iTermCPUUtilization {
    iTermCPUTicks _last;
    NSHashTable<iTermCPUUtilizationObserver> *_observers;
    NSTimer *_timer;
    uint64_t _updateTime;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cadence = 1;
        _observers = [[NSHashTable alloc] initWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPersonality capacity:1];
    }
    return self;
}

- (void)addSubscriber:(iTermCPUUtilizationObserver)block {
    if (_observers.count == 0) {
        __weak __typeof(self) weakSelf = self;
        _timer = [NSTimer scheduledTimerWithTimeInterval:self.cadence repeats:YES block:^(NSTimer * _Nonnull timer) {
            [weakSelf update];
        }];
    }
    [_observers addObject:block];
}

#pragma mark - Private

- (double)utilizationInDelta:(iTermCPUTicks)delta {
    if (_last.total == 0) {
        return 0;
    } else {
        return 1.0 - delta.idle / delta.total;
    }
}

- (void)update {
    _updateTime = mach_absolute_time();
    iTermCPUTicks current = [self sample];
    iTermCPUTicks delta = current;
    delta.idle -= _last.idle;
    delta.total -= _last.total;
    _last = current;

    double value = [self utilizationInDelta:delta];
    for (iTermCPUUtilizationObserver observer in _observers) {
        if (observer) {
            observer(value);
        }
    }
    if (_observers.count == 0) {
        [_timer invalidate];
        _timer = nil;
    }
}

- (NSTimeInterval)timeIntervalSinceLastUpdate {
    if (_updateTime == 0) {
        return INFINITY;
    }

    int64_t now = mach_absolute_time();
    const int64_t elapsed = now - _updateTime;
    static mach_timebase_info_data_t sTimebaseInfo;
    if (sTimebaseInfo.denom == 0) {
        mach_timebase_info(&sTimebaseInfo);
    }

    double nanoseconds = elapsed * sTimebaseInfo.numer / sTimebaseInfo.denom;
    return nanoseconds / 1000000000.0;
}

- (iTermCPUTicks)sample {
    host_cpu_load_info_data_t cpuinfo;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    kern_return_t rc = host_statistics(mach_host_self(),
                                       HOST_CPU_LOAD_INFO,
                                       (host_info_t)&cpuinfo,
                                       &count);
    iTermCPUTicks result = { 0, 0 };
    if (rc != KERN_SUCCESS) {
        return result;
    }

    for (int i = 0; i < CPU_STATE_MAX; i++) {
        result.total += cpuinfo.cpu_ticks[i];
    }
    result.idle = cpuinfo.cpu_ticks[CPU_STATE_IDLE];
    return result;
}

@end
