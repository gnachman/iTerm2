// Fixture: sends in macro arguments and bodies. Line numbers are part of the expectations.
#import "widget.h"
void Sink(int n, ...);
#define LOG(n, ...) Sink(n, __VA_ARGS__)
#define OUTER(x) INNER(x)
#define INNER(y) [w y]
#define MAKE() [w makeThing]
#define CAT(a, b) a##b

void Macros(Widget *w) {
    LOG(1,
        [w makeThing], 2);
    OUTER(doThing);
    LOG(3,
        MAKE());
    [w CAT(load_, alpha)];
}
