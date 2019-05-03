//
//  iTermAPIDispatcher.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 02/05/19.
//

#import "iTermAPIDispatcher.h"

#import "DebugLogging.h"
#import "ITMRPCRegistrationRequest+Extensions.h"
#import "iTermBuiltInFunctions.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"

NSString *const iTermAPIHelperFunctionCallErrorUserInfoKeyConnection = @"iTermAPIHelperFunctionCallErrorUserInfoKeyConnection";
const NSInteger iTermAPIHelperFunctionCallUnregisteredErrorCode = 100;
const NSInteger iTermAPIHelperFunctionCallOtherErrorCode = 1;

@implementation ITMServerOriginatedRPC(Extensions)

- (NSString *)it_stringRepresentation {
    NSArray<NSString *> *argNames = [self.argumentsArray mapWithBlock:^id(ITMServerOriginatedRPC_RPCArgument *anObject) {
        return anObject.name;
    }];
    return iTermFunctionSignatureFromNameAndArguments(self.name, argNames);
}

@end

@implementation iTermSessionTitleProvider

- (instancetype)initWithNotificationRequest:(ITMNotificationRequest *)req {
    self = [super init];
    if (self) {
        if (req.rpcRegistrationRequest.role != ITMRPCRegistrationRequest_Role_SessionTitle) {
            return nil;
        }
        _invocation = [self invocationOfRegistrationRequest:req.rpcRegistrationRequest];
        if (!_invocation) {
            return nil;
        }
        _displayName = [req.rpcRegistrationRequest.sessionTitleAttributes.displayName copy];
        if (!_displayName) {
            return nil;
        }
        _uniqueIdentifier = req.rpcRegistrationRequest.sessionTitleAttributes.uniqueIdentifier;
        if (!_uniqueIdentifier) {
            return nil;
        }
    }
    return self;
}

- (NSString *)invocationOfRegistrationRequest:(ITMRPCRegistrationRequest *)req {
    return [iTermAPIDispatcher invocationWithName:req.name
                                         defaults:req.defaultsArray];
}

@end


@implementation iTermAPIDispatcher {
    // connectionKey -> RPC ID (RPC ID is key in _serverOriginatedRPCCompletionBlocks)
    // WARNING: These can exist after the block has been removed from
    // _serverOriginatedRPCCompletionBlocks if it times out.
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_outstandingRPCs;
    NSMutableDictionary<NSString *, iTermServerOriginatedRPCCompletionBlock> *_serverOriginatedRPCCompletionBlocks;
}

+ (NSString *)invocationWithName:(NSString *)name
                        defaults:(NSArray<ITMRPCRegistrationRequest_RPCArgument*> *)defaultsArray {
    NSArray<ITMRPCRegistrationRequest_RPCArgument*> *sortedDefaults =
    [defaultsArray sortedArrayUsingComparator:^NSComparisonResult(ITMRPCRegistrationRequest_RPCArgument * _Nonnull obj1,
                                                                  ITMRPCRegistrationRequest_RPCArgument * _Nonnull obj2) {
        return [obj1.name compare:obj2.name];
    }];
    NSArray<NSString *> *defaults = [sortedDefaults mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgument *def) {
        return [NSString stringWithFormat:@"%@:%@", def.name, def.path];
    }];
    defaults = [defaults sortedArrayUsingSelector:@selector(compare:)];
    return [NSString stringWithFormat:@"%@(%@)", name, [defaults componentsJoinedByString:@","]];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _outstandingRPCs = [NSMutableDictionary dictionary];
        _serverOriginatedRPCCompletionBlocks = [NSMutableDictionary dictionary];
    }
    return self;
}

// Build a proto buffer and dispatch it.
- (void)dispatchRPCWithName:(NSString *)name
                  arguments:(NSDictionary *)arguments
                 completion:(iTermServerOriginatedRPCCompletionBlock)completion {
    NSError *error = nil;
    ITMServerOriginatedRPC *rpc = [self serverOriginatedRPCWithName:name arguments:arguments error:&error];
    if (error) {
        completion(nil, error);
    }
    [self dispatchServerOriginatedRPC:rpc completion:completion];
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary {
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *result = [NSMutableDictionary dictionary];
    for (NSString *stringSignature in self.delegate.dispatcherServerOriginatedRPCSubscriptions.allKeys) {
        ITMNotificationRequest *req = self.delegate.dispatcherServerOriginatedRPCSubscriptions[stringSignature].secondObject;
        if (!req) {
            continue;
        }
        ITMRPCRegistrationRequest *sig = req.rpcRegistrationRequest;
        NSString *functionName = sig.name;
        NSArray<NSString *> *args = [sig.argumentsArray mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgumentSignature *anObject) {
            return anObject.name;
        }];
        result[functionName] = args;
    }
    return result;
}

