//
//  ScreenCharArray.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/18/21.
//

#import "ScreenCharArray.h"

@implementation ScreenCharArray {
    BOOL _shouldFreeOnRelease;
    screen_char_t _placeholder;
}
@synthesize line = _line;
@synthesize length = _length;
@synthesize eol = _eol;

- (instancetype)init {
    self = [super init];
    if (self) {
        _line = &_placeholder;
        _eol = EOL_HARD;
    }
    return self;
}

- (instancetype)initWithCopyOfLine:(const screen_char_t *)line
                            length:(int)length
                      continuation:(screen_char_t)continuation {
    screen_char_t *copy = malloc(sizeof(*line) * length);
    memmove(copy, line, sizeof(*line) * length);
    self = [self initWithLine:copy length:length continuation:continuation];
    if (self) {
        _shouldFreeOnRelease = YES;
    }
    return self;
}

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                continuation:(screen_char_t)continuation {
    return [self initWithLine:line
                       length:length
                     metadata:iTermMetadataDefault()
                 continuation:continuation];
}

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                    metadata:(iTermMetadata)metadata
                continuation:(screen_char_t)continuation {
    self = [super init];
    if (self) {
        _line = line;
        _length = length;
        _continuation = continuation;
        _metadata = metadata;
        iTermMetadataRetain(_metadata);
        _eol = continuation.code;
    }
    return self;
}

- (void)dealloc {
    if (_shouldFreeOnRelease) {
        free((void *)_line);
        _line = NULL;
    }
    iTermMetadataRelease(_metadata);
}

- (BOOL)isEqualToScreenCharArray:(ScreenCharArray *)other {
    if (!other) {
        return NO;
    }
    return (_line == other->_line &&
            _length == other->_length &&
            _eol == other->_eol &&
            !memcmp(&_continuation, &other->_continuation, sizeof(_continuation)));
}

- (NSString *)debugDescription {
    return ScreenCharArrayToStringDebug(_line, _length);
}

- (id)copyWithZone:(NSZone *)zone {
    return [[ScreenCharArray alloc] initWithCopyOfLine:_line length:_length continuation:_continuation];
}

- (ScreenCharArray *)screenCharArrayByAppendingScreenCharArray:(ScreenCharArray *)other {
    const size_t combinedLength = (_length + other.length);
    screen_char_t *copy = malloc(sizeof(screen_char_t) * combinedLength);
    memmove(copy, _line, sizeof(*_line) * _length);
    memmove(copy + _length, other.line, sizeof(*_line) * other.length);
    iTermExternalAttributeIndex *originalIndex = iTermMetadataGetExternalAttributesIndex(_metadata);
    iTermExternalAttributeIndex *appendage = iTermMetadataGetExternalAttributesIndex(other->_metadata);
    iTermExternalAttributeIndex *eaIndex =
        [iTermExternalAttributeIndex concatenationOf:originalIndex
                                              length:_length
                                                with:appendage
                                              length:other->_length];
    iTermMetadata combined;
    iTermMetadataInit(&combined, _metadata.timestamp, eaIndex);
    ScreenCharArray *result = [[ScreenCharArray alloc] initWithLine:copy
                                                             length:combinedLength
                                                           metadata:combined
                                                       continuation:other.continuation];
    iTermMetadataRelease(combined);
    if (result) {
        result->_shouldFreeOnRelease = YES;
    }
    return result;
}

static BOOL ScreenCharIsNull(screen_char_t c) {
    return c.code == 0 && !c.complexChar && !c.image;
}

- (ScreenCharArray *)screenCharArrayByRemovingTrailingNullsAndHardNewline {
    ScreenCharArray *result = [self copy];
    [result makeEndingSoft];
    return result;
}

// Internal-only API for mutation. The public API is immutable.
- (void)makeEndingSoft {
    while (_length > 0 && ScreenCharIsNull(_line[_length - 1])) {
        _length -= 1;
    }
    memset(&_continuation, 0, sizeof(_continuation));
    _continuation.code = EOL_SOFT;
    _eol = EOL_SOFT;
}

@end

