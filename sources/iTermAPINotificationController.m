//
//  iTermAPINotificationController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 02/05/19.
//

#import "iTermAPINotificationController.h"

#import "DebugLogging.h"
#import "iTermBuiltInFunctions.h"
#import "iTermBuriedSessions.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Global.h"
#import "ITMRPCRegistrationRequest+Extensions.h"
#import "MovePaneController.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"

NSString *const iTermAPIHelperFunctionCallErrorUserInfoKeyConnection = @"iTermAPIHelperFunctionCallErrorUserInfoKeyConnection";
NSString *const iTermAPIRegisteredFunctionsDidChangeNotification = @"iTermAPIRegisteredFunctionsDidChangeNotification";
NSString *const iTermAPIDidRegisterSessionTitleFunctionNotification = @"iTermAPIDidRegisterSessionTitleFunctionNotification";
NSString *const iTermAPIDidRegisterStatusBarComponentNotification = @"iTermAPIDidRegisterStatusBarComponentNotification";
NSString *const iTermRemoveAPIServerSubscriptionsNotification = @"iTermRemoveAPIServerSubscriptionsNotification";

const NSInteger iTermAPIHelperFunctionCallUnregisteredErrorCode = 100;
const NSInteger iTermAPIHelperFunctionCallOtherErrorCode = 1;

@interface iTermAllSessionsSubscription : NSObject
@property (nonatomic, strong) ITMNotificationRequest *request;
@property (nonatomic, copy) NSString *connectionKey;
@end

@implementation iTermAllSessionsSubscription
@end

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
    return [self.class invocationWithName:req.name
                                 defaults:req.defaultsArray];
}

@end

@implementation iTermAPINotificationController {
    // Saves the last one to avoid sending changed notifications when nothing changed.
    ITMBroadcastDomainsChangedNotification *_lastBroadcastChangeNotification;

    // When adding a new dictionary of subscriptions update -removeAllSubscriptionsForConnectionKey: and -stop.
    NSMutableDictionary<id, ITMNotificationRequest *> *_newSessionSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_terminateSessionSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_layoutChangeSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_focusChangeSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_broadcastDomainChangeSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_profileChangeSubscriptions;
    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_appVariableSubscriptions;
    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_tabVariableSubscriptions;
    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_windowVariableSubscriptions;
    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_sessionVariableSubscriptions;
    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_allSessionVariableSubscriptions; // Will have one entry per session
    // signature -> ( connection, request )
    NSMutableDictionary<NSString *, iTermTuple<id, ITMNotificationRequest *> *> *_internalServerOriginatedRPCSubscriptions;
    NSMutableArray<iTermAllSessionsSubscription *> *_allSessionsSubscriptions;  // Has one entry per "all" subscription
    NSMutableDictionary<NSString *, iTermServerOriginatedRPCCompletionBlock> *_serverOriginatedRPCCompletionBlocks;
    // connectionKey -> RPC ID (RPC ID is key in _serverOriginatedRPCCompletionBlocks)
    // WARNING: These can exist after the block has been removed from
    // _serverOriginatedRPCCompletionBlocks if it times out.
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_outstandingRPCs;

    BOOL _layoutChanged;
}

+ (NSString *)userDefaultsKeyForNameOfScriptVendingStatusBarComponentWithID:(NSString *)uniqueID {
    return [NSString stringWithFormat:@"NoSyncScriptNameForStatusBarComponent_%@", uniqueID];
}

+ (NSString *)nameOfScriptVendingStatusBarComponentWithUniqueIdentifier:(NSString *)uniqueID {
    return [[NSUserDefaults standardUserDefaults] objectForKey:[self userDefaultsKeyForNameOfScriptVendingStatusBarComponentWithID:uniqueID]];
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
        _serverOriginatedRPCCompletionBlocks = [NSMutableDictionary dictionary];
        _outstandingRPCs = [NSMutableDictionary dictionary];
        _allSessionsSubscriptions = [NSMutableArray array];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionCreated:)
                                                     name:PTYSessionCreatedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionDidTerminate:)
                                                     name:PTYSessionTerminatedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermSessionDidChangeTabNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermTabDidChangeWindowNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermTabDidChangePositionInWindowNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermSessionBuriedStateChangeTabNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(profileDidChange:)
                                                     name:kReloadAddressBookNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidBecomeKey:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResignKey:)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(selectedTabDidChange:)
                                                     name:iTermSelectedTabDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(activeSessionDidChange:)
                                                     name:iTermSessionBecameKey
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(broadcastDomainsDidChange:)
                                                     name:iTermBroadcastDomainsDidChangeNotification
                                                   object:nil];
    }
    return self;
}

