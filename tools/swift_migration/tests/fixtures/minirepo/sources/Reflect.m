#import <objc/runtime.h>

@interface Reflect : NSObject
@end

@implementation Reflect
- (void)list:(Class)c {
    unsigned int n = 0;
    free(class_copyMethodList(c, &n));
}
@end
