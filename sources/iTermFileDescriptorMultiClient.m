//
//  iTermFileDescriptorMultiClient.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/9/19.
//

#import "iTermFileDescriptorMultiClient.h"
#import "iTermFileDescriptorMultiClient+MRR.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermClientServerProtocolMessageBox.h"
#import "iTermFileDescriptorMultiClientState.h"
#import "iTermFileDescriptorServer.h"
#import "iTermMalloc.h"
#import "iTermMultiServerMessage.h"
#import "iTermMultiServerMessageBuilder.h"
#import "iTermNotificationController.h"
#import "iTermProcessCache.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermResult.h"
#import "iTermThreadSafety.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"

#include <syslog.h>
#include <sys/un.h>

NSString *const iTermFileDescriptorMultiClientErrorDomain = @"iTermFileDescriptorMultiClientErrorDomain";

@implementation iTermFileDescriptorMultiClient {
    NSString *_socketPath;  // Thread safe because this is only assigned to in -initWithPath:
    iTermThread<iTermFileDescriptorMultiClientState *> *_thread;
}

#pragma mark - NSObject

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _socketPath = [path copy];
        _thread = [iTermThread withLabel:@"com.iterm2.multi-client"
                            stateFactory:^iTermSynchronizedState * _Nullable(dispatch_queue_t  _Nonnull queue) {
            return [[iTermFileDescriptorMultiClientState alloc] initWithQueue:queue];
        }];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass([self class]),
            self, _socketPath];
}

#pragma mark - APIs

- (pid_t)serverPID {
    __block pid_t pid;
    [_thread dispatchSync:^(iTermFileDescriptorMultiClientState * _Nullable state) {
        pid = state.serverPID;
    }];
    return pid;
}

- (void)attachToOrLaunchNewDaemonWithCallback:(iTermCallback<id, NSNumber *> *)callback {
    [_thread dispatchAsync:^(iTermFileDescriptorMultiClientState * _Nonnull state) {
        [self attachToOrLaunchNewDaemonServerWithState:state
                                              callback:callback];
    }];
}

// Connect on the unix domain socket. Send a handshake request. Read initial
// child reports. Start the read-dispatch loop. Then run the callback.
- (void)attachWithCallback:(iTermCallback<id, NSNumber *> *)callback {
    iTermThread<iTermFileDescriptorMultiClientState *> *thread = _thread;
    [_thread dispatchAsync:^(iTermFileDescriptorMultiClientState *state) {
        [self tryAttachWithState:state callback:[thread newCallbackWithBlock:
                                                 ^(iTermFileDescriptorMultiClientState *_Nonnull state,
                                                   NSNumber *_Nullable value) {
            const iTermFileDescriptorMultiClientAttachStatus status = value.unsignedIntegerValue;
            if (status != iTermFileDescriptorMultiClientAttachStatusSuccess) {
                [callback invokeWithObject:@NO];
                return;
            }
            [self handshakeWithState:state callback:callback];
        }]];
    }];
}

// These C pointers live until the callback is run.
- (void)launchChildWithExecutablePath:(const char *)path
                                 argv:(const char **)argv
                          environment:(const char **)environment
                                  pwd:(const char *)pwd
                             ttyState:(iTermTTYState)ttyState
                             callback:(iTermMultiClientLaunchCallback *)callback {
    DLog(@"begin");
    [_thread dispatchSync:^(iTermFileDescriptorMultiClientState * _Nullable state) {
        DLog(@"dispatched");
        [self launchChildWithExecutablePath:path
                                       argv:argv
                                environment:environment
                                        pwd:pwd
                                   ttyState:ttyState
                                      state:state
                                   callback:callback];
    }];
}

// Callable from any thread.
- (void)waitForChild:(iTermFileDescriptorMultiClientChild *)child
  removePreemptively:(BOOL)removePreemptively
            callback:(iTermCallback<id, iTermResult<NSNumber *> *> *)callback {
    [_thread dispatchAsync:^(iTermFileDescriptorMultiClientState * _Nullable state) {
        [self waitForChild:child
        removePreemptively:removePreemptively
                     state:state
                  callback:callback];
    }];
}

#pragma mark - Attach

// Connect on the unix domain socket. If successful, handshake and start read-dispatch
// loop and run callback. Otherwise, launch a server, handshake, start the read-dispatch
// loop, and then run the callback.
- (void)attachToOrLaunchNewDaemonServerWithState:(iTermFileDescriptorMultiClientState *)state
                                        callback:(iTermCallback<id, NSNumber *> *)callback {
    [state check];
    __weak __typeof(self) weakSelf = self;
    [self tryAttachWithState:state callback:[_thread newCallbackWithBlock:
                                             ^(iTermFileDescriptorMultiClientState *_Nonnull state,
                                               NSNumber *_Nullable statusNumber) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            [callback invokeWithObject:@(iTermFileDescriptorMultiClientAttachStatusFatalError)];
            return;
        }
        [strongSelf didAttachWithState:state status:statusNumber.integerValue callback:callback];
    }]];
}

- (void)didAttachWithState:(iTermFileDescriptorMultiClientState *)state
                    status:(iTermFileDescriptorMultiClientAttachStatus)status
                  callback:(iTermCallback<id, NSNumber *> *)callback {
    switch (status) {
        case iTermFileDescriptorMultiClientAttachStatusInProgress:
        case iTermFileDescriptorMultiClientAttachStatusSuccess:
            DLog(@"Attached to %@. Will handshake.", _socketPath);
            [self handshakeWithState:state callback:callback];
            return;

        case iTermFileDescriptorMultiClientAttachStatusConnectFailed:
            DLog(@"Connection failed to %@. Will launch..", _socketPath);
            [self launchNewDaemonAndHandshakeWithState:state callback:callback];
            return;

        case iTermFileDescriptorMultiClientAttachStatusFatalError:
            DLog(@"Fatal error attaching to %@.", _socketPath);
            assert(state.readFD < 0);
            if (state.writeFD >= 0) {
                close(state.writeFD);
                state.writeFD = -1;
            }
            [callback invokeWithObject:@NO];
            return;
    }
}

