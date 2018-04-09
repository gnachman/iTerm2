//
//  iTermAPIServer.h
//  iTerm2
//
//  Created by George Nachman on 11/3/16.
//
//

#import <Foundation/Foundation.h>
#import "Api.pbobjc.h"

extern NSString *const iTermWebSocketConnectionPeerIdentityBundleIdentifier;

@protocol iTermAPIServerDelegate<NSObject>
- (NSDictionary *)apiServerAuthorizeProcess:(pid_t)pid;
- (void)apiServerGetBuffer:(ITMGetBufferRequest *)request handler:(void (^)(ITMGetBufferResponse *))handler;
- (void)apiServerGetPrompt:(ITMGetPromptRequest *)request handler:(void (^)(ITMGetPromptResponse *))handler;
- (void)apiServerNotification:(ITMNotificationRequest *)request
                   connection:(id)connection
                      handler:(void (^)(ITMNotificationResponse *))handler;
- (void)apiServerRemoveSubscriptionsForConnection:(id)connection;
- (void)apiServerRegisterTool:(ITMRegisterToolRequest *)request
                 peerIdentity:(NSDictionary *)peerIdentity
                      handler:(void (^)(ITMRegisterToolResponse *))handler;
- (void)apiServerSetProfileProperty:(ITMSetProfilePropertyRequest *)request
                            handler:(void (^)(ITMSetProfilePropertyResponse *))handler;
- (void)apiServerGetProfileProperty:(ITMGetProfilePropertyRequest *)request
                            handler:(void (^)(ITMGetProfilePropertyResponse *))handler;
- (void)apiServerListSessions:(ITMListSessionsRequest *)request
                      handler:(void (^)(ITMListSessionsResponse *))handler;
- (void)apiServerSendText:(ITMSendTextRequest *)request
                  handler:(void (^)(ITMSendTextResponse *))handler;
- (void)apiServerCreateTab:(ITMCreateTabRequest *)request
                   handler:(void (^)(ITMCreateTabResponse *))handler;
- (void)apiServerSplitPane:(ITMSplitPaneRequest *)request
                   handler:(void (^)(ITMSplitPaneResponse *))handler;
@end

@interface iTermAPIServer : NSObject

@property (nonatomic, weak) id<iTermAPIServerDelegate> delegate;

- (void)postAPINotification:(ITMNotification *)notification toConnection:(id)connection;

@end
