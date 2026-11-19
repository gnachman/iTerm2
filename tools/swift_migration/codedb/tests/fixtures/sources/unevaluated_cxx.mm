// Fixture: sends in unevaluated operands of Objective-C++. Line numbers are part of the expectations.
#import "widget.h"
void UnevaluatedCXX(Widget *w) {
    decltype([w makeThing]) x = [w makeThing];
    bool n = noexcept([w makeThing]);
    (void)x; (void)n;
}
