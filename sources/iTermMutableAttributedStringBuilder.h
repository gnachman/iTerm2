//
//  iTermMutableAttributedStringBuilder.h
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import <Foundation/Foundation.h>

#define ENABLE_TEXT_DRAWING_FAST_PATH 1

@protocol iTermAttributedString<NSObject>
@property (readonly) NSUInteger length;
- (void)addAttribute:(NSString *)name value:(id)value;
- (void)beginEditing;
- (void)endEditing;
- (void)appendAttributedString:(NSAttributedString *)attrString;
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
@property(nonatomic, copy) NSDictionary *attributes;
@property(nonatomic, readonly) NSInteger length;
@property(nonatomic, assign) BOOL asciiLigaturesAvailable;

- (void)appendString:(NSString *)string;
- (void)appendCharacter:(unichar)code;
- (void)disableFastPath;

@end

@interface iTermCheapAttributedString : NSObject<iTermAttributedString>
@property (nonatomic, readonly) unichar *characters;
@property (nonatomic, readonly) NSDictionary *attributes;
- (void)addAttribute:(NSString *)name value:(id)value;
@end

@interface NSMutableAttributedString(iTermMutableAttributedStringBuilder) <iTermAttributedString>
// Adds the attribute across the whole length of the string. For compat with
// how iTermCheapAttributedString works.
- (void)addAttribute:(NSString *)name value:(id)value;
@end

