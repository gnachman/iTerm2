//
//  iTermMultiServerConnection.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/1/19.
//

#import <Foundation/Foundation.h>

#import "iTermFileDescriptorMultiClient.h"
#import "iTermThreadSafety.h"
#import "iTermTTYState.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermFileDescriptorMultiClientChild;

@interface iTermMultiServerConnection: NSObject<iTermFileDescriptorMultiClientDelegate>

@property (nonatomic, readonly) pid_t pid;
@property (nonatomic, readonly) NSArray<iTermFileDescriptorMultiClientChild *> *unattachedChildren;
@property (nonatomic, readonly) int socketNumber;

// YES if this process launched the server backing this connection. Only such a server
// attributes its jobs to the running app, so new sessions must not use a connection
// that was merely adopted from an earlier instance. See issue 12106.
@property (atomic, readonly) BOOL launchedByThisProcess;

+ (BOOL)available;
+ (BOOL)pathIsSafe:(NSString *)path;

// Returns a connection whose server this process launched, launching one if there is none.
// Never returns a connection to a server left behind by an earlier run of the app, because
// jobs under it are attributed to a dead process and lose TCC permissions. See issue 12106.
+ (void)getOrCreateConnectionForNewSessionWithCallback:(iTermCallback<id, iTermMultiServerConnection *> *)callback;

+ (void)getConnectionForSocketNumber:(int)number
                    createIfPossible:(BOOL)shouldCreate
                            callback:(iTermCallback<id, iTermMultiServerConnection *> *)callback;

- (instancetype)init NS_UNAVAILABLE;

- (void)attachToProcessID:(pid_t)pid
                 callback:(iTermCallback<id, iTermFileDescriptorMultiClientChild *> *)callback;

- (void)launchWithTTYState:(iTermTTYState)ttyState
                   argpath:(const char *)argpath
                      argv:(char **)argv
                initialPwd:(const char *)initialPwd
                newEnviron:(char **)newEnviron
                  callback:(iTermCallback<id, iTermResult<iTermFileDescriptorMultiClientChild *> *> *)callback;

- (void)waitForChild:(iTermFileDescriptorMultiClientChild *)child
  removePreemptively:(BOOL)removePreemptively
            callback:(iTermCallback<id, iTermResult<NSNumber *> *> *)callback;

@end


NS_ASSUME_NONNULL_END
