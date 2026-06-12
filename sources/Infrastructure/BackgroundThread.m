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

- (void)main
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSRunLoop* myRunLoop = [NSRunLoop currentRunLoop];
    // This keeps the runloop blocking when nothing else is going on.
    [myRunLoop addPort:[NSMachPort port]
               forMode:NSDefaultRunLoopMode];
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
