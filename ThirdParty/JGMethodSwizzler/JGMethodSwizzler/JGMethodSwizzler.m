//
//  JGMethodSwizzler.m
//  JGMethodSwizzler
//
//  Created by Jonas Gessner 22.08.2013
//  Copyright (c) 2013 Jonas Gessner. All rights reserved.
//

#import "JGMethodSwizzler.h"

#import <objc/runtime.h>
#import <libkern/OSAtomic.h>


#pragma mark Defines

#ifdef __clang__
#if __has_feature(objc_arc)
#define JG_ARC_ENABLED
#endif
#endif

#ifdef JG_ARC_ENABLED
#define JGBridgeCast(type, obj) ((__bridge type)obj)
#define releaseIfNecessary(object)
#else
#define JGBridgeCast(type, obj) ((type)obj)
#define releaseIfNecessary(object) [object release];
#endif


#define kClassKey @"k"
#define kCountKey @"c"
#define kIMPKey @"i"

// See http://clang.llvm.org/docs/Block-ABI-Apple.html#high-level
struct Block_literal_1 {
    void *isa; // initialized to &_NSConcreteStackBlock or &_NSConcreteGlobalBlock
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct Block_descriptor_1 {
        unsigned long int reserved;         // NULL
        unsigned long int size;         // sizeof(struct Block_literal_1)
        // optional helper functions
        void (*copy_helper)(void *dst, void *src);     // IFF (1<<25)
        void (*dispose_helper)(void *src);             // IFF (1<<25)
        // required ABI.2010.3.16
        const char *signature;                         // IFF (1<<30)
    } *descriptor;
    // imported variables
};

enum {
    BLOCK_HAS_COPY_DISPOSE =  (1 << 25),
    BLOCK_HAS_CTOR =          (1 << 26), // helpers have C++ code
    BLOCK_IS_GLOBAL =         (1 << 28),
    BLOCK_HAS_STRET =         (1 << 29), // IFF BLOCK_HAS_SIGNATURE
    BLOCK_HAS_SIGNATURE =     (1 << 30),
};
typedef int BlockFlags;



#pragma mark - Block Analysis

NS_INLINE const char *blockGetType(id block) {
    struct Block_literal_1 *blockRef = JGBridgeCast(struct Block_literal_1 *, block);
    BlockFlags flags = blockRef->flags;
    
    if (flags & BLOCK_HAS_SIGNATURE) {
        void *signatureLocation = blockRef->descriptor;
        signatureLocation += sizeof(unsigned long int);
        signatureLocation += sizeof(unsigned long int);
        
        if (flags & BLOCK_HAS_COPY_DISPOSE) {
            signatureLocation += sizeof(void(*)(void *dst, void *src));
            signatureLocation += sizeof(void (*)(void *src));
        }
        
        const char *signature = (*(const char **)signatureLocation);
        return signature;
    }
    
    return NULL;
}

NS_INLINE BOOL blockIsCompatibleWithMethodType(id block, __unsafe_unretained Class class, SEL selector, BOOL instanceMethod) {
    const char *blockType = blockGetType(block);

    NSMethodSignature *blockSignature = [NSMethodSignature signatureWithObjCTypes:blockType];
    NSMethodSignature *methodSignature = (instanceMethod ? [class instanceMethodSignatureForSelector:selector] : [class methodSignatureForSelector:selector]);
    
    if (!blockSignature || !methodSignature) {
        return NO;
    }
    
    if (blockSignature.numberOfArguments != methodSignature.numberOfArguments) {
        return NO;
    }
    const char *blockReturnType = blockSignature.methodReturnType;
    
    if (strncmp(blockReturnType, "@", 1) == 0) {
        blockReturnType = "@";
    }
    
    if (strcmp(blockReturnType, methodSignature.methodReturnType) != 0) {
        return NO;
    }
    
    for (unsigned int i = 0; i < methodSignature.numberOfArguments; i++) {
        if (i == 0) {
            // self in method, block in block
            if (strcmp([methodSignature getArgumentTypeAtIndex:i], "@") != 0) {
                return NO;
            }
            if (strcmp([blockSignature getArgumentTypeAtIndex:i], "@?") != 0) {
                return NO;
            }
        }
        else if(i == 1) {
            // SEL in method, self in block
            if (strcmp([methodSignature getArgumentTypeAtIndex:i], ":") != 0) {
                return NO;
            }
            if (instanceMethod ? strncmp([blockSignature getArgumentTypeAtIndex:i], "@", 1) != 0 : (strncmp([blockSignature getArgumentTypeAtIndex:i], "@", 1) != 0 && strcmp([blockSignature getArgumentTypeAtIndex:i], "r^#") != 0)) {
                return NO;
            }
        }
        else {
            const char *blockSignatureArg = [blockSignature getArgumentTypeAtIndex:i];
            
            if (strncmp(blockSignatureArg, "@", 1) == 0) {
                blockSignatureArg = "@";
            }
            
            if (strcmp(blockSignatureArg, [methodSignature getArgumentTypeAtIndex:i]) != 0) {
                return NO;
            }
        }
    }
    
    return YES;
}

