//
//  iTermMultiServerConnection.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/1/19.
//

#import <Foundation/Foundation.h>

#import "iTermFileDescriptorMultiClient.h"
#import "iTermTTYState.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermFileDescriptorMultiClientChild;

@interface iTermMultiServerConnection: NSObject<iTermFileDescriptorMultiClientDelegate>

@property (nonatomic, readonly) pid_t pid;
@property (nonatomic, readonly) NSArray<iTermFileDescriptorMultiClientChild *> *unattachedChildren;
@property (nonatomic, readonly) int socketNumber;

+ (instancetype)primaryConnection;
+ (instancetype)connectionForSocketNumber:(int)number
                         createIfPossible:(BOOL)shouldCreate;

- (instancetype)init NS_UNAVAILABLE;

- (iTermFileDescriptorMultiClientChild *)attachToProcessID:(pid_t)pid;

- (void)launchWithTTYState:(iTermTTYState *)ttyStatePtr
                   argpath:(const char *)argpath
                      argv:(const char **)argv
                initialPwd:(const char *)initialPwd
                newEnviron:(const char **)newEnviron
                completion:(void (^)(iTermFileDescriptorMultiClientChild *child,
                                     NSError *error))completion;

- (void)waitForChild:(iTermFileDescriptorMultiClientChild *)child
  removePreemptively:(BOOL)removePreemptively
          completion:(void (^)(int, NSError * _Nullable))completion;

@end


NS_ASSUME_NONNULL_END
