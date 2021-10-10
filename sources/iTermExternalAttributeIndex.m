//
//  iTermExternalAttributeIndex.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/17/21.
//

#import "iTermExternalAttributeIndex.h"
#import "iTermTLVCodec.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "ScreenChar.h"

@implementation iTermExternalAttributeIndex {
    NSMutableDictionary<NSNumber *, iTermExternalAttribute *> *_attributes;
    NSInteger _offset;  // Add this to externally visible indexes to get keys into _attributes.
}

+ (instancetype)withDictionary:(NSDictionary *)dictionary {
    return [[self alloc] initWithDictionary:dictionary];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if (!dictionary.count) {
        return nil;
    }
    iTermUniformExternalAttributes *uniform = [[iTermUniformExternalAttributes alloc] initWithDictionary:dictionary];
    if (uniform) {
        return uniform;
    }
    self = [self init];
    if (self) {
        [dictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            NSNumber *x = [NSNumber castFrom:key];
            if (!x) {
                return;
            }
            NSDictionary *dict = [NSDictionary castFrom:obj];
            if (!dict) {
                return;
            }
            iTermExternalAttribute *attr = [[iTermExternalAttribute alloc] initWithDictionary:dict];
            [self setAttributes:attr at:x.intValue count:1];
        }];
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _attributes = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (instancetype)fromData:(NSData *)data {
    iTermExternalAttributeIndex *eaIndex = [[iTermExternalAttributeIndex alloc] init];
    iTermTLVDecoder *decoder = [[iTermTLVDecoder alloc] initWithData:data];
    while (!decoder.finished) {
        NSRange range;
        if (![decoder decodeRange:&range]) {
            return nil;
        }
        NSData *data = [decoder decodeData];
        if (!data) {
            return nil;
        }
        iTermExternalAttribute *attr = [iTermExternalAttribute fromData:data];
        [eaIndex setAttributes:attr at:range.location count:range.length];
    }
    return eaIndex;
}

- (NSData *)encodedRange:(NSRange)range {
    return [NSData dataWithBytes:&range length:sizeof(range)];
}

- (NSData *)data {
    iTermTLVEncoder *encoder = [[iTermTLVEncoder alloc] init];
    [self enumerateValuesInRange:NSMakeRange(0, NSUIntegerMax) block:^(NSRange range, iTermExternalAttribute *attr) {
        [encoder encodeRange:range];
        [encoder encodeData:[attr data]];
    }];
    return encoder.data;
}

- (NSDictionary *)attributes {
    return _attributes;
}

- (NSInteger)offset {
    return _offset;
}

- (NSDictionary *)dictionaryValue {
    return [_attributes mapValuesWithBlock:^id(NSNumber *key, iTermExternalAttribute *attribute) {
        return attribute.dictionaryValue;
    }];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass([self class]), self, [self shortDescriptionWithLength:[self largestKey] + 1]];
}

- (NSUInteger)largestKey {
    NSNumber *key = [_attributes.allKeys maxWithComparator:^(NSNumber *lhs, NSNumber *rhs) {
        return [lhs compare:rhs];
    }];
    return [key unsignedIntegerValue];
}

- (NSString *)shortDescriptionWithLength:(int)length {
    NSMutableArray<NSString *> *array = [NSMutableArray array];
    [self enumerateValuesInRange:NSMakeRange(0, length) block:^(NSRange range, iTermExternalAttribute *attr) {
        [array addObject:[NSString stringWithFormat:@"%@=%@", NSStringFromRange(range), [attr description]]];
    }];
    return [array componentsJoinedByString:@","];
}

