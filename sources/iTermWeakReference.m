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
#import <os/lock.h>

NSString *const iTermWeaklyReferenceableObjectWillDealloc = @"iTermWeaklyReferenceableObjectWillDealloc";

static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;

@implementation iTermWeakReference {
    id<iTermWeaklyReferenceable> _object;
    Class _class;
}

- (instancetype)initWithObject:(id<iTermWeaklyReferenceable>)object {
    assert([object conformsToProtocol:@protocol(iTermWeaklyReferenceable)]);
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
    os_unfair_lock_lock(&lock);
    _object = nil;
    os_unfair_lock_unlock(&lock);
    [_class release];
    [super dealloc];
}

- (NSString *)description {
    os_unfair_lock_lock(&lock);
    id theObject = [_object retain];
    os_unfair_lock_unlock(&lock);

    NSString *description = [NSString stringWithFormat:@"<%@: %p weak ref to %@>",
                             NSStringFromClass([self class]), self, theObject];
    [theObject release];
    return description;
}

- (id)internal_unsafeObject {
    return _object;
}

- (id)weaklyReferencedObject {
    os_unfair_lock_lock(&lock);
    id theObject = [_object retain];
    os_unfair_lock_unlock(&lock);

    return [theObject autorelease];
}

#pragma mark - Notifications

- (void)objectWillDealloc:(NSNotification *)notification {
    os_unfair_lock_lock(&lock);
    _object = nil;
    os_unfair_lock_unlock(&lock);
}

#pragma mark - NSProxy

- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([NSStringFromSelector(aSelector) isEqualToString:NSStringFromSelector(@selector(weaklyReferencedObject))]) {
        return YES;
    } else {
        return [super respondsToSelector:aSelector];
    }
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    os_unfair_lock_lock(&lock);
    id theObject = [_object retain];
    // Prefer to use the object's class in case it got dynamically changed, but if the object has
    // already been deallocated used its cached class since we need to provide a non-nil signature.
    Class theClass = _object.class ?: _class;
    [theClass retain];
    os_unfair_lock_unlock(&lock);

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
    os_unfair_lock_lock(&lock);
    id theObject = [_object retain];
    os_unfair_lock_unlock(&lock);

    if (theObject) {
        [invocation invokeWithTarget:theObject];
        [theObject release];
    }
}

@end

