//
//  iTermEncoderAdapter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>
#import "iTermGraphEncoder.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermGraphCodable<NSObject>
- (BOOL)encodeGraphWithEncoder:(iTermGraphEncoder *)encoder;
@end

@protocol iTermUniquelyIdentifiable<NSObject>
- (NSString *)stringUniqueIdentifier;
@end

@protocol iTermEncoderAdapter<NSObject>
- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key;
- (void)setObject:(id)obj forKey:(NSString *)key;

- (void)encodeDictionaryWithKey:(NSString *)key
                     generation:(NSInteger)generation
                          block:(BOOL (^)(id<iTermEncoderAdapter> encoder))block;

- (void)encodeArrayWithKey:(NSString *)key
               identifiers:(NSArray<NSString *> *)identifiers
                generation:(NSInteger)generation
                     block:(BOOL (^)(id<iTermEncoderAdapter> encoder, NSString *identifier))block;

@end

@interface iTermGraphEncoderAdapter : NSObject<iTermEncoderAdapter>
@property (nonatomic, readonly) iTermGraphEncoder *encoder;

- (instancetype)initWithGraphEncoder:(iTermGraphEncoder *)encoder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermMutableDictionaryEncoderAdapter: NSObject<iTermEncoderAdapter>
@property (nonatomic, readonly) NSMutableDictionary<NSString *, id> *mutableDictionary;

- (instancetype)initWithMutableDictionary:(NSMutableDictionary *)mutableDictionary NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
