//
//  iTermExternalAttributeIndex.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/17/21.
//

#import "iTermExternalAttributeIndex.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
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
    return [self init];
#warning TODO(externalAttributes): Decode the dictionary
#warning Remember to handle iTermUniformExternalAttributes
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _attributes = [NSMutableDictionary dictionary];
    }
    return self;
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
        _attributes[@(start + _offset)] = attributes;
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

@implementation iTermExternalAttribute

- (instancetype)init {
    return [super init];
}

- (instancetype)initWithUnderlineColor:(VT100TerminalColorValue)color {
    self = [self init];
    if (self) {
        _hasUnderlineColor = YES;
        _underlineColor = color;
    }
    return self;
}

- (NSString *)description {
    if (!_hasUnderlineColor) {
        return @"none";
    }
    return [NSString stringWithFormat:@"ulc=%@", VT100TerminalColorValueDescription(_underlineColor)];
}

- (NSDictionary *)dictionaryValue {
    return @{
        iTermExternalAttributeKeyUnderlineColor: _hasUnderlineColor ? @[ @(_underlineColor.mode),
                                                                         @(_underlineColor.red),
                                                                         @(_underlineColor.green),
                                                                         @(_underlineColor.blue) ] : [NSNull null] };
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqualToExternalAttribute:(iTermExternalAttribute *)rhs {
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

