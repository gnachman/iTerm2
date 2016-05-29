#import "iTermSelectorSwizzler.h"
#import <objc/runtime.h>

static NSString *const iTermSelectorSwizzlerContexts = @"iTermSelectorSwizzlerContexts";

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

@interface iTermSwizzledSelector : NSObject

@property(nonatomic, assign) IMP originalMethodImplementation;
@property(nonatomic, assign) Method originalMethod;

- (void)unswizzle;

@end

@implementation iTermSwizzledSelector

- (void)unswizzle {
  method_setImplementation(self.originalMethod, self.originalMethodImplementation);
}

@end

@implementation iTermSelectorSwizzlerContext {
  NSMutableArray<iTermSwizzledSelector *> *_swizzledSelectors;
  BOOL _drained;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    NSMutableDictionary *dictionary = [[NSThread currentThread] threadDictionary];
    NSMutableArray<iTermSelectorSwizzlerContext *> *contexts =
        dictionary[iTermSelectorSwizzlerContexts];
    if (!contexts) {
      contexts = [NSMutableArray array];
      dictionary[iTermSelectorSwizzlerContexts] = contexts;
    }
    [contexts addObject:self];
    _swizzledSelectors = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc {
  assert(_drained);
  [_swizzledSelectors release];
  [super dealloc];
}

- (void)drain {
  assert(!_drained);
  NSMutableDictionary *dictionary = [[NSThread currentThread] threadDictionary];
  NSMutableArray *contexts = dictionary[iTermSelectorSwizzlerContexts];
  NSUInteger index = [contexts indexOfObject:self];
  if (index == NSNotFound) {
    return;
  }
  for (NSInteger i = contexts.count - 1; i > index; i--) {
    iTermSelectorSwizzlerContext *nestedContext = contexts[i];
    [nestedContext drain];
  }

  for (iTermSwizzledSelector *swizzledSelector in _swizzledSelectors) {
    [swizzledSelector unswizzle];
  }
  [_swizzledSelectors removeAllObjects];
  [contexts removeObjectAtIndex:index];

  _drained = YES;
}

@end

@implementation iTermSelectorSwizzlerContext(Protected)

+ (instancetype)currentContext {
  NSMutableDictionary *dictionary = [[NSThread currentThread] threadDictionary];
  NSMutableArray<iTermSelectorSwizzlerContext *> *contexts =
      dictionary[iTermSelectorSwizzlerContexts];
  return [contexts lastObject];
}

- (void)addSwizzledSelector:(iTermSwizzledSelector *)swizzledSelector {
  [_swizzledSelectors addObject:swizzledSelector];
}

@end

@implementation NSObject(Swizzle)

- (IMP)swizzleInstanceMethodSelector:(SEL)selector withBlock:(id)fakeBlock {
  iTermSelectorSwizzlerContext *context = [iTermSelectorSwizzlerContext currentContext];
  assert(context);
  iTermSwizzledSelector *swizzledSelector = [[[iTermSwizzledSelector alloc] init] autorelease];
  swizzledSelector.originalMethod = class_getInstanceMethod([self class], selector);
  swizzledSelector.originalMethodImplementation = method_getImplementation(swizzledSelector.originalMethod);
  if (fakeBlock && context) {
    [context addSwizzledSelector:swizzledSelector];
    IMP fakeMethodImplementation = imp_implementationWithBlock(fakeBlock);
    method_setImplementation(swizzledSelector.originalMethod, fakeMethodImplementation);
  }

  return swizzledSelector.originalMethodImplementation;
}

@end
