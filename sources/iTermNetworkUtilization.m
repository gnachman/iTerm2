//
//  iTermNetworkUtilization.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/21/18.
//

#import "iTermNetworkUtilization.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermPublisher.h"

#include <sys/sysctl.h>
#include <netinet/in.h>
#include <net/if.h>
#include <net/if_dl.h>
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

typedef struct {
    iTermNetworkUtilizationStats stats;
    NSSet<NSData *> *interfaces;
} iTermNetworkUtilizationStatsAndInterfaces;

@implementation iTermNetworkUtilization {
    NSTimer *_timer;
    iTermPublisher<iTermNetworkUtilizationSample *> *_publisher;
    iTermNetworkUtilizationStatsAndInterfaces _last;
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
    iTermNetworkUtilizationStatsAndInterfaces last = _last;
    iTermNetworkUtilizationStatsAndInterfaces current = [self currentStatsAndInterfaces];
    if (!current.interfaces) {
        return;
    }
    if (_last.interfaces == nil || [_last.interfaces isEqual:current.interfaces]) {
        const NSTimeInterval t = _publisher.timeIntervalSinceLastUpdate;
        iTermNetworkUtilizationStats diff = {
            .upbytes = (current.stats.upbytes - last.stats.upbytes) / t,
            .downbytes = (current.stats.downbytes - last.stats.downbytes) / t
        };
        [_publisher publish:[[iTermNetworkUtilizationSample alloc] initWithStats:diff]];
    } else {
        // Republish last value to avoid a hiccup.
        const iTermNetworkUtilizationStats zeroState = { 0, 0 };
        [_publisher publish:_publisher.historicalValues.lastObject ?: [[iTermNetworkUtilizationSample alloc] initWithStats:zeroState]];
    }
    _last = current;
}

- (iTermNetworkUtilizationStatsAndInterfaces)currentStatsAndInterfaces {
    iTermNetworkUtilizationStatsAndInterfaces result = { .stats = { 0, 0 }, .interfaces = nil };

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
    NSMutableSet<NSData *> *interfaceAddrs = [NSMutableSet set];
    char *lim = buf + len;
    char *next = NULL;
    for (next = buf; next < lim; ) {
        struct if_msghdr *interface = (struct if_msghdr *)next;
        next += interface->ifm_msglen;
        if (interface->ifm_type == RTM_IFINFO2) {
            struct if_msghdr2 *header = (struct if_msghdr2 *)interface;

            // See also: https://opensource.apple.com/source/Libinfo/Libinfo-542.40.3/gen.subproj/getifaddrs.c.auto.html L282
            if (header->ifm_addrs & RTA_IFP) {
                struct sockaddr *sa = (struct sockaddr *)(header + 1);
                if (sa->sa_family == AF_LINK) {
                    struct sockaddr_dl *dl = (struct sockaddr_dl *)sa;
                    // Caches the socket address data (interface name + MAC address), in order to detect interface change
                    NSData *data = [NSData dataWithBytes:dl->sdl_data length:dl->sdl_nlen + dl->sdl_alen];
                    const NSString *info = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if ([info hasPrefix:@"lo"]) {
                        continue;
                    }
                    if ([iTermAdvancedSettingsModel excludeUtunFromNetworkUtilization] && [info hasPrefix:@"utun"]) {
                        continue;
                    }
                    [interfaceAddrs addObject:data];
                }
            }
            result.stats.downbytes += header->ifm_data.ifi_ibytes;
            result.stats.upbytes += header->ifm_data.ifi_obytes;
        }
    }
    result.interfaces = interfaceAddrs;
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
