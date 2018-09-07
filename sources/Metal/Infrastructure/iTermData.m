//
//  iTermData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/4/18.
//

#import "iTermData.h"

@implementation iTermData {
@protected
    NSUInteger _originalLength;
    unsigned char _magic;
    void *_mutableBytes;
    NSUInteger _length;
}

- (instancetype)initWithLength:(NSUInteger)length magic:(unsigned char)magic {
    self = [super init];
    if (self) {
        _magic = magic;
        unsigned char *buffer = malloc(length + 1);;
        buffer[length] = magic;

        _mutableBytes = buffer;
        _length = length;
        _originalLength = length;
    }
    return self;
}

- (void)dealloc {
    if (_mutableBytes) {
        [self checkForOverrun];
        free(_mutableBytes);
    }
    _length = 0xdeadbeef;
}

- (void)setLength:(NSUInteger)length {
    assert(length <= _originalLength);
    _length = length;
}

- (void)checkForOverrun {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        assert(buffer[_originalLength] == _magic);
    }
}

@end


@implementation iTermScreenCharData : iTermData

+ (instancetype)dataOfLength:(NSUInteger)length {
    return [[self alloc] initWithLength:length magic:0x70];
}

- (void)dealloc {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        assert(buffer[_originalLength] == 0x70);
    }
}

@end

@implementation iTermGlyphKeyData : iTermData

+ (instancetype)dataOfLength:(NSUInteger)length {
    return [[self alloc] initWithLength:length magic:0x71];
}

- (void)dealloc {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        assert(buffer[_originalLength] == 0x71);
    }
}

@end

@implementation iTermAttributesData : iTermData

+ (instancetype)dataOfLength:(NSUInteger)length {
    return [[self alloc] initWithLength:length magic:0x72];
}

- (void)dealloc {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        assert(buffer[_originalLength] == 0x72);
    }
}

@end

@implementation iTermBackgroundColorRLEsData : iTermData

+ (instancetype)dataOfLength:(NSUInteger)length {
    return [[self alloc] initWithLength:length magic:0x73];
}

- (void)dealloc {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        assert(buffer[_originalLength] == 0x73);
    }
}

@end
