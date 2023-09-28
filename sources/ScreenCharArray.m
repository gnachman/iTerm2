//
//  ScreenCharArray.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/18/21.
//

#import "ScreenCharArray.h"
#import "NSMutableAttributedString+iTerm.h"

static NSString *const ScreenCharArrayKeyData = @"data";
static NSString *const ScreenCharArrayKeyEOL = @"eol";
static NSString *const ScreenCharArrayKeyMetadata = @"metadata";
static NSString *const ScreenCharArrayKeyContinuation = @"continuation";

@implementation ScreenCharArray {
    // If initialized with data, hold a reference to it to preserve ownership.
    NSData *_data;
    BOOL _shouldFreeOnRelease;
    screen_char_t _placeholder;
    size_t _offset;
}
@synthesize line = _line;
@synthesize length = _length;
@synthesize eol = _eol;

+ (instancetype)emptyLineOfLength:(int)length {
    NSMutableData *data = [NSMutableData data];
    data.length = length * sizeof(screen_char_t);
    return [[ScreenCharArray alloc] initWithData:data
                                        metadata:iTermImmutableMetadataDefault()
                                    continuation:(screen_char_t){.code = EOL_HARD}];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        NSArray *metadataArray = dictionary[ScreenCharArrayKeyMetadata];
        NSData *screenCharData = dictionary[ScreenCharArrayKeyContinuation];
        if (screenCharData.length == sizeof(_continuation)) {
            memmove(&_continuation, screenCharData.bytes, sizeof(_continuation));
        } else {
            memset(&_continuation, 0, sizeof(_continuation));
        }
        iTermMetadata metadata;
        iTermMetadataInitFromArray(&metadata, metadataArray);
        self = [self initWithData:dictionary[ScreenCharArrayKeyData]
                         metadata:iTermMetadataMakeImmutable(metadata)
                     continuation:_continuation];
        iTermMetadataRelease(metadata);
        _eol = [dictionary[ScreenCharArrayKeyEOL] intValue];
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _line = &_placeholder;
        _eol = EOL_HARD;
    }
    return self;
}

// This keeps a raw pointer to data.bytes so don't modify data's length after this.
- (instancetype)initWithData:(NSData *)data
       includingContinuation:(BOOL)includingContinuation
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation {
    self = [super init];
    if (self) {
        _line = data.bytes;
        _length = data.length / sizeof(screen_char_t);
        if (includingContinuation) {
            _length -= 1;
        }
        assert((includingContinuation ? (_length + 1) : _length) * sizeof(screen_char_t) == data.length);
        _data = data;
        _metadata = metadata;
        iTermImmutableMetadataRetain(metadata);
        _continuation = continuation;
        _eol = continuation.code;
    }
    return self;
}

- (instancetype)initWithData:(NSData *)data
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation {
    return [self initWithData:data includingContinuation:NO metadata:metadata continuation:continuation];
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
                     metadata:iTermImmutableMetadataDefault()
                 continuation:continuation];
}

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation {
    self = [super init];
    if (self) {
        _line = line;
        _length = MAX(0, length);
        _continuation = continuation;
        _metadata = metadata;
        iTermImmutableMetadataRetain(_metadata);
        _eol = continuation.code;
    }
    return self;
}

- (instancetype)initWithLine:(const screen_char_t *)line
                      length:(int)length
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation
               freeOnRelease:(BOOL)freeOnRelease {
    self = [self initWithLine:line length:length metadata:metadata continuation:continuation];
    if (self) {
        _shouldFreeOnRelease = freeOnRelease;
    }
    return self;
}

- (instancetype)initWithLine:(const screen_char_t *)line
                      offset:(size_t)offset
                      length:(int)length
                    metadata:(iTermImmutableMetadata)metadata
                continuation:(screen_char_t)continuation
               freeOnRelease:(BOOL)freeOnRelease {
    self = [self initWithLine:line + offset
                       length:length
                     metadata:metadata
                 continuation:continuation
                freeOnRelease:freeOnRelease];
    if (self) {
        _offset = offset;
    }
    return self;
}

- (void)dealloc {
    if (_shouldFreeOnRelease) {
        free((void *)(_line - _offset));
        memset(&_line, 0, sizeof(_line));
    }
    iTermImmutableMetadataRelease(_metadata);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p value=\"%@\" eol=%@>",
            NSStringFromClass([self class]), self, ScreenCharArrayToStringDebug(_line, _length), @(self.eol)];
}

