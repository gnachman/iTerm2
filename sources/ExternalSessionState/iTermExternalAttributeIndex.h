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

extern NSString *const iTermExternalAttributeBlockIDDelimiter;

typedef struct {
    BOOL valid;
    int code;
} iTermControlCodeAttribute;

// Immutable
@interface iTermExternalAttribute: NSObject<NSCopying>
@property (atomic, readonly) BOOL hasUnderlineColor;
@property (atomic, readonly) VT100TerminalColorValue underlineColor;
@property (atomic, copy, readonly, nullable) NSString *blockIDList;  // comma delimited
@property (nonatomic, readonly) NSString *humanReadableDescription;
@property (atomic, readonly) iTermControlCodeAttribute controlCode;
@property (atomic, readonly, nullable) NSNumber *controlCodeNumber;
@property (atomic, readonly, nullable) iTermURL *url;
// Per-line attribute stored on the first character of a wrapped line in LineBuffer.
// Used as a signal to re-insert DWL_SPACERs when reading from scrollback.
// Only set when entering LineBuffer; stripped when reading out.
@property (atomic, readonly) iTermLineAttribute lineAttribute;
@property (nonatomic, readonly) BOOL isDefault;
// Dual-mode foreground/background color carriers. When .valid is YES, the cell's
// foregroundColorMode (or backgroundColorMode) on screen_char_t is
// ColorModeExternal and the renderer picks .light or .dark based on the
// terminal's current appearance.
@property (atomic, readonly) iTermDualModeColor dualModeForeground;
@property (atomic, readonly) iTermDualModeColor dualModeBackground;

@property(nonatomic, readonly) NSDictionary *dictionaryValue;

+ (iTermExternalAttribute * _Nullable)attributeHavingUnderlineColor:(BOOL)hasUnderlineColor
                                                     underlineColor:(VT100TerminalColorValue)underlineColor
                                                                url:(iTermURL * _Nullable)url
                                                        blockIDList:(NSString * _Nullable)blockIDList
                                                        controlCode:(NSNumber * _Nullable)code
                                                 dualModeForeground:(iTermDualModeColor)dualFg
                                                 dualModeBackground:(iTermDualModeColor)dualBg;

+ (instancetype _Nullable)fromData:(NSData *)data;
+ (BOOL)externalAttribute:(iTermExternalAttribute * _Nullable)lhs
isEqualToExternalAttribute:(iTermExternalAttribute * _Nullable)rhs;
- (instancetype)init;
- (instancetype)initWithUnderlineColor:(VT100TerminalColorValue)color
                                   url:(iTermURL * _Nullable)url
                           blockIDList:(NSString * _Nullable)blocokIDList
                           controlCode:(NSNumber * _Nullable)code;
- (instancetype _Nullable)initWithDictionary:(NSDictionary *)dict;
- (BOOL)isEqualToExternalAttribute:(iTermExternalAttribute *)rhs;
- (NSData *)data;
// Returns a copy with lineAttribute set. If the receiver is nil and attr is
// non-singleWidth, creates a new minimal attribute.
- (iTermExternalAttribute *)copyWithLineAttribute:(iTermLineAttribute)attr;
+ (iTermExternalAttribute * _Nullable)attributeWithLineAttribute:(iTermLineAttribute)attr;
@end

@protocol iTermExternalAttributeIndexReading<NSCopying, NSMutableCopying, NSObject>
@property (nonatomic, readonly) NSDictionary<NSNumber *, iTermExternalAttribute *> *attributes;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
@property (nonatomic, readonly) BOOL isEmpty;
- (NSData *)data;
- (NSString *)shortDescriptionWithLength:(int)length;
- (iTermExternalAttributeIndex *)subAttributesInRange:(NSRange)range;
- (iTermExternalAttributeIndex *)subAttributesToIndex:(int)index;
- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index;
- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index maximumLength:(int)maxLength;
- (iTermExternalAttribute * _Nullable)objectAtIndexedSubscript:(NSInteger)idx;
- (id<iTermExternalAttributeIndexReading>)copy;
- (iTermExternalAttributeIndex *)indexByDeletingFirst:(int)n;
- (void)copyInto:(iTermExternalAttributeIndex *)destination;
- (void)copyFrom:(id<iTermExternalAttributeIndexReading> _Nullable)destination startOffset:(int)startOffset;
- (BOOL)isEqualToExternalAttributeIndex:(id<iTermExternalAttributeIndexReading>)other;
- (iTermExternalAttribute * _Nullable)attributeAtIndex:(int)i;
// Returns the lineAttribute if all entries share the same non-singleWidth
// value, or singleWidth if empty/mixed. Efficient for uniform attrs.
- (iTermLineAttribute)uniformLineAttribute;
@end

@interface iTermExternalAttributeIndex: NSObject<iTermExternalAttributeIndexReading>
@property (nonatomic, strong) NSDictionary<NSNumber *, iTermExternalAttribute *> *attributes;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;

+ (BOOL)externalAttributeIndex:(id<iTermExternalAttributeIndexReading> _Nullable)lhs
                isEqualToIndex:(id<iTermExternalAttributeIndexReading> _Nullable)rhs;

+ (instancetype _Nullable)withDictionary:(NSDictionary *)dictionary;  // return nil if input is NSNull
+ (instancetype _Nullable)fromData:(NSData *)data;
- (NSData *)data;
- (instancetype _Nullable)initWithDictionary:(NSDictionary *)dictionary;
- (NSString *)shortDescriptionWithLength:(int)length;

- (void)eraseAt:(int)x;
- (void)eraseInRange:(VT100GridRange)range;
- (void)deleteRange:(NSRange)range;
- (void)insertFrom:(iTermExternalAttributeIndex *)eaIndex
       sourceRange:(NSRange)sourceRange
           atIndex:(int)destinationIndex;

- (void)setAttributes:(iTermExternalAttribute * _Nullable)attributes at:(int)cursorX count:(int)count;
- (void)copyFrom:(id<iTermExternalAttributeIndexReading> _Nullable)source
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

- (void)copyFrom:(id<iTermExternalAttributeIndexReading> _Nullable)source
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
@property (nonatomic, readonly, nullable) NSString *identifier;
@property (nonatomic, readonly, nullable) NSString *target;
@property (nonatomic, readonly) NSData *data;

+ (instancetype _Nullable)urlWithData:(NSData * _Nullable)data code:(int)code;
+ (instancetype)urlWithURL:(NSURL *)url
                identifier:(NSString * _Nullable)identifier
                    target:(NSString * _Nullable)target;

@end


NS_ASSUME_NONNULL_END