#pragma mark - APIs

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
    for (NSString *stringSignature in self.serverOriginatedRPCSubscriptions.allKeys) {
        ITMNotificationRequest *req = self.serverOriginatedRPCSubscriptions[stringSignature].secondObject;
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
    return [self.serverOriginatedRPCSubscriptions.allKeys mapWithBlock:^id(NSString *signature) {
        ITMNotificationRequest *req = self.serverOriginatedRPCSubscriptions[signature].secondObject;
        if (!req) {
            return nil;
        }
        return [[iTermSessionTitleProvider alloc] initWithNotificationRequest:req];
    }];
}

- (NSArray<ITMRPCRegistrationRequest *> *)statusBarComponentProviderRegistrationRequests {
    return [self.serverOriginatedRPCSubscriptions.allKeys mapWithBlock:^id(NSString *signature) {
        ITMNotificationRequest *req = self.serverOriginatedRPCSubscriptions[signature].secondObject;
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
    return self.serverOriginatedRPCSubscriptions[stringSignature].secondObject != nil;
}

- (void)logToConnectionHostingFunctionWithSignature:(NSString *)signatureString
                                             format:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSString *connectionKey = [self.serverOriginatedRPCSubscriptions[signatureString] firstObject];
    [self.delegate apiNotificationControllerLogToConnectionWithKey:connectionKey string:string];
}

- (void)logToConnectionHostingFunctionWithSignature:(NSString *)signatureString
                                             string:(NSString *)string {
    NSString *connectionKey = [self.serverOriginatedRPCSubscriptions[signatureString] firstObject];
    [self.delegate apiNotificationControllerLogToConnectionWithKey:connectionKey
                                                            string:string];
}

- (void)apiServerNotification:(ITMNotificationRequest *)request
                connectionKey:(NSString *)connectionKey
                      handler:(void (^)(ITMNotificationResponse *))handler {
    if (request.notificationType == ITMNotificationType_NotifyOnVariableChange) {
        handler([self handleVariableChangeNotificationRequest:request
                                                connectionKey:connectionKey]);
        return;
    }
    if (request.notificationType == ITMNotificationType_NotifyOnNewSession ||
        request.notificationType == ITMNotificationType_NotifyOnTerminateSession ||
        request.notificationType == ITMNotificationType_NotifyOnLayoutChange ||
        request.notificationType == ITMNotificationType_NotifyOnFocusChange ||
        request.notificationType == ITMNotificationType_NotifyOnServerOriginatedRpc ||
        request.notificationType == ITMNotificationType_NotifyOnBroadcastChange) {
        handler([self handleAPINotificationRequest:request
                                     connectionKey:connectionKey]);
    } else if ([request.session isEqualToString:@"all"]) {
        ITMNotificationResponse *response = [self handleSubscriptionRequestForAllSessionsFromConnectionKey:connectionKey
                                                                                                   request:request];
        handler(response);
    } else {
        PTYSession *session = [self.delegate apiNotificationControllerSessionForAPIIdentifier:request.session
                                                                        includeBuriedSessions:YES];
        if (!session) {
            ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
            response.status = ITMNotificationResponse_Status_SessionNotFound;
            handler(response);
        } else {
            handler([session handleAPINotificationRequest:request
                                            connectionKey:connectionKey]);
        }
    }
}

- (void)didCloseConnectionWithKey:(id)connectionKey {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermRemoveAPIServerSubscriptionsNotification object:connectionKey];

    // Clean up outstanding iterm2->script RPCs.
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

    [self removeAllSubscriptionsForConnectionKey:connectionKey];
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

- (NSString *)connectionKeyForRPCWithSignature:(NSString *)signature {
    return self.serverOriginatedRPCSubscriptions[signature].firstObject;
}

- (NSString *)connectionKeyForRPCWithName:(NSString *)name
                       explicitParameters:(NSDictionary<NSString *, id> *)explicitParameters
                                    scope:(iTermVariableScope *)scope
                           fullParameters:(out NSDictionary<NSString *, id> **)fullParameters {
    if ([name hasPrefix:@"iterm2."]) {
        return nil;
    }
    for (NSString *signature in self.serverOriginatedRPCSubscriptions) {
        iTermTuple<id, ITMNotificationRequest *> *tuple = self.serverOriginatedRPCSubscriptions[signature];
        ITMNotificationRequest *request = tuple.secondObject;
        if (![request.rpcRegistrationRequest.name isEqualToString:name]) {
            continue;
        }
        if ([request.rpcRegistrationRequest it_satisfiesExplicitParameters:explicitParameters
                                                                     scope:scope
                                                            fullParameters:fullParameters]) {
            return tuple.firstObject;
        }
    }
    return nil;
}

#pragma mark - Internal

- (NSDictionary<NSString *, iTermTuple<id, ITMNotificationRequest *> *> *)serverOriginatedRPCSubscriptions {
    return _internalServerOriginatedRPCSubscriptions;
}

- (void)setServerOriginatedRPCSubscriptionWithSignature:(NSString *)signatureString
                                          connectionKey:(NSString *)connectionKey
                                                request:(ITMNotificationRequest *)request {
    _internalServerOriginatedRPCSubscriptions[signatureString] = [iTermTuple tupleWithObject:connectionKey
                                                                                   andObject:request];
}

- (void)removeServerOriginatedRPCSubscriptionWithSignature:(NSString *)signatureString {
    [_internalServerOriginatedRPCSubscriptions removeObjectForKey:signatureString];
}

- (NSInteger)removeServerOriginatedRPCSubscriptionsPassingTest:(BOOL (^)(NSString *signature,
                                                                         iTermTuple<id, ITMNotificationRequest *> *tuple))block {
    return [_internalServerOriginatedRPCSubscriptions removeObjectsPassingTest:block];
}

- (void)stop {
    [_newSessionSubscriptions removeAllObjects];
    [_terminateSessionSubscriptions removeAllObjects];
    [_layoutChangeSubscriptions removeAllObjects];
    [_focusChangeSubscriptions removeAllObjects];
    [_broadcastDomainChangeSubscriptions removeAllObjects];
    [_profileChangeSubscriptions removeAllObjects];
    [_appVariableSubscriptions removeAllObjects];
    [_tabVariableSubscriptions removeAllObjects];
    [_windowVariableSubscriptions removeAllObjects];
    [_sessionVariableSubscriptions removeAllObjects];
    [_allSessionVariableSubscriptions removeAllObjects];
    [_internalServerOriginatedRPCSubscriptions removeAllObjects];
    [_allSessionsSubscriptions removeAllObjects];
    [_serverOriginatedRPCCompletionBlocks removeAllObjects];
    [_outstandingRPCs removeAllObjects];
}

#pragma mark - Private

- (void)logToConnectionWithKey:(NSString *)connectionKey
                        format:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    [self.delegate apiNotificationControllerLogToConnectionWithKey:connectionKey string:string];
}

