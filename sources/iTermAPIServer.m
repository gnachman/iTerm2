//
//  iTermAPIServer.m
//  iTerm2
//
//  Created by George Nachman on 11/3/16.
//
//

#import "iTermAPIServer.h"

#import "Api.pbobjc.h"
#import "DebugLogging.h"
#import "iTermHTTPConnection.h"
#import "iTermLSOF.h"
#import "iTermWebSocketConnection.h"
#import "iTermWebSocketFrame.h"
#import "iTermSocket.h"
#import "iTermIPV4Address.h"
#import "iTermSocketIPV4Address.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import <objc/runtime.h>

#import <Cocoa/Cocoa.h>

NSString *const iTermAPIServerDidReceiveMessage = @"iTermAPIServerDidReceiveMessage";
NSString *const iTermAPIServerWillSendMessage = @"iTermAPIServerWillSendMessage";
NSString *const iTermAPIServerConnectionRejected = @"iTermAPIServerConnectionRejected";
NSString *const iTermAPIServerConnectionAccepted = @"iTermAPIServerConnectionAccepted";
NSString *const iTermAPIServerConnectionClosed = @"iTermAPIServerConnectionClosed";

// State shared between main thread and execution thread for a
// mainthread-blocking iTerm2-to-script RPC.
@interface iTermBlockingRPC : NSObject
@property (atomic, strong) dispatch_group_t group;
@property (atomic, strong) NSString *rpcID;
@property (atomic, strong) NSError *error;
@property (atomic, strong) ITMServerOriginatedRPCResultRequest *result;
@end

@implementation iTermBlockingRPC
@end

@interface iTermAPIServer()<iTermWebSocketConnectionDelegate>
@end

@interface iTermAPIRequest : NSObject
@property (nonatomic, weak) iTermWebSocketConnection *connection;
@property (nonatomic) ITMClientOriginatedMessage *request;
@end

@implementation iTermAPIRequest
@end

@interface iTermAPITransaction : NSObject
@property (nonatomic, weak) iTermWebSocketConnection *connection;

- (void)wait;
- (void)signal;

// Enqueue a request. You normally call -signal after this.
- (void)addRequest:(iTermAPIRequest *)request;

// Dequeue a request. You normally call -wait before this.
- (iTermAPIRequest *)dequeueRequestFromAnyConnection:(BOOL)anyConnection;
@end

@implementation iTermAPITransaction {
    NSMutableArray<iTermAPIRequest *> *_requests;
    NSInteger _base;
    dispatch_semaphore_t _sema;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sema = dispatch_semaphore_create(0);
        _requests = [NSMutableArray array];
    }
    return self;
}

- (void)wait {
    dispatch_semaphore_wait(_sema, DISPATCH_TIME_FOREVER);
}

- (void)signal {
    dispatch_semaphore_signal(_sema);
}

- (void)addRequest:(iTermAPIRequest *)request {
    @synchronized(self) {
        [_requests addObject:request];
    }
}

- (iTermAPIRequest *)dequeueRequestFromAnyConnection:(BOOL)anyConnection {
    @synchronized(self) {
        if (anyConnection) {
            iTermAPIRequest *request = _requests.firstObject;
            if (request) {
                [_requests removeObjectAtIndex:0];
            }
            return request;
        } else {
            while (_requests.count > _base) {
                iTermAPIRequest *request = _requests[_base];
                if (request.connection == self.connection) {
                    [_requests removeObjectAtIndex:_base];
                    return request;
                }
                _base++;
            }
            return nil;
        }
    }
}

@end

@interface iTermAPIServer()
@property (atomic) iTermAPITransaction *transaction;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (atomic, strong) iTermBlockingRPC *blockingRPC;  // _executionQueue
@end

@implementation iTermAPIServer {
    iTermSocket *_socket;
    NSMutableDictionary<id, iTermWebSocketConnection *> *_connections;  // _queue
    dispatch_queue_t _executionQueue;
}

