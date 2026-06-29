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
+ (NSCharacterSet *)emojiWithDefaultEmojiPresentation;
+ (NSCharacterSet *)emojiWithDefaultTextPresentation;
+ (NSCharacterSet *)strongRTLCodePoints;
+ (NSCharacterSet *)strongLTRCodePoints;
+ (NSCharacterSet *)it_unsafeForDisplayCharacters;
+ (NSCharacterSet *)it_base64Characters;
+ (NSCharacterSet *)it_urlSafeBase64Characters;
+ (NSCharacterSet *)it_accessibilityTrimCharacterSet;

@end
