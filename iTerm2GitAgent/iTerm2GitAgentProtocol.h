//
//  iTerm2GitAgentProtocol.h
//  iTerm2GitAgent
//
//  Created by George Nachman on 7/28/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermGitState;

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol iTerm2GitAgentProtocol

- (void)handshakeWithReply:(void (^)(void))reply;

- (void)requestGitStateForPath:(NSString *)path
                       timeout:(int)timeout
                    completion:(void (^)(iTermGitState * _Nullable))completion;

- (void)fetchRecentBranchesAt:(NSString *)path count:(NSInteger)maxCount completion:(void (^)(NSArray<NSString *> *))reply;


@end

NS_ASSUME_NONNULL_END
