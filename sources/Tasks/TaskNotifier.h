// This implements a select loop that runs in a special thread.

#import <Foundation/Foundation.h>
#include <sys/select.h>

extern NSString *const kCoprocessStatusChangeNotification;

@class Coprocess;
@class iTermOwnedFileDescriptor;
@class iTermTaskInputQueue;
@class PTYTask;

@protocol iTermTask<NSObject>

// The task's file descriptor, or nil if there is none. Task I/O monitors lease it so it is not
// closed while they watch it.
@property (nonatomic, readonly) iTermOwnedFileDescriptor *ownedFileDescriptor;
// What the task reads instead of its file descriptor, or nil. A tmux pane reads its output from
// here when task I/O monitors are on. Only task I/O monitors use it.
@property (nonatomic, readonly) iTermTaskInputQueue *inputQueue;

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

// Used only by task I/O monitors (see +[TaskNotifier usesTaskIOMonitors]).
// Any thread. Whether processRead can pass on what it reads without blocking.
@property (nonatomic, readonly) BOOL hasReadCapacity;
// Any thread. Runs `block` asynchronously on `queue` once hasReadCapacity may have become true. It
// may run while there is still no capacity, so check again.
- (void)notifyWhenReadCapacityAvailableOnQueue:(dispatch_queue_t)queue block:(void (^)(void))block;
// Called with TaskNotifier's lock held. Returns YES the first time it is called with `pid`, and NO
// after that. A task is deregistered many times (by brokenPipe, a restart, -stop, and dealloc), and
// a reaped pid may belong to another process, so each of a task's pids goes to the reaper once.
- (BOOL)markPidHandedToReaper:(pid_t)pid;

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
// Deregisters `task`, then calls `completion` on the main queue. With task I/O monitors, that is once
// nothing is servicing the task anymore, so it can't call into its delegate again.
- (void)deregisterTask:(id<iTermTask>)task completion:(void (^)(void))completion;

- (void)unblock;
// Call after changing what `task`'s wantsRead, wantsWrite, or coprocess return.
- (void)unblockTask:(id<iTermTask>)task;
- (void)run;

- (void)waitForPid:(pid_t)pid;

- (void)notifyCoprocessChange;

// Whether the shared instance uses the new task I/O implementation (the useTaskIOMonitors advanced
// setting). Read once per process, since the two implementations must never be mixed.
+ (BOOL)usesTaskIOMonitors;

#pragma mark - Testing

// Creates an instance that is independent of the shared instance. It has its own thread (started
// by -startForTesting) and its own unblock pipe. UnblockTaskNotifier() does not wake it; call
// -unblock instead.
// If `select` is nil, select(2) is used.
// If `coprocessChangeHandler` is nil, coprocess changes are posted on the main thread. Otherwise
// the handler is called on the notifier's thread.
// If `reaper` is nil, pids to reap go in a dead pool that the loop polls. Otherwise each is passed
// to `reaper`, which is called with the notifier's lock held.
- (instancetype)initForTestingWithSelect:(iTermTaskNotifierSelect)select
                  coprocessChangeHandler:(void (^)(void))coprocessChangeHandler
                                  reaper:(void (^)(pid_t pid))reaper;
- (void)startForTesting;

// Like -initForTestingWithSelect:coprocessChangeHandler:reaper:, but services tasks with task I/O
// monitors instead of a select loop. `reaper` is required. -startForTesting does nothing.
- (instancetype)initForTestingWithTaskIOMonitorsAndCoprocessChangeHandler:(void (^)(void))coprocessChangeHandler
                                                                    reaper:(void (^)(pid_t pid))reaper;

// Task I/O monitors only. Waits until every registered task's monitor has handled whatever is
// ready and every deregistered task's monitor has stopped using its file descriptors. Returns NO on
// timeout.
- (BOOL)flushForTestingWithTimeout:(NSTimeInterval)timeout;

// Task I/O monitors only. Like -flushForTestingWithTimeout:, but only for `task`, so other tasks may
// keep adding input meanwhile.
- (BOOL)flushTaskForTesting:(id<iTermTask>)task timeout:(NSTimeInterval)timeout
    NS_SWIFT_NAME(flushForTesting(task:timeout:));

// Stops the thread started by -startForTesting. Returns NO if it did not stop within `timeout`,
// for example because a task's callback is blocked.
- (BOOL)stopForTestingWithTimeout:(NSTimeInterval)timeout;

void UnblockTaskNotifier(void);

@end
