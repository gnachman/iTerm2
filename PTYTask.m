// -*- mode:objc -*-
/*
 **  PTYTask.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the interface to the pty session.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

// Debug option
#define DEBUG_ALLOC         0
#define DEBUG_METHOD_TRACE  0
#define PtyTaskDebugLog(fmt, ...)
// Use this instead to debug this module:
// #define PtyTaskDebugLog NSLog

#define MAXRW 1024

#import <Foundation/Foundation.h>

#include <unistd.h>
#include <util.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <libproc.h>

#import "PTYTask.h"
#import "PreferencePanel.h"
#import "ProcessCache.h"

#include <dlfcn.h>
#include <sys/mount.h>

#include <sys/time.h>
#include <sys/user.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#import "Coprocess.h"

NSString *kCoprocessStatusChangeNotification = @"kCoprocessStatusChangeNotification";

@interface TaskNotifier : NSObject
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

+ (TaskNotifier*)sharedInstance;

- (id)init;
- (void)dealloc;

- (void)registerTask:(PTYTask*)task;
- (void)deregisterTask:(PTYTask*)task;

- (void)unblock;
- (void)run;

@end

@implementation TaskNotifier

static TaskNotifier* taskNotifier = nil;

+ (TaskNotifier*)sharedInstance
{
    if(!taskNotifier) {
        taskNotifier = [[TaskNotifier alloc] init];
        [NSThread detachNewThreadSelector:@selector(run)
                  toTarget:taskNotifier withObject:nil];
    }
    return taskNotifier;
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
            return nil;
        }
        fcntl(unblockPipe[0], F_SETFL, O_NONBLOCK);
        unblockPipeR = unblockPipe[0];
        unblockPipeW = unblockPipe[1];
    }
    return self;
}

- (void)dealloc
{
    taskNotifier = nil;
    [tasks release];
    [tasksLock release];
    [deadpool release];
    close(unblockPipeR);
    close(unblockPipeW);
    [super dealloc];
}

- (void)registerTask:(PTYTask*)task
{
    PtyTaskDebugLog(@"registerTask: lock\n");
    [tasksLock lock];
    PtyTaskDebugLog(@"Add task at 0x%x\n", (void*)task);
    [tasks addObject:task];
    PtyTaskDebugLog(@"There are now %d tasks\n", [tasks count]);
    tasksChanged = YES;
    PtyTaskDebugLog(@"registerTask: unlock\n");
    [tasksLock unlock];
    [self unblock];
}

- (void)deregisterTask:(PTYTask*)task
{
    PtyTaskDebugLog(@"deregisterTask: lock\n");
    [tasksLock lock];
    PtyTaskDebugLog(@"Begin remove task 0x%x\n", (void*)task);
    PtyTaskDebugLog(@"Add %d to deadpool", [task pid]);
    [deadpool addObject:[NSNumber numberWithInt:[task pid]]];
    if ([task hasCoprocess]) {
        [deadpool addObject:[NSNumber numberWithInt:[[task coprocess] pid]]];
    }
    [tasks removeObject:task];
    tasksChanged = YES;
    PtyTaskDebugLog(@"End remove task 0x%x. There are now %d tasks.\n", (void*)task, [tasks count]);
    PtyTaskDebugLog(@"deregisterTask: unlock\n");
    [tasksLock unlock];
    [self unblock];
}

- (void)waitForPid:(pid_t)pid
{
    [tasksLock lock];
    [deadpool addObject:[NSNumber numberWithInt:pid]];
    [tasksLock unlock];
    [self unblock];
}

- (void)unblock
{
    char dummy = 0;
    write(unblockPipeW, &dummy, 1);
}

- (void)run
{
    // There's an analyzer warning here because outerPool never gets drained due to the
    // loop being infinite. I'm not quite sure why there is an outer pool, but I'm afraid to mess
    // with it.
    NSAutoreleasePool* outerPool = [[NSAutoreleasePool alloc] init];

    fd_set rfds;
    fd_set wfds;
    fd_set efds;
    int highfd;
    NSEnumerator* iter;
    PTYTask* task;

    // FIXME: replace this with something better...
    for(;;) {
        NSAutoreleasePool* innerPool = [[NSAutoreleasePool alloc] init];

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
                int statLoc;
                PtyTaskDebugLog(@"wait on %d", [pid intValue]);
                if (waitpid([pid intValue], &statLoc, WNOHANG) < 0) {
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

        PtyTaskDebugLog(@"Begin enumeration over %d tasks\n", [tasks count]);
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
                if (fd > highfd)
                    highfd = fd;
                if ([task wantsRead])
                    FD_SET(fd, &rfds);
                if ([task wantsWrite])
                    FD_SET(fd, &wfds);
                FD_SET(fd, &efds);
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

                        int wfd = [coprocess writeFileDescriptor];
                        if (wfd > highfd) {
                            highfd = wfd;
                        }
                        FD_SET(wfd, &efds);
                    }
                }
            }
            ++i;
            PtyTaskDebugLog(@"About to get task %d\n", i);
        }
        PtyTaskDebugLog(@"run1: unlock");
        [tasksLock unlock];

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
        PtyTaskDebugLog(@"Iterating over %d tasks\n", [tasks count]);
        iter = [tasks objectEnumerator];
        i = 0;
        BOOL notifyOfCoprocessChange = NO;

        while ((task = [iter nextObject])) {
            PtyTaskDebugLog(@"Got task %d\n", i);
            int fd = [task fd];
            if (fd >= 0) {
                // This is mostly paranoia, but if two threads
                // end up with the same fd (because one closed
                // and there was a race condition) then trying
                // to read twice would hang.

                if ([handledFds containsObject:[NSNumber numberWithInt:fd]]) {
                    PtyTaskDebugLog(@"Duplicate fd %d", fd);
                    continue;
                }
                [task retain];
                [handledFds addObject:[NSNumber numberWithInt:fd]];

                if (FD_ISSET(fd, &rfds)) {
                    PtyTaskDebugLog(@"run/processRead: unlock");
                    [tasksLock unlock];
                    [task processRead];
                    PtyTaskDebugLog(@"run/processRead: lock");
                    [tasksLock lock];
                    if (tasksChanged) {
                        PtyTaskDebugLog(@"Restart iteration\n");
                        tasksChanged = NO;
                        iter = [tasks objectEnumerator];
                    }
                }
                if (FD_ISSET(fd, &wfds)) {
                    PtyTaskDebugLog(@"run/processWrite: unlock");
                    [tasksLock unlock];
                    [task processWrite];
                    PtyTaskDebugLog(@"run/processWrite: lock");
                    [tasksLock lock];
                    if (tasksChanged) {
                        PtyTaskDebugLog(@"Restart iteration\n");
                        tasksChanged = NO;
                        iter = [tasks objectEnumerator];
                    }
                }
                if (FD_ISSET(fd, &efds)) {
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
                        iter = [tasks objectEnumerator];
                    }
                }

                // Move input around between coprocess and main process.
                if ([task fd] >= 0 && ![task hasBrokenPipe]) {  // Make sure the pipe wasn't just broken.
                    @synchronized (task) {
                        Coprocess *coprocess = [task coprocess];
                        if (coprocess) {
                            fd = [coprocess readFileDescriptor];
                            if ([handledFds containsObject:[NSNumber numberWithInt:fd]]) {
                                NSLog(@"Duplicate fd %d", fd);
                                continue;
                            }
                            [handledFds addObject:[NSNumber numberWithInt:fd]];
                            if (![coprocess eof] && FD_ISSET(fd, &rfds)) {
                                [coprocess read];
                                [task writeTask:coprocess.inputBuffer];
                                [coprocess.inputBuffer setLength:0];
                            }
                            if (FD_ISSET(fd, &efds)) {
                                coprocess.eof = YES;
                            }

                            fd = [coprocess writeFileDescriptor];
                            if ([handledFds containsObject:[NSNumber numberWithInt:fd]]) {
                                NSLog(@"Duplicate fd %d", fd);
                                continue;
                            }
                            [handledFds addObject:[NSNumber numberWithInt:fd]];
                            if (FD_ISSET(fd, &efds)) {
                                coprocess.eof = YES;
                            }
                            if (FD_ISSET(fd, &wfds)) {
                                if (![coprocess eof]) {
                                    [coprocess write];
                                }
                            }

                            if ([coprocess eof]) {
                                [deadpool addObject:[NSNumber numberWithInt:[coprocess pid]]];
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
        [innerPool drain];
    }

    [outerPool drain];
}

// This is run in the main thread.
- (void)notifyCoprocessChange
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kCoprocessStatusChangeNotification
                                                        object:nil];
}

@end

@implementation PTYTask

#define CTRLKEY(c) ((c)-'A'+1)

static void
setup_tty_param(
                struct termios* term,
                struct winsize* win,
                int width,
                int height,
                BOOL isUTF8)
{
    memset(term, 0, sizeof(struct termios));
    memset(win, 0, sizeof(struct winsize));

    // UTF-8 input will be added on demand.
    term->c_iflag = ICRNL | IXON | IXANY | IMAXBEL | BRKINT | (isUTF8 ? IUTF8 : 0);
    term->c_oflag = OPOST | ONLCR;
    term->c_cflag = CREAD | CS8 | HUPCL;
    term->c_lflag = ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL;

    term->c_cc[VEOF] = CTRLKEY('D');
    term->c_cc[VEOL] = -1;
    term->c_cc[VEOL2] = -1;
    term->c_cc[VERASE] = 0x7f;           // DEL
    term->c_cc[VWERASE] = CTRLKEY('W');
    term->c_cc[VKILL] = CTRLKEY('U');
    term->c_cc[VREPRINT] = CTRLKEY('R');
    term->c_cc[VINTR] = CTRLKEY('C');
    term->c_cc[VQUIT] = 0x1c;           // Control+backslash
    term->c_cc[VSUSP] = CTRLKEY('Z');
    term->c_cc[VDSUSP] = CTRLKEY('Y');
    term->c_cc[VSTART] = CTRLKEY('Q');
    term->c_cc[VSTOP] = CTRLKEY('S');
    term->c_cc[VLNEXT] = CTRLKEY('V');
    term->c_cc[VDISCARD] = CTRLKEY('O');
    term->c_cc[VMIN] = 1;
    term->c_cc[VTIME] = 0;
    term->c_cc[VSTATUS] = CTRLKEY('T');

    term->c_ispeed = B38400;
    term->c_ospeed = B38400;

    win->ws_row = height;
    win->ws_col = width;
    win->ws_xpixel = 0;
    win->ws_ypixel = 0;
}

- (id)init
{
#if DEBUG_ALLOC
    PtyTaskDebugLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    self = [super init];
    if (self) {
        pid = (pid_t)-1;
        status = 0;
        delegate = nil;
        fd = -1;
        tty = nil;
        logPath = nil;
        @synchronized(logHandle) {
            logHandle = nil;
        }
        hasOutput = NO;

        writeBuffer = [[NSMutableData alloc] init];
        writeLock = [[NSLock alloc] init];
    }
    return self;
}

- (void)dealloc
{
#if DEBUG_ALLOC
    PtyTaskDebugLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    [[TaskNotifier sharedInstance] deregisterTask:self];

    if (pid > 0) {
        killpg(pid, SIGHUP);
    }

    if (fd >= 0) {
        PtyTaskDebugLog(@"dealloc: Close fd %d\n", fd);
        close(fd);
    }

    [writeLock release];
    [writeBuffer release];
    [tty release];
    [path release];
	[command_ release];

    @synchronized (self) {
        [[self coprocess] mainProcessDidTerminate];
        [coprocess_ release];
    }

    [super dealloc];
}

- (BOOL)hasBrokenPipe
{
    return brokenPipe_;
}

static void reapchild(int n)
{
  // This intentionally does nothing.
  // We cannot ignore SIGCHLD because Sparkle (the software updater) opens a
  // Safari control which uses some buggy Netscape code that calls wait()
  // until it succeeds. If we wait() on its pid, that process locks because
  // it doesn't check if wait()'s failure is ECHLD. Instead of wait()ing here,
  // we reap our children when our select() loop sees that a pipes is broken.
}

- (NSString *)command
{
	return command_;
}

- (void)launchWithPath:(NSString*)progpath
             arguments:(NSArray*)args
           environment:(NSDictionary*)env
                 width:(int)width
                height:(int)height
                isUTF8:(BOOL)isUTF8
        asLoginSession:(BOOL)asLoginSession
{
    struct termios term;
    struct winsize win;
    char theTtyname[PATH_MAX];

    [command_ autorelease];
    command_ = [progpath copy];
    path = [progpath copy];

    setup_tty_param(&term, &win, width, height, isUTF8);
    // Register a handler for the child death signal.
    signal(SIGCHLD, reapchild);
    const char* argpath;
    argpath = [[progpath stringByStandardizingPath] UTF8String];

    int max = (args == nil) ? 0 : [args count];
    const char* argv[max + 2];

    if (asLoginSession) {
        argv[0] = [[NSString stringWithFormat:@"-%@", [progpath stringByStandardizingPath]] UTF8String];
    } else {
        argv[0] = [[progpath stringByStandardizingPath] UTF8String];
    }
    if (args != nil) {
        int i;
        for (i = 0; i < max; ++i) {
            argv[i + 1] = [[args objectAtIndex:i] cString];
        }
    }
    argv[max + 1] = NULL;
    const int envsize = env.count;
    const char *envKeys[envsize];
    const char *envValues[envsize];
    // Copy values from env (our custom environment vars) into envDict
    int i = 0;
    for (NSString *k in env) {
        NSString *v = [env objectForKey:k];
        envKeys[i] = [k UTF8String];
        envValues[i] = [v UTF8String];
        i++;
    }

    // Note: stringByStandardizingPath will automatically call stringByExpandingTildeInPath.
    const char *initialPwd = [[[env objectForKey:@"PWD"] stringByStandardizingPath] UTF8String];
    pid = forkpty(&fd, theTtyname, &term, &win);
    if (pid == (pid_t)0) {
        // Do not start the new process with a signal handler.
        signal(SIGCHLD, SIG_DFL);
        signal(SIGPIPE, SIG_DFL);
        sigset_t signals;
        sigemptyset(&signals);
        sigaddset(&signals, SIGPIPE);
        sigprocmask(SIG_UNBLOCK, &signals, NULL);

        chdir(initialPwd);
        for (i = 0; i < envsize; i++) {
            // The analyzer warning below is an obvious lie.
            setenv(envKeys[i], envValues[i], 1);
        }
        execvp(argpath, (char* const*)argv);

        /* exec error */
        fprintf(stdout, "## exec failed ##\n");
        fprintf(stdout, "argpath=%s error=%s\n", argpath, strerror(errno));

        sleep(1);
        _exit(-1);
    } else if (pid < (pid_t)0) {
        PtyTaskDebugLog(@"%@ %s", progpath, strerror(errno));
        NSRunCriticalAlertPanel(NSLocalizedStringFromTableInBundle(@"Unable to Fork!",@"iTerm", [NSBundle bundleForClass: [self class]], @"Fork Error"),
                                NSLocalizedStringFromTableInBundle(@"iTerm cannot launch the program for this session.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Fork Error"),
                                NSLocalizedStringFromTableInBundle(@"Close Session",@"iTerm", [NSBundle bundleForClass: [self class]], @"Fork Error"),
                                nil,nil);
        if ([delegate respondsToSelector:@selector(closeSession:)]) {
            [delegate performSelector:@selector(closeSession:) withObject:delegate];
        }
        return;
    }

    tty = [[NSString stringWithUTF8String:theTtyname] retain];
    NSParameterAssert(tty != nil);

    fcntl(fd,F_SETFL,O_NONBLOCK);
    [[TaskNotifier sharedInstance] registerTask:self];
}

