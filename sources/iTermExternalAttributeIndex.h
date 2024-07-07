//
//  iTermExternalAttributeIndex.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/17/21.
//

#import <Foundation/Foundation.h>
#include <simd/vector_types.h>

#import "VT100GridTypes.h"
#import "ScreenChar.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermExternalAttributeIndex;
@class iTermURL;

typedef struct {
    BOOL valid;
    int code;
} iTermControlCodeAttribute;

// Immutable
@interface iTermExternalAttribute: NSObject<NSCopying>
@property (atomic, readonly) BOOL hasUnderlineColor;
@property (atomic, readonly) VT100TerminalColorValue underlineColor;
@property (atomic, copy, readonly) NSString *blockID;
@property (nonatomic, readonly) NSString *humanReadableDescription;
@property (atomic, readonly) iTermControlCodeAttribute controlCode;
@property (atomic, readonly, nullable) NSNumber *controlCodeNumber;
@property (atomic, readonly, nullable) iTermURL *url;

@property(nonatomic, readonly) NSDictionary *dictionaryValue;

+ (iTermExternalAttribute * _Nullable)attributeHavingUnderlineColor:(BOOL)hasUnderlineColor
                                                     underlineColor:(VT100TerminalColorValue)underlineColor
                                                                url:(iTermURL * _Nullable)url
                                                            blockID:(NSString * _Nullable)blockID
                                                        controlCode:(NSNumber * _Nullable)code;

+ (instancetype _Nullable)fromData:(NSData *)data;
- (instancetype)init;
- (instancetype)initWithUnderlineColor:(VT100TerminalColorValue)color
                                   url:(iTermURL * _Nullable)url
                               blockID:(NSString * _Nullable)blocokID
                           controlCode:(NSNumber *)code;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (BOOL)isEqualToExternalAttribute:(iTermExternalAttribute *)rhs;
- (NSData *)data;
@end

@protocol iTermExternalAttributeIndexReading<NSCopying, NSMutableCopying, NSObject>
@property (nonatomic, readonly) NSDictionary<NSNumber *, iTermExternalAttribute *> *attributes;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
- (NSData *)data;
- (NSString *)shortDescriptionWithLength:(int)length;
- (iTermExternalAttributeIndex *)subAttributesToIndex:(int)index;
- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index;
- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index maximumLength:(int)maxLength;
- (iTermExternalAttribute * _Nullable)objectAtIndexedSubscript:(NSInteger)idx;
- (id<iTermExternalAttributeIndexReading>)copy;
@end

@interface iTermExternalAttributeIndex: NSObject<iTermExternalAttributeIndexReading>
@property (nonatomic, strong) NSDictionary<NSNumber *, iTermExternalAttribute *> *attributes;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;

+ (instancetype _Nullable)withDictionary:(NSDictionary *)dictionary;  // return nil if input is NSNull
+ (instancetype _Nullable)fromData:(NSData *)data;
- (NSData *)data;
- (instancetype _Nullable)initWithDictionary:(NSDictionary *)dictionary;
- (NSString *)shortDescriptionWithLength:(int)length;

- (void)eraseAt:(int)x;
- (void)eraseInRange:(VT100GridRange)range;
- (void)setAttributes:(iTermExternalAttribute * _Nullable)attributes at:(int)cursorX count:(int)count;
- (void)copyFrom:(iTermExternalAttributeIndex * _Nullable)source
          source:(int)source
     destination:(int)destination
           count:(int)count;
- (void)mutateAttributesFrom:(int)start
                          to:(int)end
                       block:(iTermExternalAttribute * _Nullable(^)(iTermExternalAttribute * _Nullable))block;

- (iTermExternalAttributeIndex *)subAttributesToIndex:(int)index;
- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index;
- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index maximumLength:(int)maxLength;
- (void)setObject:(iTermExternalAttribute * _Nullable)ea atIndexedSubscript:(NSUInteger)i;

+ (iTermExternalAttributeIndex *)concatenationOf:(id<iTermExternalAttributeIndexReading>)lhs
                                      length:(int)lhsLength
                                        with:(id<iTermExternalAttributeIndexReading>)rhs
                                      length:(int)rhsLength;
@end

@interface iTermUniformExternalAttributes: iTermExternalAttributeIndex
+ (instancetype)withAttribute:(iTermExternalAttribute *)attr;

- (void)copyFrom:(iTermExternalAttributeIndex * _Nullable)source
          source:(int)source
     destination:(int)destination
           count:(int)count NS_UNAVAILABLE;
@end


@interface NSData(iTermExternalAttributes)
- (NSData *)migrateV1ToV3:(iTermExternalAttributeIndex * _Nullable * _Nonnull)indexOut;
- (NSMutableData *)migrateV2ToV3;
- (NSData *)legacyScreenCharArrayWithExternalAttributes:(iTermExternalAttributeIndex * _Nullable)eaIndex;
@end

// Represents an OSC 8 URL.
@interface iTermURL: NSObject
@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSData *data;

+ (instancetype _Nullable)urlWithData:(NSData * _Nullable)data code:(int)code;
+ (instancetype)urlWithURL:(NSURL *)url identifier:(NSString * _Nullable)identifier;

@end


NS_ASSUME_NONNULL_END

