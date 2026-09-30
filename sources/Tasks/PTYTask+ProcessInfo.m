//
//  PTYTask+ProcessInfo.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/22.
//

#import "PTYTask+ProcessInfo.h"
#import "PTYTask+Private.h"

#import "iTermProcessCache.h"

@implementation PTYTask (ProcessInfo)

// A tmux pane session's task never forks anything itself; the only pid it has is the pane pid
// tmux reported. Both lookups below must use the same pid, or the poll path and the event path
// describe two different processes for the same session.
- (pid_t)processInfoPID {
    return self.tmuxClientProcessID ? self.tmuxClientProcessID.intValue : self.pid;
}

- (void)fetchProcessInfoForCurrentJobWithCompletion:(void (^)(iTermProcessInfo *))completion {
    const pid_t pid = self.processInfoPID;
    iTermProcessInfo *info = [[iTermProcessCache sharedInstance] deepestForegroundJobForPid:pid];
    DLog(@"%@ fetch process info for %@", self, @(pid));
    if (info.name) {
        DLog(@"Return name synchronously");
        completion(info);
    } else if (info) {
        DLog(@"Have info for pid %@ but no name", @(pid));
    }

    if (pid <= 0) {
        DLog(@"Lack a good pid");
        completion(nil);
        return;
    }
    if (_haveBumpedProcessCache) {
        DLog(@"Already bumped process cache");
        [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
        return;
    }
    _haveBumpedProcessCache = YES;
    DLog(@"Requesting immediate update");
    [[iTermProcessCache sharedInstance] requestImmediateUpdateWithCompletionBlock:^{
        completion([[iTermProcessCache sharedInstance] deepestForegroundJobForPid:pid]);
    }];
}

- (iTermProcessInfo *)cachedProcessInfoIfAvailable {
    const pid_t pid = self.processInfoPID;
    iTermProcessInfo *info = [[iTermProcessCache sharedInstance] deepestForegroundJobForPid:pid];
    if (info.name) {
        return info;
    }

    // Ask for an update the first time the cache has nothing for us, as the fetch above does.
    if (pid > 0 && !_haveBumpedProcessCache) {
        _haveBumpedProcessCache = YES;
        [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
    }

    return nil;
}

@end
