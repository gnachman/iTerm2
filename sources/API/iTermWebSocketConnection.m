//
//  iTermWebSocketConnection.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermWebSocketConnection.h"
#import "DebugLogging.h"
#import "iTermAPIConnectionIdentifierController.h"
#import "iTermHTTPConnection.h"
#import "iTermWebSocketCookieJar.h"
#import "iTermWebSocketFrame.h"
#import "iTermWebSocketFrameBuilder.h"
#import "NSData+iTerm.h"

#import <CommonCrypto/CommonDigest.h>

static NSString *const kProtocolName = @"api.iterm2.com";
static const NSInteger kWebSocketVersion = 13;
NSString *const iTermWebSocketConnectionLibraryVersionTooOldString = @"Library version too old";

// SEE ALSO iTermMinimumPythonEnvironmentVersion
// NOTE: Modules older than 0.69 did not report too-old errors correctly.
//
// *WARNING*****************************************************************************************
// *WARNING* Think carefully before changing this. It will break existing full-environment scripts.*
// *WARNING*****************************************************************************************
//
static NSString *const iTermWebSocketConnectionMinimumPythonLibraryVersion = @"0.24";

// Backpressure limits to keep a misbehaving or malicious (but authenticated)
// peer from exhausting memory by flooding us with frames faster than we can
// process or the peer can drain our responses.
//
// Bound on how many inbound read chunks may be queued for parsing at once. When
// this many are in flight the reader stops draining the socket, engaging TCP
// flow control, until the parser catches up.
static const long iTermWebSocketMaxInFlightReadChunks = 16;
// Bound on how many pong frames may be submitted for writing but not yet flushed
// to the socket. A well-behaved peer drains pongs, so this count falls as writes
// flush. A peer that floods pings but stops reading fills the socket send buffer,
// pong writes stop flushing, and the count pins at the cap; exceeding it (see
// -sendControlResponseFrame:) means the peer is misbehaving, so we abort the
// connection. We deliberately do not block waiting for a slot: frame processing,
// including teardown, runs on _queue, so blocking it on a peer that never reads
// would make the connection un-abortable and pin an fd plus a worker thread.
static const NSInteger iTermWebSocketMaxOutstandingPongs = 256;

typedef NS_ENUM(NSUInteger, iTermWebSocketConnectionState) {
    iTermWebSocketConnectionStateConnecting,
    iTermWebSocketConnectionStateOpen,
    iTermWebSocketConnectionStateClosing,
    iTermWebSocketConnectionStateClosed
};


@implementation iTermWebSocketConnection {
    iTermHTTPConnection *_connection;
    iTermWebSocketConnectionState _state;
    iTermWebSocketFrame *_fragment;
    dispatch_queue_t _queue;
    iTermWebSocketFrameBuilder *_frameBuilder;
    // Limits the number of inbound read chunks queued on _queue for parsing.
    dispatch_semaphore_t _readBackpressureSemaphore;
    // Count of pong frames submitted for writing but not yet flushed. Only
    // touched on _queue (incremented when a pong is sent, decremented by that
    // write's flush callback, which also runs on _queue).
    NSInteger _outstandingPongs;
}