// Connect to the unix domain socket. Read the hello message. Then run the callback.
// NOTE: Sets _readFD and_writeFD as a side-effect.
// Result will be @(enum iTermFileDescriptorMultiClientAttachStatus).
- (void)tryAttachWithState:(iTermFileDescriptorMultiClientState *)state
                  callback:(iTermCallback<id, NSNumber *> *)callback {
    DLog(@"tryAttachWithState(%@): Try attach", _socketPath);
    [state check];
    assert(state.readFD < 0);

    // Connect to the socket. This gets us the reading file descriptor.
    int temp = -1;
    iTermFileDescriptorMultiClientAttachStatus status =
    iTermConnectToUnixDomainSocket(_socketPath,
                                   &temp,
                                   0 /* async */);
    state.readFD = temp;
    if (status != iTermFileDescriptorMultiClientAttachStatusSuccess) {
        // Server dead or already connected.
        DLog(@"tryAttachWithState(%@): Server dead or already connected", _socketPath);
        [callback invokeWithObject:@(status)];
        return;
    }

    // Receive the file descriptor to write to.
    // TODO: why? Unix domain sockets are bidirectional.
    __weak __typeof(self) weakSelf = self;
    [self readMessageWithState:state callback:[_thread newCallbackWithBlock:
                                               ^(iTermFileDescriptorMultiClientState *_Nonnull state,
                                                 iTermResult<iTermClientServerProtocolMessageBox *> *_Nullable result) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            [callback invokeWithObject:@(iTermFileDescriptorMultiClientAttachStatusFatalError)];
            return;
        }

        __block BOOL ok = NO;
        [result handleObject:^(iTermClientServerProtocolMessageBox * _Nonnull messageBox) {
            if (messageBox.message.fileDescriptor) {
                state.writeFD = messageBox.message.fileDescriptor.intValue;
                DLog(@"tryAttachWithState(%@): Success", strongSelf->_socketPath);
                [callback invokeWithObject:@(iTermFileDescriptorMultiClientAttachStatusSuccess)];
                ok = YES;
            } else {
                DLog(@"tryAttachWithState(%@): Failed to get a file descriptor", strongSelf->_socketPath);
            }
        } error:^(NSError * _Nonnull error) {
            DLog(@"tryAttachWithState(%@): Error reading file descriptor: %@", strongSelf->_socketPath, error);
            ok = NO;
        }];
        if (!ok) {
            close(state.readFD);
            state.readFD = -1;
            // You can get here if the server crashes right after accepting the connection. It can
            // also happen if the server already has a connected client and rejects.
            DLog(@"tryAttachWithState(%@): Fatal error (see above)", strongSelf->_socketPath);
            [callback invokeWithObject:@(iTermFileDescriptorMultiClientAttachStatusFatalError)];
        }
    }]];
}

#pragma mark - Handshake

// Send a handshake message. Read child reports. Start the read-dispatch loop.
// Then run the callback.
- (void)handshakeWithState:(iTermFileDescriptorMultiClientState *)state
                  callback:(iTermCallback<id, NSNumber *> *)callback {
    // Just launched the server. Now handshake with it.
    assert(state.readFD >= 0);
    assert(state.writeFD >= 0);
    DLog(@"Handshake with %@", _socketPath);

    iTermCallback<id, NSNumber *> *innerCallback =
    [_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *state,
                                    NSNumber *handshakeOK) {
        // All child reports have been read, or it failed and we're giving up.
        DLog(@"Handshake completed for %@", self->_socketPath);
        if (!handshakeOK.boolValue) {
            DLog(@"HANDSHAKE FAILED FOR %@", self->_socketPath);
            [self closeWithState:state];
        }
        [callback invokeWithObject:handshakeOK];
    }];
    __weak __typeof(self) weakSelf = self;
    [self sendHandshakeRequestWithState:state
                               callback:[_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *state,
                                                                        NSNumber *sendResult) {
        [weakSelf didSendHandshakeRequestWithSuccess:sendResult.boolValue
                                               state:state
                                            callback:innerCallback
                                 childDiscoveryBlock:^(iTermFileDescriptorMultiClientState *state,
                                                       iTermMultiServerReportChild *report) {
            // Report must be consumed synchronously!
            [weakSelf didDiscoverChild:report state:state];
        }];
    }]];
}

- (void)sendHandshakeRequestWithState:(iTermFileDescriptorMultiClientState *)state
                             callback:(iTermCallback<id, NSNumber *> *)callback {
    iTermMultiServerClientOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeHandshake,
        .payload = {
            .handshake = {
                .maximumProtocolVersion = iTermMultiServerProtocolVersion2
            }
        }
    };
    [self send:&message state:state callback:callback];
}

// Read the handshake response. Read the child reports, calling `block` for
// each. Run the callback. Then start the read-dispatch loop.
- (void)didSendHandshakeRequestWithSuccess:(BOOL)sendOK
                                     state:(iTermFileDescriptorMultiClientState *)state
                                  callback:(iTermCallback<id, NSNumber *> *)callback
                       childDiscoveryBlock:(void (^)(iTermFileDescriptorMultiClientState *state,
                                                     iTermMultiServerReportChild *))block {
    if (!sendOK) {
        DLog(@"FAILED: Send handshake request for %@", _socketPath);
        [callback invokeWithObject:@NO];
        return;
    }

    NSString *socketPath = _socketPath;
    [self readHandshakeResponseWithState:state
                              completion:^(iTermFileDescriptorMultiClientState *state,
                                           BOOL ok,
                                           int numberOfChildren,
                                           pid_t pid) {
        if (!ok) {
            [callback invokeWithObject:@NO];
            return;
        }
        state.serverPID = pid;
        [self readInitialChildReports:numberOfChildren
                                state:state
                                block:block
                           completion:^(iTermFileDescriptorMultiClientState *state, BOOL ok) {
            DLog(@"Done reading child reports for %@ with ok=%@", socketPath, @(ok));
            if (!ok) {
                [callback invokeWithObject:@NO];
                return;
            }

            // Ensure the completion callback runs before the read loop starts producing events.
            [callback invokeWithObject:@YES];
            [self readAndDispatchNextMessageWhenReadyWithState:state];
        }];
    }];
}

// Read the handshake response and run the completion block.
- (void)readHandshakeResponseWithState:(iTermFileDescriptorMultiClientState *)state
                            completion:(void (^)(iTermFileDescriptorMultiClientState *state,
                                                 BOOL ok,
                                                 int numberOfChildren,
                                                 pid_t pid))completion {
    NSString *socketPath = _socketPath;
    DLog(@"Read handshake response for %@", socketPath);
    [self readMessageWithState:state
                      callback:[_thread newCallbackWithBlock:^(id  _Nonnull state,
                                                               iTermResult<iTermClientServerProtocolMessageBox *> *result) {
        [result handleObject:^(iTermClientServerProtocolMessageBox * _Nonnull boxedMessage) {
            DLog(@"Got a response for %@", socketPath);
            if (!boxedMessage.decoded) {
                DLog(@"Failed to decode message for %@", socketPath);
                completion(state, NO, 0, -1);
                return;
            }
            if (boxedMessage.decoded->type != iTermMultiServerRPCTypeHandshake) {
                  DLog(@"Got an unexpected response for %@", socketPath);
                completion(state, NO, 0, -1);
                return;
            }
            DLog(@"Got a valid handshake response for %@", socketPath);
            if (boxedMessage.decoded->payload.handshake.protocolVersion != iTermMultiServerProtocolVersion2) {
                completion(state, NO, 0, -1);
                return;
            }
            completion(state,
                       YES,
                       boxedMessage.decoded->payload.handshake.numChildren,
                       boxedMessage.decoded->payload.handshake.pid);
        } error:^(NSError * _Nonnull error) {
            DLog(@"FAILED: Invalid handshake response for %@", socketPath);
            completion(state, NO, 0, -1);
        }];
    }]];
}

