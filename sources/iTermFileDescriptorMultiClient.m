//
//  iTermFileDescriptorMultiClient.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/9/19.
//

#import "iTermFileDescriptorMultiClient.h"
#import "iTermFileDescriptorMultiClient+MRR.h"

#import "DebugLogging.h"
#import "iTermFileDescriptorServer.h"
#import "iTermMalloc.h"
#import "iTermResult.h"
#import "iTermThreadSafety.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSObject+iTerm.h"

#include <syslog.h>
#include <sys/un.h>

#undef DLog
#define DLog NSLog

NSString *const iTermFileDescriptorMultiClientErrorDomain = @"iTermFileDescriptorMultiClientErrorDomain";

@interface iTermMultiServerMessage: NSObject
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly) NSNumber *fileDescriptor;

- (instancetype)initWithData:(NSData *)data fileDescriptor:(NSNumber *)fileDescriptor NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation iTermMultiServerMessage

- (instancetype)initWithData:(NSData *)data fileDescriptor:(NSNumber *)fileDescriptor {
    self = [super init];
    if (self) {
        _data = [data copy];
        _fileDescriptor = fileDescriptor;
    }
    return self;
}

@end

@interface iTermMultiServerMessageBuilder: NSObject
@property (nonatomic, readonly) iTermMultiServerMessage *message;
@property (nonatomic, readonly) NSInteger length;

- (void)appendBytes:(void *)bytes length:(NSInteger)length;
- (void)setFileDescriptor:(int)fileDescriptor;
@end

@implementation iTermMultiServerMessageBuilder {
    NSMutableData *_accumulator;
    NSNumber *_fileDescriptor;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _accumulator = [NSMutableData data];
    }
    return self;
}

- (void)appendBytes:(void *)bytes length:(NSInteger)length {
    [_accumulator appendBytes:bytes
                       length:length];
}

- (void)setFileDescriptor:(int)fileDescriptor {
    _fileDescriptor = @(fileDescriptor);
}

- (NSInteger)length {
    return _accumulator.length;
}

- (iTermMultiServerMessage *)message {
    return [[iTermMultiServerMessage alloc] initWithData:_accumulator
                                          fileDescriptor:_fileDescriptor];
}

@end

@interface iTermClientServerProtocolMessageBox: NSObject
@property (nonatomic) iTermMultiServerMessage *message;
@property (nonatomic, readonly) iTermMultiServerServerOriginatedMessage *decoded;

+ (instancetype)withMessage:(iTermMultiServerMessage *)message;
@end

@implementation iTermClientServerProtocolMessageBox {
    iTermClientServerProtocolMessage _protocolMessage;
    BOOL _haveDecodedMessage;
    iTermMultiServerServerOriginatedMessage _decodedMessage;
}

+ (instancetype)withMessage:(iTermMultiServerMessage *)message {
    iTermClientServerProtocolMessageBox *box = [[iTermClientServerProtocolMessageBox alloc] init];
    iTermClientServerProtocolMessageInitialize(&box->_protocolMessage);
    if (message.fileDescriptor) {
        box->_protocolMessage.controlBuffer.cm.cmsg_len = CMSG_LEN(sizeof(int));
        box->_protocolMessage.controlBuffer.cm.cmsg_level = SOL_SOCKET;
        box->_protocolMessage.controlBuffer.cm.cmsg_type = SCM_RIGHTS;
        *((int *)CMSG_DATA(&box->_protocolMessage.controlBuffer.cm)) = message.fileDescriptor.intValue;
    }
    iTermClientServerProtocolMessageEnsureSpace(&box->_protocolMessage, message.data.length);
    memmove(box->_protocolMessage.message.msg_iov[0].iov_base, message.data.bytes, message.data.length);
    box->_message = message;
    return box;
}

- (iTermMultiServerServerOriginatedMessage *)decoded {
    if (_haveDecodedMessage) {
        return &_decodedMessage;
    }
    const int status = iTermMultiServerProtocolParseMessageFromServer(&_protocolMessage, &_decodedMessage);
    if (status) {
        DLog(@"Failed to decode message from server with status %d", status);
        return nil;
    }
    _haveDecodedMessage = YES;
    DLog(@"Decoded message from server:");
    iTermMultiServerProtocolLogMessageFromServer(&_decodedMessage);
    return &_decodedMessage;
}

