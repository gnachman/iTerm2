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
    iTermSocketAddress *_boundAddress;
    dispatch_queue_t _acceptQueue;
    int _addressFamily;
}

+ (instancetype)unixDomainSocket {
    return [[self alloc] initWithAddressFamily:AF_UNIX socketType:SOCK_STREAM];
}

- (instancetype)initWithAddressFamily:(int)addressFamily
                           socketType:(int)socketType {
    self = [super init];
    if (self) {
        _addressFamily = addressFamily;
        _fd = socket(addressFamily, socketType, 0);
        if (_fd < 0) {
            XLog(@"socket failed with %s", strerror(errno));
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_fd >= 0) {
        close(_fd);
    }
}

- (void)setReuseAddr:(BOOL)reuse {
    if (_addressFamily == AF_UNIX) {
        return;
    }
    int optionValue = reuse ? 1 : 0;
    int rc = setsockopt(_fd,
                        SOL_SOCKET,
                        SO_REUSEADDR,
                        (const void *)&optionValue,
                        sizeof(optionValue));
    if (rc) {
        XLog(@"setsockopt failed with %s", strerror(errno));
    }
}

- (BOOL)bindToAddress:(iTermSocketAddress *)address {
    if (bind(_fd, address.sockaddr, address.sockaddrSize) == 0) {
        _boundAddress = [address copy];
        return YES;
    } else {
        XLog(@"bind failed with %s", strerror(errno));
    }
    return NO;
}

- (BOOL)listenWithBacklog:(int)backlog accept:(void (^)(int, iTermSocketAddress *, NSNumber *))acceptBlock {
    if (!_boundAddress) {
        return NO;
    }
    if (_acceptQueue) {
        return NO;
    }
    if (listen(_fd, backlog) < 0) {
        XLog(@"listen failed with %s", strerror(errno));
        return NO;
    }

    _acceptQueue = dispatch_queue_create("com.iterm2.accept", NULL);

    int fd = _fd;
    dispatch_async(_acceptQueue, ^{
        while (1) {
            @autoreleasepool {
                uid_t euid = (uid_t)-1;
                gid_t egid = (gid_t)-1;
                struct sockaddr sockaddr;
                socklen_t clientAddressLength = sizeof(sockaddr);
                const int acceptFd = accept(fd, &sockaddr, &clientAddressLength);
                if (acceptFd < 0) {
                    if (errno == EINTR || errno == EWOULDBLOCK) {
                        continue;
                    } else {
                        XLog(@"accept failed with %s", strerror(errno));
                        return;
                    }
                }

                // The man page for getpeereid appears to contain a lie.
                //   "The argument s must be a UNIX-domain socket (unix(4)) of type SOCK_STREAM on
                //    which either connect(2) or listen(2) have been called"
                // Well, we called listen on `fd`, but `getpeereid` gives "Socket is not connected"
                // when you pass that to it. If you give it `acceptFd`, it works fine.
                // ¯\_(ツ)_/¯
                NSNumber *uidNumber = nil;
                if (getpeereid(acceptFd, &euid, &egid) == 0) {
                    uidNumber = @(euid);
                }
                acceptBlock(acceptFd, [iTermSocketAddress socketAddressWithSockaddr:sockaddr], uidNumber);
            }
        }
    });
    return YES;
}

- (void)close {
    close(_fd);
    _fd = -1;
}

@end
