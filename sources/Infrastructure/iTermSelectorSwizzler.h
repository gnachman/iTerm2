@import Foundation;

/**
 * A helper class for swizzling a selector for the scope of a block.
 */
@interface iTermSelectorSwizzler : NSObject

// Returns the original IMP
+ (IMP)permanentlySwizzleSelector:(SEL)selector
                        fromClass:(Class)fromClass
                        withBlock:(id)replacementBlock;

@end

// Before using -[NSObject swizzleInstanceMethodSelector:withBlock:] you must first create a context
// to hold the original methods. When you're done, -drain it. The context should be created
// autoreleased. It will become dealloc'ed after you drain it.
@interface iTermSelectorSwizzlerContext : NSObject

// Replace all methods swizzled during the lifetime of this context, or nested contexts, with their
// original implementations.
- (void)drain;

@end
