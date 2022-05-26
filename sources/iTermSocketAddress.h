//
//  iTermSocketAddress.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>
#include <sys/socket.h>

NS_ASSUME_NONNULL_BEGIN

// Encapsulates struct sockaddr, which is generally a network endpoint such as an IP address and
// port. This is the base class of a class cluster. Subclasses implement NSCopying.
@interface iTermSocketAddress : NSObject<NSCopying>

@property (nonatomic, readonly) const struct sockaddr *sockaddr;
@property (nonatomic, readonly) socklen_t sockaddrSize;
@property (nonatomic, readonly) int addressFamily;

+ (instancetype _Nullable)socketAddressWithSockaddr:(struct sockaddr)sockaddr;
+ (instancetype _Nullable)socketAddressWithPath:(NSString *)path;

- (BOOL)isEqualToSockAddr:(struct sockaddr *)other;

@end

NS_ASSUME_NONNULL_END