#pragma mark Subscribing

- (void)createSubscriptionDictionariesIfNeeded {
    if (!_newSessionSubscriptions) {
        _newSessionSubscriptions = [[NSMutableDictionary alloc] init];
        _terminateSessionSubscriptions = [[NSMutableDictionary alloc] init];
        _layoutChangeSubscriptions = [[NSMutableDictionary alloc] init];
        _focusChangeSubscriptions = [[NSMutableDictionary alloc] init];
        _internalServerOriginatedRPCSubscriptions = [[NSMutableDictionary alloc] init];
        _broadcastDomainChangeSubscriptions = [[NSMutableDictionary alloc] init];
        _appVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _tabVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _windowVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _sessionVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _allSessionVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _profileChangeSubscriptions = [[NSMutableDictionary alloc] init];
    }
}

- (ITMNotificationResponse *)handleAPINotificationRequest:(ITMNotificationRequest *)request
                                            connectionKey:(NSString *)connectionKey {
    ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
    if (!request.hasSubscribe) {
        response.status = ITMNotificationResponse_Status_RequestMalformed;
        return response;
    }
    [self createSubscriptionDictionariesIfNeeded];
    NSMutableDictionary<id, ITMNotificationRequest *> *subscriptions;
    if (request.notificationType == ITMNotificationType_NotifyOnNewSession) {
        subscriptions = _newSessionSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnTerminateSession) {
        subscriptions = _terminateSessionSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnLayoutChange) {
        subscriptions = _layoutChangeSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnFocusChange) {
        subscriptions = _focusChangeSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnBroadcastChange) {
        subscriptions = _broadcastDomainChangeSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnProfileChange) {
        subscriptions = _profileChangeSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnServerOriginatedRpc) {
        if (![self rpcNotificationRequestIsValid:request connectionKey:connectionKey]) {
            XLog(@"RPC notification request invalid: %@", request);
            response.status = ITMNotificationResponse_Status_RequestMalformed;
            return response;
        }

        NSString *signatureString = request.rpcRegistrationRequest.it_stringRepresentation;
        if (request.subscribe) {
            if (self.serverOriginatedRPCSubscriptions[signatureString]) {
                response.status = ITMNotificationResponse_Status_DuplicateServerOriginatedRpc;
                return response;
            }
            [self setServerOriginatedRPCSubscriptionWithSignature:signatureString
                                                    connectionKey:connectionKey
                                                          request:request];
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIRegisteredFunctionsDidChangeNotification
                                                                object:nil];
            switch (request.rpcRegistrationRequest.role) {
                case ITMRPCRegistrationRequest_Role_SessionTitle:
                    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIDidRegisterSessionTitleFunctionNotification
                                                                        object:request.rpcRegistrationRequest.name];
                    break;
                case ITMRPCRegistrationRequest_Role_Generic:
                    break;
                case ITMRPCRegistrationRequest_Role_StatusBarComponent:
                    [self didRegisterStatusBarComponent:request.rpcRegistrationRequest.statusBarComponentAttributes
                                           onConnection:connectionKey];
                    break;
            }
        } else {
            if (!self.serverOriginatedRPCSubscriptions[signatureString] ||
                self.serverOriginatedRPCSubscriptions[signatureString].firstObject != connectionKey) {
                response.status = ITMNotificationResponse_Status_NotSubscribed;
                return response;
            }
            [self removeServerOriginatedRPCSubscriptionWithSignature:signatureString];
        }
        response.status = ITMNotificationResponse_Status_Ok;
        return response;
    } else {
        assert(false);
    }
    if (request.subscribe) {
        if (subscriptions[connectionKey]) {
            response.status = ITMNotificationResponse_Status_AlreadySubscribed;
            return response;
        }
        subscriptions[connectionKey] = request;
    } else {
        if (!subscriptions[connectionKey]) {
            response.status = ITMNotificationResponse_Status_NotSubscribed;
            return response;
        }
        [subscriptions removeObjectForKey:connectionKey];
    }

    response.status = ITMNotificationResponse_Status_Ok;
    return response;
}

