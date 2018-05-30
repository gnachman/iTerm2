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

#import <CoreParse/CoreParse.h>

@implementation iTermScriptFunctionCall {
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
              source:(id (^)(NSString *))source
          completion:(void (^)(id, NSError *))completion {
    iTermScriptFunctionCall *call = [[iTermFunctionCallParser sharedInstance] parse:invocation
                                                                             source:source];
    [call callWithCompletion:completion];
}

+ (id)synchronousCallFunction:(NSString *)invocation
                      timeout:(NSTimeInterval)timeout
                        error:(NSError **)error
                       source:(id (^)(NSString *))source {
    iTermScriptFunctionCall *call = [[iTermFunctionCallParser sharedInstance] parse:invocation
                                                                             source:source];
    return [call synchronousCallWithDeadline:[NSDate dateWithTimeIntervalSinceNow:timeout]
                                       error:error];
}

- (void)addParameterWithName:(NSString *)name value:(id)value {
    _parameters[name] = value;
    iTermScriptFunctionCall *call = [iTermScriptFunctionCall castFrom:value];
    if (call) {
        _dependencies[name] = call;
    }
}

- (void)callWithCompletion:(void (^)(id, NSError *))completion {
    if (self.error) {
        completion(nil, self.error);
    } else {
        dispatch_group_t group = dispatch_group_create();
        [self resolveDependenciesWithGroup:group];
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (self.error) {
                completion(nil, self.error);
                return;
            }
            [[iTermAPIHelper sharedInstance] dispatchRPCWithName:self.name
                                                       arguments:self->_parameters
                                                      completion:completion];
        });
    }
}

- (id)synchronousCallWithDeadline:(NSDate *)deadline error:(out NSError **)error {
    if (self.error) {
        *error = self.error;
        return nil;
    }

    [self synchronousResolveDependenciesWithDeadline:deadline error:error];
    if (*error) {
        return nil;
    }

    return [[iTermAPIHelper sharedInstance] synchronousDispatchRPCWithName:self.name
                                                                 arguments:self->_parameters
                                                                   timeout:deadline.timeIntervalSinceNow
                                                                     error:error];
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
        if (self.error) {
            *stop = YES;
            return;
        }
        dispatch_group_enter(group);
        [call callWithCompletion:^(id result, NSError *error) {
            if (error) {
                self.error = [self errorForDependentCall:call thatFailedWithError:error];
            } else {
                self->_parameters[key] = result;
            }
            dispatch_group_leave(group);
        }];
    }];
}

- (void)synchronousResolveDependenciesWithDeadline:(NSDate *)deadline error:(out NSError **)error {
    for (NSString *key in _dependencies) {
        iTermScriptFunctionCall *call = _dependencies[key];
        NSError *innerError = nil;
        id result = [call synchronousCallWithDeadline:deadline error:&innerError];
        if (innerError) {
            *error = [self errorForDependentCall:call thatFailedWithError:innerError];
            return;
        } else {
            self->_parameters[key] = result;
        }
    }
}

@end
