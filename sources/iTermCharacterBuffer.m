//
//  iTermCharacterBuffer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/26/24.
//

#import "iTermCharacterBuffer.h"
#import "iTermMalloc.h"

@implementation iTermCharacterBuffer {
    screen_char_t *_buffer;
    int _size;
    BOOL _wasRelocated;
}

- (void)dealloc {
    free(_buffer);
}

- (NSString *)description {
    return ScreenCharArrayToStringDebug(self.pointer, self.size);
}

- (NSString *)shortDescription {
    const int maxLength = 40;
    if (self.size > maxLength + 1) {
        return [ScreenCharArrayToStringDebug(self.pointer, MIN(self.size, maxLength - 1)) stringByAppendingString:@"…"];
    } else {
        return [self description];
    }
}
- (int)size {
    return _size;
}

- (screen_char_t *)mutablePointer {
    return _buffer;
}

- (const screen_char_t *)pointer {
    return _buffer;
}

- (NSData *)data {
    return [NSData dataWithBytes:(void *)_buffer length:_size * sizeof(screen_char_t)];
}

- (instancetype)initWithSize:(int)size {
    self = [super init];
    if (self) {
        _buffer = iTermUninitializedCalloc(size, sizeof(screen_char_t));
        _size = size;
    }
    return self;
}

- (instancetype)initWithData:(NSData *)data {
    return [self initWithChars:(screen_char_t *)data.bytes 
                          size:data.length / sizeof(screen_char_t)];
}

// Makes a copy
- (instancetype)initWithChars:(screen_char_t *)source size:(int)size {
    self = [super init];
    if (self) {
        _buffer = iTermMemdup(source, size, sizeof(screen_char_t));
        _size = size;
    }
    return self;
}

- (void)resize:(int)newSize {
    screen_char_t *oldBuffer = _buffer;
    _buffer = iTermRealloc(_buffer, newSize, sizeof(screen_char_t));
    if (_buffer != oldBuffer) {
        _wasRelocated = YES;
    }
    _size = newSize;
}

- (iTermCharacterBuffer *)clone {
    return [[iTermCharacterBuffer alloc] initWithChars:_buffer size:_size];
}

- (void)clearRelocationFlag {
    _wasRelocated = NO;
}

- (BOOL)deepIsEqual:(id)object {
    if (object == self) {
        return YES;
    }
    iTermCharacterBuffer *other = [iTermCharacterBuffer castFrom:object];
    if (!other) {
        return NO;
    }
    return _size == other->_size && !memcmp(_buffer, other->_buffer, _size * sizeof(screen_char_t));
}

@end
