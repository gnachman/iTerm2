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
#import "iTerm.h"
#include <libproc.h>
#include <sys/sysctl.h>

// Singleton of this class.
static ProcessCache* instance;
NSString *PID_INFO_IS_FOREGROUND = @"foreground";
NSString *PID_INFO_NAME = @"name";

@implementation ProcessCache {
    NSMutableDictionary* pidInfoCache_;  // guraded by _cacheLock
    NSLock *_cacheLock;

    BOOL newOutput_;
    NSLock *_lock;
}

+ (void)initialize
{
    instance = [[ProcessCache alloc] init];
    NSThread* thread = [[NSThread alloc] initWithTarget:instance
                                               selector:@selector(_run)
                                                 object:nil];
    [thread start];
    // The analyzer flags this as a leak but it's really just a singleton.
}

- (instancetype)init {
    self = [super init];
    if (self) {
        pidInfoCache_ = [[NSMutableDictionary alloc] init];
        _lock = [[NSLock alloc] init];
        _cacheLock = [[NSLock alloc] init];
    }
    return self;
}

- (void)dealloc {
    [pidInfoCache_ release];
    [_lock release];
    [_cacheLock release];
    [super dealloc];
}

+ (ProcessCache*)sharedInstance {
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
- (NSString*)getNameOfPid:(pid_t)thePid isForeground:(BOOL*)isForeground {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, thePid };
    struct kinfo_proc kp;
    size_t bufSize = sizeof(kp);

    kp.kp_proc.p_comm[0] = 0;
    if (sysctl(mib, 4, &kp, &bufSize, NULL, 0) < 0) {
        return nil;
    }

    // has a controlling terminal and
    // process group id = tty process group id
    if (isForeground) {
        *isForeground = ((kp.kp_proc.p_flag & P_CONTROLT) &&
                         kp.kp_eproc.e_pgid == kp.kp_eproc.e_tpgid);
    }
    
    if (kp.kp_proc.p_comm[0]) {
        return [NSString stringWithUTF8String:kp.kp_proc.p_comm];
    } else {
        return nil;
    }
}

+ (NSArray *)allPids {
    int numBytes;
    numBytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (numBytes <= 0) {
        return nil;
    }
    
    // Put all the pids of running jobs in the pids array.
    int* pids = (int*) malloc(numBytes);
    numBytes = proc_listpids(PROC_ALL_PIDS, 0, pids, numBytes);
    if (numBytes <= 0) {
        free(pids);
        return nil;
    }
    
    int numPids = numBytes / sizeof(int);

    NSMutableArray *pidsArray = [NSMutableArray array];
    for (int i = 0; i < numPids; ++i) {
        [pidsArray addObject:[NSNumber numberWithInt:pids[i]]];
    }
    
    free(pids);
    
    return pidsArray;
}

// Returns 0 on failure.
+ (pid_t)ppidForPid:(pid_t)thePid {
    struct proc_bsdshortinfo taskShortInfo;
    memset(&taskShortInfo, 0, sizeof(taskShortInfo));
    int rc;
    rc = proc_pidinfo(thePid,
                      PROC_PIDT_SHORTBSDINFO,
                      0,
                      &taskShortInfo,
                      sizeof(taskShortInfo));
    if (rc <= 0) {
      return 0;
    } else {
      return taskShortInfo.pbsi_ppid;
    }
}

- (NSDictionary *)dictionaryOfTaskInfoForPid:(pid_t)thePid
{
    BOOL isForeground = NO;
    NSString* name = [self getNameOfPid:thePid isForeground:&isForeground];
    if (!name) {
        return nil;
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithBool:isForeground], PID_INFO_IS_FOREGROUND,
            name, PID_INFO_NAME,
            nil];
}

