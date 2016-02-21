//
//  NSData+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import "NSData+iTerm.h"

#import "DebugLogging.h"
#import "RegexKitLite.h"
#import <apr-1/apr_base64.h>

@implementation NSData (iTerm)

+ (NSData *)dataWithBase64EncodedString:(NSString *)string {
    const char *buffer = [[string stringByReplacingOccurrencesOfRegex:@"[\x0a\x0d]" withString:@""] UTF8String];
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
    [data setLength:resultLength];
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

- (NSString *)uniformTypeIdentifierForImageData {
    struct {
        const char *fingerprint;
        int length;
        CFStringRef uti;
    } identifiers[] = {
        { "BM", 2, kUTTypeBMP },
        { "GIF", 3, kUTTypeGIF },
        { "\xff\xd8\xff", 3, kUTTypeJPEG },
        { "\x00\x00\x01\x00", 4, kUTTypeICO },
        { "II\x2a\x00", 4, kUTTypeTIFF },
        { "MM\x00\x2a", 4, kUTTypeTIFF },
        { "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a", 8, kUTTypePNG },
        { "\x00\x00\x00\x0c\x6a\x50\x20\x20\x0d\x0a\x87\x0a", 12, kUTTypeJPEG2000 }
    };

    for (int i = 0; i < sizeof(identifiers) / sizeof(*identifiers); i++) {
        if (self.length >= identifiers[i].length &&
            !memcmp(self.bytes, identifiers[i].fingerprint, identifiers[i].length)) {
            return (NSString *)identifiers[i].uti;
        }
    }
    return nil;
}

- (BOOL)appendToFile:(NSString *)path addLineBreakIfNeeded:(BOOL)addNewline {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:path];
    if (!fileHandle) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fileHandle) {
            DLog(@"Failed to open for writing or create %@", path);
            return NO;
        }
    }

    @try {
        [fileHandle seekToEndOfFile];
        if (addNewline) {
            unsigned long long length = fileHandle.offsetInFile;
            if (length > 0) {
                [fileHandle seekToFileOffset:length - 1];
                NSData *data = [fileHandle readDataOfLength:1];
                if (data.length == 1) {
                    char lastByte = ((const char *)data.bytes)[0];
                    if (lastByte != '\r' && lastByte != '\n') {
                        [fileHandle seekToEndOfFile];
                        [fileHandle writeData:[NSData dataWithBytes:"\n" length:1]];
                    }
                }
            }
        }
        [fileHandle writeData:self];
        return YES;
    }
    @catch (NSException * e) {
        return NO;
    }
    @finally {
        [fileHandle closeFile];
    }
}

@end
