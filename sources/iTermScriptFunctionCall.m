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
#import "iTermObject.h"
#import "iTermScriptHistory.h"
#import "iTermTruncatedQuotedRecognizer.h"
#import "iTermVariablesIndex.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSTimer+iTerm.h"

#import <CoreParse/CoreParse.h>

void iTermFunctionCallSplitFullyQualifiedName(NSString *fqName, NSString **namespacePtr, NSString **relativeNamePtr) {
    const NSRange range = [fqName rangeOfString:@"." options:NSBackwardsSearch];
    if (range.location == NSNotFound) {
        *namespacePtr = nil;
        *relativeNamePtr = fqName;
        return;
    }
    *namespacePtr = [fqName substringToIndex:range.location];
    *relativeNamePtr = [fqName substringFromIndex:NSMaxRange(range)];
}

@implementation iTermScriptFunctionCall {
    // Maps an argument name to a parsed expression for its value.
    NSMutableDictionary<NSString *, iTermParsedExpression *> *_argToExpression;
    NSMutableArray<iTermExpressionEvaluator *> *_evaluators;
    NSMutableSet<NSString *> *_remainingArgs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _argToExpression = [NSMutableDictionary dictionary];
        _evaluators = [NSMutableArray array];
    }
    return self;
}

- (NSString *)fullyQualifiedName {
    if (!self.namespace) {
        return self.name;
    }
    return [NSString stringWithFormat:@"%@.%@", self.namespace, self.name];
}

- (NSString *)description {
    NSString *params = [[_argToExpression.allKeys mapWithBlock:^id(NSString *name) {
        return [NSString stringWithFormat:@"%@: %@", name, self->_argToExpression[name]];
    }] componentsJoinedByString:@", "];
    NSString *value = [NSString stringWithFormat:@"%@(%@)", self.fullyQualifiedName, params];
    return [NSString stringWithFormat:@"<Func %@>", value];
}

- (NSString *)signature {
    return iTermFunctionSignatureFromNamespaceAndNameAndArguments(self.namespace,
                                                                  self.name,
                                                                  _argToExpression.allKeys);
}

- (BOOL)isEqual:(id)object {
    iTermScriptFunctionCall *other = [iTermScriptFunctionCall castFrom:object];
    if (!other) {
        return NO;
    }
    return ([NSObject object:self.fullyQualifiedName isEqualToObject:other.fullyQualifiedName] &&
            [NSObject object:_argToExpression isEqualToObject:other->_argToExpression]);
}

#pragma mark - APIs

+ (iTermParsedExpression *)callMethod:(NSString *)invocation
                             receiver:(NSString *)receiver
                              timeout:(NSTimeInterval)timeout
                           retainSelf:(BOOL)retainSelf  // YES to keep it alive until it's complete
                           completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    return [self callFunction:invocation receiver:receiver timeout:timeout scope:nil retainSelf:retainSelf completion:completion];
}

+ (iTermParsedExpression *)callFunction:(NSString *)invocation
                                timeout:(NSTimeInterval)timeout
                                  scope:(iTermVariableScope *)scope
                             retainSelf:(BOOL)retainSelf
                             completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    return [self callFunction:invocation receiver:nil timeout:timeout scope:scope retainSelf:retainSelf completion:completion];
}

+ (iTermParsedExpression *)callFunction:(NSString *)invocation
                               receiver:(NSString *)receiver
                                timeout:(NSTimeInterval)timeout
                                  scope:(iTermVariableScope *)scope
                             retainSelf:(BOOL)retainSelf
                             completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    static dispatch_once_t onceToken;
    static NSMutableArray<iTermParsedExpression *> *array;
    dispatch_once(&onceToken, ^{
        array = [NSMutableArray array];
    });
    __block BOOL complete = NO;
    __block iTermParsedExpression *expression = nil;
    expression = [self callFunction:invocation
                           receiver:receiver
                            timeout:timeout
                              scope:scope
                         completion:^(id result, NSError *error, NSSet<NSString *> *missing) {
                             completion(result, error, missing);
                             if (expression) {
                                 [array removeObject:expression];
                             }
                             complete = YES;
                         }];
    if (retainSelf && !complete) {
        [array addObject:expression];
    }
    return expression;
}