NS_INLINE BOOL blockIsValidReplacementProvider(id block) {
    const char *blockType = blockGetType(block);
    
    JGMethodReplacementProvider dummy = JGMethodReplacementProviderBlock {
        return nil;
    };
    
    const char *expectedType = blockGetType(dummy);
    
    return (strcmp(expectedType, blockType) == 0);
}



NS_INLINE void classSwizzleMethod(Class cls, Method method, IMP newImp) {
	if (!class_addMethod(cls, method_getName(method), newImp, method_getTypeEncoding(method))) {
		// class already has implementation, swizzle it instead
		method_setImplementation(method, newImp);
	}
}





#pragma mark - Original Implementations

static OSSpinLock lock = OS_SPINLOCK_INIT;

static NSMutableDictionary *originalClassMethods;
static NSMutableDictionary *originalInstanceMethods;
static NSMutableDictionary *originalInstanceInstanceMethods;

NS_INLINE JG_IMP originalClassMethodImplementation(__unsafe_unretained Class class, SEL selector, BOOL fetchOnly) {
    NSCAssert(!OSSpinLockTry(&lock), @"Spin lock is not locked");
    
    if (!originalClassMethods) {
        originalClassMethods = [[NSMutableDictionary alloc] init];
    }
    
    NSString *classKey = NSStringFromClass(class);
    NSString *selectorKey = NSStringFromSelector(selector);
    
    NSMutableDictionary *classSwizzles = originalClassMethods[classKey];
    
    NSValue *pointerValue = classSwizzles[selectorKey];
    
    if (!classSwizzles) {
        classSwizzles = [NSMutableDictionary dictionary];
        
        originalClassMethods[classKey] = classSwizzles;
    }
    
    JG_IMP orig = NULL;
    
    if (pointerValue) {
        orig = [pointerValue pointerValue];
        
        if (fetchOnly) {
            if (classSwizzles.count == 1) {
                [originalClassMethods removeObjectForKey:classKey];
            }
            else {
                [classSwizzles removeObjectForKey:selectorKey];
            }
        }
    }
    else if (!fetchOnly) {
        orig = (JG_IMP)[class methodForSelector:selector];
        
        classSwizzles[selectorKey] = [NSValue valueWithPointer:orig];
    }

    if (classSwizzles.count == 0) {
        [originalClassMethods removeObjectForKey:classKey];
    }
    
    if (originalClassMethods.count == 0) {
        releaseIfNecessary(originalClassMethods);
        originalClassMethods = nil;
    }
    
    return orig;
}




NS_INLINE JG_IMP originalInstanceMethodImplementation(__unsafe_unretained Class class, SEL selector, BOOL fetchOnly) {
    NSCAssert(!OSSpinLockTry(&lock), @"Spin lock is not locked");
    
    if (!originalInstanceMethods) {
        originalInstanceMethods = [[NSMutableDictionary alloc] init];
    }
    
    NSString *classKey = NSStringFromClass(class);
    NSString *selectorKey = NSStringFromSelector(selector);
    
    NSMutableDictionary *classSwizzles = originalInstanceMethods[classKey];
    
    NSValue *pointerValue = classSwizzles[selectorKey];
    
    if (!classSwizzles) {
        classSwizzles = [NSMutableDictionary dictionary];
        
        originalInstanceMethods[classKey] = classSwizzles;
    }
    
    JG_IMP orig = NULL;
    
    if (pointerValue) {
        orig = [pointerValue pointerValue];
        
        if (fetchOnly) {
            [classSwizzles removeObjectForKey:selectorKey];
            if (classSwizzles.count == 0) {
                [originalInstanceMethods removeObjectForKey:classKey];
            }
        }
    }
    else if (!fetchOnly) {
        orig = (JG_IMP)[class instanceMethodForSelector:selector];
        
        classSwizzles[selectorKey] = [NSValue valueWithPointer:orig];
    }
    
    if (classSwizzles.count == 0) {
        [originalInstanceMethods removeObjectForKey:classKey];
    }
    
    if (originalInstanceMethods.count == 0) {
        releaseIfNecessary(originalInstanceMethods);
        originalInstanceMethods = nil;
    }
    
    return orig;
}





