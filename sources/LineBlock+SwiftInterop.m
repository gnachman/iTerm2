//
//  LineBlock+SwiftInterop.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/25/23.
//

#import "LineBlock+SwiftInterop.h"
#import "iTerm2SharedARC-Swift.h"

@implementation LineBlock (SwiftInterop)

- (void)createCharacterBufferOfSize:(int)size {
    _characterBuffer = [[iTermCompressibleCharacterBuffer alloc] init:size];
}

- (void)createCharacterBufferWithUncompressedData:(NSData *)data {
    _characterBuffer = [[iTermCompressibleCharacterBuffer alloc] initWithUncompressedData:data];
}

- (BOOL)createCharacterBufferFromEncodedData:(NSData *)data {
    _characterBuffer = [[iTermCompressibleCharacterBuffer alloc] initWithEncodedData:data];
    return _characterBuffer != nil;
}

- (const screen_char_t *)rawBuffer {
    return _characterBuffer.pointer;
}

- (screen_char_t *)mutableRawBuffer {
    return _characterBuffer.mutablePointer;
}

- (const screen_char_t *)bufferStart {
    return _characterBuffer.pointer + _startOffset;
}

- (iTermCompressibleCharacterBuffer *)copyOfCharacterBuffer {
    return [_characterBuffer clone];
}

- (BOOL)characterBufferIsEqualTo:(iTermCompressibleCharacterBuffer *)other {
    return [_characterBuffer deepIsEqual:other];
}

- (int)rawBufferSize {
    return _characterBuffer.size;
}

- (void)resizeCharacterBufferTo:(size_t)count {
    [_characterBuffer resize:count];
}

- (NSData *)encodedCharacterBufferWithMaxSize:(NSInteger)maxSize {
    return [_characterBuffer encodedDataWithMaxSize:maxSize];
}

@end
