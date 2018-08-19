//
//  iTermData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/4/18.
//

#import "iTermData.h"

static const unsigned char iTermDataMagic = 0x7b;

@implementation iTermData {
    NSUInteger _originalLength;
}

+ (instancetype)dataOfLength:(NSUInteger)length {
    iTermData *data = [[iTermData alloc] init];
    if (data) {
        unsigned char *buffer = malloc(length + 1);;
        buffer[length] = iTermDataMagic;

        data->_mutableBytes = buffer;
        data->_length = length;
        data->_originalLength = length;
    }
    return data;
}

- (void)dealloc {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        assert(buffer[_originalLength] == iTermDataMagic);
        free(_mutableBytes);
    }
    _length = 0xdeadbeef;
}

- (void)setLength:(NSUInteger)length {
    assert(length <= _originalLength);
    _length = length;
}

@end


