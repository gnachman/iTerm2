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
#import "iTermExpressionParser.h"
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
    // Maps an argument name to a parsed expression for its value.
    NSMutableDictionary<NSString *, iTermParsedExpression *> *_argToExpression;
    NSMutableArray<iTermExpressionEvaluator *> *_evaluators;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _argToExpression = [NSMutableDictionary dictionary];
        _evaluators = [NSMutableArray array];
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
    return ([NSObject object:self.name isEqualToObject:other.name] &&
            [NSObject object:_argToExpression isEqualToObject:other->_argToExpression]);
}

#pragma mark - APIs

+ (void)callFunction:(NSString *)invocation
             timeout:(NSTimeInterval)timeout
               scope:(iTermVariableScope *)scope
          completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    iTermParsedExpression *expression = [[iTermExpressionParser callParser] parse:invocation
                                                                              scope:scope];
    switch (expression.expressionType) {
        case iTermParsedExpressionTypeArrayOfValues:
        case iTermParsedExpressionTypeArrayOfExpressions:
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
            assert(expression.functionCall);
            [expression.functionCall performFunctionCallFromInvocation:invocation
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

#pragma mark - Function Calls

- (void)performFunctionCallFromInvocation:(NSString *)invocation
                                    scope:(iTermVariableScope *)scope
                                  timeout:(NSTimeInterval)timeout
                               completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    __block NSTimer *timer = nil;
    if (timeout > 0) {
        // NOTE: The timer's block retains the completion block which is what keeps the caller
        // from being dealloc'ed when it is an iTermExpressionEvaluator.
        timer = [NSTimer it_scheduledTimerWithTimeInterval:timeout repeats:NO block:^(NSTimer * _Nonnull theTimer) {
            if (timer == nil) {
                // Shouldn't happen
                return;
            }
            timer = nil;
            NSString *reason = [NSString stringWithFormat:@"Timeout (%@ sec) waiting for %@", @(timeout), invocation];
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };
            if (self.connectionKey) {
                userInfo = [userInfo dictionaryBySettingObject:self.connectionKey
                                                        forKey:iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
            }
            NSError *error = [NSError errorWithDomain:@"com.iterm2.call"
                                                 code:2
                                             userInfo:userInfo];
            completion(nil, error, nil);
        }];
    }
    [self callWithScope:scope
             invocation:invocation
            synchronous:(timeout == 0)
             completion:
     ^(id output, NSError *error, NSSet<NSString *> *missing) {
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
           invocation:(NSString *)invocation
          synchronous:(BOOL)synchronous
           completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    static NSMutableArray<iTermScriptFunctionCall *> *outstandingCalls;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        outstandingCalls = [NSMutableArray array];
    });
    [outstandingCalls addObject:self];

    __weak __typeof(self) weakSelf = self;

    [self evaluateParametersWithScope:scope
                           invocation:invocation
                          synchronous:synchronous
                           completion:^(NSDictionary<NSString *, id> *parameterValues,
                                        NSError *depError,
                                        NSSet<NSString *> *missing) {
                               __strong __typeof(self) strongSelf = weakSelf;
                               if (!strongSelf) {
                                   return;
                               }
                               [weakSelf didEvaluateParametersWithScope:scope
                                                            synchronous:synchronous
                                                        parameterValues:parameterValues
                                                               depError:depError
                                                                missing:missing
                                                             completion:completion];
                               [outstandingCalls removeObject:strongSelf];
                           }];
}

- (void)didEvaluateParametersWithScope:(iTermVariableScope *)scope
                           synchronous:(BOOL)synchronous
                       parameterValues:(NSDictionary<NSString *, id> *)parameterValues
                              depError:(NSError *)depError
                               missing:(NSSet<NSString *> *)missing
                            completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    if (depError) {
        completion(nil, depError, missing);
        return;
    }
    if (self.isBuiltinFunction) {
        [self callBuiltinFunctionWithScope:scope
                           parameterValues:parameterValues
                                completion:^(id object, NSError *error) {
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

    // Fill in any default values not expliciltly specified.
    NSDictionary<NSString *, id> *fullParameters = nil;
    self->_connectionKey = [[[iTermAPIHelper sharedInstance] connectionKeyForRPCWithName:self.name
                                                                      explicitParameters:parameterValues
                                                                                   scope:scope
                                                                          fullParameters:&fullParameters] copy];
    [[iTermAPIHelper sharedInstance] dispatchRPCWithName:self.name
                                               arguments:fullParameters
                                              completion:^(id apiResult, NSError *apiError) {
                                                  NSSet<NSString *> *missing = nil;
                                                  if (apiError.code == iTermAPIHelperFunctionCallUnregisteredErrorCode) {
                                                      missing = [NSSet setWithObject:self.signature];
                                                  }
                                                  completion(apiResult, apiError, missing);
                                              }];
}

- (BOOL)isBuiltinFunction {
    return [[iTermBuiltInFunctions sharedInstance] haveFunctionWithName:_name
                                                              arguments:_argToExpression.allKeys];
}

- (void)callBuiltinFunctionWithScope:(iTermVariableScope *)scope
                     parameterValues:(NSDictionary<NSString *, id> *)parameterValues
                           completion:(void (^)(id, NSError *))completion {
    iTermBuiltInFunctions *bif = [iTermBuiltInFunctions sharedInstance];
    [bif callFunctionWithName:_name
                   parameters:parameterValues
                        scope:scope
                   completion:completion];
}

- (void)evaluateParametersWithScope:(iTermVariableScope *)scope
                         invocation:(NSString *)invocation
                        synchronous:(BOOL)synchronous
                         completion:(void (^)(NSDictionary<NSString *, id> *parameterValues,
                                              NSError *depError,
                                              NSSet<NSString *> *missing))completion {
    dispatch_group_t group = dispatch_group_create();
    NSMutableDictionary<NSString *, id> *parameterValues = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *missing = [NSMutableSet set];
    __block NSError *depError = nil;
    [_argToExpression enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermParsedExpression *_Nonnull parsedExpression, BOOL * _Nonnull stop) {
        dispatch_group_enter(group);
        [self evaluateArgumentWithParsedExpression:parsedExpression
                                        invocation:invocation
                                             scope:scope
                                       synchronous:synchronous
                                        completion:^(NSError *error, id value, NSSet<NSString *> *innerMissing) {
                                            [missing unionSet:innerMissing];
                                            if (error) {
                                                depError = error;
                                                *stop = YES;
                                            } else {
                                                parameterValues[key] = value;
                                            }
                                            dispatch_group_leave(group);
                                        }];
    }];
    if (synchronous) {
        completion(parameterValues, depError, missing);
        return;
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        completion(parameterValues, depError, missing);
    });
}

- (void)evaluateArgumentWithParsedExpression:(iTermParsedExpression *)parsedExpression
                                  invocation:(NSString *)invocation
                                       scope:(iTermVariableScope *)scope
                                 synchronous:(BOOL)synchronous
                                  completion:(void (^)(NSError *error, id value, NSSet<NSString *> *missing))completion {
    iTermExpressionEvaluator *parameterEvaluator = [[iTermExpressionEvaluator alloc] initWithParsedExpression:parsedExpression
                                                                                                   invocation:invocation
                                                                                                        scope:scope];
    [self->_evaluators addObject:parameterEvaluator];
    [parameterEvaluator evaluateWithTimeout:synchronous ? 0 : INFINITY completion:^(iTermExpressionEvaluator *evaluator) {
        if (!evaluator.error) {
            completion(nil, evaluator.value, evaluator.missingValues);
            return;
        }

        NSError *error = nil;
        if (parsedExpression.expressionType == iTermParsedExpressionTypeFunctionCall) {
            error = [self errorForDependentCall:parsedExpression.functionCall
                            thatFailedWithError:evaluator.error
                                  connectionKey:self->_connectionKey];
        } else {
            error = evaluator.error;
        }
        completion(error, nil, evaluator.missingValues);
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
