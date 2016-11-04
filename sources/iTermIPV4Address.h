//
//  iTermIPV4Address.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

@interface iTermIPV4Address : NSObject
@property (nonatomic) in_addr_t address;
@property (nonatomic, readonly) in_addr_t networkByteOrderAddress;

- (instancetype)initWithLoopback;
@end
