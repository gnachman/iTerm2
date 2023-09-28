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

- (void)mutateAttributesFrom:(int)start
                          to:(int)end
                       block:(iTermExternalAttribute * _Nullable(^)(iTermExternalAttribute * _Nullable))block {
    for (int x = start; x <= end; x++) {
        _attributes[@(x)] = block(_attributes[@(x)]);
    }
}

- (id)objectForKeyedSubscript:(id)key {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (iTermExternalAttribute *)objectAtIndexedSubscript:(NSInteger)idx {
    return _attributes[@(idx + _offset)];
}

- (void)setObject:(iTermExternalAttribute * _Nullable)ea atIndexedSubscript:(NSUInteger)i {
    _attributes[@(i + _offset)] = ea;
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

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [self copyWithZone:zone];
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

+ (iTermExternalAttributeIndex *)concatenationOf:(id<iTermExternalAttributeIndexReading>)lhs
                                          length:(int)lhsLength
                                            with:(id<iTermExternalAttributeIndexReading>)rhs
                                          length:(int)rhsLength {
    iTermExternalAttributeIndex *result = [[iTermExternalAttributeIndex alloc] init];
    [result appendValuesFrom:lhs range:NSMakeRange(0, lhsLength) at:0];
    [result appendValuesFrom:rhs range:NSMakeRange(0, rhsLength) at:lhsLength];
    return result;
}

- (void)appendValuesFrom:(id<iTermExternalAttributeIndexReading>)source
                   range:(NSRange)range
                      at:(int)base {
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
static NSString *const iTermExternalAttributeKeyBlockID = @"b";

@interface iTermExternalAttribute()
@property (atomic, readwrite) BOOL hasUnderlineColor;
@property (atomic, readwrite) VT100TerminalColorValue underlineColor;
@property (atomic, readwrite) unsigned int urlCode;
@property (atomic, copy, readwrite) NSString *blockID;
@end

@implementation iTermExternalAttribute

+ (iTermExternalAttribute *)attributeHavingUnderlineColor:(BOOL)hasUnderlineColor
                                           underlineColor:(VT100TerminalColorValue)underlineColor
                                                  urlCode:(unsigned int)urlCode 
                                                  blockID:(NSString *)blockID {
    if (!hasUnderlineColor && urlCode == 0 && blockID == nil) {
        return nil;
    }
    static iTermExternalAttribute *last;
    if (last &&
        last.hasUnderlineColor == hasUnderlineColor &&
        !memcmp(&last->_underlineColor, &underlineColor, sizeof(underlineColor)) &&
        last.urlCode == urlCode &&
        [NSObject object:last.blockID isEqualToObject:blockID]) {
        // Since this class is immutable, there's a nice optimization in reusing the last one created.
        return last;
    }
    if (hasUnderlineColor) {
        return [[self alloc] initWithUnderlineColor:underlineColor urlCode:urlCode blockID:blockID];
    }
    last = [[self alloc] initWithURLCode:urlCode blockID:blockID];
    return last;
}

+ (instancetype)fromData:(NSData *)data {
    iTermTLVDecoder *decoder = [[iTermTLVDecoder alloc] initWithData:data];
    
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
    unsigned int urlCode = 0;
    [decoder decodeUnsignedInt:&urlCode];
    
    if (!hasUnderlineColor && urlCode == 0) {
        return nil;
    }

    // V3
    NSData *blockData = [decoder decodeData];
    NSString *blockID = nil;
    if (blockData) {
        NSString *blockID = [[NSString alloc] initWithData:blockData encoding:NSUTF8StringEncoding];
        if (!blockID.length) {
            blockID = nil;
        }
    }
    return [[self alloc] initWithUnderlineColor:underlineColor
                                        urlCode:urlCode
                                        blockID:blockID];
}

- (instancetype)init {
    return [super init];
}

- (instancetype)initWithUnderlineColor:(VT100TerminalColorValue)color
                               urlCode:(unsigned int)urlCode
                               blockID:(NSString *)blockID {
    self = [self init];
    if (self) {
        self.hasUnderlineColor = YES;
        self.underlineColor = color;
        self.urlCode = urlCode;
        self.blockID = blockID;
    }
    return self;
}

- (instancetype)initWithURLCode:(unsigned int)urlCode blockID:(NSString *)blockID {
    self = [self init];
    if (self) {
        self.urlCode = urlCode;
        self.blockID = blockID;
    }
    return self;
}

// This is intended for users, so don't make it too wonky.
- (NSString *)humanReadableDescription {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (_hasUnderlineColor) {
        [parts addObject:[NSString stringWithFormat:@"underline=%@",
                          VT100TerminalColorValueDescription(_underlineColor, YES)]];
    }
    if (_urlCode) {
        [parts addObject:@"URL"];
    }
    if (_blockID) {
        [parts addObject:@"block"];
    }
    if (parts.count == 0) {
        return @"none";
    }
    return [parts componentsJoinedByString:@","];
}

- (NSString *)description {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (_hasUnderlineColor) {
        [parts addObject:[NSString stringWithFormat:@"ulc=%@",
                          VT100TerminalColorValueDescription(_underlineColor, YES)]];
    }
    if (_urlCode) {
        [parts addObject:[NSString stringWithFormat:@"url=%@", @(_urlCode)]];
    }
    if (_blockID) {
        [parts addObject:[NSString stringWithFormat:@"block=%@", _blockID]];
    }
    if (parts.count == 0) {
        return @"none";
    }
    return [parts componentsJoinedByString:@","];
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
    [encoder encodeUnsignedInt:_urlCode];
    [encoder encodeData:[_blockID dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]];

    return encoder.data;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        self.blockID = [NSString castFrom:dict[iTermExternalAttributeKeyBlockID]];
        id obj = dict[iTermExternalAttributeKeyUnderlineColor];
        if (![obj isKindOfClass:[NSNull class]]) {
            NSArray<NSNumber *> *values = [NSArray castFrom:obj];
            if (!values || values.count < 4) {
                return nil;
            }
            _hasUnderlineColor = YES;
            _underlineColor.mode = [values[0] intValue];
            _underlineColor.red = [values[1] intValue];
            _underlineColor.green = [values[2] intValue];
            _underlineColor.blue = [values[3] intValue];
        }
        _urlCode = [dict[iTermExternalAttributeKeyURLCode] unsignedIntValue];
        if (!_hasUnderlineColor && _urlCode == 0 && !self.blockID) {
            return nil;
        }
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    return @{
        iTermExternalAttributeKeyURLCode: @(_urlCode),
        iTermExternalAttributeKeyBlockID: self.blockID ?: [NSNull null],
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

- (id)mutableCopyWithZone:(NSZone *)zone {
    return [self copyWithZone:zone];
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

- (void)setObject:(iTermExternalAttribute * _Nullable)ea atIndexedSubscript:(NSUInteger)i {
    [self doesNotRecognizeSelector:_cmd];
}

- (void)mutateAttributesFrom:(int)start
                          to:(int)end
                       block:(iTermExternalAttribute * _Nullable (^)(iTermExternalAttribute * _Nullable))block {
    [self doesNotRecognizeSelector:_cmd];
}

- (void)enumerateSortedKeysInRange:(NSRange)range block:(void (^)(NSNumber *key))block {
    for (NSUInteger i = 0; i < range.length; i++) {
        block(@(range.location + i));
    }
}

@end

@interface NSMutableData(ScreenCharMigration)
- (void)migrateV2ToV3InPlace;
@end

@implementation NSMutableData(ScreenCharMigration)
- (void)migrateV2ToV3InPlace {
    screen_char_t *chars = (screen_char_t *)self.mutableBytes;
    for (NSUInteger i = 0; i < self.length / sizeof(screen_char_t); i++) {
        if (!chars[i].complexChar &&
            !chars[i].image &&
            chars[i].code >= ITERM2_LEGACY_PRIVATE_BEGIN &&
            chars[i].code <= ITERM2_LEGACY_PRIVATE_END) {
            chars[i].code = ITERM2_PRIVATE_BEGIN + (chars[i].code - ITERM2_LEGACY_PRIVATE_BEGIN);
        }
    }
}
@end

@implementation NSData(iTermExternalAttributes)

- (void)migrateV2ToV1:(NSMutableData *)modern {
    screen_char_t *chars = (screen_char_t *)modern.mutableBytes;
    for (NSUInteger i = 0; i < self.length / sizeof(screen_char_t); i++) {
        if (!chars[i].complexChar &&
            !chars[i].image &&
            chars[i].code >= ITERM2_PRIVATE_BEGIN &&
            chars[i].code <= ITERM2_PRIVATE_END) {
            chars[i].code = ITERM2_LEGACY_PRIVATE_BEGIN + (chars[i].code - ITERM2_PRIVATE_BEGIN);
        }
    }
}

- (NSData *)migrateV1ToV3:(iTermExternalAttributeIndex **)indexOut {
    const legacy_screen_char_t *source = (legacy_screen_char_t *)self.bytes;
    const NSUInteger length = self.length;
    assert(length < NSUIntegerMax);
    assert(length % sizeof(screen_char_t) == 0);
    assert(sizeof(legacy_screen_char_t) == sizeof(screen_char_t));
    const NSUInteger count = length / sizeof(legacy_screen_char_t);
    NSUInteger firstURLIndex = 0;
    for (firstURLIndex = 0; firstURLIndex < count; firstURLIndex++) {
        if (source[firstURLIndex].urlCode) {
            break;
        }
    }
    if (firstURLIndex == count) {
        // Fast path - no URLs present.
        if (indexOut) {
            *indexOut = nil;
        }
        return self;
    }
    
    // Slow path - convert URLs to external attributes.
    NSMutableData *modern = [NSMutableData dataWithLength:length];
    legacy_screen_char_t *dest = (legacy_screen_char_t *)modern.mutableBytes;
    memmove(dest, self.bytes, length);
    iTermExternalAttributeIndex *eaIndex = nil;
    for (NSUInteger i = firstURLIndex; i < count; i++) {
        if (dest[i].urlCode) {
            if (!eaIndex) {
                eaIndex = [[iTermExternalAttributeIndex alloc] init];
            }
            iTermExternalAttribute *ea = [iTermExternalAttribute attributeHavingUnderlineColor:NO
                                                                                underlineColor:(VT100TerminalColorValue){}
                                                                                       urlCode:dest[i].urlCode
                                                                                       blockID:nil];
            eaIndex[i] = ea;
            // This is a little hinky. dest goes from being a pointer to legacy_screen_char_t to screen_char_t at this point.
            // There's a rule that you can safely initialize a screen_char_t with 0s, so regardless of what future changes
            // screen_char_t undergoes, it will always migrate to 0s in the fields formerly occupied by urlCode.
            dest[i].urlCode = 0;
        }
    }
    [modern migrateV2ToV3InPlace];
    if (indexOut) {
        *indexOut = eaIndex;
    }
    return modern;
}

- (NSMutableData *)migrateV2ToV3 {
    NSMutableData *temp = [self mutableCopy];
    [temp migrateV2ToV3InPlace];
    return temp;
}

- (NSData *)legacyScreenCharArrayWithExternalAttributes:(iTermExternalAttributeIndex * _Nullable)eaIndex {
    const NSUInteger length = self.length;
    assert(length < NSUIntegerMax);
    assert(length % sizeof(screen_char_t) == 0);
    assert(sizeof(legacy_screen_char_t) == sizeof(screen_char_t));
    const NSUInteger count = length / sizeof(screen_char_t);

    NSMutableData *legacyData = [self mutableCopy];
    legacy_screen_char_t *dest = (legacy_screen_char_t *)legacyData.mutableBytes;
    for (NSUInteger i = 0; i < count; i++) {
        dest[i].urlCode = eaIndex[i].urlCode;
    }
    [self migrateV2ToV1:legacyData];
    return legacyData;
}

@end
