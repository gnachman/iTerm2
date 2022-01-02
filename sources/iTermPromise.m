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
- (instancetype)initWithLock:(NSObject *)lock
                    observer:(void (^)(iTermOr<id, NSError *> *))observer
NS_DESIGNATED_INITIALIZER;

- (void)fulfill:(id)value;
- (void)reject:(NSError *)error;

@end

@implementation iTermPromiseSeal {
    NSObject *_lock;
}

- (instancetype)initWithLock:(NSObject *)lock
                    observer:(void (^)(iTermOr<id, NSError *> *))observer {
    self = [super init];
    if (self) {
        _observer = [observer copy];
        _lock = lock;
    }
    return self;
}

- (void)fulfill:(id)value {
    assert(value);
    @synchronized (_lock) {
        assert(_value == nil);
        _value = [iTermOr first:value];
        self.observer(self.value);
    }
}

- (void)reject:(NSError *)error {
    assert(error);
    @synchronized (_lock) {
        assert(_value == nil);
        _value = [iTermOr second:error];
        self.observer(self.value);
    }
}

@end

@interface iTermPromise()
@property (nonatomic, strong) iTermOr<id, NSError *> *value;
@property (nonatomic, copy) id<iTermPromiseSeal> seal;
@property (nonatomic, strong) void (^callback)(iTermOr<id, NSError *> *);
@end

@implementation iTermPromise {
    NSObject *_lock;
    BOOL _haveNotified;
}

+ (void)mutateStorage:(void (^)(NSMutableSet<iTermPromise *> *storage))block {
    static dispatch_once_t onceToken;
    static NSMutableSet<iTermPromise *> *storage;
    dispatch_once(&onceToken, ^{
        storage = [NSMutableSet set];
    });

    @synchronized([iTermPromise class]) {
        block(storage);
    }
}

+ (instancetype)promise:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal>))block {
    return [[iTermPromise alloc] initPrivate:block];
}

- (instancetype)initPrivate:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal>))block {
    self = [super init];
    if (self) {
        _lock = [[NSObject alloc] init];
        __weak __typeof(self) weakSelf = self;
        iTermPromiseSeal *seal = [[iTermPromiseSeal alloc] initWithLock:_lock
                                                               observer:^(iTermOr<id,NSError *> *or) {
            [or whenFirst:^(id object) { [weakSelf didFulfill:object]; }
                   second:^(NSError *object) { [weakSelf didReject:object]; }];
        }];
        [iTermPromise mutateStorage:^(NSMutableSet<iTermPromise *> *storage) {
            [storage addObject:self];
        }];
        if (self) {
            block(seal);
        }
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    return self == object;
}

- (NSUInteger)hash {
    NSUInteger result;
    void *selfPtr = (__bridge void *)self;
    assert(sizeof(result) == sizeof(selfPtr));
    memmove(&result, &selfPtr, sizeof(result));
    return result;
}

- (void)didFulfill:(id)object {
    @synchronized (_lock) {
        assert(!self.value);
        self.value = [iTermOr first:object];
        [iTermPromise mutateStorage:^(NSMutableSet<iTermPromise *> *storage) {
            [storage removeObject:self];
        }];
    }
}

- (void)didReject:(NSError *)error {
    @synchronized (_lock) {
        assert(!self.value);
        self.value = [iTermOr second:error];
        [iTermPromise mutateStorage:^(NSMutableSet<iTermPromise *> *storage) {
            [storage removeObject:self];
        }];
    }
}

- (void)setValue:(iTermOr<id, NSError *> *)value {
    @synchronized (_lock) {
        assert(!_value);
        assert(value);

        _value = value;
        [self notify];
    }
}

- (void)setCallback:(void (^)(iTermOr<id,NSError *> *))callback {
    @synchronized (_lock) {
        assert(!_callback);
        assert(callback);

        _callback = callback;
        [self notify];
    }
}

- (void)notify {
    @synchronized (_lock) {
        assert(!_haveNotified);
        _haveNotified = YES;
        if (!self.callback || !self.value) {
            return;
        }
        self.callback(self.value);
    }
}

- (iTermPromise *)then:(void (^)(id))block {
    @synchronized (_lock) {
        assert(!self.callback);

        iTermPromise *next = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
            self.callback = ^(iTermOr<id,NSError *> *value) {
                // _lock is held at this point since this is called from -notify.
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
}

- (iTermPromise *)catchError:(void (^)(NSError *error))block {
    @synchronized (_lock) {
        assert(!self.callback);

        iTermPromise *next = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
            self.callback = ^(iTermOr<id,NSError *> *value) {
                // _lock is held at this point since this is called from -notify.
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
}

- (BOOL)hasValue {
    @synchronized (_lock) {
        return self.value != nil;
    }
}

@end