- (NSArray<iTermSessionTitleProvider *> *)sessionTitleFunctions {
    return [self.delegate.dispatcherServerOriginatedRPCSubscriptions.allKeys mapWithBlock:^id(NSString *signature) {
        ITMNotificationRequest *req = self.delegate.dispatcherServerOriginatedRPCSubscriptions[signature].secondObject;
        if (!req) {
            return nil;
        }
        return [[iTermSessionTitleProvider alloc] initWithNotificationRequest:req];
    }];
}

- (NSArray<ITMRPCRegistrationRequest *> *)statusBarComponentProviderRegistrationRequests {
    return [self.delegate.dispatcherServerOriginatedRPCSubscriptions.allKeys mapWithBlock:^id(NSString *signature) {
        ITMNotificationRequest *req = self.delegate.dispatcherServerOriginatedRPCSubscriptions[signature].secondObject;
        if (!req) {
            return nil;
        }
        if (req.rpcRegistrationRequest.role != ITMRPCRegistrationRequest_Role_StatusBarComponent) {
            return nil;
        }
        return req.rpcRegistrationRequest;
    }];
}

- (BOOL)haveRegisteredFunctionWithSignature:(NSString *)stringSignature {
    return self.delegate.dispatcherServerOriginatedRPCSubscriptions[stringSignature].secondObject != nil;
}

- (void)logToConnectionHostingFunctionWithSignature:(NSString *)signatureString
                                             format:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSString *connectionKey = [self.delegate.dispatcherServerOriginatedRPCSubscriptions[signatureString] firstObject];
    [self.delegate dispatcherLogToConnectionWithKey:connectionKey string:string];
}

- (void)logToConnectionHostingFunctionWithSignature:(NSString *)signatureString
                                             string:(NSString *)string {
    NSString *connectionKey = [self.delegate.dispatcherServerOriginatedRPCSubscriptions[signatureString] firstObject];
    [self.delegate dispatcherLogToConnectionWithKey:connectionKey
                                             string:string];
}


#pragma mark - Private

- (NSString *)connectionKeyForRPCWithSignature:(NSString *)signature {
    return self.delegate.dispatcherServerOriginatedRPCSubscriptions[signature].firstObject;
}