+ (instancetype)sharedInstance {
    static id instance;
    @synchronized (self) {
        if (!instance) {
            instance = [[self alloc] init];
        }
    }
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _connections = [[NSMutableDictionary alloc] init];
        _socket = [iTermSocket tcpIPV4Socket];
        if (!_socket) {
            XLog(@"Failed to create socket");
            return nil;
        }
        _queue = dispatch_queue_create("com.iterm2.apisockets", NULL);
        _executionQueue = dispatch_queue_create("com.iterm2.apiexec", DISPATCH_QUEUE_SERIAL);

        [_socket setReuseAddr:YES];
        iTermIPV4Address *loopback = [[iTermIPV4Address alloc] initWithLoopback];
        iTermSocketAddress *socketAddress = [iTermSocketAddress socketAddressWithIPV4Address:loopback
                                                                                        port:1912];
        if (![_socket bindToAddress:socketAddress]) {
            XLog(@"Failed to bind");
            return nil;
        }

        BOOL ok = [_socket listenWithBacklog:5 accept:^(int fd, iTermSocketAddress *clientAddress) {
            [self didAcceptConnectionOnFileDescriptor:fd fromAddress:clientAddress];
        }];
        if (!ok) {
            XLog(@"Failed to listen");
            return nil;
        }
    }
    return self;
}

- (void)postAPINotification:(ITMNotification *)notification toConnectionKey:(NSString *)connectionKey {
    dispatch_async(_queue, ^{
        iTermWebSocketConnection *webSocketConnection = self->_connections[connectionKey];
        if (webSocketConnection) {
            ITMServerOriginatedMessage *response = [[ITMServerOriginatedMessage alloc] init];
            response.notification = notification;
            dispatch_async(self->_executionQueue, ^{
                [self sendResponse:response onConnection:webSocketConnection];
            });
        }
    });
}

- (NSString *)websocketKeyForConnectionKey:(NSString *)connectionKey {
    __block NSString *result = nil;
    dispatch_sync(_queue, ^{
        result = self->_connections[connectionKey].key;
    });
    return result;

}
- (void)didAcceptConnectionOnFileDescriptor:(int)fd fromAddress:(iTermSocketAddress *)address {
    DLog(@"Accepted connection");
    dispatch_queue_t queue = _queue;
    dispatch_async(queue, ^{
        iTermHTTPConnection *connection = [[iTermHTTPConnection alloc] initWithFileDescriptor:fd clientAddress:address];

        pid_t pid = [iTermLSOF processIDWithConnectionFromAddress:address];
        if (pid == -1) {
            XLog(@"Reject connection from unidentifiable process with address %@", address);
            dispatch_async(connection.queue, ^{
                [connection unauthorized];
            });
            return;
        }

        [self startRequestOnConnection:connection pid:pid completion:^(BOOL ok, NSString *reason) {
            if (!ok) {
                XLog(@"Reject unauthenticated process (pid %d): %@", pid, reason);
                dispatch_async(connection.queue, ^{
                    [connection unauthorized];
                });
            }
        }];
    });
}

// _queue
- (void)startRequestOnConnection:(iTermHTTPConnection *)connection pid:(int)pid completion:(void (^)(BOOL, NSString *))completion {
    dispatch_async(connection.queue, ^{
        NSURLRequest *request = [connection readRequest];
        dispatch_async(self->_queue, ^{
            [self reallyStartRequestOnConnection:connection pid:pid request:request completion:completion];
        });
    });
}

