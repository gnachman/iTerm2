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


@implementation iTermLocalCPUUtilizationPublisher {
    NSTimer *_timer;
    iTermCPUTicks _last;
}

+ (instancetype)sharedInstance {
    static iTermLocalCPUUtilizationPublisher *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermLocalCPUUtilizationPublisher alloc] initWithCapacity:120];
    });
    return instance;
}

- (void)addSubscriber:(id)subscriber block:(void (^)(id _Nonnull))block {
    [super addSubscriber:subscriber block:block];
    [self updateTimer];
}

- (void)removeSubscriber:(id)subscriber {
    [super removeSubscriber:subscriber];
    [self updateTimer];
}

- (void)updateTimer {
    if (!self.hasAnySubscribers) {
        [_timer invalidate];
        _timer = nil;
        return;
    }
    if (_timer) {
        return;
    }

    _timer = [NSTimer scheduledTimerWithTimeInterval:1
                                              target:self
                                            selector:@selector(timerDidFire:)
                                            userInfo:nil
                                             repeats:YES];
}

- (void)timerDidFire:(NSTimer *)timer {
    iTermCPUTicks current = [self sample];
    iTermCPUTicks delta = current;
    delta.idle -= _last.idle;
    delta.total -= _last.total;
    _last = current;

    double value = [self utilizationInDelta:delta];
    if (value != value) {
        return;
    }
    [self publish:@(value)];
}

- (double)utilizationInDelta:(iTermCPUTicks)delta {
    if (_last.total == 0) {
        return 0;
    } else {
        return 1.0 - delta.idle / delta.total;
    }
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

#pragma mark -

@interface iTermCPUUtilization()
@property (nonatomic, copy) NSString *sessionID;
@end


// The design:
//
// Source publisher:                  iTermCPUUtilization:  Router:            Consumer:
// One per data source                One per session       One per session    One per data sink
//
// [Local publisher singleton] -----> [timer fires] -----> router ----------> consumer
//                              \                                  `--------> consumer
//                               `--> [timer fires] -----> router ----------> consumer
//                                                                 `--------> consumer
// [example1.com publisher] --------> [timer fires] -----> router ----------> consumer
//                                                                 `--------> consumer
// [example2.com publisher] --------> [timer fires] -----> router ----------> consumer
//                                                                 `--------> consumer
@implementation iTermCPUUtilization {
    NSTimer *_timer;
    iTermPublisher<NSNumber *> *_publisher;
    iTermPublisher<NSNumber *> *_router;
}

+ (NSMutableDictionary<NSString *, iTermCPUUtilization *> *)sessionInstances {
    static NSMutableDictionary<NSString *, iTermCPUUtilization *> *gSessionInstances;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSessionInstances = [NSMutableDictionary dictionary];
    });
    return gSessionInstances;
}

+ (instancetype)instanceForSessionID:(NSString *)sessionID {
    iTermCPUUtilization *instance = self.sessionInstances[sessionID];
    if (instance) {
        return instance;
    }
    instance = [[iTermCPUUtilization alloc] initWithPublisher:[iTermLocalCPUUtilizationPublisher sharedInstance]];
    [self setInstance:instance forSessionID:sessionID];
    return instance;
}

+ (void)setInstance:(iTermCPUUtilization *)instance forSessionID:(NSString *)sessionID {
    instance.sessionID = sessionID;
    if (instance) {
        self.sessionInstances[sessionID] = instance;
    } else {
        [self.sessionInstances removeObjectForKey:sessionID];
    }
}

- (instancetype)initWithPublisher:(iTermPublisher<NSNumber *> *)publisher {
    self = [super init];
    if (self) {
        _router = [[iTermPublisher alloc] initWithCapacity:publisher.capacity];
        [self setPublisher:publisher];
    }
    return self;
}

- (instancetype)init {
    return [self initWithPublisher:[iTermLocalCPUUtilizationPublisher sharedInstance]];
}

- (void)setPublisher:(iTermPublisher<NSNumber *> *)publisher {
    if (publisher == _publisher) {
        return;
    }
    [_publisher removeSubscriber:self];
    __weak __typeof(self) weakSelf = self;
    _publisher = publisher;
    [publisher addSubscriber:self block:^(NSNumber * _Nonnull payload) {
        [weakSelf republish:payload];
    }];
}

// publisher -> router
- (void)republish:(NSNumber *)payload {
    [_router publish:payload];
}

- (void)addSubscriber:(id)subscriber block:(iTermCPUUtilizationObserver)block {
    [_router addSubscriber:subscriber block:^(NSNumber * _Nonnull payload) {
        block(payload.doubleValue);
    }];
    NSNumber *last = _publisher.historicalValues.lastObject;
    if (last != nil) {
        block(last.doubleValue);
    }
}

#pragma mark - Private

- (NSArray<NSNumber *> *)samples {
    return _publisher.historicalValues;
}

@end
