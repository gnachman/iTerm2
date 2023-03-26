//
//  LineBlock+SwiftInterop.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/25/23.
//

#import "LineBlock+SwiftInterop.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAtomicMutableArrayOfWeakObjects.h"
#import "iTermWeakBox.h"

@implementation LineBlock (SwiftInterop)

static void iTermLineBlockDidEnterSuperposition(__unsafe_unretained LineBlock *lineBlock) {
    for (iTermWeakBox<id<iTermLineBlockObserver>> *box in lineBlock->_observers) {
        [box.object lineBlockDidDecompress:lineBlock];
    }
}

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
    const BOOL wasInSuperposition = _characterBuffer.isInSuperposition;
    const screen_char_t *result = _characterBuffer.pointer;
    if (!wasInSuperposition && _characterBuffer.isInSuperposition) {
        iTermLineBlockDidEnterSuperposition(self);
    }
    return result;
}

- (screen_char_t *)mutableRawBuffer {
    const BOOL wasInSuperposition = _characterBuffer.isInSuperposition;
    screen_char_t *result = _characterBuffer.mutablePointer;
    if (!wasInSuperposition && _characterBuffer.isInSuperposition) {
        iTermLineBlockDidEnterSuperposition(self);
    }
    return result;
}

- (const screen_char_t *)bufferStart {
    const BOOL wasInSuperposition = _characterBuffer.isInSuperposition;
    const screen_char_t *result = _characterBuffer.pointer + _startOffset;
    if (!wasInSuperposition && _characterBuffer.isInSuperposition) {
        iTermLineBlockDidEnterSuperposition(self);
    }
    return result;
}

- (const screen_char_t *)bufferStartIfUncompressed {
    if (_characterBuffer.hasUncompressedBuffer) {
        return self.bufferStart;
    }
    return nil;
}

- (const screen_char_t *)rawBufferIfUncompressed {
    if (_characterBuffer.hasUncompressedBuffer) {
        return self.rawBuffer;
    }
    return nil;
}

- (iTermCompressibleCharacterBuffer *)copyOfCharacterBuffer:(BOOL)keepCompressed {
    return [_characterBuffer cloneCompressed:keepCompressed];
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

- (ScreenCharArray *)screenCharArrayStartingAtOffset:(NSInteger)offset
                                              length:(NSInteger)length
                                            metadata:(iTermImmutableMetadata)metadata
                                        continuation:(screen_char_t)continuation
                                      paddedToLength:(NSInteger)paddedSize
                                      eligibleForDWC:(BOOL)eligibleForDWC {
    return [_characterBuffer screenCharArrayStartingAtOffset:offset
                                                      length:length
                                                    metadata:metadata
                                                continuation:continuation
                                              paddedToLength:paddedSize
                                              eligibleForDWC:eligibleForDWC];
}

- (NSString *)stringFromOffset:(int)offset
                        length:(int)length
                  backingStore:(unichar **)backingStorePtr
                        deltas:(int **)deltasPtr {
    return [_characterBuffer stringFromOffset:offset length:length backingStore:backingStorePtr deltas:deltasPtr];
}

- (BOOL)isOnlyUncompressed {
    return !_characterBuffer.isCompressed && _characterBuffer.hasUncompressedBuffer;
}

- (BOOL)hasBeenIdleLongEnoughToCompress {
    const NSTimeInterval ttl = 1.25 * MAX(1.0, _characterBuffer.size / 1024.0);

    return _characterBuffer.idleTime > ttl;
}

- (void)reallyCompress {
    assert(self.clients.strongObjects.count == 0);
    assert(self.owner == nil);
    if ([_characterBuffer compress]) {
        // Bump the generation so we write it back to db compressed. This is important because then
        // when state is restored we don't need to re-do the work of compressing it.
        self.generation += 1;
    }
}

- (void)purgeDecompressed {
    [_characterBuffer purgeDecompressed];
}

- (NSString *)compressionDebugDescription {
    return _characterBuffer.compressionDebugDescription;
}

- (NSString *)characterBufferDescription {
    return _characterBuffer.debugDescription;
}

@end
