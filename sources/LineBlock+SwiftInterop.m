//
//  LineBlock+SwiftInterop.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/25/23.
//

#import "LineBlock+SwiftInterop.h"

#import "iTermMalloc.h"

@implementation LineBlock (SwiftInterop)

- (void)createCharacterBufferOfSize:(int)size {
    [self setRawBuffer:(screen_char_t *)iTermMalloc(sizeof(screen_char_t) * size)];
    _bufferSize = size;
}

- (void)createCharacterBufferWithUncompressedData:(NSData *)data {
    [self setRawBuffer:(screen_char_t *)iTermMalloc(_bufferSize * sizeof(screen_char_t))];
    memmove((void *)self.mutableRawBuffer, data.bytes, data.length);
}

- (void)setRawBuffer:(screen_char_t *)replacement {
    _rawBuffer = replacement;
}

- (const screen_char_t *)rawBuffer {
    return _rawBuffer;
}

- (screen_char_t *)mutableRawBuffer {
    return _rawBuffer;
}

- (const screen_char_t *)bufferStart {
    return _rawBuffer + _startOffset;
}

- (int)rawBufferSize {
    return _bufferSize;
}

@end
