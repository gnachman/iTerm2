//
//  iTermExternalAttributeIndex.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/17/21.
//

#import "iTermExternalAttributeIndex.h"
#import "NSDictionary+iTerm.h"

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
        _attributes[@(storeBase + i)] = [source.attributes[@(loadBase + i)] copy];
    }
}

- (iTermExternalAttribute *)objectAtIndexedSubscript:(NSInteger)idx {
    return _attributes[@(idx + _offset)];
}

- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index {
    return [self subAttributesFromIndex:index maximumLength:INT_MAX];
}

- (iTermExternalAttributeIndex *)subAttributesFromIndex:(int)index maximumLength:(int)maxLength {
    iTermExternalAttributeIndex *sub = [[iTermExternalAttributeIndex alloc] init];
    sub->_offset = index;
    [_attributes enumerateKeysAndObjectsUsingBlock:^(NSNumber *_Nonnull key, iTermExternalAttribute *_Nonnull obj, BOOL * _Nonnull stop) {
        const int intKey = key.intValue;
        if (intKey < index) {
            return;
        }
        if (intKey >= index + maxLength) {
            *stop = YES;
            return;
        }
        sub->_attributes[key] = obj;
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

- (NSDictionary *)dictionaryValue {
    return @{
        iTermExternalAttributeKeyUnderlineColor: _hasUnderlineColor ? @[ @(_underlineColor.x),
                                                                         @(_underlineColor.y),
                                                                         @(_underlineColor.z),
                                                                         @(_underlineColor.w) ] : [NSNull null] };
}

- (id)copyWithZone:(NSZone *)zone {
    iTermExternalAttribute *copy = [[iTermExternalAttribute alloc] init];
    copy.hasUnderlineColor = _hasUnderlineColor;
    copy.underlineColor = _underlineColor;
    return copy;
}

@end

@implementation iTermUniformExternalAttributes {
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

@end