- (ITMNotificationResponse *)handleSubscriptionRequestForAllSessionsFromConnectionKey:(NSString *)connectionKey
                                                                              request:(ITMNotificationRequest *)request {
    if (request.notificationType == ITMNotificationType_NotifyOnVariableChange) {
        ITMNotificationResponse *response = [self handleVariableSubscriptionRequestForAllSessionsForConnection:connectionKey
                                                                                                       request:request];
        if (response.status != ITMNotificationResponse_Status_Ok) {
            return response;
        }
    } else {
        for (PTYSession *session in [self.delegate apiNotificationControllerAllSessions]) {
            ITMNotificationResponse *response = [session handleAPINotificationRequest:request
                                                                        connectionKey:connectionKey];
            if (response.status != ITMNotificationResponse_Status_AlreadySubscribed &&
                response.status != ITMNotificationResponse_Status_NotSubscribed &&
                response.status != ITMNotificationResponse_Status_Ok) {
                return response;
            }
        }
    }

    if (request.subscribe) {
        iTermAllSessionsSubscription *sub = [[iTermAllSessionsSubscription alloc] init];
        sub.request = [request copy];
        sub.connectionKey = connectionKey;
        [_allSessionsSubscriptions addObject:sub];
    } else {
        ITMNotificationRequest *requestToRemove = [request copy];
        requestToRemove.subscribe = YES;
        const NSInteger countBefore = _allSessionsSubscriptions.count;
        [_allSessionsSubscriptions removeObjectsPassingTest:^BOOL(iTermAllSessionsSubscription *sub) {
            return [NSObject object:sub.request isEqualToObject:requestToRemove];
        }];
        const NSInteger countAfter = _allSessionsSubscriptions.count;
        if (countBefore == countAfter) {
            ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
            response.status = ITMNotificationResponse_Status_NotSubscribed;
            return response;
        }
    }
    ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
    response.status = ITMNotificationResponse_Status_Ok;
    return response;
}

