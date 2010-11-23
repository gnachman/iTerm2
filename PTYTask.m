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

/* Some portions of this code were adapated from Apple's implementation of "ps".
 * It appears to be BSD-derived. Their copyright message follows: */

/*-
 * Copyright (c) 1990, 1993, 1994
 *  The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 * ------+---------+---------+-------- + --------+---------+---------+---------*
 * Copyright (c) 2004  - Garance Alistair Drosehn <gad@FreeBSD.org>.
 * All rights reserved.
 *
 * Significant modifications made to bring `ps' options somewhat closer
 * to the standard for `ps' as described in SingleUnixSpec-v3.
 * ------+---------+---------+-------- + --------+---------+---------+---------*
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

#import <iTerm/PTYTask.h>
#import <iTerm/PreferencePanel.h>

#include <dlfcn.h>
#include <sys/mount.h>

#include <sys/time.h>
#include <sys/user.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface TaskNotifier : NSObject
{
    NSMutableArray* tasks;
    // Set to true when an element of 'tasks' was modified
    BOOL tasksChanged;
    // Protects 'tasks' and 'tasksChanged'.
    NSRecursiveLock* tasksLock;
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
    if ([super init] == nil) {
        return nil;
    }

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

    return self;
}

- (void)dealloc
{
    [tasks release];
    [tasksLock release];
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
    [tasks removeObject:task];
    tasksChanged = YES;
    PtyTaskDebugLog(@"End remove task 0x%x. There are now %d tasks.\n", (void*)task, [tasks count]);
    PtyTaskDebugLog(@"deregisterTask: unlock\n");
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
        CFMutableSetRef handledFds = CFSetCreateMutable (NULL, [tasks count], NULL);

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

        while ((task = [iter nextObject])) {
            PtyTaskDebugLog(@"Got task %d\n", i);
            int fd = [task fd];
            if (fd >= 0) {
                // This is mostly paranoia, but if two threads
                // end up with the same fd (because one closed
                // and there was a race condition) then trying
                // to read twice would hang.

                // The cast warning on this line can be ignored.
                if (CFSetContainsValue(handledFds, (void*)fd)) {
                    PtyTaskDebugLog(@"Duplicate fd %d", fd);
                    continue;
                }
                // The cast warning on this line can be ignored.
                CFSetAddValue(handledFds, (void*)fd);

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
                    [task brokenPipe];
                    PtyTaskDebugLog(@"run/brokenPipe: lock");
                    [tasksLock lock];
                    if (tasksChanged) {
                        PtyTaskDebugLog(@"Restart iteration\n");
                        tasksChanged = NO;
                        iter = [tasks objectEnumerator];
                    }
                }
            }
            ++i;
            PtyTaskDebugLog(@"About to get task %d\n", i);
        }
        PtyTaskDebugLog(@"run3: unlock");
        [tasksLock unlock];

    breakloop:
        CFRelease(handledFds);
        [innerPool drain];
    }

    [outerPool drain];
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
    term->c_cc[VLNEXT] = -1;
    term->c_cc[VDISCARD] = -1;
    term->c_cc[VMIN] = 1;
    term->c_cc[VTIME] = 0;
    term->c_cc[VSTATUS] = -1;

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
    if ([super init] == nil)
        return nil;

    pid = (pid_t)-1;
    status = 0;
    delegate = nil;
    fd = -1;
    tty = nil;
    logPath = nil;
    logHandle = nil;
    hasOutput = NO;

    writeBuffer = [[NSMutableData alloc] init];
    writeLock = [[NSLock alloc] init];

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
    [super dealloc];
}

// Signal handler for SIGCHLD. Be careful changing this - there's very little
// that can be safely done in a signal handler. For some reason, it sometimes
// happens that there is no child to reap, so we use WNOHANG and reap everything
// that is available.
static void reapchild(int n)
{
    int statLoc;
    while (waitpid(-1, &statLoc, WNOHANG) > 0) {
        ;
    }
}

- (void)launchWithPath:(NSString*)progpath
             arguments:(NSArray*)args
           environment:(NSDictionary*)env
                 width:(int)width
                height:(int)height
                isUTF8:(BOOL)isUTF8
{
    struct termios term;
    struct winsize win;
    char theTtyname[PATH_MAX];
    int sts;

    path = [progpath copy];

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[launchWithPath:%@ arguments:%@ environment:%@ width:%d height:%d", __FILE__, __LINE__, progpath, args, env, width, height);
#endif

    setup_tty_param(&term, &win, width, height, isUTF8);
    // Register a handler for the child death signal that just wait()s on it.
    signal(SIGCHLD, reapchild);
    pid = forkpty(&fd, theTtyname, &term, &win);
    if (pid == (pid_t)0) {
        const char* argpath = [[progpath stringByStandardizingPath] UTF8String];
        // Do not start the new process with a signal handler.
        signal(SIGCHLD, SIG_DFL);
        int max = (args == nil) ? 0 : [args count];
        const char* argv[max + 2];

        argv[0] = argpath;
        if (args != nil) {
            int i;
            for (i = 0; i < max; ++i) {
                argv[i + 1] = [[args objectAtIndex:i] cString];
            }
        }
        argv[max + 1] = NULL;

        if (env != nil) {
            NSArray* keys = [env allKeys];
            int i, theMax = [keys count];
            for (i = 0; i < theMax; ++i) {
                NSString* key;
                NSString* value;
                key = [keys objectAtIndex:i];
                value = [env objectForKey:key];
                if (key != nil && value != nil) {
                    setenv([key UTF8String], [value UTF8String], 1);
                }
            }
        }
        // Note: stringByStandardizingPath will automatically call stringByExpandingTildeInPath.
        chdir([[[env objectForKey:@"PWD"] stringByStandardizingPath] UTF8String]);
        sts = execvp(argpath, (char* const*)argv);

        /* exec error */
        fprintf(stdout, "## exec failed ##\n");
        fprintf(stdout, "%s %s\n", argpath, strerror(errno));

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

    tty = [[NSString stringWithCString:theTtyname] retain];
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
    return [writeBuffer length] > 0;
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
    }

    // Shrink the writeBuffer
    length = [writeBuffer length] - written;
    memmove(ptr, ptr+written, length);
    [writeBuffer setLength:length];

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

