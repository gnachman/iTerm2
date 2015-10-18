//
//  iTermObjectPool.h
//  iTerm
//
//  Created by George Nachman on 3/3/14.
//
//

#import <Foundation/Foundation.h>

// Example usage:
//
// @interface MyObject : iTermPooledObject
// + (instancetype)myObject;
// ...
// @end
//
// static iTermObjectPool *gPool;
//
// @implementation MyObject
// + (void)initialize {
//   gPool = [[iTermObjectPool alloc] initWithClass:self collections:10 objectsPerCollection:1000];
// }
//
// + (instancetype)myObject {
//   return (MyObject *)[gPool pooledObject];
// }
//
// // Optional to impelement -init, but it must be the designated initializer.
// - (instancetype)init {
//   ...
// }
//
// // NOTE: Do not implement dealloc. Implement this instead. Remember to 0 out ivars.
// - (void)destroyPooledObject {
//   [_member release];
//   _member = nil;
//   ...
// }
//
// @end
//
// Example client:
// MyObject *object = [MyObject myObject];
// ...
// [object recycleObject];

@class iTermObjectPool;

@interface iTermPooledObject : NSObject

- (void)recycleObject;
- (void)destroyPooledObject;  // Like dealloc

@end

@interface iTermObjectPool : NSObject

@property(nonatomic, readonly) iTermPooledObject *pooledObject;

- (instancetype)initWithClass:(Class)theClass
                  collections:(int)numCollections
         objectsPerCollection:(int)objectsPerCollection;

@end
