//
//  iTermSocketAddress.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermSocketAddress.h"
#import "DebugLogging.h"
#import "iTermIPV4Address.h"
#import "iTermSocketIPV4Address.h"

@interface iTermSocketIPV4Address()
- (instancetype)initWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port;
@end

@implementation iTermSocketAddress

+ (instancetype)socketAddressWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port {
    return [[iTermSocketIPV4Address alloc] initWithIPV4Address:address port:port];
}

+ (instancetype)socketAddressWithSockaddr:(struct sockaddr)sockaddr {
    switch (sockaddr.sa_family) {
        case AF_INET: {
            struct sockaddr_in *inAddr = (struct sockaddr_in *)&sockaddr;
            return [self socketAddressWithIPV4Address:[[iTermIPV4Address alloc] initWithInetAddr:ntohl(inAddr->sin_addr.s_addr)]
                                                 port:ntohs(inAddr->sin_port)];
        }

        default:
            ELog(@"Unrecognized address family %@", @(sockaddr.sa_family));
            return nil;
    }
}

+ (int)socketAddressPort:(struct sockaddr *)sa {
    if (sa->sa_family == AF_INET) {
        struct sockaddr_in *addr = (struct sockaddr_in *)sa;
        return ntohs(addr->sin_port);
    } else if (sa->sa_family == AF_INET6) {
        struct sockaddr_in6 *addr = (struct sockaddr_in6 *)sa;
        return ntohs(addr->sin6_port);
    } else {
        return 0;
    }
}

+ (BOOL)socketAddressIsLoopback:(struct sockaddr *)sa {
    if (sa->sa_family == AF_INET) {
        struct sockaddr_in *addr = (struct sockaddr_in *)sa;
        return IN_LOOPBACK(ntohl(addr->sin_addr.s_addr));
    } else if (sa->sa_family == AF_INET6) {
        struct sockaddr_in6 *addr = (struct sockaddr_in6 *)sa;
        return IN6_IS_ADDR_LOOPBACK(&addr->sin6_addr);
    } else {
        return 0;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (BOOL)isLoopback {
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (BOOL)isEqualToSockAddr:(struct sockaddr *)other {
    const struct sockaddr *mine = self.sockaddr;
    if (mine->sa_len != other->sa_len) {
        return NO;
    }
    return memcmp(mine, other, mine->sa_len) == 0;
}

@end
