//
//  iTermWeakReference.h
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import <Foundation/Foundation.h>

// TODO: This should be an NSProxy, see http://stackoverflow.com/questions/4692161/non-retaining-array-for-delegates
@interface iTermWeakReference<ObjectType> : NSObject

// When object is dealloc'ed this pointer becomes nil. No attempts at thread safety here; only
// suitable for objects that get dealloced on the main thread.
@property(nonatomic, readonly) ObjectType object;

// Returns the object not retained and autoreleased. For tests.
@property(nonatomic, readonly) ObjectType unsafeObject;

+ (instancetype)weakReferenceToObject:(ObjectType)object;
- (instancetype)initWithObject:(id)object;

@end

@interface NSObject(iTermWeakReference)
- (iTermWeakReference *)weakSelf;
@end