- (NSString *)stringValue {
    NSMutableString *result = [NSMutableString string];
    const screen_char_t *line = self.line;
    for (int i = 0; i < self.length; i++) {
        const screen_char_t c = line[i];
        if (c.image) {
            continue;
        }
        if (!c.complexChar) {
            if (c.code >= ITERM2_PRIVATE_BEGIN && c.code <= ITERM2_PRIVATE_END) {
                continue;
            }
            if (!c.code) {
                // Stop on the first null.
                break;
            }
            [result appendCharacter:c.code];
            continue;
        }
        [result appendString:ScreenCharToStr(&c)];
    }
    return result;
}

- (NSAttributedString *)attributedStringValueWithAttributeProvider:(NSDictionary *(^)(screen_char_t, iTermExternalAttribute *))attributeProvider {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    const screen_char_t *line = self.line;
    id<iTermExternalAttributeIndexReading> eaindex = iTermImmutableMetadataGetExternalAttributesIndex(_metadata);
    for (int i = 0; i < self.length; i++) {
        const screen_char_t c = line[i];
        if (c.image) {
            continue;
        }
        NSString *string = nil;
        if (!c.complexChar) {
            if (c.code >= ITERM2_PRIVATE_BEGIN && c.code <= ITERM2_PRIVATE_END) {
                continue;
            }
            if (!c.code) {
                // Stop on the first null.
                break;
            }
            string = [NSString stringWithLongCharacter:c.code];
        } else {
            string = ScreenCharToStr(&c);
        }
        [result iterm_appendString:string
                    withAttributes:attributeProvider(c, eaindex[i])];
    }
    return result;
}

- (BOOL)isEqual:(id)object {
    ScreenCharArray *other = [ScreenCharArray castFrom:object];
    return [self isEqualToScreenCharArray:other];
}

- (BOOL)isEqualToScreenCharArray:(ScreenCharArray *)other {
    if (!other) {
        return NO;
    }
    if (_length != other->_length) {
        return NO;
    }
    if (_eol != other->_eol) {
        return NO;
    }
    if (memcmp(&_continuation, &other->_continuation, sizeof(_continuation))) {
        return NO;
    }
    if ((_line != other->_line && memcmp(_line, other->_line, _length * sizeof(screen_char_t)))) {
        return NO;
    }
    return YES;
}

- (NSString *)debugDescription {
    NSString *content = ScreenCharArrayToStringDebug(_line, _length);
    switch (_eol) {
        case EOL_HARD:
            return [content stringByAppendingString:@" [hard eol]"];
        case EOL_SOFT:
            return [content stringByAppendingString:@" [soft eol]"];
        case EOL_DWC:
            return [content stringByAppendingString:@" [dwc eol]"];
    }
    return content;
}

- (id)copyWithZone:(NSZone *)zone {
    ScreenCharArray *theCopy = [[ScreenCharArray alloc] initWithCopyOfLine:_line
                                                                    length:_length
                                                              continuation:_continuation];
    theCopy->_metadata = iTermImmutableMetadataCopy(_metadata);
    return theCopy;
}

- (NSDictionary *)dictionaryValue {
    return @{
        ScreenCharArrayKeyData: [NSData dataWithBytes:self.line length:self.length * sizeof(screen_char_t)],
        ScreenCharArrayKeyEOL: @(_eol),
        ScreenCharArrayKeyMetadata: iTermImmutableMetadataEncodeToArray(_metadata),
        ScreenCharArrayKeyContinuation: [NSData dataWithBytes:&_continuation length:sizeof(_continuation)]
    };
}

