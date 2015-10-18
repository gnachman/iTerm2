// This implements a select loop that runs in a special thread.

#import <Foundation/Foundation.h>

// Posted just before select() is called.
extern NSString *const kTaskNotifierDidSpin;

@class PTYTask;

@interface TaskNotifier : NSObject

+ (instancetype)sharedInstance;

- (void)registerTask:(PTYTask *)task;
- (void)deregisterTask:(PTYTask *)task;

- (void)unblock;
- (void)run;

- (void)waitForPid:(pid_t)pid;

- (void)notifyCoprocessChange;

- (void)lock;
- (void)unlock;

@end
