//
//  iTermScriptFunctionCall.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/18.
//

#import "iTermScriptFunctionCall.h"
#import "iTermScriptFunctionCall+Private.h"

#import "iTermAPIHelper.h"
#import "iTermBuiltInFunctions.h"
#import "iTermFunctionCallParser.h"
#import "iTermScriptHistory.h"
#import "iTermTruncatedQuotedRecognizer.h"
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
    NSMutableDictionary<NSString *, iTermScriptFunctionCall *> *_dependencies;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _parameters = [NSMutableDictionary dictionary];
        _dependencies = [NSMutableDictionary dictionary];
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
            [NSObject object:_dependencies isEqualToObject:other->_dependencies]);
}

#pragma mark - APIs

+ (void)evaluateExpression:(NSString *)expressionString
                   timeout:(NSTimeInterval)timeout
                    source:(id (^)(NSString *))source
                completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    iTermParsedExpression *parsedExpression =
        [[iTermFunctionCallParser expressionParser] parse:expressionString
                                                   source:source];
    [self evaluateParsedExpression:parsedExpression
                           timeout:timeout
                            source:source
                        completion:completion];
}

+ (void)callFunction:(NSString *)invocation
             timeout:(NSTimeInterval)timeout
              source:(id (^)(NSString *))source
          completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    iTermParsedExpression *expression = [[iTermFunctionCallParser callParser] parse:invocation
                                                                             source:source];
    if (expression.string || expression.number) {
        NSString *reason = @"Expected a function call, not a literal";
        completion(nil,
                   [NSError errorWithDomain:@"com.iterm2.call"
                                       code:3
                                   userInfo:@{ NSLocalizedDescriptionKey: reason }],
                   nil);
        return;
    }
    if (expression.error) {
        completion(nil, expression.error, nil);
        return;
    }

    [self performFunctionCall:expression.functionCall
               fromInvocation:invocation
                       source:source
                      timeout:timeout
                   completion:completion];
}

+ (void)evaluateString:(NSString *)string
               timeout:(NSTimeInterval)timeout
                source:(id (^)(NSString *))source
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
                              source:source
                          completion:
             ^(id output, NSError *error, NSSet<NSString *> *missingFuncs) {
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
    NSNumber *number = [NSNumber castFrom:jsonObject];
    if (string) {
        return string;
    } else if (number) {
        return [number stringValue];
    } else if ([NSNull castFrom:jsonObject]) {
        return @"";
    } else {
        return [NSJSONSerialization it_jsonStringForObject:jsonObject];
    }
}

+ (void)evaluateInterpolatedStringParts:(NSArray *)interpolatedStringParts
                                timeout:(NSTimeInterval)timeout
                                 source:(id (^)(NSString *))source
                             completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    dispatch_group_t group = NULL;
    __block NSError *firstError = nil;
    NSMutableArray *parts = [NSMutableArray array];
    NSMutableSet<NSString *> *missingFunctionSignatures = [NSMutableSet set];
    if (timeout > 0) {
        group = dispatch_group_create();
        dispatch_notify(group, dispatch_get_main_queue(), ^{
            completion([parts componentsJoinedByString:@""],
                       firstError,
                       missingFunctionSignatures);
        });
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
                                    source:source
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
                     if (group) {
                         dispatch_group_leave(group);
                     }
                 }
             }];
        }
    }];
    if (!group) {
        completion([parts componentsJoinedByString:@""],
                   firstError,
                   missingFunctionSignatures);
    }
}

+ (void)evaluateParsedExpression:(iTermParsedExpression *)expression
                         timeout:(NSTimeInterval)timeout
                          source:(id (^)(NSString *))source
                      completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    if (expression.string) {
        completion(expression.string, nil, nil);
        return;
    }
    if (expression.number) {
        completion([expression.number stringValue], nil, nil);
        return;
    }
    if (expression.error) {
        completion(nil, expression.error, nil);
        return;
    }
    if (expression.interpolatedStringParts) {
        [self evaluateInterpolatedStringParts:expression.interpolatedStringParts
                                      timeout:timeout
                                       source:source
                                   completion:completion];
        return;
    } else {
        assert(expression.functionCall);

        [self performFunctionCall:expression.functionCall
                   fromInvocation:expression.functionCall.description
                           source:source
                          timeout:timeout
                       completion:completion];
    }
}

