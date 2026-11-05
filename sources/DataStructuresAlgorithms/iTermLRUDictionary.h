//
//  iTermLRUDictionary.h
//  iTerm2
//
//  Created by George Nachman on 11/1/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A dictionary that evicts the least recently used entries once the total cost exceeds the
// maximum size. Looking an entry up counts as using it. Not thread safe.
@interface iTermLRUDictionary<__covariant KeyType, __covariant ValueType>: NSObject

- (instancetype)initWithMaximumSize:(NSInteger)maximumSize NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (ValueType _Nullable)objectForKey:(KeyType)key;
- (nullable ValueType)objectForKeyedSubscript:(KeyType)key;

- (void)addObjectWithKey:(KeyType)key value:(ValueType)value cost:(NSInteger)cost;
- (void)removeObjectForKey:(KeyType)key;
- (void)removeAllObjects;

@end

NS_ASSUME_NONNULL_END
