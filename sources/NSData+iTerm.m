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

- (NSString *)stringWithBase64Encoding {
    int length = apr_base64_encode_len(self.length);
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
            [string appendString:@"\n"];
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

@end
