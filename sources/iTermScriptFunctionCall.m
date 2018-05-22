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
    iTermScriptFunctionCall *call = [[[iTermFunctionCallParser alloc] init] parse:invocation
                                                                           source:source];
    [call callWithCompletion:completion];
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

- (void)resolveDependenciesWithGroup:(dispatch_group_t)group {
    [_dependencies enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermScriptFunctionCall * _Nonnull call, BOOL * _Nonnull stop) {
        if (self.error) {
            *stop = YES;
            return;
        }
        dispatch_group_enter(group);
        [call callWithCompletion:^(id result, NSError *error) {
            if (error) {
                NSString *reason = [NSString stringWithFormat:@"In call to %@: %@", call.name, error.localizedDescription];
                NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };

                NSString *traceback = error.localizedFailureReason;
                if (traceback) {
                    userInfo = [userInfo dictionaryBySettingObject:traceback forKey:NSLocalizedFailureReasonErrorKey];
                }

                self.error = [NSError errorWithDomain:@"com.iterm2.call"
                                                 code:1
                                             userInfo:userInfo];
            } else {
                self->_parameters[key] = result;
            }
            dispatch_group_leave(group);
        }];
    }];
}

@end