#pragma mark - Function Calls

+ (void)performFunctionCall:(iTermScriptFunctionCall *)functionCall
             fromInvocation:(NSString *)invocation
                     source:(id (^)(NSString *))source
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
    [functionCall callWithSource:source synchronous:(timeout == 0) completion:^(id output, NSError *error) {
        if (timeout > 0) {
            // Not synchronous
            if (timer == nil) {
                // Already timed out
                return;
            }
            [timer invalidate];
            timer = nil;
        }
        NSSet<NSString *> *missing = nil;
        if (error.code == iTermAPIHelperFunctionCallUnregisteredErrorCode) {
            missing = [NSSet setWithObject:functionCall.signature];
        }
        completion(output, error, missing);
    }];
}

- (void)addParameterWithName:(NSString *)name value:(id)value {
    _parameters[name] = value;
    iTermScriptFunctionCall *call = [iTermScriptFunctionCall castFrom:value];
    if (call) {
        _dependencies[name] = call;
    }
}

- (void)callWithSource:(id (^)(NSString *))source
           synchronous:(BOOL)synchronous
            completion:(void (^)(id, NSError *))completion {
    if (_depError) {
        completion(nil, self->_depError);
    } else {
        dispatch_group_t group = dispatch_group_create();
        [self resolveDependenciesWithSource:source
                                synchronous:synchronous
                                      group:group];
        void (^onResolved)(void) = ^{
            if (self->_depError) {
                completion(nil, self->_depError);
                return;
            }
            if (self.isBuiltinFunction) {
                [self callBuiltinFunctionWithSource:source completion:completion];
                return;
            }
            if (synchronous) {
                // This is useful because it causes source to be called for all depended-upon
                // variables even if the function can't be executed. This makes it possible for
                // the session name controller to build up its set of dependencies.
                completion(nil, nil);
                return;
            }
            NSString *signature = iTermFunctionSignatureFromNameAndArguments(self.name,
                                                                             self->_parameters.allKeys);
            self->_connectionKey = [[[iTermAPIHelper sharedInstance] connectionKeyForRPCWithSignature:signature] copy];
            [[iTermAPIHelper sharedInstance] dispatchRPCWithName:self.name
                                                       arguments:self->_parameters
                                                      completion:completion];
        };
        if (synchronous) {
            onResolved();
        } else {
            dispatch_group_notify(group, dispatch_get_main_queue(), onResolved);
        }
    }
}

- (BOOL)isBuiltinFunction {
    return [[iTermBuiltInFunctions sharedInstance] haveFunctionWithName:_name
                                                              arguments:_parameters.allKeys];
}

- (void)callBuiltinFunctionWithSource:(id (^)(NSString *))source
                           completion:(void (^)(id, NSError *))completion {
    iTermBuiltInFunctions *bif = [iTermBuiltInFunctions sharedInstance];
    [bif callFunctionWithName:_name
                   parameters:_parameters
                       source:source
                   completion:completion];
}

- (NSError *)errorForDependentCall:(iTermScriptFunctionCall *)call thatFailedWithError:(NSError *)error {
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

- (void)resolveDependenciesWithSource:(id (^)(NSString *))source
                          synchronous:(BOOL)synchronous
                                group:(dispatch_group_t)group {
    [_dependencies enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermScriptFunctionCall * _Nonnull call, BOOL * _Nonnull stop) {
        if (self->_depError) {
            *stop = YES;
            return;
        }
        dispatch_group_enter(group);
        [call callWithSource:source synchronous:synchronous completion:^(id result, NSError *error) {
            if (error) {
                self->_depError = [self errorForDependentCall:call thatFailedWithError:error];
            } else {
                self->_parameters[key] = result;
            }
            dispatch_group_leave(group);
        }];
    }];
}

@end
