// This implements a select loop that runs in a special thread.

#import <Foundation/Foundation.h>
#include <sys/select.h>

extern NSString *const kCoprocessStatusChangeNotification;

@class Coprocess;
@class PTYTask;

@protocol iTermTask<NSObject>

@property (nonatomic, readonly) int fd;

@property (nonatomic, readonly) pid_t pid;
@property (nonatomic, readonly) pid_t pidToWaitOn;

@property (nonatomic, readonly) BOOL hasCoprocess;
@property (nonatomic, strong) Coprocess *coprocess;

@property (nonatomic, readonly) BOOL wantsRead;
@property (nonatomic, readonly) BOOL wantsWrite;
@property (nonatomic, readonly) BOOL writeBufferHasRoom;
@property (nonatomic, readonly) BOOL hasBrokenPipe;
@property (atomic, readonly) BOOL sshIntegrationActive;

- (void)processRead;
- (void)processWrite;
// Called on any thread
- (void)brokenPipe;
- (void)writeTask:(NSData *)data coprocess:(BOOL)coprocess;
- (void)didRegister;

@end

// Has the same signature and semantics as select(2). Tests use it to observe or script the loop.
typedef int (^iTermTaskNotifierSelect)(int nfds,
                                       fd_set *readfds,
                                       fd_set *writefds,
                                       fd_set *errorfds,
                                       struct timeval *timeout);

@interface TaskNotifier : NSObject

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

- (void)registerTask:(id<iTermTask>)task;
- (void)deregisterTask:(id<iTermTask>)task;

- (void)unblock;
- (void)run;

- (void)waitForPid:(pid_t)pid;

- (void)notifyCoprocessChange;

- (void)lock;
- (void)unlock;

#pragma mark - Testing

// Creates an instance that is independent of the shared instance. It has its own thread (started
// by -startForTesting) and its own unblock pipe. UnblockTaskNotifier() does not wake it; call
// -unblock instead.
// If `select` is nil, select(2) is used.
// If `coprocessChangeHandler` is nil, coprocess changes are posted on the main thread (which
// blocks the loop until main runs it). Otherwise the handler is called on the notifier's thread.
- (instancetype)initForTestingWithSelect:(iTermTaskNotifierSelect)select
                  coprocessChangeHandler:(void (^)(void))coprocessChangeHandler;
- (void)startForTesting;

// Stops the thread started by -startForTesting. Returns NO if it did not stop within `timeout`,
// for example because a task's callback is blocked.
- (BOOL)stopForTestingWithTimeout:(NSTimeInterval)timeout;

void UnblockTaskNotifier(void);

@end
