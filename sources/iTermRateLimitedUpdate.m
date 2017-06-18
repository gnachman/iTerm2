//
//  iTermRateLimitedUpdate.m
//  iTerm2
//
//  Created by George Nachman on 6/17/17.
//
//

#import "iTermRateLimitedUpdate.h"

@interface iTermTimerProxy : NSObject
- (void)performBlock:(NSTimer *)timer;
@end

// The timer keeps a strong reference to the proxy, while the proxy's block can
// hold a weak reference to the true target.
@implementation iTermTimerProxy

- (void)performBlock:(NSTimer *)timer {
    void (^block)(NSTimer * _Nonnull) = timer.userInfo;
    if (block != nil) {
        block(timer);
    }
}

@end

@interface NSTimer (iTerm)

+ (instancetype)it_scheduledTimerWithTimeInterval:(NSTimeInterval)timeInterval repeats:(BOOL)repeats block:(void (^_Nonnull)(NSTimer * _Nonnull timer))block;
+ (instancetype)it_weakTimerWithTimeInterval:(NSTimeInterval)timeInterval repeats:(BOOL)repeats target:(id)target selector:(SEL)selector;

@end

@implementation NSTimer (iTerm)

+ (instancetype)it_scheduledTimerWithTimeInterval:(NSTimeInterval)timeInterval
                                          repeats:(BOOL)repeats
                                            block:(void (^_Nonnull)(NSTimer * _Nonnull timer))block {
    iTermTimerProxy *proxy = [[iTermTimerProxy alloc] init];
    return [NSTimer scheduledTimerWithTimeInterval:timeInterval
                                            target:proxy
                                          selector:@selector(performBlock:)
                                          userInfo:[block copy]
                                           repeats:repeats];
}

+ (instancetype)it_weakTimerWithTimeInterval:(NSTimeInterval)timeInterval repeats:(BOOL)repeats target:(id)target selector:(SEL)selector {
    __weak id weakTarget = target;
    return [self it_scheduledTimerWithTimeInterval:timeInterval repeats:repeats block:^(NSTimer * _Nonnull timer) {
        [timer it_performSelector:selector onTarget:weakTarget];
    }];
}

- (void)it_performSelector:(SEL)selector onTarget:(id)target {
    if (target) {
        void (*func)(id, SEL, NSTimer *) = (void *)[target methodForSelector:selector];
        func(target, selector, self);
    }
}

@end

@implementation iTermRateLimitedUpdate {
    // While nonnil, block will not be performed.
    NSTimer *_timer;
    void (^_block)();
}

- (void)invalidate {
    [_timer invalidate];
    _timer = nil;
    _block = nil;
}

- (void)performRateLimitedBlock:(void (^)())block {
    if (_timer == nil) {
        block();
        _timer = [NSTimer it_weakTimerWithTimeInterval:self.minimumInterval
                                               repeats:NO
                                                target:self
                                              selector:@selector(performBlockIfNeeded:)];
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
        void (^block)() = _block;
        _block = nil;
        block();
    }
}

@end