- (void)removeAllSubscriptionsForConnectionKey:(id)connectionKey {
    // Remove all notification subscriptions.
    // RPCs are special.
    NSInteger rpcsRemoved = [self removeServerOriginatedRPCSubscriptionsPassingTest:
                             ^BOOL(NSString *signature,
                                   iTermTuple<id, ITMNotificationRequest *> *tuple) {
                                 return [tuple.firstObject isEqual:connectionKey];
                             }];
    [_allSessionVariableSubscriptions[connectionKey] enumerateObjectsUsingBlock:^(iTermTuple<ITMNotificationRequest *,iTermVariableReference *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        [tuple.secondObject removeAllLinks];
    }];
    NSMutableDictionary *empty = [NSMutableDictionary dictionary];
    NSArray<NSMutableDictionary<id, ITMNotificationRequest *> *> *dicts =
    @[ _newSessionSubscriptions ?: empty,
       _profileChangeSubscriptions ?: empty,
       _terminateSessionSubscriptions  ?: empty,
       _layoutChangeSubscriptions ?: empty,
       _focusChangeSubscriptions ?: empty,
       _broadcastDomainChangeSubscriptions ?: empty,
       _allSessionVariableSubscriptions ?: empty];
    [dicts enumerateObjectsUsingBlock:^(NSMutableDictionary<id,ITMNotificationRequest *> * _Nonnull dict,
                                        NSUInteger idx,
                                        BOOL * _Nonnull stop) {
        [dict removeObjectForKey:connectionKey];
    }];
    [_allSessionsSubscriptions removeObjectsPassingTest:^BOOL(iTermAllSessionsSubscription *sub) {
        return [sub.connectionKey isEqual:connectionKey];
    }];
    if (rpcsRemoved) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIRegisteredFunctionsDidChangeNotification
                                                            object:nil];
    }
}

- (BOOL)rpcNotificationRequestIsValid:(ITMNotificationRequest *)request
                        connectionKey:(NSString *)connectionKey {
    if (request.argumentsOneOfCase != ITMNotificationRequest_Arguments_OneOfCase_RpcRegistrationRequest) {
        [self logToConnectionWithKey:connectionKey format:@"Expected an RPC registration request, but got:\n%@", request];
        return NO;
    }
    NSError *error = nil;
    if (![request.rpcRegistrationRequest it_rpcRegistrationRequestValidWithError:&error]) {
        [self logToConnectionWithKey:connectionKey format:@"Malformed RPC function signature: %@", error.localizedDescription];

        return NO;
    }

    return YES;
}

#pragma mark Status Bar Components

- (void)didRegisterStatusBarComponent:(ITMRPCRegistrationRequest_StatusBarComponentAttributes *)attributes
                         onConnection:(NSString *)connectionKey {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIDidRegisterStatusBarComponentNotification
                                                        object:attributes.uniqueIdentifier];
    NSString *fullPath = [self.delegate apiNotificationControllerFullPathOfScriptWithConnectionKey:connectionKey];
    if (!fullPath) {
        return;
    }
    NSString *uniqueID = attributes.uniqueIdentifier;
    return [[NSUserDefaults standardUserDefaults] setObject:fullPath
                                                     forKey:[self.class userDefaultsKeyForNameOfScriptVendingStatusBarComponentWithID:uniqueID]];
}

#pragma mark Variables

- (BOOL)unsubscribeFromVariableChangeNotificationsForAllSessionsForConnectionKey:(NSString *)connectionKey
                                                                         request:(ITMNotificationRequest *)request {
    NSMutableArray *array = _allSessionVariableSubscriptions[connectionKey];
    NSIndexSet *indexes = [array indexesOfObjectsPassingTest:^BOOL(iTermTuple<ITMNotificationRequest *, iTermVariableReference *> * _Nonnull tuple,
                                                                   NSUInteger idx,
                                                                   BOOL * _Nonnull stop) {
        return ([NSObject object:tuple.firstObject.variableMonitorRequest isEqualToObject:request.variableMonitorRequest]);
    }];

    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL * _Nonnull stop) {
        iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *tuple = array[index];
        [tuple.secondObject removeAllLinks];
    }];
    [array removeObjectsAtIndexes:indexes];

    return indexes.count > 0;
}

- (void)subscribeToVariableChangeNotificationsForAllSessionsForConnectionKey:(NSString *)connectionKey
                                                                     request:(ITMNotificationRequest *)request {
    for (PTYSession *session in [self.delegate apiNotificationControllerAllSessions]) {
        [self monitorVariableChangesForConnectionKey:connectionKey
                                          identifier:session.guid
                                             request:request
                                       subscriptions:_allSessionVariableSubscriptions];
    }
}

