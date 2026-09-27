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
    if (!isascii(code)) {
        // The fast path skips CoreText shaping, so it draws each character's
        // isolated glyph. That is fine for scripts that don't shape, but breaks
        // cursive scripts (Arabic/Persian) whose letters must join. macOS's
        // isalpha()/isnumber() are locale-aware and return true for non-ASCII
        // letters/digits, which used to route Persian to this no-shaping path and
        // render every letter disconnected. Only ASCII is safe on the fast path.
        return NO;
    }
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

// Both settings are snapshotted here rather than read live from
// iTermAdvancedSettingsModel during the build.
- (instancetype)initWithPreferSpeedToFullLigatureSupport:(BOOL)preferSpeedToFullLigatureSupport
                                     lowFiCombiningMarks:(BOOL)lowFiCombiningMarks NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

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