- (ITMServerOriginatedRPC *)serverOriginatedRPCWithName:(NSString *)name
                                              arguments:(NSDictionary *)arguments
                                                  error:(out NSError **)error {

    ITMServerOriginatedRPC *rpc = [[ITMServerOriginatedRPC alloc] init];
    rpc.name = name;
    for (NSString *argumentName in [arguments.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        id argumentValue = arguments[argumentName];
        NSString *jsonValue;
        if ([NSNull castFrom:argumentValue]) {
            jsonValue = nil;
        } else {
            jsonValue = [NSJSONSerialization it_jsonStringForObject:argumentValue];
            if (!jsonValue) {
                NSString *reason = [NSString stringWithFormat:@"Could not JSON encode value “%@”", arguments[argumentName]];
                NSString *signature = iTermFunctionSignatureFromNameAndArguments(name,
                                                                                 arguments.allKeys);
                NSString *connectionKey = [self connectionKeyForRPCWithSignature:signature];
                NSDictionary *userinfo = @{ NSLocalizedDescriptionKey: reason };
                if (connectionKey) {
                    userinfo =
                    [userinfo dictionaryBySettingObject:connectionKey
                                                 forKey:iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
                }
                if (error) {
                    *error = [NSError errorWithDomain:@"com.iterm2.api"
                                                 code:2
                                             userInfo:userinfo];
                }

                return nil;
            }
        }
        ITMServerOriginatedRPC_RPCArgument *argument = [[ITMServerOriginatedRPC_RPCArgument alloc] init];
        argument.name = argumentName;
        if (jsonValue) {
            argument.jsonValue = jsonValue;
        }

        [rpc.argumentsArray addObject:argument];
    }
    return rpc;
}

- (NSString *)signatureOfAnyRegisteredFunctionWithName:(NSString *)name {
    for (NSString *key in self.delegate.dispatcherServerOriginatedRPCSubscriptions) {
        iTermTuple<id, ITMNotificationRequest *> *sub = self.delegate.dispatcherServerOriginatedRPCSubscriptions[key];
        ITMNotificationRequest *request = sub.secondObject;
        if ([request.rpcRegistrationRequest.name isEqual:name]) {
            return request.rpcRegistrationRequest.it_stringRepresentation;
        }
    }
    return [iTermBuiltInFunctions.sharedInstance signatureOfAnyRegisteredFunctionWithName:name];
}

// Dispatches a well-formed proto buffer or gives an error if not connected.
- (void)dispatchServerOriginatedRPC:(ITMServerOriginatedRPC *)rpc
                         completion:(iTermServerOriginatedRPCCompletionBlock)completion {
    NSString *signature = rpc.it_stringRepresentation;
    iTermTuple<id, ITMNotificationRequest *> *sub = self.delegate.dispatcherServerOriginatedRPCSubscriptions[signature];

    id connectionKey = sub.firstObject;
    if (!connectionKey) {
        NSString *reason = [NSString stringWithFormat:@"No function registered for invocation “%@”. Ensure the script is running and the function name and argument names are correct.", signature];
        NSString *bestMatch = [self signatureOfAnyRegisteredFunctionWithName:rpc.name];
        if (bestMatch) {
            reason = [reason stringByAppendingFormat:@" There is a similarly named function available with a different signature: %@", bestMatch];
        }
        completion(nil, [self rpcDispatchError:reason detail:nil unregistered:YES connectionKey:nil]);
        return;
    }

    ITMNotificationRequest *notificationRequest = sub.secondObject;
    [self dispatchRPC:rpc toHandler:notificationRequest connectionKey:connectionKey completion:completion];
}

// Constructs an error with an optional traceback in `detail`.
- (NSError *)rpcDispatchError:(NSString *)reason
                       detail:(NSString *)detail
                 unregistered:(BOOL)unregistered
                connectionKey:(NSString *)connectionKey {
    if (reason == nil) {
        reason = @"Unknown reason";
    }
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };
    if (detail) {
        userInfo = [userInfo dictionaryBySettingObject:detail forKey:NSLocalizedFailureReasonErrorKey];
    }
    if (connectionKey) {
        userInfo = [userInfo dictionaryBySettingObject:connectionKey
                                                forKey:iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
    }
    return [NSError errorWithDomain:@"com.iterm2.api"
                               code:unregistered ? iTermAPIHelperFunctionCallUnregisteredErrorCode : iTermAPIHelperFunctionCallOtherErrorCode
                           userInfo:userInfo];
}

// Dispatches an RPC, assuming connected. Registers a timeout.
- (void)dispatchRPC:(ITMServerOriginatedRPC *)rpc
          toHandler:(ITMNotificationRequest * _Nonnull)handler
      connectionKey:(NSString *)connectionKey
         completion:(iTermServerOriginatedRPCCompletionBlock)completion {
    ITMNotification *notification = [[ITMNotification alloc] init];
    notification.serverOriginatedRpcNotification.requestId = [self nextServerOriginatedRPCRequestIDWithCompletion:completion];
    NSMutableSet *outstanding = _outstandingRPCs[connectionKey];
    if (!outstanding) {
        outstanding = [NSMutableSet set];
        _outstandingRPCs[connectionKey] = outstanding;
    }
    [outstanding addObject:notification.serverOriginatedRpcNotification.requestId];
    notification.serverOriginatedRpcNotification.rpc = rpc;
    [self.delegate dispatcherPostNotification:notification
                                connectionKey:connectionKey];

    __weak __typeof(self) weakSelf = self;
    const NSTimeInterval timeoutSeconds = handler.rpcRegistrationRequest.hasTimeout ? handler.rpcRegistrationRequest.timeout : 5;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf checkForRPCTimeout:notification.serverOriginatedRpcNotification.requestId
                       connectionKey:connectionKey];
    });
}