- (void)enumerateValuesInRange:(NSRange)range block:(void (^NS_NOESCAPE)(NSRange, iTermExternalAttribute * _Nonnull))block {
    __block NSNumber *startOfRunKey = nil;
    __block NSNumber *endOfRunKey = nil;
    void (^emit)(void) = ^{
        assert(startOfRunKey);
        assert(endOfRunKey);
        assert(self[startOfRunKey.unsignedIntegerValue]);
        assert(endOfRunKey.unsignedIntegerValue >= startOfRunKey.unsignedIntegerValue);
        block(NSMakeRange(startOfRunKey.unsignedIntegerValue,
                          endOfRunKey.unsignedIntegerValue - startOfRunKey.unsignedIntegerValue + 1),
              self[startOfRunKey.unsignedIntegerValue]);
    };
    void (^accumulate)(NSNumber *) = ^(NSNumber *key) {
        assert(key);
        if (!startOfRunKey) {
            // Start of first run.
            startOfRunKey = key;
            endOfRunKey = key;
            return;
        }
        if (key.unsignedIntegerValue == endOfRunKey.unsignedIntegerValue + 1 &&
            [self[startOfRunKey.unsignedIntegerValue] isEqualToExternalAttribute:self[key.unsignedIntegerValue]]) {
            // Continue current run.
            endOfRunKey = key;
            return;
        }

        // Run ended. Begin a new run.
        emit();
        startOfRunKey = key;
        endOfRunKey = key;
    };
    [self enumerateSortedKeysInRange:range block:^(NSNumber *key) {
        accumulate(key);
    }];
    if (startOfRunKey) {
        emit();
    }
}

// Subclasses override this.
- (void)enumerateSortedKeysInRange:(NSRange)range block:(void (^)(NSNumber *key))block {
    NSArray<NSNumber *> *sortedKeys = [[_attributes allKeys] sortedArrayUsingSelector:@selector(compare:)];
    [sortedKeys enumerateObjectsUsingBlock:^(NSNumber * _Nonnull key, NSUInteger idx, BOOL * _Nonnull stop) {
        if (!NSLocationInRange(key.unsignedIntegerValue - _offset, range)) {
            return;
        }
        block(key);
    }];
}

- (void)copyFrom:(iTermExternalAttributeIndex *)source
          source:(int)loadBase
     destination:(int)storeBase
           count:(int)count {
    int start;
    int end;
    int stride;
    if (source == self && storeBase > loadBase) {
        // Copying to the right within self.
        start = count - 1;
        end = -1;
        stride = -1;
    } else {
        // Copying to other object or to the left.
        start = 0;
        end = count;
        stride = 1;
    }
    for (int i = start; i != end; i += stride) {
        _attributes[@(storeBase + i)] = source[loadBase + i];
    }
}

- (id)objectForKeyedSubscript:(id)key {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (iTermExternalAttribute *)objectAtIndexedSubscript:(NSInteger)idx {
    return _attributes[@(idx + _offset)];
}

- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index {
    return [self subAttributesFromIndex:index maximumLength:INT_MAX];
}

- (iTermExternalAttributeIndex *)subAttributesToIndex:(int)index {
    return [self subAttributesFromIndex:0 maximumLength:index];
}

- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index maximumLength:(int)maxLength {
    iTermExternalAttributeIndex *sub = [[iTermExternalAttributeIndex alloc] init];
    sub->_offset = 0;
    [_attributes enumerateKeysAndObjectsUsingBlock:^(NSNumber *_Nonnull key, iTermExternalAttribute *_Nonnull obj, BOOL * _Nonnull stop) {
        const int intKey = key.intValue + _offset;
        if (intKey < index) {
            return;
        }
        if (intKey >= (NSInteger)index + (NSInteger)maxLength) {
            return;
        }
        sub->_attributes[@(intKey - index)] = obj;
    }];
    return sub;
}

- (id)copyWithZone:(NSZone *)zone {
    iTermExternalAttributeIndex *copy = [[iTermExternalAttributeIndex alloc] init];
    copy->_attributes = [_attributes mutableCopy];
    return copy;
}

- (void)eraseAt:(int)x {
    [_attributes removeObjectForKey:@(x + _offset)];
}

- (void)eraseInRange:(VT100GridRange)range {
    for (int i = 0; i < range.length; i++) {
        [self eraseAt:i + range.location];
    }
}

- (void)setAttributes:(iTermExternalAttribute *)attributes at:(int)start count:(int)count {
    for (int i = 0; i < count; i++) {
        _attributes[@(i + start + _offset)] = attributes;
    }
}

+ (iTermExternalAttributeIndex *)concatenationOf:(iTermExternalAttributeIndex *)lhs
                                      length:(int)lhsLength
                                        with:(iTermExternalAttributeIndex *)rhs
                                      length:(int)rhsLength {
    iTermExternalAttributeIndex *result = [[iTermExternalAttributeIndex alloc] init];
    [result appendValuesFrom:lhs range:NSMakeRange(0, lhsLength) at:0];
    [result appendValuesFrom:rhs range:NSMakeRange(0, rhsLength) at:lhsLength];
    return result;
}

- (void)appendValuesFrom:(iTermExternalAttributeIndex *)source range:(NSRange)range at:(int)base {
    [source.attributes enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, iTermExternalAttribute * _Nonnull obj, BOOL * _Nonnull stop) {
        const int intKey = key.intValue;
        if (intKey < range.location) {
            return;
        }
        if (intKey >= NSMaxRange(range)) {
            return;
        }
        _attributes[@(intKey + base + _offset)] = obj;
    }];
}

