#import "Hazardous.h"
#import "Hub.h"

@implementation Hazardous

- (void)everything:(id)x {
    @try {
    } @catch (id e) {
    }
    @synchronized (self) {
    }
    NSInvocation *inv = nil;
    [x respondsToSelector:@selector(foo)];
    Class c = NSClassFromString(@"Foo");
    [x valueForKey:@"foo"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(foo) name:@"n" object:nil];
    [x sortedArrayUsingSelector:@selector(compare:)];
    IMP imp = [x methodForSelector:@selector(foo)];
    ((void (*)(id, SEL))objc_msgSend)(x, @selector(foo));
}

@end
