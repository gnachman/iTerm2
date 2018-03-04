//
//  iTermData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/4/18.
//

#import "iTermData.h"
#import "DebugLogging.h"

@implementation iTermData {
    NSUInteger _originalLength;
    BOOL _unowned;
}

+ (instancetype)dataOfLength:(NSUInteger)length {
    iTermData *data = [[iTermData alloc] init];
    if (data) {
        data->_mutableBytes = malloc(length);
        data->_length = length;
        data->_originalLength = length;
        data->_allocatedCapacity = length;
    }
    return data;
}

+ (instancetype)pageAlignedUninitializeDataOfLength:(NSUInteger)length {
    assert(length > 0);
    iTermData *data = [[iTermData alloc] init];
    if (data) {
        char *bytes;
        static int pagesize;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            pagesize = sysconf(_SC_PAGE_SIZE);
            if (pagesize == -1) {
                ELog(@"Failed to get page size: %s", strerror(errno));
            }
            assert(pagesize > 0);
        });

        // Allocate a multiple of page size bytes (makes Metal happy)
        const size_t numberOfPages = (length + pagesize) / pagesize;
        const size_t adjustedLength = numberOfPages * pagesize;
        assert(adjustedLength >= length);
        if (posix_memalign((void **)&bytes, pagesize, adjustedLength) != 0) {
            return nil;
        }

        data->_mutableBytes = (unsigned char *)bytes;
        data->_length = length;
        data->_originalLength = length;
        data->_allocatedCapacity = adjustedLength;
    }
    return data;
}

+ (instancetype)unownedDataWithBytes:(void *)bytes length:(NSUInteger)length {
    iTermData *data = [[iTermData alloc] init];
    if (data) {
        data->_unowned = YES;
        data->_mutableBytes = bytes;
        data->_length = length;
        data->_originalLength = -1;
        data->_allocatedCapacity = length;
    }
    return data;
}
- (void)dealloc {
    if (_mutableBytes && !_unowned) {
        free(_mutableBytes);
    }
    _length = 0xdeadbeef;
}

- (void)setLength:(NSUInteger)length {
    assert(length <= _originalLength);
    _length = length;
}

- (const void *)bytes {
    return _mutableBytes;
}

- (NSString *)bitRanges {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    int n = 0;
    for (int i = 0; i < _length; i++) {
        unsigned char c = _mutableBytes[i];
        for (int j = 0; j < 8; j++, n++) {
            if (c & (1 << j)) {
                [indexes addIndex:n];
            }
        }
    }
    return indexes.description;
}

@end


