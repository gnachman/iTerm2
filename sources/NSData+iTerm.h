//
//  NSData+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import <Foundation/Foundation.h>

@interface NSData (iTerm)

+ (NSData *)dataWithBase64EncodedString:(NSString *)string;

// returns a string the the data base-64 encoded into 77-column lines divided by lineBreak.
- (NSString *)stringWithBase64EncodingWithLineBreak:(NSString *)lineBreak;

// Indicates if the data contains a single-byte code belonging to |asciiSet|.
- (BOOL)containsAsciiCharacterInSet:(NSCharacterSet *)asciiSet;

- (BOOL)hasPrefixOfBytes:(char *)bytes length:(int)length;

- (NSString *)uniformTypeIdentifierForImageData;

@end
