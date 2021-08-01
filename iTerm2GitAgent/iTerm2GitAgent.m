//
//  iTerm2GitAgent.m
//  iTerm2GitAgent
//
//  Created by George Nachman on 7/28/21.
//

#import "iTerm2GitAgent.h"

#import "iTermGitClient.h"
#include <mach/task.h>
#include <mach/task_info.h>
#include <mach-o/dyld.h>
#include <syslog.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/shared_region.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/sysctl.h>

static const char *GetPathToSelf(void) {
    // First ask how much memory we need to store the path.
    uint32_t size = 0;
    char placeholder[1];
    _NSGetExecutablePath(placeholder, &size);

    // Allocate memory and get the path and return it. Plus an extra byte because I live in fear.
    char *pathToExecutable = malloc(size + 1);
    if (_NSGetExecutablePath(pathToExecutable, &size) != 0) {
        free(pathToExecutable);
        return nil;
    }

    return pathToExecutable;
}

@interface iTermGitRecentBranch: NSObject
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, copy) NSString *branch;
@end

@implementation iTermGitRecentBranch

- (NSComparisonResult)compare:(iTermGitRecentBranch *)other {
    return [self.date compare:other.date];
}

@end
 
@implementation iTerm2GitAgent {
    _Atomic int _count;
    int _numWedged;
    dispatch_queue_t _queue;
    NSThread *_minder;
    NSTimeInterval last_cpu_time_;
    int64_t last_system_time_;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.iterm2.pidinfo", DISPATCH_QUEUE_CONCURRENT);
        _minder = [[NSThread alloc] initWithTarget:self selector:@selector(minderMainLoop) object:nil];
        [_minder start];
    }
    return self;
}

- (void)minderMainLoop {
    const NSTimeInterval samplingInterval = 0.1;
    const double maximumUtilization = 20;
    while (!_minder.isCancelled) {
        NSLog(@"minder: sleep for %f sec", samplingInterval);
        usleep(samplingInterval * 1000000.0);

        const double utilization = [self cpuUsage];
        NSLog(@"minder: utilization is %f%%", utilization );

        const NSTimeInterval sleepTime = samplingInterval * (utilization / maximumUtilization - 1);
        NSLog(@"minder: sleep time is %f seconds", sleepTime);
        if (sleepTime > 0) {
            usleep(sleepTime * 1000000.0);
        }
    }
}

static NSTimeInterval TimeSinceBoot(void) {
    const int64_t elapsed = mach_absolute_time();
    static dispatch_once_t onceToken;
    static mach_timebase_info_data_t sTimebaseInfo;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&sTimebaseInfo);
    });

    const double nanoseconds = elapsed * sTimebaseInfo.numer / sTimebaseInfo.denom;
    const double nanosPerSecond = 1000.0 * 1000.0 * 1000.0;
    return nanoseconds / nanosPerSecond;
}

#define TIME_VALUE_TO_TIMEVAL(a, r) do {  \
  (r)->tv_sec = (a)->seconds;             \
  (r)->tv_usec = (a)->microseconds;       \
} while (0)

static const int kMicrosecondsPerSecond = 1000000;

int64_t TimeValToMicroseconds(struct timeval tv) {
  int64_t ret = tv.tv_sec;
  ret *= kMicrosecondsPerSecond;
  ret += tv.tv_usec;
  return ret;
}

