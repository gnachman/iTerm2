//
//  TaskNotifier.m
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import "TaskNotifier.h"
#import "Coprocess.h"
#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"

#include <stdatomic.h>
#include <sys/time.h>
#include <sys/select.h>

#define PtyTaskDebugLog(args...)

NSString *const kCoprocessStatusChangeNotification = @"kCoprocessStatusChangeNotification";

// The shared instance's unblock pipe's write end. UnblockTaskNotifier() reads it from a signal
// handler, so it is a plain int that is written once.
static volatile int gSharedUnblockPipeW = -1;
static TaskNotifier *gSharedInstance;

// The select loop is the only user of raw descriptor numbers. Everything else does I/O through
// iTermOwnedFileDescriptor, which can't be closed out from under it.
static int iTermUnsafeFileDescriptor(iTermOwnedFileDescriptor *owned) {
    return owned ? owned.unsafeFileDescriptor : -1;
}

static int iTermTaskUnsafeFileDescriptor(id<iTermTask> task) {
    return iTermUnsafeFileDescriptor(task.ownedFileDescriptor);
}

@implementation TaskNotifier
{
    int _unblockPipeR;
    int _unblockPipeW;

    // Testing only. When nil, select(2) is called directly.
    iTermTaskNotifierSelect _select;
    // Testing only. When nil, coprocess changes are posted on the main thread.
    void (^_coprocessChangeHandler)(void);
    // When nil, pids to reap go in `deadpool`.
    void (^_reaper)(pid_t);
    // When set, tasks are serviced by task I/O monitors instead of the select loop, which does not
    // run.
    iTermTaskIOMonitorRegistry *_monitors;
    // Set to stop the run loop. Only test instances are ever stopped.
    atomic_bool _stopped;
    // Signaled when -run returns.
    dispatch_semaphore_t _didStop;
    // Testing only. Set by -startForTesting.
    BOOL _startedForTesting;

    NSMutableArray<id<iTermTask>> *_tasks;
    // Set to true when an element of '_tasks' was modified
    BOOL tasksChanged;
    // Protects '_tasks' and 'tasksChanged'.
    NSRecursiveLock *tasksLock;

    // A set of NSNumber*s holding pids of tasks that need to be wait()ed on
    NSMutableSet* deadpool;
}


+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        TaskNotifier *notifier = [[self alloc] init];
        if ([self usesTaskIOMonitors]) {
            [notifier useTaskIOMonitorsWithCoprocessChangeHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:kCoprocessStatusChangeNotification
                                                                        object:nil];
                });
            } reaper:^(pid_t pid) {
                [[iTermChildReaper sharedInstance] reapProcessWithID:pid];
            }];
        }
        gSharedUnblockPipeW = notifier->_unblockPipeW;
        gSharedInstance = notifier;
        if (!notifier->_monitors) {
            [NSThread detachNewThreadSelector:@selector(run)
                                     toTarget:gSharedInstance
                                   withObject:nil];
        }
    });
    return gSharedInstance;
}

+ (BOOL)usesTaskIOMonitors {
    static BOOL value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        value = [iTermAdvancedSettingsModel useTaskIOMonitors];
        RLog(@"useTaskIOMonitors=%@", value ? @"YES" : @"NO");
    });
    return value;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _unblockPipeR = -1;
        _unblockPipeW = -1;
        atomic_init(&_stopped, false);
        _didStop = dispatch_semaphore_create(0);
        deadpool = [[NSMutableSet alloc] init];
        _tasks = [[NSMutableArray alloc] init];
        tasksLock = [[NSRecursiveLock alloc] init];
        tasksChanged = NO;

        int unblockPipe[2];
        if (pipe(unblockPipe) != 0) {
            [self release];
            return nil;
        }
        // Set close-on-exec and non-blocking on both sides of the pipe.
        for (int i = 0; i < 2; i++) {
            int flags;
            flags = fcntl(unblockPipe[0], F_GETFD);
            fcntl(unblockPipe[i], F_SETFD, flags | FD_CLOEXEC);
            fcntl(unblockPipe[i], F_SETFL, O_NONBLOCK);
        }
        _unblockPipeR = unblockPipe[0];
        _unblockPipeW = unblockPipe[1];
    }
    return self;
}