// queue
// completion called on queue
- (void)reallyStartRequestOnConnection:(iTermHTTPConnection *)connection
                                   pid:(int)pid
                               request:(NSURLRequest *)request
                            completion:(void (^)(BOOL, NSString *))completion {
    if (!request) {
        dispatch_async(connection.queue, ^{
            [connection badRequest];
        });
        completion(NO, @"Failed to read request from HTTP connection");
        return;
    }
    if (![request.URL.path isEqualToString:@"/"]) {
        dispatch_async(connection.queue, ^{
            [connection badRequest];
        });
        completion(NO, [NSString stringWithFormat:@"Path %@ not known", request.URL.path]);
        return;
    }
    NSString *authReason = nil;
    iTermWebSocketConnection *webSocketConnection = [iTermWebSocketConnection newWebSocketConnectionForRequest:request
                                                                                                    connection:connection
                                                                                                        reason:&authReason];
    if (webSocketConnection) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *reason = nil;
            NSString *displayName = nil;
            NSDictionary *identity = [self.delegate apiServerAuthorizeProcess:pid
                                                                preauthorized:webSocketConnection.preauthorized
                                                                       reason:&reason
                                                                  displayName:&displayName];
            if (identity) {
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIServerConnectionAccepted
                                                                    object:webSocketConnection.key
                                                                  userInfo:@{ @"reason": reason ?: [NSNull null],
                                                                              @"job": displayName ?: [NSNull null],
                                                                              @"pid": @(pid),
                                                                              @"websocket": webSocketConnection }];
                dispatch_async(self->_queue, ^{
                    DLog(@"Upgrading request to websocket");
                    webSocketConnection.displayName = displayName;
                    webSocketConnection.peerIdentity = identity;
                    webSocketConnection.delegate = self;
                    webSocketConnection.delegateQueue = self->_queue;
                    self->_connections[webSocketConnection.guid] = webSocketConnection;
                    [webSocketConnection handleRequest:request completion:^{
                        dispatch_async(self->_queue, ^{
                            completion(YES, nil);
                        });
                    }];
                });
            } else {
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIServerConnectionRejected
                                                                    object:request.allHTTPHeaderFields[@"x-iterm2-key"]
                                                                  userInfo:@{ @"reason": reason ?: @"Unknown reason",
                                                                              @"job": displayName ?: [NSNull null],
                                                                              @"pid": @(pid) }];
                dispatch_async(connection.queue, ^{
                    [connection unauthorized];
                });
                dispatch_async(self->_queue, ^{
                    completion(NO, reason);
                });
            }
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIServerConnectionRejected
                                                                object:request.allHTTPHeaderFields[@"x-iterm2-key"]
                                                              userInfo:@{ @"reason": authReason ?: @"Unknown reason",
                                                                          @"pid": @(pid) }];
        });
        dispatch_async(connection.queue, ^{
            [connection badRequest];
        });
        completion(NO, authReason);
    }
}

// queue
- (void)sendResponse:(ITMServerOriginatedMessage *)response onConnection:(iTermWebSocketConnection *)webSocketConnection {
    DLog(@"Sending response %@", response);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIServerWillSendMessage
                                                            object:webSocketConnection.key
                                                          userInfo:@{ @"message": response }];
    });
    [webSocketConnection sendBinary:[response data] completion:nil];
}

#pragma mark - Transactions

// Runs on execution queue
- (void)dispatchRequestWhileNotInTransaction:(ITMClientOriginatedMessage *)request
                                  connection:(iTermWebSocketConnection *)webSocketConnection {
    NSAssert(!self.transaction, @"Already in a transaction");

    __weak __typeof(self) weakSelf = self;
    if (request.submessageOneOfCase == ITMClientOriginatedMessage_Submessage_OneOfCase_TransactionRequest) {
        ITMServerOriginatedMessage *response = [self newResponseForRequest:request];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIServerDidReceiveMessage
                                                                object:webSocketConnection.key
                                                              userInfo:@{ @"request": request }];
        });
        if (!request.transactionRequest.begin) {
            dispatch_async(dispatch_get_main_queue(), ^{
                response.transactionResponse = [[ITMTransactionResponse alloc] init];
                response.transactionResponse.status = ITMTransactionResponse_Status_NoTransaction;
                [weakSelf sendResponse:response onConnection:webSocketConnection];
            });
            return;
        }

        iTermAPITransaction *transaction = [[iTermAPITransaction alloc] init];
        transaction.connection = webSocketConnection;
        self.transaction = transaction;

        // Enter the main queue before sending the transaction response. This guarantees the main
        // thread doesn't do anything after that response is sent.
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_async(self->_queue, ^{
                response.transactionResponse = [[ITMTransactionResponse alloc] init];
                response.transactionResponse.status = ITMTransactionResponse_Status_Ok;
                [weakSelf sendResponse:response onConnection:webSocketConnection];
            });
            [weakSelf drainTransaction:transaction];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf dispatchRequest:request connection:webSocketConnection];
        });
    }
}

