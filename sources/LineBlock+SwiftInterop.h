//
//  LineBlock+SwiftInterop.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/25/23.
//

#import "LineBlock.h"

NS_ASSUME_NONNULL_BEGIN

// This stupid file exists because Objective-C++ cannot coexist with *-Swift.h. I tried to make it
// work but regardless of whether the #include was in extern "C" {…} or outside it, a lot of headers
// failed to compile in hard-to-fix ways.
@interface LineBlock (SwiftInterop)

- (void)createCharacterBufferOfSize:(int)size;
- (void)setRawBuffer:(screen_char_t *)replacement;
- (const screen_char_t *)rawBuffer;
- (screen_char_t *)mutableRawBuffer;
- (const screen_char_t *)bufferStart;

// Get the size of the raw buffer.
- (int)rawBufferSize;


@end

NS_ASSUME_NONNULL_END
