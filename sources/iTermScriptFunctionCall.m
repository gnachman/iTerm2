//
//  iTermScriptFunctionCall.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/18.
//

#import "iTermScriptFunctionCall.h"
#import "iTermScriptFunctionCall+Private.h"

#import "DebugLogging.h"
#import "iTermAPIHelper.h"
#import "iTermBuiltInFunctions.h"
#import "iTermExpressionEvaluator.h"
#import "iTermFunctionCallParser.h"
#import "iTermScriptHistory.h"
#import "iTermTruncatedQuotedRecognizer.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSTimer+iTerm.h"

#import <CoreParse/CoreParse.h>

@implementation iTermScriptFunctionCall {
    NSError *_depError;
    // Maps an argument name to a parsed expression for its value.
    NSMutableDictionary<NSString *, iTermParsedExpression *> *_argToExpression;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _argToExpression = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)description {
    NSString *params = [[_argToExpression.allKeys mapWithBlock:^id(NSString *name) {
        return [NSString stringWithFormat:@"%@: %@", name, self->_argToExpression[name]];
    }] componentsJoinedByString:@", "];
    NSString *value = [NSString stringWithFormat:@"%@(%@)", self.name, params];
    return [NSString stringWithFormat:@"<Func %@>", value];
}

- (NSString *)signature {
    return iTermFunctionSignatureFromNameAndArguments(self.name,
                                                      _argToExpression.allKeys);
}

- (BOOL)isEqual:(id)object {
    iTermScriptFunctionCall *other = [iTermScriptFunctionCall castFrom:object];
    if (!other) {
        return NO;
    }
    return ([NSObject object:_depError isEqualToObject:other->_depError] &&
            [NSObject object:_argToExpression isEqualToObject:other->_argToExpression]);
}

#pragma mark - APIs

+ (void)evaluateExpression:(NSString *)expressionString
                   timeout:(NSTimeInterval)timeout
                     scope:(iTermVariableScope *)scope
                completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    iTermExpressionEvaluator *evaluator = [[iTermExpressionEvaluator alloc] initWithExpressionString:expressionString scope:scope];
    [evaluator evaluateWithTimeout:timeout completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
        completion(evaluator.value, evaluator.error, evaluator.missingValues);
    }];
}

+ (void)evaluateString:(NSString *)string
               timeout:(NSTimeInterval)timeout
                 scope:(iTermVariableScope *)scope
            completion:(void (^)(NSString *result,
                                 NSError *error,
                                 NSSet<NSString *> *missingFunctionSignatures))completion {
    iTermExpressionEvaluator *evaluator = [[iTermExpressionEvaluator alloc] initWithInterpolatedString:string
                                                                                                 scope:scope];
    [evaluator evaluateWithTimeout:timeout completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
        completion(evaluator.value, evaluator.error, evaluator.missingValues);
    }];
}

+ (void)callFunction:(NSString *)invocation
             timeout:(NSTimeInterval)timeout
               scope:(iTermVariableScope *)scope
          completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    iTermParsedExpression *expression = [[iTermFunctionCallParser callParser] parse:invocation
                                                                              scope:scope];
    switch (expression.expressionType) {
        case iTermParsedExpressionTypeArray:
        case iTermParsedExpressionTypeNumber:
        case iTermParsedExpressionTypeString: {
            NSString *reason = @"Expected a function call, not a literal";
            completion(nil,
                       [NSError errorWithDomain:@"com.iterm2.call"
                                           code:3
                                       userInfo:@{ NSLocalizedDescriptionKey: reason }],
                       nil);
            return;
        }
        case iTermParsedExpressionTypeError:
            completion(nil, expression.error, nil);
            return;

        case iTermParsedExpressionTypeNil: {
            NSString *reason = @"nil not allowed";
            completion(nil,
                       [NSError errorWithDomain:@"com.iterm2.call"
                                           code:4
                                       userInfo:@{ NSLocalizedDescriptionKey: reason }],
                       nil);
            return;
        }
        case iTermParsedExpressionTypeFunctionCall:
            [self performFunctionCall:expression.functionCall
                       fromInvocation:invocation
                                scope:scope
                              timeout:timeout
                           completion:completion];
            return;
        case iTermParsedExpressionTypeInterpolatedString: {
            NSString *reason = @"interpolated string not allowed";
            completion(nil,
                       [NSError errorWithDomain:@"com.iterm2.call"
                                           code:4
                                       userInfo:@{ NSLocalizedDescriptionKey: reason }],
                       nil);
            return;
        }
    }
    assert(NO);
}