NS_INLINE JG_IMP originalInstanceInstanceMethodImplementation(__unsafe_unretained Class class, SEL selector, BOOL fetchOnly) {
    NSCAssert(!OSSpinLockTry(&lock), @"Spin lock is not locked");
    
    if (!originalInstanceInstanceMethods) {
        originalInstanceInstanceMethods = [[NSMutableDictionary alloc] init];
    }
    
    NSString *classKey = NSStringFromClass(class);
    NSString *selectorKey = NSStringFromSelector(selector);
    
    NSMutableDictionary *instanceSwizzles = originalInstanceInstanceMethods[classKey];
    
    if (!instanceSwizzles) {
        instanceSwizzles = [NSMutableDictionary dictionary];
        
        originalInstanceInstanceMethods[classKey] = instanceSwizzles;
    }
    
    JG_IMP orig = NULL;

    if (fetchOnly) {
        NSMutableDictionary *dict = instanceSwizzles[selectorKey];
        if (!dict) {
            return NULL;
        }
        NSValue *pointerValue = dict[kIMPKey];
        orig = [pointerValue pointerValue];
        unsigned int count = [dict[kCountKey] unsignedIntValue];
        if (count == 1) {
            [instanceSwizzles removeObjectForKey:selectorKey];
            if (instanceSwizzles.count == 0) {
                [originalInstanceInstanceMethods removeObjectForKey:classKey];
            }
        }
        else {
            dict[kCountKey] = @(count-1);
        }
    }
    else {
        NSMutableDictionary *dict = instanceSwizzles[selectorKey];
        if (!dict) {
            dict = [NSMutableDictionary dictionaryWithCapacity:2];
            dict[kCountKey] = @(1);
            
            orig = (JG_IMP)[class instanceMethodForSelector:selector];
            dict[kIMPKey] = [NSValue valueWithPointer:orig];
            
            instanceSwizzles[selectorKey] = dict;
        }
        else {
            orig = [dict[kIMPKey] pointerValue];
            
            unsigned int count = [dict[kCountKey] unsignedIntValue];
            dict[kCountKey] = @(count+1);
        }
    }
    
    if (originalInstanceInstanceMethods.count == 0) {
        releaseIfNecessary(originalInstanceInstanceMethods);
        originalInstanceInstanceMethods = nil;
    }
    
    return orig;
}


#pragma mark - Deswizzling Global Swizzles


NS_INLINE BOOL deswizzleClassMethod(__unsafe_unretained Class class, SEL selector) {
    OSSpinLockLock(&lock);
    
    JG_IMP originalIMP = originalClassMethodImplementation(class, selector, YES);
    
    if (originalIMP) {
        method_setImplementation(class_getClassMethod(class, selector), (IMP)originalIMP);
        OSSpinLockUnlock(&lock);
        return YES;
    }
    else {
        OSSpinLockUnlock(&lock);
        return NO;
    }
}


NS_INLINE BOOL deswizzleInstanceMethod(__unsafe_unretained Class class, SEL selector) {
    OSSpinLockLock(&lock);
    
    JG_IMP originalIMP = originalInstanceMethodImplementation(class, selector, YES);
    
    if (originalIMP) {
        method_setImplementation(class_getInstanceMethod(class, selector), (IMP)originalIMP);
        OSSpinLockUnlock(&lock);
        return YES;
    }
    else {
        OSSpinLockUnlock(&lock);
        return NO;
    }
}


NS_INLINE BOOL deswizzleAllClassMethods(__unsafe_unretained Class class) {
    OSSpinLockLock(&lock);
    BOOL success = NO;
    NSDictionary *d = [originalClassMethods[NSStringFromClass(class)] copy];
    for (NSString *sel in d) {
        OSSpinLockUnlock(&lock);
        if (deswizzleClassMethod(class, NSSelectorFromString(sel))) {
            success = YES;
        }
        OSSpinLockLock(&lock);
    }
    OSSpinLockUnlock(&lock);
    releaseIfNecessary(d);
    return success;
}


