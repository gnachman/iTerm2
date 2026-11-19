// Fixture: Objective-C++ state, compiled with ARC. Line numbers are part of the expectations.
#import "state_base.h"
struct Counter {
    int n;
    Counter() : n(0) {}
};
static Counter sGlobalCounter;
thread_local int tCount;
@interface CxxThing : Root
@end
@implementation CxxThing {
    Counter _counter;
    Rect2 _frame;
    Vec4 _tint;
}
- (int)tick {
    tCount++;
    _counter.n++;
    return sGlobalCounter.n + _frame.origin.x;
}
@end
static Rect2 *sFramePtr;
static char *const *sNames;
static int sMixed;
void Poke(void) {
    sFramePtr->width = 1;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ sMixed = 1; });
    sMixed = 2;
    (void)sNames;
}
@implementation CxxThing (More)
- (void)reset {
    Counter fresh;
    _counter = fresh;
}
@end
