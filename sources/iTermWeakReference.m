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

@implementation iTermWeakReference {
    __weak id<iTermWeaklyReferenceable> _object;
    Class _class;
}

- (instancetype)initWithObject:(id<iTermWeaklyReferenceable>)object {
    assert([object conformsToProtocol:@protocol(iTermWeaklyReferenceable)]);
    if (self) {
        _object = object;
        _class = [object class];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p weak ref to %@>",
                             NSStringFromClass([self class]), self, _object];
}

- (id)weaklyReferencedObject {
    return _object;
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
    id theObject NS_VALID_UNTIL_END_OF_SCOPE;
    theObject = _object;

    // Prefer to use the object's class in case it got dynamically changed, but if the object has
    // already been deallocated used its cached class since we need to provide a non-nil signature.
    Class theClass = [theObject class] ?: _class;

    NSMethodSignature *signature;
    if (theObject) {
        signature = [theObject methodSignatureForSelector:selector];
    } else {
        signature = [theClass instanceMethodSignatureForSelector:selector];
    }

    return signature;
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    id theObject NS_VALID_UNTIL_END_OF_SCOPE;
    theObject = _object;

    if (theObject) {
        [invocation invokeWithTarget:theObject];
    }
}

@end

