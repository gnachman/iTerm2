#import <Foundation/Foundation.h>

#define CONCURRENT_KEY(name) @#name
#define CONCURRENT_CHECK(x) if (x) { return; }

extern int gConcurrentSelf;
int gConcurrentSelf = 0;

@interface Concurrent : NSObject
@property (atomic) int atomicCount;
@property int defaultAtomic;
@property (nonatomic) int plain;
@end

@implementation Concurrent {
    volatile int _flag;
}

- (void)run:(dispatch_group_t)group queue:(dispatch_queue_t)q source:(dispatch_source_t)src handler:(dispatch_block_t)handler {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
    });
    dispatch_group_async(group, q, ^{
    });
    dispatch_group_notify(group, q, ^{
    });
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    dispatch_source_set_event_handler(src, handler);
    NSMutableDictionary *d = [[NSThread currentThread] threadDictionary];
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:CONCURRENT_KEY(count)];
    goto done;
done:
    return;
}

+ (instancetype)newThing {
    return [[self alloc] init];
}

- (id)copyState {
    return nil;
}

- (void)dispatchTo:(id)obj selector:(SEL)sel {
CONCURRENT_CHECK(obj == nil)
    [obj respondsToSelector:sel];
    [NSApp targetForAction:sel];
    [obj performSelectorOnMainThread:sel withObject:nil waitUntilDone:NO];
    [obj fixture_dispatch:nil onTarget:obj];
}

- (id)mutableCopyState {
    return nil;
}

@end
