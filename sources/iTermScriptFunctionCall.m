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
    NSMutableDictionary<NSString *, id> *_parameters;
    NSMutableDictionary<NSString *, iTermScriptFunctionCall *> *_dependentCalls;
    NSMutableDictionary<NSString *, NSArray *> *_dependentInterpolatedStrings;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _parameters = [NSMutableDictionary dictionary];
        _dependentCalls = [NSMutableDictionary dictionary];
        _dependentInterpolatedStrings = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)description {
    NSString *params = [[_parameters.allKeys mapWithBlock:^id(NSString *name) {
        return [NSString stringWithFormat:@"%@: %@", name, self->_parameters[name]];
    }] componentsJoinedByString:@", "];
    NSString *value = [NSString stringWithFormat:@"%@(%@)", self.name, params];
    return [NSString stringWithFormat:@"<Func %@>", value];
}

- (NSString *)signature {
    return iTermFunctionSignatureFromNameAndArguments(self.name,
                                                      _parameters.allKeys);
}

- (BOOL)isEqual:(id)object {
    iTermScriptFunctionCall *other = [iTermScriptFunctionCall castFrom:object];
    if (!other) {
        return NO;
    }
    return ([NSObject object:_depError isEqualToObject:other->_depError] &&
            [NSObject object:_parameters isEqualToObject:other->_parameters] &&
            [NSObject object:_dependentCalls isEqualToObject:other->_dependentCalls] &&
            [NSObject object:_dependentInterpolatedStrings isEqualToObject:other->_dependentInterpolatedStrings]);
}

#pragma mark - APIs

+ (void)evaluateExpression:(NSString *)expressionString
                   timeout:(NSTimeInterval)timeout
                     scope:(iTermVariableScope *)scope
                completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    iTermParsedExpression *parsedExpression =
        [[iTermFunctionCallParser expressionParser] parse:expressionString
                                                    scope:scope];
    [self evaluateParsedExpression:parsedExpression
                           timeout:timeout
                             scope:scope
                        completion:completion];
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

+ (void)evaluateString:(NSString *)string
               timeout:(NSTimeInterval)timeout
                 scope:(iTermVariableScope *)scope
            completion:(void (^)(NSString *,
                                 NSError *,
                                 NSSet<NSString *> *missingFunctionSignatures))completion {
    NSMutableArray *parts = [NSMutableArray array];
    __block NSError *firstError = nil;
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet<NSString *> *missingFunctionSignatures = [NSMutableSet set];
    [string enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        if (isLiteral) {
            [parts addObject:[substring it_stringByExpandingBackslashEscapedCharacters]];
        } else {
            dispatch_group_enter(group);
            NSInteger i = parts.count;
            [parts addObject:@""];
            [self evaluateExpression:substring
                             timeout:timeout
                               scope:scope
                          completion:
             ^(id originalOutput, NSError *error, NSSet<NSString *> *missingFuncs) {
                 id output = [self stringFromJSONObject:originalOutput];
                 if (output) {
                     parts[i] = output;
                 }
                 if (error) {
                     firstError = error;
                 }
                 [missingFunctionSignatures unionSet:missingFuncs];
                 dispatch_group_leave(group);
             }];
        }
    }];
    if (timeout == 0) {
        completion([parts componentsJoinedByString:@""],
                   firstError,
                   missingFunctionSignatures);
    } else {
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            completion([parts componentsJoinedByString:@""],
                       firstError,
                       missingFunctionSignatures);
        });
    }
}

#pragma mark - Private

+ (NSString *)stringFromJSONObject:(id)jsonObject {
    NSString *string = [NSString castFrom:jsonObject];
    if (string) {
        return string;
    }
    NSNumber *number = [NSNumber castFrom:jsonObject];
    if (number) {
        return [number stringValue];
    }
    NSArray *array = [NSArray castFrom:jsonObject];
    if (array) {
        return [NSString stringWithFormat:@"[%@]", [[array mapWithBlock:^id(id anObject) {
            return [self stringFromJSONObject:anObject];
        }] componentsJoinedByString:@", "]];
    }

    if ([NSNull castFrom:jsonObject] || !jsonObject) {
        return @"";
    }

    return [NSJSONSerialization it_jsonStringForObject:jsonObject];
}

