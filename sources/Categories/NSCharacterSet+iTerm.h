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

+ (NSCharacterSet *)urlCharacterSet;
+ (NSCharacterSet *)filenameCharacterSet;
// Full-width punctuation used in CJK text that may follow a URL or a file name in prose. These
// code points are members of the IDN character set, so a run of URL or filename characters
// swallows them, but they cannot end a URL or a file name.
+ (NSCharacterSet *)it_trailingCJKPunctuationCharacterSet;
// The characters above plus the user-configurable +trailingPunctuationMarks.
+ (NSCharacterSet *)it_trailingPunctuationCharacterSet;
+ (NSCharacterSet *)emojiWithDefaultEmojiPresentation;
+ (NSCharacterSet *)emojiWithDefaultTextPresentation;
+ (NSCharacterSet *)strongRTLCodePoints;
+ (NSCharacterSet *)strongLTRCodePoints;
+ (NSCharacterSet *)it_unsafeForDisplayCharacters;
+ (NSCharacterSet *)it_base64Characters;
+ (NSCharacterSet *)it_urlSafeBase64Characters;
+ (NSCharacterSet *)it_accessibilityTrimCharacterSet;

@end
