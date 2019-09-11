//
//  iTermWeakReference.h
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
// DO NOT USE THIS IF YOU CAN POSSIBLY AVOID IT
//
// This started as an attempt to build weak references without ARC. This turns out to be impossible
// because there's a race condition—you can't hold a mutex between the least release decrementing
// the reference count to 0 and the start of dealloc. Consequently, the original implementation was
// broken beyond repair.
//
// The new implementation uses ARC. It has no value whatsoever and should be avoided, except for
// backward compatibility with existing code.
//
// The only reason it continues to exist is that I don't trust that weak references work correctly
// in non-ARC code yet. I'll need to try removing it in beta and see if anything catches fire.
//
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

// Helps you distinguish true objects from proxies.
@protocol iTermWeakReference<NSObject>
// Returns the object if it has not been dealloc'ed, or nil if it has. The actual implementation is
// in iTermWeakReference, and this method does not get forwarded. Classes should not implement this.
- (id)weaklyReferencedObject;

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

// Returns a retained and autoreleases reference to the proxied object, or nil if it has been dealloced.
@property(nonatomic, readonly) ObjectType weaklyReferencedObject;

- (instancetype)initWithObject:(id<iTermWeaklyReferenceable>)object;

@end

// Use this macro inside a weakly referenceable object's @implementation.
#define ITERM_WEAKLY_REFERENCEABLE \
- (_Nullable id)weakSelf { \
    return [[[iTermWeakReference alloc] initWithObject:self] autorelease]; \
} \
- (void)dealloc { \
    if ([self respondsToSelector:@selector(iterm_dealloc)]) { \
        [self iterm_dealloc]; \
    } else { \
        [super dealloc];  \
    } \
} \

