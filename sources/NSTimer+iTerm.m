//
//  NSTimer+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 8/1/17.
//
//

#import "NSTimer+iTerm.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"

@interface iTermTimerProxy : NSObject
@property (nonatomic, weak) id target;
@property (nonatomic) SEL selector;
@property (nonatomic, weak) NSTimer *timer;

- (void)performBlock:(NSTimer *)timer;

@end

@implementation iTermTimerProxy

- (instancetype)init {
    self = [super init];
    if (self) {
    }
    return self;
}

- (NSString *)timerInfo {
    if (!self.timer) {
        return @"nil";
    }
    CFRunLoopTimerRef timer = (__bridge CFRunLoopTimerRef)self.timer;
    return [NSString stringWithFormat:@"<%@: %p interval=%@ repeats=%@ nextFireDate=%@ seconds from now valid=%@>",
            NSStringFromClass([self.timer class]),
            self.timer,
            @(CFRunLoopTimerGetInterval(timer)),
            CFRunLoopTimerDoesRepeat(timer) ? @"yes" : @"no",
            @([self.timer.fireDate timeIntervalSinceNow]),
            self.timer.isValid ? @"yes" : @"no"];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p target=%@ selector=%@ timer=%@>",
            NSStringFromClass([self class]), self, self.target, NSStringFromSelector(self.selector), self.timerInfo];
}

- (void)timerDidFire:(NSTimer *)timer {
    id target = self.target;
    if (target) {
        ((void (*)(id, SEL, NSTimer *))[target methodForSelector:self.selector])(self.target, self.selector, timer);
    } else {
        DLog(@"Automatically invalidate timer for selector %@", NSStringFromSelector(self.selector));
        [timer invalidate];
    }
}

- (void)performBlock:(NSTimer *)timer {
    void (^block)(NSTimer * _Nonnull) = timer.userInfo;
    if (block != nil) {
        block(timer);
    }
}

@end

@implementation NSTimer (iTerm)

+ (instancetype)weakTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target selector:(SEL)selector userInfo:(id)userInfo repeats:(BOOL)repeats {
    iTermTimerProxy *proxy = [[iTermTimerProxy alloc] init];
    proxy.target = target;
    proxy.selector = selector;
    NSTimer *timer = [NSTimer timerWithTimeInterval:interval
                                             target:proxy
                                           selector:@selector(timerDidFire:)
                                           userInfo:userInfo
                                            repeats:repeats];
    proxy.timer = timer;
    return timer;
}

+ (instancetype)scheduledWeakTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(id)userInfo repeats:(BOOL)yesOrNo {
    iTermTimerProxy *proxy = [[iTermTimerProxy alloc] init];
    proxy.target = aTarget;
    proxy.selector = aSelector;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:ti
                                                      target:proxy
                                                    selector:@selector(timerDidFire:)
                                                    userInfo:userInfo
                                                     repeats:yesOrNo];
    proxy.timer = timer;
    return timer;
}

+ (instancetype)it_scheduledTimerWithTimeInterval:(NSTimeInterval)timeInterval
                                          repeats:(BOOL)repeats
                                            block:(void (^_Nonnull)(NSTimer * _Nonnull timer))block {
    iTermTimerProxy *proxy = [[iTermTimerProxy alloc] init];
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:timeInterval
                                                      target:proxy
                                                    selector:@selector(performBlock:)
                                                    userInfo:[block copy]
                                                     repeats:repeats];
    proxy.timer = timer;
    return timer;
}

- (void)it_performSelector:(SEL)selector onTarget:(id)target {
    if (target) {
        void (*func)(id, SEL, NSTimer *) = (void *)[target methodForSelector:selector];
        func(target, selector, self);
    }
}

@end