// Read exactly `numberOfChildren` child reports. This happens before the
// read-dispatch loop begins so it is safe to do a bunch of async read calls.
// It will call itself recursively until numberOfChildren is 0. Then the
// completion block will be called.
- (void)readInitialChildReports:(int)numberOfChildren
                          state:(iTermFileDescriptorMultiClientState *)state
                          block:(void (^)(iTermFileDescriptorMultiClientState *state, iTermMultiServerReportChild *))block
                     completion:(void (^)(iTermFileDescriptorMultiClientState *state, BOOL ok))completion {
    DLog(@"Read initial child reports (%@) for %@", @(numberOfChildren), _socketPath);
    if (numberOfChildren == 0) {
        DLog(@"Have no children for %@", _socketPath);
        completion(state, YES);
        return;
    }
    __weak __typeof(self) weakSelf = self;
    NSString *socketPath = _socketPath;
    [self readMessageWithState:state
                      callback:[_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *state,
                                                               iTermResult<iTermClientServerProtocolMessageBox *> *result) {
        [result handleObject:^(iTermClientServerProtocolMessageBox * _Nonnull box) {
            __strong __typeof(self) strongSelf = weakSelf;
            DLog(@"Read a child report for %@", socketPath);
            if (!strongSelf) {
                completion(state, NO);
                return;
            }
            if (!box.decoded) {
                DLog(@"Failed to decode message for %@", socketPath);
                completion(state, NO);
                return;
            }
            if (box.decoded->type != iTermMultiServerRPCTypeReportChild) {
                DLog(@"Unexpected message type when reading child reports for %@", socketPath);
                completion(state, NO);
                return;
            }
            iTermMultiServerServerOriginatedMessage *message = box.decoded;
            block(state, &message->payload.reportChild);
            const BOOL foundLast = message->payload.reportChild.isLast;
            if (!foundLast) {
                assert(numberOfChildren > 0);
                [strongSelf->_thread dispatchAsync:^(iTermFileDescriptorMultiClientState * _Nullable state) {
                    DLog(@"Want another child report for %@", socketPath);
                    [strongSelf readInitialChildReports:numberOfChildren - 1
                                                  state:state
                                                  block:block
                                             completion:completion];
                }];
                return;
            }
            DLog(@"Got last child report for %@", socketPath);
            completion(state, YES);
        } error:^(NSError * _Nonnull error) {
            DLog(@"FAILED to read initial child report %@: %@", socketPath, error);
            completion(state, NO);
        }];
    }]];
}

// Called during handshake as children are reported.
// The `report` must be consumed synchronously because its memory will not
// survive the return of this function.
- (void)didDiscoverChild:(iTermMultiServerReportChild *)report
                   state:(iTermFileDescriptorMultiClientState *)state {
    iTermFileDescriptorMultiClientChild *child =
    [[iTermFileDescriptorMultiClientChild alloc] initWithReport:report
                                                         thread:self->_thread];
    [self addChild:child state:state attached:NO];
}

#pragma mark - Launch Child

static int LengthOfNullTerminatedPointerArray(const void **array) {
    int i = 0;
    while (array[i]) {
        i++;
    }
    return i;
}

static unsigned long long MakeUniqueID(void) {
    unsigned long long result = arc4random_uniform(0xffffffff);
    result <<= 32;
    result |= arc4random_uniform(0xffffffff);;
    return (long long)result;
}

// Send a launch request and then run the callback. Eventually, you may receive
// a child report. The request and the child report are coupled by the unique
// ID, but we may read other messages before getting the child report.
// These C pointers live until the callback is run.
- (void)launchChildWithExecutablePath:(const char *)path
                                 argv:(const char **)argv
                          environment:(const char **)environment
                                  pwd:(const char *)pwd
                             ttyState:(iTermTTYState)ttyState
                                state:(iTermFileDescriptorMultiClientState *)state
                             callback:(iTermMultiClientLaunchCallback *)callback {
    DLog(@"begin");
    const unsigned long long uniqueID = MakeUniqueID();
    iTermMultiServerClientOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeLaunch,
        .payload = {
            .launch = {
                .path = path,
                .argv = argv,
                .argc = LengthOfNullTerminatedPointerArray((const void **)argv),
                .envp = environment,
                .envc = LengthOfNullTerminatedPointerArray((const void **)environment),
                .columns = ttyState.win.ws_col,
                .rows = ttyState.win.ws_row,
                .pixel_width = ttyState.win.ws_xpixel,
                .pixel_height = ttyState.win.ws_ypixel,
                .isUTF8 = !!(ttyState.term.c_iflag & IUTF8),
                .pwd = pwd,
                .uniqueId = uniqueID
            }
        }
    };
    iTermMultiServerClientOriginatedMessage messageCopy = [self copyLaunchRequest:message];

    DLog(@"Add pending launch %@ for %@", @(message.payload.launch.uniqueId), _socketPath);
    state.pendingLaunches[@(message.payload.launch.uniqueId)] =
        [[iTermFileDescriptorMultiClientPendingLaunch alloc] initWithRequest:messageCopy.payload.launch
                                                                    callback:callback
                                                                      thread:_thread];

    [self send:&message state:state callback:[_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *state,
                                                                             NSNumber *result) {
        DLog(@"called back");
        const BOOL ok = result.boolValue;
        if (ok) {
            DLog(@"Wrote launch request successfully.");
            return;
        }

        DLog(@"Failed to write launch request.");
        if (state.pendingLaunches[@(uniqueID)]) {
            DLog(@"Invoke callback with connection-lost error.");
            [state.pendingLaunches removeObjectForKey:@(uniqueID)];
            [callback invokeWithObject:[iTermResult withError:[self connectionLostError]]];
        }
    }]];
}

static NSMutableArray *gCurrentMultiServerLogLineStorage;
static void iTermMultiServerStringForMessageFromClientLogger(const char *file,
                                                             int line,
                                                             const char *func,
                                                             const char *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *string = [[NSString alloc] initWithFormat:[NSString stringWithUTF8String:format]
                                            arguments:args];
    [gCurrentMultiServerLogLineStorage addObject:string];
    va_end(args);
};