@end

static NSString *const iTermExternalAttributeKeyUnderlineColor = @"uc";
static NSString *const iTermExternalAttributeKeyURLCode = @"url";

@implementation iTermExternalAttribute

+ (instancetype)fromData:(NSData *)data {
    iTermTLVDecoder *decoder = [[iTermTLVDecoder alloc] initWithData:data];
    
    int version = 1;
    
    // v1
    BOOL hasUnderlineColor;
    if (![decoder decodeBool:&hasUnderlineColor]) {
        return nil;
    }
    VT100TerminalColorValue underlineColor = { 0 };
    if (hasUnderlineColor) {
        if (![decoder decodeInt:&underlineColor.red]) {
            return nil;
        }
        if (![decoder decodeInt:&underlineColor.green]) {
            return nil;
        }
        if (![decoder decodeInt:&underlineColor.blue]) {
            return nil;
        }
        int temp;
        if (![decoder decodeInt:&temp]) {
            return nil;
        }
        underlineColor.mode = temp;
    }
    
    // v2
    int urlCode = 0;
    if ([decoder decodeInt:&urlCode]) {
        version = 2;
    }
    
    if (!hasUnderlineColor && urlCode == 0) {
        return nil;
    }
    return [[self alloc] initWithUnderlineColor:underlineColor
                                        urlCode:urlCode];
}

- (instancetype)init {
    return [super init];
}

- (instancetype)initWithUnderlineColor:(VT100TerminalColorValue)color
                               urlCode:(int)urlCode {
    self = [self init];
    if (self) {
        _hasUnderlineColor = YES;
        _underlineColor = color;
        _urlCode = urlCode;
    }
    return self;
}

- (NSString *)description {
    if (!_hasUnderlineColor) {
        return @"none";
    }
    return [NSString stringWithFormat:@"ulc=%@ url=%@",
            VT100TerminalColorValueDescription(_underlineColor, YES),
            @(_urlCode)];
}

