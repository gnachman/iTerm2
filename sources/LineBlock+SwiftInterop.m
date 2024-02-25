//
//  LineBlock+SwiftInterop.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/29/24.
//

#import "LineBlock+SwiftInterop.h"
#import "iTerm2SharedARC-Swift.h"

@implementation LineBlock(SwiftInterop)

- (NSData *)decompressedDataFromV4Data:(NSData *)v4data {
    iTermCompressibleCharacterBuffer *cb = [[iTermCompressibleCharacterBuffer alloc] initWithEncodedData:v4data];
    if (!cb) {
        return nil;
    }
    screen_char_t *p = cb.mutablePointer;
    return [NSData dataWithBytes:p length:cb.size * sizeof(screen_char_t)];
}

@end