+ (instancetype)newWebSocketConnectionForRequest:(NSURLRequest *)request
                                      connection:(iTermHTTPConnection *)connection
                                          reason:(out NSString *__autoreleasing *)reason {
    if (![request.HTTPMethod isEqualToString:@"GET"]) {
        *reason = [NSString stringWithFormat:@"HTTP method %@ not accepted (must be GET)", request.HTTPMethod];
        return nil;
    }
    if (request.URL.path.length == 0) {
        *reason = @"Request had an empty path in the HTTP request";
        return nil;
    }
    NSDictionary<NSString *, NSString *> *headers = request.allHTTPHeaderFields;
    NSDictionary<NSString *, NSString *> *requiredValues =
        @{ @"upgrade": @"websocket",
           @"connection": @"Upgrade",
           @"sec-websocket-protocol": kProtocolName,
         };
    for (NSString *key in requiredValues) {
        if ([headers[key] caseInsensitiveCompare:requiredValues[key]] != NSOrderedSame) {
            *reason = [NSString stringWithFormat:@"Header %@ has value <%@> but I require <%@>", key, headers[key], requiredValues[key]];
            return nil;
        }
    }

    NSArray<NSString *> *requiredKeys =
        @[ @"sec-websocket-key",
           @"sec-websocket-version",
           @"host",
           @"origin" ];
    for (NSString *key in requiredKeys) {
        if ([headers[key] length] == 0) {
            *reason = [NSString stringWithFormat:@"Empty or missing value for required header %@", key];
            return nil;
        }
    }

    NSURL *originURL = [NSURL URLWithString:headers[@"origin"]];
    if (![originURL.host isEqualToString:@"localhost"]) {
        *reason = [NSString stringWithFormat:@"Origin's host is not localhost: is %@ (string value is %@)", originURL.host, headers[@"origin"]];
        return nil;
    }

    NSString *host = headers[@"host"];
    NSInteger colon = [host rangeOfString:@":" options:NSBackwardsSearch].location;
    if (colon != NSNotFound) {
        host = [host substringToIndex:colon];
    }
    NSArray<NSString *> *loopbackNames = @[ @"localhost", @"127.0.0.1", @"[::1]" ];
    if (![loopbackNames containsObject:host]) {
        *reason = [NSString stringWithFormat:@"Host header is %@, but must be localhost, 127.0.01, or [::1].", host];
        return nil;
    }

    NSString *version = headers[@"sec-websocket-version"];
    if ([version integerValue] < kWebSocketVersion) {
        *reason = [NSString stringWithFormat:@"sec-websocket-version of %@ is older than %@", version, @(kWebSocketVersion)];
        return nil;
    }

    BOOL authenticated = NO;
    NSString *cookie = headers[@"x-iterm2-cookie"];
    if (cookie) {
        if ([[iTermWebSocketCookieJar sharedInstance] consumeCookie:cookie]) {
            authenticated = YES;
        } else {
            *reason = [NSString stringWithFormat:@"x-iterm2-cookie of %@ not recognized", cookie];
            cookie = nil;
        }
    }

    {
        NSString *libver = headers[@"x-iterm2-library-version"];
        if (!libver) {
            *reason = @"The “x-iterm2-library-version” header was not set. You may need to update your Python runtime to a newer version.";
            return nil;
        }
        NSArray<NSString *> *parts = [libver componentsSeparatedByString:@" "];
        if (parts.count != 2) {
            *reason = [NSString stringWithFormat:@"The “x-iterm2-library-version” header was malformed: ”%@”", libver];
            return nil;
        }

        NSDictionary *minimums = @{ @"python": [NSDecimalNumber decimalNumberWithString:iTermWebSocketConnectionMinimumPythonLibraryVersion] };
        NSString *name = parts[0];
        NSDecimalNumber *min = minimums[name];
        NSDecimalNumber *version = [NSDecimalNumber decimalNumberWithString:parts[1]];
        NSComparisonResult result = [min compare:version];
        if (result == NSOrderedDescending) {
            *reason = [NSString stringWithFormat:@"%@. %@ library version reported as %@. Minimum supported by this version of iTerm2 is %@",
                       iTermWebSocketConnectionLibraryVersionTooOldString, name, version, min];
            return nil;
        }
    }
    
    RLog(@"Request validates as websocket upgrade request");
    iTermWebSocketConnection *conn = [[self alloc] initWithConnection:connection];
    if (conn) {
        conn->_preauthorized = authenticated;
        NSString *key = headers[@"x-iterm2-key"] ?: [[NSUUID UUID] UUIDString];
        conn->_key = [[iTermAPIConnectionIdentifierController sharedInstance] identifierForKey:key];
        conn->_advisoryName = headers[@"x-iterm2-advisory-name"];
    }
    return conn;
}

