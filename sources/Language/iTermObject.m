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
                                        NSLocalizedStringWithDefaultValue(@"MethodCall.NoObjectWithID", nil, [NSBundle mainBundle], @"No object with ID %@", @"Error when no object exists for the given identifier; placeholder is the identifier"),
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
    iTermCallMethodOnObjectWithConnectionKey(object, name, args, nil, completion);
}

void iTermCallMethodByIdentifierWithConnectionKey(NSString *identifier,
                                                  NSString *name,
                                                  NSDictionary *args,
                                                  id connectionKey,
                                                  void (^completion)(id, NSError *)) {
    iTermCallMethodByIdentifierWithConnectionKeyAndCancellation(identifier, name, args, connectionKey, nil, completion);
}

void iTermCallMethodByIdentifierWithConnectionKeyAndCancellation(NSString *identifier,
                                                                 NSString *name,
                                                                 NSDictionary *args,
                                                                 id connectionKey,
                                                                 iTermScriptCallCancellation *cancellation,
                                                                 void (^completion)(id, NSError *)) {
    id<iTermObject> object = [[iTermVariablesIndex sharedInstance] variablesForKey:identifier].owner;
    if (!object) {
        completion(nil,
                   iTermMethodCallError(iTermAPIHelperErrorCodeInvalidIdentifier,
                                        NSLocalizedStringWithDefaultValue(@"MethodCall.NoObjectWithID", nil, [NSBundle mainBundle], @"No object with ID %@", @"Error when no object exists for the given identifier; placeholder is the identifier"),
                                        identifier));
        return;
    }

    iTermCallMethodOnObjectWithConnectionKeyAndCancellation(object, name, args, connectionKey, cancellation, completion);
}

void iTermCallMethodOnObjectWithConnectionKey(id<iTermObject> object,
                                              NSString *name,
                                              NSDictionary *args,
                                              id connectionKey,
                                              void (^completion)(id, NSError *)) {
    iTermCallMethodOnObjectWithConnectionKeyAndCancellation(object, name, args, connectionKey, nil, completion);
}

void iTermCallMethodOnObjectWithConnectionKeyAndCancellation(id<iTermObject> object,
                                                             NSString *name,
                                                             NSDictionary *args,
                                                             id connectionKey,
                                                             iTermScriptCallCancellation *cancellation,
                                                             void (^completion)(id, NSError *)) {
    NSString *const signature = iTermFunctionSignatureFromNamespaceAndNameAndArguments(nil, name, args.allKeys);
    iTermBuiltInMethod *const method = [object.objectMethodRegistry methodWithSignature:signature];
    if (!method) {
        completion(nil,
                   iTermMethodCallError(iTermAPIHelperErrorCodeUnregisteredFunction,
                                        NSLocalizedStringWithDefaultValue(@"MethodCall.NoMethodFound", nil, [NSBundle mainBundle], @"No method found on %1$@ with signature %2$@", @"Error when no method matches; placeholders are the object and the signature"),
                                        object,
                                        signature));
        return;
    }

    [method callWithArguments:args
                connectionKey:connectionKey
                 cancellation:cancellation
                   completion:completion];
}

