//
//  iTermWeakReference.m
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import "iTermWeakReference.h"

#import "DebugLogging.h"
#import "JGMethodSwizzler.h"
#import <objc/runtime.h>

static OSSpinLock lock = OS_SPINLOCK_INIT;

@implementation iTermWeakReference {
    NSObject *_object;
    Class _class;
}

+ (instancetype)weakReferenceToObject:(id)object {
    return [[[self alloc] initWithObject:object] autorelease];
}

- (instancetype)initWithObject:(id)object {
    _object = object;
    _class = [object class];
    Class key = [self class];
    void (^nullifyBlock)(id) = ^(id theObject) {
        [theObject deswizzle];
        
        OSSpinLockLock(&lock);
        NSMutableArray *weakRefs = objc_getAssociatedObject(theObject, key);
        for (NSValue *value in weakRefs) {
            iTermWeakReference *weakReference = [value nonretainedObjectValue];
            [weakReference internal_nullify];
        }
        OSSpinLockUnlock(&lock);
    };
    
    OSSpinLockLock(&lock);
    // We only want to swizzle an object a single time. Use associated objects to tell if
    // we've swizzled it. The object holds an array of weak refs.
    NSMutableArray<NSValue *> *weakRefs = objc_getAssociatedObject(object, key);
    if (!weakRefs) {
        weakRefs = [NSMutableArray array];
        objc_setAssociatedObject(object, key, weakRefs, OBJC_ASSOCIATION_RETAIN);

        [object swizzleMethod:@selector(dealloc)
              withReplacement:JGMethodReplacementProviderBlock {
                  void (^result)(NSObject *) = ^ void (__unsafe_unretained NSObject *blockSelf) {
                      nullifyBlock(blockSelf);
                      ((__typeof(void (*)(__typeof(blockSelf), SEL, ...)))original)(blockSelf, _cmd);
                  };
                  return [[result copy] autorelease];
              }];
    }
    [weakRefs addObject:[NSValue valueWithNonretainedObject:self]];

    OSSpinLockUnlock(&lock);

    return self;
}

- (void)dealloc {
    OSSpinLockLock(&lock);
    if (_object) {
        NSMutableArray<NSValue *> *weakRefs = objc_getAssociatedObject(_object, [self class]);
        [weakRefs removeObject:[NSValue valueWithNonretainedObject:self]];
        // The object cannot be safely deswizzled. If another thread tries to invoke a method on
        // the object during deswizzling, it will go awry (looks like the objc runtime isn't
        // thread-safe in this way).
    }
    OSSpinLockUnlock(&lock);

    [super dealloc];
}

- (void)internal_nullify {
    _object = nil;
}

- (id)internal_unsafeObject {
    OSSpinLockLock(&lock);
    id result = _object;
    OSSpinLockUnlock(&lock);
    return result;
}

- (id)proxiedObject {
    OSSpinLockLock(&lock);
    id result = [[_object retain] autorelease];
    OSSpinLockUnlock(&lock);
    return result;
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    OSSpinLockLock(&lock);
    id object = [_object retain];
    OSSpinLockUnlock(&lock);

    if (object) {
        invocation.target = object;
        [invocation invoke];
        [object release];
    }
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    OSSpinLockLock(&lock);
    id object = [_object retain];
    OSSpinLockUnlock(&lock);

    NSMethodSignature *result;
    if (object) {
        result = [object methodSignatureForSelector:sel];
        [object release];
    } else {
        result = [_class instanceMethodSignatureForSelector:sel];
    }
    return result;
}

@end

@implementation NSObject(iTermWeakReference)

- (NSObject *)weakSelf {
    return (NSObject *)[[[iTermWeakReference alloc] initWithObject:self] autorelease];
}

@end
