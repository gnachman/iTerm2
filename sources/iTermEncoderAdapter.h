//
//  iTermEncoderAdapter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>
#import "iTermGraphDeltaEncoder.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermGraphCodable<NSObject>
- (BOOL)encodeGraphWithEncoder:(iTermGraphEncoder *)encoder;
@end

@protocol iTermUniquelyIdentifiable<NSObject>
- (NSString *)stringUniqueIdentifier;
@end

@protocol iTermEncoderAdapter<NSObject>
- (void)setObject:(id _Nullable)obj forKeyedSubscript:(NSString *)key;
- (void)setObject:(id _Nullable)obj forKey:(NSString *)key;
- (void)mergeDictionary:(NSDictionary *)dictionary;

- (BOOL)encodePropertyList:(id)plist withKey:(NSString *)key;

- (BOOL)encodeDictionaryWithKey:(NSString *)key
                     generation:(NSInteger)generation
                          block:(BOOL (^ NS_NOESCAPE)(id<iTermEncoderAdapter> encoder))block;

- (void)encodeArrayWithKey:(NSString *)key
               identifiers:(NSArray<NSString *> *)identifiers
                generation:(NSInteger)generation
                     block:(BOOL (^ NS_NOESCAPE)(id<iTermEncoderAdapter> encoder,
                                                 NSInteger i,
                                                 NSString *identifier,
                                                 BOOL *stop))block;

- (void)encodeArrayWithKey:(NSString *)key
               identifiers:(NSArray<NSString *> *)identifiers
                generation:(NSInteger)generation
                   options:(iTermGraphEncoderArrayOptions)options
                     block:(BOOL (^ NS_NOESCAPE)(id<iTermEncoderAdapter> encoder,
                                                 NSInteger i,
                                                 NSString *identifier,
                                                 BOOL *stop))block;

@end

@interface iTermGraphEncoderAdapter : NSObject<iTermEncoderAdapter>
@property (nonatomic, readonly) iTermGraphEncoder *encoder;

- (instancetype)initWithGraphEncoder:(iTermGraphEncoder *)encoder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermMutableDictionaryEncoderAdapter: NSObject<iTermEncoderAdapter>
@property (nonatomic, readonly) NSMutableDictionary<NSString *, id> *mutableDictionary;

+ (instancetype)encoder;
- (instancetype)initWithMutableDictionary:(NSMutableDictionary *)mutableDictionary NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
