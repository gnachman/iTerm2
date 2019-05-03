//
//  iTermAPIDispatcher.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 02/05/19.
//

#import <Foundation/Foundation.h>

#import "Api.pbobjc.h"
#import "iTermTuple.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermAPIHelperFunctionCallErrorUserInfoKeyConnection;
extern const NSInteger iTermAPIHelperFunctionCallUnregisteredErrorCode;
extern const NSInteger iTermAPIHelperFunctionCallOtherErrorCode;

typedef void (^iTermServerOriginatedRPCCompletionBlock)(id _Nullable, NSError * _Nullable);

@interface iTermSessionTitleProvider : NSObject
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSString *invocation;
@property (nonatomic, readonly) NSString *uniqueIdentifier;
@end

@protocol iTermAPIDispatcherDelegate<NSObject>

- (NSDictionary<NSString *, iTermTuple<id, ITMNotificationRequest *> *> *)dispatcherServerOriginatedRPCSubscriptions;

- (void)dispatcherLogToConnectionWithKey:(NSString *)connectionKey
                                  string:(NSString *)string;

- (void)dispatcherPostNotification:(ITMNotification *)notification
                     connectionKey:(NSString *)key;

@end

@interface iTermAPIDispatcher : NSObject

@property (nonatomic, weak) id<iTermAPIDispatcherDelegate> delegate;

@property (nonatomic, readonly) NSDictionary<NSString *, NSArray<NSString *> *> *registeredFunctionSignatureDictionary;
@property (nonatomic, readonly) NSArray<ITMRPCRegistrationRequest *> *statusBarComponentProviderRegistrationRequests;
@property (nonatomic, readonly) NSArray<iTermSessionTitleProvider *> *sessionTitleFunctions;

+ (NSString *)invocationWithName:(NSString *)name
                        defaults:(NSArray<ITMRPCRegistrationRequest_RPCArgument*> *)defaultsArray;

- (void)dispatchRPCWithName:(NSString *)name
                  arguments:(NSDictionary *)arguments
                 completion:(iTermServerOriginatedRPCCompletionBlock)completion;

// stringSignature is like func(arg1,arg2). Use iTermFunctionSignatureFromNameAndArguments to construct it safely.
- (BOOL)haveRegisteredFunctionWithSignature:(NSString *)stringSignature;

- (void)logToConnectionHostingFunctionWithSignature:(nullable NSString *)signatureString
                                             format:(NSString *)format, ...;

- (void)logToConnectionHostingFunctionWithSignature:(nullable NSString *)signatureString
                                             string:(NSString *)string;

#pragma mark - Internal

- (void)didCloseConnectionWithKey:(id)connectionKey;
- (void)stop;
- (void)serverOriginatedRPCDidReceiveResponseWithResult:(ITMServerOriginatedRPCResultRequest *)result
                                          connectionKey:(NSString *)connectionKey;

@end

NS_ASSUME_NONNULL_END
