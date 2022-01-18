//
//  iTermGCDTimer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/20.
//

#import "iTermGCDTimer.h"

#import "NSObject+iTerm.h"

#import <QuartzCore/QuartzCore.h>

@implementation iTermGCDTimer {
    __weak id _target;
    SEL _selector;
    NSTimeInterval _interval;
    CFTimeInterval _scheduledTime;
    dispatch_queue_t _queue;
    BOOL _valid;
}

- (instancetype)initWithInterval:(NSTimeInterval)interval target:(id)target selector:(SEL)selector {
    return [self initWithInterval:interval queue:dispatch_get_main_queue() target:target selector:selector];
}

- (instancetype)initWithInterval:(NSTimeInterval)interval
                           queue:(dispatch_queue_t)queue
                          target:(id)target // WEAK!
                        selector:(SEL)selector {
    self = [super init];
    if (self) {
        _target = target;
        _selector = selector;
        _interval = interval;
        _queue = queue;
        _valid = YES;
        [self schedule];
    }
    return self;
}

- (void)invalidate {
    _valid = NO;
}

- (void)schedule {
    if (_target == nil) {
        return;
    }
    __weak __typeof(self) weakSelf = self;

    _scheduledTime = CACurrentMediaTime();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_interval * NSEC_PER_SEC)), _queue, ^{
        [weakSelf didFire];
    });
}

- (void)didFire {
    if (!_valid) {
        return;
    }
    _actualInterval = CACurrentMediaTime() - _scheduledTime;
    [self schedule];
    __strong id strongTarget = _target;
    if (!strongTarget) {
        return;
    }
    [strongTarget it_performNonObjectReturningSelector:_selector withObject:self];
}

@end

