//
//  iTermExpressionEvaluator.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/28/19.
//

#import "iTermExpressionEvaluator.h"

#import "iTermAPIHelper.h"
#import "iTermExpressionParser.h"
#import "iTermScriptFunctionCall+Private.h"
#import "iTermScriptHistory.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@implementation iTermExpressionEvaluator {
    BOOL _hasBeenEvaluated;
    BOOL _isBeingEvaluated;
    id _value;
    iTermParsedExpression *_parsedExpression;
    iTermVariableScope *_scope;
    NSMutableArray<iTermExpressionEvaluator *> *_innerEvaluators;
    NSString *_invocation;
}

- (instancetype)initWithParsedExpression:(iTermParsedExpression *)parsedExpression
                              invocation:(NSString *)invocation
                                   scope:(iTermVariableScope *)scope {
    self = [super init];
    if (self) {
        _invocation = [invocation copy];
        _parsedExpression = parsedExpression;
        _scope = scope;
        _innerEvaluators = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithExpressionString:(NSString *)expressionString
                                   scope:(iTermVariableScope *)scope {
    iTermParsedExpression *parsedExpression =
    [[iTermExpressionParser expressionParser] parse:expressionString
                                                scope:scope];
    return [self initWithParsedExpression:parsedExpression
                               invocation:expressionString
                                    scope:scope];
}

- (instancetype)initWithInterpolatedString:(NSString *)interpolatedString scope:(iTermVariableScope *)scope {
    iTermParsedExpression *parsedExpression = [iTermExpressionParser parsedExpressionWithInterpolatedString:interpolatedString
                                                                                                        scope:scope];
    return [self initWithParsedExpression:parsedExpression
                               invocation:interpolatedString
                                    scope:scope];
}

- (id)value {
    if (_hasBeenEvaluated) {
        return _value;
    }
#if DEBUG
    assert(!_isBeingEvaluated);
#endif
    [self evaluateWithTimeout:0 completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {}];
    return _value;
}

- (void)evaluateWithTimeout:(NSTimeInterval)timeout
                 completion:(void (^)(iTermExpressionEvaluator *))completion {
    _hasBeenEvaluated = YES;
    assert(!_isBeingEvaluated);
    _isBeingEvaluated = YES;
    // NOTE: The completion block *must* retain self. When the timeout is nonzero and an async
    // function call must be made, iTermScriptFunctionCall will create an NSTimer that holds a
    // reference to the completion block. Until that timer is invalidated, it holds a reference
    // to the completion block which in turn holds a reference to self. Our callers are not
    // expected to keep references to this object.
    [self evaluateParsedExpression:_parsedExpression
                        invocation:_invocation
                       withTimeout:timeout
                        completion:^(id result, NSError *error, NSSet<NSString *> *missing) {
                            if (error) {
                                self->_value = nil;
                            } else {
                                self->_value = result;
                            }
                            self->_error = error;
                            self->_missingValues = missing;
                            self->_isBeingEvaluated = NO;
                            completion(self);
                        }];
}

- (void)evaluateSwiftyString:(NSString *)string
                 withTimeout:(NSTimeInterval)timeout
                  completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    NSMutableArray *parts = [NSMutableArray array];
    __block NSError *firstError = nil;
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet<NSString *> *missingFunctionSignatures = [NSMutableSet set];
    [string enumerateSwiftySubstrings:^(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop) {
        if (isLiteral) {
            [parts addObject:[substring it_stringByExpandingBackslashEscapedCharacters]];
        } else {
            dispatch_group_enter(group);
            [parts addObject:@""];

            iTermParsedExpression *parsedExpression =
            [[iTermExpressionParser expressionParser] parse:substring
                                                        scope:self->_scope];
            iTermExpressionEvaluator *innerEvaluator = [[iTermExpressionEvaluator alloc] initWithParsedExpression:parsedExpression
                                                                                                       invocation:string
                                                                                                            scope:self->_scope];
            [self->_innerEvaluators addObject:innerEvaluator];
            [innerEvaluator evaluateWithTimeout:timeout completion:^(iTermExpressionEvaluator *evaluator) {
                [missingFunctionSignatures unionSet:evaluator.missingValues];
                if (evaluator.error) {
                    firstError = evaluator.error;
                } else {
                    parts[index] = [self stringFromJSONObject:evaluator.value];
                }
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

- (void)evaluateParsedExpression:(iTermParsedExpression *)parsedExpression
                      invocation:(NSString *)invocation
                     withTimeout:(NSTimeInterval)timeout
                      completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    switch (parsedExpression.expressionType) {
        case iTermParsedExpressionTypeFunctionCall: {
            assert(parsedExpression.functionCall);
            [parsedExpression.functionCall performFunctionCallFromInvocation:invocation
                                                                       scope:_scope
                                                                     timeout:timeout
                                                                  completion:completion];
            return;
        }

        case iTermParsedExpressionTypeInterpolatedString: {
            [self evaluateInterpolatedStringParts:parsedExpression.interpolatedStringParts
                                       invocation:invocation
                                      withTimeout:timeout
                                       completion:completion];
            return;
        }

        case iTermParsedExpressionTypeArrayOfExpressions: {
            [self evaluateArray:parsedExpression.arrayOfExpressions
                     invocation:invocation
                    withTimeout:timeout
                     completion:completion];
            return;
        }
        case iTermParsedExpressionTypeArrayOfValues:
        case iTermParsedExpressionTypeString:
        case iTermParsedExpressionTypeNumber:
            completion(parsedExpression.object, nil, nil);
            return;

        case iTermParsedExpressionTypeError:
            completion(nil, parsedExpression.error, nil);
            return;

        case iTermParsedExpressionTypeNil:
            completion(nil, nil, nil);
            return;
    }

    NSString *reason = [NSString stringWithFormat:@"Invalid parsed expression type %@", @(parsedExpression.expressionType)];
    NSError *error = [NSError errorWithDomain:@"com.iterm2.expression-evaluator"
                                         code:2
                                     userInfo:@{ NSLocalizedDescriptionKey: reason}];
    completion(nil, error, nil);
}

- (void)evaluateInterpolatedStringParts:(NSArray<iTermParsedExpression *> *)interpolatedStringParts
                             invocation:(NSString *)invocation
                            withTimeout:(NSTimeInterval)timeout
                             completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    dispatch_group_t group = NULL;
    __block NSError *firstError = nil;
    NSMutableArray *parts = [NSMutableArray array];
    NSMutableSet<NSString *> *missingFunctionSignatures = [NSMutableSet set];
    if (timeout > 0) {
        group = dispatch_group_create();
    }
    [interpolatedStringParts enumerateObjectsUsingBlock:^(iTermParsedExpression *_Nonnull parsedExpression,
                                                          NSUInteger idx,
                                                          BOOL * _Nonnull stop) {
        [parts addObject:@""];
        iTermExpressionEvaluator *innerEvaluator = [[iTermExpressionEvaluator alloc] initWithParsedExpression:parsedExpression
                                                                                                   invocation:invocation
                                                                                                        scope:self->_scope];
        [self->_innerEvaluators addObject:innerEvaluator];
        if (group) {
            dispatch_group_enter(group);
        }
        [innerEvaluator evaluateWithTimeout:timeout completion:^(iTermExpressionEvaluator *evaluator) {
            [missingFunctionSignatures unionSet:evaluator.missingValues];
            if (evaluator.error) {
                firstError = evaluator.error;
                [self logError:evaluator.error invocation:invocation];
            } else {
                parts[idx] = [self stringFromJSONObject:evaluator.value];
            }
            if (group) {
                dispatch_group_leave(group);
            }
        }];
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

- (void)evaluateArray:(NSArray *)array
           invocation:(NSString *)invocation
          withTimeout:(NSTimeInterval)timeInterval
           completion:(void (^)(id, NSError *, NSSet<NSString *> *))completion {
    __block NSError *errorOut = nil;
    NSMutableSet<NSString *> *missing = [NSMutableSet set];
    NSMutableArray *populatedArray = [array mutableCopy];
    dispatch_group_t group = nil;
    if (timeInterval > 0) {
        group = dispatch_group_create();
    }
    [array enumerateObjectsUsingBlock:^(iTermParsedExpression *_Nonnull parsedExpression,
                                        NSUInteger idx,
                                        BOOL * _Nonnull stop) {
        iTermExpressionEvaluator *innerEvaluator = [[iTermExpressionEvaluator alloc] initWithParsedExpression:parsedExpression
                                                                                                   invocation:invocation
                                                                                                        scope:self->_scope];
        [self->_innerEvaluators addObject:innerEvaluator];
        if (group) {
            dispatch_group_enter(group);
        }
        __block BOOL alreadyRun = NO;
        [innerEvaluator evaluateWithTimeout:timeInterval completion:^(iTermExpressionEvaluator *evaluator){
            assert(!alreadyRun);
            alreadyRun = YES;
            [missing unionSet:evaluator.missingValues];
            if (evaluator.error) {
                errorOut = evaluator.error;
            } else {
                populatedArray[idx] = evaluator.value;
            }
            if (group) {
                dispatch_group_leave(group);
            }
        }];
    }];
    if (group) {
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            completion(populatedArray, errorOut, missing);
        });
    } else {
        completion(populatedArray, errorOut, missing);
    }
}

- (NSString *)stringFromJSONObject:(id)jsonObject {
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

- (void)logError:(NSError *)error invocation:(NSString *)invocation {
    NSString *message =
    [NSString stringWithFormat:@"Error evaluating expression %@: %@",
     invocation, error.localizedDescription];
    [[iTermScriptHistoryEntry globalEntry] addOutput:message];
}

@end
