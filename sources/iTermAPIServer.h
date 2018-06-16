//
//  iTermAPIServer.h
//  iTerm2
//
//  Created by George Nachman on 11/3/16.
//
//

#import <Foundation/Foundation.h>
#import "Api.pbobjc.h"

extern NSString *const iTermAPIServerAuthorizationKey;
extern NSString *const iTermAPIServerDidReceiveMessage;
extern NSString *const iTermAPIServerWillSendMessage;
extern NSString *const iTermAPIServerConnectionRejected;
extern NSString *const iTermAPIServerConnectionAccepted;
extern NSString *const iTermAPIServerConnectionClosed;

@protocol iTermAPIServerDelegate<NSObject>
- (NSDictionary *)apiServerAuthorizeProcess:(pid_t)pid preauthorized:(BOOL)preauthorized reason:(out NSString **)reason displayName:(out NSString **)displayName;
- (void)apiServerGetBuffer:(ITMGetBufferRequest *)request handler:(void (^)(ITMGetBufferResponse *))handler;
- (void)apiServerGetPrompt:(ITMGetPromptRequest *)request handler:(void (^)(ITMGetPromptResponse *))handler;
- (void)apiServerNotification:(ITMNotificationRequest *)request
                connectionKey:(NSString *)connectionKey
                      handler:(void (^)(ITMNotificationResponse *))handler;
- (void)apiServerDidCloseConnectionWithKey:(NSString *)connectionKey;
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
- (void)apiServerSetProperty:(ITMSetPropertyRequest *)request
                     handler:(void (^)(ITMSetPropertyResponse *))handler;
- (void)apiServerGetProperty:(ITMGetPropertyRequest *)request
                     handler:(void (^)(ITMGetPropertyResponse *))handler;
- (void)apiServerInject:(ITMInjectRequest *)request
                handler:(void (^)(ITMInjectResponse *))handler;
- (void)apiServerActivate:(ITMActivateRequest *)request
                  handler:(void (^)(ITMActivateResponse *))handler;
- (void)apiServerVariable:(ITMVariableRequest *)request
                  handler:(void (^)(ITMVariableResponse *))handler;
- (void)apiServerSavedArrangement:(ITMSavedArrangementRequest *)request
                          handler:(void (^)(ITMSavedArrangementResponse *))response;
- (void)apiServerFocus:(ITMFocusRequest *)request
               handler:(void (^)(ITMFocusResponse *))response;
- (void)apiServerListProfiles:(ITMListProfilesRequest *)request
                      handler:(void (^)(ITMListProfilesResponse *))response;
- (void)apiServerServerOriginatedRPCResult:(ITMServerOriginatedRPCResultRequest *)request
                             connectionKey:(NSString *)connectionKey
                                   handler:(void (^)(ITMServerOriginatedRPCResultResponse *))response;
- (void)apiServerRestartSession:(ITMRestartSessionRequest *)request
                        handler:(void (^)(ITMRestartSessionResponse *))response;
- (void)apiServerMenuItem:(ITMMenuItemRequest *)request
                  handler:(void (^)(ITMMenuItemResponse *))response;
- (void)apiServerSetTabLayout:(ITMSetTabLayoutRequest *)request
                      handler:(void (^)(ITMSetTabLayoutResponse *))response;

@end

@interface iTermAPIServer : NSObject

@property (nonatomic, weak) id<iTermAPIServerDelegate> delegate;

- (void)postAPINotification:(ITMNotification *)notification toConnectionKey:(NSString *)connectionKey;

@end
