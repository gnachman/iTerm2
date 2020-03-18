//
//  iTermFileDescriptorMultiClient.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/9/19.
//

#import "iTermFileDescriptorMultiClient.h"
#import "iTermFileDescriptorMultiClient+MRR.h"

#import "DebugLogging.h"
#import "iTermDefer.h"
#import "iTermFileDescriptorServer.h"
#import "iTermResult.h"
#import "iTermThreadSafety.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

#include <syslog.h>
#include <sys/un.h>

NSString *const iTermFileDescriptorMultiClientErrorDomain = @"iTermFileDescriptorMultiClientErrorDomain";

@interface iTermMultiServerServerOriginatedMessageBox: NSObject
@property (nonatomic) iTermMultiServerServerOriginatedMessage message;
@end

@implementation iTermMultiServerServerOriginatedMessageBox
- (instancetype)initWithMessage:(iTermMultiServerServerOriginatedMessage)message {
    self = [super init];
    if (self) {
        _message = message;
    }
    return self;
}
- (void)dealloc {
    iTermMultiServerServerOriginatedMessageFree(&_message);
}
@end

@interface iTermClientServerProtocolMessageBox: NSObject
@property (nonatomic) iTermClientServerProtocolMessage message;
@property (nonatomic, readonly) iTermMultiServerServerOriginatedMessageBox *decoded;
- (instancetype)initWithMessage:(iTermClientServerProtocolMessage)message;
@end

@implementation iTermClientServerProtocolMessageBox
+ (instancetype)withFactory:(BOOL (^)(iTermClientServerProtocolMessage *messagePtr))factory {
    iTermClientServerProtocolMessageBox *box = [[iTermClientServerProtocolMessageBox alloc] init];
    memset(&box->_message, 0, sizeof(box->_message));
    if (!factory(&box->_message)) {
        return nil;
    }
    return box;
}
- (instancetype)initWithMessage:(iTermClientServerProtocolMessage)message {
    self = [super init];
    if (self) {
        _message = message;
    }
    return self;
}
- (iTermMultiServerServerOriginatedMessageBox *)decoded {
    iTermMultiServerServerOriginatedMessage decodedMessage;
    const int status = iTermMultiServerProtocolParseMessageFromServer(&_message, &decodedMessage);
    if (status) {
        return nil;
    }
    return [[iTermMultiServerServerOriginatedMessageBox alloc] initWithMessage:decodedMessage];
}
- (void)dealloc {
    iTermClientServerProtocolMessageFree(&_message);
}
@end

@interface iTermFileDescriptorMultiClientPendingLaunch: NSObject
@property (nonatomic, readonly) iTermMultiServerRequestLaunch launchRequest;
// replaces completion
@property (nonatomic, readonly) iTermMultiClientLaunchCallback *launchCallback;

- (instancetype)initWithRequest:(iTermMultiServerRequestLaunch)request
                       callback:(iTermMultiClientLaunchCallback *)callback
                         thread:(iTermThread *)thread NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)invalidate;
@end

@implementation iTermFileDescriptorMultiClientPendingLaunch {
    BOOL _invalid;
    iTermMultiServerRequestLaunch _launchRequest;
    iTermThreadChecker *_checker;
}

- (instancetype)initWithRequest:(iTermMultiServerRequestLaunch)request
                     callback:(iTermMultiClientLaunchCallback *)callback
                         thread:(iTermThread *)thread {
    self = [super init];
    if (self) {
        _launchRequest = request;
        _launchCallback = callback;
        _checker = [[iTermThreadChecker alloc] initWithThread:thread];
    }
    return self;
}

- (void)invalidate {
    [_checker check];
    _invalid = YES;
    memset(&_launchRequest, 0, sizeof(_launchRequest));
}

- (iTermMultiServerRequestLaunch)launchRequest {
    [_checker check];
    assert(!_invalid);
    return _launchRequest;
}

@end

@class iTermFileDescriptorMultiClientState;
@interface iTermFileDescriptorMultiClientState: iTermSynchronizedState<iTermFileDescriptorMultiClientState *>
@property (nonatomic) int readFD;
@property (nonatomic) int writeFD;
@property (nonatomic) pid_t serverPID;
@property (nonatomic, readonly) NSMutableArray<iTermFileDescriptorMultiClientChild *> *children;
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, iTermFileDescriptorMultiClientPendingLaunch *> *pendingLaunches;
@end

