//
//  iTermObject.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/19.
//

#import "iTermObject.h"

#import "iTermAPIHelper.h"
#import "iTermBuiltInFunctions.h"
#import "iTermVariablesIndex.h"
#import "NSDictionary+iTerm.h"

NSError *iTermMethodCallError(iTermAPIHelperErrorCode code,
                              NSString *format,
                              ...) {
    va_list args;
    va_start(args, format);
    NSString *reason = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDictionary *userInfo = @{ NSLocalizedFailureReasonErrorKey: reason };
    NSError *error = [NSError errorWithDomain:iTermAPIHelperErrorDomain
                                         code:code
                                     userInfo:userInfo];
    return error;
}

void iTermCallMethodByIdentifier(NSString *identifier,
                                 NSString *name,
                                 NSDictionary *args,
                                 void (^completion)(id, NSError *)) {
    id<iTermObject> object = [[iTermVariablesIndex sharedInstance] variablesForKey:identifier].owner;
    if (!object) {
        completion(nil,
                   iTermMethodCallError(iTermAPIHelperErrorCodeInvalidIdentifier,
                                        @"No object with ID %@",
                                        identifier));
        return;
    }

    iTermCallMethodOnObject(object,
                            name,
                            args,
                            completion);
}

void iTermCallMethodOnObject(id<iTermObject> object,
                             NSString *name,
                             NSDictionary *args,
                             void (^completion)(id, NSError *)) {
    NSString *const signature = iTermFunctionSignatureFromNameAndArguments(name, args.allKeys);
    iTermBuiltInMethod *const method = [object.objectMethodRegistry methodWithSignature:signature];
    if (!method) {
        completion(nil,
                   iTermMethodCallError(iTermAPIHelperErrorCodeUnregisteredFunction,
                                        @"No method found on %@ with signature %@",
                                        object,
                                        signature));
        return;
    }

    [method callWithArguments:args completion:completion ?: ^(id result, NSError *error){}];
}

