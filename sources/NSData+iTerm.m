//
//  NSData+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import "NSData+iTerm.h"
#import <apr-1/apr_base64.h>

@implementation NSData (iTerm)

+ (NSData *)dataWithBase64EncodedString:(NSString *)string {
    // TODO: Handle objects other than images.
    const char *buffer = [string UTF8String];
    int destLength = apr_base64_decode_len(buffer);
    if (destLength <= 0) {
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:destLength];
    char *decodedBuffer = [data mutableBytes];
    int resultLength = apr_base64_decode(decodedBuffer, buffer);
    if (resultLength <= 0) {
        return nil;
    }
    return data;
}

- (NSString *)stringWithBase64EncodingWithLineBreak:(NSString *)lineBreak {
    // Subtract because the result includes the trailing null. Take MAX in case it returns 0 for
    // some reason.
    int length = MAX(0, apr_base64_encode_len(self.length) - 1);
    NSMutableData *buffer = [NSMutableData dataWithLength:length];
    if (buffer) {
        apr_base64_encode_binary(buffer.mutableBytes,
                                 self.bytes,
                                 self.length);
    }
    NSMutableString *string = [NSMutableString string];
    int remaining = length;
    int offset = 0;
    char *bytes = (char *)buffer.mutableBytes;
    while (remaining > 0) {
        @autoreleasepool {
            NSString *chunk = [[[NSString alloc] initWithBytes:bytes + offset
                                                        length:MIN(77, remaining)
                                                      encoding:NSUTF8StringEncoding] autorelease];
            [string appendString:chunk];
            [string appendString:lineBreak];
            remaining -= chunk.length;
            offset += chunk.length;
        }
    }
    return string;
}

- (BOOL)containsAsciiCharacterInSet:(NSCharacterSet *)asciiSet {
    char flags[256];
    for (int i = 0; i < 256; i++) {
        flags[i] = [asciiSet characterIsMember:i];
    }
    const unsigned char *bytes = [self bytes];
    int length = [self length];
    for (int i = 0; i < length; i++) {
        if (flags[bytes[i]]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)hasPrefixOfBytes:(char *)bytes length:(int)length {
    if (self.length < length) {
        return NO;
    }
    char *myBytes = (char *)self.bytes;
    return !memcmp(myBytes, bytes, length);
}

@end
