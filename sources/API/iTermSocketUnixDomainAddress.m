//
//  iTermSocketUnixDomainAddress.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/10/20.
//

#import "iTermSocketUnixDomainAddress.h"
#include <sys/socket.h>
#include <sys/un.h>

@implementation iTermSocketUnixDomainAddress {
    struct sockaddr_un _sockaddr;
}

- (instancetype)initWithPath:(NSString *)path {
    if (strlen(path.UTF8String) + 1 >= sizeof(_sockaddr.sun_path)) {
        return nil;
    }
    self = [super init];
    if (self) {
        _sockaddr.sun_family = AF_UNIX;
        snprintf(_sockaddr.sun_path,
                 sizeof(_sockaddr.sun_path),
                 "%s",
                 path.UTF8String);
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%s", _sockaddr.sun_path];
}

- (const struct sockaddr *)sockaddr {
    return (const struct sockaddr *)&_sockaddr;
}

- (socklen_t)sockaddrSize {
    return (socklen_t)sizeof(_sockaddr);
}

- (id)copyWithZone:(NSZone *)zone {
    return [[iTermSocketUnixDomainAddress alloc] initWithPath:[NSString stringWithUTF8String:_sockaddr.sun_path]];
}

- (BOOL)isLoopback {
    return NO;
}

- (uint16)port {
    return 0;
}

- (BOOL)isEqualToSockAddr:(struct sockaddr *)other {
    if (other->sa_family != _sockaddr.sun_family) {
        return NO;
    }
    struct sockaddr_un *other_un = (struct sockaddr_un *)other;
    return !strncmp(other_un->sun_path, _sockaddr.sun_path, sizeof(_sockaddr.sun_path));
}

- (int)addressFamily {
    return AF_UNIX;
}

@end