// Runs on main queue and blocks it during a transaction.
- (void)drainTransaction:(iTermAPITransaction *)transaction {
    while (1) {
        [transaction wait];
        if (self.transaction != transaction) {
            // Connection must have been terminated.
            break;
        }
        iTermAPIRequest *transactionRequest = [transaction dequeueRequestFromAnyConnection:NO];

        if (transactionRequest.request.submessageOneOfCase == ITMClientOriginatedMessage_Submessage_OneOfCase_TransactionRequest &&
            !transactionRequest.request.transactionRequest.begin) {
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIServerDidReceiveMessage
                                                                object:transactionRequest.connection.key
                                                              userInfo:@{ @"request": transactionRequest.request }];
            // End the transaction by request.
            ITMServerOriginatedMessage *response = [self newResponseForRequest:transactionRequest.request];
            response.transactionResponse = [[ITMTransactionResponse alloc] init];
            response.transactionResponse.status = ITMTransactionResponse_Status_Ok;
            dispatch_async(_queue, ^{
                [self sendResponse:response onConnection:transactionRequest.connection];
            });
            break;
        }

        [self dispatchRequest:transactionRequest.request
                   connection:transactionRequest.connection];
    }
    dispatch_async(_executionQueue, ^{
        if (self.transaction == transaction) {
            self.transaction = nil;
        }
        iTermAPIRequest *apiRequest = [transaction dequeueRequestFromAnyConnection:YES];
        while (apiRequest) {
            if (apiRequest.connection) {
                [self enqueueOrDispatchRequest:apiRequest.request onConnection:apiRequest.connection];
            }
            apiRequest = [transaction dequeueRequestFromAnyConnection:YES];
        }
    });
}

#pragma mark - Handle incoming RPCs

- (void)finishHandlingRequestWithResponse:(ITMServerOriginatedMessage *)response
                             onConnection:(iTermWebSocketConnection *)webSocketConnection {
    dispatch_async(self.queue, ^{
        [self sendResponse:response onConnection:webSocketConnection];
    });
}

- (ITMServerOriginatedMessage *)newResponseForRequest:(ITMClientOriginatedMessage *)request {
    ITMServerOriginatedMessage *response = [[ITMServerOriginatedMessage alloc] init];
    response.id_p = request.id_p;
    return response;
}

- (void)handleTransactionRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];
    response.transactionResponse = [[ITMTransactionResponse alloc] init];
    response.transactionResponse.status = ITMTransactionResponse_Status_AlreadyInTransaction;
    [self finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
}

- (void)handleGetBufferRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerGetBuffer:request.getBufferRequest
                          handler:^(ITMGetBufferResponse *getBufferResponse) {
                              assert(!handled);
                              handled = YES;
                              response.getBufferResponse = getBufferResponse;
                              [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
                          }];
}

- (void)handleGetPromptRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerGetPrompt:request.getPromptRequest handler:^(ITMGetPromptResponse *getPromptResponse) {
        assert(!handled);
        handled = YES;
        response.getPromptResponse = getPromptResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleNotificationRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerNotification:request.notificationRequest
                       connectionKey:webSocketConnection.guid
                             handler:^(ITMNotificationResponse *notificationResponse) {
                                 assert(!handled);
                                 handled = YES;
                                 response.notificationResponse = notificationResponse;
                                 [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
                             }];
}

- (void)handleRegisterToolRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerRegisterTool:request.registerToolRequest
                        peerIdentity:webSocketConnection.peerIdentity
                             handler:^(ITMRegisterToolResponse *registerToolResponse) {
                                 assert(!handled);
                                 handled = YES;
                                 response.registerToolResponse = registerToolResponse;
                                 [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
                             }];
}

- (void)handleSetProfilePropertyRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerSetProfileProperty:request.setProfilePropertyRequest
                                   handler:^(ITMSetProfilePropertyResponse *setProfilePropertyResponse) {
                                       assert(!handled);
                                       handled = YES;
                                       response.setProfilePropertyResponse = setProfilePropertyResponse;
                                       [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
                                   }];
}

