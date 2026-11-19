// Fixture: a class compiled with manual reference counting. Line numbers are part of the expectations.
#import "legacy.h"
@implementation Legacy {
    id _obj;
    StrongBox _box;
}
- (void)set:(id)o {
    _obj = o;
}
@end
