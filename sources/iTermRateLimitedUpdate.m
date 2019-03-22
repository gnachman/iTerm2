//
//  iTermRateLimitedUpdate.m
//  iTerm2
//
//  Created by George Nachman on 6/17/17.
//
//

#import "iTermRateLimitedUpdate.h"
#import "NSTimer+iTerm.h"

@implementation iTermRateLimitedUpdate {
    // While nonnil, block will not be performed.
    NSTimer *_timer;
    void (^_block)(void);
}

- (void)invalidate {
    [_timer invalidate];
    _timer = nil;
    _block = nil;
}

- (void)scheduleTimer {
    [self scheduleTimerAfterDelay:self.minimumInterval];
}

- (void)scheduleTimerAfterDelay:(NSTimeInterval)delay {
    [_timer invalidate];
    _timer = [NSTimer scheduledWeakTimerWithTimeInterval:delay
                                                  target:self
                                                selector:@selector(performBlockIfNeeded:)
                                                userInfo:nil
                                                 repeats:NO];
}

- (void)setMinimumInterval:(NSTimeInterval)minimumInterval {
    if (minimumInterval < _minimumInterval && _timer) {
        [_timer invalidate];
        _minimumInterval = minimumInterval;
        [self performBlockIfNeeded:_timer];
    } else {
        _minimumInterval = minimumInterval;
    }
}
- (void)performRateLimitedBlock:(void (^)(void))block {
    if (_timer == nil) {
        block();
        [self scheduleTimer];
    } else {
        _block = [block copy];
    }
}

- (void)performRateLimitedSelector:(SEL)selector
                          onTarget:(id)target
                        withObject:(id)object {
    __weak id weakTarget = target;
    [self performRateLimitedBlock:^{
        id strongTarget = weakTarget;
        if (strongTarget) {
            void (*func)(id, SEL, NSTimer *) = (void *)[weakTarget methodForSelector:selector];
            func(weakTarget, selector, object);
        }
    }];
}

- (void)performBlockIfNeeded:(NSTimer *)timer {
    _timer = nil;
    if (_block != nil) {
        void (^block)(void) = _block;
        _block = nil;
        block();
        [self scheduleTimer];
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

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
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
