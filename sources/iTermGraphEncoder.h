//
//  iTermGraphEncoder.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import <Foundation/Foundation.h>

#import "iTermEncoderGraphRecord.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermGraphEncoder : NSObject
@property (nonatomic, readonly) iTermEncoderGraphRecord *record;

- (void)encodeString:(NSString *)string forKey:(NSString *)key;
- (void)encodeNumber:(NSNumber *)number forKey:(NSString *)key;
- (void)encodeData:(NSData *)data forKey:(NSString *)key;
- (void)encodeDate:(NSDate *)date forKey:(NSString *)key;
- (void)encodeNullForKey:(NSString *)key;
- (void)encodeGraph:(iTermEncoderGraphRecord *)record;

// When encoding an array where all elements have the same key, use the identifer to distinguish
// array elements. For example, if you have an array of [obj1, obj2, obj3] whose identifiers are
// 1, 2, and 3 respectively and the array's value changes to [obj2, obj3, obj4] then the encoder
// can see that obj2 and obj3 don't need to be re-encoded if their generation is unchanged and
// that it can delete obj1.
- (void)encodeChildWithKey:(NSString *)key
                identifier:(NSString *)identifier
                generation:(NSInteger)generation
                     block:(void (^ NS_NOESCAPE)(iTermGraphEncoder *subencoder))block;

// Return nil from block to stop adding elements. Otherwise, return identifier.
// The block should use `identifier` as the key for the POD/graph it encodes.
// The keys of the POD/graphs encoded with `subencoder` are ignored.
- (void)encodeArrayWithKey:(NSString *)key
                generation:(NSInteger)generation
               identifiers:(NSArray<NSString *> *)identifiers
                     block:(void (^ NS_NOESCAPE)(NSString *identifier, NSInteger index, iTermGraphEncoder *subencoder))block;

- (void)encodeDictionary:(NSDictionary *)dict
                 withKey:(NSString *)key
              generation:(NSInteger)generation;

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString *)identifier
                 generation:(NSInteger)generation NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