static NSString *iTermMultiServerStringForMessageFromClient(iTermMultiServerClientOriginatedMessage *message) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gCurrentMultiServerLogLineStorage = [NSMutableArray array];
    });
    @synchronized(gCurrentMultiServerLogLineStorage) {
        iTermMultiServerProtocolLogMessageFromClient2(message, iTermMultiServerStringForMessageFromClientLogger);
        NSString *result = [gCurrentMultiServerLogLineStorage componentsJoinedByString:@"\n"];
        [gCurrentMultiServerLogLineStorage removeAllObjects];
        return result;
    }
}

// Called on job manager's queue via [self launchChildWithExecutablePath:…]
- (iTermMultiServerClientOriginatedMessage)copyLaunchRequest:(iTermMultiServerClientOriginatedMessage)original {
    ITAssertWithMessage(original.type == iTermMultiServerRPCTypeLaunch, @"Type is %@", @(original.type));

    // Encode and decode the message so we can have our own copy of it.
    iTermClientServerProtocolMessage temp;
    iTermClientServerProtocolMessageInitialize(&temp);

    {
        const int status = iTermMultiServerProtocolEncodeMessageFromClient(&original, &temp);
        ITAssertWithMessage(status == 0, @"On encode: status is %@", @(status));
    }

    iTermMultiServerClientOriginatedMessage messageCopy;
    {
        const int status = iTermMultiServerProtocolParseMessageFromClient(&temp, &messageCopy);
        if (status) {
            iTermClientServerProtocolMessage temp;
            iTermClientServerProtocolMessageInitialize(&temp);
            (void)iTermMultiServerProtocolEncodeMessageFromClient(&original, &temp);
            NSData *data = [NSData dataWithBytes:temp.ioVectors[0].iov_base
                                          length:temp.ioVectors[0].iov_len];
            NSString *description = iTermMultiServerStringForMessageFromClient(&messageCopy);
            ITAssertWithMessage(status == 0, @"On decode: status is %@ for %@ based on %@",
                                @(status),
                                [data debugDescription],
                                description);
        }
    }

    return messageCopy;
}

// Handle a launch response, telling us about a child that was hopefully forked and execed.
// Add a new child and run the callback for the pending launch.
// `launch` must be consumed synchronously.
- (void)handleLaunch:(iTermMultiServerResponseLaunch)launch
               state:(iTermFileDescriptorMultiClientState *)state {
    DLog(@"handleLaunch: unique ID %@ for %@", @(launch.uniqueId), _socketPath);
    iTermFileDescriptorMultiClientPendingLaunch *pendingLaunch = state.pendingLaunches[@(launch.uniqueId)];
    if (!pendingLaunch) {
        ITBetaAssert(NO, @"No pending launch for %@ in %@", @(launch.uniqueId), state.pendingLaunches);
        return;
    }
    [state.pendingLaunches removeObjectForKey:@(launch.uniqueId)];

    if (launch.status != 0) {
        DLog(@"handleLaunch: error status %@ for %@", @(launch.status), _socketPath);
        [pendingLaunch.launchCallback invokeWithObject:[iTermResult withError:self.forkError]];
        [pendingLaunch invalidate];
        return;
    }

    // Happy path
    iTermMultiServerReportChild fakeReport = {
        .isLast = 0,
        .pid = launch.pid,
        .path = pendingLaunch.launchRequest.path,
        .argv = pendingLaunch.launchRequest.argv,
        .argc = pendingLaunch.launchRequest.argc,
        .envp = pendingLaunch.launchRequest.envp,
        .envc = pendingLaunch.launchRequest.envc,
        .isUTF8 = pendingLaunch.launchRequest.isUTF8,
        .pwd = pendingLaunch.launchRequest.pwd,
        .terminated = 0,
        .tty = launch.tty,
        .fd = launch.fd
    };

    iTermFileDescriptorMultiClientChild *child = [[iTermFileDescriptorMultiClientChild alloc] initWithReport:&fakeReport
                                                                                                      thread:_thread];
    [self addChild:child state:state attached:YES];
    DLog(@"handleLaunch: Success for pid %@ from %@", @(launch.pid), _socketPath);
    [pendingLaunch.launchCallback invokeWithObject:[iTermResult withObject:child]];

    iTermMultiServerClientOriginatedMessage temp;
    temp.type = iTermMultiServerRPCTypeLaunch;
    temp.payload.launch = pendingLaunch.launchRequest;
    iTermMultiServerClientOriginatedMessageFree(&temp);
    [pendingLaunch invalidate];
}

#pragma mark - Wait for Child

// Send a wait request. The response handler gets attached to the child to
// avoid coupling request and response in time. The callback is run right
// away if the request can't be written, or else it gets called when the
// wait response for this pid is received.
- (void)waitForChild:(iTermFileDescriptorMultiClientChild *)child
  removePreemptively:(BOOL)removePreemptively
               state:(iTermFileDescriptorMultiClientState *)state
            callback:(iTermCallback<id, iTermResult<NSNumber *> *> *)callback {
    if (child.haveWaited) {
        [callback invokeWithObject:[iTermResult withError:[self waitError:2]]];
        return;
    }
    if (removePreemptively) {
        if (child.haveSentPreemptiveWait) {
            [callback invokeWithObject:[iTermResult withError:[self waitError:1]]];
            return;
        }
        [child willWaitPreemptively];
    }

    assert(!child.haveWaited);
    iTermMultiServerClientOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeWait,
        .payload = {
            .wait = {
                .pid = child.pid,
                .removePreemptively = removePreemptively
            }
        }
    };

    __weak __typeof(child) weakChild = child;
    iTermCallback<id, iTermResult<NSNumber *> *> *waitCallback =
    [_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *_Nonnull state,
                                                         iTermResult<NSNumber *> *waitResult) {
        [waitResult handleObject:
         ^(NSNumber * _Nonnull statusNumber) {
            DLog(@"wait for %@ returned termination status %@", @(weakChild.pid), statusNumber);
            [weakChild setTerminationStatus:statusNumber.intValue];
            [callback invokeWithObject:waitResult];
        }
                           error:
         ^(NSError * _Nonnull error) {
            DLog(@"wait for %@ returned error %@", @(weakChild.pid), error);
            [callback invokeWithObject:waitResult];
        }];
    }];
    [child addWaitCallback:waitCallback];

    __weak __typeof(self) weakSelf = self;
    iTermCallback<id, NSNumber *> *sendCallback =
    [_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *state,
                                                                             NSNumber *value) {
        [weakSelf didWriteWaitRequestWithStatus:value.boolValue
                                          child:child
                                          state:state];
    }];
    [self send:&message state:state callback:sendCallback];
}

- (void)didWriteWaitRequestWithStatus:(BOOL)sendOK
                                child:(iTermFileDescriptorMultiClientChild *)child
                                state:(iTermFileDescriptorMultiClientState *)state {
    if (sendOK) {
        return;
    }
    [child invokeAllWaitCallbacks:[iTermResult withError:self.ioError]];
    DLog(@"Close client for %@ because of failed write", _socketPath);
    [self closeWithState:state];
}

