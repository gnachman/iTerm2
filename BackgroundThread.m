//
//  BackgroundThread.m
//  iTerm
//
//  Created by George Nachman on 3/1/12.
//

#import "BackgroundThread.h"

@implementation BackgroundThread

+ (NSThread *)backgroundThread
{
    static NSThread *thread;
    if (!thread) {
        thread = [[BackgroundThread alloc] init];
        [thread start];
    }
    return thread;
}

- (void)scheduleTimer
{
    NSRunLoop* myRunLoop = [NSRunLoop currentRunLoop]; //[[NSRunLoop alloc] init];
    
    [myRunLoop addTimer:[NSTimer timerWithTimeInterval:60
                                                target:self
                                              selector:@selector(scheduleTimer)
                                              userInfo:nil
                                               repeats:YES]
                forMode:NSDefaultRunLoopMode];
}

- (void)main
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSRunLoop* myRunLoop = [NSRunLoop currentRunLoop]; //[[NSRunLoop alloc] init];
    // The timer keeps the runloop from returning immediately.
    [self scheduleTimer];
    while (1) {
        if (!pool) {
            pool = [[NSAutoreleasePool alloc] init];
        }
        
        [myRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];

        [pool drain];
        pool = nil;
    }
}

@end
