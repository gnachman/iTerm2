// Fixture: a category and a subclass in another file, compiled with ARC. Line numbers are part of the expectations.
#import "holder.h"
@interface SubHolder : Holder
@end
@implementation Holder (Extra)
- (void)bumpFromCategory {
    _count++;
}
@end
@implementation SubHolder
- (int)inherited {
    return _count;
}
@end
