//
//  NSMutableData+iTerm.m
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import "NSMutableData+iTerm.h"
#import "NSStringITerm.h"

@implementation NSMutableData (iTerm)

- (void)appendBytes:(unsigned char *)bytes length:(int)length excludingCharacter:(char)exclude {
    int i;
    int lastIndex = 0;
    for (i = 0; i < length; i++) {
        if (bytes[i] == exclude) {
            if (i > lastIndex) {
                [self appendBytes:bytes + lastIndex length:i - lastIndex];
            }
            lastIndex = i + 1;
        }
    }
    if (i > lastIndex) {
        [self appendBytes:bytes + lastIndex length:i - lastIndex];
    }
}

- (void)replaceOccurrencesOfBytes:(const char *)searchBytes length:(int)searchLength
                        withBytes:(const char *)replacementBytes length:(int)replacementLength {
    NSMutableData *dataWithReplacements = [NSMutableData data];
    const char *bytes = [self bytes];

    NSData *searchData = [NSData dataWithBytes:searchBytes length:searchLength];

    int offset = 0;
    while (offset < self.length) {
        NSRange searchRange = NSMakeRange(offset, self.length - offset);
        NSRange bytesRange = [self rangeOfData:searchData options:0 range:searchRange];
        if (bytesRange.location == NSNotFound) {
            bytesRange.location = self.length;
        }
        [dataWithReplacements appendBytes:bytes + offset length:bytesRange.location - offset];
        offset = NSMaxRange(bytesRange);
    }
    [self setData:dataWithReplacements];
}

- (void)escapeShellCharacters {
    NSString *charsToEscape = [NSString shellEscapableCharacters];
    char flags[256] = { 0 };
    for (int i = 0; i < charsToEscape.length; i++) {
        unsigned int c = [charsToEscape characterAtIndex:i];
        flags[c] = 1;
    }

    NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
    const char *bytes = [self bytes];
    int length = [self length];
    for (int i = 0; i < length; i++) {
        unsigned int c = bytes[i];
        if (flags[c]) {
            [indices addIndex:i];
        }
    }

    [indices enumerateIndexesWithOptions:NSEnumerationReverse
                              usingBlock:^(NSUInteger idx, BOOL *stop) {
                                  [self replaceBytesInRange:NSMakeRange(idx, 0)
                                                  withBytes:"\\"
                                                     length:1];
                              }];
}

- (void)removeAsciiCharactersInSet:(NSCharacterSet *)characterSet {
    char flags[256];
    for (int i = 0; i < 256; i++) {
        flags[i] = [characterSet characterIsMember:i];
    }
    NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
    const char *bytes = [self bytes];
    int length = [self length];
    for (int i = 0; i < length; i++) {
        unsigned int c = bytes[i];
        if (flags[c]) {
            [indices addIndex:i];
        }
    }
    [indices enumerateIndexesWithOptions:NSEnumerationReverse
                              usingBlock:^(NSUInteger idx, BOOL *stop) {
                                  [self replaceBytesInRange:NSMakeRange(idx, 0)
                                                  withBytes:""
                                                     length:0];
                              }];
}


@end
