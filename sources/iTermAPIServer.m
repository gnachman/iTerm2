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
#import "iTermSocket.h"
#import "iTermIPV4Address.h"
#import "iTermSocketIPV4Address.h"


@interface iTermAPIServer()<iTermWebSocketConnectionDelegate>
@end

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
        _queue = dispatch_queue_create("com.iterm2.apisockets", NULL);
        if (!_socket) {
            return nil;
        }
        [_socket setReuseAddr:YES];
        iTermIPV4Address *loopback = [[iTermIPV4Address alloc] initWithLoopback];
        iTermSocketAddress *socketAddress = [iTermSocketAddress socketAddressWithIPV4Address:loopback
                                                                                        port:1912];
        if (![_socket bindToAddress:socketAddress]) {
            return nil;
        }

        BOOL ok = [_socket listenWithBacklog:5 accept:^(int fd, iTermSocketAddress *clientAddress) {
            [self didAcceptConnectionOnFileDescriptor:fd fromAddress:clientAddress];
        }];
        if (!ok) {
            return nil;
        }
    }
    return self;
}

- (void)didAcceptConnectionOnFileDescriptor:(int)fd fromAddress:(iTermSocketAddress *)address {
    dispatch_async(_queue, ^{
        iTermHTTPConnection *connection = [[iTermHTTPConnection alloc] initWithFileDescriptor:fd clientAddress:address];
        NSURLRequest *request = [connection readRequest];
        if (!request) {
            ELog(@"Failed to read request from HTTP connection");
            [connection badRequest];
            return;
        }

        if ([iTermWebSocketConnection validateRequest:request]) {
            iTermWebSocketConnection *webSocketConnection = [[iTermWebSocketConnection alloc] initWithConnection:connection];
            webSocketConnection.delegate = self;
            [_connections addObject:webSocketConnection];
            [webSocketConnection handleRequest:request];
        } else {
            [connection badRequest];
        }
    });
}

#pragma mark - iTermWebSocketConnectionDelegate

- (void)webSocketConnectionDidTerminate:(iTermWebSocketConnection *)webSocketConnection {
    [_connections removeObject:webSocketConnection];
}

- (void)webSocketConnection:(iTermWebSocketConnection *)webSocketConnection didReadFrame:(iTermWebSocketFrame *)frame {
    NSLog(@"Got a frame: %@", frame);
}

@end
