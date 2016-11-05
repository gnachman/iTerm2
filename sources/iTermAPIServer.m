//
//  iTermAPIServer.m
//  iTerm2
//
//  Created by George Nachman on 11/3/16.
//
//

#import "iTermAPIServer.h"

#import "DebugLogging.h"
#import "iTermHTTPConnection.h"
#import "iTermWebSocketConnection.h"
#import "iTermWebSocketFrame.h"
#import "iTermSocket.h"
#import "iTermIPV4Address.h"
#import "iTermSocketIPV4Address.h"

@interface iTermAPIServer()<iTermWebSocketConnectionDelegate>
@end

#define ILog ELog

@implementation iTermAPIServer {
    iTermSocket *_socket;
    NSMutableArray<iTermWebSocketConnection *> *_connections;
    dispatch_queue_t _queue;
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
        _connections = [[NSMutableArray alloc] init];
        _socket = [iTermSocket tcpIPV4Socket];
        if (!_socket) {
            ELog(@"Failed to create socket");
            return nil;
        }
        _queue = dispatch_queue_create("com.iterm2.apisockets", NULL);
        [_socket setReuseAddr:YES];
        iTermIPV4Address *loopback = [[iTermIPV4Address alloc] initWithLoopback];
        iTermSocketAddress *socketAddress = [iTermSocketAddress socketAddressWithIPV4Address:loopback
                                                                                        port:1912];
        if (![_socket bindToAddress:socketAddress]) {
            ELog(@"Failed to bind");
            return nil;
        }

        BOOL ok = [_socket listenWithBacklog:5 accept:^(int fd, iTermSocketAddress *clientAddress) {
            [self didAcceptConnectionOnFileDescriptor:fd fromAddress:clientAddress];
        }];
        if (!ok) {
            ELog(@"Failed to listen");
            return nil;
        }
    }
    return self;
}

- (void)didAcceptConnectionOnFileDescriptor:(int)fd fromAddress:(iTermSocketAddress *)address {
    ILog(@"Accepted connection");
    dispatch_async(_queue, ^{
        iTermHTTPConnection *connection = [[iTermHTTPConnection alloc] initWithFileDescriptor:fd clientAddress:address];
        NSURLRequest *request = [connection readRequest];
        if (!request) {
            ELog(@"Failed to read request from HTTP connection");
            [connection badRequest];
            return;
        }

        if ([iTermWebSocketConnection validateRequest:request]) {
            ILog(@"Upgrading request to websocket");
            iTermWebSocketConnection *webSocketConnection = [[iTermWebSocketConnection alloc] initWithConnection:connection];
            webSocketConnection.delegate = self;
            [_connections addObject:webSocketConnection];
            [webSocketConnection handleRequest:request];
        } else {
            ELog(@"Bad request %@", request);
            [connection badRequest];
        }
    });
}

#pragma mark - iTermWebSocketConnectionDelegate

- (void)webSocketConnectionDidTerminate:(iTermWebSocketConnection *)webSocketConnection {
    ILog(@"Connection terminated");
    [_connections removeObject:webSocketConnection];
}

- (void)webSocketConnection:(iTermWebSocketConnection *)webSocketConnection didReadFrame:(iTermWebSocketFrame *)frame {
#if DEBUG
    if (frame.opcode == iTermWebSocketOpcodeText) {
        [webSocketConnection sendText:[NSString stringWithFormat:@"You said: %@", frame.text]];
    } else {
        char data[4] = { 0x0b, 0xad, 0xf0, 0x0d };
        [webSocketConnection sendBinary:[NSData dataWithBytes:data length:sizeof(data)]];
    }
    ILog(@"Got a frame: %@", frame);
#endif
}

@end