- (double)cpuUsage {
    mach_port_t task = mach_task_self();
    if (task == MACH_PORT_NULL) {
        return 0;
    }

    struct task_thread_times_info thread_info_data;
    mach_msg_type_number_t thread_info_count = TASK_THREAD_TIMES_INFO_COUNT;
    kern_return_t kr = task_info(task,
                                 TASK_THREAD_TIMES_INFO,
                                 (task_info_t)&thread_info_data,
                                 &thread_info_count);
    if (kr != KERN_SUCCESS) {
        // Most likely cause: |task| is a zombie.
        return 0;
    }
    struct task_basic_info_64 task_info_data;
    if (![self getTaskInfo:task data:&task_info_data]) {
        return 0;
    }

    struct timeval user_timeval;
    struct timeval system_timeval;
    struct timeval task_timeval;
    TIME_VALUE_TO_TIMEVAL(&thread_info_data.user_time, &user_timeval);
    TIME_VALUE_TO_TIMEVAL(&thread_info_data.system_time, &system_timeval);
    timeradd(&user_timeval, &system_timeval, &task_timeval);

    // ... task info contains terminated time.
    TIME_VALUE_TO_TIMEVAL(&task_info_data.user_time, &user_timeval);
    TIME_VALUE_TO_TIMEVAL(&task_info_data.system_time, &system_timeval);
    timeradd(&user_timeval, &task_timeval, &task_timeval);
    timeradd(&system_timeval, &task_timeval, &task_timeval);

    NSTimeInterval time = TimeSinceBoot();
    int64_t task_time = TimeValToMicroseconds(task_timeval);
    if (last_system_time_ == 0) {
        // First call, just set the last values.
        last_cpu_time_ = time;
        last_system_time_ = task_time;
        return 0;
    }
    int64_t system_time_delta = task_time - last_system_time_;
    int64_t time_delta = (time - last_cpu_time_) * kMicrosecondsPerSecond;

    if (time_delta == 0) {
        return 0;
    }

    last_cpu_time_ = time;
    last_system_time_ = task_time;
    return ((double)system_time_delta * 100.0) / (double)time_delta;
}


- (BOOL)getTaskInfo:(mach_port_t)task data:(struct task_basic_info_64 *)task_info_data {
    if (task == MACH_PORT_NULL) {
        return NO;
    }
    mach_msg_type_number_t count = TASK_BASIC_INFO_64_COUNT;
    kern_return_t kr = task_info(task,
                                 TASK_BASIC_INFO_64,
                                 (task_info_t)task_info_data,
                                 &count);
    return kr == KERN_SUCCESS;
}

- (void)performRiskyBlock:(void (^)(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)))block {
#if DEBUG
    const NSTimeInterval timeout = 30;
#else
    const NSTimeInterval timeout = 10;
#endif
    __block _Atomic BOOL done = NO;
    __block _Atomic BOOL wedged = NO;
    _count++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(timeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (done) {
            return;
        }
        wedged = YES;
        block(NO, nil);
        self->_numWedged++;

        if (self->_numWedged > 128) {
            syslog(LOG_ERR, "There are more than 128 wedged threads. Restarting.");
            _exit(0);
        }
    });
    dispatch_async(_queue, ^{
        block(YES, ^{
            self->_count--;
            if (wedged) {
              // Finished after timeout.
              self->_numWedged--;
              syslog(LOG_INFO,
                     "pidinfo detected slow but not wedged proc_pidinfo. Count is now %d.",
                     self->_numWedged);
                return NO;
            }
            done = YES;
            return YES;
        });
    });
}

- (void)handshakeWithReply:(void (^)(void))reply {
    reply();
}

- (void)setPriority:(int)newPriority {
    int rc = setpriority(PRIO_PROCESS, 0, newPriority);
    if (rc) {
        syslog(LOG_ERR, "setpriority(%d): %s", newPriority, strerror(errno));
    }
}