@implementation iTermFileDescriptorMultiClientState
- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super initWithQueue:queue];
    if (self) {
        _children = [NSMutableArray array];
        _pendingLaunches = [NSMutableDictionary dictionary];
        _readFD = -1;
        _writeFD = -1;
        _serverPID = -1;
    }
    return self;
}
@end

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

#pragma mark - APIs

- (pid_t)serverPID {
    __block pid_t pid;
    [_thread dispatchSync:^(iTermFileDescriptorMultiClientState * _Nullable state) {
        pid = state.serverPID;
    }];
    return pid;
}

- (void)attachOrLaunchServerWithCallback:(iTermCallback<id, NSNumber *> *)callback {
    [_thread dispatchAsync:^(iTermFileDescriptorMultiClientState * _Nonnull state) {
        [self attachOrLaunchServerWithState:state
                                   callback:callback];
    }];
}

- (void)attachWithCallback:(iTermCallback<id, NSNumber *> *)callback {
    [_thread dispatchAsync:^(iTermFileDescriptorMultiClientState *state) {
        if ([self tryAttachWithState:state] != iTermFileDescriptorMultiClientAttachStatusSuccess) {
            [callback invokeWithObject:@NO];
            return;
        }
        [self handshakeWithState:state callback:callback];
    }];
}

- (void)launchChildWithExecutablePath:(const char *)path
                                 argv:(const char **)argv
                          environment:(const char **)environment
                                  pwd:(const char *)pwd
                             ttyState:(iTermTTYState *)ttyStatePtr
                             callback:(iTermMultiClientLaunchCallback *)callback {
    [_thread dispatchSync:^(iTermFileDescriptorMultiClientState * _Nullable state) {
        [self launchChildWithExecutablePath:path
                                       argv:argv
                                environment:environment
                                        pwd:pwd
                                   ttyState:ttyStatePtr
                                      state:state
                                   callback:callback];
    }];
}

#pragma mark - Private Methods

- (void)attachOrLaunchServerWithState:(iTermFileDescriptorMultiClientState *)state
                             callback:(iTermCallback<id, NSNumber *> *)callback {
    [state check];
    switch ([self tryAttachWithState:state]) {
        case iTermFileDescriptorMultiClientAttachStatusSuccess:
            NSLog(@"Attached to %@. Will handshake.", _socketPath);
            [self handshakeWithState:state callback:callback];
            return;

        case iTermFileDescriptorMultiClientAttachStatusConnectFailed:
            NSLog(@"Connection failed to %@. Will launch..", _socketPath);
            [self launchAndHandshakeWithState:state callback:callback];
            return;

        case iTermFileDescriptorMultiClientAttachStatusFatalError:
            NSLog(@"Fatal error attaching to %@.", _socketPath);
            assert(state.readFD < 0);
            if (state.writeFD >= 0) {
                close(state.writeFD);
                state.writeFD = -1;
            }
            [callback invokeWithObject:@NO];
            return;
    }
}

- (void)launchAndHandshakeWithState:(iTermFileDescriptorMultiClientState *)state
                           callback:(iTermCallback<id, NSNumber *> *)callback {
    assert(state.readFD < 0);
    assert(state.writeFD < 0);

    if (![self launchWithState:state]) {
        assert(state.readFD < 0);
        assert(state.writeFD < 0);
        [callback invokeWithObject:@NO];
        return;
    }

    [self handshakeWithState:state callback:callback];
}

- (void)handshakeWithState:(iTermFileDescriptorMultiClientState *)state
                  callback:(iTermCallback<id, NSNumber *> *)callback {
    // Just launched the server. Now handshake with it.
    assert(state.readFD >= 0);
    assert(state.writeFD >= 0);
    NSLog(@"Handshake with %@", _socketPath);
    iTermCallback<id, NSNumber *> *innerCallback =
    [_thread newCallbackWithWeakTarget:self
                              selector:@selector(handshakeDidCompleteWithState:ok:userInfo:)
                              userInfo:callback];
    __weak __typeof(self) weakSelf = self;

    [self handshakeWithState:state
                    callback:innerCallback
         childDiscoveryBlock:^(iTermFileDescriptorMultiClientState *state,
                               iTermMultiServerReportChild *report) {
        [weakSelf didDiscoverChild:report state:state];
    }];
}

