//
//  iTermSocketIPV4Address.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>
#import "iTermSocketAddress.h"

@class iTermIPV4Address;

// An IPv4 address and port.
@interface iTermSocketIPV4Address : iTermSocketAddress
- (instancetype)init NS_UNAVAILABLE;
@end
