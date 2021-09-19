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

@property(nonatomic, readonly) NSDictionary *dictionaryValue;

- (instancetype)init;
- (instancetype)initWithUnderlineColor:(VT100TerminalColorValue)color;
- (BOOL)isEqualToExternalAttribute:(iTermExternalAttribute *)rhs;

@end

@interface iTermExternalAttributeIndex: NSObject<NSCopying>
@property (nonatomic, strong) NSDictionary<NSNumber *, iTermExternalAttribute *> *attributes;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;

+ (instancetype)withDictionary:(NSDictionary *)dictionary;  // return nil if input is NSNull
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSString *)shortDescriptionWithLength:(int)length;

- (void)eraseAt:(int)x;
- (void)eraseInRange:(VT100GridRange)range;
- (void)setAttributes:(iTermExternalAttribute *)attributes at:(int)cursorX count:(int)count;
- (void)copyFrom:(iTermExternalAttributeIndex *)source
          source:(int)source
     destination:(int)destination
           count:(int)count;
- (iTermExternalAttributeIndex *)subAttributesToIndex:(int)index;
- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index;
- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index maximumLength:(int)maxLength;
- (iTermExternalAttribute * _Nullable)objectAtIndexedSubscript:(NSInteger)idx;
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


NS_ASSUME_NONNULL_END
