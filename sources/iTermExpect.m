//
//  iTermExpect.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/19.
//

#import "iTermExpect.h"

@interface iTermExpectation()
@property (nonatomic, readonly) void (^willExpect)(iTermExpectation *expectation);
@property (nullable, nonatomic, strong, readwrite) iTermExpectation *successor;
@property (nullable, nonatomic, weak, readwrite) iTermExpectation *predecessor;
@end

@implementation iTermExpectation {
    void (^_completion)(iTermExpectation *, NSArray<NSString *> * _Nonnull);
}

- (instancetype)initWithRegularExpression:(NSString *)regex
                               willExpect:(void (^)(iTermExpectation *))willExpect
                               completion:(void (^)(iTermExpectation *, NSArray<NSString *> * _Nonnull))completion {
    self = [super init];
    if (self) {
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
    _predecessor.successor = nil;
    _hasCompleted = YES;
    _completion = nil;
    _willExpect = nil;
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
                                   completion:(void (^)(NSArray<NSString *> *captureGroups))completion {
    return [self expectRegularExpression:regex
                                   after:nil
                              willExpect:nil
                              completion:completion];
}

- (iTermExpectation *)expectRegularExpression:(NSString *)regex
                                        after:(nullable iTermExpectation *)predecessor
                                   willExpect:(void (^ _Nullable)(void))willExpect
                                   completion:(void (^ _Nullable)(NSArray<NSString *> * _Nonnull))completion {
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

- (void)setTimeout:(NSTimeInterval)timeout forExpectation:(iTermExpectation *)expectation {
    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!expectation.hasCompleted) {
            [weakSelf cancelExpectation:expectation];
        }
    });
}

@end