+ (NSString *)signatureForFunctionCallInvocation:(NSString *)invocation
                                           error:(out NSError *__autoreleasing *)error {
    iTermVariableRecordingScope *permissiveScope = [[iTermVariableRecordingScope alloc] initWithScope:[[iTermVariableScope alloc] init]];
    permissiveScope.neverReturnNil = YES;
    iTermParsedExpression *expression = [[iTermFunctionCallParser callParser] parse:invocation
                                                                              scope:permissiveScope];
    switch (expression.expressionType) {
        case iTermParsedExpressionTypeNumber:
        case iTermParsedExpressionTypeString:
        case iTermParsedExpressionTypeArray:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected function call, not a literal" }];
            }
            return nil;

        case iTermParsedExpressionTypeError:
            if (error) {
                *error = expression.error;
            }
            return nil;

        case iTermParsedExpressionTypeFunctionCall:
            return expression.functionCall.signature;

        case iTermParsedExpressionTypeNil:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected function call, not nil" }];
            }
            return nil;
        case iTermParsedExpressionTypeInterpolatedString:
            if (error) {
                *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:3
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Expected function call, not an interpolated string" }];
            }
            return nil;
    }
    assert(NO);
}

#pragma mark - Function Calls

+ (void)performFunctionCall:(iTermScriptFunctionCall *)functionCall
             fromInvocation:(NSString *)invocation
                      scope:(iTermVariableScope *)scope
                    timeout:(NSTimeInterval)timeout
                 completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    __block NSTimer *timer = nil;
    if (timeout > 0) {
        timer = [NSTimer it_scheduledTimerWithTimeInterval:timeout repeats:NO block:^(NSTimer * _Nonnull theTimer) {
            if (timer == nil) {
                // Shouldn't happen
                return;
            }
            timer = nil;
            NSString *reason = [NSString stringWithFormat:@"Timeout (%@ sec) waiting for %@", @(timeout), invocation];
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };
            if (functionCall.connectionKey) {
                userInfo = [userInfo dictionaryBySettingObject:functionCall.connectionKey
                                                        forKey:iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
            }
            NSError *error = [NSError errorWithDomain:@"com.iterm2.call"
                                                 code:2
                                             userInfo:userInfo];
            completion(nil, error, nil);
        }];
    }
    [functionCall callWithScope:scope synchronous:(timeout == 0) completion:^(id output, NSError *error, NSSet<NSString *> *missing) {
        if (timeout > 0) {
            // Not synchronous
            if (timer == nil) {
                // Already timed out
                return;
            }
            [timer invalidate];
            timer = nil;
        }
        completion(output, error, missing);
    }];
}

- (void)addParameterWithName:(NSString *)name parsedExpression:(iTermParsedExpression *)expression {
    _argToExpression[name] = expression;
}

- (void)callWithScope:(iTermVariableScope *)scope
          synchronous:(BOOL)synchronous
           completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    if (_depError) {
        completion(nil, self->_depError, nil);
        return;
    }

    dispatch_group_t group = dispatch_group_create();
    NSMutableSet<NSString *> *mutableMissing = [NSMutableSet set];
    [self evaluateParametersWithScope:scope
                          synchronous:synchronous
                              missing:mutableMissing
                                group:group];
    void (^allParametersEvaluated)(NSSet<NSString *> *) = ^(NSSet<NSString *> *missing){
        if (self->_depError) {
            completion(nil, self->_depError, missing);
            return;
        }
        if (self.isBuiltinFunction) {
            [self callBuiltinFunctionWithScope:scope completion:^(id object, NSError *error) {
                completion(object, error, nil);
            }];
            return;
        }
        if (synchronous) {
            // This is useful because it causes the scope to be called for all depended-upon
            // variables even if the function can't be executed. This makes it possible for
            // the session name controller to build up its set of dependencies.
            completion(nil, nil, missing);
            return;
        }
        NSDictionary<NSString *, iTermParsedExpression *> *fullParameters = nil;
        self->_connectionKey = [[[iTermAPIHelper sharedInstance] connectionKeyForRPCWithName:self.name
                                                           explicitParametersWithExpressions:self->_argToExpression
                                                                                       scope:scope
                                                                              fullParameters:&fullParameters] copy];
        [[iTermAPIHelper sharedInstance] dispatchRPCWithName:self.name
                                                   arguments:[self valueDictionaryFromArgToExpressionDictionary:fullParameters ?: self->_argToExpression]  // Parameters are needed for error reporting
                                                  completion:^(id apiResult, NSError *apiError) {
                                                      NSSet<NSString *> *missing = nil;
                                                      if (apiError.code == iTermAPIHelperFunctionCallUnregisteredErrorCode) {
                                                          missing = [NSSet setWithObject:self.signature];
                                                      }
                                                      completion(apiResult, apiError, missing);
                                                  }];
    };
    if (synchronous) {
        allParametersEvaluated(nil);
    } else {
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            allParametersEvaluated(mutableMissing);
        });
    }
}