- (void)readTask:(NSData*)data
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTask readTask:%@]", __FILE__, __LINE__, data);
#endif
    if ([self logging]) {
        [logHandle writeData:data];
    }

    // forward the data to our delegate
    if ([delegate respondsToSelector:@selector(readTask:)]) {
        [delegate performSelectorOnMainThread:@selector(readTask:)
                                   withObject:data 
                                waitUntilDone:YES];
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
    [[TaskNotifier sharedInstance] deregisterTask:self];
    if ([delegate respondsToSelector:@selector(brokenPipe)]) {
        [delegate performSelectorOnMainThread:@selector(brokenPipe)
                  withObject:nil waitUntilDone:YES];
    }
}

- (void)sendSignal:(int)signo
{
    if (pid >= 0) {
        killpg(pid, signo);
    }
}

- (void)setWidth:(int)width height:(int)height
{
    struct winsize winsize;

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

- (int)wait
{
    if (pid >= 0) {
        waitpid(pid, &status, 0);
    }
    return status;
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

    return logHandle == nil ? NO : YES;
}

- (void)loggingStop
{
    [logHandle closeFile];

    [logPath autorelease];
    [logHandle autorelease];
    logPath = nil;
    logHandle = nil;
}

- (BOOL)logging
{
    return logHandle == nil ? NO : YES;
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
    int numPids;
    numPids = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (numPids <= 0) {
        return -1;
    }

    int* pids = (int*) malloc(sizeof(int) * numPids);
    numPids = proc_listpids(PROC_ALL_PIDS, 0, pids, numPids);
    if (numPids <= 0) {
        free(pids);
        return -1;
    }

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
            long long birthday = taskAllInfo.pbsd.pbi_start.tv_sec * 1000000 + taskAllInfo.pbsd.pbi_start.tv_usec;
            if (birthday < oldestTime || oldestTime == 0) {
                oldestTime = birthday;
                oldestPid = pids[i];
            }
        }
    }

    free(pids);
    return oldestPid;
}

