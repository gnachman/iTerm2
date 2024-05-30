//
//  iTermPromise.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/10/20.
//

#import "iTermPromise.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
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

- (id)maybeFirst {
    return _first;
}

- (id)maybeSecond {
    return _second;
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
                     promise:(id)promise
                    observer:(void (^)(iTermOr<id, NSError *> *))observer
NS_DESIGNATED_INITIALIZER;

@end

@implementation iTermPromiseSeal {
    NSObject *_lock;
    // The seal keeps the promise from getting dealloced. This gets nilled out after fulfill/reject.
    // This works because the provider must eventually either fulfill or reject and it has to keep
    // the seal around until that happens.
    id _promise;
}

- (instancetype)initWithLock:(NSObject *)lock
                     promise:(id)promise
                    observer:(void (^)(iTermOr<id, NSError *> *))observer {
    self = [super init];
    if (self) {
        _observer = [observer copy];
        _promise = promise;
        _lock = lock;
    }
    return self;
}

- (void)dealloc {
    // This assertion fails if the seal was dealloc'ed without fulfill or reject called.
    assert(_promise == nil);
}

- (void)fulfill:(id)value {
    assert(value);
    @synchronized (_lock) {
        assert(_value == nil);
        _value = [iTermOr first:value];
        self.observer(self.value);
        _promise = nil;
    }
}

- (void)reject:(NSError *)error {
    assert(error);
    @synchronized (_lock) {
        assert(_value == nil);
        _value = [iTermOr second:error];
        self.observer(self.value);
        _promise = nil;
    }
}

- (void)rejectWithDefaultError {
    [self reject:[NSError errorWithDomain:@"com.iterm2.promise" code:0 userInfo:nil]];
}

@end

typedef void (^iTermPromiseCallback)(iTermOr<id, NSError *> *);

@interface iTermPromise()
@property (nonatomic, strong) iTermOr<id, NSError *> *value;
@property (nonatomic, copy) id<iTermPromiseSeal> seal;
@property (nonatomic, strong) NSMutableArray<iTermPromiseCallback> *callbacks;
@end

@implementation iTermPromise {
@protected
    NSObject *_lock;
    BOOL _waited;
}

+ (instancetype)promise:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal>))block {
    return [[self alloc] initPrivate:block];
}

+ (instancetype)promiseValue:(id)value {
    return [self promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
        if (value) {
            [seal fulfill:value];
        } else {
            [seal rejectWithDefaultError];
        }
    }];
}

+ (instancetype)promiseDefaultError {
    return [self promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
        [seal rejectWithDefaultError];
    }];
}

+ (void)gather:(NSArray<iTermPromise<id> *> *)promises
         queue:(dispatch_queue_t)queue
    completion:(void (^)(NSArray<iTermOr<id, NSError *> *> *values))completion {
    dispatch_group_t group = dispatch_group_create();
    [promises enumerateObjectsUsingBlock:^(iTermPromise<id> * _Nonnull promise, NSUInteger idx, BOOL * _Nonnull stop) {
        dispatch_group_enter(group);
        [[promise then:^(id  _Nonnull value) {
            dispatch_group_leave(group);
        }] catchError:^(NSError * _Nonnull error) {
            dispatch_group_leave(group);
        }];
    }];
    dispatch_group_notify(group, queue, ^{
        NSArray<iTermOr<id, NSError *> *> *ors = [promises mapWithBlock:^id(iTermPromise<id> *promise) {
            return promise.value;
        }];
        completion(ors);
    });
}

- (instancetype)initPrivate:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal>))block {
    self = [super init];
    if (self) {
        _callbacks = [NSMutableArray array];
        _lock = [[NSObject alloc] init];
        __weak __typeof(self) weakSelf = self;
        iTermPromiseSeal *seal = [[iTermPromiseSeal alloc] initWithLock:_lock
                                                                promise:self
                                                               observer:^(iTermOr<id,NSError *> *or) {
            [or whenFirst:^(id object) { [weakSelf didFulfill:object]; }
                   second:^(NSError *object) { [weakSelf didReject:object]; }];
        }];
        if (self) {
            block(seal);
        }
    }
    DLog(@"create %@", self);
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
    DLog(@"fulfill %@", self);
    @synchronized (_lock) {
        assert(!self.value);
        self.value = [iTermOr first:object];
    }
}

