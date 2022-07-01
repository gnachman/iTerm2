//
//  iTermTuple.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/9/18.
//

#import "iTermTuple.h"

#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

static NSString *const iTermTupleValueKey = @"value";

@implementation iTermTuple

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)tupleWithObject:(id)firstObject andObject:(id)secondObject {
    iTermTuple *tuple = [[self alloc] init];
    tuple.firstObject = firstObject;
    tuple.secondObject = secondObject;
    return tuple;
}

+ (instancetype)fromPlistValue:(id)plistValue {
    NSArray *array = [NSArray castFrom:plistValue];
    NSDictionary *firstDict = [array uncheckedObjectAtIndex:0] ?: @{};
    NSDictionary *secondDict = [array uncheckedObjectAtIndex:1] ?: @{};
    return [iTermTuple tupleWithObject:firstDict[iTermTupleValueKey]
                             andObject:secondDict[iTermTupleValueKey]];
}

+ (NSArray<iTermTuple *> *)cartesianProductOfArray:(NSArray *)a1
                                              with:(NSArray *)a2 {
    return [a1 flatMapWithBlock:^NSArray *(id v1) {
        return [a2 mapWithBlock:^id(id v2) {
            return [iTermTuple tupleWithObject:v1 andObject:v2];
        }];
    }];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        _firstObject = [aDecoder decodeObjectForKey:@"firstObject"];
        _secondObject = [aDecoder decodeObjectForKey:@"secondObject"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_firstObject forKey:@"firstObject"];
    [aCoder encodeObject:_secondObject forKey:@"secondObject"];
}

- (id)plistValue {
    NSDictionary *first = self.firstObject ? @{ iTermTupleValueKey: self.firstObject } : @{};
    NSDictionary *second = self.secondObject ? @{ iTermTupleValueKey: self.secondObject } : @{};
    return @[ first, second ];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p (%@, %@)>",
            NSStringFromClass([self class]),
            self,
            _firstObject,
            _secondObject];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[self class]]) {
        return NO;
    }
    iTermTuple *other = object;
    return ((_firstObject == other->_firstObject || [_firstObject isEqual:other->_firstObject]) &&
            (_secondObject == other->_secondObject || [_secondObject isEqual:other->_secondObject]));
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] tupleWithObject:_firstObject andObject:_secondObject];
}

- (NSUInteger)hash {
    return iTermMikeAshHash([_firstObject hash],
                            [_secondObject hash]);
}

- (NSComparisonResult)compare:(id)object {
    iTermTuple *other = [iTermTuple castFrom:object];
    if (!other) {
        return NSOrderedAscending;
    }

    NSComparisonResult result = [self.firstObject compare:other.firstObject];
    if (result != NSOrderedSame) {
        return result;
    }
    return [self.secondObject compare:other.secondObject];
}

@end

@implementation iTermTriple

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)tripleWithObject:(id)firstObject andObject:(id)secondObject object:(id)thirdObject {
    iTermTriple *triple = [super tupleWithObject:firstObject andObject:secondObject];
    triple->_thirdObject = thirdObject;
    return triple;
}

+ (instancetype)fromPlistValue:(id)plistValue {
    NSArray *array = [NSArray castFrom:plistValue];
    NSDictionary *firstDict = [array uncheckedObjectAtIndex:0] ?: @{};
    NSDictionary *secondDict = [array uncheckedObjectAtIndex:1] ?: @{};
    NSDictionary *thirdDict = [array uncheckedObjectAtIndex:2] ?: @{};
    return [iTermTriple tripleWithObject:firstDict[iTermTupleValueKey]
                               andObject:secondDict[iTermTupleValueKey]
                                  object:thirdDict[iTermTupleValueKey]];
}


- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        _thirdObject = [aDecoder decodeObjectForKey:@"thirdObject"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_thirdObject forKey:@"thirdObject"];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p (%@, %@, %@)>",
            NSStringFromClass([self class]),
            self,
            self.firstObject,
            self.secondObject,
            _thirdObject];
}

- (id)plistValue {
    NSDictionary *first = self.firstObject ? @{ iTermTupleValueKey: self.firstObject } : @{};
    NSDictionary *second = self.secondObject ? @{ iTermTupleValueKey: self.secondObject } : @{};
    NSDictionary *third = self.thirdObject ? @{ iTermTupleValueKey: self.thirdObject } : @{};
    return @[ first, second, third ];
}

- (BOOL)isEqual:(id)object {
    if (![super isEqual:object]) {
        return NO;
    }
    iTermTriple *other = object;
    return (_thirdObject == other->_thirdObject || [_thirdObject isEqual:other->_thirdObject]);
}

- (id)copyWithZone:(NSZone *)zone {
    return [iTermTriple tripleWithObject:self.firstObject
                               andObject:self.secondObject
                                  object:_thirdObject];
}

- (NSUInteger)hash {
    return iTermCombineHash([super hash],
                            [_thirdObject hash]);
}

- (NSComparisonResult)compare:(id)object {
    iTermTriple *other = [iTermTriple castFrom:object];
    if (!other) {
        return NSOrderedAscending;
    }

    NSComparisonResult result = [self.firstObject compare:other.firstObject];
    if (result != NSOrderedSame) {
        return result;
    }
    result = [self.secondObject compare:other.secondObject];
    if (result != NSOrderedSame) {
        return result;
    }
    return [self.thirdObject compare:other.thirdObject];
}

@end
