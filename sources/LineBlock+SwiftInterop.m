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

- (const screen_char_t *)bufferStartIfUncompressed {
    if (_characterBuffer.hasUncompressedBuffer) {
        return self.bufferStart;
    }
    return nil;
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

- (int)calculateNumberOfFullLinesWithOffset:(int)offset
                                     length:(int)length
                                      width:(int)width
                                 mayHaveDWC:(BOOL)mayHaveDWC {
    if (width <= 1 || !mayHaveDWC) {
        // Need to use max(0) because otherwise we get -1 for length=0 width=1.
        return MAX(0, length - 1) / width;
    }

    if (_characterBuffer.isCompressed) {
        return [_characterBuffer numberOfFullLinesWithOffset:offset
                                                      length:length
                                                       width:width];
    } else {
        return iTermLineBlockNumberOfFullLinesImpl(self.rawBuffer + offset, length, width);
    }
}

int iTermLineBlockNumberOfFullLinesImpl(const screen_char_t *buffer,
                                        int length,
                                        int width) {
    int fullLines = 0;
    for (int i = width; i < length; i += width) {
        if (ScreenCharIsDWC_RIGHT(buffer[i])) {
            --i;
        }
        ++fullLines;
    }
    return fullLines;
}

- (screen_char_t)characterAtIndex:(NSInteger)i {
    return [_characterBuffer characterAtIndex:i];
}

@end
