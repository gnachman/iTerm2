//
//  iTermInProcessAPIConnection.h
//  iTerm2
//
//  A synthetic connection that lets embedded callers (the it2 command tree run
//  over SSH integration) drive iTermAPIServer's existing dispatch and
//  subscription machinery without a real websocket. Each ITMServerOriginatedMessage
//  the server "sends" (request responses and subscription notifications) is
//  delivered, serialized, to `responseHandler` on an arbitrary queue.
//

#import <Foundation/Foundation.h>
#import "iTermWebSocketConnection.h"  // iTermAPIServerConnection protocol

NS_ASSUME_NONNULL_BEGIN

@interface iTermInProcessAPIConnection : NSObject <iTermAPIServerConnection>

- (instancetype)initWithKey:(id)key
            responseHandler:(void (^)(NSData *responseData))responseHandler NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Invoked when the API server tears the connection down (e.g. the API is
// disabled or the server stops and calls -abortWithCompletion:). Lets the owner
// unblock any thread waiting on a response instead of hanging forever.
@property (nonatomic, copy, nullable) void (^onAbort)(void);

@end

NS_ASSUME_NONNULL_END