- (BOOL)wantsRead
{
    return YES;
}

- (BOOL)wantsWrite
{
    [writeLock lock];
    BOOL wantsWrite = [writeBuffer length] > 0;
    [writeLock unlock];
    return wantsWrite;
}

- (BOOL)writeBufferHasRoom
{
    const int kMaxWriteBufferSize = 1024 * 10;
    [writeLock lock];
    BOOL hasRoom = [writeBuffer length] < kMaxWriteBufferSize;
    [writeLock unlock];
    return hasRoom;
}

- (void)processRead
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):+[PTYTask processRead]", __FILE__, __LINE__);
#endif

    int iterations = 10;
    int bytesRead = 0;

    NSMutableData* data = [NSMutableData dataWithLength:MAXRW * iterations];
    for (int i = 0; i < iterations; ++i) {
        // Only read up to MAXRW*iterations bytes, then release control
        ssize_t n = read(fd, [data mutableBytes] + bytesRead, MAXRW);
        if (n < 0) {
            // There was a read error.
            if (errno != EAGAIN && errno != EINTR) {
                // It was a serious error.
                [self brokenPipe];
                return;
            } else {
                // We could read again in the case of EINTR but it would
                // complicate the code with little advantage. Just bail out.
                n = 0;
            }
        }
        bytesRead += n;
        if (n < MAXRW) {
            // If we read fewer bytes than expected, return. For some apparently
            // undocumented reason, read() never returns more than 1024 bytes
            // (at least on OS 10.6), so that's what MAXRW is set to. If that
            // ever goes down this'll break.
            break;
        }
    }

    [data setLength:bytesRead];
    hasOutput = YES;

    // Send data to the terminal
    [self readTask:data];
}

