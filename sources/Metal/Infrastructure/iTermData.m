//
//  iTermData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/4/18.
//

#import "iTermData.h"

@implementation iTermData {
    NSUInteger _originalLength;
}

+ (instancetype)dataOfLength:(NSUInteger)length {
    iTermData *data = [[iTermData alloc] init];
    if (data) {
        data->_mutableBytes = malloc(length);
        data->_length = length;
        data->_originalLength = length;
    }
    return data;
}

- (void)dealloc {
    if (_mutableBytes) {
        free(_mutableBytes);
    }
    _length = 0xdeadbeef;
}

- (void)setLength:(NSUInteger)length {
    assert(length <= _originalLength);
    _length = length;
}

@end


