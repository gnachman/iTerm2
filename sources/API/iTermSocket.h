//
//  iTermSocket.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermSocketAddress;

// A humane interface for Berkeley sockets.
@interface iTermSocket : NSObject
@property (nonatomic, readonly) int fd;

+ (instancetype _Nullable)unixDomainSocket;

- (void)setReuseAddr:(BOOL)reuse;
- (BOOL)bindToAddress:(iTermSocketAddress *)address;
// If nonnil, the number is the effective user ID of the connecting process.
- (BOOL)listenWithBacklog:(int)backlog accept:(void (^)(int, iTermSocketAddress * _Nullable, NSNumber *))acceptBlock;
- (void)close;

@end

NS_ASSUME_NONNULL_END