- (void)processWrite
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTask processWrite] with writeBuffer length %d",
          __FILE__, __LINE__, [writeBuffer length]);
#endif

    // Retain to prevent the object from being released during this method
    // Lock to protect the writeBuffer from the main thread
    [self retain];
    [writeLock lock];

    // Only write up to MAXRW bytes, then release control
    char* ptr = [writeBuffer mutableBytes];
    unsigned int length = [writeBuffer length];
    if (length > MAXRW) {
        length = MAXRW;
    }
    ssize_t written = write(fd, [writeBuffer mutableBytes], length);

    // No data?
    if ((written < 0) && (!(errno == EAGAIN || errno == EINTR))) {
        [self brokenPipe];
        return;
    } else if (written > 0) {
        // Shrink the writeBuffer
        length = [writeBuffer length] - written;
        memmove(ptr, ptr+written, length);
        [writeBuffer setLength:length];
    }

    // Clean up locks
    [writeLock unlock];
    [self autorelease];
}

- (BOOL)hasOutput
{
    return hasOutput;
}

- (void)setDelegate:(id)object
{
    delegate = object;
}

- (id)delegate
{
    return delegate;
}

// The bytes in data were just read from the fd.
- (void)readTask:(NSData*)data
{
    @synchronized(logHandle) {
        if ([self logging]) {
            [logHandle writeData:data];
        }
    }

    // forward the data to our delegate
    if ([delegate respondsToSelector:@selector(readTask:)]) {
        [delegate performSelectorOnMainThread:@selector(readTask:)
                                   withObject:data 
                                waitUntilDone:YES];
    }

    @synchronized (self) {
        [coprocess_.outputBuffer appendData:data];
    }
}

