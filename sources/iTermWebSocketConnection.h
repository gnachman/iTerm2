//
//  iTermWebSocketConnection.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

@class iTermHTTPConnection;
@class iTermWebSocketConnection;
@class iTermWebSocketFrame;

@protocol iTermWebSocketConnectionDelegate<NSObject>
- (void)webSocketConnectionDidTerminate:(iTermWebSocketConnection *)webSocketConnection;
- (void)webSocketConnection:(iTermWebSocketConnection *)webSocketConnection didReadFrame:(iTermWebSocketFrame *)frame;
@end

@interface iTermWebSocketConnection : NSObject
@property(nonatomic, weak) id<iTermWebSocketConnectionDelegate> delegate;
@property(nonatomic, weak) dispatch_queue_t delegateQueue;
@property(nonatomic, copy) NSDictionary *peerIdentity;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic, readonly) BOOL preauthorized;
@property(nonatomic, readonly) id key;

+ (instancetype)newWebSocketConnectionForRequest:(NSURLRequest *)request
                                      connection:(iTermHTTPConnection *)connection
                                          reason:(out NSString **)reason;

- (instancetype)init NS_UNAVAILABLE;

- (void)handleRequest:(NSURLRequest *)request
           completion:(void (^)(void))completion;
- (void)closeWithCompletion:(void (^)(void))completion;  // Send close frame
- (void)abortWithCompletion:(void (^)(void))completion;  // Close TCP connection
- (void)sendBinary:(NSData *)binaryData
        completion:(void (^)(void))completion;
- (void)sendText:(NSString *)text
      completion:(void (^)(void))completion;

@end