// Called after all children are reported during handshake.
- (void)handshakeDidCompleteWithState:(iTermFileDescriptorMultiClientState *)state
                                   ok:(NSNumber *)handshakeOK
                             userInfo:(id)userInfo {
    NSLog(@"Handshake completed for %@", _socketPath);
    iTermCallback<id, NSNumber *> *callback = [iTermCallback forceCastFrom:userInfo];
    if (!handshakeOK.boolValue) {
        NSLog(@"HANDSHAKE FAILED FOR %@", _socketPath);
        [self closeWithState:state];
    }
    [callback invokeWithObject:handshakeOK];
}

// Called during handshake as children are reported.
- (void)didDiscoverChild:(iTermMultiServerReportChild *)report
                   state:(iTermFileDescriptorMultiClientState *)state {
    iTermFileDescriptorMultiClientChild *child =
    [[iTermFileDescriptorMultiClientChild alloc] initWithReport:report
                                                         thread:self->_thread];
    [self addChild:child state:state];
}

- (void)closeWithState:(iTermFileDescriptorMultiClientState *)state {
    NSLog(@"CLOSE %@", _socketPath);
    assert(state.readFD >= 0);
    assert(state.writeFD >= 0);

    close(state.readFD);
    close(state.writeFD);

    state.readFD = -1;
    state.writeFD = -1;

    [self.delegate fileDescriptorMultiClientDidClose:self];
}

- (void)addChild:(iTermFileDescriptorMultiClientChild *)child
           state:(iTermFileDescriptorMultiClientState *)state {
    [state.children addObject:child];
    [self.delegate fileDescriptorMultiClient:self didDiscoverChild:child];
}

- (void)readWithState:(iTermFileDescriptorMultiClientState *)state
             callback:(iTermCallback<id, iTermResult<iTermMultiServerServerOriginatedMessageBox *> *> *)callback {
    int readFD = state.readFD;
    iTermThread *thread = _thread;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int fds[1] = { readFD };
        int results[1] = { 0 };
        NSLog(@"Readloop: waiting for %@", self->_socketPath);
        iTermSelect(fds, sizeof(fds) / sizeof(*fds), results, YES);
        NSLog(@"Readloop: select woke for %@", self->_socketPath);
        [thread dispatchAsync:^(iTermFileDescriptorMultiClientState *state) {
            if (state.readFD < 0) {
                NSLog(@"Readloop: IO error for %@", self->_socketPath);
                [callback invokeWithObject:[iTermResult withError:self.ioError]];
                return;
            }
            [callback invokeWithObject:[self resultByReadingAndDecodingMessageWithState:state]];
        }];
    });
}

- (iTermResult<iTermMultiServerServerOriginatedMessageBox *> *)resultByReadingAndDecodingMessageWithState:(iTermFileDescriptorMultiClientState *)state {
    NSLog(@"Decoding message from %@", _socketPath);
    if (state.readFD < 0) {
        NSLog(@"Decoding: FD already closed for %@", _socketPath);
        return [iTermResult withError:self.ioError];
    }
    iTermClientServerProtocolMessageBox *encodedBox =
    [iTermClientServerProtocolMessageBox withFactory:^BOOL(iTermClientServerProtocolMessage *messagePtr) {
        assert(state.readFD >= 0);
        return iTermMultiServerRecv(state.readFD, messagePtr) == 0;
    }];

    if (!encodedBox) {
        NSLog(@"Decoding: recv failed for %@", _socketPath);
        return [iTermResult withError:self.protocolError];
    }

    iTermMultiServerServerOriginatedMessageBox *decodedBox = encodedBox.decoded;
    if (!decodedBox) {
        NSLog(@"Decoding: decode failed for %@", _socketPath);
        return [iTermResult withError:self.protocolError];
    }

    return [iTermResult withObject:decodedBox];
}

