//
//  iTermSocketAddress.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

@class iTermIPV4Address;

@interface iTermSocketAddress : NSObject<NSCopying>
@property (nonatomic, readonly) struct sockaddr *sockaddr;
@property (nonatomic, readonly) socklen_t sockaddrSize;

+ (instancetype)socketAddressWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port;

@end
