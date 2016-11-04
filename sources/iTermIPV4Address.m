//
//  iTermIPV4Address.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermIPV4Address.h"

#include <arpa/inet.h>

@implementation iTermIPV4Address

- (instancetype)initWithLoopback {
    self = [super init];
    if (self) {
        _address = INADDR_LOOPBACK;
    }
    return self;
}

- (in_addr_t)networkByteOrderAddress {
    return htonl(_address);
}

@end