- (void)writeTask:(NSData*)data
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTask writeTask:%@]", __FILE__, __LINE__, data);
#endif

    // Write as much as we can now through the non-blocking pipe
    // Lock to protect the writeBuffer from the IO thread
    [writeLock lock];
    [writeBuffer appendData:data];
    [[TaskNotifier sharedInstance] unblock];
    [writeLock unlock];
}

- (void)brokenPipe
{
    brokenPipe_ = YES;
    [[TaskNotifier sharedInstance] deregisterTask:self];
    if ([delegate respondsToSelector:@selector(brokenPipe)]) {
        [delegate performSelectorOnMainThread:@selector(brokenPipe)
                  withObject:nil waitUntilDone:YES];
    }
}

- (void)sendSignal:(int)signo
{
    if (pid >= 0) {
        kill(pid, signo);
    }
}

- (void)setWidth:(int)width height:(int)height
{
    PtyTaskDebugLog(@"Set terminal size to %dx%d", width, height);
    struct winsize winsize;
    // TODO(georgen): Access to fd should be synchronoized or else it should not be allowed to call this function from the main thread.
    if (fd == -1) {
        return;
    }

    ioctl(fd, TIOCGWINSZ, &winsize);
    if ((winsize.ws_col != width) || (winsize.ws_row != height)) {
        winsize.ws_col = width;
        winsize.ws_row = height;
        ioctl(fd, TIOCSWINSZ, &winsize);
    }
}

