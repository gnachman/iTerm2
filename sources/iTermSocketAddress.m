//
//  iTermSocketAddress.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermSocketAddress.h"
#import "DebugLogging.h"
#import "iTermSocketUnixDomainAddress.h"
#import <sys/un.h>

@interface iTermSocketUnixDomainAddress()
- (instancetype)initWithPath:(NSString *)path;
@end

@implementation iTermSocketAddress

+ (instancetype)socketAddressWithPath:(NSString *)path {
    return [[iTermSocketUnixDomainAddress alloc] initWithPath:path];
}

+ (instancetype)socketAddressWithSockaddr:(struct sockaddr)sockaddr {
    switch (sockaddr.sa_family) {
        case AF_UNIX: {
            struct sockaddr_un *unAddr = (struct sockaddr_un *)&sockaddr;
            return [self socketAddressWithPath:[NSString stringWithUTF8String:unAddr->sun_path]];
        }

        default:
            XLog(@"Unrecognized address family %@", @(sockaddr.sa_family));
            return nil;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (BOOL)isEqualToSockAddr:(struct sockaddr *)other {
    const struct sockaddr *mine = self.sockaddr;
    if (mine->sa_len != other->sa_len) {
        return NO;
    }
    return memcmp(mine, other, mine->sa_len) == 0;
}

@end
