#import <objc/runtime.h>

@interface Lookup : NSObject
@end

@implementation Lookup
- (unsigned int)count:(Class)c selector:(SEL)s {
    return method_getNumberOfArguments(class_getInstanceMethod(c, s));
}
- (BOOL)isMeta:(Class)c {
    return class_isMetaClass(c);
}
@end
