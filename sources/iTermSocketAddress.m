//
//  iTermSocketAddress.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermSocketAddress.h"
#import "iTermIPV4Address.h"
#import "iTermSocketIPV4Address.h"

@implementation iTermSocketAddress

+ (instancetype)socketAddressWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port {
    return [[iTermSocketIPV4Address alloc] initWithIPV4Address:address port:port];
}

- (id)copyWithZone:(NSZone *)zone {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

@end
