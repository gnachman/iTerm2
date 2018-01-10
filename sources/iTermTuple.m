//
//  iTermTuple.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/9/18.
//

#import "iTermTuple.h"

@implementation iTermTuple

+ (instancetype)tupleWithObject:(id)firstObject andObject:(id)secondObject {
    iTermTuple *tuple = [[self alloc] init];
    tuple.firstObject = firstObject;
    tuple.secondObject = secondObject;
    return tuple;
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

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p (%@, %@)>",
            NSStringFromClass([self class]),
            self,
            _firstObject,
            _secondObject];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[iTermTuple class]]) {
        return NO;
    }
    iTermTuple *other = object;
    return ((_firstObject == other->_firstObject || [_firstObject isEqual:other->_firstObject]) &&
            (_secondObject == other->_secondObject || [_secondObject isEqual:other->_secondObject]));
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] tupleWithObject:_firstObject andObject:_secondObject];
}

// https://www.mikeash.com/pyblog/friday-qa-2010-06-18-implementing-equality-and-hashing.html
- (NSUInteger)hash {
    const NSUInteger hash1 = [_firstObject hash];
    const NSUInteger hash2 = [_secondObject hash];
    static const int rot = (CHAR_BIT * sizeof(NSUInteger)) / 2;
    return hash1 ^ ((hash2 << rot) | (hash2 >> rot));
}

@end
