//
//  iTermIPV4Address.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermIPV4Address.h"

@implementation iTermIPV4Address

- (instancetype)initWithInetAddr:(in_addr_t)addr {
    self = [super init];
    if (self) {
        _address = addr;
    }
    return self;
}

- (instancetype)initWithLoopback {
    return [self initWithInetAddr:INADDR_LOOPBACK];
}

- (in_addr_t)networkByteOrderAddress {
    return htonl(_address);
}

@end
