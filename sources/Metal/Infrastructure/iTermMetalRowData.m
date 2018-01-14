//
//  iTermMetalRowData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import "iTermMetalRowData.h"

@implementation iTermData

+ (instancetype)dataOfLength:(NSUInteger)length {
    iTermData *data = [[iTermData alloc] init];
    if (data) {
        data->_mutableBytes = malloc(length);
        data->_length = length;
    }
    return data;
}

- (void)dealloc {
    if (_mutableBytes) {
        free(_mutableBytes);
    }
    _length = 0xdeadbeef;
}

@end

@implementation iTermMetalRowData

- (instancetype)init {
    self = [super init];
    if (self) {
        _imageRuns = [NSMutableArray array];
    }
    return self;
}

@end

