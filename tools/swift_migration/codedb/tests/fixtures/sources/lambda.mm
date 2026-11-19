// Fixture: Objective-C++ with a lambda.
#import "widget.h"
void WithLambda(Widget *w) {
    auto f = [w]() { [w doThing]; };
    f();
}
void Local(Widget *w) {
    void (^b)(void) = ^{ struct L { static void f(Widget *x) { [x makeThing]; } }; L::f(w); };
    b();
}
