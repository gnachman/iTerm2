// This implements a select loop that runs in a special thread.

#import <Foundation/Foundation.h>

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

@optional

// Returns YES if this task uses dispatch_source for I/O instead of select().
// Tasks implementing this and returning YES will have their FD skipped in
// TaskNotifier's select() loop. Coprocess FDs are still handled via select().
// Default (not implemented): NO - use select() for backward compatibility.
- (BOOL)useDispatchSource;

@end

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

void UnblockTaskNotifier(void);

@end
