//
//  iTermBroadcastPasswordHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/23/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PTYSession;

@interface iTermBroadcastPasswordHelper : NSObject

+ (void)tryToSendPassword:(NSString *)password
               toSessions:(NSArray<PTYSession *> *)sessions
               completion:(NSArray<PTYSession *> *(^)(NSArray<PTYSession *> *okSessions,
                                                      NSArray<PTYSession *> *problemSessions))completion;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
