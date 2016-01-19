@import Foundation;

/**
 * A helper class for swizzling a selector for the scope of a block.
 */
@interface iTermSelectorSwizzler : NSObject

/**
 * Swizzles a method with a block for the runtime of a block.
 * Lookup order is class method -> instance method.
 *
 * @param selector The selector to swizzle (must be implemented on the fromClass)
 * @param fromClass The class to swizzle the selector
 * @param fakeSelectorBlock The block to replace the method implementation in the selector with
 * @param block The block to run with the swizzled selector
 */
+ (void)swizzleSelector:(SEL)selector
              fromClass:(Class)fromClass
              withBlock:(id)fakeSelectorBlock
               forBlock:(dispatch_block_t)block;

@end
