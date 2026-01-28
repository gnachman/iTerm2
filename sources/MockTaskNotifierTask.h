//
//  MockTaskNotifierTask.h
//  iTerm2SharedARC
//
//  Test-only mock implementation of iTermTask protocol for testing TaskNotifier behavior.
//  Implementation is only compiled when ITERM_DEBUG is defined.
//

#import <Foundation/Foundation.h>
#import "TaskNotifier.h"

NS_ASSUME_NONNULL_BEGIN

/// Mock task that implements iTermTask for testing TaskNotifier behavior.
/// Configurable to test both dispatch source and legacy select() paths.
/// NOTE: Only available when ITERM_DEBUG is defined at compile time.
@interface MockTaskNotifierTask : NSObject<iTermTask>

// MARK: - iTermTask Required Properties

@property (nonatomic) int fd;
@property (nonatomic) pid_t pid;
@property (nonatomic) pid_t pidToWaitOn;
@property (nonatomic) BOOL hasCoprocess;
@property (nonatomic, strong, nullable) Coprocess *coprocess;
@property (nonatomic) BOOL wantsRead;
@property (nonatomic) BOOL wantsWrite;
@property (nonatomic) BOOL writeBufferHasRoom;
@property (nonatomic) BOOL hasBrokenPipe;
@property (atomic) BOOL sshIntegrationActive;

// MARK: - Configuration for Testing

/// Set to true to make useDispatchSource return YES.
/// Default is NO (use select() path).
@property (nonatomic) BOOL dispatchSourceEnabled;

/// If true, this mock does NOT respond to useDispatchSource selector,
/// simulating a legacy task that relies on select().
@property (nonatomic) BOOL simulateLegacyTask;

// MARK: - Call Tracking

/// Number of times processRead was called
@property (nonatomic, readonly) NSInteger processReadCallCount;

/// Number of times processWrite was called
@property (nonatomic, readonly) NSInteger processWriteCallCount;

/// Number of times brokenPipe was called
@property (nonatomic, readonly) NSInteger brokenPipeCallCount;

/// Number of times didRegister was called
@property (nonatomic, readonly) NSInteger didRegisterCallCount;

/// Number of times writeTask:coprocess: was called with coprocess=YES
@property (nonatomic, readonly) NSInteger writeTaskCoprocessCallCount;

/// Last data received via writeTask:coprocess: with coprocess=YES
@property (nonatomic, strong, readonly, nullable) NSData *lastCoprocessData;

// MARK: - Test Helpers

/// Reset all call counts and state for a fresh test
- (void)reset;

/// Wait for processRead to be called at least `count` times, with timeout
/// Returns YES if reached, NO if timed out
- (BOOL)waitForProcessReadCalls:(NSInteger)count timeout:(NSTimeInterval)timeout;

/// Wait for writeTask:coprocess: to be called at least `count` times, with timeout
/// Returns YES if reached, NO if timed out
- (BOOL)waitForCoprocessWriteCalls:(NSInteger)count timeout:(NSTimeInterval)timeout;

/// Close the file descriptor if valid
- (void)closeFd;

// MARK: - Factory Methods

/// Create a pipe and set fd to the read end.
/// Returns the write fd via the out parameter.
/// Returns nil on failure.
/// Caller is responsible for closing both FDs.
+ (nullable MockTaskNotifierTask *)createPipeTaskWithWriteFd:(int *)writeFd;

@end

NS_ASSUME_NONNULL_END
