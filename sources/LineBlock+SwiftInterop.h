//
//  LineBlock+SwiftInterop.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/25/23.
//

#import "LineBlock.h"

@class iTermCompressibleCharacterBuffer;
@class iTermCompressedCharacterBuffer;

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
- (iTermCompressibleCharacterBuffer *)copyOfCharacterBuffer;
- (NSData *)encodedCharacterBufferWithMaxSize:(NSInteger)maxSize;

// This is slow! Don't use it except for dev.
- (BOOL)characterBufferIsEqualTo:(iTermCompressibleCharacterBuffer *)other;

// Get the size of the raw buffer.
- (int)rawBufferSize;

- (void)decompressCharacterBuffer;
- (void)resizeCharacterBufferTo:(size_t)count;
- (int)calculateNumberOfFullLinesWithOffset:(int)offset
                                     length:(int)length
                                      width:(int)width
                                 mayHaveDWC:(BOOL)mayHaveDWC;

- (NSString *)stringFromOffset:(int)offset
                        length:(int)length
                  backingStore:(unichar **)backingStorePtr
                        deltas:(int **)deltasPtr;

- (screen_char_t)characterAtIndex:(int)index;
- (ScreenCharArray *)paddedScreenCharArrayForRange:(NSRange)range
                                          paddedTo:(int)paddedSize
                                    eligibleForDWC:(BOOL)eligibleForDWC
                                      continuation:(screen_char_t)continuation;
- (const screen_char_t * _Nullable)rawBufferIfUncompressed;

@end

NS_ASSUME_NONNULL_END
