//
//  iTermGenericEvaluator.m
//  iTerm2
//
//  Created by George Nachman on 12/31/25.
//

#import "iTermGenericEvaluator.h"

#import "DebugLogging.h"
#import "iTermAPIHelper.h"
#import "iTermExpressionEvaluator.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

@interface iTermGenericEvaluator()
@property (nonatomic) BOOL needsReevaluation;
@property (nonatomic) NSInteger count;
@property (nonatomic) NSInteger appliedCount;
@end

@implementation iTermGenericEvaluator {
    NSMutableSet<NSString *> *_missingFunctions;
    iTermVariableScope *_scope;
    BOOL _observing;
    iTermVariableReference<NSString *> *_sourceRef;
    BOOL _sideEffectsAllowed;
}

- (instancetype)initWithString:(NSString *)stringToEvaluate
                        scope:(iTermVariableScope *)scope
            sideEffectsAllowed:(BOOL)sideEffectsAllowed
                      observer:(id(^)(id, NSError *))observer {
    self = [super init];
    if (self) {
        _stringToEvaluate = [stringToEvaluate copy];
        _scope = scope;
        _refs = [NSMutableArray array];
        _observer = [observer copy];
        _missingFunctions = [NSMutableSet set];
        _sideEffectsAllowed = sideEffectsAllowed;
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
              destinationPath:(NSString *)destinationPath
           sideEffectsAllowed:(BOOL)sideEffectsAllowed {
    self = [super init];
    if (self) {
        _sideEffectsAllowed = sideEffectsAllowed;
        _stringToEvaluate = [[NSString castFrom:[scope valueForVariableName:sourcePath]] copy] ?: @"";
        _scope = scope;
        _refs = [NSMutableArray array];
        _missingFunctions = [NSMutableSet set];
        _destinationPath = [destinationPath copy];
        _sourceRef = [[iTermVariableReference alloc] initWithPath:sourcePath vendor:scope];
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
    DLog(@"%@->%@ sourceDidChange to %@", _sourceRef.path, _destinationPath, _sourceRef.value);
    self.stringToEvaluate = [NSString castFrom:_sourceRef.value] ?: @"";
}

- (void)setStringToEvaluate:(NSString *)stringToEvaluate {
    if ([NSObject object:stringToEvaluate isEqualToObject:_stringToEvaluate]) {
        return;
    }
    _stringToEvaluate = [stringToEvaluate copy];
    if (_evaluationResult) {
        // Update the refs without losing the cached evaluation.
        [self evaluateSynchronously:YES
                 sideEffectsAllowed:NO
                         completion:^(id newValue, NSError *error) {}];
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

- (iTermVariableScope *)scope {
    if (_contextProvider) {
        return _contextProvider() ?: _scope;
    }
    return _scope;
}

- (void)setEvaluatedResult:(id)evaluationResult error:(NSError *)error {
    if (error == nil && [NSObject object:evaluationResult isEqualToObject:self.evaluationResult]) {
        return;
    }

    _evaluationResult = [evaluationResult copy];
    if (self.destinationPath) {
        [_scope setValue:evaluationResult forVariableNamed:self.destinationPath];
    }

    ITAssertWithMessage(!_observing, @"Already observing");
    if (!self.observer) {
        DLog(@"Swifty string %@ has no observer", self);
        return;
    }
    _observing = YES;
    id replacement = self.observer(_evaluationResult, error);
    if (![NSObject object:replacement isEqualToObject:_evaluationResult]) {
        _evaluationResult = replacement;
        if (self.destinationPath) {
            [_scope setValue:replacement forVariableNamed:self.destinationPath];
        }
        self.observer(_evaluationResult, nil);
    }
    _observing = NO;
}

- (void)evaluateSynchronously:(BOOL)synchronously sideEffectsAllowed:(BOOL)sideEffectsAllowed {
    __weak __typeof(self) weakSelf = self;
    NSInteger count = ++_count;
    DLog(@"%p: %@->%@ evaluate %@", self, _sourceRef.path, _destinationPath, _stringToEvaluate);
    [self evaluateSynchronously:synchronously
             sideEffectsAllowed:sideEffectsAllowed
                     completion:^(id result, NSError *error) {
        DLog(@"%p: result=%@ error=%@", weakSelf, result, error);
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            if (strongSelf.appliedCount > count) {
                // A later async evaluation has already completed. Don't overwrite it.
                DLog(@"obsoleted");
                return;
            }
            strongSelf.appliedCount = count;
            if (error == nil && [NSObject object:strongSelf.evaluationResult isEqualToObject:result]) {
                DLog(@"unchanged");
                return;
            }
            [strongSelf setEvaluatedResult:result error:error];
        }
    }];
}

- (void)evaluateSynchronously:(BOOL)synchronously
           sideEffectsAllowed:(BOOL)sideEffectsAllowed
                   completion:(void (^)(id, NSError *))completion {
    iTermVariableRecordingScope *scope = [self.scope recordingCopy];
    __weak __typeof(self) weakSelf = self;
    [self evaluateSynchronously:synchronously
             sideEffectsAllowed:sideEffectsAllowed
                      withScope:scope
                     completion:^(id result, NSError *error, NSSet<NSString *> *missing) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_missingFunctions unionSet:missing];
        if (error) {
            NSString *message =
            [NSString stringWithFormat:@"Invocation of “%@” failed with error:\n%@\n",
             strongSelf.stringToEvaluate,
             [error localizedDescription]];

            NSString *connectionKey =
            error.userInfo[iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
            iTermScriptHistoryEntry *entry =
            [[iTermScriptHistory sharedInstance] entryWithIdentifier:connectionKey];
            if (!entry) {
                entry = [iTermScriptHistoryEntry globalEntry];
            }
            [entry addOutput:message completion:^{}];
        }
        completion(result, error);
    }];
    _refs = [scope recordedReferences];
    for (iTermVariableReference *ref in _refs) {
        ref.onChangeBlock = ^{
            [weakSelf dependencyDidChange];
        };
    }
}

- (iTermExpressionEvaluator *)expressionEvaluator {
    ITAssertWithMessage(NO, @"Subclass must implement this");
    [self doesNotRecognizeSelector:_cmd];
}

- (void)evaluateSynchronously:(BOOL)synchronously
           sideEffectsAllowed:(BOOL)sideEffectsAllowed
                   withScope:(iTermVariableScope *)scope
                   completion:(void (^)(id result, NSError *error, NSSet<NSString *> *missing))completion {
    iTermExpressionEvaluator *evaluator = [self expressionEvaluator];
    [evaluator evaluateWithTimeout:synchronously ? 0 : 30
                sideEffectsAllowed:sideEffectsAllowed
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
    if (!_evaluationResult) {
        _needsReevaluation = YES;
    }
    if (!_needsReevaluation) {
        return;
    }
    _needsReevaluation = NO;
    if (!_evaluationResult) {
        [self evaluateSynchronously:YES sideEffectsAllowed:NO];
    }
    [self evaluateSynchronously:NO sideEffectsAllowed:_sideEffectsAllowed];
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
