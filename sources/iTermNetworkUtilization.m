//
//  iTermNetworkUtilization.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/21/18.
//

#import "iTermNetworkUtilization.h"

#import "iTermPublisher.h"

#include <sys/sysctl.h>
#include <netinet/in.h>
#include <net/if.h>
#include <net/route.h>

typedef struct {
    double upbytes;
    double downbytes;
} iTermNetworkUtilizationStats;

@implementation iTermNetworkUtilizationSample {
    iTermNetworkUtilizationStats _stats;
}

- (instancetype)initWithStats:(iTermNetworkUtilizationStats)stats {
    self = [super init];
    if (self) {
        _stats = stats;
    }
    return self;
}

- (double)bytesPerSecondRead {
    return _stats.downbytes;
}

- (double)bytesPerSecondWrite {
    return _stats.upbytes;
}

@end

@interface iTermNetworkUtilization()<iTermPublisherDelegate>
@end

@implementation iTermNetworkUtilization {
    NSTimer *_timer;
    iTermPublisher<iTermNetworkUtilizationSample *> *_publisher;
    iTermNetworkUtilizationStats _last;
    // Used to detect network interface change
    NSUInteger lastInterfaceCount;
    BOOL interfaceHasChanged;
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
        _publisher = [[iTermPublisher alloc] initWithCapacity:120];
        _publisher.delegate = self;
    }
    return self;
}

- (void)addSubscriber:(id)subscriber block:(void (^)(double, double))block {
    [_publisher addSubscriber:subscriber block:^(iTermNetworkUtilizationSample *_Nonnull payload) {
        block(payload.bytesPerSecondRead,
              payload.bytesPerSecondWrite);
    }];
    iTermNetworkUtilizationSample *last = _publisher.historicalValues.lastObject;
    if (last != nil) {
        block(last.bytesPerSecondRead, last.bytesPerSecondWrite);
    } else {
        [self update];
    }
}

- (NSArray<iTermNetworkUtilizationSample *> *)samples {
    return _publisher.historicalValues;
}

#pragma mark - Private

- (void)update {
    iTermNetworkUtilizationStats last = _last;
    iTermNetworkUtilizationStats current = [self currentStats];
    if (!interfaceHasChanged) {
        NSTimeInterval t = _publisher.timeIntervalSinceLastUpdate;
        iTermNetworkUtilizationStats diff = {
            .upbytes = (current.upbytes - last.upbytes) / t,
            .downbytes = (current.downbytes - last.downbytes) / t
        };
        [_publisher publish:[[iTermNetworkUtilizationSample alloc] initWithStats:diff]];
    } else {
        interfaceHasChanged = false;
        iTermNetworkUtilizationSample *last = _publisher.historicalValues.lastObject;
        if (last != nil) {
            [_publisher publish:last];
        } else {
            iTermNetworkUtilizationStats zeroState = { 0, 0 };
            [_publisher publish:[[iTermNetworkUtilizationSample alloc] initWithStats:zeroState]];
        }
    }
    _last = current;
}

- (iTermNetworkUtilizationStats)currentStats {
    iTermNetworkUtilizationStats result = { 0, 0 };

    int mib[] = {
        CTL_NET,
        PF_ROUTE,
        0,
        0,
        NET_RT_IFLIST2,
        0
    };

    size_t len;
    if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0) {
        return result;
    }
    NSMutableData *storage = [NSMutableData dataWithLength:len];
    char *buf = (char *)storage.mutableBytes;
    if (sysctl(mib, 6, buf, &len, NULL, 0) < 0) {
        return result;
    }
    NSUInteger interfaceCount = 0;
    char *lim = buf + len;
    char *next = NULL;
    for (next = buf; next < lim; ) {
        struct if_msghdr *interface = (struct if_msghdr *)next;
        next += interface->ifm_msglen;
        if (interface->ifm_type == RTM_IFINFO2) {
            struct if_msghdr2 *header = (struct if_msghdr2 *)interface;
            result.downbytes += header->ifm_data.ifi_ibytes;
            result.upbytes += header->ifm_data.ifi_obytes;
            interfaceCount++;
        }
    }
    if (interfaceCount != lastInterfaceCount) {
        lastInterfaceCount = interfaceCount;
        interfaceHasChanged = true;
    }
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
