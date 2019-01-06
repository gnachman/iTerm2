//
//  iTermWeakVariables.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import "iTermWeakVariables.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermWeakVariables

- (instancetype)initWithVariables:(iTermVariables *)variables {
    self = [super init];
    if (self) {
        _variables = variables;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        _variables = nil;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass([self class]), self, _variables];
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

@end

NS_ASSUME_NONNULL_END
