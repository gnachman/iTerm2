// Fixture: uses of the macros, compiled with MODE=1. Line numbers are part of the expectations.
#import "macros.h"
#define LOCAL 1
LEAKY(gThing)
DECLARE_CLASS(Declared)
@interface User : MRoot {
    int _count;
}
@end
@implementation User
DEFINE_GETTER(limit)
- (void)setFoo:(int)v {
}
- (int)run:(MRoot *)peer NOT_RETAINED {
    int a = SQUARE(LIMIT);
    int b = TWICE(LIMIT);
    int c = SQUARE(SQUARE(2));
    LOGF("%d", a);
    const char *n = NAME_OF(peer);
    int GETTER(x) = 1;
    SEND_LOG(peer, n);
    CALL(peer, ping);
    int s = SELF_COUNT;
    RETURN_IF(a > 100);
    LOOP_BREAK
    Logf("%s %d %s", WHERE);
    @synchronized(ITNonnilLock([peer lockObject])) {
        _count = AS_TYPE(int, b) + FIRST_ONLY(c, s);
    }
    void (^blk)(void) = RUN_BLOCK(_count++);
    LOCKED(peer, _count = 0);
    SETTER_FOR(Foo);
    int m = SDK_MIN(a, b);
    SDK_PING(peer);
    SEL ps = PING_SELECTOR;
    SEL cs = CMD_NAME;
    for (int i = 0; i < 2; i++) {
        if (i) ESCAPE_BREAK;
    }
    return KIND + LOCAL + m + get_x + gThing_storage + REDEFINED + (blk != 0) + (ps == cs);
}
@end
#define USER_CLASS User
@implementation USER_CLASS (Named)
- (void)named {
}
@end
