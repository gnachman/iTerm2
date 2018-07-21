//
//  iTermCPUUtilization.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/19/18.
//

#import "iTermCPUUtilization.h"
#import "iTermPublisher.h"

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


@interface iTermCPUUtilization()<iTermPublisherDelegate>
@end

@implementation iTermCPUUtilization {
    iTermCPUTicks _last;
    NSTimer *_timer;
    iTermPublisher<NSNumber *> *_publisher;
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
        _publisher = [[iTermPublisher alloc] init];
        _publisher.delegate = self;
    }
    return self;
}

- (void)addSubscriber:(id)subscriber block:(iTermCPUUtilizationObserver)block {
    [_publisher addSubscriber:subscriber block:^(NSNumber * _Nonnull payload) {
        block(payload.doubleValue);
    }];
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
    iTermCPUTicks current = [self sample];
    iTermCPUTicks delta = current;
    delta.idle -= _last.idle;
    delta.total -= _last.total;
    _last = current;

    double value = [self utilizationInDelta:delta];
    [_publisher publish:@(value)];
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

#pragma mark - iTermPublisherDelegate

- (void)publisherDidChangeNumberOfSubscribers:(iTermPublisher *)publisher {
    if (!_publisher.hasAnySubscribers) {
        [_timer invalidate];
        _timer = nil;
    } else if (!_timer) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:self.cadence
                                                  target:self
                                                selector:@selector(update)
                                                userInfo:nil
                                                 repeats:YES];
    }
}
@end