- (instancetype)initWithConnection:(iTermHTTPConnection *)connection {
    self = [super init];
    if (self) {
        _connection = connection;
        _queue = dispatch_queue_create("com.iterm2.websocket", NULL);
        _readBackpressureSemaphore = dispatch_semaphore_create(iTermWebSocketMaxInFlightReadChunks);
        _guid = [[NSUUID UUID] UUIDString];
    }
    return self;
}

// any queue
- (void)handleRequest:(NSURLRequest *)request completion:(void (^)(void))completion {
    dispatch_async(_queue, ^{
        [self reallyHandleRequest:request completion:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }];
    });
}

// queue
- (void)reallyHandleRequest:(NSURLRequest *)request completion:(void (^)(void))completion {
    DLog(@"Handling websocket request %@", request);
    ITAssertWithMessage(_state == iTermWebSocketConnectionStateConnecting, @"Request already handled");

    [self sendUpgradeResponseWithKey:request.allHTTPHeaderFields[@"sec-websocket-key"]
                             version:[request.allHTTPHeaderFields[@"sec-websocket-version"] integerValue]
                          completion:^(BOOL status) {
                              [self didUpgradeSuccessfully:status];
                              completion();
                          }];
}

// queue
- (void)didUpgradeSuccessfully:(BOOL)upgradeOK {
    if (!upgradeOK) {
        dispatch_async(_connection.queue, ^{
            [self->_connection badRequest];
        });
        _state = iTermWebSocketConnectionStateClosed;
        dispatch_async(self.delegateQueue, ^{
            [self.delegate webSocketConnectionDidTerminate:self];
        });
        return;
    }

    _state = iTermWebSocketConnectionStateOpen;

    _frameBuilder = [[iTermWebSocketFrameBuilder alloc] init];

    // I tried using dispatch_read but it didn't work reliably. Seems to work OK for writing.
    __weak __typeof(self) weakSelf = self;
    dispatch_semaphore_t backpressure = _readBackpressureSemaphore;
    dispatch_async(self->_connection.queue, ^{
        while (weakSelf) {
            NSMutableData *data = [self->_connection readSynchronously];
            if (!data) {
                RLog(@"Read EOF from connection");
                [weakSelf abortWithCompletion:nil];
                return;
            }
            // Block the reader (and thus stop draining the socket, engaging TCP
            // flow control) when too many inbound chunks are already queued for
            // parsing. Signaled once each chunk finishes processing. Without
            // this a peer that sends data faster than we can parse it could
            // force an unbounded backlog of unparsed chunks into memory.
            dispatch_semaphore_wait(backpressure, DISPATCH_TIME_FOREVER);
            dispatch_async(self->_queue, ^{
                [weakSelf didReceiveData:data];
                dispatch_semaphore_signal(backpressure);
            });
        }
    });
}

// queue
- (BOOL)didReceiveData:(NSMutableData *)data {
    DLog(@"Read %@ bytes of data", @(data.length));
    __weak __typeof(self) weakSelf = self;
    [_frameBuilder addData:data
                     frame:^(iTermWebSocketFrame *frame, BOOL *stop) {
                         if (!stop) {
                             [weakSelf reallyAbort];
                         } else {
                             *stop = [weakSelf didReceiveFrame:frame];
                         }
                     }];
    return _state != iTermWebSocketConnectionStateClosed;
}

// queue
- (BOOL)didReceiveFrame:(iTermWebSocketFrame *)frame {
    if (_state != iTermWebSocketConnectionStateClosed) {
        [self handleFrame:frame];
    }
    return (_state == iTermWebSocketConnectionStateClosed);
}

