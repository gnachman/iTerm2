@import Foundation;

/**
 * A helper class for replacing the implementation of a method, for good.
 */
@interface iTermSelectorSwizzler : NSObject

// Returns the original IMP
+ (IMP)permanentlySwizzleSelector:(SEL)selector
                        fromClass:(Class)fromClass
                        withBlock:(id)replacementBlock;

@end

// A per-thread stack of contexts, each holding the original implementations of methods swizzled
// while it was the innermost context; draining it restores them. Nothing in the app swizzles through
// a context any more (the method that did was deleted), so no context records anything. A context
// must be drained before it is deallocated.
@interface iTermSelectorSwizzlerContext : NSObject

// Replace all methods swizzled during the lifetime of this context, or nested contexts, with their
// original implementations.
- (void)drain;

@end