- (int)fd
{
    return fd;
}

- (pid_t)pid
{
    return pid;
}

- (void)stop
{
    [self sendSignal:SIGHUP];

    if (fd >= 0) {
        close(fd);
    }
    // This isn't an atomic update, but select() should be resilient to
    // being passed a half-broken fd. We must change it because after this
    // function returns, a new task may be created with this fd and then
    // the select thread wouldn't know which task a fd belongs to.
    fd = -1;
}

- (int)status
{
    return status;
}

- (NSString*)tty
{
    return tty;
}

- (NSString*)path
{
    return path;
}

- (BOOL)loggingStartWithPath:(NSString*)aPath
{
    BOOL rc;
    @synchronized(logHandle) {
        [logPath autorelease];
        logPath = [[aPath stringByStandardizingPath] copy];

        [logHandle autorelease];
        logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (logHandle == nil) {
            NSFileManager* fm = [NSFileManager defaultManager];
            [fm createFileAtPath:logPath contents:nil attributes:nil];
            logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        }
        [logHandle retain];
        [logHandle seekToEndOfFile];

        rc = (logHandle == nil ? NO : YES);
    }
    return rc;
}

- (void)loggingStop
{
    @synchronized(logHandle) {
        [logHandle closeFile];

        [logPath autorelease];
        [logHandle autorelease];
        logPath = nil;
        logHandle = nil;
    }
}

