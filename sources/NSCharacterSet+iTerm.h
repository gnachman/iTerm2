//
//  NSCharacterSet+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 3/29/15.
//
//

#import <Foundation/Foundation.h>

@interface NSCharacterSet (iTerm)

// No code point less than this will be an emoji with a default emoji presentation.
extern unichar iTermMinimumDefaultEmojiPresentationCodePoint;

// Characters with the Default_Ignorable_Code_Point derived property.
// Includes things like zero-width spaces.
// See issue 9368.
+ (instancetype)ignorableCharactersForUnicodeVersion:(NSInteger)version;

+ (instancetype)spacingCombiningMarksForUnicodeVersion:(int)version;

+ (instancetype)emojiAcceptingVS16;

+ (instancetype)codePointsWithOwnCell;

+ (NSCharacterSet *)urlCharacterSet;
+ (NSCharacterSet *)filenameCharacterSet;
+ (NSCharacterSet *)emojiWithDefaultEmojiPresentation;
+ (NSCharacterSet *)emojiWithDefaultTextPresentation;
+ (NSCharacterSet *)modifierCharactersForcingFullWidthRendition;
+ (NSCharacterSet *)rtlSmellingCodePoints;
+ (NSCharacterSet *)strongRTLCodePoints;
+ (NSCharacterSet *)strongLTRCodePoints;
+ (NSCharacterSet *)it_unsafeForDisplayCharacters;
+ (NSCharacterSet *)it_base64Characters;
+ (NSCharacterSet *)it_urlSafeBase64Characters;

@end
