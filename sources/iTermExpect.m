//
//  iTermExpect.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/19.
//

#import "iTermExpect.h"

#import "NSArray+iTerm.h"

// The concurrency model is based on multi-version concurrency. The API is designed so that merge conflicts cannot happen.
// Clients on the main thread can add or cancel expectations.
// Periodically, the main-thread instance of iTermExpect will be copied into the mutation thread.
// This snapshot persists for a short time.
// The mutation thread performs matching and may call didMatchWithCaptureGroups:.
// Calls to didMatchWithCaptureGroups: on the mutation thread schedule matching main-thread calls.
// These main thread calls update the main thread's copy of iTermExpect (e.g., adding and removing
// expectations) and also run user callbacks.
// During a call to didMatchWithCaptureGroups: the mutation thread updates its internal state in the
// same way.
// Races are inevitable. For example, the main thread could cancel an expectation that already ran
// on the mutation thread. In this case the completion() callback would not be run (since the
// cancellation would mark it as completed before the async -didMatchWithCaptureGroups: runs).
// The goal for dealing with races is to always have a consistent internal state and to be racey
// only in the ways that there are inherent races in matching input from an external process.
@interface iTermExpectation()
@property (nonatomic, readonly) void (^willExpect)(iTermExpectation *expectation);
@property (nullable, nonatomic, strong, readwrite) iTermExpectation *successor;
@property (nullable, nonatomic, weak, readwrite) iTermExpectation *predecessor;
@property (nonatomic, nullable, weak) iTermExpectation *original;
@end

@implementation iTermExpectation {
    void (^_completion)(iTermExpectation *, NSArray<NSString *> * _Nonnull);
}

- (instancetype)initWithOriginal:(iTermExpectation *)original
                      willExpect:(void (^)(iTermExpectation *))willExpect
                      completion:(void (^)(iTermExpectation *, NSArray<NSString *> * _Nonnull))completion {
    self = [self initWithRegularExpression:original.regex
                                  deadline:original.deadline
                                willExpect:willExpect
                                completion:completion];
    if (self) {
        _original = original;
    }
    return self;
}

- (instancetype)initWithRegularExpression:(NSString *)regex
                                 deadline:(NSDate *)deadline
                               willExpect:(void (^)(iTermExpectation *))willExpect
                               completion:(void (^)(iTermExpectation *, NSArray<NSString *> * _Nonnull))completion {
    self = [super init];
    if (self) {
        _deadline = deadline;
        _completion = [completion copy];
        _willExpect = [willExpect copy];
        _regex = [regex copy];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p regex=%@ hasCompleted=%@ successors=%@>",
            NSStringFromClass(self.class), self, _regex, @(self.hasCompleted), _successor];
}

- (iTermExpectation *)lastExpectation {
    return _successor ?: self;
    return self;
}

- (void)didMatchWithCaptureGroups:(NSArray<NSString *> *)captureGroups {
    if (self.original) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.original.hasCompleted) {
                return;
            }
            [weakSelf.original didMatchWithCaptureGroups:captureGroups];
        });
    }
    _hasCompleted = YES;
    if (_completion) {
        _completion(self, captureGroups);
    }
    _completion = nil;
    if (_successor) {
        [_successor expect];
    }
}

- (void)addSuccessor:(iTermExpectation *)successor {
    assert([NSThread isMainThread]);
    iTermExpectation *current = self;
    while (current.successor) {
        current = current.successor;
    }
    current.successor = successor;
    successor.predecessor = self;
}

- (void)expect {
    assert(!_hasCompleted);
    _willExpect(self);
}

- (void)cancel {
    [_successor cancel];
    _predecessor.successor = nil;
    _hasCompleted = YES;
    _completion = nil;
    _willExpect = nil;
    if (self.original) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.original cancel];
        });
    }
}

@end

@implementation iTermExpect {
    NSMutableArray<iTermExpectation *> *_expectations;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _expectations = [NSMutableArray array];
    }
    return self;
}

- (iTermExpectation *)expectRegularExpression:(NSString *)regex
                                        after:(nullable iTermExpectation *)predecessor
                                     deadline:(nullable NSDate *)deadline
                                   willExpect:(void (^ _Nullable)(void))willExpect
                                   completion:(void (^ _Nullable)(NSArray<NSString *> * _Nonnull))completion {
    assert([NSThread isMainThread]);
    __weak __typeof(self) weakSelf = self;
    void (^internalWillExpect)(iTermExpectation *) = ^(iTermExpectation *expectation){
        if (willExpect) {
            willExpect();
        }
        [weakSelf addExpectation:expectation];
    };
    void (^internalCompletion)(iTermExpectation *, NSArray<NSString *> *) = ^(iTermExpectation *expectation,
                                                                              NSArray<NSString *> *captureGroups) {
        [weakSelf removeExpectation:expectation];
        if (completion) {
            completion(captureGroups);
        }
    };
    iTermExpectation *expectation = [[iTermExpectation alloc] initWithRegularExpression:regex
                                                                               deadline:deadline
                                                                             willExpect:internalWillExpect
                                                                             completion:internalCompletion];
    if (predecessor && !predecessor.hasCompleted) {
        [predecessor addSuccessor:expectation];
        return expectation;
    }
    [expectation expect];
    return expectation;
}

- (void)addExpectation:(iTermExpectation *)expectation {
    [_expectations addObject:expectation];
}

- (void)removeExpectation:(iTermExpectation *)expectation {
    [_expectations removeObject:expectation];
}

- (void)cancelExpectation:(iTermExpectation *)expectation {
    [expectation cancel];
    [_expectations removeObject:expectation];
}

- (NSArray<iTermExpectation *> *)expectations {
    [_expectations removeObjectsPassingTest:^BOOL(iTermExpectation *expectation) {
        return expectation.deadline != nil && expectation.deadline.timeIntervalSinceNow < 0;
    }];
    return [_expectations copy];
}

#pragma mark - NSCopying

- (iTermExpectation *)copyOfExpectation:(iTermExpectation *)original {
    __weak __typeof(self) weakSelf = self;
    void (^willExpect)(iTermExpectation *) = ^(iTermExpectation *obj) {
        [weakSelf addExpectation:obj];
    };
    void (^completion)(iTermExpectation *, NSArray<NSString *> *) = ^(iTermExpectation *obj,
                                                                      NSArray<NSString *> * _Nonnull captures) {
        [weakSelf removeExpectation:obj];
    };
    return [[iTermExpectation alloc] initWithOriginal:original
                                           willExpect:willExpect
                                           completion:completion];
}

- (id)copyWithZone:(NSZone *)zone {
    iTermExpect *theCopy = [[iTermExpect alloc] init];
    [self.expectations enumerateObjectsUsingBlock:^(iTermExpectation * _Nonnull original, NSUInteger idx, BOOL * _Nonnull stop) {
        [theCopy addExpectation:[self copyOfExpectation:original]];
    }];
    return theCopy;
}

@end