- (BOOL)send:(iTermMultiServerClientOriginatedMessage *)message
       state:(iTermFileDescriptorMultiClientState *)state {
    if (state.writeFD < 0) {
        return NO;
    }

    iTermClientServerProtocolMessageBox *box =
    [iTermClientServerProtocolMessageBox withFactory:^BOOL(iTermClientServerProtocolMessage *obj) {
        iTermClientServerProtocolMessageInitialize(obj);
        if (iTermMultiServerProtocolEncodeMessageFromClient(message, obj)) {
            return NO;
        }
        return YES;
    }];

    if (!box) {
        return NO;
    }

    errno = 0;
    const ssize_t bytesWritten = iTermFileDescriptorClientWrite(state.writeFD,
                                                                box.message.ioVectors[0].iov_base,
                                                                box.message.ioVectors[0].iov_len);

    return bytesWritten > 0;
}

- (BOOL)sendHandshakeRequestWithState:(iTermFileDescriptorMultiClientState *)state {
    iTermMultiServerClientOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeHandshake,
        .payload = {
            .handshake = {
                .maximumProtocolVersion = iTermMultiServerProtocolVersion1
            }
        }
    };
    return [self send:&message state:state];
}

- (void)readHandshakeResponseWithState:(iTermFileDescriptorMultiClientState *)state
                            completion:(void (^)(iTermFileDescriptorMultiClientState *state,
                                                 BOOL ok,
                                                 int numberOfChildren,
                                                 pid_t pid))completion {
    NSLog(@"Read handshake response for %@", _socketPath);
    [self readWithState:state callback:[_thread newCallbackWithBlock:^(id  _Nonnull state,
                                                                       iTermResult<iTermMultiServerServerOriginatedMessageBox *> *result) {
        [result handleObject:^(iTermMultiServerServerOriginatedMessageBox * _Nonnull boxedMessage) {
            NSLog(@"Got a valid handshake response for %@", self->_socketPath);
            if (boxedMessage.message.type != iTermMultiServerRPCTypeHandshake) {
                completion(state, NO, 0, -1);
                return;
            }
            if (boxedMessage.message.payload.handshake.protocolVersion != iTermMultiServerProtocolVersion1) {
                completion(state, NO, 0, -1);
                return;
            }
            completion(state,
                       YES,
                       boxedMessage.message.payload.handshake.numChildren,
                       boxedMessage.message.payload.handshake.pid);
        } error:^(NSError * _Nonnull error) {
            NSLog(@"FAILED: Invalid handshake response for %@", self->_socketPath);
            completion(state, NO, 0, -1);
        }];
    }]];
}

- (void)readInitialChildReports:(int)numberOfChildren
                          state:(iTermFileDescriptorMultiClientState *)state
                          block:(void (^)(iTermFileDescriptorMultiClientState *state, iTermMultiServerReportChild *))block
                     completion:(void (^)(iTermFileDescriptorMultiClientState *state, BOOL ok))completion {
    NSLog(@"Read initial child reports (%@) for %@", @(numberOfChildren), _socketPath);
    if (numberOfChildren == 0) {
        NSLog(@"Have no children for %@", _socketPath);
        completion(state, YES);
        return;
    }
    __weak __typeof(self) weakSelf = self;
    [self readWithState:state
               callback:[_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *state,
                                                        iTermResult<iTermMultiServerServerOriginatedMessageBox *> *result) {
        [result handleObject:^(iTermMultiServerServerOriginatedMessageBox * _Nonnull box) {
            __strong __typeof(self) strongSelf = weakSelf;
            NSLog(@"Read a child report for %@", strongSelf->_socketPath);
            if (!strongSelf) {
                completion(state, NO);
                return;
            }
            if (box.message.type != iTermMultiServerRPCTypeReportChild) {
                NSLog(@"Unexpected message type when reading child reports for %@", strongSelf->_socketPath);
                completion(state, NO);
                return;
            }
            iTermMultiServerServerOriginatedMessage message = box.message;
            block(state, &message.payload.reportChild);
            const BOOL foundLast = box.message.payload.reportChild.isLast;
            if (!foundLast) {
                [strongSelf->_thread dispatchAsync:^(iTermFileDescriptorMultiClientState * _Nullable state) {
                    NSLog(@"Want another child report for %@", strongSelf->_socketPath);
                    [strongSelf readInitialChildReports:numberOfChildren - 1
                                                  state:state
                                                  block:block
                                             completion:completion];
                }];
                return;
            }
            NSLog(@"Got last child report for %@", strongSelf->_socketPath);
            completion(state, YES);
        } error:^(NSError * _Nonnull error) {
            completion(state, NO);
        }];
    }]];
}

