//
//  LineBlock+SwiftInterop.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/25/23.
//

#import "LineBlock+SwiftInterop.h"

@implementation LineBlock (SwiftInterop)

- (void)setRawBuffer:(screen_char_t *)replacement {
    raw_buffer = replacement;
}

- (const screen_char_t *)rawBuffer {
    return raw_buffer;
}

- (screen_char_t *)mutableRawBuffer {
    return raw_buffer;
}

- (const screen_char_t *)bufferStart {
    return raw_buffer + start_offset;
}

- (int)rawBufferSize {
    return buffer_size;
}

@end
