//
//  iTermData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/4/18.
//

#import "iTermData.h"
#import "DebugLogging.h"

static const unsigned char iTermDataGuardRegionValue[64] = {
    0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E, 0x7F,
    0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F,
    0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F,
    0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaA, 0xaB, 0xaC, 0xaD, 0xaE, 0xaF
};

@implementation iTermData {
@protected
    NSUInteger _originalLength;
    void *_mutableBytes;
    NSUInteger _length;
}

- (instancetype)initWithLength:(NSUInteger)length {
    self = [super init];
    if (self) {
        unsigned char *buffer = malloc(length + sizeof(iTermDataGuardRegionValue));
        memmove(buffer + length, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));

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

- (const unsigned char *)bytes {
    return _mutableBytes;
}

- (void)setLength:(NSUInteger)length {
    assert(length <= _originalLength);
    _length = length;
}
- (void)checkForOverrun {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        const int comparisonResult = memcmp(buffer + _originalLength, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));
        assert(comparisonResult == 0);
    }
}

@end


@implementation iTermScreenCharData : iTermData

+ (instancetype)dataOfLength:(NSUInteger)length {
    return [[self alloc] initWithLength:length];
}

- (void)checkForOverrun {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        const int comparisonResult = memcmp(buffer + _originalLength, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));
        assert(comparisonResult == 0);
    }
}
@end

@implementation iTermGlyphKeyData : iTermData

+ (instancetype)dataOfLength:(NSUInteger)length {
    return [[self alloc] initWithLength:length];
}

- (void)checkForOverrun {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        const int comparisonResult = memcmp(buffer + _originalLength, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));
        assert(comparisonResult == 0);
    }
}
- (void)checkForOverrun1 {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        const int comparisonResult = memcmp(buffer + _originalLength, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));
        assert(comparisonResult == 0);
    }
}
- (void)checkForOverrun2 {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        const int comparisonResult = memcmp(buffer + _originalLength, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));
        assert(comparisonResult == 0);
    }
}
@end

@implementation iTermAttributesData : iTermData

+ (instancetype)dataOfLength:(NSUInteger)length {
    return [[self alloc] initWithLength:length];
}

- (void)checkForOverrun {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        const int comparisonResult = memcmp(buffer + _originalLength, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));
        assert(comparisonResult == 0);
    }
}
- (void)checkForOverrun1 {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        const int comparisonResult = memcmp(buffer + _originalLength, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));
        assert(comparisonResult == 0);
    }
}
- (void)checkForOverrun2 {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        const int comparisonResult = memcmp(buffer + _originalLength, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));
        assert(comparisonResult == 0);
    }
}
@end

@implementation iTermBackgroundColorRLEsData : iTermData

+ (instancetype)dataOfLength:(NSUInteger)length {
    return [[self alloc] initWithLength:length];
}

- (void)checkForOverrun {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        const int comparisonResult = memcmp(buffer + _originalLength, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));
        assert(comparisonResult == 0);
    }
}
@end

@implementation iTermBitmapData : iTermData
+ (instancetype)dataOfLength:(NSUInteger)length {
    ITAssertWithMessage(length > 0, @"Zero length (%@)", @(length));
    return [[self alloc] initWithLength:length];
}

- (void)checkForOverrun {
    [self checkForOverrunWithInfo:@"No info"];
}

- (void)checkForOverrunWithInfo:(NSString *)info {
    if (_mutableBytes) {
        unsigned char *buffer = _mutableBytes;
        const int comparisonResult = memcmp(buffer + _originalLength, iTermDataGuardRegionValue, sizeof(iTermDataGuardRegionValue));
        if (comparisonResult == 0) {
            return;
        }
        NSMutableString *hex = [NSMutableString string];
        for (NSInteger i = 0; i < sizeof(iTermDataGuardRegionValue); i++) {
            unsigned int value = buffer[_originalLength + i];
            [hex appendFormat:@"%02x ", value];
        }
        [hex appendString:@"vs expected: "];
        for (NSInteger i = 0; i < sizeof(iTermDataGuardRegionValue); i++) {
            unsigned int value = iTermDataGuardRegionValue[i];
            [hex appendFormat:@"%02x ", value];
        }
        ITAssertWithMessage(NO, @"%@. Guard corrupted: actual is %@", info, hex);
    }
}
@end