- (NSData *)data {
    iTermTLVEncoder *encoder = [[iTermTLVEncoder alloc] init];
    [encoder encodeBool:_hasUnderlineColor];
    if (_hasUnderlineColor) {
        [encoder encodeInt:_underlineColor.red];
        [encoder encodeInt:_underlineColor.green];
        [encoder encodeInt:_underlineColor.blue];
        [encoder encodeInt:_underlineColor.mode];
    }
    [encoder encodeInt:_urlCode];
    return encoder.data;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        id obj = dict[iTermExternalAttributeKeyUnderlineColor];
        if ([obj isKindOfClass:[NSNull class]]) {
            return self;
        }
        _hasUnderlineColor = YES;

        NSArray<NSNumber *> *values = [NSArray castFrom:obj];
        if (!values || values.count < 4) {
            return nil;
        }
        _underlineColor.mode = [values[0] intValue];
        _underlineColor.red = [values[1] intValue];
        _underlineColor.green = [values[2] intValue];
        _underlineColor.blue = [values[3] intValue];
        
        _urlCode = [dict[iTermExternalAttributeKeyURLCode] intValue];
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    return @{
        iTermExternalAttributeKeyURLCode: @(_urlCode),
        iTermExternalAttributeKeyUnderlineColor: _hasUnderlineColor ? @[ @(_underlineColor.mode),
                                                                         @(_underlineColor.red),
                                                                         @(_underlineColor.green),
                                                                         @(_underlineColor.blue) ] : [NSNull null] };
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqualToExternalAttribute:(iTermExternalAttribute *)rhs {
    if (_urlCode != rhs.urlCode) {
        return NO;
    }
    if (_hasUnderlineColor != rhs.hasUnderlineColor) {
        return NO;
    }
    if (!_hasUnderlineColor && !rhs.hasUnderlineColor) {
        return YES;
    }
    return !memcmp(&_underlineColor, &rhs->_underlineColor, sizeof(_underlineColor));
}

@end

@implementation iTermUniformExternalAttributes  {
    iTermExternalAttribute *_attr;
}

+ (instancetype)withAttribute:(iTermExternalAttribute *)attr {
    return [[self alloc] initWithAttribute:attr];
}

- (instancetype)initWithAttribute:(iTermExternalAttribute *)attr {
    if (!attr) {
        return nil;
    }
    self = [super init];
    if (self) {
        _attr = attr;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    NSDictionary *value = dictionary[@"all"];
    if (!value) {
        return nil;
    }
    self = [super init];
    if (self) {
        _attr = [[iTermExternalAttribute alloc] initWithDictionary:value];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass([self class]), self, _attr];
}

- (NSString *)shortDescriptionWithLength:(int)length {
    return [self description];
}

- (NSDictionary *)dictionaryValue {
    return @{ @"all": _attr.dictionaryValue };
}

- (void)copyFrom:(iTermExternalAttributeIndex *)source
          source:(int)loadBase
     destination:(int)storeBase
           count:(int)count {
    [self doesNotRecognizeSelector:_cmd];
}

- (iTermExternalAttribute *)objectAtIndexedSubscript:(NSInteger)idx {
    return _attr;
}

- (iTermExternalAttributeIndex *)subAttributesToIndex:(int)index {
    return self;
}

- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index {
    return self;
}

- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index maximumLength:(int)maxLength {
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (void)eraseAt:(int)x {
    [self doesNotRecognizeSelector:_cmd];
}

- (void)eraseInRange:(VT100GridRange)range {
    [self doesNotRecognizeSelector:_cmd];
}

- (void)setAttributes:(iTermExternalAttribute *)attributes at:(int)start count:(int)count {
    [self doesNotRecognizeSelector:_cmd];
}

- (void)enumerateSortedKeysInRange:(NSRange)range block:(void (^)(NSNumber *key))block {
    for (NSUInteger i = 0; i < range.length; i++) {
        block(@(range.location + i));
    }
}

@end

@implementation NSData(iTermExternalAttributes)

- (NSData *)modernizedScreenCharArray:(iTermExternalAttributeIndex **)indexOut {
    const legacy_screen_char_t *source = (legacy_screen_char_t *)self.bytes;
    const NSUInteger length = self.length;
    assert(length < NSUIntegerMax);
    NSUInteger firstURLIndex = 0;
    for (firstURLIndex = 0; firstURLIndex < length; firstURLIndex++) {
        if (source[firstURLIndex].urlCode) {
            break;
        }
    }
    if (firstURLIndex == length) {
        // Fast path - no URLs present.
        if (indexOut) {
            *indexOut = nil;
        }
        return self;
    }
    
    // Slow path - convert URLs to external attributes.
    NSMutableData *modern = [NSMutableData dataWithLength:self.length];
    legacy_screen_char_t *dest = (legacy_screen_char_t *)modern.mutableBytes;
    memmove(dest, self.bytes, length);
    iTermExternalAttributeIndex *eaIndex = nil;
    for (NSUInteger i = firstURLIndex; i < length; i++) {
        if (dest[i].urlCode) {
            if (!eaIndex) {
                eaIndex = [[iTermExternalAttributeIndex alloc] init];
            }
            eaIndex[i].urlCode = dest[i].urlCode;
            // This is a little hinky. dest goes from being a pointer to legacy_screen_char_t to screen_char_t at this point.
            // There's a rule that you can safely initialize a screen_char_t with 0s, so regardless of what future changes
            // screen_char_t undergoes, it will always migrate to 0s in the fields formerly occupied by urlCode.
            dest[i].urlCode = 0;
        }
    }
    if (indexOut) {
        *indexOut = eaIndex;
    }
    return modern;
}

@end