+ (void)evaluateInterpolatedStringParts:(NSArray *)interpolatedStringParts
                                timeout:(NSTimeInterval)timeout
                                  scope:(iTermVariableScope *)scope
                             completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    dispatch_group_t group = NULL;
    __block NSError *firstError = nil;
    NSMutableArray *parts = [NSMutableArray array];
    NSMutableSet<NSString *> *missingFunctionSignatures = [NSMutableSet set];
    if (timeout > 0) {
        group = dispatch_group_create();
    }
    [interpolatedStringParts enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj isKindOfClass:[NSString class]]) {
            [parts addObject:obj];
        } else {
            NSInteger index = parts.count;
            [parts addObject:@""];
            if (group) {
                dispatch_group_enter(group);
            }
            [self evaluateParsedExpression:obj
                                   timeout:timeout
                                     scope:scope
                                completion:
             ^(id value, NSError *error, NSSet<NSString *> *missingFuncs) {
                 [missingFunctionSignatures unionSet:missingFuncs];
                 if (error) {
                     if (!firstError) {
                         firstError = error;
                     }
                     parts[index] = @"";
                     NSString *message =
                         [NSString stringWithFormat:@"Error evaluating expression %@: %@",
                      obj, error.localizedDescription];
                     [[iTermScriptHistoryEntry globalEntry] addOutput:message];
                 } else {
                     parts[index] = [self stringFromJSONObject:value];
                 }
                 if (group) {
                     dispatch_group_leave(group);
                 }
             }];
        }
    }];
    if (!group) {
        completion([parts componentsJoinedByString:@""],
                   firstError,
                   missingFunctionSignatures);
    } else {
        dispatch_notify(group, dispatch_get_main_queue(), ^{
            completion(firstError ? nil : [parts componentsJoinedByString:@""],
                       firstError,
                       missingFunctionSignatures);
        });
    }
}

+ (void)evaluateParsedExpression:(iTermParsedExpression *)expression
                         timeout:(NSTimeInterval)timeout
                           scope:(iTermVariableScope *)scope
                      completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    switch (expression.expressionType) {
        case iTermParsedExpressionTypeFunctionCall:
            [self performFunctionCall:expression.functionCall
                       fromInvocation:expression.functionCall.description
                                scope:scope
                              timeout:timeout
                           completion:completion];
            return;
        case iTermParsedExpressionTypeNil:
            assert(expression.optional);
            completion(nil, nil, nil);
            return;
        case iTermParsedExpressionTypeError:
            completion(nil, expression.error, nil);
            return;
        case iTermParsedExpressionTypeNumber:
            completion(expression.number, nil, nil);
            return;
        case iTermParsedExpressionTypeString:
            completion(expression.string, nil, nil);
            return;
        case iTermParsedExpressionTypeInterpolatedString:
            [self evaluateInterpolatedStringParts:expression.interpolatedStringParts
                                          timeout:timeout
                                            scope:scope
                                       completion:completion];
            return;
        case iTermParsedExpressionTypeArray:
            completion(expression.array, nil, nil);
            return;
    }

    ITAssertWithMessage(NO, @"Malformed expression %@", expression);
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

