//
//  iTermIPV4Address.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>
#include <arpa/inet.h>

// Represents an IPv4 address, and nothing more.
@interface iTermIPV4Address : NSObject

@property (nonatomic) in_addr_t address;  // Host byte order
@property (nonatomic, readonly) in_addr_t networkByteOrderAddress;

- (instancetype)initWithLoopback;
- (instancetype)initWithInetAddr:(in_addr_t)addr;

@end
