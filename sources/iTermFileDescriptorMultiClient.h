//
//  iTermFileDescriptorMultiClient.h
//  iTerm2
//
//  Created by George Nachman on 7/25/19.
//

#import <Foundation/Foundation.h>
#import "iTermMultiServerProtocol.h"
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
    iTermFileDescriptorMultiClientErrorCodePreemptiveWaitResponse
};

@interface iTermFileDescriptorMultiClientChild : NSObject
@property (nonatomic, readonly) pid_t pid;
@property (nonatomic, readonly) NSString *executablePath;
@property (nonatomic, readonly) NSArray<NSString *> *args;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, readonly) BOOL utf8;
@property (nonatomic, readonly) NSString *initialDirectory;
@property (nonatomic, readonly) BOOL hasTerminated;
@property (nonatomic, readonly) BOOL haveWaited;  // only for non-preemptive waits
@property (nonatomic, readonly) BOOL haveSentPreemptiveWait;
@property (nonatomic, readonly) int terminationStatus;  // only defined if haveWaited is YES
@property (nonatomic, readonly) int fd;
@property (nonatomic, readonly) NSString *tty;
@end

@protocol iTermFileDescriptorMultiClientDelegate<NSObject>

- (void)fileDescriptorMultiClient:(iTermFileDescriptorMultiClient *)client
                 didDiscoverChild:(iTermFileDescriptorMultiClientChild *)child;

- (void)fileDescriptorMultiClient:(iTermFileDescriptorMultiClient *)client
                childDidTerminate:(iTermFileDescriptorMultiClientChild *)child;

- (void)fileDescriptorMultiClientDidClose:(iTermFileDescriptorMultiClient *)client;

@end

@interface iTermFileDescriptorMultiClient : NSObject

@property (nonatomic, weak) id<iTermFileDescriptorMultiClientDelegate> delegate;
@property (nonatomic, readonly) pid_t serverPID;

- (instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Returns YES on success or NO if it failed to create a socket (out of file descriptors maybe?)
- (BOOL)attachOrLaunchServer;
- (BOOL)attach;

- (void)launchChildWithExecutablePath:(const char *)path
                                 argv:(const char **)argv
                          environment:(const char **)environment
                                  pwd:(const char *)pwd
                             ttyState:(iTermTTYState *)ttyStatePtr
                           completion:(void (^)(iTermFileDescriptorMultiClientChild * _Nullable child, NSError * _Nullable))completion;

- (void)waitForChild:(iTermFileDescriptorMultiClientChild *)child
  removePreemptively:(BOOL)removePreemptively
          completion:(void (^)(int status, NSError * _Nullable))completion;

@end

NS_ASSUME_NONNULL_END