- (void)handleGetProfilePropertyRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerGetProfileProperty:request.getProfilePropertyRequest
                                   handler:^(ITMGetProfilePropertyResponse *getProfilePropertyResponse) {
                                       assert(!handled);
                                       handled = YES;
                                       response.getProfilePropertyResponse = getProfilePropertyResponse;
                                       [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
                                   }];
}

- (void)handleListSessionsRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerListSessions:request.listSessionsRequest
                             handler:^(ITMListSessionsResponse *listSessionsResponse) {
                                 assert(!handled);
                                 handled = YES;
                                 response.listSessionsResponse = listSessionsResponse;
                                 [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
                             }];
}

- (void)handleSendTextRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerSendText:request.sendTextRequest handler:^(ITMSendTextResponse *sendTextResponse) {
        assert(!handled);
        handled = YES;
        response.sendTextResponse = sendTextResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleCreateTabRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerCreateTab:request.createTabRequest handler:^(ITMCreateTabResponse *createTabResponse) {
        assert(!handled);
        handled = YES;
        response.createTabResponse = createTabResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleSplitPaneRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerSplitPane:request.splitPaneRequest handler:^(ITMSplitPaneResponse *splitPaneResponse) {
        assert(!handled);
        handled = YES;
        response.splitPaneResponse = splitPaneResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleSetPropertyRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerSetProperty:request.setPropertyRequest handler:^(ITMSetPropertyResponse *setPropertyResponse) {
        assert(!handled);
        handled = YES;
        response.setPropertyResponse = setPropertyResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleGetPropertyRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerGetProperty:request.getPropertyRequest handler:^(ITMGetPropertyResponse *getPropertyResponse) {
        assert(!handled);
        handled = YES;
        response.getPropertyResponse = getPropertyResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleInjectRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerInject:request.injectRequest handler:^(ITMInjectResponse *injectResponse) {
        assert(!handled);
        handled = YES;
        response.injectResponse = injectResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleActivateRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerActivate:request.activateRequest handler:^(ITMActivateResponse *activateResponse) {
        assert(!handled);
        handled = YES;
        response.activateResponse = activateResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleVariableRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerVariable:request.variableRequest handler:^(ITMVariableResponse *variableResponse) {
        assert(!handled);
        handled = YES;
        response.variableResponse = variableResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleSavedArrangementRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerSavedArrangement:request.savedArrangementRequest handler:^(ITMSavedArrangementResponse *savedArrangementResponse) {
        assert(!handled);
        handled = YES;
        response.savedArrangementResponse = savedArrangementResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleFocusRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerFocus:request.focusRequest handler:^(ITMFocusResponse *focusResponse) {
        assert(!handled);
        handled = YES;
        response.focusResponse = focusResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleListProfilesRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerListProfiles:request.listProfilesRequest handler:^(ITMListProfilesResponse *listProfilesResponse) {
        assert(!handled);
        handled = YES;
        response.listProfilesResponse = listProfilesResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleServerOriginatedRpcResultRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerServerOriginatedRPCResult:request.serverOriginatedRpcResultRequest
                                    connectionKey:webSocketConnection.key
                                          handler:^(ITMServerOriginatedRPCResultResponse *listProfilesResponse) {
                                              assert(!handled);
                                              handled = YES;
        response.serverOriginatedRpcResultResponse = listProfilesResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

// Runs on execution queue
- (BOOL)tryHandleResponse:(ITMClientOriginatedMessage *)request
            toBlockingRPC:(iTermBlockingRPC *)blockingRPC
               connection:(iTermWebSocketConnection *)webSocketConnection {
    if (!blockingRPC) {
        return NO;
    }
    if (![blockingRPC.rpcID isEqualToString:request.serverOriginatedRpcResultRequest.requestId]) {
        return NO;
    }
    blockingRPC.result = request.serverOriginatedRpcResultRequest;
    dispatch_group_leave(blockingRPC.group);

    // Send a response to unblock the script
    ITMServerOriginatedMessage *response = [[ITMServerOriginatedMessage alloc] init];
    response.id_p = request.id_p;
    [self finishHandlingRequestWithResponse:response onConnection:webSocketConnection];

    return YES;
}

- (void)handleMalformedRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];
    response.error = @"Invalid request. Upgrade iTerm2 to a newer version.";
    [self finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
}

- (void)handleUnhandleableRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];
    response.error = @"Not ready. This is a bug! Please report it at https://iterm2.com/bugs";
    [self finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
}

- (void)handleRestartSessionRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerRestartSession:request.restartSessionRequest handler:^(ITMRestartSessionResponse *restartSessionResponse) {
        assert(!handled);
        handled = YES;
        response.restartSessionResponse = restartSessionResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleMenuItemRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerMenuItem:request.menuItemRequest handler:^(ITMMenuItemResponse *menuItemResponse) {
        assert(!handled);
        handled = YES;
        response.menuItemResponse = menuItemResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleSetTabLayoutRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerSetTabLayout:request.setTabLayoutRequest handler:^(ITMSetTabLayoutResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.setTabLayoutResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleGetBroadcastDomainsRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerGetBroadcastDomains:request.getBroadcastDomainsRequest handler:^(ITMGetBroadcastDomainsResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.getBroadcastDomainsResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleTmuxRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerTmuxRequest:request.tmuxRequest handler:^(ITMTmuxResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.tmuxResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleReorderTabsRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];
    
    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerReorderTabsRequest:request.reorderTabsRequest handler:^(ITMReorderTabsResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.reorderTabsResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handlePreferencesRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerPreferencesRequest:request.preferencesRequest handler:^(ITMPreferencesResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.preferencesResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleColorPresetRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerColorPresetRequest:request.colorPresetRequest handler:^(ITMColorPresetResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.colorPresetResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleSelectionRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerSelectionRequest:request.selectionRequest handler:^(ITMSelectionResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.selectionResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleStatusBarComponentRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerStatusBarComponentRequest:request.statusBarComponentRequest handler:^(ITMStatusBarComponentResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.statusBarComponentResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleSetBroadcastDomainsRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerSetBroadcastDomainsRequest:request.setBroadcastDomainsRequest handler:^(ITMSetBroadcastDomainsResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.setBroadcastDomainsResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleCloseRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerCloseRequest:request.closeRequest handler:^(ITMCloseResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.closeResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}

- (void)handleInvokeFunctionRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    ITMServerOriginatedMessage *response = [self newResponseForRequest:request];

    __block BOOL handled = NO;
    __weak __typeof(self) weakSelf = self;
    [_delegate apiServerInvokeFunctionRequest:request.invokeFunctionRequest handler:^(ITMInvokeFunctionResponse *theResponse) {
        assert(!handled);
        handled = YES;
        response.invokeFunctionResponse = theResponse;
        [weakSelf finishHandlingRequestWithResponse:response onConnection:webSocketConnection];
    }];
}


// Runs on main queue, either in or not in a transaction.
- (void)dispatchRequest:(ITMClientOriginatedMessage *)request connection:(iTermWebSocketConnection *)webSocketConnection {
    DLog(@"Got request %@", request);
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIServerDidReceiveMessage
                                                        object:webSocketConnection.key
                                                      userInfo:@{ @"request": request }];
    if (!_delegate) {
        [self handleUnhandleableRequest:request connection:webSocketConnection];
        return;
    }

    switch (request.submessageOneOfCase) {
        case ITMClientOriginatedMessage_Submessage_OneOfCase_TransactionRequest:
            if (request.transactionRequest.begin) {
                [self handleTransactionRequest:request connection:webSocketConnection];
            }
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_GetBufferRequest:
            [self handleGetBufferRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_GetPromptRequest:
            [self handleGetPromptRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_NotificationRequest:
            [self handleNotificationRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_RegisterToolRequest:
            [self handleRegisterToolRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_SetProfilePropertyRequest:
            [self handleSetProfilePropertyRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_GetProfilePropertyRequest:
            [self handleGetProfilePropertyRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_ListSessionsRequest:
            [self handleListSessionsRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_SendTextRequest:
            [self handleSendTextRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_CreateTabRequest:
            [self handleCreateTabRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_SplitPaneRequest:
            [self handleSplitPaneRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_SetPropertyRequest:
            [self handleSetPropertyRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_GetPropertyRequest:
            [self handleGetPropertyRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_InjectRequest:
            [self handleInjectRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_ActivateRequest:
            [self handleActivateRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_VariableRequest:
            [self handleVariableRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_SavedArrangementRequest:
            [self handleSavedArrangementRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_FocusRequest:
            [self handleFocusRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_ListProfilesRequest:
            [self handleListProfilesRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_ServerOriginatedRpcResultRequest:
            [self handleServerOriginatedRpcResultRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_GPBUnsetOneOfCase:
            [self handleMalformedRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_RestartSessionRequest:
            [self handleRestartSessionRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_MenuItemRequest:
            [self handleMenuItemRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_SetTabLayoutRequest:
            [self handleSetTabLayoutRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_GetBroadcastDomainsRequest:
            [self handleGetBroadcastDomainsRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_TmuxRequest:
            [self handleTmuxRequest:request connection:webSocketConnection];
            break;
            
        case ITMClientOriginatedMessage_Submessage_OneOfCase_ReorderTabsRequest:
            [self handleReorderTabsRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_PreferencesRequest:
            [self handlePreferencesRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_ColorPresetRequest:
            [self handleColorPresetRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_SelectionRequest:
            [self handleSelectionRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_StatusBarComponentRequest:
            [self handleStatusBarComponentRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_SetBroadcastDomainsRequest:
            [self handleSetBroadcastDomainsRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_CloseRequest:
            [self handleCloseRequest:request connection:webSocketConnection];
            break;

        case ITMClientOriginatedMessage_Submessage_OneOfCase_InvokeFunctionRequest:
            [self handleInvokeFunctionRequest:request connection:webSocketConnection];
            break;
    }
}

// Runs on execution queue.
- (void)addRequestToTransaction:(iTermAPIRequest *)apiRequest {
    if (apiRequest.connection == self.transaction.connection) {
        [self.transaction addRequest:apiRequest];
        [self.transaction signal];
    } else {
        [self.transaction addRequest:apiRequest];
    }
}

// Runs on execution queue
- (void)enqueueOrDispatchRequest:(ITMClientOriginatedMessage *)request onConnection:(iTermWebSocketConnection *)webSocketConnection {
    if (self.transaction) {
        iTermAPIRequest *apiRequest = [[iTermAPIRequest alloc] init];
        apiRequest.connection = webSocketConnection;
        apiRequest.request = request;
        [self addRequestToTransaction:apiRequest];
        return;
    }

    if ([self tryHandleResponse:request toBlockingRPC:self.blockingRPC connection:webSocketConnection]) {
        return;
    }

    [self dispatchRequestWhileNotInTransaction:request connection:webSocketConnection];
}

#pragma mark - iTermWebSocketConnectionDelegate

// _queue
- (void)webSocketConnectionDidTerminate:(iTermWebSocketConnection *)webSocketConnection {
    DLog(@"Connection terminated");
    [self->_connections removeObjectForKey:webSocketConnection.guid];
    dispatch_async(self->_executionQueue, ^{
        if (self.transaction.connection == webSocketConnection) {
            iTermAPITransaction *transaction = self.transaction;
            self.transaction = nil;
            [transaction signal];
        }
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_delegate apiServerDidCloseConnectionWithKey:webSocketConnection.guid];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIServerConnectionClosed
                                                                object:webSocketConnection.key];
        });
    });
}

// _queue
- (void)webSocketConnection:(iTermWebSocketConnection *)webSocketConnection didReadFrame:(iTermWebSocketFrame *)frame {
    if (frame.opcode == iTermWebSocketOpcodeBinary) {
        ITMClientOriginatedMessage *request = [ITMClientOriginatedMessage parseFromData:frame.payload error:nil];
        DLog(@"Dispatch %@", request);
        if (request) {
            DLog(@"Received request: %@", request);
            __weak __typeof(self) weakSelf = self;
            dispatch_async(_executionQueue, ^{
                [weakSelf enqueueOrDispatchRequest:request onConnection:webSocketConnection];
            });
        }
    }
    DLog(@"Got a frame: %@", frame);
}

@end

