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

+ (BOOL)available;
+ (BOOL)pathIsSafe:(NSString *)path;

+ (void)getOrCreatePrimaryConnectionWithCallback:(iTermCallback<id, iTermMultiServerConnection *> *)callback;

+ (void)getConnectionForSocketNumber:(int)number
                    createIfPossible:(BOOL)shouldCreate
                            callback:(iTermCallback<id, iTermMultiServerConnection *> *)callback;

- (instancetype)init NS_UNAVAILABLE;

- (void)attachToProcessID:(pid_t)pid
                 callback:(iTermCallback<id, iTermFileDescriptorMultiClientChild *> *)callback;

// In-process freeze/thaw support. Re-adds a child that was previously attached
// (and therefore removed from unattachedChildren) back into the unattached list
// so a later -attachToProcessID: can re-adopt it WITHOUT tearing down and
// re-handshaking this connection (which is shared by every session on the
// daemon). The child's file descriptor is left open by the caller.
- (void)reinsertUnattachedChild:(iTermFileDescriptorMultiClientChild *)child;

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
