//
//  iTermSocket.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermSocket.h"

#import "DebugLogging.h"
#import "iTermSocketAddress.h"
#include <arpa/inet.h>

@implementation iTermSocket {
    int _addressFamily;
    int _socketType;
    iTermSocketAddress *_boundAddress;
    dispatch_queue_t _acceptQueue;
}

+ (instancetype)tcpIPV4Socket {
    return [[[self alloc] initWithAddressFamily:AF_INET socketType:SOCK_STREAM] autorelease];
}

- (instancetype)initWithAddressFamily:(int)addressFamily
                           socketType:(int)socketType {
    self = [super init];
    if (self) {
        _addressFamily = addressFamily;
        _socketType = socketType;
        _fd = socket(_addressFamily, _socketType, 0);
        if (_fd < 0) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_fd >= 0) {
        close(_fd);
    }
    [_boundAddress release];
    if (_acceptQueue) {
        dispatch_release(_acceptQueue);
    }
    [super dealloc];
}

- (void)setReuseAddr:(BOOL)reuse {
    int optionValue = reuse ? 1 : 0;
    setsockopt(_fd,
               SOL_SOCKET,
               SO_REUSEADDR,
               (const void *)&optionValue,
               sizeof(optionValue));
}

- (BOOL)bindToAddress:(iTermSocketAddress *)address {
    if (bind(_fd, address.sockaddr, address.sockaddrSize) == 0) {
        [_boundAddress release];
        _boundAddress = [address copy];
        return YES;
    }
    return NO;
}

- (BOOL)listenWithBacklog:(int)backlog accept:(void (^)(int, iTermSocketAddress *))acceptBlock {
    if (listen(_fd, backlog) < 0) {
        return NO;
    }

    if (!_acceptQueue) {
        _acceptQueue = dispatch_queue_create("com.iterm2.accept", NULL);
    };

    int fd = _fd;
    dispatch_async(_acceptQueue, ^{
        while (1) {
            @autoreleasepool {
                iTermSocketAddress *clientSocketAddress = [[[_boundAddress class] alloc] init];
                socklen_t clientAddressLength = clientSocketAddress.sockaddrSize;
                int acceptFd = accept(fd, clientSocketAddress.sockaddr, &clientAddressLength);
                if (acceptFd < 0) {
                    if (errno == EINTR || errno == EWOULDBLOCK) {
                        continue;
                    } else {
                        ELog(@"Accept failed with %s", strerror(errno));
                        return;
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    acceptBlock(acceptFd, clientSocketAddress);
                });
            }
        }
    });
    return YES;
}

@end
