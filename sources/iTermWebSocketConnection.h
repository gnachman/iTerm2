//
//  iTermWebSocketConnection.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

@class iTermAPIServerConnection;
@class iTermWebSocketConnection;
@class iTermWebSocketFrame;

@protocol iTermWebSocketConnectionDelegate<NSObject>
- (void)webSocketConnectionDidTerminate:(iTermWebSocketConnection *)webSocketConnection;
- (void)webSocketConnection:(iTermWebSocketConnection *)webSocketConnection didReadFrame:(iTermWebSocketFrame *)frame;
@end

@interface iTermWebSocketConnection : NSObject
@property(nonatomic, assign) id<iTermWebSocketConnectionDelegate> delegate;

- (instancetype)initWithConnection:(iTermAPIServerConnection *)connection;
- (void)start;
- (void)close;
- (void)sendData:(NSData *)data;

@end