+ (iTermParsedExpression *)callFunction:(NSString *)invocation
                               receiver:(NSString *)receiver
                                timeout:(NSTimeInterval)timeout
                                  scope:(iTermVariableScope *)scope
                             completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    iTermVariableScope *placeholderScope = scope ? nil : [[iTermVariablePlaceholderScope alloc] init];
    iTermParsedExpression *expression = [[iTermExpressionParser callParser] parse:invocation
                                                                            scope:scope ?: placeholderScope];
    switch (expression.expressionType) {
        case iTermParsedExpressionTypeVariableReference:
        case iTermParsedExpressionTypeArrayLookup:
            assert(false);

        case iTermParsedExpressionTypeArrayOfValues:
        case iTermParsedExpressionTypeArrayOfExpressions:
        case iTermParsedExpressionTypeNumber:
        case iTermParsedExpressionTypeBoolean:
        case iTermParsedExpressionTypeString: {
            NSString *reason = @"Expected a function call, not a literal";
            completion(nil,
                       [NSError errorWithDomain:@"com.iterm2.call"
                                           code:3
                                       userInfo:@{ NSLocalizedDescriptionKey: reason }],
                       nil);
            return nil;
        }
        case iTermParsedExpressionTypeError:
            completion(nil, expression.error, nil);
            return nil;

        case iTermParsedExpressionTypeNil: {
            NSString *reason = @"nil not allowed";
            completion(nil,
                       [NSError errorWithDomain:@"com.iterm2.call"
                                           code:4
                                       userInfo:@{ NSLocalizedDescriptionKey: reason }],
                       nil);
            return nil;
        }
        case iTermParsedExpressionTypeFunctionCall:
            [self executeFunctionCalls:@[expression.functionCall]
                            invocation:invocation
                              receiver:receiver
                               timeout:timeout
                                 scope:scope
                            completion:completion];
            return expression;
        case iTermParsedExpressionTypeFunctionCalls:
            [self executeFunctionCalls:expression.functionCalls
                            invocation:invocation
                              receiver:receiver
                               timeout:timeout
                                 scope:scope
                            completion:completion];
            return expression;
        case iTermParsedExpressionTypeInterpolatedString: {
            NSString *reason = @"interpolated string not allowed";
            completion(nil,
                       [NSError errorWithDomain:@"com.iterm2.call"
                                           code:4
                                       userInfo:@{ NSLocalizedDescriptionKey: reason }],
                       nil);
            return nil;
        }
    }
    assert(NO);
    return nil;
}

+ (void)executeFunctionCalls:(NSArray<iTermScriptFunctionCall *> *)calls
                  invocation:(NSString *)invocation
                    receiver:(NSString *)receiver
                     timeout:(NSTimeInterval)timeout
                       scope:(iTermVariableScope *)scope
                  completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    if (calls.count == 0) {
        completion(nil, nil, nil);
        return;
    }
    iTermScriptFunctionCall *call = calls[0];
    __weak __typeof(self) weakSelf = self;
    if (receiver) {
        [call performMethodCallFromInvocation:invocation
                                     receiver:receiver
                                      timeout:timeout
                                   completion:^(id result, NSError *error, NSSet<NSString *> *missing) {
            if (error) {
                completion(nil, error, missing);
                return;
            }
            if (calls.count < 2) {
                completion(result, error, missing);
                return;
            }
            [weakSelf executeFunctionCalls:[calls subarrayFromIndex:1]
                                invocation:invocation
                                  receiver:receiver
                                   timeout:timeout
                                     scope:scope
                                completion:completion];
        }];
    } else {
        [call performFunctionCallFromInvocation:invocation
                                       receiver:nil
                                          scope:scope
                                        timeout:timeout
                                     completion:^(id result, NSError *error, NSSet<NSString *> *missing) {
            if (error) {
                completion(nil, error, missing);
                return;
            }
            if (calls.count < 2) {
                completion(result, error, missing);
                return;
            }
            [weakSelf executeFunctionCalls:[calls subarrayFromIndex:1]
                                invocation:invocation
                                  receiver:receiver
                                   timeout:timeout
                                     scope:scope
                                completion:completion];
        }];
    }
}

#pragma mark - Function Calls

- (void)performMethodCallFromInvocation:(NSString *)invocation
                               receiver:(NSString *)receiver
                                timeout:(NSTimeInterval)timeout
                             completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    id<iTermObject> object = [[iTermVariablesIndex sharedInstance] variablesForKey:receiver].owner;
    if (!object) {
        NSString *reason = [NSString stringWithFormat:@"Object with identifier “%@” not found", receiver];
        completion(nil,
                   [NSError errorWithDomain:@"com.iterm2.call"
                                       code:5
                                   userInfo:@{ NSLocalizedDescriptionKey: reason }],
                   nil);
        return;
    }
    [self performFunctionCallFromInvocation:invocation
                                   receiver:receiver
                                      scope:object.objectScope
                                    timeout:timeout
                                 completion:completion];
}

- (void)functionCallDidTimeOutAfter:(NSTimeInterval)timeout
                         invocation:(NSString *)invocation
                         completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    NSString *reason;
    if (_remainingArgs.count) {
         reason = [NSString stringWithFormat:@"Timeout (%@ sec) while evaluating invocation “%@”. The timeout occurred while evaluating the following arguments to %@: %@", @(timeout), invocation, self.fullyQualifiedName, [_remainingArgs.allObjects componentsJoinedByString:@", "]];
    } else {
        reason = [NSString stringWithFormat:@"Timeout (%@ sec) while evaluating invocation “%@”. The timeout occurred while waiting for %@ to return.",
                            @(timeout), invocation, self.name];
    }
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };
    if (self.connectionKey) {
        userInfo = [userInfo dictionaryBySettingObject:self.connectionKey
                                                forKey:iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
    }
    iTermScriptHistoryEntry *entry = [[iTermAPIHelper sharedInstance] scriptHistoryEntryForConnectionKey:self.connectionKey];
    [entry addOutput:[reason stringByAppendingString:@"\n"] completion:^{}];

    NSError *error = [NSError errorWithDomain:@"com.iterm2.call"
                                         code:2
                                     userInfo:userInfo];
    completion(nil, error, nil);
}

