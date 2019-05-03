//
//  iTermAPINotificationController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 02/05/19.
//

#import <Foundation/Foundation.h>

#import "Api.pbobjc.h"
#import "iTermAPIDispatcher.h"
#import "iTermTuple.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableScope;
@class PTYTab;
@class PseudoTerminal;
@class PTYSession;

extern NSString *const iTermAPIRegisteredFunctionsDidChangeNotification;
extern NSString *const iTermAPIDidRegisterSessionTitleFunctionNotification;
extern NSString *const iTermAPIDidRegisterStatusBarComponentNotification;  // object is the unique id of the status bar component
extern NSString *const iTermRemoveAPIServerSubscriptionsNotification;



@protocol iTermAPINotificationControllerDelegate<NSObject>

- (void)apiNotificationControllerPostNotification:(ITMNotification *)notification
                                    connectionKey:(NSString *)key;

- (PTYTab *)apiNotificationControllerTabWithID:(NSString *)tabID;

- (PseudoTerminal *)apiNotificationControllerWindowControllerWithID:(NSString *)windowID;

- (PTYSession *)apiNotificationControllerSessionForAPIIdentifier:(NSString *)identifier
                                           includeBuriedSessions:(BOOL)includeBuriedSessions;

- (ITMListSessionsResponse *)apiNotificationControllerListSessionsResponse;

- (void)apiNotificationControllerLogToConnectionWithKey:(NSString *)connectionKey
                                                 string:(NSString *)string;

- (nullable NSString *)apiNotificationControllerFullPathOfScriptWithConnectionKey:(NSString *)connectionKey;

- (NSArray<PTYSession *> *)apiNotificationControllerAllSessions;

- (void)apiNotificationControllerEnumerateBroadcastDomains:(void (^)(NSArray<PTYSession *> *))addDomain;

@end

@interface iTermAPINotificationController : NSObject

@property (nonatomic, weak) id<iTermAPINotificationControllerDelegate> delegate;
@property (nonatomic, readonly) iTermAPIDispatcher *dispatcher;
@property (nonatomic, readonly) NSDictionary<NSString *, iTermTuple<id, ITMNotificationRequest *> *> *serverOriginatedRPCSubscriptions;

+ (NSString *)nameOfScriptVendingStatusBarComponentWithUniqueIdentifier:(NSString *)uniqueID;

- (NSString *)connectionKeyForRPCWithName:(NSString *)name
                       explicitParameters:(NSDictionary<NSString *, id> *)explicitParameters
                                    scope:(iTermVariableScope *)scope
                           fullParameters:(out NSDictionary<NSString *, id> **)fullParameters;

#pragma mark - Internal

- (void)apiServerNotification:(ITMNotificationRequest *)request
                connectionKey:(NSString *)connectionKey
                      handler:(void (^)(ITMNotificationResponse *))handler;

- (void)didCloseConnectionWithKey:(id)connectionKey;

- (void)stop;


@end

NS_ASSUME_NONNULL_END
