//
//  iTermSocket.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

@class iTermSocketAddress;

// A humane interface for Berkeley sockets.
@interface iTermSocket : NSObject
@property (nonatomic, readonly) int fd;

+ (instancetype)tcpIPV4Socket;

- (void)setReuseAddr:(BOOL)reuse;
- (BOOL)bindToAddress:(iTermSocketAddress *)address;
- (BOOL)listenWithBacklog:(int)backlog accept:(void (^)(int, iTermSocketAddress *))acceptBlock;
- (void)close;

@end
