//
//  iTermAPIHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import <Foundation/Foundation.h>
#import "iTermAPIServer.h"

extern NSString *const iTermRemoveAPIServerSubscriptionsNotification;

typedef void (^iTermServerOriginatedRPCCompletionBlock)(id, NSError *);

@interface iTermAPIHelper : NSObject<iTermAPIServerDelegate>

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

- (void)postAPINotification:(ITMNotification *)notification toConnection:(id)connection;

- (void)dispatchRPCWithName:(NSString *)name
                  arguments:(NSDictionary *)arguments
                 completion:(iTermServerOriginatedRPCCompletionBlock)completion;

- (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary;

@end
