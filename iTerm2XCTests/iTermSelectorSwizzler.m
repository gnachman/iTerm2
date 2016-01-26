#import "iTermSelectorSwizzler.h"
#import <objc/runtime.h>

@implementation iTermSelectorSwizzler

+ (void)swizzleSelector:(SEL)selector
              fromClass:(Class)fromClass
              withBlock:(id)fakeSelectorBlock
               forBlock:(dispatch_block_t)block {
    if (!fakeSelectorBlock || !block) {
        return;
    }

    Method originalMethod = class_getClassMethod(fromClass, selector)
        ?: class_getInstanceMethod(fromClass, selector);

    IMP originalMethodImplementation = method_getImplementation(originalMethod);
    IMP fakeMethodImplementation = imp_implementationWithBlock(fakeSelectorBlock);
    method_setImplementation(originalMethod, fakeMethodImplementation);

    block();

    method_setImplementation(originalMethod, originalMethodImplementation);
}

@end
