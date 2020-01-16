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
    NSRunLoop* myRunLoop = [NSRunLoop currentRunLoop];
    // This keeps the runloop blocking when nothing else is going on.
    [myRunLoop addPort:[NSMachPort port]
               forMode:NSDefaultRunLoopMode];
    while (1) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [myRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        [pool drain];
    }
}

@end
