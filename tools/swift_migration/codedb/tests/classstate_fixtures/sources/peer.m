// Fixture: other code that reaches Owner's state. Line numbers are part of the expectations.
#import "owner.h"
#import "legacy.h"
#import "generic.h"
extern int gOwnerTotal;
@interface Peer : Root
@end
@implementation Peer
- (void)reach:(Owner *)owner {
    owner->_pub = 8;
    gOwnerTotal++;
}
@end
int PeerRead(Owner *o) {
    return o->_pkg;
}
@interface SubOwner : Owner
@end
@implementation SubOwner
- (int)flag {
    return 2;
}
@end
