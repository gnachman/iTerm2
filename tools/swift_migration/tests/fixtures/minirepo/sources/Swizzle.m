#import <objc/runtime.h>

@interface Swizzle : NSObject
@end

@implementation Swizzle
- (void)swap:(Method)a with:(Method)b {
    method_exchangeImplementations(a, b);
}
- (id)performSelector:(SEL)aSelector {
    return nil;
}
@end