// Handle a wait response from the daemon, giving the child's exit code.
- (void)handleWait:(iTermMultiServerResponseWait)wait
             state:(iTermFileDescriptorMultiClientState *)state {
    DLog(@"handleWait for socket %@ pid %@ with error %@, status %@",
          _socketPath, @(wait.pid), @(wait.resultType), @(wait.status));
        iTermFileDescriptorMultiClientChild *child = [self childWithPID:wait.pid state:state];
    switch (wait.resultType) {
        case iTermMultiServerResponseWaitResultTypeNotTerminated:
            break;
        case iTermMultiServerResponseWaitResultTypePreemptive:
        case iTermMultiServerResponseWaitResultTypeNoSuchChild:
        case iTermMultiServerResponseWaitResultTypeStatusIsValid:
            [self removeChild:[self childWithPID:wait.pid state:state] state:state];
            break;
    }
    iTermResult<NSNumber *> *result;
    if (wait.resultType != iTermMultiServerResponseWaitResultTypeStatusIsValid) {
        result = [iTermResult withError:[self waitError:wait.resultType]];
    } else {
        result = [iTermResult withObject:@(wait.status)];
    }
    [child invokeAllWaitCallbacks:result];
}

#pragma mark - Termination

// Handle a termination notification from the daemon. Notifies the delegate.
- (void)handleTermination:(iTermMultiServerReportTermination)termination
                    state:(iTermFileDescriptorMultiClientState *)state {
    DLog(@"handleTermination for %@", _socketPath);
    iTermFileDescriptorMultiClientChild *child = [self childWithPID:termination.pid state:state];
    if (child) {
        [child didTerminate];
        [self.delegate fileDescriptorMultiClient:self childDidTerminate:child];
    }
}

#pragma mark - Launch Daemon

// Launch a new daemon, handshake with it, start the read-dispatch loop, and run the callback.
- (void)launchNewDaemonAndHandshakeWithState:(iTermFileDescriptorMultiClientState *)state
                                    callback:(iTermCallback<id, NSNumber *> *)callback {
    assert(state.readFD < 0);
    assert(state.writeFD < 0);

    if (![self launchNewDaemonWithState:state]) {
        assert(state.readFD < 0);
        assert(state.writeFD < 0);
        [callback invokeWithObject:@NO];
        return;
    }

    [self handshakeWithState:state callback:callback];
}

- (NSArray<NSString *> *)serverFolders {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    if (appSupport) {
        [result addObject:appSupport];
    }

    NSString *dotDir = [[NSFileManager defaultManager] homeDirectoryDotDir];
    if (dotDir) {
        [result addObject:dotDir];
    }

    return result;
}

- (NSString *)serverPath {
    NSString *filename = iTermServerName.name;

    for (NSString *folder in [self serverFolders]) {
        NSString *path = [folder stringByAppendingPathComponent:filename];
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path] ||
            [[NSFileManager defaultManager] directoryIsWritable:folder]) {
            return path;
        }
    }

    return nil;
}

- (void)showError:(NSError *)error message:(NSString *)message badURL:(NSURL *)url {
    DLog(@"message: %@ error: %@ url: %@", message, error, url);
    dispatch_async(dispatch_get_main_queue(), ^{
        static iTermRateLimitedUpdate *rateLimit;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            rateLimit = [[iTermRateLimitedUpdate alloc] initWithName:@"Multi client error"
                                                     minimumInterval:2];
        });
        [rateLimit performRateLimitedBlock:^{
            DLog(@"Called");
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Problem Starting iTerm2 Daemon";
            alert.informativeText = message;
            [alert runModal];
        }];
    });
}

- (NSString *)pathToServerInBundle {
    return [[NSBundle bundleForClass:self.class] pathForAuxiliaryExecutable:@"iTermServer"];
}

- (BOOL)shouldCopyServerTo:(NSString *)desiredPath {
    DLog(@"%@", desiredPath);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:desiredPath]) {
        DLog(@"File doesn't exist");
        return YES;
    }

    NSError *error = nil;
    NSDictionary<NSFileAttributeKey, id> *attributes = [fileManager attributesOfItemAtPath:desiredPath error:&error];
    if (!attributes) {
        DLog(@"%@", error);
        return YES;
    }

    const long long existingFileSize = [attributes fileSize];

    NSString *pathToServerInBundle = [self pathToServerInBundle];
    attributes = [fileManager attributesOfItemAtPath:pathToServerInBundle error:&error];
    if (!attributes) {
        DLog(@"%@", error);
        return YES;
    }

    const long long bundleFileSize = [attributes fileSize];
    DLog(@"Existing size=%@ bundle size=%@", @(existingFileSize), @(bundleFileSize));

    return existingFileSize != bundleFileSize;
}

// Copy iTermServer to a safe location where Autoupdate won't delete it. See issue 9022 for
// wild speculation on why this is important.
- (NSString *)serverPathCopyingIfNeeded {
    NSString *desiredPath = [self serverPath];
    if (!desiredPath) {
        [self showError:nil
                message:[NSString stringWithFormat:@"Neither ~/Library/Application Support/iTerm2 nor ~/.iterm2 are writable directories. This prevents the session restoration server from running. Please correct the problem and restart iTerm2."]
                 badURL:nil];
        return nil;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Does the server already exist where we need it to be?
    if ([self shouldCopyServerTo:desiredPath]) {
        [self deleteDisusedServerBinaries];
        [fileManager removeItemAtPath:desiredPath error:nil];
        
        NSString *sourcePath = [self pathToServerInBundle];
        NSError *error = nil;
        [fileManager copyItemAtPath:sourcePath
                             toPath:desiredPath
                              error:&error];
        if (error) {
            [self showError:error
                    message:[NSString stringWithFormat:@"Could not copy %@ to %@: %@", sourcePath, desiredPath, error.localizedDescription]
                     badURL:[NSURL fileURLWithPath:desiredPath]];
            return nil;
        }
    }

    // Is it executable?
    {
        NSError *error = nil;
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:desiredPath error:&error];
        if (error) {
            [self showError:error
                    message:[NSString stringWithFormat:@"Could not check permissions on %@", desiredPath]
                     badURL:[NSURL fileURLWithPath:desiredPath]];
            return nil;
        }
        NSNumber *permissions = attributes[NSFilePosixPermissions];
        if ((permissions.intValue & 0700) == 0700) {
            return desiredPath;
        }
    }

    // Make it executable.
    {
        NSError *error = nil;
        [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @(0700) }
                                         ofItemAtPath:desiredPath
                                                error:&error];
        if (error) {
            [self showError:error
                    message:[NSString stringWithFormat:@"Could not set 0700 permissions on %@", desiredPath]
                     badURL:[NSURL fileURLWithPath:desiredPath]];
            return nil;
        }
    }

    return desiredPath;
}

