//
//  iTermAPIHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import <Foundation/Foundation.h>
#import "ITMRPCRegistrationRequest+Extensions.h"
#import "iTermAPIDispatcher.h"
#import "iTermAPINotificationController.h"
#import "iTermAPIServer.h"
#import "iTermTuple.h"

extern NSString *const iTermAPIHelperDidStopNotification;

@class iTermParsedExpression;
@class iTermScriptHistoryEntry;
@class iTermVariableScope;

@interface iTermAPIHelper : NSObject<iTermAPIServerDelegate>

@property (nonatomic, readonly) iTermAPINotificationController *notificationController;
@property (nonatomic, readonly) iTermAPIDispatcher *dispatcher;

+ (BOOL)confirmShouldStartServerAndUpdateUserDefaultsForced:(BOOL)forced;
+ (instancetype)sharedInstance;
+ (instancetype)sharedInstanceFromExplicitUserAction;

+ (ITMRPCRegistrationRequest *)registrationRequestForStatusBarComponentWithUniqueIdentifier:(NSString *)uniqueIdentifier;

- (instancetype)init NS_UNAVAILABLE;

+ (void)setEnabled:(BOOL)enabled;
+ (BOOL)isEnabled;

- (void)postAPINotification:(ITMNotification *)notification toConnectionKey:(NSString *)connectionKey;

// function name -> [ arg1, arg2, ... ]
+ (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary;

+ (NSArray<iTermSessionTitleProvider *> *)sessionTitleFunctions;

+ (NSArray<ITMRPCRegistrationRequest *> *)statusBarComponentProviderRegistrationRequests;

// Performs block either when the function becomes registered, immediately if it's already
// registered, or after timeout (with an argument of YES) if it does not become registered
// soon enough.
- (void)performBlockWhenFunctionRegisteredWithName:(NSString *)name
                                         arguments:(NSArray<NSString *> *)arguments
                                           timeout:(NSTimeInterval)timeout
                                             block:(void (^)(BOOL timedOut))block;

- (iTermScriptHistoryEntry *)scriptHistoryEntryForConnectionKey:(NSString *)connectionKey;

@end

