// Fixture: C++ references and lambdas, compiled with ARC. Line numbers are part of the expectations.
#import "state_base.h"
static int sTotal;
@interface Lam : Root
@end
@implementation Lam {
    int _n;
    int _m;
    int _k;
}
- (void)run {
    int &r = _n;
    const int &c = _m;
    auto byRef = [&]() { _k = 1; };
    auto byCopy = [=]() { return _k; };
    Lam *other = self;
    auto init = [o = other]() { return o->_m; };
    auto stat = [] { sTotal = 1; };
    r = c;
    byRef();
    (void)byCopy();
    (void)init();
    stat();
}
@end