- (BOOL)logging
{
    BOOL rc;
    @synchronized(logHandle) {
        rc = (logHandle == nil ? NO : YES);
    }
    return rc;
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"PTYTask(pid %d, fildes %d)", pid, fd];
}

// This is a stunningly brittle hack. Find the child of parentPid with the
// oldest start time. This relies on undocumented APIs, but short of forking
// ps, I can't see another way to do it.

- (pid_t)getFirstChildOfPid:(pid_t)parentPid
{
    int numBytes;
    numBytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (numBytes <= 0) {
        return -1;
    }

    int* pids = (int*) malloc(numBytes+sizeof(int));
    // Save a magic int at the end to be sure that the buffer isn't overrun.
    const int PID_MAGIC = 0xdeadbeef;
    int magicIndex = numBytes/sizeof(int);
    pids[magicIndex] = PID_MAGIC;
    numBytes = proc_listpids(PROC_ALL_PIDS, 0, pids, numBytes);
    assert(pids[magicIndex] == PID_MAGIC);
    if (numBytes <= 0) {
        free(pids);
        return -1;
    }

    int numPids = numBytes / sizeof(int);

    long long oldestTime = 0;
    pid_t oldestPid = -1;
    for (int i = 0; i < numPids; ++i) {
        struct proc_taskallinfo taskAllInfo;
        int rc = proc_pidinfo(pids[i],
                              PROC_PIDTASKALLINFO,
                              0,
                              &taskAllInfo,
                              sizeof(taskAllInfo));
        if (rc <= 0) {
            continue;
        }

        pid_t ppid = taskAllInfo.pbsd.pbi_ppid;
        if (ppid == parentPid) {
#ifdef BLOCKS_NOT_AVAILABLE  // OS 10.5
            long long birthday = taskAllInfo.pbsd.pbi_start.tv_sec * 1000000 + taskAllInfo.pbsd.pbi_start.tv_usec;
#else  // OS 10.6+
            long long birthday = taskAllInfo.pbsd.pbi_start_tvsec * 1000000 + taskAllInfo.pbsd.pbi_start_tvusec;
#endif
            if (birthday < oldestTime || oldestTime == 0) {
                oldestTime = birthday;
                oldestPid = pids[i];
            }
        }
    }

    assert(pids[magicIndex] == PID_MAGIC);
    free(pids);
    return oldestPid;
}