NS_INLINE BOOL deswizzleAllInstanceMethods(__unsafe_unretained Class class) {
    OSSpinLockLock(&lock);
    BOOL success = NO;
    NSDictionary *d = [originalInstanceMethods[NSStringFromClass(class)] copy];
    for (NSString *sel in d) {
        OSSpinLockUnlock(&lock);
        if (deswizzleInstanceMethod(class, NSSelectorFromString(sel))) {
            success = YES;
        }
        OSSpinLockLock(&lock);
    }
    OSSpinLockUnlock(&lock);
    releaseIfNecessary(d);
    return success;
}


#pragma mark - Global Swizzling

NS_INLINE void swizzleClassMethod(__unsafe_unretained Class class, SEL selector, JGMethodReplacementProvider replacement) {
    NSCAssert(blockIsValidReplacementProvider(replacement), @"Invalid method replacemt provider");
    
    NSCAssert([class respondsToSelector:selector], @"Invalid method: +[%@ %@]", NSStringFromClass(class), NSStringFromSelector(selector));
    
    OSSpinLockLock(&lock);
    
    Method originalMethod = class_getClassMethod(class, selector);
    
    JG_IMP orig = originalClassMethodImplementation(class, selector, NO);
    
    id replaceBlock = replacement(orig, class, selector);
    
    NSCAssert(blockIsCompatibleWithMethodType(replaceBlock, class, selector, NO), @"Invalid method replacement");
    
    Class meta = object_getClass(class);
    
    classSwizzleMethod(meta, originalMethod, imp_implementationWithBlock(replaceBlock));
    
    OSSpinLockUnlock(&lock);
}


NS_INLINE void swizzleInstanceMethod(__unsafe_unretained Class class, SEL selector, JGMethodReplacementProvider replacement) {
    NSCAssert(blockIsValidReplacementProvider(replacement), @"Invalid method replacemt provider");
    
    NSCAssert([class instancesRespondToSelector:selector], @"Invalid method: -[%@ %@]", NSStringFromClass(class), NSStringFromSelector(selector));
    
    NSCAssert(originalInstanceInstanceMethods[NSStringFromClass(class)][NSStringFromSelector(selector)] == nil, @"Swizzling an instance method that has already been swizzled on a specific instance is not supported");
    
    OSSpinLockLock(&lock);
    
    Method originalMethod = class_getInstanceMethod(class, selector);
    
    JG_IMP orig = originalInstanceMethodImplementation(class, selector, NO);
    
    id replaceBlock = replacement(orig, class, selector);
    
    NSCAssert(blockIsCompatibleWithMethodType(replaceBlock, class, selector, YES), @"Invalid method replacement");
    
    IMP replace = imp_implementationWithBlock(replaceBlock);
    
    classSwizzleMethod(class, originalMethod, replace);
    
    OSSpinLockUnlock(&lock);
}




#pragma mark - Instance Specific Swizzling & Deswizzling

static NSMutableDictionary *dynamicSubclassesByObject;

NS_INLINE unsigned int swizzleCount(__unsafe_unretained id object) {
    NSValue *key = [NSValue valueWithPointer:JGBridgeCast(const void *, object)];
    
    unsigned int count = [dynamicSubclassesByObject[key][kCountKey] unsignedIntValue];
    
    return count;
}

NS_INLINE void decreaseSwizzleCount(__unsafe_unretained id object) {
    NSValue *key = [NSValue valueWithPointer:JGBridgeCast(const void *, object)];
    
    NSMutableDictionary *classDict = dynamicSubclassesByObject[key];
    
    unsigned int count = [classDict[kCountKey] unsignedIntValue];
    
    classDict[kCountKey] = @(count-1);
}

NS_INLINE BOOL deswizzleInstance(__unsafe_unretained id object) {
    OSSpinLockLock(&lock);
    
    BOOL success = NO;
    
    if (swizzleCount(object) > 0) {
        Class dynamicSubclass = object_getClass(object);
        
        object_setClass(object, [object class]);
        
        objc_disposeClassPair(dynamicSubclass);
        
        [originalInstanceInstanceMethods removeObjectForKey:NSStringFromClass([object class])];
        
        [dynamicSubclassesByObject removeObjectForKey:[NSValue valueWithPointer:JGBridgeCast(const void *, object)]];
        
        if (!dynamicSubclassesByObject.count) {
            releaseIfNecessary(dynamicSubclassesByObject);
            dynamicSubclassesByObject = nil;
        }
        
        if (!originalInstanceInstanceMethods.count) {
            releaseIfNecessary(originalInstanceInstanceMethods);
            originalInstanceInstanceMethods = nil;
        }
        
        success = YES;
    }
    
    OSSpinLockUnlock(&lock);
    
    return success;
}

