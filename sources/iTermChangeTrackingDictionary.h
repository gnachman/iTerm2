//
//  iTermChangeTrackingDictionary.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/25/23.
//

#import <Foundation/Foundation.h>
#import "iTermEncoderAdapter.h"

NS_ASSUME_NONNULL_BEGIN

// A mutable dictionary that tracks a generation number of each key. Careful! The list of generations grows monotonically.
@interface iTermChangeTrackingDictionary<__covariant KeyType, __covariant ObjectType> : NSObject<iTermGraphCodable>

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSDictionary<KeyType, ObjectType> *dictionary;
@property (nonatomic, readonly) NSArray<KeyType> *allKeys;

- (nullable ObjectType)objectForKey:(KeyType)aKey;
- (void)setObject:(ObjectType _Nullable)anObject forKey:(KeyType <NSCopying>)aKey;

- (nullable ObjectType)objectForKeyedSubscript:(KeyType)key;
- (void)setObject:(nullable ObjectType)obj forKeyedSubscript:(KeyType <NSCopying>)key;

- (void)removeObjectForKey:(KeyType)key;

- (void)enumerateKeysAndObjectsUsingBlock:(void (^ NS_NOESCAPE)(KeyType key, ObjectType obj, BOOL *stop))block;

- (NSInteger)generationForKey:(KeyType)key;
- (void)loadFromRecord:(iTermEncoderGraphRecord *)record
              keyClass:(Class)keyClass
            valueClass:(Class)valueClass;

@end

NS_ASSUME_NONNULL_END