// any queue
- (void)sendBinary:(NSData *)binaryData completion:(void (^)(void))completion {
    dispatch_async(_queue, ^{
        [self reallySendBinary:binaryData];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

// queue
- (void)reallySendBinary:(NSData *)binaryData {
    if (_state == iTermWebSocketConnectionStateOpen) {
        DLog(@"Sending binary frame");
        [self sendFrame:[iTermWebSocketFrame binaryFrameWithData:binaryData]];
    } else {
        DLog(@"Not sending binary frame because not open");
    }
}

// any queue
- (void)sendText:(NSString *)text completion:(void (^)(void))completion {
    dispatch_async(_queue, ^{
        [self reallySendText:text];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

// queue
- (void)reallySendText:(NSString *)text {
    if (_state == iTermWebSocketConnectionStateOpen) {
        DLog(@"Sending text frame");
        [self sendFrame:[iTermWebSocketFrame textFrameWithString:text]];
    } else {
        DLog(@"Not sending text frame because not open");
    }
}

// queue
- (void)sendFrame:(iTermWebSocketFrame *)frame {
    DLog(@"Send frame %@", frame);
    [self sendData:frame.data flushed:nil];
}

// queue
// Sends a pong. Rather than block _queue waiting for outbound room (which would
// make the connection un-abortable against a peer that never reads - teardown
// also runs on _queue), we bound the number of outstanding, not-yet-flushed
// pongs. A well-behaved peer drains pongs, so _outstandingPongs falls as writes
// flush and a slot is always available. A peer that floods pings but stops
// reading fills the send buffer, pongs stop flushing, and the count pins at the
// cap; the next pong then aborts the misbehaving connection, which frees the fd,
// the reader thread, and (via the write-error path) the outstanding writes. We
// never silently drop a pong and carry on.
- (void)sendControlResponseFrame:(iTermWebSocketFrame *)frame {
    if (_outstandingPongs >= iTermWebSocketMaxOutstandingPongs) {
        RLog(@"Peer has %@ undrained pongs; aborting misbehaving connection",
             @(_outstandingPongs));
        [self reallyAbort];
        return;
    }
    _outstandingPongs += 1;
    __weak __typeof(self) weakSelf = self;
    [self sendData:frame.data flushed:^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->_outstandingPongs -= 1;
        }
    }];
}

// queue
// `flushed`, if provided, runs on _queue exactly once when the write finishes
// (successfully or with an error).
- (void)sendData:(NSData *)data flushed:(void (^)(void))flushed {
    dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length, _queue, ^{
        DLog(@"Disposing of data %p", data);
        [data length];  // Keep a reference to data
    });

    __weak __typeof(self) weakSelf = self;
    __block BOOL settled = NO;
    [_connection writeAsynchronously:dispatchData queue:_queue completion:^(bool done, dispatch_data_t  _Nullable data, int error) {
        DLog(@"Write progress: done=%d error=%d", (int)done, (int)error);
        if (error) {
            [weakSelf reallyAbort];
        }
        // dispatch_io_write may invoke this repeatedly for a partial write; run
        // `flushed` only on the final call (done) or on error.
        if ((done || error) && !settled) {
            settled = YES;
            if (flushed) {
                flushed();
            }
        }
    }];
}

// any queue
- (void)abortWithCompletion:(void (^)(void))completion {
    dispatch_async(_queue, ^{
        [self reallyAbort];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

// queue
- (void)reallyAbort {
    if (_state != iTermWebSocketConnectionStateClosed) {
        RLog(@"Aborting connection");
        _state = iTermWebSocketConnectionStateClosed;
        dispatch_queue_t queue = self.delegateQueue;
        if (queue) {
            dispatch_async(queue, ^{
                [self.delegate webSocketConnectionDidTerminate:self];
            });
        }
        [self performClose];
    }
}

- (void)performClose {
    [_connection closeConnection];
}

// queue
- (void)handleFrame:(iTermWebSocketFrame *)frame {
    DLog(@"Handle frame %@", frame);
    switch (frame.opcode) {
        case iTermWebSocketOpcodeBinary:
        case iTermWebSocketOpcodeText:
            if (_state == iTermWebSocketConnectionStateOpen) {
                if (frame.fin) {
                    DLog(@"Pass finished frame to delegate");
                    dispatch_async(self.delegateQueue, ^{
                        [self.delegate webSocketConnection:self didReadFrame:frame];
                    });
                } else if (_fragment == nil) {
                    DLog(@"Begin fragmented frame");
                    _fragment = frame;
                } else {
                    DLog(@"Already have a fragmented frame started. Opcode should have been Continuation");
                    [self reallyAbort];
                }
            } else {
                [self reallyAbort];
            }
            break;

        case iTermWebSocketOpcodePing:
            if (_state == iTermWebSocketConnectionStateOpen) {
                DLog(@"Sending pong");
                [self sendControlResponseFrame:[iTermWebSocketFrame pongFrameForPingFrame:frame]];
            } else {
                [self reallyAbort];
            }
            break;

        case iTermWebSocketOpcodePong:
            DLog(@"Got pong");
            break;

        case iTermWebSocketOpcodeContinuation:
            if (_state == iTermWebSocketConnectionStateOpen) {
                if (!_fragment) {
                    DLog(@"Continuation without fragment");
                    [self reallyAbort];
                    break;
                }
                DLog(@"Append fragment");
                [_fragment appendFragment:frame];
                if (frame.fin) {
                    DLog(@"Fragmented frame finished. Sending to delegate");
                    iTermWebSocketFrame *fragment = _fragment;
                    _fragment = nil;
                    dispatch_async(self.delegateQueue, ^{
                        [self.delegate webSocketConnection:self didReadFrame:fragment];
                    });
                }
            } else {
                [self reallyAbort];
            }
            break;

        case iTermWebSocketOpcodeConnectionClose:
            if (_state == iTermWebSocketConnectionStateOpen) {
                RLog(@"open->closing");
                _state = iTermWebSocketConnectionStateClosing;
                [self sendFrame:[iTermWebSocketFrame closeFrame]];

                _state = iTermWebSocketConnectionStateClosed;
                dispatch_async(self.delegateQueue, ^{
                    [self.delegate webSocketConnectionDidTerminate:self];
                });
                [self performClose];
            } else if (_state == iTermWebSocketConnectionStateClosing) {
                RLog(@"closing->closed");
                _state = iTermWebSocketConnectionStateClosed;
                dispatch_async(self.delegateQueue, ^{
                    [self.delegate webSocketConnectionDidTerminate:self];
                });
                [self performClose];
            }
            break;
    }
}

// Any queue
- (void)closeWithCompletion:(void (^)(void))completion {
    dispatch_async(_queue, ^{
        [self reallyClose];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

// queue
- (void)reallyClose {
    RLog(@"Client initiated close");
    if (_state == iTermWebSocketConnectionStateOpen) {
        DLog(@"Send close frame");
        _state = iTermWebSocketConnectionStateClosing;
        [self sendFrame:[iTermWebSocketFrame closeFrame]];
    }
}

// queue
// Completion block called on _queue
- (void)sendUpgradeResponseWithKey:(NSString *)key
                           version:(NSInteger)version
                        completion:(void (^)(BOOL))completion {
    RLog(@"Upgrading with key %@", key);
    key = [key stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];

    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    if (CC_SHA1([data bytes], [data length], hash) ) {
        NSData *sha1 = [NSData dataWithBytes:hash length:CC_SHA1_DIGEST_LENGTH];
        NSDictionary<NSString *, NSString *> *headers =
            @{
               @"Upgrade": @"websocket",
               @"Connection": @"Upgrade",
               @"Sec-WebSocket-Accept": [sha1 stringWithBase64EncodingWithLineBreak:@""],
               @"Sec-WebSocket-Protocol": kProtocolName,
               @"X-iTerm2-Protocol-Version": @"1.17"
             };
        if (version > kWebSocketVersion) {
            NSMutableDictionary *temp = [headers mutableCopy];
            temp[@"Sec-Websocket-Version"] = [@(kWebSocketVersion) stringValue];
            headers = temp;
        }
        DLog(@"Send headers %@", headers);
        dispatch_async(_connection.queue, ^{
            BOOL result = [self->_connection sendResponseWithCode:101
                                                           reason:@"Switching Protocols"
                                                          headers:headers];
            dispatch_async(self->_queue, ^{
                completion(result);
            });
        });
    } else {
        completion(NO);
    }
}

@end
