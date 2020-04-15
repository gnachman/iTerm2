//
//  iTermFileDescriptorMultiClientState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import <Foundation/Foundation.h>

#import "iTermFileDescriptorMultiClientChild.h"
#import "iTermFileDescriptorMultiClientPendingLaunch.h"
#import "iTermThreadSafety.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermFileDescriptorMultiClientState;

@interface iTermFileDescriptorMultiClientState: iTermSynchronizedState<iTermFileDescriptorMultiClientState *>
@property (nonatomic) int readFD;
@property (nonatomic) int writeFD;
@property (nonatomic) pid_t serverPID;
@property (nonatomic, readonly) NSMutableArray<iTermFileDescriptorMultiClientChild *> *children;
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, iTermFileDescriptorMultiClientPendingLaunch *> *pendingLaunches;
@property (nonatomic, strong) dispatch_source_t daemonProcessSource;

- (void)whenWritable:(void (^)(iTermFileDescriptorMultiClientState *state))block;
- (void)whenReadable:(void (^)(iTermFileDescriptorMultiClientState *state))block;

@end

NS_ASSUME_NONNULL_END