// Use sysctl magic to get the name of a process and whether it is controlling
// the tty. This code was adapted from ps, here:
// http://opensource.apple.com/source/adv_cmds/adv_cmds-138.1/ps/
//
// The equivalent in ps would be:
//   ps -aef -o stat
// If a + occurs in the STAT column then it is considered to be a foreground
// job.
- (NSString*)getNameOfPid:(pid_t)thePid isForeground:(BOOL*)isForeground
{
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, thePid };
    struct kinfo_proc kp;
    size_t bufSize = sizeof(kp);

    kp.kp_proc.p_comm[0] = 0;
    if (sysctl(mib, 4, &kp, &bufSize, NULL, 0) < 0) {
        return 0;
    }

    // has a controlling terminal and
    // process group id = tty process group id
    *isForeground = ((kp.kp_proc.p_flag & P_CONTROLT) &&
                     kp.kp_eproc.e_pgid == kp.kp_eproc.e_tpgid);

    if (kp.kp_proc.p_comm[0]) {
        return [NSString stringWithUTF8String:kp.kp_proc.p_comm];
    } else {
        return nil;
    }
}

// Get the name of this task's current job. It is quite approximate! Any
// arbitrary tty-controller in the tty's pgid that has this task as an ancestor
// may be chosen. This function also implements a chache to avoid doing the
// potentially expensive system calls too often.
- (NSString*)currentJob
{
    static NSMutableDictionary* pidInfoCache;
    static NSDate* lastCacheUpdate;

    const double kMaxCacheAge = 0.5;
    if (lastCacheUpdate == nil ||
        [lastCacheUpdate timeIntervalSinceNow] < -kMaxCacheAge) {
        if (pidInfoCache == nil) {
            pidInfoCache = [[NSMutableDictionary alloc] init];
        }
        [self refreshProcessCache:pidInfoCache];
        [lastCacheUpdate release];
        lastCacheUpdate = [[NSDate date] retain];
    }

    return [pidInfoCache objectForKey:[NSNumber numberWithInt:pid]];
}

// Constructs a map of pid -> name of tty controller where pid is the tty
// controller or any ancestor of the tty controller.
- (void)refreshProcessCache:(NSMutableDictionary*)cache
{
    [cache removeAllObjects];
    int numPids;
    numPids = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (numPids <= 0) {
        return;
    }

    int* pids = (int*) malloc(sizeof(int) * numPids);
    numPids = proc_listpids(PROC_ALL_PIDS, 0, pids, numPids);
    if (numPids <= 0) {
        free(pids);
        return;
    }

    NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithCapacity:numPids];
    NSMutableDictionary* ancestry = [NSMutableDictionary dictionaryWithCapacity:numPids];
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
        BOOL isForeground;
        NSString* name = [self getNameOfPid:pids[i] isForeground:&isForeground];
        if (isForeground) {
            [temp setObject:name forKey:[NSNumber numberWithInt:pids[i]]];
        }
        [ancestry setObject:[NSNumber numberWithInt:ppid] forKey:[NSNumber numberWithInt:pids[i]]];
    }

    for (NSNumber* tempPid in temp) {
        NSString* value = [temp objectForKey:tempPid];
        [cache setObject:value forKey:tempPid];

        NSNumber* parent = [ancestry objectForKey:tempPid];
        while (parent != nil) {
            [cache setObject:value forKey:parent];
            parent = [ancestry objectForKey:parent];
        }
    }

    free(pids);
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

@end

