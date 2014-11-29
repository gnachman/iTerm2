//
//  NSMutableData+iTerm.h
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import <Foundation/Foundation.h>

@interface NSMutableData (iTerm)

- (void)appendBytes:(unsigned char *)bytes length:(int)length excludingCharacter:(char)exclude;
- (void)replaceOccurrencesOfBytes:(const char *)searchBytes length:(int)searchLength
                        withBytes:(const char *)replacementBytes length:(int)replacementLength;

// These operate on UTF-8 NSData.
- (void)removeAsciiCharactersInSet:(NSCharacterSet *)characterSet;
- (void)escapeShellCharacters;

@end
