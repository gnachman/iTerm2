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

// See EastAsianWidth.txt in Unicode 6.0.

// Full-width characters.
+ (instancetype)fullWidthCharacterSetForUnicodeVersion:(NSInteger)version;

// Ambiguous-width characters.
+ (instancetype)ambiguousWidthCharacterSetForUnicodeVersion:(NSInteger)version;

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
+ (NSCharacterSet *)flagCharactersForUnicodeVersion:(NSInteger)version;

@end
