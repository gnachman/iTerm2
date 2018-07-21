//
//  iTermPublisher.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/20/18.
//

#import "iTermPublisher.h"

#import "NSObject+iTerm.h"
#include <mach/mach_time.h>

static const char* siTermPublisherAttachment = "siTermPublisherAttachment";

@interface iTermSubscriberAttachment : NSObject

@property (nonatomic, copy) void (^willDealloc)(void);

@end

@implementation iTermSubscriberAttachment

- (void)dealloc {
    if (self.willDealloc) {
        self.willDealloc();
    }
}

@end

@implementation iTermPublisher {
    NSInteger _count;
    NSMapTable<id, void (^)(id)> *_subscribers;
    uint64_t _updateTime;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _subscribers = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPersonality
                                                 valueOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality
                                                     capacity:1];
    }
    return self;
}

- (void)addSubscriber:(id)subscriber block:(void (^)(id))block {
    iTermSubscriberAttachment *attachment = [[iTermSubscriberAttachment alloc] init];
    __weak __typeof(self) weakSelf = self;
    attachment.willDealloc = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf countDidChange];
        });
    };
    [subscriber it_setAssociatedObject:attachment
                                forKey:(void *)siTermPublisherAttachment];
    [_subscribers setObject:block forKey:subscriber];
    [self countDidChange];
}

- (NSInteger)numberOfSubscribers {
    return _subscribers.count;
}

- (void)countDidChange {
    if (_subscribers.count != _count) {
        _count = _subscribers.count;
        [self.delegate publisherDidChangeNumberOfSubscribers:self];
    }
}

- (void)removeSubscriber:(id)subscriber {
    [_subscribers removeObjectForKey:subscriber];
}

- (void)publish:(id)payload {
    _updateTime = mach_absolute_time();
    for (id key in _subscribers) {
        void (^block)(id) = [_subscribers objectForKey:key];
        if (block) {
            block(payload);
        }
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

@end
