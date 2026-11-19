#import <objc/runtime.h>

@interface Assoc : NSObject
@end

@implementation Assoc
- (void)tag:(id)o {
    objc_setAssociatedObject(o, @selector(tag:), self, OBJC_ASSOCIATION_RETAIN);
}
@end