NS_INLINE BOOL deswizzleMethod(__unsafe_unretained id object, SEL selector) {
    OSSpinLockLock(&lock);
    
    BOOL success = NO;
    
    unsigned int count = swizzleCount(object);
    
    if (count == 1) {
        OSSpinLockUnlock(&lock);
        return deswizzleInstance(object);
    }
    else if (count > 1) {
        JG_IMP originalIMP = originalInstanceInstanceMethodImplementation([object class], selector, YES);
        if (originalIMP) {
            method_setImplementation(class_getInstanceMethod(object_getClass(object), selector), (IMP)originalIMP);
            
            success = YES;
        }
        
        decreaseSwizzleCount(object);
    }
    
    OSSpinLockUnlock(&lock);
    
    return success;
}


NS_INLINE void swizzleInstance(__unsafe_unretained id object, SEL selector, JGMethodReplacementProvider replacementProvider) {
    Class class = [object class];
    
    NSCAssert(blockIsValidReplacementProvider(replacementProvider), @"Invalid method replacemt provider");
    
    NSCAssert([object respondsToSelector:selector], @"Invalid method: -[%@ %@]", NSStringFromClass(class), NSStringFromSelector(selector));
    
    OSSpinLockLock(&lock);
    
	if (!dynamicSubclassesByObject) {
		dynamicSubclassesByObject = [[NSMutableDictionary alloc] init];
	};
    
    NSValue *key = [NSValue valueWithPointer:JGBridgeCast(const void *, object)];
    
    NSMutableDictionary *classDict = dynamicSubclassesByObject[key];
    
	Class newClass = [classDict[kClassKey] pointerValue];
    
	if (!classDict || !newClass) {
        NSString *dynamicSubclass = [NSStringFromClass(class) stringByAppendingFormat:@"_JGMS_%@", [[NSUUID UUID] UUIDString]];
		
        const char *newClsName = [dynamicSubclass UTF8String];
        
        NSCAssert(!objc_lookUpClass(newClsName), @"Class %@ already exists!\n", dynamicSubclass);
        
        newClass = objc_allocateClassPair(class, newClsName, 0);
        
        NSCAssert(newClass, @"Could not create class %@\n", dynamicSubclass);
        
        objc_registerClassPair(newClass);
        
        classDict = [NSMutableDictionary dictionary];
        classDict[kClassKey] = [NSValue valueWithPointer:JGBridgeCast(const void *, newClass)];
        classDict[kCountKey] = @(1);
        
        dynamicSubclassesByObject[[NSValue valueWithPointer:JGBridgeCast(const void *, object)]] = classDict;
        
        Method classMethod = class_getInstanceMethod(newClass, @selector(class));
        
        id swizzledClass = ^Class (__unsafe_unretained id self) {
            return class;
        };
        
        classSwizzleMethod(newClass, classMethod, imp_implementationWithBlock(swizzledClass));
        
        SEL deallocSel = sel_getUid("dealloc");
        if (selector != deallocSel) {
            // If you swizzle the same method twice it affects all instance.
            // https://github.com/JonasGessner/JGMethodSwizzler/issues/3
            // So if you're swizzling dealloc, the caller must do it.
            // This is George's hack since I don't know how to fix the underlying bug.
            Method dealloc = class_getInstanceMethod(newClass, deallocSel);
            __block JG_IMP deallocImp = (JG_IMP)method_getImplementation(dealloc);
            id deallocHandler = ^(__unsafe_unretained id self) {
                NSCAssert(deswizzleInstance(self), @"Deswizzling of class %@ failed", NSStringFromClass([self class]));
                
                if (deallocImp) {
                    deallocImp(self, deallocSel);
                }
            };
            
            classSwizzleMethod(newClass, dealloc, imp_implementationWithBlock(deallocHandler));
        }
    }
    else {
        unsigned int count = [classDict[kCountKey] unsignedIntValue];
        classDict[kCountKey] = @(count+1);
    }
    
    Method origMethod = class_getInstanceMethod(class, selector);
    
    JG_IMP origIMP = originalInstanceInstanceMethodImplementation([object class], selector, NO);
    
    id replaceBlock = replacementProvider(origIMP, class, selector);
    
    NSCAssert(blockIsCompatibleWithMethodType(replaceBlock, class, selector, YES), @"Invalid method replacement");
    
    classSwizzleMethod(newClass, origMethod, imp_implementationWithBlock(replaceBlock));
    
    object_setClass(object, newClass);
    
	OSSpinLockUnlock(&lock);
}