- (void)dealloc {
    iTermClientServerProtocolMessageFree(&_protocolMessage);
}
@end

@interface iTermFileDescriptorMultiClientPendingLaunch: NSObject
@property (nonatomic, readonly) iTermMultiServerRequestLaunch launchRequest;
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

- (void)whenWritable:(void (^)(iTermFileDescriptorMultiClientState *state))block;
- (void)whenReadable:(void (^)(iTermFileDescriptorMultiClientState *state))block;

@end

@implementation iTermFileDescriptorMultiClientState {
    dispatch_source_t _writeSource;
    NSMutableArray *_writeQueue;
    dispatch_source_t _readSource;
    NSMutableArray *_readQueue;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super initWithQueue:queue];
    if (self) {
        _children = [NSMutableArray array];
        _pendingLaunches = [NSMutableDictionary dictionary];
        _readFD = -1;
        _writeFD = -1;
        _serverPID = -1;
        _writeQueue = [NSMutableArray array];
        _readQueue = [NSMutableArray array];
    }
    return self;
}

- (void)setFileDescriptorNonblocking:(int)fd {
    const int flags = fcntl(fd, F_GETFL, 0);
    if (flags != -1) {
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
}

- (void)setWriteFD:(int)writeFD {
    if (writeFD >= 0) {
        [self setFileDescriptorNonblocking:writeFD];
    }
    const BOOL cancelWrites = (writeFD < 0 && _writeFD >= 0);
    _writeFD = writeFD;
    if (cancelWrites) {
        [self didBecomeWritable];
        assert(_writeQueue.count == 0);
    }
}

- (void)setReadFD:(int)readFD {
    if (readFD >= 0) {
        [self setFileDescriptorNonblocking:readFD];
    }
    const BOOL cancelReads = (readFD < 0 && _readFD >= 0);
    _readFD = readFD;
    if (cancelReads) {
        [self didBecomeReadable];
        assert(_readQueue.count == 0);
    }
}

- (void)whenReadable:(void (^)(iTermFileDescriptorMultiClientState *))block {
    assert(_readFD >= 0);
    [_readQueue addObject:[block copy]];
    if (_readSource) {
        return;
    }
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _readFD, 0, self.queue);
    if (!_readSource) {
        DLog(@"Failed to create dispatch source for read!");
        close(_readFD);
        _readFD = -1;
        return;
    }

    __weak __typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_readSource, ^{
        [weakSelf didBecomeReadable];
    });

    dispatch_resume(_readSource);
}

- (void)didBecomeReadable {
    NSArray *queue = [_readQueue copy];
    [_readQueue removeAllObjects];

    for (void (^block)(iTermFileDescriptorMultiClientState *) in queue) {
        if (_readQueue.count) {
            [_readQueue addObject:block];
        } else {
            block(self);
        }
    }
    if (_readQueue.count == 0 && _readSource != nil) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }
}

- (void)whenWritable:(void (^)(iTermFileDescriptorMultiClientState *state))block {
    assert(_writeFD >= 0);

    [_writeQueue addObject:[block copy]];
    if (_writeSource) {
        return;
    }
    _writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, _writeFD, 0, self.queue);
    if (!_writeSource) {
        DLog(@"Failed to create dispatch source for write!");
        close(_writeFD);
        _writeFD = -1;
        return;
    }

    __weak __typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_writeSource, ^{
        [weakSelf didBecomeWritable];
    });

    dispatch_resume(_writeSource);
}

- (void)didBecomeWritable {
    NSArray *queue = [_writeQueue copy];
    [_writeQueue removeAllObjects];

    for (void (^block)(iTermFileDescriptorMultiClientState *) in queue) {
        if (_writeQueue.count) {
            [_writeQueue addObject:block];
        } else {
            block(self);
        }
    }
    if (_writeQueue.count == 0 && _writeSource != nil) {
        dispatch_source_cancel(_writeSource);
        _writeSource = nil;
    }
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
    [_thread dispatchSync:^(iTermFileDescriptorMultiClientState * _Nullable state) {
        [self launchChildWithExecutablePath:path
                                       argv:argv
                                environment:environment
                                        pwd:pwd
                                   ttyState:ttyState
                                      state:state
                                   callback:callback];
    }];
}

