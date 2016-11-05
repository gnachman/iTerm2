//
//  iTermWebSocketConnection.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermWebSocketConnection.h"
#import "iTermHTTPConnection.h"
#import "iTermWebSocketFrame.h"
#import "iTermWebSocketFrameBuilder.h"
#import "NSData+iTerm.h"

#import <CommonCrypto/CommonDigest.h>

static NSString *const kProtocolName = @"api.iterm2.com";

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
    dispatch_io_t _channel;
}

+ (BOOL)validateRequest:(NSURLRequest *)request {
    if (![request.HTTPMethod isEqualToString:@"GET"]) {
        return NO;
    }
    if (request.URL.path.length == 0) {
        return NO;
    }
    NSDictionary<NSString *, NSString *> *headers = request.allHTTPHeaderFields;
    NSDictionary<NSString *, NSString *> *requiredValues =
        @{ @"host": @"localhost",
           @"upgrade": @"websocket",
           @"connection": @"Upgrade",
           @"sec-websocket-protocol": kProtocolName,
           @"sec-websocket-version": @"1",
           @"origin": @"localhost" };
    for (NSString *key in requiredValues) {
        if (![headers[key] isEqualToString:requiredValues[key]]) {
            return NO;
        }
    }

    NSArray<NSString *> *requiredKeys =
        @[ @"sec-websocket-key",
           @"origin" ];
    for (NSString *key in requiredKeys) {
        if ([headers[key] length] == 0) {
            return NO;
        }
    }

    return YES;
}

- (instancetype)initWithConnection:(iTermHTTPConnection *)connection {
    self = [super init];
    if (self) {
        _connection = connection;
    }
    return self;
}

- (void)handleRequest:(NSURLRequest *)request {
    NSAssert(_state == iTermWebSocketConnectionStateConnecting, @"Request already handled");

    if (![self sendUpgradeResponseWithKey:request.allHTTPHeaderFields[@"sec-websocket-key"]]) {
        [_connection badRequest];
        _state = iTermWebSocketConnectionStateClosed;
        [_delegate webSocketConnectionDidTerminate:self];
        return;
    }

    _state = iTermWebSocketConnectionStateOpen;

    _frameBuilder = [[iTermWebSocketFrameBuilder alloc] init];
    _queue = dispatch_queue_create("com.iterm2.api-io", NULL);
    _channel = [_connection newChannelOnQueue:_queue];

    __weak __typeof(self) weakSelf = self;
    dispatch_io_set_low_water(_channel, 1);
    dispatch_io_read(_channel, 0, SIZE_MAX, _queue, ^(bool done, dispatch_data_t data, int error) {
        if (data) {
            dispatch_data_apply(data, ^bool(dispatch_data_t  _Nonnull region, size_t offset, const void * _Nonnull buffer, size_t size) {
                return [weakSelf didReceiveData:[NSMutableData dataWithBytes:buffer length:size]];
            });
        }
        if (error || done) {
            [self abort];
        }
    });
}

- (BOOL)didReceiveData:(NSMutableData *)data {
    [_frameBuilder addData:data
                     frame:^(iTermWebSocketFrame *frame, BOOL *stop) {
                         if (_state != iTermWebSocketConnectionStateClosed) {
                             [self handleFrame:frame];
                         }
                         *stop = (_state == iTermWebSocketConnectionStateClosed);
                     }];
    return _state != iTermWebSocketConnectionStateClosed;
}

- (void)sendBinary:(NSData *)binaryData {
    if (_state == iTermWebSocketConnectionStateOpen) {
        [self sendFrame:[iTermWebSocketFrame binaryFrameWithData:binaryData]];
    }
}

- (void)sendText:(NSString *)text {
    if (_state == iTermWebSocketConnectionStateOpen) {
        [self sendFrame:[iTermWebSocketFrame textFrameWithString:text]];
    }
}

- (void)sendFrame:(iTermWebSocketFrame *)frame {
    [self sendData:frame.data];
}

- (void)sendData:(NSData *)data {
    dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length, _queue, ^{
        [data length];  // Keep a reference to data
    });

    __weak __typeof(self) weakSelf = self;
    dispatch_io_write(_channel, 0, dispatchData, _queue, ^(bool done, dispatch_data_t  _Nullable data, int error) {
        if (error || done) {
            [weakSelf abort];
        }
    });
}

- (void)abort {
    if (_state != iTermWebSocketConnectionStateClosed) {
        [_delegate webSocketConnectionDidTerminate:self];
        [_connection close];
        _state = iTermWebSocketConnectionStateClosed;
    }
}

- (void)handleFrame:(iTermWebSocketFrame *)frame {
    switch (frame.opcode) {
        case iTermWebSocketOpcodeBinary:
        case iTermWebSocketOpcodeText:
            if (_state == iTermWebSocketConnectionStateOpen) {
                if (frame.fin) {
                    [_delegate webSocketConnection:self didReadFrame:frame];
                } else if (_fragment == nil) {
                    _fragment = frame;
                } else {
                    [self abort];
                }
            } else {
                [self abort];
            }
            break;

        case iTermWebSocketOpcodePing:
            if (_state == iTermWebSocketConnectionStateOpen) {
                [self sendFrame:[iTermWebSocketFrame pongFrameForPingFrame:frame]];
            } else {
                [self abort];
            }
            break;

        case iTermWebSocketOpcodePong:
            break;

        case iTermWebSocketOpcodeContinuation:
            if (_state == iTermWebSocketConnectionStateOpen) {
                if (!_fragment) {
                    [self abort];
                    break;
                }
                [_fragment appendFragment:frame];
                if (frame.fin) {
                    [_delegate webSocketConnection:self didReadFrame:_fragment];
                    _fragment = nil;
                }
            } else {
                [self abort];
            }
            break;

        case iTermWebSocketOpcodeConnectionClose:
            if (_state == iTermWebSocketConnectionStateOpen) {
                _state = iTermWebSocketConnectionStateClosing;
                [self sendFrame:[iTermWebSocketFrame closeFrame]];
            } else if (_state == iTermWebSocketConnectionStateClosing) {
                _state = iTermWebSocketConnectionStateClosed;
            }
            break;
    }
}

- (void)close {
    if (_state == iTermWebSocketConnectionStateOpen) {
        _state = iTermWebSocketConnectionStateClosing;
        [self sendFrame:[iTermWebSocketFrame closeFrame]];
    }
}

- (BOOL)sendUpgradeResponseWithKey:(NSString *)key {
    key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    key = [key stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];

    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    if (CC_SHA1([data bytes], [data length], hash) ) {
        NSData *sha1 = [NSData dataWithBytes:hash length:CC_SHA1_DIGEST_LENGTH];
        NSDictionary<NSString *, NSString *> *headers =
            @{ @"Upgrade": @"websocket",
               @"Connection": @"Upgrade",
               @"Sec-WebSocket-Accept": [sha1 stringWithBase64EncodingWithLineBreak:NO],
               @"Sec-WebSocket-Protocol": kProtocolName };
        return [_connection sendResponseWithCode:101
                                          reason:@"Switching Protocols"
                                         headers:headers];
    } else {
        return NO;
    }
}

@end
