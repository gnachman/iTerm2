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
#import "PTYTask.h"

#define PtyTaskDebugLog(args...)

NSString *const kTaskNotifierDidSpin = @"kTaskNotifierDidSpin";

@implementation TaskNotifier
{
    NSMutableArray* tasks;
    // Set to true when an element of 'tasks' was modified
    BOOL tasksChanged;
    // Protects 'tasks' and 'tasksChanged'.
    NSRecursiveLock* tasksLock;
    
    // A set of NSNumber*s holding pids of tasks that need to be wait()ed on
    NSMutableSet* deadpool;
    int unblockPipeR;
    int unblockPipeW;
}


+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
        [NSThread detachNewThreadSelector:@selector(run)
                                 toTarget:instance
                               withObject:nil];
    });
    return instance;
}

- (id)init
{
    self = [super init];
    if (self) {
        deadpool = [[NSMutableSet alloc] init];
        tasks = [[NSMutableArray alloc] init];
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
        unblockPipeR = unblockPipe[0];
        unblockPipeW = unblockPipe[1];
    }
    return self;
}

- (void)dealloc
{
    [tasks release];
    [tasksLock release];
    [deadpool release];
    close(unblockPipeR);
    close(unblockPipeW);
    [super dealloc];
}

- (void)registerTask:(PTYTask*)task {
    PtyTaskDebugLog(@"registerTask: lock\n");
    [tasksLock lock];
    PtyTaskDebugLog(@"Add task at %p\n", (void*)task);
    [tasks addObject:task];
    PtyTaskDebugLog(@"There are now %lu tasks\n", (unsigned long)[tasks count]);
    tasksChanged = YES;
    PtyTaskDebugLog(@"registerTask: unlock\n");
    [tasksLock unlock];
    [self unblock];
}

- (void)deregisterTask:(PTYTask *)task
{
    PtyTaskDebugLog(@"deregisterTask: lock\n");
    [tasksLock lock];
    PtyTaskDebugLog(@"Begin remove task %p\n", (void*)task);
    PtyTaskDebugLog(@"Add %d to deadpool", [task pid]);
    pid_t pid = task.pid;
    if (pid != -1) {
        // Not a restored task.
        [deadpool addObject:@([task pid])];
    }
    if ([task hasCoprocess]) {
        [deadpool addObject:@([[task coprocess] pid])];
    }
    [tasks removeObject:task];
    tasksChanged = YES;
    PtyTaskDebugLog(@"End remove task %p. There are now %lu tasks.\n",
                    (void*)task, (unsigned long)[tasks count]);
    PtyTaskDebugLog(@"deregisterTask: unlock\n");
    [tasksLock unlock];
    [self unblock];
}

- (void)waitForPid:(pid_t)pid
{
    [tasksLock lock];
    [deadpool addObject:@(pid)];
    [tasksLock unlock];
    [self unblock];
}

- (void)unblock
{
    // This is called in a signal handler and must only call functions listed
    // as safe in sigaction(2)'s man page.
    char dummy = 0;
    write(unblockPipeW, &dummy, 1);
}

