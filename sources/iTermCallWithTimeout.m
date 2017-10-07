//
//  iTermCallWithTimeout.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/7/17.
//

#import "iTermCallWithTimeout.h"

@implementation iTermCallWithTimeout {
    dispatch_queue_t _queue;
}

+ (instancetype)instanceForIdentifier:(NSString *)identifier {
    static NSMutableDictionary *objects;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        objects = [NSMutableDictionary dictionary];
    });
    iTermCallWithTimeout *object = objects[identifier];
    if (object == nil) {
        object = [[self alloc] initWithIdentifier:identifier];
        objects[identifier] = object;
    }
    return object;
}

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create([[NSString stringWithFormat:@"com.iterm2.timeoutcall.%@", identifier] UTF8String],
                                       NULL);
    }
    return self;
}

- (BOOL)executeWithTimeout:(NSTimeInterval)timeout block:(void (^)(void))block {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);

    dispatch_async(_queue, ^{
        block();
        dispatch_group_leave(group);
    });

    // Wait up to half a second for the statfs to finish.
    long timedOut = dispatch_group_wait(group,
                                        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
    return !!timedOut;
}

@end