- (NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *)subscriptionsForVariableChangeScope:(ITMVariableScope)scope {
    [self createSubscriptionDictionariesIfNeeded];
    switch (scope) {
        case ITMVariableScope_App:
            return _appVariableSubscriptions;
        case ITMVariableScope_Tab:
            return _tabVariableSubscriptions;
        case ITMVariableScope_Window:
            return _windowVariableSubscriptions;
        case ITMVariableScope_Session:
            return _sessionVariableSubscriptions;
    }
    return nil;
}

- (ITMNotificationResponse *)handleVariableSubscriptionRequestForAllSessionsForConnection:(NSString *)connectionKey request:(ITMNotificationRequest *)request {
    [self createSubscriptionDictionariesIfNeeded];
    if (request.subscribe) {
        [self subscribeToVariableChangeNotificationsForAllSessionsForConnectionKey:connectionKey
                                                                           request:request];
        ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
        response.status = ITMNotificationResponse_Status_Ok;
        return response;
    }

    const BOOL wasSubscribed = [self unsubscribeFromVariableChangeNotificationsForAllSessionsForConnectionKey:connectionKey
                                                                                                      request:request];
    ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
    if (wasSubscribed) {
        response.status = ITMNotificationResponse_Status_Ok;
    } else {
        response.status = ITMNotificationResponse_Status_NotSubscribed;
    }
    return response;
}

- (ITMNotificationResponse *)handleVariableChangeNotificationRequest:(ITMNotificationRequest *)request
                                                       connectionKey:(NSString *)connectionKey {
    ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
    if (!request.hasSubscribe) {
        response.status = ITMNotificationResponse_Status_RequestMalformed;
        return response;
    }

    // Handle the special case of (un)subscribing to "all" sessions.
    NSString *identifier = request.variableMonitorRequest.identifier;
    if ([identifier isEqualToString:@"all"]) {
        if (request.variableMonitorRequest.scope != ITMVariableScope_Session) {
            // TODO, I guess.
            response.status = ITMNotificationResponse_Status_InvalidIdentifier;
            return response;
        }
        return [self handleSubscriptionRequestForAllSessionsFromConnectionKey:connectionKey
                                                                      request:request];
    }

    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *subscriptions =
    [self subscriptionsForVariableChangeScope:request.variableMonitorRequest.scope];
    NSMutableArray *array = subscriptions[connectionKey];
    const NSInteger index = [array indexOfObjectPassingTest:^BOOL(iTermTuple<ITMNotificationRequest *, iTermVariableReference *> * _Nonnull tuple,
                                                                  NSUInteger idx,
                                                                  BOOL * _Nonnull stop) {
        return ([NSObject object:tuple.firstObject.variableMonitorRequest isEqualToObject:request.variableMonitorRequest]);
    }];
    if (request.subscribe) {
        if (array != nil && index != NSNotFound) {
            response.status = ITMNotificationResponse_Status_AlreadySubscribed;
            return response;
        }
        BOOL ok = [self monitorVariableChangesForConnectionKey:connectionKey
                                                    identifier:identifier
                                                       request:request
                                                 subscriptions:subscriptions];
        if (ok) {
            response.status = ITMNotificationResponse_Status_Ok;
        } else {
            response.status = ITMNotificationResponse_Status_InvalidIdentifier;
        }
        return response;
    } else {
        if (index == NSNotFound) {
            response.status = ITMNotificationResponse_Status_NotSubscribed;
            return response;
        }
        iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *tuple = array[index];
        [tuple.secondObject removeAllLinks];
        [array removeObjectAtIndex:index];
        response.status = ITMNotificationResponse_Status_Ok;
        return response;
    }
}

- (ITMNotification *)variableChangeNotificationWithScope:(ITMVariableScope)scope
                                              identifier:(NSString *)identifier
                                                    name:(NSString *)variableName
                                                newValue:(id)newValue {
    ITMNotification *notification = [[ITMNotification alloc] init];
    notification.variableChangedNotification.scope = scope;
    if (identifier != nil) {
        notification.variableChangedNotification.identifier = identifier;
    }
    notification.variableChangedNotification.name = variableName;
    notification.variableChangedNotification.jsonNewValue = [NSJSONSerialization it_jsonStringForObject:newValue];
    return notification;
}

- (iTermVariableScope *)scopeForCategory:(ITMVariableScope)category identifier:(NSString *)identifier {
    switch (category) {
        case ITMVariableScope_App:
            return [iTermVariableScope globalsScope];
        case ITMVariableScope_Tab:
            return [[self.delegate apiNotificationControllerTabWithID:identifier] variablesScope];
        case ITMVariableScope_Window: {
            PseudoTerminal *windowController = [self.delegate apiNotificationControllerWindowControllerWithID:identifier];
            iTermVariableScope *scope = windowController.scope;
            return scope;
        }
        case ITMVariableScope_Session:
            return [[self.delegate apiNotificationControllerSessionForAPIIdentifier:identifier
                                                              includeBuriedSessions:YES] variablesScope];
    }

    return nil;
}

