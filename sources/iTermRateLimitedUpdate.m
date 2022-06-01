//
//  iTermRateLimitedUpdate.m
//  iTerm2
//
//  Created by George Nachman on 6/17/17.
//
//

#import "iTermRateLimitedUpdate.h"

#import "DebugLogging.h"
#import "NSTimer+iTerm.h"
#import "iTermGCD.h"
#import "iTermGCDTimer.h"

@implementation iTermRateLimitedUpdate {
    // While nonnil, block will not be performed.
    id<iTermTimer> _timer;
    void (^_block)(void);
}

- (instancetype)initWithName:(NSString *)name minimumInterval:(NSTimeInterval)minimumInterval {
    ITAssertWithMessage(minimumInterval >= 0, @"Minimum interval too small");
    self = [super init];
    if (self) {
        _name = [name copy];
        [self setMinimumInterval:minimumInterval];
    }
    return self;
}

- (void)invalidate {
    if (self.debug) {
        DLog(@"Invalidate timer from %@", [NSThread callStackSymbols]);
    }
    [_timer invalidate];
    _timer = nil;
    _block = nil;
    _deferCount = 0;
}

- (void)force {
    if (!_timer) {
        return;
    }
    [_timer invalidate];
    _timer = nil;
    if (_block) {
        _block();
        _deferCount = 0;
    }
    [self scheduleTimer];
}

- (void)performWithinDuration:(NSTimeInterval)duration {
    if (!_timer) {
        return;
    }
    const NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + duration;
    if (_timer.fireDate.timeIntervalSinceReferenceDate < deadline) {
        return;
    }
    [self scheduleTimerAfterDelay:duration];
}

- (void)scheduleTimer {
    ITAssertWithMessage(self.minimumInterval >= 0, @"Minimum interval is %@ for %@", @(self.minimumInterval), self.name);
    [self scheduleTimerAfterDelay:self.minimumInterval];
}

- (void)scheduleTimerAfterDelay:(NSTimeInterval)delay {
    DLog(@"Schedule timer after delay %@", @(delay));
    if (self.debug) {
        DLog(@"Schedule timer after delay %@", @(delay));
    }
    [_timer invalidate];
    if (_queue) {
        _timer = [iTermGCDTimer scheduledWeakTimerWithTimeInterval:delay
                                                            target:self
                                                          selector:@selector(performBlockIfNeeded:)
                                                             queue:_queue];
    } else {
        _timer = [NSTimer scheduledWeakTimerWithTimeInterval:delay
                                                      target:self
                                                    selector:@selector(performBlockIfNeeded:)
                                                    userInfo:nil
                                                     repeats:NO];
    }
}

- (void)setMinimumInterval:(NSTimeInterval)minimumInterval {
    DLog(@"%@ setMinimumInterval:%@\n%@", self.name, @(minimumInterval), [NSThread callStackSymbols]);
    if (minimumInterval < _minimumInterval && _timer) {
        if (self.debug) {
            DLog(@"Invalidate timer");
        }
        [_timer invalidate];
        _minimumInterval = minimumInterval;
        [self performBlockIfNeeded:_timer];
    } else {
        _minimumInterval = minimumInterval;
    }
}

- (void)performRateLimitedBlock:(void (^)(void))block {
    [iTermGCD assertMainQueueSafe];
    if (_minimumInterval == 0) {
        block();
        return;
    }
    if (_timer == nil) {
        if (self.debug) {
            DLog(@"RLU perform immediately");
        }
        block();
        _deferCount = 0;
        [self scheduleTimer];
    } else {
        if (self.debug) {
            DLog(@"RLU defer. minimum interval is %@", @(_minimumInterval));
        }
        if (self.suppressionMode) {
            DLog(@"in suppression mode");
            return;
        }
        _deferCount += 1;
        _block = [block copy];
    }
}

- (void)performRateLimitedSelector:(SEL)selector
                          onTarget:(id)target
                        withObject:(id)object {
    __weak id weakTarget = target;
    [self performRateLimitedBlock:^{
        DLog(@"Called with target=%@ selector=%@", weakTarget, NSStringFromSelector(selector));
        id strongTarget = weakTarget;
        if (strongTarget) {
            void (*func)(id, SEL, NSTimer *) = (void *)[weakTarget methodForSelector:selector];
            func(weakTarget, selector, object);
        }
    }];
}

- (void)performBlockIfNeeded:(NSTimer *)timer {
    DLog(@"RLU timer fired");
    if (self.debug) {
        DLog(@"RLU timer fired");
    }
    _timer = nil;
    if (_block != nil) {
        DLog(@"RLU timer handler: have a block");
        if (self.debug) {
            DLog(@"RLU timer handler: have a block");
        }
        void (^block)(void) = _block;
        _block = nil;
        block();
        _deferCount = 0;
        [self scheduleTimer];
    } else {
        DLog(@"RLU timer fired - NO BLOCK");
        if (self.debug) {
            DLog(@"RLU timer fired - NO BLOCK");
        }
    }
}

@end

@implementation iTermRateLimitedIdleUpdate

- (void)performRateLimitedBlock:(void (^)(void))block {
    [self scheduleTimer];
    [super performRateLimitedBlock:block];
}


@end

static NSString *const iTermPersistentRateLimitedUpdateUserDefaultsKey = @"NoSyncPersistentRateLimitedUpdates";

@implementation iTermPersistentRateLimitedUpdate {
    NSString *_name;
}

+ (NSTimeInterval)nextDateForName:(NSString *)name {
    NSDictionary<NSString *, NSNumber *> *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:iTermPersistentRateLimitedUpdateUserDefaultsKey];
    return [dict[name] doubleValue];
}

+ (void)setNextDate:(NSTimeInterval)nextDate forName:(NSString *)name {
    NSMutableDictionary<NSString *, NSNumber *> *dict = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:iTermPersistentRateLimitedUpdateUserDefaultsKey] ?: @{} mutableCopy];
    dict[name] = @(nextDate);
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:iTermPersistentRateLimitedUpdateUserDefaultsKey];
}

- (instancetype)initWithName:(NSString *)name minimumInterval:(NSTimeInterval)minimumInterval {
    self = [super initWithName:name minimumInterval:minimumInterval];
    if (self) {
        _name = name;
        NSTimeInterval nextTime = [self.class nextDateForName:name];
        if (nextTime != 0) {
            const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            if (now < nextTime) {
                // Next allowed run is in the future
                [self scheduleTimerAfterDelay:nextTime - now];
            }
        }
        [self setMinimumInterval:minimumInterval];
    }
    return self;
}

- (void)scheduleTimer {
    const NSTimeInterval delay = self.minimumInterval;
    [super scheduleTimer];
    [self.class setNextDate:[NSDate timeIntervalSinceReferenceDate] + delay
                    forName:_name];
}

@end
