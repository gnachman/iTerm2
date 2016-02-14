//
//  iTermWeakReference.h
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import <Foundation/Foundation.h>

// A poor man's weak reference. Doesn't work with class clusters like NSMutableString. Works by
// dynamically subclassing the object and swizzling -dealloc.
//
// Usage:
//
// MyObject *myObject = [[MyObject alloc] init];
// MyObject *weakRef = [myObject weakSelf];
// ...
// [weakRef foo];  // calls -[myObject foo]
// assert(weakRef.proxiedObject);
// [myObject release];
// assert(!weakRef.proxiedObject);  // This is how you can tell the object has been released
// [weakRef foo];  // does nothing
@interface iTermWeakReference<ObjectType> : NSProxy

@property(nonatomic, readonly) ObjectType proxiedObject;

// Returns the object not retained and autoreleased. For tests.
@property(nonatomic, readonly) ObjectType internal_unsafeObject;

- (ObjectType)initWithObject:(id)object;

@end

@interface NSObject(iTermWeakReference)
- (instancetype)weakSelf;
@end