- (void)monitorVariableChangesForConnectionKey:(NSString *)connectionKey
                                    identifier:(NSString *)identifier
                                       request:(ITMNotificationRequest *)request
                                         scope:(iTermVariableScope *)scope
                                 subscriptions:(NSMutableDictionary<id,NSMutableArray<iTermTuple<ITMNotificationRequest *,iTermVariableReference *> *> *> *)subscriptions {
    NSString *name = request.variableMonitorRequest.name;
    iTermVariableReference *ref = [[iTermVariableReference alloc] initWithPath:name
                                                                         scope:scope];
    __weak __typeof(ref) weakRef = ref;
    __weak __typeof(self) weakSelf = self;
    ref.onChangeBlock = ^{
        ITMNotification *notification = [weakSelf variableChangeNotificationWithScope:request.variableMonitorRequest.scope
                                                                           identifier:identifier
                                                                                 name:name
                                                                             newValue:weakRef.value];
        if (notification) {
            [weakSelf.delegate apiNotificationControllerPostNotification:notification
                                                           connectionKey:connectionKey];
        }
    };
    [subscriptions it_addObject:[iTermTuple tupleWithObject:request andObject:ref] toMutableArrayForKey:connectionKey];
}

- (BOOL)monitorVariableChangesForConnectionKey:(NSString *)connectionKey
                                    identifier:(NSString *)identifier
                                       request:(ITMNotificationRequest *)request
                                 subscriptions:(NSMutableDictionary<id,NSMutableArray<iTermTuple<ITMNotificationRequest *,iTermVariableReference *> *> *> *)subscriptions {
    iTermVariableScope *scope = [self scopeForCategory:request.variableMonitorRequest.scope identifier:identifier];
    if (scope == nil) {
        return NO;
    }
    [self monitorVariableChangesForConnectionKey:connectionKey
                                      identifier:identifier
                                         request:request
                                           scope:scope
                                   subscriptions:subscriptions];
    return YES;
}

#pragma mark Layout

- (void)handleLayoutChange {
    _layoutChanged = NO;
    [_layoutChangeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[ITMNotification alloc] init];
        notification.layoutChangedNotification.listSessionsResponse = [self.delegate apiNotificationControllerListSessionsResponse];
        [self.delegate apiNotificationControllerPostNotification:notification
                                                   connectionKey:key];
    }];
}

#pragma mark Focus

- (void)handleFocusChange:(ITMFocusChangedNotification *)notif {
    [_focusChangeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[ITMNotification alloc] init];
        notification.focusChangedNotification = notif;
        [self.delegate apiNotificationControllerPostNotification:notification
                                                   connectionKey:key];
    }];
}

#pragma mark Broadcast

- (void)handleBroadcastChange {
    ITMBroadcastDomainsChangedNotification *broadcastSubNotification = [[ITMBroadcastDomainsChangedNotification alloc] init];
    [self.delegate apiNotificationControllerEnumerateBroadcastDomains:^(NSArray<PTYSession *> *sessions) {
        ITMBroadcastDomain *domain = [[ITMBroadcastDomain alloc] init];
        for (PTYSession *session in sessions) {
            [domain.sessionIdsArray addObject:session.guid];
        }
        [broadcastSubNotification.broadcastDomainsArray addObject:domain];
    }];
    ITMNotification *notification = [[ITMNotification alloc] init];
    notification.broadcastDomainsChanged = broadcastSubNotification;
    if ([NSObject object:broadcastSubNotification isEqualToObject:_lastBroadcastChangeNotification]) {
        return;
    }
    _lastBroadcastChangeNotification = broadcastSubNotification;
    [_broadcastDomainChangeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        [self.delegate apiNotificationControllerPostNotification:notification
                                                   connectionKey:key];
    }];
}