// Launch a daemon synchronously.
- (BOOL)launchNewDaemonWithState:(iTermFileDescriptorMultiClientState *)state {
    assert(state.readFD < 0);

    NSString *executable = [self serverPathCopyingIfNeeded];
    if (!executable) {
        return NO;
    }

    int readFD = -1;
    int writeFD = -1;
    iTermForkState forkState = [self launchWithSocketPath:_socketPath
                                               executable:executable
                                                   readFD:&readFD
                                                  writeFD:&writeFD];
    if (forkState.pid < 0) {
        return NO;
    }

    state.daemonProcessSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC,
                                                       forkState.pid,
                                                       DISPATCH_PROC_EXIT,
                                                       state.queue);
    dispatch_source_set_event_handler(state.daemonProcessSource, ^{
        int statLoc;
        waitpid(forkState.pid, &statLoc, WNOHANG);
    });
    dispatch_resume(state.daemonProcessSource);

    assert(readFD >= 0);
    assert(writeFD >= 0);
    state.readFD = readFD;
    state.writeFD = writeFD;

    return YES;
}

#pragma mark - Janitorial

- (void)deleteDisusedServerBinaries {
    if (@available(macOS 10.15, *)) {
        [iTermServerDeleter deleteDisusedServersIn:[self serverFolders]
                                          provider:[iTermProcessCache newProcessCollection]];
    }
}

#pragma mark - Tear Down

// Close the file descriptors. Notify the delegate.
- (void)closeWithState:(iTermFileDescriptorMultiClientState *)state {
    if (state.readFD < 0 && state.writeFD < 0) {
        DLog(@"Already closed %@, doing nothing", _socketPath);
        return;
    }
    DLog(@"CLOSE %@", _socketPath);

    if (state.readFD >= 0) {
        close(state.readFD);
    }
    if (state.writeFD >= 0) {
        close(state.writeFD);
    }

    state.readFD = -1;
    state.writeFD = -1;

    NSDictionary<NSNumber *, iTermFileDescriptorMultiClientPendingLaunch *> *pendingLaunches = [state.pendingLaunches copy];
    [state.pendingLaunches removeAllObjects];
    [pendingLaunches enumerateKeysAndObjectsUsingBlock:
     ^(NSNumber * _Nonnull uniqueID,
       iTermFileDescriptorMultiClientPendingLaunch * _Nonnull pendingLaunch,
       BOOL * _Nonnull stop) {
        [pendingLaunch cancelWithError:[self connectionLostError]];
    }];

    [state.children enumerateObjectsUsingBlock:
     ^(iTermFileDescriptorMultiClientChild * _Nonnull child,
       NSUInteger idx,
       BOOL * _Nonnull stop) {
        [child invokeAllWaitCallbacks:[iTermResult withError:[self connectionLostError]]];
    }];
    [state.children removeAllObjects];

    [self.delegate fileDescriptorMultiClientDidClose:self];
}

#pragma mark - Read-Dispatch Loop

// This is the read-dispatch loop. readAndDispatchNextMessageWithState will call this method after
// it's done reading a message.
- (void)readAndDispatchNextMessageWhenReadyWithState:(iTermFileDescriptorMultiClientState *)state {
    if (state.readFD < 0 || state.writeFD < 0) {
        DLog(@"readAndDispatchNextMessageWhenReadyWithState: aborting because files are closed");
        return;
    }
    DLog(@"readAndDispatchNextMessageWhenReadyWithState: registring read callback");
    __weak __typeof(self) weakSelf = self;
    [state whenReadable:^(iTermFileDescriptorMultiClientState *state) {
        [weakSelf readAndDispatchNextMessageWithState:state];
    }];
}

// Read a message and dispatch it to the appropriate handler.
- (void)readAndDispatchNextMessageWithState:(iTermFileDescriptorMultiClientState *)state {
    DLog(@"readAndDispatchNextMessageWithState(%@)", _socketPath);
    NSString *socketPath = [_socketPath copy];
    [self readMessageWithState:state
                      callback:[_thread newCallbackWithBlock:
                                ^(iTermFileDescriptorMultiClientState *state,
                                  iTermResult<iTermClientServerProtocolMessageBox *> *result) {
        __block BOOL ok = YES;
        [result handleObject:^(iTermClientServerProtocolMessageBox * _Nonnull object) {
            ok = [self dispatch:object state:state];
            if (!ok) {
                DLog(@"Close connection because dispatch failed %@", socketPath);
            }
        } error:^(NSError * _Nonnull error) {
            DLog(@"FAILED to read message to be dispatched %@: %@", socketPath, error);
            ok = NO;
        }];
        if (!ok) {
            [self closeWithState:state];
            return;
        }
        [self readAndDispatchNextMessageWhenReadyWithState:state];
    }]];
}

// Invoke the appropriate handler for a just-received message.
- (BOOL)dispatch:(iTermClientServerProtocolMessageBox *)box
           state:(iTermFileDescriptorMultiClientState *)state {
    DLog(@"dispatch for %@", _socketPath);
    iTermMultiServerServerOriginatedMessage *decoded = box.decoded;
    if (!decoded) {
        return NO;
    }
    switch (decoded->type) {
        case iTermMultiServerRPCTypeWait:
            [self handleWait:decoded->payload.wait state:state];
            break;

        case iTermMultiServerRPCTypeLaunch:
            [self handleLaunch:decoded->payload.launch state:state];
            break;

        case iTermMultiServerRPCTypeTermination:
            [self handleTermination:decoded->payload.termination state:state];
            break;

        case iTermMultiServerRPCTypeHello:  // Shouldn't happen at this point
        case iTermMultiServerRPCTypeHandshake:
        case iTermMultiServerRPCTypeReportChild:
            DLog(@"Close %@ because of unexpected message of type %@", _socketPath, @(decoded->type));
            [self closeWithState:state];
            break;
    }
    return YES;
}

#pragma mark - Child Management

- (void)addChild:(iTermFileDescriptorMultiClientChild *)child
           state:(iTermFileDescriptorMultiClientState *)state
        attached:(BOOL)attached {
    DLog(@"Add child %@ attached=%@", child, @(attached));
    [state.children addObject:child];
    if (!attached) {
        [self.delegate fileDescriptorMultiClient:self didDiscoverChild:child];
    }
}

- (void)removeChild:(iTermFileDescriptorMultiClientChild *)child
              state:(iTermFileDescriptorMultiClientState *)state {
    if (!child) {
        return;
    }
    DLog(@"Remove child %@", child);
    [state.children removeObject:child];
}