#pragma mark - Category Implementations

@implementation NSObject (JGMethodSwizzler)

+ (void)swizzleClassMethod:(SEL)selector withReplacement:(JGMethodReplacementProvider)replacementProvider {
    swizzleClassMethod(self, selector, replacementProvider);
}

+ (void)swizzleInstanceMethod:(SEL)selector withReplacement:(JGMethodReplacementProvider)replacementProvider {
    swizzleInstanceMethod(self, selector, replacementProvider);
}

@end


@implementation NSObject (JGMethodDeSwizzler)

+ (BOOL)deswizzleClassMethod:(SEL)selector {
    return deswizzleClassMethod(self, selector);
}

+ (BOOL)deswizzleInstanceMethod:(SEL)selector {
    return deswizzleInstanceMethod(self, selector);
}

+ (BOOL)deswizzleAllClassMethods {
    return deswizzleAllClassMethods(self);
}

+ (BOOL)deswizzleAllInstanceMethods {
    return deswizzleAllInstanceMethods(self);
}

+ (BOOL)deswizzleAllMethods {
    BOOL c = [self deswizzleAllClassMethods];
    BOOL i = [self deswizzleAllInstanceMethods];
    return (c || i);
}

@end



@implementation NSObject (JGInstanceSwizzler)

- (void)swizzleMethod:(SEL)selector withReplacement:(JGMethodReplacementProvider)replacementProvider {
    swizzleInstance(self, selector, replacementProvider);
}

- (BOOL)deswizzleMethod:(SEL)selector {
    return deswizzleMethod(self, selector);
}

- (BOOL)deswizzle {
    return deswizzleInstance(self);
}

@end



#pragma mark - Public functions

BOOL deswizzleGlobal(void) {
    BOOL success = NO;
    OSSpinLockLock(&lock);
    NSDictionary *d = originalClassMethods.copy;
    for (NSString *classKey in d) {
        OSSpinLockUnlock(&lock);
        BOOL ok = [NSClassFromString(classKey) deswizzleAllMethods];
        OSSpinLockLock(&lock);
        if (!success == ok) {
            success = YES;
        }
    }
    
    NSDictionary *d1 = originalInstanceMethods.copy;
    for (NSString *classKey in d1) {
        OSSpinLockUnlock(&lock);
        BOOL ok = [NSClassFromString(classKey) deswizzleAllMethods];
        OSSpinLockLock(&lock);
        if (!success == ok) {
            success = YES;
        }
    }
    OSSpinLockUnlock(&lock);
    
    releaseIfNecessary(d);
    releaseIfNecessary(d1);
    
    return success;
}


BOOL deswizzleInstances(void) {
    OSSpinLockLock(&lock);
    BOOL success = NO;
    NSDictionary *d = dynamicSubclassesByObject.copy;
    for (NSValue *pointer in d) {
        id object = [pointer pointerValue];
        OSSpinLockUnlock(&lock);
        BOOL ok = [object deswizzle];
        OSSpinLockLock(&lock);
        if (!success && ok) {
            success = YES;
        }
    }
    OSSpinLockUnlock(&lock);
    
    releaseIfNecessary(d);
    
    return success;
}

BOOL deswizzleAll(void) {
    BOOL a = deswizzleGlobal();
    BOOL b = deswizzleInstances();
    
    return (a || b);
}

//For debugging purposes:
//NSString *getStatus() {
//    return [NSString stringWithFormat:@"Original Class:\n%@\n\n\nOriginal Instance:\n%@\n\n\nOriginal Instance Specific:\n%@\n\n\nDynamic Subclasses:\n%@\n\n\n", originalClassMethods, originalInstanceMethods, originalInstanceInstanceMethods, dynamicSubclassesByObject];
//}


