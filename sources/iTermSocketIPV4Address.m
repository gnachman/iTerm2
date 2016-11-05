//
//  iTermSocketIPV4Address.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermSocketIPV4Address.h"
#import "iTermIPV4Address.h"

#include <arpa/inet.h>
#include <sys/socket.h>

@implementation iTermSocketIPV4Address {
    struct sockaddr_in _sockaddr;
}

- (instancetype)initWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port {
    self = [super init];
    if (self) {
        _sockaddr.sin_family = AF_INET;
        _sockaddr.sin_addr.s_addr = address.networkByteOrderAddress;
        _sockaddr.sin_port = htons(port);
    }
    return self;
}

- (const struct sockaddr *)sockaddr {
    return (const struct sockaddr *)&_sockaddr;
}

- (socklen_t)sockaddrSize {
    return (socklen_t)sizeof(_sockaddr);
}

- (id)copyWithZone:(NSZone *)zone {
    iTermIPV4Address *address = [[iTermIPV4Address alloc] initWithInetAddr:_sockaddr.sin_addr.s_addr];
    return [[iTermSocketIPV4Address alloc] initWithIPV4Address:address port:ntohs(_sockaddr.sin_port)];
}

@end