#pragma mark - Private Methods

- (void)attachOrLaunchServerWithState:(iTermFileDescriptorMultiClientState *)state
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
        [strongSelf didAttachOrLaunchWithState:state status:statusNumber.integerValue callback:callback];
    }]];
}

- (void)didAttachOrLaunchWithState:(iTermFileDescriptorMultiClientState *)state
                            status:(iTermFileDescriptorMultiClientAttachStatus)status
                          callback:(iTermCallback<id, NSNumber *> *)callback {
    switch (status) {
        case iTermFileDescriptorMultiClientAttachStatusSuccess:
            DLog(@"Attached to %@. Will handshake.", _socketPath);
            [self handshakeWithState:state callback:callback];
            return;

        case iTermFileDescriptorMultiClientAttachStatusConnectFailed:
            DLog(@"Connection failed to %@. Will launch..", _socketPath);
            [self launchAndHandshakeWithState:state callback:callback];
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
    DLog(@"Handshake with %@", _socketPath);
    iTermCallback<id, NSNumber *> *innerCallback =
    [_thread newCallbackWithWeakTarget:self
                              selector:@selector(handshakeDidCompleteWithState:ok:userInfo:)
                              userInfo:callback];
    __weak __typeof(self) weakSelf = self;

    [self handshakeWithState:state
                    callback:innerCallback
         childDiscoveryBlock:^(iTermFileDescriptorMultiClientState *state,
                               iTermMultiServerReportChild *report) {
        // report must be consumed synchronously!
        [weakSelf didDiscoverChild:report state:state];
    }];
}

// Called after all children are reported during handshake.
- (void)handshakeDidCompleteWithState:(iTermFileDescriptorMultiClientState *)state
                                   ok:(NSNumber *)handshakeOK
                             userInfo:(id)userInfo {
    DLog(@"Handshake completed for %@", _socketPath);
    iTermCallback<id, NSNumber *> *callback = [iTermCallback forceCastFrom:userInfo];
    if (!handshakeOK.boolValue) {
        DLog(@"HANDSHAKE FAILED FOR %@", _socketPath);
        [self closeWithState:state];
    }
    [callback invokeWithObject:handshakeOK];
}

// Called during handshake as children are reported.
// report must be consumed synchronously!
- (void)didDiscoverChild:(iTermMultiServerReportChild *)report
                   state:(iTermFileDescriptorMultiClientState *)state {
    iTermFileDescriptorMultiClientChild *child =
    [[iTermFileDescriptorMultiClientChild alloc] initWithReport:report
                                                         thread:self->_thread];
    [self addChild:child state:state attached:NO];
}

- (void)closeWithState:(iTermFileDescriptorMultiClientState *)state {
    if (state.readFD < 0 && state.writeFD < 0) {
        DLog(@"Already closed %@, doing nothing", _socketPath);
        return;
    }
    DLog(@"CLOSE %@", _socketPath);

    close(state.readFD);
    close(state.writeFD);

    state.readFD = -1;
    state.writeFD = -1;

    [self.delegate fileDescriptorMultiClientDidClose:self];
}

- (void)addChild:(iTermFileDescriptorMultiClientChild *)child
           state:(iTermFileDescriptorMultiClientState *)state
        attached:(BOOL)attached {
    DLog(@"Add child %@ attached=%@", child, @(attached));
    [state.children addObject:child];
    if (!attached) {
        [self.delegate fileDescriptorMultiClient:self didDiscoverChild:child];
    }
}

- (void)appendDataFromMessage:(iTermClientServerProtocolMessage *)message
                           to:(NSMutableData *)accumulator {
    [accumulator appendBytes:message->message.msg_iov[0].iov_base
                      length:message->message.msg_iov[0].iov_len];
}

// Read a full message, which may contain a file desciptor.
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

- (void)readWithState:(iTermFileDescriptorMultiClientState *)state
               length:(NSInteger)length
             callback:(iTermCallback<id, iTermResult<iTermMultiServerMessage *> *> *)callback {
    iTermMultiServerMessageBuilder *builder = [[iTermMultiServerMessageBuilder alloc] init];
    [state whenReadable:^(iTermFileDescriptorMultiClientState *state) {
        [self partialReadWithState:state totalLength:length builder:builder callback:callback];
    }];
}

- (void)partialReadWithState:(iTermFileDescriptorMultiClientState *)state
                 totalLength:(NSInteger)totalLength
                     builder:(iTermMultiServerMessageBuilder *)builder
                    callback:(iTermCallback<id, iTermResult<iTermMultiServerMessage *> *> *)callback {
    DLog(@"Want to read %@ from %@", @(totalLength), _socketPath);

    if (state.readFD < 0) {
        DLog(@"readFD<0 for %@", _socketPath);
        [callback invokeWithObject:[iTermResult withError:self.ioError]];
        return;
    }

    iTermClientServerProtocolMessage message;
    const ssize_t bytesRead = iTermMultiServerReadMessage(state.readFD, &message, totalLength - builder.length);
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
    if (bytesRead == 0) {
        DLog(@"EOF %@", _socketPath);
        [callback invokeWithObject:[iTermResult withError:self.ioError]];
        return;
    }

    // If you're asked to read 0 bytes then it could be a file descriptor.
    if (message.controlBuffer.cm.cmsg_len == CMSG_LEN(sizeof(int)) &&
        message.controlBuffer.cm.cmsg_level == SOL_SOCKET &&
        message.controlBuffer.cm.cmsg_type == SCM_RIGHTS) {
        DLog(@"Got a file descriptor in message from %@", _socketPath);
        [builder setFileDescriptor:*((int *)CMSG_DATA(&message.controlBuffer.cm))];
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

static void HexDump(NSData *data) {
    char buffer[80];
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    int addr = 0;
    int offset = 0;
    DLog(@"- Begin hex dump of outbound message -");
    for (int i = 0; i < data.length; i++) {
        offset += sprintf(buffer + offset, "%02x ", bytes[i]);
        if (i % 16 == 0 && i > 0) {
            DLog(@"%04d  %s", addr, buffer);
            addr = i;
            offset = 0;
        }
    }
    if (offset > 0) {
        DLog(@"%04d  %s", addr, buffer);
    }
    DLog(@"- End hex dump of outbound message -");
}

- (void)send:(iTermMultiServerClientOriginatedMessage *)message
       state:(iTermFileDescriptorMultiClientState *)state
    callback:(iTermCallback<id, NSNumber *> *)callback {
    if (state.writeFD < 0) {
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

    if (clientServerProtocolMessage.ioVectors[0].iov_len == 0) {
        [callback invokeWithObject:@YES];
        return;
    }
    
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
    HexDump(data);

    __weak __typeof(self) weakSelf = self;
    [state whenWritable:^(iTermFileDescriptorMultiClientState * _Nullable state) {
        [weakSelf tryWrite:data
                     state:state
                  callback:callback];
    }];

}

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
    DLog(@"Wrote %@/%@", @(bytesWritten), @(data.length));
    if (bytesWritten < 0) {
        DLog(@"Write failed to %@: %s", _socketPath, strerror(errno));
        [callback invokeWithObject:@NO];
        return;
    }
    if (bytesWritten == data.length) {
        [callback invokeWithObject:@YES];
        return;
    }

    DLog(@"Queue attempt to write in the future.");
    __weak __typeof(self) weakSelf = self;
    [state whenWritable:^(iTermFileDescriptorMultiClientState * _Nullable state) {
        [weakSelf tryWrite:[data subdataFromOffset:bytesWritten]
                     state:state
                  callback:callback];
    }];
}

- (void)sendHandshakeRequestWithState:(iTermFileDescriptorMultiClientState *)state
                             callback:(iTermCallback<id, NSNumber *> *)callback {
    iTermMultiServerClientOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeHandshake,
        .payload = {
            .handshake = {
                .maximumProtocolVersion = iTermMultiServerProtocolVersion1
            }
        }
    };
    [self send:&message state:state callback:callback];
}

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
            if (boxedMessage.decoded->payload.handshake.protocolVersion != iTermMultiServerProtocolVersion1) {
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

- (void)handshakeWithState:(iTermFileDescriptorMultiClientState *)state
                  callback:(iTermCallback<id, NSNumber *> *)callback
       childDiscoveryBlock:(void (^)(iTermFileDescriptorMultiClientState *state, iTermMultiServerReportChild *))block {
    assert(state.readFD >= 0);
    assert(state.writeFD >= 0);

    DLog(@"Send handshake request for %@", _socketPath);
    __weak __typeof(self) weakSelf = self;
    [self sendHandshakeRequestWithState:state callback:[_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *state,
                                                                                       NSNumber *sendResult) {
        [weakSelf didSendHandshakeRequestWithSuccess:sendResult.boolValue
                                               state:state
                                            callback:callback
                                 childDiscoveryBlock:block];
    }]];
}

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

// This is copypasta from iTermFileDescriptorClient.c's iTermFileDescriptorClientConnect()
// NOTE: Sets _readFD and_writeFD as a side-effect.
// Result will be @(enum iTermFileDescriptorMultiClientAttachStatus).
- (void)tryAttachWithState:(iTermFileDescriptorMultiClientState *)state
                  callback:(iTermCallback<id, NSNumber *> *)callback {
    DLog(@"tryAttachWithState(%@): Try attach", _socketPath);
    [state check];
    assert(state.readFD < 0);

    // Connect to the socket. This gets us the reading file descriptor.
    int temp = -1;
    iTermFileDescriptorMultiClientAttachStatus status = iTermConnectToUnixDomainSocket(_socketPath.UTF8String, &temp);
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

static unsigned long long MakeUniqueID(void) {
    unsigned long long result = arc4random_uniform(0xffffffff);
    result <<= 32;
    result |= arc4random_uniform(0xffffffff);;
    return (long long)result;
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

// These C pointers live until the callback is run.
- (void)launchChildWithExecutablePath:(const char *)path
                                 argv:(const char **)argv
                          environment:(const char **)environment
                                  pwd:(const char *)pwd
                             ttyState:(iTermTTYState)ttyState
                                state:(iTermFileDescriptorMultiClientState *)state
                             callback:(iTermMultiClientLaunchCallback *)callback {
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
        const BOOL ok = result.boolValue;
        if (ok) {
            DLog(@"Wrote launch request successfully.");
            return;
        }

        DLog(@"Failed to write launch request.");
        [state.pendingLaunches removeObjectForKey:@(uniqueID)];
        [callback invokeWithObject:[iTermResult withError:[self connectionLostError]]];
    }]];
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

    __weak __typeof(child) weakChild = child;
    child.waitCallback = [_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *_Nonnull state,
                                                         iTermResult<NSNumber *> *waitResult) {
        [waitResult handleObject:
         ^(NSNumber * _Nonnull statusNumber) {
            DLog(@"wait for %@ returned termination status %@", @(child.pid), statusNumber);
            [weakChild setTerminationStatus:statusNumber.intValue];
            [callback invokeWithObject:waitResult];
        }
                           error:
         ^(NSError * _Nonnull error) {
            DLog(@"wait for %@ returned error %@", @(child.pid), error);
            [callback invokeWithObject:waitResult];
        }];
    }];

    __weak __typeof(self) weakSelf = self;
    [self send:&message state:state callback:[_thread newCallbackWithBlock:^(iTermFileDescriptorMultiClientState *state,
                                                                             NSNumber *value) {
        [weakSelf didWriteWaitRequestWithStatus:value.boolValue
                                          child:child
                                          state:state
                                       callback:callback];
    }]];
}

- (void)didWriteWaitRequestWithStatus:(BOOL)sendOK
                                child:(iTermFileDescriptorMultiClientChild *)child
                                state:(iTermFileDescriptorMultiClientState *)state
                             callback:(iTermCallback<id, iTermResult<NSNumber *> *> *)callback {
    if (sendOK) {
        return;
    }
    child.waitCallback = nil;
    DLog(@"Close client for %@ because of failed write", _socketPath);
    [self closeWithState:state];
    [callback invokeWithObject:[iTermResult withError:[self connectionLostError]]];
}

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
    DLog(@"handleWait for socket %@ pid %@ with error %@, status %@",
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

// launch must be consumed synchronously.
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

// Runs on _queue
- (void)handleTermination:(iTermMultiServerReportTermination)termination
                    state:(iTermFileDescriptorMultiClientState *)state {
    DLog(@"handleTermination for %@", _socketPath);
    iTermFileDescriptorMultiClientChild *child = [self childWithPID:termination.pid state:state];
    if (child) {
        [child didTerminate];
        [self.delegate fileDescriptorMultiClient:self childDidTerminate:child];
    }
}

// Runs on _queue
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