#pragma mark Dispatching Server-originated RPCs

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
    for (NSString *key in self.serverOriginatedRPCSubscriptions) {
        iTermTuple<id, ITMNotificationRequest *> *sub = self.serverOriginatedRPCSubscriptions[key];
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
    iTermTuple<id, ITMNotificationRequest *> *sub = self.serverOriginatedRPCSubscriptions[signature];

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
    [self.delegate apiNotificationControllerPostNotification:notification
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

#pragma mark - Notifications

- (void)sessionCreated:(NSNotification *)notification {
    PTYSession *session = notification.object;
    for (iTermAllSessionsSubscription *sub in _allSessionsSubscriptions) {
        if (sub.request.notificationType == ITMNotificationType_NotifyOnVariableChange) {
            [self monitorVariableChangesForConnectionKey:sub.connectionKey
                                              identifier:session.guid
                                                 request:sub.request
                                                   scope:session.variablesScope
                                           subscriptions:_allSessionVariableSubscriptions];
            continue;
        }
        [session handleAPINotificationRequest:sub.request
                                connectionKey:sub.connectionKey];
    }
    [_newSessionSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[ITMNotification alloc] init];
        notification.newSessionNotification = [[ITMNewSessionNotification alloc] init];
        notification.newSessionNotification.sessionId = session.guid;
        [self.delegate apiNotificationControllerPostNotification:notification
                                                   connectionKey:key];
    }];
}

- (void)sessionDidTerminate:(NSNotification *)notification {
    PTYSession *session = notification.object;
    [_terminateSessionSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[ITMNotification alloc] init];
        notification.terminateSessionNotification = [[ITMTerminateSessionNotification alloc] init];
        notification.terminateSessionNotification.sessionId = session.guid;
        [self.delegate apiNotificationControllerPostNotification:notification
                                                   connectionKey:key];
    }];
}

- (void)layoutChanged:(NSNotification *)notification {
    if (!_layoutChanged) {
        _layoutChanged = YES;
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleLayoutChange];
        });
    }
}

- (void)profileDidChange:(NSNotification *)notification {
    NSArray<BookmarkJournalEntry *> *entries = notification.userInfo[@"array"];
    NSSet<NSString *> *guids = [NSSet setWithArray:[entries mapWithBlock:^id(BookmarkJournalEntry *entry) {
        return entry->guid;
    }]];
    for (NSString *guid in guids) {
        [_profileChangeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull request, BOOL * _Nonnull stop) {
            ITMNotification *notification = [[ITMNotification alloc] init];
            notification.profileChangedNotification = [[ITMProfileChangedNotification alloc] init];
            notification.profileChangedNotification.guid = guid;
            [self.delegate apiNotificationControllerPostNotification:notification
                                                       connectionKey:key];
        }];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    focusChange.applicationActive = YES;
    [self handleFocusChange:focusChange];
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    focusChange.applicationActive = NO;
    [self handleFocusChange:focusChange];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    NSWindow *window = notification.object;
    PseudoTerminal *term = [[iTermController sharedInstance] terminalForWindow:window];
    focusChange.window = [[ITMFocusChangedNotification_Window alloc] init];
    if (term) {
        focusChange.window.windowId = term.terminalGuid;
        focusChange.window.windowStatus = ITMFocusChangedNotification_Window_WindowStatus_TerminalWindowBecameKey;
    } else {
        term = [[iTermController sharedInstance] currentTerminal];
        if (!term) {
            // Non-terminal window became key and no terminal is current (e.g., you opened prefs).
            // Not very interesting.
            return;
        }
        focusChange.window.windowId = [term terminalGuid];
        focusChange.window.windowStatus = ITMFocusChangedNotification_Window_WindowStatus_TerminalWindowIsCurrent;
    }
    [self handleFocusChange:focusChange];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    NSWindow *window = notification.object;
    PseudoTerminal *term = [[iTermController sharedInstance] terminalForWindow:window];
    if (window && term) {
        focusChange.window = [[ITMFocusChangedNotification_Window alloc] init];
        focusChange.window.windowId = term.terminalGuid;
        focusChange.window.windowStatus = ITMFocusChangedNotification_Window_WindowStatus_TerminalWindowResignedKey;
        [self handleFocusChange:focusChange];
    }
}

- (void)selectedTabDidChange:(NSNotification *)notification {
    PTYTab *tab = notification.object;
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    focusChange.selectedTab = [@(tab.uniqueId) stringValue];
    [self handleFocusChange:focusChange];
}

- (void)activeSessionDidChange:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSNumber *changed = userInfo[@"changed"];
    if (changed && !changed.boolValue) {
        return;
    }
    PTYSession *session = notification.object;
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    focusChange.session = session.guid;
    [self handleFocusChange:focusChange];
}

- (void)broadcastDomainsDidChange:(NSNotification *)notification {
    [self handleBroadcastChange];
}

@end
