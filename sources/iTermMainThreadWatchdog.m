//
//  iTermMainThreadWatchdog.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/28/18.
//

#import "iTermMainThreadWatchdog.h"

#import "DebugLogging.h"
#import <signal.h>

@implementation iTermMainThreadWatchdog {
    dispatch_queue_t _queue;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.iterm2.watchdog", 0);
    }
    return self;
}

- (void)schedule {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), _queue, ^{
        [self check];
        [self schedule];
    });
}

- (void)check {
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    DLog(@"dispatch to main");
    dispatch_async(dispatch_get_main_queue(), ^{
        DLog(@"running main thread block, signaling semaphore");
        dispatch_semaphore_signal(sema);
    });
    if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) != 0) {
        DLog(@"Have been wedged for a whole second");
        TurnOffDebugLoggingSilently();
        raise(SIGABRT);
        DLog(@"Shouldn't get here");
    }
}

@end