- (BOOL)isBuiltinFunction {
    return [[iTermBuiltInFunctions sharedInstance] haveFunctionWithName:_name
                                                              arguments:_argToExpression.allKeys];
}

- (void)callBuiltinFunctionWithScope:(iTermVariableScope *)scope
                           completion:(void (^)(id, NSError *))completion {
    iTermBuiltInFunctions *bif = [iTermBuiltInFunctions sharedInstance];
    [bif callFunctionWithName:_name
                   parameters:[self valueDictionaryFromArgToExpressionDictionary:_argToExpression]
                        scope:scope
                   completion:completion];
}

- (void)evaluateParametersWithScope:(iTermVariableScope *)scope
                        synchronous:(BOOL)synchronous
                            missing:(NSMutableSet<NSString *> *)missing
                              group:(dispatch_group_t)group {
    [_argToExpression enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermParsedExpression *_Nonnull parsedExpression, BOOL * _Nonnull stop) {
        if (self->_depError) {
            *stop = YES;
            return;
        }
        dispatch_group_enter(group);
        iTermExpressionEvaluator *evaluator = [[iTermExpressionEvaluator alloc] initWithParsedExpression:parsedExpression
                                                                                                   scope:scope];
        [evaluator evaluateWithTimeout:synchronous ? 0 : INFINITY completion:^(iTermExpressionEvaluator *evaluator){
            if (evaluator.error) {
                if (parsedExpression.functionCall) {
                    self->_depError = [self errorForDependentCall:expr.functionCall
                                              thatFailedWithError:evaluator.error
                                                    connectionKey:self->_connectionKey];
                } else {
                    self->_depError = evaluator.error;
                }
            } else {
#warning TODO: Save the evaluator instead of relying on a retain loop to keep it. Have another dictionary for values.
                self->_evaluatedParameters[key] = evaluator.value;
            }
            [missing unionSet:evaluator.missingValues];
            dispatch_group_leave(group);
        }];
    }];
}

- (NSError *)errorForDependentCall:(iTermScriptFunctionCall *)call
               thatFailedWithError:(NSError *)error
                     connectionKey:(id)connectionKey {
    if (error.code == iTermAPIHelperFunctionCallUnregisteredErrorCode && [error.domain isEqualToString:@"com.iterm2.api"]) {
        return error;
    }
    NSString *reason = [NSString stringWithFormat:@"In call to %@: %@", call.name, error.localizedDescription];
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };
    if (error.userInfo[iTermAPIHelperFunctionCallErrorUserInfoKeyConnection]) {
        userInfo = [userInfo dictionaryBySettingObject:error.userInfo[iTermAPIHelperFunctionCallErrorUserInfoKeyConnection]
                                                forKey:iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
    } else if (connectionKey) {
        userInfo = [userInfo dictionaryBySettingObject:connectionKey
                                                forKey:iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
    }
    NSString *traceback = error.localizedFailureReason;
    if (traceback) {
        userInfo = [userInfo dictionaryBySettingObject:traceback forKey:NSLocalizedFailureReasonErrorKey];
    }

    return [NSError errorWithDomain:@"com.iterm2.call"
                               code:1
                           userInfo:userInfo];
}

@end