// TODO: Make this async if it's really necessary. It's going to be difficult.
- (void)handshakeWithState:(iTermFileDescriptorMultiClientState *)state
                  callback:(iTermCallback<id, NSNumber *> *)callback
       childDiscoveryBlock:(void (^)(iTermFileDescriptorMultiClientState *state, iTermMultiServerReportChild *))block {
    assert(state.readFD >= 0);
    assert(state.writeFD >= 0);

    NSLog(@"Send handshake request for %@", _socketPath);
    if (![self sendHandshakeRequestWithState:state]) {
        NSLog(@"FAILED: Send handshake request for %@", _socketPath);
        [callback invokeWithObject:@NO];
        return;
    }

    [self readHandshakeResponseWithState:state completion:^(iTermFileDescriptorMultiClientState *state, BOOL ok, int numberOfChildren, pid_t pid) {
        if (!ok) {
            [callback invokeWithObject:@NO];
            return;
        }
        state.serverPID = pid;
        [self readInitialChildReports:numberOfChildren
                                state:state
                                block:block
                           completion:^(iTermFileDescriptorMultiClientState *state, BOOL ok) {
            NSLog(@"Done reading child reports for %@ with ok=%@", self->_socketPath, @(ok));
            if (!ok) {
                [callback invokeWithObject:@NO];
                return;
            }

            // Ensure the completion callback runs before the read loop starts producing events.
            [callback invokeWithObject:@YES];
            [self enterReadLoop];
        }];
    }];
}

- (void)enterReadLoop {
    [self->_thread dispatchAsync:^(iTermFileDescriptorMultiClientState *state) {
        [self readLoopWithState:state];
    }];
}

// This is copypasta from iTermFileDescriptorClient.c's iTermFileDescriptorClientConnect()
// NOTE: Sets _readFD and_writeFD as a side-effect.
// TODO: Make this async if it's really necessary. It's going to be difficult.
- (iTermFileDescriptorMultiClientAttachStatus)tryAttachWithState:(iTermFileDescriptorMultiClientState *)state {
    NSLog(@"tryAttachWithState(%@): Try attach", _socketPath);
    [state check];
    assert(state.readFD < 0);
    int temp = -1;
    iTermFileDescriptorMultiClientAttachStatus status = iTermConnectToUnixDomainSocket(_socketPath.UTF8String, &temp);
    state.readFD = temp;
    if (status != iTermFileDescriptorMultiClientAttachStatusSuccess) {
        // Server dead or already connected.
        NSLog(@"tryAttachWithState(%@): Server dead or already connected", _socketPath);
        return status;
    }
    iTermClientServerProtocolMessage message;
    iTermClientServerProtocolMessageInitialize(&message);
    temp = state.writeFD;

    int readStatus = iTermMultiServerRecv(state.readFD, &message);
    NSLog(@"Recv of initial file descriptor for %@ success=%@", _socketPath, @(!readStatus));
    if (!readStatus) {
        readStatus = iTermMultiServerProtocolGetFileDescriptor(&message, &temp);
        NSLog(@"Extract file descriptor for %@ success=%@", _socketPath, @(!readStatus));
    }
    if (readStatus) {
        close(state.readFD);
        state.readFD = -1;
        // You can get here if the server crashes right after accepting the connection. It can
        // also happen if the server already has a connected client and rejects.
        NSLog(@"tryAttachWithState(%@): Fatal error (see above)", _socketPath);
        return iTermFileDescriptorMultiClientAttachStatusFatalError;
    }
    state.writeFD = temp;
    NSLog(@"tryAttachWithState(%@): Success", _socketPath);
    return iTermFileDescriptorMultiClientAttachStatusSuccess;
}

- (BOOL)launchWithState:(iTermFileDescriptorMultiClientState *)state {
    assert(state.readFD < 0);

    NSString *executable = [[NSBundle bundleForClass:self.class] pathForAuxiliaryExecutable:@"iTermServer"];
    assert(executable);

    int readFD = -1;
    int writeFD = -1;
    iTermForkState forkState = [self launchWithSocketPath:_socketPath
                                               executable:executable
                                                   readFD:&readFD
                                                  writeFD:&writeFD];
    if (forkState.pid < 0) {
        return NO;
    }
    assert(readFD >= 0);
    assert(writeFD >= 0);
    state.readFD = readFD;
    state.writeFD = writeFD;

    return YES;
}