// Calls the completion block if RPC timed out.
- (void)checkForRPCTimeout:(NSString *)requestID
             connectionKey:(NSString *)connectionKey {
    iTermServerOriginatedRPCCompletionBlock completion = _serverOriginatedRPCCompletionBlocks[requestID];
    if (!completion) {
        return;
    }

    [_serverOriginatedRPCCompletionBlocks removeObjectForKey:requestID];
    completion(nil, [self rpcDispatchError:@"Timeout"
                                    detail:nil
                              unregistered:NO
                             connectionKey:connectionKey]);
}

- (NSString *)nextServerOriginatedRPCRequestIDWithCompletion:(iTermServerOriginatedRPCCompletionBlock)completion {
    static NSInteger nextID;
    NSString *requestID = [NSString stringWithFormat:@"rpc-%@", @(nextID)];
    nextID++;
    if (completion) {
        _serverOriginatedRPCCompletionBlocks[requestID] = [completion copy];
    }
    return requestID;
}

#pragma mark - Internal

- (void)didCloseConnectionWithKey:(id)connectionKey {
    NSSet<NSString *> *requestIDs = _outstandingRPCs[connectionKey];
    [_outstandingRPCs removeObjectForKey:connectionKey];
    for (NSString *requestID in requestIDs) {
        iTermServerOriginatedRPCCompletionBlock completion = _serverOriginatedRPCCompletionBlocks[requestID];
        // completion will be nil if it already timed out
        if (completion) {
            [_serverOriginatedRPCCompletionBlocks removeObjectForKey:requestID];
            completion(nil, [self rpcDispatchError:@"Script terminated during function call"
                                            detail:nil
                                      unregistered:YES
                                     connectionKey:connectionKey]);
        }
    }
}

- (void)stop {
    [_outstandingRPCs removeAllObjects];
    [_serverOriginatedRPCCompletionBlocks removeAllObjects];
}

- (void)serverOriginatedRPCDidReceiveResponseWithResult:(ITMServerOriginatedRPCResultRequest *)result
                                          connectionKey:(NSString *)connectionKey {
    NSString *key = result.requestId;
    if (!key) {
        DLog(@"Bogus key %@", key);
        return;
    }

    iTermServerOriginatedRPCCompletionBlock block = _serverOriginatedRPCCompletionBlocks[key];
    if (!block) {
        // Could be a timeout already occurred.
        DLog(@"Key %@ doesn't match a pending RPC", key);
        return;
    }
    [_serverOriginatedRPCCompletionBlocks removeObjectForKey:key];

    id value = nil;
    NSDictionary *exception = nil;
    NSError *error = nil;

    switch (result.resultOneOfCase) {
        case ITMServerOriginatedRPCResultRequest_Result_OneOfCase_JsonValue:
            value = [NSJSONSerialization JSONObjectWithData:[result.jsonValue dataUsingEncoding:NSUTF8StringEncoding]
                                                    options:NSJSONReadingAllowFragments
                                                      error:&error];
            if (!value || error) {
                value = nil;
                exception = @{ @"reason": [NSString stringWithFormat:@"Undecodable value: %@", error.localizedDescription] };
            }
            break;

        case ITMServerOriginatedRPCResultRequest_Result_OneOfCase_JsonException:
            exception = [NSJSONSerialization JSONObjectWithData:[result.jsonException dataUsingEncoding:NSUTF8StringEncoding]
                                                        options:NSJSONReadingAllowFragments
                                                          error:&error];
            if (error) {
                exception = @{ @"reason": [NSString stringWithFormat:@"Undecodable exception: %@", error.localizedDescription] };
            } else {
                exception = [NSDictionary castFrom:exception] ?: @{ @"reason": @"Malformed exception" };
            }
            break;

        case ITMServerOriginatedRPCResultRequest_Result_OneOfCase_GPBUnsetOneOfCase:
            exception = @{ @"reason": @"Malformed result." };
            break;
    }

    if (exception) {
        block(nil, [self rpcDispatchError:exception[@"reason"]
                                   detail:exception[@"traceback"]
                             unregistered:NO
                            connectionKey:connectionKey]);
    } else {
        if ([NSNull castFrom:value]) {
            value = nil;
        }
        block(value, nil);
    }
}

@end
