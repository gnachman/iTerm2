//
//  NSData+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import <Foundation/Foundation.h>

@interface NSData (iTerm)

- (NSString *)stringWithBase64Encoding;
- (BOOL)containsAsciiCharacterInSet:(NSCharacterSet *)asciiSet;

@end
