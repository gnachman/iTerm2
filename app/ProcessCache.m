// -*- mode:objc -*-
/*
 **  ProcessCache.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Keeps a pid->session leader job name map and refreshes it in a separate thread.
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

#import "ProcessCache.h"
#include <libproc.h>
#include <sys/sysctl.h>

// Singleton of this class.
static ProcessCache* instance;

@implementation ProcessCache

+ (void)initialize
{
    instance = [[ProcessCache alloc] init];
    NSThread* thread = [[NSThread alloc] initWithTarget:instance
                                               selector:@selector(_run)
                                                 object:nil];
    [thread start];
}

- (id)init
{
    self = [super init];
    if (self) {
        pidInfoCache_ = [[NSMutableDictionary alloc] init];
        lock_ = [[NSLock alloc] init];
    }
    return self;
}

+ (ProcessCache*)sharedInstance
{
    assert(instance);
    return instance;
}

// Use sysctl magic to get the name of a process and whether it is controlling
// the tty. This code was adapted from ps, here:
// http://opensource.apple.com/source/adv_cmds/adv_cmds-138.1/ps/
//
// The equivalent in ps would be:
//   ps -aef -o stat
// If a + occurs in the STAT column then it is considered to be a foreground
// job.
- (NSString*)_getNameOfPid:(pid_t)thePid isForeground:(BOOL*)isForeground
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


// Constructs a map of pid -> name of tty controller where pid is the tty
// controller or any ancestor of the tty controller.
- (void)_refreshProcessCache:(NSMutableDictionary*)cache
{
    [cache removeAllObjects];
    int numBytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (numBytes <= 0) {
        return;
    }
    
    // Put all the pids of running jobs in the pids array.
    int* pids = (int*) malloc(numBytes);
    numBytes = proc_listpids(PROC_ALL_PIDS, 0, pids, numBytes);
    if (numBytes <= 0) {
        free(pids);
        return;
    }
    
    // Add a mapping to 'temp' of pid->job name for all foreground jobs.
    // Add a mapping to 'ancestry' of of pid->ppid for all pid's.
    int numPids = numBytes / sizeof(int);
    
    NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithCapacity:numPids];
    NSMutableDictionary* ancestry = [NSMutableDictionary dictionaryWithCapacity:numPids];
    for (int i = 0; i < numPids; ++i) {
        struct proc_taskallinfo taskAllInfo;
        memset(&taskAllInfo, 0, sizeof(taskAllInfo));
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
        NSString* name = [self _getNameOfPid:pids[i] isForeground:&isForeground];
        if (isForeground) {
            [temp setObject:name forKey:[NSNumber numberWithInt:pids[i]]];
        }
        [ancestry setObject:[NSNumber numberWithInt:ppid] forKey:[NSNumber numberWithInt:pids[i]]];
    }
    
    // For each pid in 'temp', follow the parent pid chain in 'ancestry' and add a map of
    // ancestorPid->job name to 'cache' for all ancestors of the job with that name.
    for (NSNumber* tempPid in temp) {
        NSString* value = [temp objectForKey:tempPid];
        [cache setObject:value forKey:tempPid];
        
        NSNumber* parent = [ancestry objectForKey:tempPid];
        NSNumber* cycleFinder = parent;
        while (parent != nil) {
            [cache setObject:value forKey:parent];
            
            // cycleFinder moves through the chain of ancestry at twice the
            // rate of parent. If it ever catches up to parent then there is a cycle.
            // A cycle can occur because there's a race in getting each process's
            // ppid. See bug 771 for details.
            if (cycleFinder) {
                cycleFinder = [ancestry objectForKey:cycleFinder];
                if (cycleFinder && [cycleFinder isEqualToNumber:parent]) {
                    break;
                }
            }
            if (cycleFinder) {
                cycleFinder = [ancestry objectForKey:cycleFinder];
                if (cycleFinder && [cycleFinder isEqualToNumber:parent]) {
                    break;
                }
            }
            
            parent = [ancestry objectForKey:parent];
        }
    }
    
    free(pids);
}

- (void)_update
{
    // Calculate a new ancestorPid->jobName dict.
    NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithCapacity:100];
    [self _refreshProcessCache:temp];

    // Quickly swap the pointer to minimize lock time, and then free the old cache.
    NSMutableDictionary* old = pidInfoCache_;
    [temp retain];
   
    [lock_ lock];
    pidInfoCache_ = temp;
    [lock_ unlock];
    
    [old release];
}

- (BOOL)testAndClearNewOutput
{
    [lock_ lock];
    BOOL v = newOutput_;
    newOutput_ = NO;
    [lock_ unlock];
    return v;
}

- (void)notifyNewOutput
{
    [lock_ lock];
    newOutput_ = YES;
    [lock_ unlock];
}

- (void)_run
{
    while (1) {
        NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
        [self _update];
        // As long as there's no output, don't update the process cache. Otherwise the CPU usage
        // appears to spike periodically.
        while (![self testAndClearNewOutput]) {
            [NSThread sleepForTimeInterval:[NSApp isActive] ? 0.5 : 5];
        }
        [pool release];
    }
}

- (NSString*)jobNameWithPid:(int)pid
{
    assert(lock_);
    [lock_ lock];
    NSString* jobName = [pidInfoCache_ objectForKey:[NSNumber numberWithInt:pid]];
    // Move jobName into this thread's autorelease pool so it will survive until we return to
    // mainloop.
    [[jobName retain] autorelease];
    [lock_ unlock];
    
    return jobName;
}


@end
