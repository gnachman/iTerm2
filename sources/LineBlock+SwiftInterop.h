//
//  LineBlock+SwiftInterop.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/25/23.
//

#import "LineBlock.h"

@class iTermCompressibleCharacterBuffer;

NS_ASSUME_NONNULL_BEGIN

// This stupid file exists because Objective-C++ cannot coexist with *-Swift.h. I tried to make it
// work but regardless of whether the #include was in extern "C" {…} or outside it, a lot of headers
// failed to compile in hard-to-fix ways.
@interface LineBlock (SwiftInterop)

- (void)createCharacterBufferOfSize:(int)size;
- (void)createCharacterBufferWithUncompressedData:(NSData *)data;
- (BOOL)createCharacterBufferFromEncodedData:(NSData *)data;
- (const screen_char_t *)rawBuffer;
- (screen_char_t *)mutableRawBuffer;
- (const screen_char_t *)bufferStart;
- (const screen_char_t *)bufferStartIfUncompressed;
- (iTermCompressibleCharacterBuffer *)copyOfCharacterBuffer;
- (NSData *)encodedCharacterBufferWithMaxSize:(NSInteger)maxSize;

// This is slow! Don't use it except for dev.
- (BOOL)characterBufferIsEqualTo:(iTermCompressibleCharacterBuffer *)other;

// Get the size of the raw buffer.
- (int)rawBufferSize;
- (void)resizeCharacterBufferTo:(size_t)count;
- (int)calculateNumberOfFullLinesWithOffset:(int)offset
                                     length:(int)length
                                      width:(int)width
                                 mayHaveDWC:(BOOL)mayHaveDWC;
- (screen_char_t)characterAtIndex:(NSInteger)i;

@end

NS_ASSUME_NONNULL_END
