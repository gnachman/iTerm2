//
//  iTermMemoryUtilization.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/21/18.
//

#import "iTermMemoryUtilization.h"

#import "DebugLogging.h"
#import "iTermPublisher.h"
#include <mach/mach.h>
#include <mach/mach_init.h>
#include <mach/mach_error.h>
#include <mach/mach_host.h>
#include <mach/mach_time.h>
#include <mach/vm_map.h>

@interface iTermMemoryUtilization()<iTermPublisherDelegate>
@end

@implementation iTermMemoryUtilization {
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
        _publisher = [[iTermPublisher alloc] initWithCapacity:120];
        _publisher.delegate = self;
    }
    return self;
}

- (void)addSubscriber:(id)subscriber block:(void (^)(double))block {
    [_publisher addSubscriber:subscriber block:^(NSNumber * _Nonnull payload) {
        block(payload.doubleValue);
    }];
    NSNumber *last = _publisher.historicalValues.lastObject;
    if (last != nil) {
        block(last.doubleValue);
    } else {
        [self update];
    }
}

- (NSArray<NSNumber *> *)samples {
    return [_publisher historicalValues];
}

#pragma mark - Private

- (void)update {
    [_publisher publish:@((double)self.memoryUsage / (double)self.availableMemory)];
}

- (long long)pageSize {
    static vm_size_t pagesize = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_port_t host_port = mach_host_self();
        host_page_size(host_port, &pagesize);
    });
    return pagesize;
}

// Command-line vm_stat program     vm_stat struct
// Pages free:                      free_count
// Pages active:                    active_count
// Pages inactive:                  inactive_count
// Pages speculative:               speculative_count
// Pages throttled:                 throttled_count
// Pages wired down:                wire_count
// Pages purgeable:                 purgeable_count (maybe?)
// "Translation faults":            faults
// Pages copy-on-write:             cow_faults
// Pages zero filled:               zero_fill_count
// Pages reactivated:               reactivations
// Pages purged:                    purges
// File-backed pages:               external_page_count
// Anonymous pages:                 internal_page_count
// Pages stored in compressor:      total_uncompressed_pages_in_compressor
// Pages occupied by compressor:    compressor_page_count
// Decompressions:                  decompressions
// Compressions:                    compressions
// Pageins:                         pageins
// Pageouts:                        pageouts
// Swapins:                         swapins
// Swapouts:                        swapouts

- (long long)memoryUsage {
    mach_port_t host_port = mach_host_self();
    vm_statistics64_data_t vm_stat;
    mach_msg_type_number_t host_size = HOST_VM_INFO64_COUNT;

    kern_return_t status = host_statistics64(host_port, HOST_VM_INFO64, (host_info64_t)&vm_stat, &host_size);
    if (status != KERN_SUCCESS)
    {
        return 0;
    }

    return self.pageSize * (vm_stat.internal_page_count - vm_stat.purgeable_count + vm_stat.wire_count);
}

- (long long)availableMemory {
    return [NSProcessInfo processInfo].physicalMemory;
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

