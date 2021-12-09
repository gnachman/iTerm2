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

// Immutable
@interface iTermExternalAttribute: NSObject<NSCopying>
@property (nonatomic, readonly) BOOL hasUnderlineColor;
@property (nonatomic, readonly) VT100TerminalColorValue underlineColor;
@property (nonatomic, readonly) unsigned int urlCode;
@property (nonatomic, readonly) NSString *humanReadableDescription;

@property(nonatomic, readonly) NSDictionary *dictionaryValue;

+ (iTermExternalAttribute *)attributeHavingUnderlineColor:(BOOL)hasUnderlineColor
                                           underlineColor:(VT100TerminalColorValue)underlineColor
                                                  urlCode:(unsigned int)urlCode;

+ (instancetype)fromData:(NSData *)data;
- (instancetype)init;
- (instancetype)initWithUnderlineColor:(VT100TerminalColorValue)color
                               urlCode:(unsigned int)urlCode;
- (instancetype)initWithURLCode:(unsigned int)urlCode;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (BOOL)isEqualToExternalAttribute:(iTermExternalAttribute *)rhs;
- (NSData *)data;

@end

@protocol iTermExternalAttributeIndexReading<NSObject>
@property (nonatomic, readonly) NSDictionary<NSNumber *, iTermExternalAttribute *> *attributes;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
- (NSData *)data;
- (NSString *)shortDescriptionWithLength:(int)length;
- (id<iTermExternalAttributeIndexReading>)subAttributesToIndex:(int)index;
- (id<iTermExternalAttributeIndexReading>)subAttributesFromIndex:(int)index;
- (id<iTermExternalAttributeIndexReading>)subAttributesFromIndex:(int)index maximumLength:(int)maxLength;
- (id<iTermExternalAttributeIndexReading> _Nullable)objectAtIndexedSubscript:(NSInteger)idx;
@end

@interface iTermExternalAttributeIndex: NSObject<NSCopying, iTermExternalAttributeIndexReading>
@property (nonatomic, strong) NSDictionary<NSNumber *, iTermExternalAttribute *> *attributes;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;

+ (instancetype)withDictionary:(NSDictionary *)dictionary;  // return nil if input is NSNull
+ (instancetype)fromData:(NSData *)data;
- (NSData *)data;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSString *)shortDescriptionWithLength:(int)length;

- (void)eraseAt:(int)x;
- (void)eraseInRange:(VT100GridRange)range;
- (void)setAttributes:(iTermExternalAttribute *)attributes at:(int)cursorX count:(int)count;
- (void)copyFrom:(iTermExternalAttributeIndex *)source
          source:(int)source
     destination:(int)destination
           count:(int)count;
- (void)mutateAttributesFrom:(int)start
                          to:(int)end
                       block:(iTermExternalAttribute * _Nullable(^)(iTermExternalAttribute * _Nullable))block;

- (iTermExternalAttributeIndex *)subAttributesToIndex:(int)index;
- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index;
- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index maximumLength:(int)maxLength;
- (iTermExternalAttribute * _Nullable)objectAtIndexedSubscript:(NSInteger)idx;
- (void)setObject:(iTermExternalAttribute * _Nullable)ea atIndexedSubscript:(NSUInteger)i;

+ (iTermExternalAttributeIndex *)concatenationOf:(iTermExternalAttributeIndex *)lhs
                                      length:(int)lhsLength
                                        with:(iTermExternalAttributeIndex *)rhs
                                      length:(int)rhsLength;
@end

@interface iTermUniformExternalAttributes: iTermExternalAttributeIndex
+ (instancetype)withAttribute:(iTermExternalAttribute *)attr;

- (void)copyFrom:(iTermExternalAttributeIndex *)source
          source:(int)loadBase
     destination:(int)storeBase
           count:(int)count NS_UNAVAILABLE;
@end


@interface NSData(iTermExternalAttributes)
- (NSData *)modernizedScreenCharArray:(iTermExternalAttributeIndex * _Nullable * _Nullable)indexOut;
- (NSData *)legacyScreenCharArrayWithExternalAttributes:(iTermExternalAttributeIndex * _Nullable)eaIndex;
@end

NS_ASSUME_NONNULL_END
