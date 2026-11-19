// Fixture: another class, compiled with manual reference counting. Line numbers are part of the expectations.
#import "holder.h"
@interface Peer : Root {
    id _retained;
    __unsafe_unretained id _loose;
    unsigned _peerFlag : 1;
}
- (void)poke:(Holder *)h;
@end
@implementation Peer
- (void)poke:(Holder *)h {
    h->_publicCount = h->_publicCount + 1;
    _retained = h;
    gHolderCount = 0;
    void (^b)(void) = ^{ _loose = _retained; };
    b();
}
@end
