// Fixture: a category of Owner in another file. Line numbers are part of the expectations.
#import "owner.h"
@implementation Owner (Cat)
- (void)poke {
    _pub = 7;
}
- (void)viaLocal:(Owner *)p {
    Owner *o = p;
    o->_pub = 9;
}
@end
