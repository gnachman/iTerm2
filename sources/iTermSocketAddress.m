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

- (id)copyWithZone:(NSZone *)zone {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (BOOL)isLoopback {
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

@end
