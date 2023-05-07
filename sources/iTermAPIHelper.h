//
//  iTermAPIHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import <Foundation/Foundation.h>
#import "iTermAPIServer.h"
#import "iTermTuple.h"

extern NSString *const iTermRemoveAPIServerSubscriptionsNotification;
extern NSString *const iTermAPIRegisteredFunctionsDidChangeNotification;
extern NSString *const iTermAPIDidRegisterSessionTitleFunctionNotification;
extern NSString *const iTermAPIDidRegisterStatusBarComponentNotification;  // object is the unique id of the status bar component
extern NSString *const iTermAPIHelperDidStopNotification;
extern NSString *const iTermAPIHelperDidDetectChangeOfPythonAuthMethodNotification;
extern NSString *const iTermAPIHelperErrorDomain;

extern NSString *const iTermAPIHelperFunctionCallErrorUserInfoKeyConnection;

@class iTermParsedExpression;
@class iTermScriptHistoryEntry;
@class iTermVariableScope;
@class NSWindow;

typedef NS_ENUM(NSUInteger, iTermAPIHelperErrorCode) {
    iTermAPIHelperErrorCodeRegistrationFailed,
    iTermAPIHelperErrorCodeInvalidJSON,
    iTermAPIHelperErrorCodeUnregisteredFunction,
    iTermAPIHelperErrorCodeFunctionCallFailed,
    iTermAPIHelperErrorCodeAPIDisabled,
    iTermAPIHelperErrorCodeTimeout,
    iTermAPIHelperErrorCodeInvalidIdentifier
};

typedef void (^iTermServerOriginatedRPCCompletionBlock)(id, NSError *);

@protocol iTermSubscribable<NSObject>

- (NSString *)subscribableIdentifier;

- (ITMNotificationResponse *)handleAPINotificationRequest:(ITMNotificationRequest *)request
                                            connectionKey:(NSString *)connectionKey;

@end

@interface iTermSessionTitleProvider : NSObject
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSString *invocation;
@property (nonatomic, readonly) NSString *uniqueIdentifier;
@end

@interface iTermAPIHelper : NSObject<iTermAPIServerDelegate>

+ (BOOL)confirmShouldStartServerAndUpdateUserDefaultsForced:(BOOL)forced;
+ (instancetype)sharedInstance;
+ (instancetype)sharedInstanceFromExplicitUserAction;
+ (instancetype)sharedInstanceIfEnabled;

+ (BOOL)requireApplescriptAuth;
+ (void)setRequireApplescriptAuth:(BOOL)requireApplescriptAuth
                           window:(NSWindow *)window;
typedef NS_ENUM(NSUInteger, iTermNoAuthStatus) {
    iTermNoAuthStatusNone,
    iTermNoAuthStatusValid,
    iTermNoAuthStatusCorrupt
};

+ (iTermNoAuthStatus)noAuthStatus:(out NSString **)contentsPtr;

+ (NSString *)invocationWithFullyQualifiedName:(NSString *)fqname
                                      defaults:(NSArray<ITMRPCRegistrationRequest_RPCArgument*> *)defaultsArray;
+ (ITMRPCRegistrationRequest *)registrationRequestForStatusBarComponentWithUniqueIdentifier:(NSString *)uniqueIdentifier;

- (instancetype)init NS_UNAVAILABLE;

+ (void)setEnabled:(BOOL)enabled;
+ (BOOL)isEnabled;

- (void)postAPINotification:(ITMNotification *)notification toConnectionKey:(NSString *)connectionKey;

- (void)dispatchRPCWithName:(NSString *)name
                  arguments:(NSDictionary *)arguments
                 completion:(iTermServerOriginatedRPCCompletionBlock)completion;

// function name -> [ arg1, arg2, ... ]
+ (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary;

+ (NSArray<iTermSessionTitleProvider *> *)sessionTitleFunctions;

+ (NSArray<ITMRPCRegistrationRequest *> *)statusBarComponentProviderRegistrationRequests;
+ (NSArray<ITMRPCRegistrationRequest *> *)contextMenuProviderRegistrationRequests;

+ (NSString *)nameOfScriptVendingStatusBarComponentWithUniqueIdentifier:(NSString *)uniqueID;

// stringSignature is like func(arg1,arg2) or title.com.example.foo::func(arg1,arg2). Use iTermFunctionSignatureFromNamespaceAndNameAndArguments to construct it safely.
- (BOOL)haveRegisteredFunctionWithSignature:(NSString *)stringSignature;
- (NSString *)connectionKeyForRPCWithSignature:(NSString *)signature;
- (NSString *)connectionKeyForRPCWithName:(NSString *)name
                       explicitParameters:(NSDictionary<NSString *, id> *)explicitParameters
                                    scope:(iTermVariableScope *)scope
                           fullParameters:(out NSDictionary<NSString *, id> **)fullParameters;

- (void)logToConnectionHostingFunctionWithSignature:(NSString *)signatureString
                                             format:(NSString *)format, ...;
- (void)logToConnectionHostingFunctionWithSignature:(NSString *)signatureString
                                             string:(NSString *)string;
- (iTermScriptHistoryEntry *)scriptHistoryEntryForConnectionKey:(NSString *)connectionKey;
- (NSDictionary<NSString *, iTermTuple<id, ITMNotificationRequest *> *> *)serverOriginatedRPCSubscriptions;

@end

@interface ITMRPCRegistrationRequest(Extensions)
// This gives the string signature.
@property (nonatomic, readonly) NSString *it_stringRepresentation;
- (BOOL)it_rpcRegistrationRequestValidWithError:(out NSError **)error;

// returns namespace.name
- (NSString *)it_fullyQualifiedName;
@end