- (void)addParameterWithName:(NSString *)name value:(id)value {
    _parameters[name] = value;
    iTermScriptFunctionCall *call = [iTermScriptFunctionCall castFrom:value];
    if (call) {
        _dependentCalls[name] = call;
    }

    iTermParsedExpression *expression = [iTermParsedExpression castFrom:value];
    if (expression.expressionType == iTermParsedExpressionTypeInterpolatedString) {
        _dependentInterpolatedStrings[name] = expression.interpolatedStringParts;
    }
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
    [self resolveDependenciesWithScope:scope
                           synchronous:synchronous
                               missing:mutableMissing
                                 group:group];
    void (^onResolved)(NSSet<NSString *> *) = ^(NSSet<NSString *> *missing){
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
        NSString *signature = iTermFunctionSignatureFromNameAndArguments(self.name,
                                                                         self->_parameters.allKeys);
        self->_connectionKey = [[[iTermAPIHelper sharedInstance] connectionKeyForRPCWithSignature:signature] copy];
        [[iTermAPIHelper sharedInstance] dispatchRPCWithName:self.name
                                                   arguments:self->_parameters
                                                  completion:^(id apiResult, NSError *apiError) {
                                                      NSSet<NSString *> *missing = nil;
                                                      if (apiError.code == iTermAPIHelperFunctionCallUnregisteredErrorCode) {
                                                          missing = [NSSet setWithObject:self.signature];
                                                      }
                                                      completion(apiResult, apiError, missing);
                                                  }];
    };
    if (synchronous) {
        onResolved(nil);
    } else {
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            onResolved(mutableMissing);
        });
    }
}

- (BOOL)isBuiltinFunction {
    return [[iTermBuiltInFunctions sharedInstance] haveFunctionWithName:_name
                                                              arguments:_parameters.allKeys];
}

- (void)callBuiltinFunctionWithScope:(iTermVariableScope *)scope
                           completion:(void (^)(id, NSError *))completion {
    iTermBuiltInFunctions *bif = [iTermBuiltInFunctions sharedInstance];
    [bif callFunctionWithName:_name
                   parameters:_parameters
                        scope:scope
                   completion:completion];
}

- (NSError *)errorForDependentCall:(iTermScriptFunctionCall *)call thatFailedWithError:(NSError *)error {
    if (error.code == iTermAPIHelperFunctionCallUnregisteredErrorCode && [error.domain isEqualToString:@"com.iterm2.api"]) {
        return error;
    }
    NSString *reason = [NSString stringWithFormat:@"In call to %@: %@", call.name, error.localizedDescription];
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };
    if (error.userInfo[iTermAPIHelperFunctionCallErrorUserInfoKeyConnection]) {
        userInfo = [userInfo dictionaryBySettingObject:error.userInfo[iTermAPIHelperFunctionCallErrorUserInfoKeyConnection]
                                                forKey:iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
    } else if (_connectionKey) {
        userInfo = [userInfo dictionaryBySettingObject:_connectionKey
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

- (void)resolveDependenciesWithScope:(iTermVariableScope *)scope
                          synchronous:(BOOL)synchronous
                             missing:(NSMutableSet<NSString *> *)missing
                                group:(dispatch_group_t)group {
    [_dependentCalls enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermScriptFunctionCall * _Nonnull call, BOOL * _Nonnull stop) {
        if (self->_depError) {
            *stop = YES;
            return;
        }
        dispatch_group_enter(group);
        [call callWithScope:scope synchronous:synchronous completion:^(id result, NSError *error, NSSet<NSString *> *innerMissing) {
            [missing unionSet:innerMissing];
            if (error) {
                self->_depError = [self errorForDependentCall:call thatFailedWithError:error];
            } else {
                self->_parameters[key] = result;
            }
            dispatch_group_leave(group);
        }];
    }];
    [_dependentInterpolatedStrings enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSArray * _Nonnull interpolatedStringParts, BOOL * _Nonnull stop) {
        if (self->_depError) {
            *stop = YES;
            return;
        }
        dispatch_group_enter(group);
        [iTermScriptFunctionCall evaluateInterpolatedStringParts:interpolatedStringParts
                                                         timeout:synchronous ? 0 : INFINITY
                                                           scope:scope
                                                      completion:^(id result, NSError *error, NSSet<NSString *> *innerMissing) {
                                                          [missing unionSet:innerMissing];
                                                          if (error) {
                                                              self->_depError = error;
                                                          } else {
                                                              self->_parameters[key] = result;
                                                          }
                                                          dispatch_group_leave(group);
                                                      }];
    }];
}

@end
