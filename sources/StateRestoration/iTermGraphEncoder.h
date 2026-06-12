//
//  iTermGraphEncoder.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import <Foundation/Foundation.h>

#import "iTermEncoderGraphRecord.h"

extern NSInteger iTermGenerationAlwaysEncode;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermGraphEncoderState) {
    iTermGraphEncoderStateLive,
    iTermGraphEncoderStateCommitted,
    iTermGraphEncoderStateRolledBack
};

typedef NS_OPTIONS(NSUInteger, iTermGraphEncoderArrayOptions) {
    iTermGraphEncoderArrayOptionsNone = 0,
    iTermGraphEncoderArrayOptionsReverse = (1 << 0)
};

@protocol iTermGraphEncodable<NSObject>
- (BOOL)graphEncoderShouldIgnore;
@end

@interface iTermGraphEncoder : NSObject
// nil if rolled back.
@property (nullable, nonatomic, readonly) iTermEncoderGraphRecord *record;
@property (nonatomic, readonly) iTermGraphEncoderState state;

- (void)encodeString:(NSString *)string forKey:(NSString *)key;
- (void)encodeNumber:(NSNumber *)number forKey:(NSString *)key;
- (void)encodeData:(NSData *)data forKey:(NSString *)key;
- (void)encodeDate:(NSDate *)date forKey:(NSString *)key;
- (void)encodeNullForKey:(NSString *)key;
- (BOOL)encodeObject:(id)obj key:(NSString *)key;
- (void)encodeGraph:(iTermEncoderGraphRecord *)record;
- (BOOL)encodePropertyList:(id)plist withKey:(NSString *)key;

- (void)mergeDictionary:(NSDictionary *)dictionary;

// When encoding an array where all elements have the same key, use the identifer to distinguish
// array elements. For example, if you have an array of [obj1, obj2, obj3] whose identifiers are
// 1, 2, and 3 respectively and the array's value changes to [obj2, obj3, obj4] then the encoder
// can see that obj2 and obj3 don't need to be re-encoded if their generation is unchanged and
// that it can delete obj1.
//
// The block can return NO to rollback any changes it has made.
- (BOOL)encodeChildWithKey:(NSString *)key
                identifier:(NSString *)identifier
                generation:(NSInteger)generation
                     block:(BOOL (^ NS_NOESCAPE)(iTermGraphEncoder *subencoder))block;

- (void)encodeChildrenWithKey:(NSString *)key
                  identifiers:(NSArray<NSString *> *)identifiers
                   generation:(NSInteger)generation
                        block:(BOOL (^)(NSString *identifier,
                                        NSUInteger idx,
                                        iTermGraphEncoder *subencoder,
                                        BOOL *stop))block;

// Return nil from block to stop adding elements. Otherwise, return identifier.
// The block should use `identifier` as the key for the POD/graph it encodes.
// The keys of the POD/graphs encoded with `subencoder` are ignored.
- (void)encodeArrayWithKey:(NSString *)key
                generation:(NSInteger)generation
               identifiers:(NSArray<NSString *> *)identifiers
                   options:(iTermGraphEncoderArrayOptions)options
                     block:(BOOL (^ NS_NOESCAPE)(NSString *identifier,
                                                 NSInteger i,
                                                 iTermGraphEncoder *subencoder,
                                                 BOOL *stop))block;

- (void)encodeDictionary:(NSDictionary *)dict
                 withKey:(NSString *)key
              generation:(NSInteger)generation;

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString *)identifier
                 generation:(NSInteger)generation NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithRecord:(iTermEncoderGraphRecord *)record;

- (instancetype)init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
