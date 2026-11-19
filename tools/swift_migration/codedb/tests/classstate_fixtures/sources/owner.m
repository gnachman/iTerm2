// Fixture: Owner's own code, compiled with ARC. Line numbers are part of the expectations.
#import "owner.h"
#define MAKE_GETTER(n) - (int)n { return 0; }
int gOwnerTotal = 0;
static int sHits;
static Thing *sShared;
@implementation Owner {
    NiceEnum _nice;
    __int128 _big;
    _Atomic(int) _atom;
    StrongBox _strongBox;
    UnretainedBox _unretainedBox;
    Flex *_flex;
    Number _number;
    unsigned _flag : 1;
    char _buf[8];
    Callback _callback;
    VarCallback _varCallback;
    void (^_plainBlock)(PlainEnum);
    void (^_boxBlock)(StrongBox);
    Vec4 _vec;
    long double _ld;
    SEL _sel;
    id<Drawing> _drawer;
    Opaque *_opaque;
    __weak Thing *_weakThing;
    Thing *_other;
    Thing *_name;
}
@synthesize name = _other;
- (int)flag {
    return _flag;
}
- (void)work:(Owner *)peer {
    _pub = 1;
    _pkg += 2;
    Fill(&_pkg);
    peer->_pub = 3;
    sHits++;
    gOwnerTotal = _pub;
    void (^b)(void) = ^{ self->_pub = 4; };
    b();
    @synchronized (self) {
        _pkg = 5;
        sHits = 0;
    }
}
+ (Thing *)shared {
    static Thing *sLocal;
    sLocal = sShared;
    return sLocal;
}
- (void)draw {
}
MAKE_GETTER(made)
#if 0
- (void)neverCompiled {
}
#endif
@end
