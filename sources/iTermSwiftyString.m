//
//  iTermSwiftyString.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/12/18.
//

#import "iTermSwiftyString.h"

#import "DebugLogging.h"
#import "iTermAPIHelper.h"
#import "iTermExpressionEvaluator.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

@interface iTermSwiftyString()
@property (nonatomic, copy, readwrite) NSString *evaluatedString;
@property (nonatomic) BOOL needsReevaluation;
@property (nonatomic) NSInteger count;
@property (nonatomic) NSInteger appliedCount;
@end

@implementation iTermSwiftyString {
    NSMutableSet<NSString *> *_missingFunctions;
    iTermVariableScope *_scope;
    BOOL _observing;
    iTermVariableReference<NSString *> *_sourceRef;
}

- (instancetype)initWithString:(NSString *)swiftyString
                        scope:(iTermVariableScope *)scope
                      observer:(void (^)(NSString * _Nonnull))observer {
    self = [super init];
    if (self) {
        _swiftyString = [swiftyString copy];
        _scope = scope;
        _refs = [NSMutableArray array];
        _observer = [observer copy];
        _missingFunctions = [NSMutableSet set];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(registeredFunctionsDidChange:)
                                                     name:iTermAPIRegisteredFunctionsDidChangeNotification
                                                   object:nil];
        [self reevaluateIfNeeded];
    }
    return self;
}

- (instancetype)initWithScope:(iTermVariableScope *)scope
                   sourcePath:(nonnull NSString *)sourcePath
              destinationPath:(NSString *)destinationPath {
    self = [super init];
    if (self) {
        _swiftyString = [[NSString castFrom:[scope valueForVariableName:sourcePath]] copy] ?: @"";
        _scope = scope;
        _refs = [NSMutableArray array];
        _missingFunctions = [NSMutableSet set];
        _destinationPath = [destinationPath copy];
        _sourceRef = [[iTermVariableReference alloc] initWithPath:sourcePath scope:scope];
        __weak __typeof(self) weakSelf = self;
        _sourceRef.onChangeBlock = ^{
            [weakSelf sourceDidChange];
        };
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(registeredFunctionsDidChange:)
                                                     name:iTermAPIRegisteredFunctionsDidChangeNotification
                                                   object:nil];
        [self reevaluateIfNeeded];
    }
    return self;
}

- (void)dealloc {
    [self invalidate];
}

- (void)sourceDidChange {
    self.swiftyString = [NSString castFrom:_sourceRef.value] ?: @"";
}

- (void)setSwiftyString:(NSString *)swiftyString {
    if ([NSObject object:swiftyString isEqualToObject:_swiftyString]) {
        return;
    }
    _swiftyString = [swiftyString copy];
    if (_evaluatedString) {
        // Update the refs without losing the cached evaluation.
        [self evaluateSynchronously:YES completion:^(NSString *newValue) {}];
    }
    // Reevaluate later, which may happen asynchronously.
    [self setNeedsReevaluation];
}

- (void)invalidate {
    _observer = nil;
    _sourceRef.onChangeBlock = nil;
    [_sourceRef invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Private

- (void)setEvaluatedString:(NSString *)evaluatedString {
    if ([NSObject object:evaluatedString isEqualToObject:self.evaluatedString]) {
        return;
    }

    _evaluatedString = [evaluatedString copy];
    if (self.destinationPath) {
        [_scope setValue:evaluatedString forVariableNamed:self.destinationPath];
    }

    assert(!_observing);
    if (!self.observer) {
        DLog(@"Swifty string %@ has no observer", self);
        return;
    }
    _observing = YES;
    self.observer(_evaluatedString);
    _observing = NO;
}

- (void)evaluateSynchronously:(BOOL)synchronously {
    __weak __typeof(self) weakSelf = self;
    NSInteger count = ++_count;
    [self evaluateSynchronously:synchronously completion:^(NSString *result) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            if (strongSelf.appliedCount > count) {
                // A later async evaluation has already completed. Don't overwrite it.
                return;
            }
            strongSelf.appliedCount = count;
            if ([NSObject object:strongSelf.evaluatedString isEqualToObject:result]) {
                return;
            }
            strongSelf.evaluatedString = result;
        }
    }];
}

- (void)evaluateSynchronously:(BOOL)synchronously
                   completion:(void (^)(NSString *))completion {
    iTermVariableRecordingScope *scope = [_scope recordingCopy];
    __weak __typeof(self) weakSelf = self;
    [self evaluateSynchronously:synchronously withScope:scope completion:^(NSString *result, NSError *error, NSSet<NSString *> *missing) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_missingFunctions unionSet:missing];
        if (error) {
            NSString *message =
            [NSString stringWithFormat:@"Invocation of “%@” failed with error:\n%@\n",
             strongSelf.swiftyString,
             [error localizedDescription]];

            NSString *connectionKey =
            error.userInfo[iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
            iTermScriptHistoryEntry *entry =
            [[iTermScriptHistory sharedInstance] entryWithIdentifier:connectionKey];
            if (!entry) {
                entry = [iTermScriptHistoryEntry globalEntry];
            }
            [entry addOutput:message];

        }
        completion(result);
    }];
    _refs = [scope recordedReferences];
    for (iTermVariableReference *ref in _refs) {
        ref.onChangeBlock = ^{
            [weakSelf dependencyDidChange];
        };
    }
}

- (void)evaluateSynchronously:(BOOL)synchronously
                   withScope:(iTermVariableScope *)scope
                   completion:(void (^)(NSString *result, NSError *error, NSSet<NSString *> *missing))completion {
    iTermExpressionEvaluator *evaluator = [[iTermExpressionEvaluator alloc] initWithInterpolatedString:_swiftyString
                                                                                                 scope:scope];
    [evaluator evaluateWithTimeout:synchronously ? 0 : 30
                        completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
                            completion(evaluator.value, evaluator.error, evaluator.missingValues);
                        }];
}

- (void)dependencyDidChange {
    if (!_observing) {
        [self setNeedsReevaluation];
    }
    
}
- (void)setNeedsReevaluation {
    self.needsReevaluation = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.needsReevaluation) {
            [self reevaluateIfNeeded];
        }
    });
}

- (void)reevaluateIfNeeded {
    if (!_evaluatedString) {
        _needsReevaluation = YES;
    }
    if (!_needsReevaluation) {
        return;
    }
    _needsReevaluation = NO;
    if (!_evaluatedString) {
        [self evaluateSynchronously:YES];
    }
    [self evaluateSynchronously:NO];
}

#pragma mark - Notifications

- (void)registeredFunctionsDidChange:(NSNotification *)notification {
    NSArray<NSString *> *registered = [_missingFunctions.allObjects filteredArrayUsingBlock:^BOOL(NSString *signature) {
        return [[iTermAPIHelper sharedInstance] haveRegisteredFunctionWithSignature:signature];
    }];
    if (!registered.count) {
        return;
    }
    [_missingFunctions minusSet:[NSSet setWithArray:registered]];
    [self setNeedsReevaluation];
}

@end

@implementation iTermSwiftyStringPlaceholder {
    NSString *_string;
}

- (instancetype)initWithString:(NSString *)swiftyString {
    self = [super initWithString:@""
                           scope:nil
                        observer:^(NSString * _Nonnull newValue) {}];
    if (self) {
        _string = [swiftyString copy];
    }
    return self;
}

- (NSString *)swiftyString {
    return _string;
}

@end