- (iTermFileDescriptorMultiClientChild *)childWithPID:(pid_t)pid
                                                state:(iTermFileDescriptorMultiClientState *)state {
    return [state.children objectPassingTest:^BOOL(iTermFileDescriptorMultiClientChild *element, NSUInteger index, BOOL *stop) {
        return element.pid == pid;
    }];
}

#pragma mark - Reading

// Read a full message, which may contain a file desciptor. First, read the
// length of the message. Then read the payload. Then decode it and invoke the
// callback. See the note on whenReadable: for why doing two async reads is
// safe. It is critical that this be the only method that calls -readWithState
// after than handshake is complete. Otherwise, reads could get intermingled.
- (void)readMessageWithState:(iTermFileDescriptorMultiClientState *)state
                    callback:(iTermCallback<id, iTermResult<iTermClientServerProtocolMessageBox *> *> *)callback {
    // First, read the length of the forthcoming message.
    __weak __typeof(self) weakSelf = self;
    NSString *socketPath = [_socketPath copy];
    DLog(@"Read length of next message from %@", socketPath);
    [self readWithState:state
                 length:sizeof(size_t)
               callback:[_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *_Nonnull state,
                                                        iTermResult<iTermMultiServerMessage *> *_Nullable result) {
        [result handleObject:^(iTermMultiServerMessage * _Nonnull lengthMessage) {
            __strong __typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                DLog(@"Looks like I've been dealloced. %@", socketPath);
                [callback invokeWithObject:[iTermResult withError:[NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                                                                                      code:iTermFileDescriptorMultiClientErrorCodeUnknown
                                                                                  userInfo:nil]]];
                return;
            }
            assert(lengthMessage.data.length == sizeof(size_t));
            size_t length;
            memmove(&length, lengthMessage.data.bytes, sizeof(size_t));
            DLog(@"Next message length is %@. %@", @(length), socketPath);
            static const NSInteger MAX_MESSAGE_SIZE = 1024 * 1024;
            if (length > MAX_MESSAGE_SIZE) {
                DLog(@"Max length exceeded, return io error %@", socketPath);
                [callback invokeWithObject:[iTermResult withError:strongSelf.ioError]];
                return;
            }

            DLog(@"Will read payload of length %@. %@", @(length), socketPath);
            // Now read the payload including a possible file descriptor.
            [weakSelf readWithState:state
                             length:length
                           callback:[strongSelf->_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *_Nonnull state,
                                                                                iTermResult<iTermMultiServerMessage *> *_Nullable result) {
                [result handleObject:^(iTermMultiServerMessage * _Nonnull payload) {
                    // Try to decode the payload.
                    __strong __typeof(self) strongSelf = weakSelf;
                    if (!strongSelf) {
                        DLog(@"I've been dealloced while reading %@", socketPath);
                        [callback invokeWithObject:[iTermResult withError:[NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                                                                                              code:iTermFileDescriptorMultiClientErrorCodeUnknown
                                                                                          userInfo:nil]]];
                        return;
                    }
                    iTermClientServerProtocolMessageBox *encodedBox = [iTermClientServerProtocolMessageBox withMessage:payload];

                    if (!encodedBox) {
                        DLog(@"Decoding: recv failed for %@", strongSelf->_socketPath);
                        [callback invokeWithObject:[iTermResult withError:strongSelf.protocolError]];
                    }

                    [callback invokeWithObject:[iTermResult withObject:encodedBox]];
                }
                               error:^(NSError * _Nonnull error) {
                    DLog(@"Failed to read payload from %@: %@", socketPath, error);
                    [callback invokeWithObject:[iTermResult withError:error]];
                }];
            }]];
        } error:^(NSError * _Nonnull error) {
            DLog(@"Failed to read next message's length %@: %@", socketPath, error);
            [callback invokeWithObject:[iTermResult withError:error]];
        }];
    }]];
}

// When the socket becomes readable, read exactly `length` bytes and then run
// the callback with the result.
- (void)readWithState:(iTermFileDescriptorMultiClientState *)state
               length:(NSInteger)length
             callback:(iTermCallback<id, iTermResult<iTermMultiServerMessage *> *> *)callback {
    iTermMultiServerMessageBuilder *builder = [[iTermMultiServerMessageBuilder alloc] init];
    [state whenReadable:^(iTermFileDescriptorMultiClientState *state) {
        [self partialReadWithState:state totalLength:length builder:builder callback:callback];
    }];
}

