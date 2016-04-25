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

// Before using -[NSObject swizzleInstanceMethodSelector:withBlock:] you must first create a context
// to hold the original methods. When you're done, -drain it. The context should be created
// autoreleased. It will become dealloc'ed after you drain it.
@interface iTermSelectorSwizzlerContext : NSObject

// Replace all methods swizzled during the lifetime of this context, or nested contexts, with their
// original implementations.
- (void)drain;

@end

@interface NSObject(Swizzle)
// fakeBlock's arguments will be self, _cmd, and then all arguments. There must be a current
// iTermSelectorSwizzlerContext for this to work. It will return the IMP of the original
// implementation, which you may call from your block.
//
// Example usage:
//   iTermSelectorSwizzlerContext *context = [[[iTermSelectorSwizzlerContext alloc] init] autorelease];
//   typedef void RemoveObserverImp(id, SEL, id);
//   __block RemoveObserverImp *removeObserver;
//   removeObserver = (RemoveObserverImp *)
//     [[NSNotificationCenter defaultCenter] swizzleInstanceMethodSelector:@selector(removeObserver:)
//                                                               withBlock:^(id target, id observer) {
//         ...do your thing here...
//         removeObserver(target, @selector(removeObserver:), observer);
//       }];
//   ...swizzle more methods, do whatever needs to be done...
//   [context drain];

- (IMP)swizzleInstanceMethodSelector:(SEL)selector withBlock:(id)fakeBlock;

@end
