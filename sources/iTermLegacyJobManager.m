//
//  iTermLegacyJobManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/16/19.
//

#import "iTermLegacyJobManager.h"

#import "iTermProcessCache.h"
#import "PTYTask+MRR.h"
#import "TaskNotifier.h"

@implementation iTermLegacyJobManager

@synthesize fd = _fd;
@synthesize tty = _tty;
@synthesize childPid = _childPid;

- (instancetype)init {
    self = [super init];
    if (self) {
        _fd = -1;
        _childPid = -1;
    }
    return self;
}

- (pid_t)serverPid {
    return -1;
}

- (void)setServerPid:(pid_t)serverPid {
    assert(NO);
}

- (pid_t)serverChildPid {
    return -1;
}

- (int)socketFd {
    return -1;
}

- (void)setSocketFd:(int)socketFd {
    assert(NO);
}

- (iTermJobManagerForkAndExecStatus)forkAndExecWithForkState:(iTermForkState *)forkStatePtr
                        ttyState:(iTermTTYState *)ttyStatePtr
                         argpath:(const char *)argpath
                            argv:(const char **)argv
                      initialPwd:(const char *)initialPwd
                      newEnviron:(char **)newEnviron {
    self.fd = iTermForkAndExecToRunJobDirectly(forkStatePtr,
                                               ttyStatePtr,
                                               argpath,
                                               argv,
                                               YES,
                                               initialPwd,
                                               newEnviron);
    // If you get here you're the parent.
    _childPid = forkStatePtr->pid;
    if (_childPid > 0) {
        [[iTermProcessCache sharedInstance] registerTrackedPID:_childPid];
    }
    if (forkStatePtr->pid < (pid_t)0) {
        return iTermJobManagerForkAndExecStatusFailedToFork;
    }
    return iTermJobManagerForkAndExecStatusSuccess;
}

- (void)didForkParent:(const iTermForkState *)forkState
             ttyState:(iTermTTYState *)ttyState
          synchronous:(BOOL)synchronous
                 task:(id<iTermTask>)task
           completion:(void (^)(BOOL))completion {
    self.tty = [NSString stringWithUTF8String:ttyState->tty];
    fcntl(self.fd, F_SETFL, O_NONBLOCK);
    [[TaskNotifier sharedInstance] registerTask:task];

    completion(NO);
}


- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection
         withProcessID:(NSNumber *)thePid
                  task:(id<iTermTask>)task {

}

- (void)closeSocketFd {
    assert(NO);
}

@end
