// Fixture: an ARC category of Legacy, whose @implementation is manual reference counting (the shape of PTYSession).
#import "legacy.h"
typedef struct { int n; } PrivatePair;
@implementation Legacy (ARCCat)
- (void)poke:(id)o {
    _shared = o;
}
@end
@interface LegacyHolder : Root
@end
@implementation LegacyHolder {
    PrivatePair _pair;
    int capacity_;
    signed char _lit;
    int _depth;
}
- (int)capacity {
    return capacity_;
}
@end
