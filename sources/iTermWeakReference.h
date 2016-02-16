//
//  iTermWeakReference.h
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
// Provides a mostly-not-insane version of zeroing weak refs for manual reference counting.
// Usage:
//
// MyClass.h:
// @interface MyClass : Blah<iTermWeaklyReferenceable>
// - (void)doFoo;
// ...
// @end
//
// MyClass.m:
// @implementation MyClass
// ITERM_WEAKLY_REFERENCEABLE
// - (void)iterm_dealloc {
//    [_myIvar release];
//    [super dealloc];
// }
//
// Call site:
// MyClass *myObject = [[MyClass alloc] init];
// MyClass<iTermWeakReference> *weakReference = [myObject weakSelf];
// [weakReference doFoo];  // invokes [myObject doFoo]
// [myObject release];
// [weakReference doFoo];  // no-op
//
// Caveats:
// If a class is weakly referenceable, then all its subclasses must also be weakly referenceable.

#import <Foundation/Foundation.h>

// Objects that are capable of being weakly referenced must post this at the start of dealloc.
extern NSString *const iTermWeaklyReferenceableObjectWillDealloc;

// Helps you distinguish true objects from proxies.
@protocol iTermWeakReference<NSObject>
// Returns the object if it has not been dealloc'ed, or nil if it has. The actual implementation is
// in iTermWeakReference, and this method does not get forwarded. Classes should not implement this.
- (id)weaklyReferencedObject;

// For tests.
- (id)internal_unsafeObject;

@end

// Objects that can be weakly referenced must conform to this protocol and use the
// ITERM_WEAKLY_REFERENCEABLE macro inside their implementation.
@protocol iTermWeaklyReferenceable<NSObject>
// The returned object will conform to iTermWeakReference. Obj-C's type system doesn't deal well with
// assigning an id<iTermWeakReference> to an object of type Foo<iTermWeakReference>*, issuing a bogus
// warning.
- (id)weakSelf;
@optional
// Move your dealloc code into this optional method.
- (void)iterm_dealloc;
@end

// A weak reference to an object that forwards method invocations to it.
@interface iTermWeakReference<ObjectType> : NSProxy

// For tests only.
@property(nonatomic, readonly) ObjectType internal_unsafeObject;

// Returns a retained and autoreleases reference to the proxied object, or nil if it has been dealloced.
@property(nonatomic, readonly) ObjectType weaklyReferencedObject;

- (instancetype)initWithObject:(id<iTermWeaklyReferenceable>)object;

@end

// Use this macro inside a weakly referencable object's @implementation.
#define ITERM_WEAKLY_REFERENCEABLE \
- (id)weakSelf { \
    return [[[iTermWeakReference alloc] initWithObject:self] autorelease]; \
} \
- (void)dealloc { \
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermWeaklyReferenceableObjectWillDealloc object:self]; \
    if ([self respondsToSelector:@selector(iterm_dealloc)]) { \
        [self iterm_dealloc]; \
    } else { \
        [super dealloc];  \
    } \
} \