- (instancetype)initForTestingWithSelect:(iTermTaskNotifierSelect)select
                  coprocessChangeHandler:(void (^)(void))coprocessChangeHandler
                                  reaper:(void (^)(pid_t))reaper {
    self = [self init];
    if (self) {
        _select = [select copy];
        _coprocessChangeHandler = [coprocessChangeHandler copy];
        _reaper = [reaper copy];
    }
    return self;
}

- (instancetype)initForTestingWithTaskIOMonitorsAndCoprocessChangeHandler:(void (^)(void))coprocessChangeHandler
                                                                    reaper:(void (^)(pid_t))reaper {
    self = [self init];
    if (self) {
        [self useTaskIOMonitorsWithCoprocessChangeHandler:coprocessChangeHandler reaper:reaper];
    }
    return self;
}

- (void)useTaskIOMonitorsWithCoprocessChangeHandler:(void (^)(void))coprocessChangeHandler
                                             reaper:(void (^)(pid_t))reaper {
    ITAssertWithMessage(reaper != nil, @"Task I/O monitors need a reaper");
    _reaper = [reaper copy];
    _monitors = [[iTermTaskIOMonitorRegistry alloc] initWithReaper:reaper
                                            coprocessChangeHandler:coprocessChangeHandler];
}

- (void)dealloc {
    [_monitors release];
    [_tasks release];
    [tasksLock release];
    [deadpool release];
    [_select release];
    [_coprocessChangeHandler release];
    [_reaper release];
    dispatch_release(_didStop);
    [self closeUnblockPipe];
    [super dealloc];
}

- (void)closeUnblockPipe {
    // gSharedUnblockPipeW must stay valid forever. Clearing it first would not help because a
    // signal handler may already have loaded it, and the closed fd could then be reused.
    ITAssertWithMessage(self != gSharedInstance, @"The shared instance's unblock pipe must never be closed");
    if (_unblockPipeR >= 0) {
        close(_unblockPipeR);
        _unblockPipeR = -1;
    }
    if (_unblockPipeW >= 0) {
        close(_unblockPipeW);
        _unblockPipeW = -1;
    }
}

- (void)startForTesting {
    ITAssertWithMessage(self != gSharedInstance, @"Only test instances may be started this way");
    ITAssertWithMessage(!_startedForTesting, @"Already started");
    _startedForTesting = YES;
    if (_monitors) {
        return;
    }
    NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:nil];
    // Tests wait on this thread from main. Match main's QoS to avoid a priority inversion.
    thread.qualityOfService = NSQualityOfServiceUserInteractive;
    [thread start];
    [thread release];
}

- (BOOL)stopForTestingWithTimeout:(NSTimeInterval)timeout {
    ITAssertWithMessage(_startedForTesting, @"Not started for testing");
    ITAssertWithMessage(!atomic_load(&_stopped), @"Already stopped");
    if (_monitors) {
        atomic_store(&_stopped, true);
        return [self flushForTestingWithTimeout:timeout];
    }
    // Set the flag before writing to the pipe. The pipe stays readable until the loop drains it,
    // so a stop that arrives between the loop's check of the flag and select() is not lost.
    atomic_store_explicit(&_stopped, true, memory_order_release);
    [self unblock];
    const long result = dispatch_semaphore_wait(_didStop,
                                                dispatch_time(DISPATCH_TIME_NOW,
                                                              (int64_t)(timeout * NSEC_PER_SEC)));
    if (result != 0) {
        return NO;
    }
    [self closeUnblockPipe];
    return YES;
}

- (BOOL)flushForTestingWithTimeout:(NSTimeInterval)timeout {
    ITAssertWithMessage(_monitors != nil, @"Only task I/O monitors can be flushed");
    return [_monitors flushForTestingWithTimeout:timeout];
}

- (BOOL)flushTaskForTesting:(id<iTermTask>)task timeout:(NSTimeInterval)timeout {
    ITAssertWithMessage(_monitors != nil, @"Only task I/O monitors can be flushed");
    return [_monitors flushTaskForTesting:task timeout:timeout];
}

