//
//  NSMutableData+iTerm.m
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import "NSMutableData+iTerm.h"

@implementation NSMutableData (iTerm)

+ (instancetype)uninitializedDataWithLength:(NSUInteger)length {
    return [[[self alloc] initWithUninitializedLength:length] autorelease];
}

- (instancetype)initWithUninitializedLength:(NSUInteger)length {
    return [self initWithBytesNoCopy:malloc(length) length:length freeWhenDone:YES];
}

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

- (NSInteger)it_replaceOccurrencesOfData:(NSData *)target withData:(NSData *)replacement {
    NSInteger count = 0;
    NSRange range = NSMakeRange(0, self.length);
    while (range.length > 0) {
        NSRange replacementRange = [self rangeOfData:target options:0 range:range];
        if (replacementRange.location == NSNotFound) {
            break;
        }
        [self replaceBytesInRange:replacementRange withBytes:replacement.bytes length:replacement.length];
        count++;
        const NSInteger location = replacementRange.location + replacement.length;
        const NSInteger myLength = self.length;
        assert(myLength >= location);
        range.location = location;
        range.length = myLength - location;
    }
    return count;
}

@end
