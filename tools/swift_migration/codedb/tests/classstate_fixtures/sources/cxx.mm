// Fixture: an Objective-C++ class with C++ state. Line numbers are part of the expectations.
#import "cs_base.h"
struct Counter {
    Counter() : n(0) {}
    int n;
};
@interface Cxx : Root
@end
@implementation Cxx {
    Counter _counter;
    int _plainInt;
}
- (void)run {
    auto f = [self]() { return _plainInt; };
    _counter.n = f();
}
@end
