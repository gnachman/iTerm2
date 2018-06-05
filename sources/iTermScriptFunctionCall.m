//
//  iTermScriptFunctionCall.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/18.
//

#import "iTermScriptFunctionCall.h"
#import "iTermScriptFunctionCall+Private.h"

#import "iTermAPIHelper.h"
#import "iTermFunctionCallParser.h"
#import "iTermTruncatedQuotedRecognizer.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
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

+ (void)callFunction:(NSString *)invocation
             timeout:(NSTimeInterval)timeout
              source:(id (^)(NSString *))source
          completion:(void (^)(id, NSError *))completion {
    iTermParsedExpression *expression = [[iTermFunctionCallParser sharedInstance] parse:invocation
                                                                                 source:source];
    if (expression.string || expression.number) {
        NSString *reason = @"Expected a function call, not a literal";
        completion(nil, [NSError errorWithDomain:@"com.iterm2.call"
                                            code:3
                                        userInfo:@{ NSLocalizedDescriptionKey: reason }]);
        return;
    }
    if (expression.error) {
        completion(nil, expression.error);
        return;
    }

    [self performFunctionCall:expression.functionCall
               fromInvocation:invocation
                      timeout:timeout
                   completion:completion];
}

+ (void)evaluateExpression:(NSString *)invocation
                   timeout:(NSTimeInterval)timeout
                    source:(id (^)(NSString *))source
                completion:(void (^)(id, NSError *))completion {
    iTermParsedExpression *expression = [[iTermFunctionCallParser sharedInstance] parse:invocation
                                                                                 source:source];
    if (expression.string) {
        completion(expression.string, nil);
        return;
    }
    if (expression.number) {
        completion([expression.number stringValue], nil);
        return;
    }
    if (expression.error) {
        completion(nil, expression.error);
        return;
    }
    assert(expression.functionCall);

    [self performFunctionCall:expression.functionCall
               fromInvocation:invocation
                      timeout:timeout
                   completion:completion];
}

+ (void)performFunctionCall:(iTermScriptFunctionCall *)functionCall
             fromInvocation:(NSString *)invocation
                    timeout:(NSTimeInterval)timeout
                 completion:(void (^)(id, NSError *))completion {
    __block NSTimer *timer;
    timer = [NSTimer it_scheduledTimerWithTimeInterval:timeout repeats:NO block:^(NSTimer * _Nonnull theTimer) {
        if (timer == nil) {
            // Shouldn't happen
            return;
        }
        timer = nil;
        NSString *reason = [NSString stringWithFormat:@"Timeout (%@ sec) waiting for %@", @(timeout), invocation];
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };
        NSError *error = [NSError errorWithDomain:@"com.iterm2.call"
                                             code:2
                                         userInfo:userInfo];
        completion(nil, error);
    }];
    [functionCall callWithCompletion:^(id output, NSError *error) {
        if (timer == nil) {
            // Already timed out
            return;
        }
        [timer invalidate];
        timer = nil;
        completion(output, error);
    }];
}

+ (void)evaluateString:(NSString *)string
               timeout:(NSTimeInterval)timeout
                source:(id (^)(NSString *))source
            completion:(void (^)(NSString *, NSError *))completion {
    NSMutableArray *parts = [NSMutableArray array];
    __block NSError *firstError = nil;
    dispatch_group_t group = dispatch_group_create();
    [string enumerateSwiftySubstrings:^(NSString *substring, BOOL isLiteral) {
        if (isLiteral) {
            [parts addObject:substring];
        } else {
            dispatch_group_enter(group);
            NSInteger i = parts.count;
            [parts addObject:[NSNull null]];
            [self evaluateExpression:substring timeout:timeout source:source completion:^(id output, NSError *error) {
                if (output) {
                    parts[i] = output;
                } else {
                    parts[i] = @"";
                }
                if (error) {
                    firstError = error;
                }
                dispatch_group_leave(group);
            }];
        }
    }];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        completion([parts componentsJoinedByString:@""],
                   firstError);
    });
}

- (void)addParameterWithName:(NSString *)name value:(id)value {
    _parameters[name] = value;
    iTermScriptFunctionCall *call = [iTermScriptFunctionCall castFrom:value];
    if (call) {
        _dependencies[name] = call;
    }
}

- (void)callWithCompletion:(void (^)(id, NSError *))completion {
    if (_depError) {
        completion(nil, self->_depError);
    } else {
        dispatch_group_t group = dispatch_group_create();
        [self resolveDependenciesWithGroup:group];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (self->_depError) {
                completion(nil, self->_depError);
                return;
            }
            [[iTermAPIHelper sharedInstance] dispatchRPCWithName:self.name
                                                       arguments:self->_parameters
                                                      completion:completion];
        });
    }
}

- (NSError *)errorForDependentCall:(iTermScriptFunctionCall *)call thatFailedWithError:(NSError *)error {
    NSString *reason = [NSString stringWithFormat:@"In call to %@: %@", call.name, error.localizedDescription];
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };

    NSString *traceback = error.localizedFailureReason;
    if (traceback) {
        userInfo = [userInfo dictionaryBySettingObject:traceback forKey:NSLocalizedFailureReasonErrorKey];
    }

    return [NSError errorWithDomain:@"com.iterm2.call"
                               code:1
                           userInfo:userInfo];
}

- (void)resolveDependenciesWithGroup:(dispatch_group_t)group {
    [_dependencies enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermScriptFunctionCall * _Nonnull call, BOOL * _Nonnull stop) {
        if (self->_depError) {
            *stop = YES;
            return;
        }
        dispatch_group_enter(group);
        [call callWithCompletion:^(id result, NSError *error) {
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
