//
//  iTermMutableAttributedStringBuilder.h
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import <Foundation/Foundation.h>

#define ENABLE_TEXT_DRAWING_FAST_PATH 1

// NSvalue with range of columns
extern NSString *const iTermSourceColumnsAttribute;

// NSData mapping character index to source cell. Only for NSAttributedString, not for cheap strings.
extern NSString *const iTermSourceCellIndexAttribute;

// NSData mapping character index to destination cell. Only for NSAttributedString, not for cheap strings.
extern NSString *const iTermDrawInCellIndexAttribute;

@protocol iTermAttributedString<NSObject>
@property (readonly) NSUInteger length;
- (void)addAttribute:(NSString *)name value:(id)value;
- (void)beginEditing;
- (void)endEditing;
- (void)appendAttributedString:(NSAttributedString *)attrString;
- (NSRange)sourceColumnRange;
@end

// We don't render these characters with CoreText, so they will never get ligatures. This allows
// much better rendering performance because CoreText is very slow compared to Core Graphics.
static inline BOOL iTermCharacterSupportsFastPath(unichar code, BOOL asciiLigaturesAvailable) {
    if (asciiLigaturesAvailable) {
        return isalpha(code) || isnumber(code) || code == ' ';
    } else {
        return isascii(code);
    }
}

@interface iTermMutableAttributedStringBuilder : NSObject

// Either a NSMutableAttributedString or an iTermCheapAttributedString
@property(nonatomic, readonly) id attributedString;

// The attributes to apply to all future characters
@property(nonatomic, copy) NSDictionary *attributes;
@property(nonatomic, readonly) NSInteger length;
@property(nonatomic, assign) BOOL asciiLigaturesAvailable;
@property(nonatomic, assign) BOOL zippy;
@property(nonatomic) NSInteger endColumn;
@property(nonatomic) NSInteger startColumn;
@property(nonatomic) BOOL hasBidi;

- (void)appendString:(NSString *)string rtl:(BOOL)rtl sourceCell:(int)sourceCell drawInCell:(int)drawInCell;
- (void)appendCharacter:(unichar)code rtl:(BOOL)rtl sourceCell:(int)sourceCell drawInCell:(int)drawInCell;
- (void)disableFastPath;
- (void)enableExplicitDirectionControls;

@end

@interface iTermCheapAttributedString : NSObject<iTermAttributedString>
@property (nonatomic, readonly) unichar *characters;
@property (nonatomic, readonly) NSDictionary *attributes;
- (void)addAttribute:(NSString *)name value:(id)value;
- (iTermCheapAttributedString *)copyWithAttributes:(NSDictionary *)attributes;
@end

@interface NSMutableAttributedString(iTermMutableAttributedStringBuilder) <iTermAttributedString>
// Adds the attribute across the whole length of the string. For compat with
// how iTermCheapAttributedString works.
- (void)addAttribute:(NSString *)name value:(id)value;
@end

