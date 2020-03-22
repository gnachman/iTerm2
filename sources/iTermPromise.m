//
//  iTermPromise.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/10/20.
//

#import "iTermPromise.h"

#import "NSObject+iTerm.h"

@implementation iTermOr {
    id _first;
    id _second;
}

+ (instancetype)first:(id)object {
    assert(object);
    return [[self alloc] initWithFirst:object second:nil];
}

+ (instancetype)second:(id)object {
    assert(object);
    return [[self alloc] initWithFirst:nil second:object];
}

- (instancetype)initWithFirst:(id)first second:(id)second {
    self = [super init];
    if (self) {
        _first = first;
        _second = second;
    }
    return self;
}

- (void)whenFirst:(void (^ NS_NOESCAPE)(id))firstBlock
           second:(void (^ NS_NOESCAPE)(id))secondBlock {
    if (_first && firstBlock) {
        firstBlock(_first);
    } else if (_second && secondBlock) {
        secondBlock(_second);
    }
}

- (BOOL)hasFirst {
    return _first != nil;
}

- (BOOL)hasSecond {
    return _second != nil;
}

- (NSString *)description {
    __block NSString *value;
    [self whenFirst:^(id  _Nonnull object) {
        value = [NSString stringWithFormat:@"first=%@", object];
    } second:^(id  _Nonnull object) {
        value = [NSString stringWithFormat:@"second=%@", object];
    }];
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass(self.class), self, value];
}

- (BOOL)isEqual:(id)object {
    if (object == self) {
        return YES;
    }
    iTermOr *other = [iTermOr castFrom:object];
    if (!other) {
        return NO;
    }
    return [NSObject object:_first isEqualToObject:other->_first] && [NSObject object:_second isEqualToObject:other->_second];
}

- (NSUInteger)hash {
    return [_first hash] | [_second hash];
}

@end

@interface iTermPromiseSeal: NSObject<iTermPromiseSeal>

@property (nonatomic, readonly) iTermOr<id, NSError *> *value;
@property (nonatomic, readonly) void (^observer)(iTermOr<id, NSError *> *value);

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithObserver:(void (^)(iTermOr<id, NSError *> *))observer NS_DESIGNATED_INITIALIZER;

- (void)fulfill:(id)value;
- (void)reject:(NSError *)error;

@end

@implementation iTermPromiseSeal

- (instancetype)initWithObserver:(void (^)(iTermOr<id, NSError *> *))observer {
    self = [super init];
    if (self) {
        _observer = [observer copy];
    }
    return self;
}

- (void)fulfill:(id)value {
    assert(_value == nil);
    assert(value);
    _value = [iTermOr first:value];
    self.observer(self.value);
}

- (void)reject:(NSError *)error {
    assert(_value == nil);
    assert(error);
    _value = [iTermOr second:error];
    self.observer(self.value);
}

@end

@interface iTermPromise()
@property (nonatomic, strong) iTermOr<id, NSError *> *value;
@property (nonatomic, copy) id<iTermPromiseSeal> seal;
@property (nonatomic, strong) void (^callback)(iTermOr<id, NSError *> *);
@end

@implementation iTermPromise

+ (instancetype)promise:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal>))block {
    return [[iTermPromise alloc] initPrivate:block];
}

- (instancetype)initPrivate:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal>))block {
    self = [super init];
    __weak __typeof(self) weakSelf = self;
    iTermPromiseSeal *seal = [[iTermPromiseSeal alloc] initWithObserver:^(iTermOr<id,NSError *> *or) {
        [or whenFirst:^(id object) {
            [weakSelf didFulfill:object];
        }
               second:^(NSError *object) {
            [weakSelf didReject:object];
        }];
    }];
    if (!seal) {
        return nil;
    }
    if (self) {
        block(seal);
    }
    return self;
}

- (void)didFulfill:(id)object {
    assert(!self.value);
    self.value = [iTermOr first:object];
}

- (void)didReject:(NSError *)error {
    assert(!self.value);
    self.value = [iTermOr second:error];
}

- (void)setValue:(iTermOr<id, NSError *> *)value {
    assert(!_value);
    assert(value);

    _value = value;
    [self notify];
}

- (void)setCallback:(void (^)(iTermOr<id,NSError *> *))callback {
    assert(!_callback);
    assert(callback);

    _callback = callback;
    [self notify];
}

- (void)notify {
    if (!self.callback || !self.value) {
        return;
    }
    self.callback(self.value);
}

- (iTermPromise *)then:(void (^)(id))block {
    assert(!self.callback);

    iTermPromise *next = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        self.callback = ^(iTermOr<id,NSError *> *value) {
            [value whenFirst:^(id object) {
                block(object);
                [seal fulfill:object];
            }
                      second:^(NSError *object) {
                [seal reject:object];
            }];
        };
    }];
    return next;
}

- (iTermPromise *)catchError:(void (^)(NSError *error))block {
    assert(!self.callback);

    iTermPromise *next = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        self.callback = ^(iTermOr<id,NSError *> *value) {
            [value whenFirst:^(id object) {
                [seal fulfill:object];
            }
                      second:^(NSError *object) {
                block(object);
                [seal reject:object];
            }];
        };
    }];
    return next;
}

@end
