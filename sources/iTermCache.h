//
//  iTermCache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/5/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermCache<KeyType, ValueType>: NSObject

- (instancetype)initWithCapacity:(NSInteger)capacity NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable id)objectForKeyedSubscript:(KeyType<NSCopying>)key;
- (void)setObject:(ValueType)obj forKeyedSubscript:(KeyType<NSCopying>)key;

@end

NS_ASSUME_NONNULL_END
