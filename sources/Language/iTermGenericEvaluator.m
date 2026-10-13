//
//  iTermGenericEvaluator.m
//  iTerm2
//
//  Created by George Nachman on 12/31/25.
//

#import "iTermGenericEvaluator.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAPIHelper.h"
#import "iTermExpressionEvaluator.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

@interface iTermGenericEvaluator()
@property (nonatomic) NSInteger count;
@property (nonatomic) NSInteger appliedCount;
@end

@implementation iTermGenericEvaluator {
    NSMutableSet<NSString *> *_missingFunctions;
    iTermVariableScope *_scope;
    BOOL _observing;
    iTermVariableReference<NSString *> *_sourceRef;
    BOOL _sideEffectsAllowed;
    iTermIdempotentOperationJoiner *_reevaluationJoiner;
    BOOL _invalidated;
    // Incremented each time an evaluation starts. Only the newest
    // evaluation may install its dependencies as _refs.
    NSInteger _refsGeneration;
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
        _reevaluationJoiner = [iTermIdempotentOperationJoiner asyncJoiner:dispatch_get_main_queue()];
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
        _reevaluationJoiner = [iTermIdempotentOperationJoiner asyncJoiner:dispatch_get_main_queue()];
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
    // Idempotent because the usual lifecycle invalidates twice: callers
    // invalidate explicitly before dropping their reference, and then
    // -dealloc invalidates again. -removeObserver: is O(the process's
    // entire observer registrar) even when this object registered
    // nothing, so the second pass costs as much as the first while
    // having nothing left to remove.
    if (_invalidated) {
        return;
    }
    _invalidated = YES;
    _observer = nil;
    _sourceRef.onChangeBlock = nil;
    [_sourceRef invalidate];
    [_reevaluationJoiner invalidate];
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
    const NSInteger generation = ++_refsGeneration;
    __block BOOL completed = NO;
    [self evaluateSynchronously:synchronously
             sideEffectsAllowed:sideEffectsAllowed
                      withScope:scope
                     completion:^(id result, NSError *error, NSSet<NSString *> *missing) {
        completed = YES;
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        // An asynchronous evaluation can read variables after it starts
        // (for example, a built-in function's default arguments are read
        // only once its explicit arguments have been evaluated), so the
        // dependencies are complete only now.
        [strongSelf installReferencesFromScope:scope
                                    generation:generation
                                  keepExisting:NO];
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
    if (!completed) {
        // Observe what has been read so far while the evaluation is in
        // flight, without dropping dependencies an earlier evaluation
        // established: this one may not have read them yet, and a change
        // to one of them before it does would otherwise go unnoticed.
        // The completion block replaces these with the full set.
        [self installReferencesFromScope:scope
                              generation:generation
                            keepExisting:YES];
    }
}

- (void)installReferencesFromScope:(iTermVariableRecordingScope *)scope
                        generation:(NSInteger)generation
                      keepExisting:(BOOL)keepExisting {
    if (_invalidated || generation != _refsGeneration) {
        // Either nothing should be observed any more, or a newer
        // evaluation started (possibly of a different string), so these
        // dependencies are stale.
        return;
    }
    __weak __typeof(self) weakSelf = self;
    NSArray<iTermVariableReference *> *added = [scope recordedReferences];
    // Merging by path alone assumes the scope does not change while an
    // evaluation is in flight; a stale ref only costs a reevaluation.
    if (keepExisting && _refs.count > 0) {
        NSSet<NSString *> *existingPaths = [NSSet setWithArray:[_refs mapWithBlock:^id(iTermVariableReference *ref) {
            return ref.path;
        }]];
        added = [added filteredArrayUsingBlock:^BOOL(iTermVariableReference *ref) {
            return ![existingPaths containsObject:ref.path];
        }];
        _refs = [_refs arrayByAddingObjectsFromArray:added];
    } else {
        _refs = added;
    }
    for (iTermVariableReference *ref in added) {
        ref.onChangeBlock = ^{
            [weakSelf dependencyDidChange];
        };
    }
}

- (iTermExpressionEvaluator *)expressionEvaluatorUsingScope:(iTermVariableScope *)scope {
    ITAssertWithMessage(NO, @"Subclass must implement this");
    [self doesNotRecognizeSelector:_cmd];
}

- (void)evaluateSynchronously:(BOOL)synchronously
           sideEffectsAllowed:(BOOL)sideEffectsAllowed
                   withScope:(iTermVariableScope *)scope
                   completion:(void (^)(id result, NSError *error, NSSet<NSString *> *missing))completion {
    iTermExpressionEvaluator *evaluator = [self expressionEvaluatorUsingScope:scope];
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
    __weak __typeof(self) weakSelf = self;
    [_reevaluationJoiner setNeedsUpdateWithBlock:^{
        [weakSelf reevaluateIfNeeded];
    }];
}

- (void)reevaluateIfNeeded {
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