- (void)performFunctionCallFromInvocation:(NSString *)invocation
                                 receiver:(NSString *)receiver
                                    scope:(iTermVariableScope *)scope
                                  timeout:(NSTimeInterval)timeout
                               completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    __block NSTimer *timer = nil;
    _remainingArgs = [NSMutableSet setWithArray:_argToExpression.allKeys];
    if (timeout > 0) {
        // NOTE: The timer's block retains the completion block which is what keeps the caller
        // from being dealloc'ed when it is an iTermExpressionEvaluator.
        __weak __typeof(self) weakSelf = self;
        timer = [NSTimer it_scheduledTimerWithTimeInterval:timeout repeats:NO block:^(NSTimer * _Nonnull theTimer) {
            if (timer == nil) {
                // Shouldn't happen
                return;
            }
            timer = nil;
            [weakSelf functionCallDidTimeOutAfter:timeout
                                       invocation:invocation
                                       completion:completion];
        }];
    }
    [self callWithScope:scope
             invocation:invocation
               receiver:receiver
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
             receiver:(NSString *)receiver
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
                               [strongSelf didEvaluateParametersWithScope:scope
                                                              synchronous:synchronous
                                                          parameterValues:parameterValues
                                                                 receiver:receiver
                                                                 depError:depError
                                                                  missing:missing
                                                               completion:completion];
                               [outstandingCalls removeObject:strongSelf];
                           }];
}

- (void)didEvaluateParametersWithScope:(iTermVariableScope *)scope
                           synchronous:(BOOL)synchronous
                       parameterValues:(NSDictionary<NSString *, id> *)parameterValues
                              receiver:(NSString *)receiver
                              depError:(NSError *)depError
                               missing:(NSSet<NSString *> *)missing
                            completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    if (depError) {
        completion(nil, depError, missing);
        return;
    }
    if (receiver) {
        iTermCallMethodByIdentifier(receiver,
                                    self.fullyQualifiedName,
                                    parameterValues,
                                    ^(id object, NSError *error) {
                                        completion(object, error, nil);
                                    });
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
    iTermAPIHelper *apiHelper = [iTermAPIHelper sharedInstanceIfEnabled];
    if (apiHelper == nil) {
        NSString *const signature = [self signature];
        NSError *error = [NSError errorWithDomain:iTermAPIHelperErrorDomain
                                             code:iTermAPIHelperErrorCodeAPIDisabled
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Undefined function with signature “%@”", signature]}];
        completion(nil, error, nil);
        return;
    }
    self->_connectionKey = [[apiHelper connectionKeyForRPCWithName:self.fullyQualifiedName
                                                explicitParameters:parameterValues
                                                             scope:scope
                                                    fullParameters:&fullParameters] copy];
    [apiHelper dispatchRPCWithName:self.fullyQualifiedName
                         arguments:fullParameters
                        completion:^(id apiResult, NSError *apiError) {
                            NSSet<NSString *> *missing = nil;
                            if (apiError.code == iTermAPIHelperErrorCodeUnregisteredFunction) {
                                missing = [NSSet setWithObject:self.signature];
                            }
                            completion(apiResult, apiError, missing);
                        }];
}

- (BOOL)isBuiltinFunction {
    return [[iTermBuiltInFunctions sharedInstance] haveFunctionWithName:_name
                                                              namespace:_namespace
                                                              arguments:_argToExpression.allKeys];
}

- (void)callBuiltinFunctionWithScope:(iTermVariableScope *)scope
                     parameterValues:(NSDictionary<NSString *, id> *)parameterValues
                          completion:(void (^)(id, NSError *))completion {
    iTermBuiltInFunctions *bif = [iTermBuiltInFunctions sharedInstance];
    [bif callFunctionWithName:_name
                    namespace:_namespace
                   parameters:parameterValues
                        scope:scope
                   completion:completion];
}

- (void)didEvaluateArgument:(NSString *)key {
    [_remainingArgs removeObject:key];
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
    __weak __typeof(self) weakSelf = self;
    [_argToExpression enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermParsedExpression *_Nonnull parsedExpression, BOOL * _Nonnull stop) {
        dispatch_group_enter(group);
        [self evaluateArgumentWithParsedExpression:parsedExpression
                                        invocation:invocation
                                             scope:scope
                                       synchronous:synchronous
                                        completion:^(NSError *error, id value, NSSet<NSString *> *innerMissing) {
                                            [weakSelf didEvaluateArgument:key];
                                            [missing unionSet:innerMissing];
                                            if (error) {
                                                depError = error;
                                                *stop = YES;
                                            } else {
                                                parameterValues[key] = value ?: [NSNull null];
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
    if (error.code == iTermAPIHelperErrorCodeUnregisteredFunction && [error.domain isEqualToString:iTermAPIHelperErrorDomain]) {
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
