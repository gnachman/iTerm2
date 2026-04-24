//
//  iTermResult.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/14/20.
//

#import "iTermResult.h"

@implementation iTermResult {
    id _object;
    NSError *_error;
}

+ (instancetype)withError:(NSError *)error {
    assert(error);
    return [[self alloc] initWithObject:nil error:error];
}

+ (instancetype)withObject:(id)object {
    assert(object);
    return [[self alloc] initWithObject:object error:nil];
}

- (instancetype)initWithObject:(id)object error:(NSError *)error {
    self = [super init];
    if (self) {
        _object = object;
        _error = error;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@=%@>",
            NSStringFromClass(self.class),
            self,
            _object ? @"object" : @"error",
            _object ?: _error];
}

- (void)handleObject:(void (^)(id _Nonnull))object error:(void (^)(NSError * _Nonnull))error {
    if (_object) {
        object(_object);
        return;
    }
    error(_error);
}

@end
