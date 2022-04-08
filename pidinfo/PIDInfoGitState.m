//
//  PIDInfoGitState.m
//  pidinfo
//
//  Created by George Nachman on 4/27/21.
//

#import <Foundation/Foundation.h>
#import "PIDInfoGitState.h"
#import "iTermGitClient.h"
#import "iTermGitState.h"
#include <syslog.h>
#include <stdarg.h>

void PIDInfoGetGitState(const char *cpath, int timeout) {
    const int newPriority = 20;
    int rc = setpriority(PRIO_PROCESS, 0, newPriority);
    if (rc) {
        syslog(LOG_ERR, "setpriority(%d): %s", newPriority, strerror(errno));
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(timeout * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                   ^{
        kill(getpid(), SIGKILL);
    });

    iTermGitState *state = [iTermGitState gitStateForRepoAtPath:[NSString stringWithUTF8String:cpath]];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
    archiver.requiresSecureCoding = YES;
    [archiver encodeObject:state forKey:@"state"];
    [archiver finishEncoding];
    NSFileHandle *fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:1
                                                             closeOnDealloc:YES];
    [fileHandle writeData:archiver.encodedData];
}
