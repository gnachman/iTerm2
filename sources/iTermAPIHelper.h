//
//  iTermAPIHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import <Foundation/Foundation.h>
#import "iTermAPIServer.h"

extern NSString *const iTermRemoveAPIServerSubscriptionsNotification;
extern NSString *const iTermAPIRegisteredFunctionsDidChangeNotification;

typedef void (^iTermServerOriginatedRPCCompletionBlock)(id, NSError *);

@interface iTermAPIHelper : NSObject<iTermAPIServerDelegate>

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

- (void)postAPINotification:(ITMNotification *)notification toConnection:(id)connection;

- (void)dispatchRPCWithName:(NSString *)name
                  arguments:(NSDictionary *)arguments
                 completion:(iTermServerOriginatedRPCCompletionBlock)completion;

// Invokes an RPC and waits until it returns. The RPC should execute quickly
// and may not do anything that blocks on the main thread.
- (id)synchronousDispatchRPCWithName:(NSString *)name
                           arguments:(NSDictionary *)arguments
                             timeout:(NSTimeInterval)timeout
                               error:(out NSError **)error;

- (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary;

// Performs block either when the function becomes registered, immediately if it's already
// registered, or after timeout (with an argument of YES) if it does not become registered
// soon enough.
- (void)performBlockWhenFunctionRegisteredWithName:(NSString *)name
                                         arguments:(NSArray<NSString *> *)arguments
                                           timeout:(NSTimeInterval)timeout
                                             block:(void (^)(BOOL timedOut))block;

@end