- (void)registerTask:(id<iTermTask>)task {
    if (_monitors) {
        switch ([_monitors registerTask:task]) {
            case iTermTaskIOMonitorRegistrationRegistered:
                [self dispatchDidRegister:task];
                return;
            case iTermTaskIOMonitorRegistrationAlreadyRegistered:
                return;
            case iTermTaskIOMonitorRegistrationNoFileDescriptor:
                // The select loop deregisters such a task, reaping its processes, on its next
                // iteration.
                RLog(@"Deregister %@, which has no file descriptor", task);
                [self dispatchDidRegister:task];
                [self deregisterTask:task];
                return;
        }
    }
    PtyTaskDebugLog(@"registerTask: lock\n");
    [tasksLock lock];
    if ([_tasks containsObject:task]) {
        DLog(@"Ignore redundant registration of %@", task);
        [tasksLock unlock];
        return;
    }
    PtyTaskDebugLog(@"Add task at %p\n", (void*)task);
    [_tasks addObject:task];
    PtyTaskDebugLog(@"There are now %lu tasks\n", (unsigned long)_tasks.count);
    tasksChanged = YES;
    PtyTaskDebugLog(@"registerTask: unlock\n");
    [tasksLock unlock];
    [self unblock];
    [self dispatchDidRegister:task];
}

- (void)dispatchDidRegister:(id<iTermTask>)task {
    __weak __typeof(task) weakTask = task;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakTask didRegister];
    });
}

- (void)deregisterTask:(id<iTermTask>)task {
    PtyTaskDebugLog(@"deregisterTask: lock\n");
    [tasksLock lock];
    PtyTaskDebugLog(@"Begin remove task %p\n", (void*)task);
    PtyTaskDebugLog(@"Add %d to deadpool", [task pid]);
    pid_t pidToWaitOn = task.pidToWaitOn;
    if (pidToWaitOn > 0) {
        [self reapPid:pidToWaitOn];
    }
    if ([task hasCoprocess]) {
        [self reapPid:[[task coprocess] pid]];
    }
    if (_monitors) {
        [_monitors deregisterTask:task];
        [tasksLock unlock];
        return;
    }
    [_tasks removeObject:task];
    tasksChanged = YES;
    PtyTaskDebugLog(@"End remove task %p. There are now %lu tasks.\n",
                    (void *)task,
                    (unsigned long)[_tasks count]);
    PtyTaskDebugLog(@"deregisterTask: unlock\n");
    [tasksLock unlock];
    [self unblock];
}

- (void)waitForPid:(pid_t)pid {
    [tasksLock lock];
    [self reapPid:pid];
    [tasksLock unlock];
    [self unblock];
}

// Call with tasksLock held.
- (void)reapPid:(pid_t)pid {
    if (pid <= 0) {
        // waitpid treats 0 and negative pids as process groups, which would reap other code's
        // children.
        DLog(@"Ignore request to reap pid %@", @(pid));
        return;
    }
    if (_reaper) {
        _reaper(pid);
    } else {
        [deadpool addObject:@(pid)];
    }
}

- (void)unblock {
    if (_monitors) {
        // Nothing reads the pipe.
        return;
    }
    char dummy = 0;
    write(_unblockPipeW, &dummy, 1);
}

- (void)unblockTask:(id<iTermTask>)task {
    if (_monitors) {
        [_monitors unblockTask:task];
    } else {
        [self unblock];
    }
}

void UnblockTaskNotifier(void) {
    // This is called in a signal handler and must only call functions listed
    // as safe in sigaction(2)'s man page. It must also preserve errno, since write() may set it
    // (e.g., EAGAIN when the pipe is full) while the interrupted code is about to read it.
    const int fd = gSharedUnblockPipeW;
    if (fd < 0) {
        return;
    }
    const int savedErrno = errno;
    char dummy = 0;
    write(fd, &dummy, 1);
    errno = savedErrno;
}