+ (void)augmentClosure:(NSMutableSet *)closure
              withTree:(NSDictionary *)tree
                atNode:(NSNumber *)node
                  skip:(int)skip
{
    if (skip <= 0) {
        [closure addObject:node];
    }
    NSSet *children = [tree objectForKey:node];
    if (children) {
        for (NSNumber *n in children) {
            if (![closure containsObject:n]) {
                [ProcessCache augmentClosure:closure withTree:tree atNode:n skip:skip-1];
            }
        }
    }
}

- (NSSet *)childrenOfPid:(pid_t)thePid levelsToSkip:(int)skip
{
    NSArray *allPids = [ProcessCache allPids];
    NSMutableDictionary *parentage = [NSMutableDictionary dictionary];
    
    // parentage maps ppid -> {pid, pid, ...}
    for (NSNumber *n in allPids) {
        pid_t parentPid = [ProcessCache ppidForPid:[n intValue]];
        if (parentPid) {
            NSNumber *ppid = [NSNumber numberWithInt:parentPid];
            NSMutableSet *children = [parentage objectForKey:ppid];
            if (!children) {
                children = [NSMutableSet set];
                [parentage setObject:children forKey:ppid];
            }
            [children addObject:n];
        }
    }
    
    // Return the transitive closure of children of thePid.
    NSMutableSet *closure = [NSMutableSet set];
    NSNumber *n = [NSNumber numberWithInt:thePid];
    [ProcessCache augmentClosure:closure
                        withTree:parentage
                          atNode:n
                            skip:skip+1];
    return closure;
}

// Constructs a map of pid -> name of tty controller where pid is the tty
// controller or any ancestor of the tty controller.
- (void)_refreshProcessCache:(NSMutableDictionary*)cache
{    
    [cache removeAllObjects];
    // Add a mapping to 'temp' of pid->job name for all foreground jobs.
    // Add a mapping to 'ancestry' of of pid->ppid for all pid's.
    
    NSArray *allPids = [ProcessCache allPids];
    int numPids = [allPids count];
    
    NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithCapacity:numPids];
    NSMutableDictionary* ancestry = [NSMutableDictionary dictionaryWithCapacity:numPids];
    for (NSNumber *n in allPids) {
        pid_t thePid = [n intValue];

        pid_t ppid = [ProcessCache ppidForPid:thePid];
        if (!ppid) {
            continue;
        }

        BOOL isForeground;
        NSString* name = [self getNameOfPid:thePid isForeground:&isForeground];
        if (name) {
            if (isForeground) {
                [temp setObject:name forKey:[NSNumber numberWithInt:thePid]];
            }
            [ancestry setObject:[NSNumber numberWithInt:ppid] forKey:n];
        }
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
}

- (void)_update {
    // Calculate a new ancestorPid->jobName dict.
    NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithCapacity:100];
    [self _refreshProcessCache:temp];

    // Quickly swap the pointer to minimize lock time, and then free the old cache.
    [_cacheLock lock];
    [pidInfoCache_ autorelease];
    pidInfoCache_ = [temp retain];
    [_cacheLock unlock];
}

- (BOOL)testAndClearNewOutput {
    BOOL v;

    [_lock lock];
    v = newOutput_;
    newOutput_ = NO;
    [_lock unlock];

    return v;
}

- (void)notifyNewOutput {
    [_lock lock];
    newOutput_ = YES;
    [_lock unlock];
}

- (void)_run
{
    while (1) {
        NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
        [self _update];

        // Rate limit this while loop to avoid eating too much CPU when we're very busy.
        [NSThread sleepForTimeInterval:0.1];

        // As long as there's no output, don't update the process cache. Otherwise the CPU usage
        // appears to spike periodically.
        while (![self testAndClearNewOutput]) {
            [NSThread sleepForTimeInterval:[NSApp isActive] ? 0.5 : 5];
        }
        [pool release];
    }
}

- (NSString*)jobNameWithPid:(int)pid {
    [_cacheLock lock];
    NSString *jobName = [[[pidInfoCache_ objectForKey:@(pid)] retain] autorelease];
    [_cacheLock unlock];

    return jobName;
}


@end
