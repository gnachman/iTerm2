//
//  iTermOrderedDictionary.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/29/20.
//

#import <Foundation/Foundation.h>
#import "iTermTuple.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermOrderedDictionary<__covariant KeyType, __covariant ObjectType> : NSObject
@property (nonatomic, readonly) NSString *debugString;

+ (instancetype)byMapping:(NSArray<ObjectType> *)array
                    block:(nullable KeyType _Nullable (^NS_NOESCAPE)(NSUInteger index, ObjectType object))block;
+ (instancetype)byMappingEnumerator:(NSEnumerator<ObjectType> *)array
                              block:(nullable KeyType (^NS_NOESCAPE)(NSUInteger index, ObjectType object))block;
+ (instancetype)withTuples:(NSArray<iTermTuple<KeyType, ObjectType> *> *)tuples;

- (NSArray<KeyType> *)keys;
- (NSArray<ObjectType> *)values;
- (nullable ObjectType)objectForKeyedSubscript:(KeyType)key;

@end

NS_ASSUME_NONNULL_END