// Get the name of this task's current job. It is quite approximate! Any
// arbitrary tty-controller in the tty's pgid that has this task as an ancestor
// may be chosen. This function also implements a chache to avoid doing the
// potentially expensive system calls too often.
- (NSString*)currentJob:(BOOL)forceRefresh
{
    return [[ProcessCache sharedInstance] jobNameWithPid:pid];
}

- (NSString*)getWorkingDirectory
{
    struct proc_vnodepathinfo vpi;
    int ret;
    /* This only works if the child process is owned by our uid */
    ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof(vpi));
    if (ret <= 0) {
        // The child was probably owned by root (which is expected if it's
        // a login shell. Use the cwd of its oldest child instead.
        pid_t childPid = [self getFirstChildOfPid:pid];
        if (childPid > 0) {
            ret = proc_pidinfo(childPid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof(vpi));
        }
    }
    if (ret <= 0) {
        /* An error occured */
        return nil;
    } else if (ret != sizeof(vpi)) {
        /* Now this is very bad... */
        return nil;
    } else {
        /* All is good */
        return [NSString stringWithUTF8String:vpi.pvi_cdir.vip_path];
    }
}

- (void)stopCoprocess
{
    pid_t thePid = 0;
    @synchronized (self) {
        if (coprocess_.pid > 0) {
            thePid = coprocess_.pid;
        }
        [coprocess_ terminate];
        [coprocess_ release];
        coprocess_ = nil;
    }
    if (thePid) {
        [[TaskNotifier sharedInstance] waitForPid:thePid];
    }
    [[TaskNotifier sharedInstance] performSelectorOnMainThread:@selector(notifyCoprocessChange)
                                                    withObject:nil
                                                 waitUntilDone:NO];
}

- (void)setCoprocess:(Coprocess *)coprocess
{
    @synchronized (self) {
        [coprocess_ autorelease];
        coprocess_ = [coprocess retain];
    }
    [[TaskNotifier sharedInstance] unblock];
}

- (Coprocess *)coprocess
{
    @synchronized (self) {
        return coprocess_;
    }
    return nil;
}

- (BOOL)hasCoprocess
{
    @synchronized (self) {
        return coprocess_ != nil;
    }
    return NO;
}

- (BOOL)hasMuteCoprocess
{
    @synchronized (self) {
        return coprocess_ != nil && coprocess_.mute;
    }
    return NO;
}

@end