- (BOOL)handleReadOnFileDescriptor:(int)fd task:(id<iTermTask>)task fdSet:(fd_set *)fdSet {
    if (FD_ISSET(fd, fdSet)) {
        PtyTaskDebugLog(@"run/processRead: unlock");
        [tasksLock unlock];
        [task processRead];
        PtyTaskDebugLog(@"run/processRead: lock");
        [tasksLock lock];
        if (tasksChanged) {
            PtyTaskDebugLog(@"Restart iteration\n");
            tasksChanged = NO;
            return YES;
        }
    }
    return NO;
}

- (BOOL)handleWriteOnFileDescriptor:(int)fd task:(id<iTermTask>)task fdSet:(fd_set *)fdSet {
    if (FD_ISSET(fd, fdSet)) {
        PtyTaskDebugLog(@"run/processWrite: unlock");
        [tasksLock unlock];
        [task retain];
        [task processWrite];
        [task release];
        PtyTaskDebugLog(@"run/processWrite: lock");
        [tasksLock lock];
        if (tasksChanged) {
            PtyTaskDebugLog(@"Restart iteration\n");
            tasksChanged = NO;
            return YES;
        }
    }
    return NO;
}

- (BOOL)handleErrorOnFileDescriptor:(int)fd task:(id<iTermTask>)task fdSet:(fd_set *)fdSet {
    if (FD_ISSET(fd, fdSet)) {
        PtyTaskDebugLog(@"run/brokenPipe: unlock");
        [tasksLock unlock];
        // brokenPipe will call deregisterTask and add the pid to
        // deadpool.
        [task brokenPipe];
        PtyTaskDebugLog(@"run/brokenPipe: lock");
        [tasksLock lock];
        if (tasksChanged) {
            PtyTaskDebugLog(@"Restart iteration\n");
            tasksChanged = NO;
            return YES;
        }
    }
    return NO;
}

- (void)handleReadOnFileDescriptor:(int)fd
                              task:(id<iTermTask>)task
                     withCoprocess:(Coprocess *)coprocess
                             fdSet:(fd_set *)fdSet {
    if (![coprocess eof] && FD_ISSET(fd, fdSet)) {
        PtyTaskDebugLog(@"Reading from coprocess");
        [coprocess read];
        [task writeTask:coprocess.inputBuffer coprocess:YES];
        [coprocess.inputBuffer setLength:0];
    }
}

- (void)handleErrorOnFileDescriptor:(int)fd
                      withCoprocess:(Coprocess *)coprocess
                              fdSet:(fd_set *)fdSet {
    if (FD_ISSET(fd, fdSet)) {
        PtyTaskDebugLog(@"EOF on coprocess %@", coprocess);
        coprocess.eof = YES;
    }
}

- (void)handleWriteOnFileDescriptor:(int)coprocessWriteFd
                      withCoprocess:(Coprocess *)coprocess
                              fdSet:(fd_set *)fdSet {
    if (FD_ISSET(coprocessWriteFd, fdSet)) {
        if (![coprocess eof]) {
            PtyTaskDebugLog(@"Write to coprocess %@", coprocess);
            [coprocess write];
        }
    }
}

