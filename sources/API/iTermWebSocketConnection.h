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

// Prefix of error message when connecting client is outdated.
extern NSString *const iTermWebSocketConnectionLibraryVersionTooOldString;

@protocol iTermWebSocketConnectionDelegate<NSObject>
- (void)webSocketConnectionDidTerminate:(iTermWebSocketConnection *)webSocketConnection;
- (void)webSocketConnection:(iTermWebSocketConnection *)webSocketConnection didReadFrame:(iTermWebSocketFrame *)frame;
@end

// The subset of a connection the API server needs in order to dispatch a request
// and deliver responses/notifications back. iTermWebSocketConnection is the
// socket-backed implementation; an in-process implementation lets embedded
// callers (e.g. it2 over SSH integration) reuse the server's dispatch, handlers,
// and subscription machinery without a real socket.
@protocol iTermAPIServerConnection<NSObject>
@property(nonatomic, readonly) id key;
@property(nonatomic, readonly) NSString *guid;
- (void)sendBinary:(NSData *)binaryData completion:(void (^)(void))completion;
- (void)abortWithCompletion:(void (^)(void))completion;
@end

@interface iTermWebSocketConnection : NSObject <iTermAPIServerConnection>
@property(nonatomic, weak) id<iTermWebSocketConnectionDelegate> delegate;
@property(nonatomic, weak) dispatch_queue_t delegateQueue;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic, readonly) BOOL preauthorized;
@property(nonatomic, readonly) id key;
@property(nonatomic, readonly) NSString *advisoryName;
@property(nonatomic, readonly) NSString *guid;

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
