//
//  NSData+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import <Foundation/Foundation.h>

@interface NSData (iTerm)

// Tries to guess, from the first bytes of data, what kind of image it is and
// returns the corresponding UTI string constant. Not guaranteed to be correct.
@property(nonatomic, readonly) NSString *uniformTypeIdentifierForImageData;

  // Base-64 decodes string and returns data or nil.
+ (NSData *)dataWithBase64EncodedString:(NSString *)string;

// returns a string the the data base-64 encoded into 77-column lines divided by lineBreak.
- (NSString *)stringWithBase64EncodingWithLineBreak:(NSString *)lineBreak;

// Indicates if the data contains a single-byte code belonging to |asciiSet|.
- (BOOL)containsAsciiCharacterInSet:(NSCharacterSet *)asciiSet;

- (BOOL)hasPrefixOfBytes:(char *)bytes length:(int)length;


// Appends this data to the file at |path|. If |addNewline| is YES then a '\n' is appended if the
// file does not already end with \n or \r. This plays a little fast and loose with character
// encoding, but it gets the job done.
- (BOOL)appendToFile:(NSString *)path addLineBreakIfNeeded:(BOOL)addNewline;

@end