static int LengthOfNullTerminatedPointerArray(const void **array) {
    int i = 0;
    while (array[i]) {
        i++;
    }
    return i;
}

static long long MakeUniqueID(void) {
    long long result = arc4random_uniform(0xffffffff);
    result <<= 32;
    result |= arc4random_uniform(0xffffffff);;
    return result;
}

// Called on job manager's queue via [self launchChildWithExecutablePath:…]
- (iTermMultiServerClientOriginatedMessage)copyLaunchRequest:(iTermMultiServerClientOriginatedMessage)original {
    assert(original.type == iTermMultiServerRPCTypeLaunch);

    // Encode and decode the message so we can have our own copy of it.
    iTermClientServerProtocolMessage temp;
    iTermClientServerProtocolMessageInitialize(&temp);

    {
        const int status = iTermMultiServerProtocolEncodeMessageFromClient(&original, &temp);
        assert(status == 0);
    }

    iTermMultiServerClientOriginatedMessage messageCopy;
    {
        const int status = iTermMultiServerProtocolParseMessageFromClient(&temp, &messageCopy);
        assert(status == 0);
    }

    return messageCopy;
}

- (void)launchChildWithExecutablePath:(const char *)path
                                 argv:(const char **)argv
                          environment:(const char **)environment
                                  pwd:(const char *)pwd
                             ttyState:(iTermTTYState *)ttyStatePtr
                                state:(iTermFileDescriptorMultiClientState *)state
                             callback:(iTermMultiClientLaunchCallback *)callback {
    const long long uniqueID = MakeUniqueID();
    iTermMultiServerClientOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeLaunch,
        .payload = {
            .launch = {
                .path = path,
                .argv = argv,
                .argc = LengthOfNullTerminatedPointerArray((const void **)argv),
                .envp = environment,
                .envc = LengthOfNullTerminatedPointerArray((const void **)environment),
                .columns = ttyStatePtr->win.ws_col,
                .rows = ttyStatePtr->win.ws_row,
                .pixel_width = ttyStatePtr->win.ws_xpixel,
                .pixel_height = ttyStatePtr->win.ws_ypixel,
                .isUTF8 = !!(ttyStatePtr->term.c_iflag & IUTF8),
                .pwd = pwd,
                .uniqueId = uniqueID
            }
        }
    };
    if (![self send:&message state:state]) {
        [callback invokeWithObject:[iTermResult withError:[self connectionLostError]]];
        return;
    }

    iTermMultiServerClientOriginatedMessage messageCopy = [self copyLaunchRequest:message];

    NSLog(@"Add pending launch %@ for %@", @(uniqueID), _socketPath);
    state.pendingLaunches[@(uniqueID)] =
    [[iTermFileDescriptorMultiClientPendingLaunch alloc] initWithRequest:messageCopy.payload.launch
                                                                callback:callback
                                                                  thread:_thread];
}

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
    if (![self send:&message state:state]) {
        [self closeWithState:state];
        [callback invokeWithObject:[iTermResult withError:[self connectionLostError]]];
        return;
    }
    __weak __typeof(child) weakChild = child;
    child.waitCallback = [_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *_Nonnull state,
                                                         iTermResult<NSNumber *> *waitResult) {
        [waitResult handleObject:
         ^(NSNumber * _Nonnull statusNumber) {
            NSLog(@"wait for %@ returned termination status %@", @(child.pid), statusNumber);
            [weakChild setTerminationStatus:statusNumber.intValue];
            [callback invokeWithObject:waitResult];
        }
                           error:
         ^(NSError * _Nonnull error) {
            NSLog(@"wait for %@ returned error %@", @(child.pid), error);
            [callback invokeWithObject:waitResult];
        }];
    }];
}