- (BOOL)handleReadOnFileDescriptor:(int)fd task:(PTYTask *)task fdSet:(fd_set *)fdSet {
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

- (BOOL)handleWriteOnFileDescriptor:(int)fd task:(PTYTask *)task fdSet:(fd_set *)fdSet {
    if (FD_ISSET(fd, fdSet)) {
        PtyTaskDebugLog(@"run/processWrite: unlock");
        [tasksLock unlock];
        [task processWrite];
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

- (BOOL)handleErrorOnFileDescriptor:(int)fd task:(PTYTask *)task fdSet:(fd_set *)fdSet {
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
                              task:(PTYTask *)task
                     withCoprocess:(Coprocess *)coprocess
                             fdSet:(fd_set *)fdSet {
    if (![coprocess eof] && FD_ISSET(fd, fdSet)) {
        [coprocess read];
        [task writeTask:coprocess.inputBuffer];
        [coprocess.inputBuffer setLength:0];
    }
}

- (void)handleErrorOnFileDescriptor:(int)fd
                      withCoprocess:(Coprocess *)coprocess
                              fdSet:(fd_set *)fdSet {
    if (FD_ISSET(fd, fdSet)) {
        coprocess.eof = YES;
    }
}

- (void)handleWriteOnFileDescriptor:(int)coprocessWriteFd
                      withCoprocess:(Coprocess *)coprocess
                              fdSet:(fd_set *)fdSet {
    if (FD_ISSET(coprocessWriteFd, fdSet)) {
        if (![coprocess eof]) {
            [coprocess write];
        }
    }
}

- (void)run
{
    fd_set rfds;
    fd_set wfds;
    fd_set efds;
    int highfd;
    NSEnumerator* iter;
    PTYTask* task;
    NSAutoreleasePool* autoreleasePool = [[NSAutoreleasePool alloc] init];
    
    // FIXME: replace this with something better...
    for(;;) {
        
        FD_ZERO(&rfds);
        FD_ZERO(&wfds);
        FD_ZERO(&efds);
        
        // Unblock pipe to interrupt select() whenever a PTYTask register/unregisters
        highfd = unblockPipeR;
        FD_SET(unblockPipeR, &rfds);
        NSMutableSet* handledFds = [[NSMutableSet alloc] initWithCapacity:[tasks count]];
        
        // Add all the PTYTask pipes
        PtyTaskDebugLog(@"run1: lock");
        [tasksLock lock];
        PtyTaskDebugLog(@"Begin cleaning out dead tasks");
        int j;
        for (j = [tasks count] - 1; j >= 0; --j) {
            PTYTask* theTask = [tasks objectAtIndex:j];
            if ([theTask fd] < 0) {
                PtyTaskDebugLog(@"Deregister dead task %d\n", j);
                [self deregisterTask:theTask];
            }
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
        
        PtyTaskDebugLog(@"Begin enumeration over %lu tasks\n", (unsigned long)[tasks count]);
        iter = [tasks objectEnumerator];
        int i = 0;
        // FIXME: this can be converted to ObjC 2.0.
        while ((task = [iter nextObject])) {
            PtyTaskDebugLog(@"Got task %d\n", i);
            int fd = [task fd];
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
                    int writeFd;
                    int optionalWriteFd = task.writeFd;
                    if (optionalWriteFd != -1) {
                        writeFd = optionalWriteFd;
                        highfd = MAX(highfd, writeFd);
                    } else {
                        writeFd = fd;
                    }
                    FD_SET(writeFd, &wfds);
                }
                FD_SET(fd, &efds);
            }

            int deathFd = task.deathFd;
            if (deathFd != -1) {
                FD_SET(deathFd, &rfds);
            }

            @synchronized (task) {
                Coprocess *coprocess = [task coprocess];
                if (coprocess) {
                    if ([coprocess wantToRead] && [task writeBufferHasRoom]) {
                        int rfd = [coprocess readFileDescriptor];
                        if (rfd > highfd) {
                            highfd = rfd;
                        }
                        FD_SET(rfd, &rfds);
                    }
                    if ([coprocess wantToWrite]) {
                        int wfd = [coprocess writeFileDescriptor];
                        if (wfd > highfd) {
                            highfd = wfd;
                        }
                        FD_SET(wfd, &wfds);
                    }
                    if (![coprocess eof]) {
                        int rfd = [coprocess readFileDescriptor];
                        if (rfd > highfd) {
                            highfd = rfd;
                        }
                        FD_SET(rfd, &efds);
                    }
                }
            }
            ++i;
            PtyTaskDebugLog(@"About to get task %d\n", i);
        }
        PtyTaskDebugLog(@"run1: unlock");
        [tasksLock unlock];

        [[NSNotificationCenter defaultCenter] postNotificationName:kTaskNotifierDidSpin object:nil];

        // Poll...
        if (select(highfd+1, &rfds, &wfds, &efds, NULL) <= 0) {
            switch(errno) {
                case EAGAIN:
                case EINTR:
                default:
                    goto breakloop;
                    // If the file descriptor is closed in the main thread there's a race where sometimes you'll get an EBADF.
            }
        }
        
        // Interrupted?
        if (FD_ISSET(unblockPipeR, &rfds)) {
            char dummy[32];
            do {
                read(unblockPipeR, dummy, sizeof(dummy));
            } while (errno != EAGAIN);
        }
        
        // Check for read events on PTYTask pipes
        PtyTaskDebugLog(@"run2: lock");
        [tasksLock lock];
        PtyTaskDebugLog(@"Iterating over %lu tasks\n", (unsigned long)[tasks count]);
        iter = [tasks objectEnumerator];
        i = 0;
        BOOL notifyOfCoprocessChange = NO;
        
        while ((task = [iter nextObject])) {
            PtyTaskDebugLog(@"Got task %d\n", i);
            int fd = [task fd];
            int optionalWriteFd = task.writeFd;
            int optionalDeathFd = task.deathFd;
            int writeFd = optionalWriteFd == -1 ? fd : optionalWriteFd;

            if (fd >= 0) {
                // This is mostly paranoia, but if two threads
                // end up with the same fd (because one closed
                // and there was a race condition) then trying
                // to read twice would hang.
                
                if ([handledFds containsObject:@(fd)]) {
                    PtyTaskDebugLog(@"Duplicate fd %d", fd);
                    continue;
                }
                [task retain];
                [handledFds addObject:@(fd)];

                if ([self handleReadOnFileDescriptor:fd task:task fdSet:&rfds]) {
                    iter = [tasks objectEnumerator];
                }
                if ([self handleWriteOnFileDescriptor:writeFd task:task fdSet:&wfds]) {
                    iter = [tasks objectEnumerator];
                }
                if ([self handleErrorOnFileDescriptor:fd task:task fdSet:&efds]) {
                    iter = [tasks objectEnumerator];
                }
                if (optionalDeathFd != -1 && [self handleErrorOnFileDescriptor:optionalDeathFd task:task fdSet:&rfds]) {
                    iter = [tasks objectEnumerator];
                }
                // Move input around between coprocess and main process.
                if ([task fd] >= 0 && ![task hasBrokenPipe]) {  // Make sure the pipe wasn't just broken.
                    @synchronized (task) {
                        Coprocess *coprocess = [task coprocess];
                        if (coprocess) {
                            fd = [coprocess readFileDescriptor];
                            if ([handledFds containsObject:@(fd)]) {
                                NSLog(@"Duplicate fd %d", fd);
                                continue;
                            }
                            [handledFds addObject:@(fd)];

                            [self handleReadOnFileDescriptor:fd task:task withCoprocess:coprocess fdSet:&rfds];
                            [self handleErrorOnFileDescriptor:fd withCoprocess:coprocess fdSet:&efds];

                            // Handle writes
                            int coprocessWriteFd = [coprocess writeFileDescriptor];
                            if ([handledFds containsObject:@(coprocessWriteFd)]) {
                                NSLog(@"Duplicate fd %d", coprocessWriteFd);
                                continue;
                            }
                            [handledFds addObject:@(coprocessWriteFd)];
                            [self handleWriteOnFileDescriptor:coprocessWriteFd withCoprocess:coprocess fdSet:&wfds];

                            if ([coprocess eof]) {
                                [deadpool addObject:@([coprocess pid])];
                                [coprocess terminate];
                                [task setCoprocess:nil];
                                notifyOfCoprocessChange = YES;
                            }
                        }
                    }
                }
                [task release];
            }
            ++i;
            PtyTaskDebugLog(@"About to get task %d\n", i);
        }
        PtyTaskDebugLog(@"run3: unlock");
        [tasksLock unlock];
        if (notifyOfCoprocessChange) {
            [self performSelectorOnMainThread:@selector(notifyCoprocessChange)
                                   withObject:nil
                                waitUntilDone:YES];
        }
        
    breakloop:
        [handledFds release];
        [autoreleasePool drain];
        autoreleasePool = [[NSAutoreleasePool alloc] init];
    }
    assert(false);  // Must never get here or the autorelease pool would leak.
}

// This is run in the main thread.
- (void)notifyCoprocessChange
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kCoprocessStatusChangeNotification
                                                        object:nil];
}

@end
