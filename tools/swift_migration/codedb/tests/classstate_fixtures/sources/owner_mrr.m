// Fixture: a category of Owner compiled with manual reference counting. Line numbers are part of the expectations.
#import "owner.h"
@implementation Owner (MRR)
- (int)peek {
    return _pkg;
}
@end