// Read exactly `totalLength` bytes and then run the callback. Since it may
// take many async read calls, the builder is used to accumulate the input.
// This is run from within a whenReadable: callback, so any call to
// whenReadable: made herein is moved to the head of the queue.
- (void)partialReadWithState:(iTermFileDescriptorMultiClientState *)state
                 totalLength:(NSInteger)totalLength
                     builder:(iTermMultiServerMessageBuilder *)builder
                    callback:(iTermCallback<id, iTermResult<iTermMultiServerMessage *> *> *)callback {
    DLog(@"Want to read %@ from %@", @(totalLength), _socketPath);

    if (state.readFD < 0) {
        DLog(@"readFD<0 for %@", _socketPath);
        [callback invokeWithObject:[iTermResult withError:self.connectionLostError]];
        return;
    }

    iTermClientServerProtocolMessage message;
    ssize_t bytesRead = iTermMultiServerReadMessage(state.readFD, &message, totalLength - builder.length);
    if (bytesRead < 0) {
        if (errno == EAGAIN) {
            DLog(@"Nothing to read %@. Will wait for the socket to become readable and try again later.", _socketPath);
            __weak __typeof(self) weakSelf = self;
            [state whenReadable:^(iTermFileDescriptorMultiClientState *state) {
                [weakSelf partialReadWithState:state
                                   totalLength:totalLength
                                       builder:builder
                                      callback:callback];
            }];
            return;
        }
        DLog(@"read failed with %s for %@", strerror(errno), _socketPath);
        [callback invokeWithObject:[iTermResult withError:self.ioError]];
        return;
    }
    if (message.controlBuffer.cm.cmsg_len == CMSG_LEN(sizeof(int)) &&
        message.controlBuffer.cm.cmsg_level == SOL_SOCKET &&
        message.controlBuffer.cm.cmsg_type == SCM_RIGHTS) {
        DLog(@"Got a file descriptor in message from %@", _socketPath);
        [builder setFileDescriptor:*((int *)CMSG_DATA(&message.controlBuffer.cm))];
    }

    if (bytesRead == 0) {
        DLog(@"EOF %@", _socketPath);
        [callback invokeWithObject:[iTermResult withError:self.connectionLostError]];
        [self closeWithState:state];
        return;
    }

    DLog(@"Append %@ bytes in read from %@", @(bytesRead), _socketPath);
    if (bytesRead > 0) {
        [builder appendBytes:message.message.msg_iov[0].iov_base
                      length:bytesRead];
    }

    assert(builder.length <= totalLength);
    if (builder.length == totalLength) {
        DLog(@"Read complete from %@", _socketPath);
        [callback invokeWithObject:[iTermResult withObject:builder.message]];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    DLog(@"Have read %@/%@ from %@. Wait for socket to be readable again.", @(builder.length), @(totalLength), _socketPath);
    [state whenReadable:^(iTermFileDescriptorMultiClientState *state) {
        [weakSelf partialReadWithState:state
                           totalLength:totalLength
                               builder:builder
                              callback:callback];
    }];
}

#pragma mark - Writing

#if BETA
static void HexDump(NSData *data) {
    NSMutableString *dest = [NSMutableString string];
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    int addr = 0;
    DLog(@"- Begin hex dump of outbound message -");
    for (int i = 0; i < data.length; i++) {
        if (i % 16 == 0 && i > 0) {
            DLog(@"%4d  %@", addr, dest);
            addr = i;
            dest = [NSMutableString string];
        }
        [dest appendFormat:@"%02x ", bytes[i]];
    }
    if (dest.length) {
        DLog(@"%04d  %@", addr, dest);
    }
    DLog(@"- End hex dump of outbound message -");
}
#endif

// Send a message. Then run the callback.
- (void)send:(iTermMultiServerClientOriginatedMessage *)message
       state:(iTermFileDescriptorMultiClientState *)state
    callback:(iTermCallback<id, NSNumber *> *)callback {
    DLog(@"begin");
    if (state.writeFD < 0) {
        DLog(@"no write fd");
        [callback invokeWithObject:@NO];
        return;
    }

    iTermClientServerProtocolMessage clientServerProtocolMessage;
    iTermClientServerProtocolMessageInitialize(&clientServerProtocolMessage);
    if (iTermMultiServerProtocolEncodeMessageFromClient(message, &clientServerProtocolMessage)) {
        DLog(@"Failed to encode message from client");
        iTermMultiServerProtocolLogMessageFromClient(message);
        [callback invokeWithObject:@NO];
        iTermClientServerProtocolMessageFree(&clientServerProtocolMessage);
        return;
    }

    DLog(@"Encoded message from from client");
    iTermMultiServerProtocolLogMessageFromClient(message);

    // 0 length messages are indistinguishable from EOF.
    assert(clientServerProtocolMessage.ioVectors[0].iov_len != 0);

    NSMutableData *data = [NSMutableData data];
    size_t length = clientServerProtocolMessage.ioVectors[0].iov_len;
    char temp[sizeof(length)];
    memmove(temp, &length, sizeof(length));
    [data appendBytes:temp length:sizeof(temp)];
    [data appendBytes:clientServerProtocolMessage.ioVectors[0].iov_base
               length:length];
    iTermClientServerProtocolMessageFree(&clientServerProtocolMessage);

    DLog(@"Will send %@ byte header plus %@ byte payload, totaling %@ bytes",
         @(sizeof(temp)), @(length), @(data.length));
#if BETA
    HexDump([data subdataFromOffset:sizeof(temp)]);
#endif

    __weak __typeof(self) weakSelf = self;
    [state whenWritable:^(iTermFileDescriptorMultiClientState * _Nullable state) {
        DLog(@"called back");
        [weakSelf tryWrite:data
                     state:state
                  callback:callback];
    }];

}

// Write the entirety of data, then run the callback.
// This may take many async writes. It is always called from a whenWritable:
// block which ensures writes will be consecutive.
- (void)tryWrite:(NSData *)data
           state:(iTermFileDescriptorMultiClientState *)state
        callback:(iTermCallback<id, NSNumber *> *)callback {
    assert(data.length > 0);
    if (state.writeFD < 0) {
        [callback invokeWithObject:@NO];
        return;
    }
    errno = 0;
    DLog(@"Try to write %@ bytes", @(data.length));
    const ssize_t bytesWritten = iTermFileDescriptorClientWrite(state.writeFD,
                                                                data.bytes,
                                                                data.length);
    const NSInteger dataLength = data.length;
    const int savedErrno = errno;
    ITAssertWithMessage(bytesWritten <= dataLength, @"Data length is %@ but wrote %@. errno is %d",  @(dataLength), @(bytesWritten), savedErrno);
    DLog(@"Wrote %@/%@ error=%s", @(bytesWritten), @(dataLength), strerror(savedErrno));
    if (bytesWritten < 0 && errno != EAGAIN) {
        DLog(@"Write failed to %@: %s", _socketPath, strerror(errno));
        [callback invokeWithObject:@NO];
        return;
    }
    if (bytesWritten == 0) {
        DLog(@"EOF on write fd");
        [callback invokeWithObject:@NO];
        [self closeWithState:state];
        return;
    }

    if (bytesWritten == dataLength) {
        [callback invokeWithObject:@YES];
        return;
    }

    DLog(@"Queue attempt to write in the future.");
    __weak __typeof(self) weakSelf = self;
    [state whenWritable:^(iTermFileDescriptorMultiClientState * _Nullable state) {
        ITAssertWithMessage(bytesWritten <= dataLength, @"Data length is %@ but wrote %@.",
                            @(dataLength), @(bytesWritten));
        [weakSelf tryWrite:[data subdataFromOffset:MAX(0, bytesWritten)]  // NOTE: bytesWritten can be negative if we get EAGAIN
                     state:state
                  callback:callback];
    }];
}

#pragma mark - Error Helpers

- (NSError *)forkError {
    return [NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                               code:iTermFileDescriptorMultiClientErrorCodeForkFailed
                           userInfo:nil];
}

- (NSError *)connectionLostError {
    return [NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                               code:iTermFileDescriptorMultiClientErrorCodeConnectionLost
                           userInfo:nil];
}

- (NSError *)waitError:(int)errorNumber {
    iTermFileDescriptorMultiClientErrorCode code = iTermFileDescriptorMultiClientErrorCodeUnknown;
    switch (errorNumber) {
        case 2:
            code = iTermFileDescriptorMultiClientErrorAlreadyWaited;
            break;
        case 1:
            code = iTermFileDescriptorMultiClientErrorCodePreemptiveWaitResponse;
            break;
        case 0:
            return nil;
        case -1:
            code = iTermFileDescriptorMultiClientErrorCodeNoSuchChild;
            break;
        case -2:
            code = iTermFileDescriptorMultiClientErrorCodeCanNotWait;
            break;
    }
    return [NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                               code:code
                           userInfo:nil];
}

- (NSError *)ioError {
    return [NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                               code:iTermFileDescriptorMultiClientErrorIO
                           userInfo:nil];
}

- (NSError *)protocolError {
    return [NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                               code:iTermFileDescriptorMultiClientErrorProtocolError
                           userInfo:nil];
}

@end
