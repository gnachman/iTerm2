//
//  NSTimer+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 8/1/17.
//
//

#import "NSTimer+iTerm.h"

@interface iTermTimerProxy : NSObject
@property (nonatomic, weak) id target;
@property (nonatomic) SEL selector;

- (void)performBlock:(NSTimer *)timer;

@end

@implementation iTermTimerProxy

- (void)timerDidFire:(NSTimer *)timer {
    id target = self.target;
    if (target) {
        ((void (*)(id, SEL, NSTimer *))[target methodForSelector:self.selector])(self.target, self.selector, timer);
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
    return [NSTimer timerWithTimeInterval:interval
                                   target:proxy
                                 selector:@selector(timerDidFire:)
                                 userInfo:userInfo
                                  repeats:repeats];
}

+ (instancetype)scheduledWeakTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(id)userInfo repeats:(BOOL)yesOrNo {
    iTermTimerProxy *proxy = [[iTermTimerProxy alloc] init];
    proxy.target = aTarget;
    proxy.selector = aSelector;
    return [NSTimer scheduledTimerWithTimeInterval:ti
                                            target:proxy
                                          selector:@selector(timerDidFire:)
                                          userInfo:userInfo
                                           repeats:yesOrNo];
}

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

- (void)it_performSelector:(SEL)selector onTarget:(id)target {
    if (target) {
        void (*func)(id, SEL, NSTimer *) = (void *)[target methodForSelector:selector];
        func(target, selector, self);
    }
}

@end
