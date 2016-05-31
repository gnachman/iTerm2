//
//  iTermWeakReference.m
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import "iTermWeakReference.h"

#import "DebugLogging.h"

#import <objc/runtime.h>

NSString *const iTermWeaklyReferenceableObjectWillDealloc = @"iTermWeaklyReferenceableObjectWillDealloc";

static OSSpinLock lock = OS_SPINLOCK_INIT;

@implementation iTermWeakReference {
    id<iTermWeaklyReferenceable> _object;
    Class _class;
}

- (instancetype)initWithObject:(id<iTermWeaklyReferenceable>)object {
    if (self) {
        _object = object;
        _class = [[object class] retain];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(objectWillDealloc:)
                                                     name:iTermWeaklyReferenceableObjectWillDealloc
                                                   object:_object];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    OSSpinLockLock(&lock);
    _object = nil;
    OSSpinLockUnlock(&lock);
    [_class release];
    [super dealloc];
}

- (NSString *)description {
    OSSpinLockLock(&lock);
    id theObject = [_object retain];
    OSSpinLockUnlock(&lock);
    
    NSString *description = [NSString stringWithFormat:@"<%@: %p weak ref to %@>",
                             NSStringFromClass([self class]), self, theObject];
    [theObject release];
    return description;
}

- (id)internal_unsafeObject {
    return _object;
}

- (id)weaklyReferencedObject {
    OSSpinLockLock(&lock);
    id theObject = [_object retain];
    OSSpinLockUnlock(&lock);

    return [theObject autorelease];
}

#pragma mark - Notifications

- (void)objectWillDealloc:(NSNotification *)notification {
    OSSpinLockLock(&lock);
    _object = nil;
    OSSpinLockUnlock(&lock);
}

#pragma mark - NSProxy

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    OSSpinLockLock(&lock);
    id theObject = [_object retain];
    // Prefer to use the object's class in case it got dynamically changed, but if the object has
    // already been deallocated used its cached class since we need to provide a non-nil signature.
    Class theClass = _object.class ?: _class;
    [theClass retain];
    OSSpinLockUnlock(&lock);

    NSMethodSignature *signature;
    if (theObject) {
        signature = [theObject methodSignatureForSelector:selector];
    } else {
        signature = [theClass instanceMethodSignatureForSelector:selector];
    }
    [theClass release];
    [theObject release];

    return signature;
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    OSSpinLockLock(&lock);
    id theObject = [_object retain];
    OSSpinLockUnlock(&lock);

    if (theObject) {
        [invocation invokeWithTarget:theObject];
        [theObject release];
    }
}

@end