- (ScreenCharArray *)screenCharArrayByAppendingScreenCharArray:(ScreenCharArray *)other {
    const size_t combinedLength = (_length + other.length);
    screen_char_t *copy = malloc(sizeof(screen_char_t) * combinedLength);
    memmove(copy, _line, sizeof(*_line) * _length);
    memmove(copy + _length, other.line, sizeof(*_line) * other.length);
    id<iTermExternalAttributeIndexReading> originalIndex = iTermImmutableMetadataGetExternalAttributesIndex(_metadata);
    id<iTermExternalAttributeIndexReading> appendage = iTermImmutableMetadataGetExternalAttributesIndex(other->_metadata);
    iTermExternalAttributeIndex *eaIndex =
    [iTermExternalAttributeIndex concatenationOf:originalIndex
                                          length:_length
                                            with:appendage
                                          length:other->_length];
    iTermMetadata combined;
    iTermMetadataInit(&combined, _metadata.timestamp, eaIndex);
    ScreenCharArray *result = [[ScreenCharArray alloc] initWithLine:copy
                                                             length:combinedLength
                                                           metadata:iTermMetadataMakeImmutable(combined)
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

- (ScreenCharArray *)inWindow:(VT100GridRange)window {
    const screen_char_t *theLine = self.line;
    int offset = 0;
    int maxLength = self.length;
    if (window.length > 0) {
        offset = window.location;
        maxLength = window.length;
    }
    if (offset == 0 && maxLength >= self.length) {
        return self;
    }
    return [[ScreenCharArray alloc] initWithLine:theLine + offset
                                          length:MIN(maxLength, self.length)
                                        metadata:self.metadata
                                    continuation:self.continuation];
}

- (ScreenCharArray *)paddedToLength:(int)length eligibleForDWC:(BOOL)eligibleForDWC {
    if (self.length == length) {
        return self;
    }
    NSMutableData *data = [NSMutableData dataWithLength:sizeof(screen_char_t) * (length + 1)];
    screen_char_t *buffer = (screen_char_t *)data.mutableBytes;
    memmove(buffer, self.line, MIN(length, self.length) * sizeof(screen_char_t));

    // Copy continuation to added section if needed.
    screen_char_t continuation = self.continuation;
    screen_char_t zero = { 0 };
    if (memcmp(&continuation, &zero, sizeof(continuation))) {
        for (int i = self.length; i < length; i++) {
            buffer[i] = continuation;
        }
    }
    unichar eol = self.eol;
    if (eol == EOL_SOFT &&
        buffer[length - 1].code == 0 &&
        eligibleForDWC) {
        // The last line in the scrollback buffer is actually a split DWC
        // if the first char on the screen is double-width and the buffer is soft-wrapped without
        // a last char.
        // Normally LineBuffer does this for you, but it can't if you're asking for the last line
        // in the line buffer since it won't know about the DWC that got wrapped into VT100Grid.
        eol = EOL_DWC;
    }
    if (eol == EOL_DWC) {
        ScreenCharSetDWC_SKIP(&buffer[length - 1]);
    }
    continuation.code = eol;
    memmove(&buffer[length], &continuation, sizeof(screen_char_t));
    return [[ScreenCharArray alloc] initWithData:data
                           includingContinuation:YES
                                        metadata:self.metadata
                                    continuation:continuation];
}

- (ScreenCharArray *)copyByZeroingRange:(NSRange)range {
    ScreenCharArray *theCopy = [self copy];
    screen_char_t *line = (screen_char_t *)theCopy->_line;
    for (NSInteger i = 0; i < range.length; i++) {
        line[range.location + i] = (screen_char_t){ 0 };
    }
    return theCopy;
}

- (ScreenCharArray *)paddedOrTruncatedToLength:(NSUInteger)newLength {
    if (newLength == self.length) {
        return self;
    }
    if (newLength < self.length) {
        return [[ScreenCharArray alloc] initWithCopyOfLine:self.line length:newLength continuation:self.continuation];
    }
    return [self paddedToLength:newLength eligibleForDWC:NO];
}

- (ScreenCharArray *)paddedToAtLeastLength:(NSUInteger)newLength {
    if (newLength <= self.length) {
        return self;
    }
    return [self paddedToLength:newLength eligibleForDWC:NO];
}

- (NSMutableData *)mutableLineData {
    return [[NSMutableData alloc] initWithBytes:self.line length:sizeof(screen_char_t) * self.length];
}

- (ScreenCharArray *)screenCharArrayBySettingCharacterAtIndex:(int)i
                                                           to:(screen_char_t)c {
    assert(i >= 0);
    assert(i < self.length);
    
    NSMutableData *temp = [self mutableLineData];
    screen_char_t *line = (screen_char_t *)temp.mutableBytes;
    line[i] = c;
    return [[ScreenCharArray alloc] initWithData:temp metadata:self.metadata continuation:self.continuation];
}

- (void)makeSafe {
    if (_data != nil) {
        return;
    }
    NSMutableData *mutableData = [[NSMutableData alloc] initWithLength:(_length + 1) * sizeof(screen_char_t)];
    screen_char_t *screenChars = (screen_char_t *)mutableData.mutableBytes;
    memmove((void *)screenChars, _line, _length * sizeof(screen_char_t));
    _data = mutableData;
    const screen_char_t eol = self.continuation;
    memmove(&screenChars[_length], &eol, sizeof(eol));
    _line = _data.bytes;
    _shouldFreeOnRelease = NO;
}

const BOOL ScreenCharIsNullOrWhitespace(const screen_char_t c) {
    if (ScreenCharIsNull(c)) {
        return YES;
    }
    if (c.image) {
        return NO;
    }
    if (!c.complexChar && c.code == TAB_FILLER) {
        return YES;
    }
    NSString *s = ScreenCharToStr(&c);;
    return [s rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0;
}

- (NSInteger)lengthExcludingTrailingWhitespaceAndNulls {
    NSInteger length = self.length;
    const screen_char_t *line = self.line;
    while (length > 0 && ScreenCharIsNullOrWhitespace(line[length - 1])) {
        length -= 1;
    }
    return length;
}

@end

