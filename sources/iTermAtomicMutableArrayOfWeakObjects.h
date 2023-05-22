//
//  iTermAtomicMutableArrayOfWeakObjects.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/3/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermAtomicMutableArrayOfWeakObjects<ObjectType>: NSObject<NSFastEnumeration>
@property (atomic, readonly) NSArray<ObjectType> *strongObjects;
@property (atomic, readonly) NSUInteger count;

+ (instancetype)array;
// The argument will be nil if the object was already deallocated.
- (void)removeObjectsPassingTest:(BOOL (^)(ObjectType _Nullable anObject))block;
- (void)removeAllObjects;
- (void)addObject:(ObjectType)object;
- (void)prune;
- (iTermAtomicMutableArrayOfWeakObjects *)compactMap:(id (^)(ObjectType value))block;

@end

NS_ASSUME_NONNULL_END
