//
//  iTermAtomicMutableArrayOfWeakObjects.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/3/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermAtomicMutableArrayOfWeakObjects<ObjectType>: NSObject
@property (atomic, readonly) NSArray<ObjectType> *strongObjects;
@property (atomic, readonly) NSUInteger count;

+ (instancetype)array;
- (void)removeObjectsPassingTest:(BOOL (^)(ObjectType anObject))block;
- (void)removeAllObjects;
- (void)addObject:(ObjectType)object;
@end

NS_ASSUME_NONNULL_END
