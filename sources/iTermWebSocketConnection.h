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
@property(nonatomic, assign) id<iTermWebSocketConnectionDelegate> delegate;
@property(nonatomic, copy) NSDictionary *peerIdentity;
@property(nonatomic, readonly) BOOL authenticated;

+ (instancetype)newWebSocketConnectionForRequest:(NSURLRequest *)request
                                      connection:(iTermHTTPConnection *)connection;

- (instancetype)init NS_UNAVAILABLE;

- (void)handleRequest:(NSURLRequest *)request;
- (void)close;
- (void)sendBinary:(NSData *)binaryData;
- (void)sendText:(NSString *)text;

@end
