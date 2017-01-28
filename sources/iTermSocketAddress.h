//
//  iTermSocketAddress.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

@class iTermIPV4Address;

// Encapsulates struct sockaddr, which is generally a network endpoint such as an IP address and
// port. This is the base class of a class cluster. Subclasses implement NSCopying.
@interface iTermSocketAddress : NSObject<NSCopying>

@property (nonatomic, readonly) const struct sockaddr *sockaddr;
@property (nonatomic, readonly) socklen_t sockaddrSize;
@property (nonatomic, readonly) uint16 port;

+ (instancetype)socketAddressWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port;
+ (instancetype)socketAddressWithSockaddr:(struct sockaddr)sockaddr;
+ (int)socketAddressPort:(struct sockaddr *)sa;
+ (BOOL)socketAddressIsLoopback:(struct sockaddr *)sa;

- (BOOL)isLoopback;
- (BOOL)isEqualToSockAddr:(struct sockaddr *)other;

@end
