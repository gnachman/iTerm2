//
//  iTermPublisher.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/20/18.
//

#import "iTermPublisher.h"

#import "NSArray+iTerm.h"
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

@interface iTermSubscriber : NSObject<NSCopying>
@property (nonatomic, weak, readonly) id object;
@property (nonatomic, copy) void (^block)(id);

- (instancetype)initWithWeakReferenceToObject:(id)object block:(void (^)(id))block;
@end

@implementation iTermSubscriber {
    __weak id _object;
}

- (instancetype)initWithWeakReferenceToObject:(id)object block:(void (^)(id))block {
    self = [super init];
    if (self) {
        _object = object;
        _block = [block copy];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p object=%@>", self.class, self, _object];
}

- (BOOL)isEqual:(id)object {
    return object == self;
}

- (id)copyWithZone:(NSZone *)zone {
    // yay for being immutable!
    return self;
}

@end

@implementation iTermPublisher {
    // NSMapTable would be perfect here, except it's a broken pile of shit.
    // http://cocoamine.net/blog/2013/12/13/nsmaptable-and-zeroing-weak-references/
    //
    // Quoting from the closest thing to documentation that Apple can be bothered to write:
    //
    // https://developer.apple.com/library/archive/releasenotes/Foundation/RN-FoundationOlderNotes/#//apple_ref/doc/uid/TP40008080-TRANSLATED_CHAPTER_965-TRANSLATED_DEST_999B
    //
    // "weak-to-strong NSMapTables are not currently recommended, as the strong values for weak keys
    // which get zero'd out do not get cleared away (and released) until/unless the map table
    // resizes itself"
    //
    // While this doesn't seem to be the case in 10.13, the count is still wrong. As this appears to
    // be a dumpster fire I'll go my own way.
    NSMutableArray<iTermSubscriber *> *_subscribers;
    uint64_t _updateTime;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _subscribers = [NSMutableArray array];
    }
    return self;
}

- (void)addSubscriber:(id)object block:(void (^)(id))block {
    iTermSubscriberAttachment *attachment = [[iTermSubscriberAttachment alloc] init];
    __weak __typeof(self) weakSelf = self;
    iTermSubscriber *subscriber = [[iTermSubscriber alloc] initWithWeakReferenceToObject:object
                                                                                   block:block];
    attachment.willDealloc = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf didDeallocObjectForSubscriber:subscriber];
        });
    };
    [object it_setAssociatedObject:attachment
                            forKey:(void *)siTermPublisherAttachment];
    [_subscribers addObject:subscriber];
    [self countDidChange];
}

- (void)didDeallocObjectForSubscriber:(iTermSubscriber *)subscriber {
    [_subscribers removeObject:subscriber];
    [self countDidChange];
}

- (BOOL)haveSubscribers {
    return _subscribers.count > 0;
}

- (void)countDidChange {
    BOOL hasAnySubscribers = [self haveSubscribers];
    if (hasAnySubscribers != _hasAnySubscribers) {
        _hasAnySubscribers = hasAnySubscribers;
        [self.delegate publisherDidChangeNumberOfSubscribers:self];
    }
}

- (void)removeSubscriber:(id)object {
    iTermSubscriber *subscriber = [_subscribers objectPassingTest:^BOOL(iTermSubscriber *element, NSUInteger index, BOOL *stop) {
        return element.object == object;
    }];
    [_subscribers removeObject:subscriber];
    [self countDidChange];
}

- (void)publish:(id)payload {
    _updateTime = mach_absolute_time();
    for (iTermSubscriber *obj in _subscribers) {
        if (obj.object) {
            obj.block(payload);
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