- (void)run {
    fd_set rfds;
    fd_set wfds;
    fd_set efds;
    int highfd;
    NSEnumerator *iter;
    NSAutoreleasePool *autoreleasePool = [[NSAutoreleasePool alloc] init];

    // FIXME: replace this with something better...
    while (!atomic_load_explicit(&_stopped, memory_order_acquire)) {

        FD_ZERO(&rfds);
        FD_ZERO(&wfds);
        FD_ZERO(&efds);

        // Unblock pipe to interrupt select() whenever a PTYTask register/unregisters
        highfd = _unblockPipeR;
        FD_SET(_unblockPipeR, &rfds);
        NSMutableSet *handledFds = [[NSMutableSet alloc] initWithCapacity:256];

        // Add all the PTYTask pipes
        PtyTaskDebugLog(@"run1: lock");
        [tasksLock lock];
        PtyTaskDebugLog(@"Begin cleaning out dead tasks");
        NSMutableArray<id<iTermTask>> *tasksToDeregister = [NSMutableArray array];
        for (id<iTermTask> theTask in _tasks) {
            if (iTermTaskUnsafeFileDescriptor(theTask) < 0) {
                PtyTaskDebugLog(@"Deregister dead task %@\n", theTask);
                [tasksToDeregister addObject:theTask];
            }
        }
        for (id<iTermTask> theTask in tasksToDeregister) {
            [self deregisterTask:theTask];
        }

        if ([deadpool count] > 0) {
            // waitpid() on pids that we think are dead or will be dead soon.
            NSMutableSet* newDeadpool = [NSMutableSet setWithCapacity:[deadpool count]];
            for (NSNumber* pid in deadpool) {
                if ([pid intValue] < 0) {
                    continue;
                }
                int statLoc;
                PtyTaskDebugLog(@"wait on %d", [pid intValue]);
                pid_t waitresult = waitpid([pid intValue], &statLoc, WNOHANG);
                if (waitresult == 0) {
                    // the process is not yet dead, so put it back in the pool
                    [newDeadpool addObject:pid];
                } else if (waitresult < 0) {
                    if (errno != ECHILD) {
                        PtyTaskDebugLog(@"  wait failed with %d (%s), adding back to deadpool", errno, strerror(errno));
                        [newDeadpool addObject:pid];
                    } else {
                        PtyTaskDebugLog(@"  wait failed with ECHILD, I guess we already waited on it.");
                    }
                }
            }
            [deadpool release];
            deadpool = [newDeadpool retain];
        }

        // Figure out the file descriptors to select on.
        PtyTaskDebugLog(@"Begin enumeration over %lu tasks\n", (unsigned long)[_tasks count]);
        for (id<iTermTask> task in _tasks) {
            PtyTaskDebugLog(@"Got task %@\n", task);
            int fd = iTermTaskUnsafeFileDescriptor(task);
            if (fd < 0) {
                PtyTaskDebugLog(@"Task has fd of %d\n", fd);
            } else {
                // PtyTaskDebugLog(@"Select on fd %d\n", fd);
                if (fd > highfd) {
                    highfd = fd;
                }
                if ([task wantsRead]) {
                    FD_SET(fd, &rfds);
                }
                if ([task wantsWrite]) {
                    FD_SET(fd, &wfds);
                }
                FD_SET(fd, &efds);
            }

            @synchronized (task) {
                Coprocess *coprocess = [task coprocess];
                if (coprocess) {
                    if ([coprocess wantToRead] && [task writeBufferHasRoom]) {
                        int rfd = iTermUnsafeFileDescriptor(coprocess.ownedReadFileDescriptor);
                        if (rfd > highfd) {
                            highfd = rfd;
                        }
                        FD_SET(rfd, &rfds);
                    }
                    if ([coprocess wantToWrite]) {
                        int wfd = iTermUnsafeFileDescriptor(coprocess.ownedWriteFileDescriptor);
                        if (wfd > highfd) {
                            highfd = wfd;
                        }
                        FD_SET(wfd, &wfds);
                    }
                    if (![coprocess eof]) {
                        int rfd = iTermUnsafeFileDescriptor(coprocess.ownedReadFileDescriptor);
                        if (rfd > highfd) {
                            highfd = rfd;
                        }
                        FD_SET(rfd, &efds);
                    }
                }
            }
        }

        PtyTaskDebugLog(@"run1: unlock");
        [tasksLock unlock];

        [autoreleasePool drain];
        autoreleasePool = [[NSAutoreleasePool alloc] init];

        // Poll...
        int selectResult;
        if (_select) {
            selectResult = _select(highfd+1, &rfds, &wfds, &efds, NULL);
        } else {
            selectResult = select(highfd+1, &rfds, &wfds, &efds, NULL);
        }
        if (selectResult <= 0) {
            switch(errno) {
                case EAGAIN:
                case EINTR:
                default:
                    goto breakloop;
                    // If the file descriptor is closed in the main thread there's a race where sometimes you'll get an EBADF.
            }
        }

        // Interrupted?
        if (FD_ISSET(_unblockPipeR, &rfds)) {
            char dummy[32];
            do {
                read(_unblockPipeR, dummy, sizeof(dummy));
            } while (errno != EAGAIN);
        }

        // Check for read events on PTYTask pipes
        PtyTaskDebugLog(@"run2: lock");
        [tasksLock lock];
        PtyTaskDebugLog(@"Iterating over %lu tasks\n", (unsigned long)_tasks.count);
        iter = [_tasks objectEnumerator];
        BOOL notifyOfCoprocessChange = NO;

        id<iTermTask> task;
        while ((task = [iter nextObject])) {
            PtyTaskDebugLog(@"Got task %@\n", task);
            int fd = iTermTaskUnsafeFileDescriptor(task);

            if (fd >= 0) {
                // This is mostly paranoia, but if two threads
                // end up with the same fd (because one closed
                // and there was a race condition) then trying
                // to read twice would hang.

                if ([handledFds containsObject:@(fd)]) {
                    PtyTaskDebugLog(@"Duplicate fd %d", fd);
                    continue;
                }
                [[task retain] autorelease];
                [handledFds addObject:@(fd)];

                if ([self handleReadOnFileDescriptor:fd task:task fdSet:&rfds]) {
                    iter = [_tasks objectEnumerator];
                }
                if ([self handleWriteOnFileDescriptor:fd task:task fdSet:&wfds]) {
                    iter = [_tasks objectEnumerator];
                }
                if ([self handleErrorOnFileDescriptor:fd task:task fdSet:&efds]) {
                    iter = [_tasks objectEnumerator];
                }
                // Move input around between coprocess and main process.
                if (iTermTaskUnsafeFileDescriptor(task) >= 0 && ![task hasBrokenPipe]) {  // Make sure the pipe wasn't just broken.
                    @synchronized (task) {
                        Coprocess *coprocess = [task coprocess];
                        if (coprocess) {
                            fd = iTermUnsafeFileDescriptor(coprocess.ownedReadFileDescriptor);
                            if ([handledFds containsObject:@(fd)]) {
                                NSLog(@"Duplicate fd %d", fd);
                                continue;
                            }
                            [handledFds addObject:@(fd)];

                            [self handleReadOnFileDescriptor:fd task:task withCoprocess:coprocess fdSet:&rfds];
                            [self handleErrorOnFileDescriptor:fd withCoprocess:coprocess fdSet:&efds];

                            // Handle writes
                            int coprocessWriteFd = iTermUnsafeFileDescriptor(coprocess.ownedWriteFileDescriptor);
                            if ([handledFds containsObject:@(coprocessWriteFd)]) {
                                NSLog(@"Duplicate fd %d", coprocessWriteFd);
                                continue;
                            }
                            [handledFds addObject:@(coprocessWriteFd)];
                            [self handleWriteOnFileDescriptor:coprocessWriteFd withCoprocess:coprocess fdSet:&wfds];

                            if ([coprocess eof]) {
                                // terminate signals the pid, so reap it only afterwards.
                                const pid_t coprocessPid = [coprocess pid];
                                [coprocess terminate];
                                [self reapPid:coprocessPid];
                                [task setCoprocess:nil];
                                notifyOfCoprocessChange = YES;
                            }
                        }
                    }
                }
            }
        }

        PtyTaskDebugLog(@"run3: unlock");
        [tasksLock unlock];
        if (notifyOfCoprocessChange) {
            if (_coprocessChangeHandler) {
                _coprocessChangeHandler();
            } else {
                // Don't wait: the observers only redraw, and waiting would stall every
                // session's I/O until main is free.
                [self performSelectorOnMainThread:@selector(notifyCoprocessChange)
                                       withObject:nil
                                    waitUntilDone:NO];
            }
        }

    breakloop:
        [handledFds release];
        [autoreleasePool drain];
        autoreleasePool = [[NSAutoreleasePool alloc] init];
    }
    // Only test instances get here.
    [autoreleasePool drain];
    dispatch_semaphore_signal(_didStop);
}

// This is run in the main thread.
- (void)notifyCoprocessChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:kCoprocessStatusChangeNotification
                                                        object:nil];
}

@end