- (void)requestGitStateForPath:(NSString *)path
                       timeout:(int)timeout
                    completion:(void (^)(iTermGitState * _Nullable))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil);
            syslog(LOG_WARNING, "pidinfo wedged");
            return;
        }

        int pipeFDs[2];
        const int pipeRC = pipe(pipeFDs);
        if (pipeRC == -1) {
            reply(nil);
            completion();
            return;
        }

        const char *exe = GetPathToSelf();
        const char *pathCString = strdup(path.UTF8String);
        char *timeoutStr = NULL;
        asprintf(&timeoutStr, "%d", timeout);
        const int childPID = fork();
        switch (childPID) {
            case 0: {
                // Child
                // Make the write end of the pipe be file descriptor 0.
                if (pipeFDs[1] != 0) {
                  close(0);
                  dup2(pipeFDs[1], 0);
                }
                // Close all file descriptors except 0.
                const int dtableSize = getdtablesize();
                for (int j = 1; j < dtableSize; j++) {
                    close(j);
                }
                // exec because this is a multi-threaded program, and multi-threaded programs have
                // to exec() after fork() if they want to do anything useful.
                execl(exe, exe, "--git-state", pathCString, timeoutStr, 0);
                _exit(0);
            }
            case -1:
                // Failed to fork
                free((void *)timeoutStr);
                free((void *)exe);
                free((void *)pathCString);
                close(pipeFDs[0]);
                close(pipeFDs[1]);
                reply(nil);
                completion();
                break;
            default: {
                // Parent
                free((void *)timeoutStr);
                free((void *)exe);
                free((void *)pathCString);
                close(pipeFDs[1]);
                NSFileHandle *fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:pipeFDs[0] closeOnDealloc:YES];
                int stat_loc = 0;
                int waitRC;
                do {
                    waitRC = waitpid(childPID, &stat_loc, 0);
                } while (waitRC == -1 && errno == EINTR);
                if (WIFSIGNALED(stat_loc)) {
                    // If it timed out don't even try to read because it could be incomplete.
                    reply(nil);
                    completion();
                    break;
                }
                NSData *data = [fileHandle readDataToEndOfFile];
                NSError *error = nil;
                NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
                if (!decoder) {
                    reply(nil);
                    completion();
                    break;
                }

                iTermGitState *state = [decoder decodeTopLevelObjectOfClass:[iTermGitState class]
                                                                     forKey:@"state"
                                                                      error:nil];
                reply(state);
                completion();
            }
        }
    }];
}

- (void)fetchRecentBranchesAt:(NSString *)path count:(NSInteger)maxCount completion:(void (^)(NSArray<NSString *> *))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil);
            syslog(LOG_WARNING, "pidinfo wedged");
            return;
        }
        [self setPriority:20];
        reply([self recentBranchesAt:path count:maxCount]);
        completion();
    }];
}

- (NSArray<NSString *> *)recentBranchesAt:(NSString *)path count:(NSInteger)maxCount {
    iTermGitClient *client = [[iTermGitClient alloc] initWithRepoPath:path];
    if (!client) {
        return nil;
    }
    // git for-each-ref --count=maxCount --sort=-commiterdate refs/heads/ --format=%(refname:short)
    NSMutableArray<iTermGitRecentBranch *> *recentBranches = [NSMutableArray array];
    NSMutableSet<NSString *> *shortNames = [NSMutableSet set];
    [client forEachReference:^(git_reference * _Nonnull ref, BOOL * _Nonnull stop) {
        NSString *fullName = [client fullNameForReference:ref];
        if (![iTermGitClient name:fullName matchesPattern:@"refs/heads"]) {
            NSLog(@"%@ does not match pattern", fullName);
            return;
        }
        NSString *shortName = [client shortNameForReference:ref];
        if (!shortName) {
            return;
        }
        if ([shortNames containsObject:shortName]) {
            return;
        }
        [shortNames addObject:shortName];
        iTermGitRecentBranch *rb = [[iTermGitRecentBranch alloc] init];
        rb.date = [client commiterDateAt:ref];
        NSLog(@"MATCHED: %@ %@", shortName, rb.date);
        rb.branch = shortName;
        [recentBranches addObject:rb];
    }];
    [recentBranches sortUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    for (iTermGitRecentBranch *rb in recentBranches.reverseObjectEnumerator) {
        [results addObject:rb.branch];
        if (results.count == maxCount) {
            break;
        }
    }
    return results;
}


@end