- (void)didReject:(NSError *)error {
    @synchronized (_lock) {
        assert(!self.value);
        self.value = [iTermOr second:error];
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

- (void)addCallback:(iTermPromiseCallback)callback {
    @synchronized (_lock) {
        assert(callback);
        assert(_callbacks);
        [_callbacks addObject:[callback copy]];

        [self notify];
    }
}

- (void)notify {
    @synchronized (_lock) {
        id value = self.value;
        if (!value) {
            return;
        }
        NSArray<iTermPromiseCallback> *callbacks = [self.callbacks copy];
        [self.callbacks removeAllObjects];
        [callbacks enumerateObjectsUsingBlock:^(iTermPromiseCallback _Nonnull callback, NSUInteger idx, BOOL * _Nonnull stop) {
            callback(value);
        }];
    }
}

- (iTermPromise *)then:(void (^)(id))block {
    @synchronized (_lock) {

        iTermPromise *next = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
            [self addCallback:^(iTermOr<id,NSError *> *value) {
                // _lock is held at this point since this is called from -notify.
                [value whenFirst:^(id object) {
                    block(object);
                    [seal fulfill:object];
                }
                          second:^(NSError *object) {
                    [seal reject:object];
                }];
            }];
        }];
        return next;
    }
}

- (iTermPromise *)catchError:(void (^)(NSError *error))block {
    @synchronized (_lock) {
        iTermPromise *next = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
            [self addCallback:^(iTermOr<id,NSError *> *value) {
                // _lock is held at this point since this is called from -notify.
                [value whenFirst:^(id object) {
                    [seal fulfill:object];
                }
                          second:^(NSError *object) {
                    block(object);
                    [seal reject:object];
                }];
            }];
        }];
        return next;
    }
}

static void iTermPromiseRunBlockOnQueue(dispatch_queue_t queue, id parameter, void (^block)(id)) {
    if (dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == dispatch_queue_get_label(queue)) {
        block(parameter);
        return;
    }
    dispatch_async(queue, ^{
        block(parameter);
    });
}

- (iTermPromise *)onQueue:(dispatch_queue_t)queue then:(void (^)(id value))block {
    return [self then:^(id  _Nonnull value) {
        iTermPromiseRunBlockOnQueue(queue, value, block);
    }];
}

- (iTermPromise *)onQueue:(dispatch_queue_t)queue catchError:(void (^)(NSError *error))block {
    return [self catchError:^(NSError * _Nonnull error) {
        iTermPromiseRunBlockOnQueue(queue, error, block);
    }];
}

- (BOOL)hasValue {
    @synchronized (_lock) {
        return self.value != nil;
    }
}

- (id)maybeValue {
    __block id result = nil;
    @synchronized (_lock) {
        [self.value whenFirst:^(id  _Nonnull object) {
            result = object;
        } second:^(NSError * _Nonnull object) {
            result = nil;
        }];
    }
    return result;
}

- (id)maybeError {
    __block NSError *result = nil;
    @synchronized (_lock) {
        [self.value whenFirst:^(id  _Nonnull object) {
            result = nil;
        } second:^(NSError * _Nonnull error) {
            result = error;
        }];
    }
    return result;
}

- (iTermOr<id, NSError *> *)wait {
    dispatch_group_t group = dispatch_group_create();
    @synchronized (_lock) {
        if (self.hasValue) {
            return self.value;
        }
        dispatch_group_enter(group);
        _waited = YES;
        [self addCallback:^(iTermOr<id, NSError *> *result) {
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    @synchronized (_lock) {
        return self.value;
    }
}

@end

@implementation iTermRenegablePromise

+ (instancetype)promise:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal> seal))block
                renege:(void (^)(void))renege {
    iTermRenegablePromise *promise = [super promise:block];
    if (promise) {
        promise->_renegeBlock = [renege copy];
    }
    return promise;
}

- (void)dealloc {
    DLog(@"dealloc %@", self);
    [self renege];
}

- (void)renege {
    @synchronized (_lock) {
        if (self.value || _waited) {
            return;
        }
        if (_renegeBlock) {
            void (^block)(void) = _renegeBlock;
            _renegeBlock = nil;
            block();
        }
    }
}

@end
