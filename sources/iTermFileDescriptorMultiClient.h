//
//  iTermFileDescriptorMultiClient.h
//  iTerm2
//
//  Created by George Nachman on 7/25/19.
//

#import <Foundation/Foundation.h>
#import "iTermFileDescriptorMultiClientChild.h"
#import "iTermFileDescriptorMultiClientPendingLaunch.h"
#import "iTermMultiServerProtocol.h"
#import "iTermThreadSafety.h"
#import "iTermTTYState.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermFileDescriptorMultiClient;

extern NSString *const iTermFileDescriptorMultiClientErrorDomain;
typedef NS_ENUM(NSUInteger, iTermFileDescriptorMultiClientErrorCode) {
    iTermFileDescriptorMultiClientErrorCodeConnectionLost,
    iTermFileDescriptorMultiClientErrorCodeNoSuchChild,
    iTermFileDescriptorMultiClientErrorCodeCanNotWait,  // child not terminated
    iTermFileDescriptorMultiClientErrorCodeUnknown,
    iTermFileDescriptorMultiClientErrorCodeForkFailed,
    iTermFileDescriptorMultiClientErrorCodePreemptiveWaitResponse,
    iTermFileDescriptorMultiClientErrorIO,
    iTermFileDescriptorMultiClientErrorProtocolError,  // unparsable message
    iTermFileDescriptorMultiClientErrorCannotConnect,
    iTermFileDescriptorMultiClientErrorAlreadyWaited
};

// No guarantees about which thread delegates are called on.
@protocol iTermFileDescriptorMultiClientDelegate<NSObject>

- (void)fileDescriptorMultiClient:(iTermFileDescriptorMultiClient *)client
                 didDiscoverChild:(iTermFileDescriptorMultiClientChild *)child;

- (void)fileDescriptorMultiClient:(iTermFileDescriptorMultiClient *)client
                childDidTerminate:(iTermFileDescriptorMultiClientChild *)child;

- (void)fileDescriptorMultiClientDidClose:(iTermFileDescriptorMultiClient *)client;

@end

#pragma mark -

@interface iTermFileDescriptorMultiClient : NSObject

@property (nonatomic, weak) id<iTermFileDescriptorMultiClientDelegate> delegate;
@property (nonatomic, readonly) pid_t serverPID;

- (instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Returns YES on success or NO if it failed to create a socket (out of file descriptors maybe?)
- (void)attachToOrLaunchNewDaemonWithCallback:(iTermCallback<id, NSNumber *> *)callback;
- (void)attachWithCallback:(iTermCallback<id, NSNumber *> *)callback;

- (void)launchChildWithExecutablePath:(const char *)path
                                 argv:(char *_Nonnull *_Nonnull)argv
                          environment:(char *_Nonnull *_Nonnull)environment
                                  pwd:(const char *)pwd
                             ttyState:(iTermTTYState)ttyStatePtr
                             callback:(iTermMultiClientLaunchCallback *)callback;

- (void)waitForChild:(iTermFileDescriptorMultiClientChild *)child
  removePreemptively:(BOOL)removePreemptively
            callback:(iTermCallback<id, iTermResult<NSNumber *> *> * _Nullable)callback;  // number is integer status

@end

NS_ASSUME_NONNULL_END
