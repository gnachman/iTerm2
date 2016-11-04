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

@interface iTermSocketIPV4Address : iTermSocketAddress
- (instancetype)initWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port;
@end
