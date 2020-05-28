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

- (void)processRead;
- (void)processWrite;
// Called on any thread
- (void)brokenPipe;
- (void)writeTask:(NSData *)data;

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

- (void)pipeDidBreakForExternalProcessID:(pid_t)pid
                                  status:(int)status;

void UnblockTaskNotifier(void);

@end
