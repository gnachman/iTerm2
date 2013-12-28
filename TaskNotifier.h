// This implements a select loop that runs in a special thread.

#import <Foundation/Foundation.h>

@class PTYTask;

@interface TaskNotifier : NSObject

+ (TaskNotifier*)sharedInstance;

- (id)init;
- (void)dealloc;

- (void)registerTask:(PTYTask*)task;
- (void)deregisterTask:(PTYTask*)task;

- (void)unblock;
- (void)run;

- (void)waitForPid:(pid_t)pid;

@end