- (void)readLoopWithState:(iTermFileDescriptorMultiClientState *)state {
    NSLog(@"readloop(%@): read", _socketPath);
    [self readWithState:state callback:[_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *state,
                                                                       iTermResult<iTermMultiServerServerOriginatedMessageBox *> *result) {
        [result handleObject:^(iTermMultiServerServerOriginatedMessageBox * _Nonnull object) {
            [self dispatch:object
                     state:state];
        } error:^(NSError * _Nonnull error) {
            if (state.readFD >= 0 && state.writeFD >= 0) {
                [self closeWithState:state];
            }
        }];
        if (state.readFD >= 0 && state.writeFD >= 0) {
            [self enterReadLoop];
        }
    }]];
}

// Called on self.queue from handleTermination: and handleWait:
- (iTermFileDescriptorMultiClientChild *)childWithPID:(pid_t)pid
                                                state:(iTermFileDescriptorMultiClientState *)state {
    return [state.children objectPassingTest:^BOOL(iTermFileDescriptorMultiClientChild *element, NSUInteger index, BOOL *stop) {
        return element.pid == pid;
    }];
}

// Called on self.queue from dispatch:
- (void)handleWait:(iTermMultiServerResponseWait)wait
             state:(iTermFileDescriptorMultiClientState *)state {
    NSLog(@"handleWait for socket %@ pid %@ with error %@, status %@",
          _socketPath, @(wait.pid), @(wait.errorNumber), @(wait.status));
        iTermFileDescriptorMultiClientChild *child = [self childWithPID:wait.pid state:state];
    iTermResult<NSNumber *> *result;
    if (wait.errorNumber) {
        result = [iTermResult withError:[self waitError:wait.errorNumber]];
    } else {
        result = [iTermResult withObject:@(wait.status)];
    }
    [child.waitCallback invokeWithObject:result];
    child.waitCallback = nil;
}

- (void)handleLaunch:(iTermMultiServerResponseLaunch)launch
               state:(iTermFileDescriptorMultiClientState *)state {
    NSLog(@"handleLaunch: unique ID %@ for %@", @(launch.uniqueId), _socketPath);
    iTermFileDescriptorMultiClientPendingLaunch *pendingLaunch = state.pendingLaunches[@(launch.uniqueId)];
    if (!pendingLaunch) {
        ITBetaAssert(NO, @"No pending launch for %@ in %@", @(launch.uniqueId), state.pendingLaunches);
        return;
    }
    [state.pendingLaunches removeObjectForKey:@(launch.uniqueId)];

    if (launch.status != 0) {
        NSLog(@"handleLaunch: error status %@ for %@", @(launch.status), _socketPath);
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
    [self addChild:child state:state];
    NSLog(@"handleLaunch: Success for pid %@ from %@", @(launch.pid), _socketPath);
    [pendingLaunch.launchCallback invokeWithObject:[iTermResult withObject:child]];

    iTermMultiServerClientOriginatedMessage temp;
    temp.type = iTermMultiServerRPCTypeLaunch;
    temp.payload.launch = pendingLaunch.launchRequest;
    iTermMultiServerClientOriginatedMessageFree(&temp);
    [pendingLaunch invalidate];
}

// Runs on _queue
- (void)handleTermination:(iTermMultiServerReportTermination)termination
                    state:(iTermFileDescriptorMultiClientState *)state {
    NSLog(@"handleTermination for %@", _socketPath);
    iTermFileDescriptorMultiClientChild *child = [self childWithPID:termination.pid state:state];
    if (child) {
        [child didTerminate];
        [self.delegate fileDescriptorMultiClient:self childDidTerminate:child];
    }
}

// Runs on _queue
- (void)dispatch:(iTermMultiServerServerOriginatedMessageBox *)box
                  state:(iTermFileDescriptorMultiClientState *)state {
    NSLog(@"dispatch for %@", _socketPath);
    switch (box.message.type) {
        case iTermMultiServerRPCTypeWait:
            [self handleWait:box.message.payload.wait state:state];
            break;

        case iTermMultiServerRPCTypeLaunch:
            [self handleLaunch:box.message.payload.launch state:state];
            break;

        case iTermMultiServerRPCTypeTermination:
            [self handleTermination:box.message.payload.termination state:state];
            break;

        case iTermMultiServerRPCTypeHandshake:
        case iTermMultiServerRPCTypeReportChild:
            [self closeWithState:state];
            break;
    }
}

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
