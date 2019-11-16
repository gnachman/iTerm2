//
//  iTermLegacyJobManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/16/19.
//

#import "iTermLegacyJobManager.h"

#import "DebugLogging.h"
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

- (void)forkAndExecWithTtyState:(iTermTTYState *)ttyStatePtr
                        argpath:(const char *)argpath
                           argv:(const char **)argv
                     initialPwd:(const char *)initialPwd
                     newEnviron:(char **)newEnviron
                    synchronous:(BOOL)synchronous
                           task:(id<iTermTask>)task
                     completion:(void (^)(iTermJobManagerForkAndExecStatus))completion {
    iTermForkState forkState = {
        .connectionFd = -1,
        .deadMansPipe = { 0, 0 },
    };
    self.fd = iTermForkAndExecToRunJobDirectly(&forkState,
                                               ttyStatePtr,
                                               argpath,
                                               argv,
                                               YES,
                                               initialPwd,
                                               newEnviron);
    // If you get here you're the parent.
    _childPid = forkState.pid;
    if (_childPid > 0) {
        [[iTermProcessCache sharedInstance] registerTrackedPID:_childPid];
    }
    if (forkState.pid < (pid_t)0) {
        completion(iTermJobManagerForkAndExecStatusFailedToFork);
        return;
    }

    // Make sure the master side of the pty is closed on future exec() calls.
    DLog(@"fcntl");
    fcntl(self.fd, F_SETFD, fcntl(self.fd, F_GETFD) | FD_CLOEXEC);

    self.tty = [NSString stringWithUTF8String:ttyStatePtr->tty];
    fcntl(self.fd, F_SETFL, O_NONBLOCK);
    [[TaskNotifier sharedInstance] registerTask:task];
    completion(iTermJobManagerForkAndExecStatusSuccess);
}

- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection
         withProcessID:(NSNumber *)thePid
                  task:(id<iTermTask>)task {

}

- (void)closeSocketFd {
    assert(NO);
}

- (void)sendSignal:(int)signo toProcessGroup:(BOOL)toProcessGroup {
    if (_childPid <= 0) {
        return;
    }
    [[iTermProcessCache sharedInstance] unregisterTrackedPID:_childPid];
    if (toProcessGroup) {
        killpg(_childPid, signo);
    } else {
        kill(_childPid, signo);
    }
}

- (void)killWithMode:(iTermJobManagerKillingMode)mode {
    switch (mode) {
        case iTermJobManagerKillingModeRegular:
            [self sendSignal:SIGHUP toProcessGroup:NO];
            break;

        case iTermJobManagerKillingModeForce:
            [self sendSignal:SIGKILL toProcessGroup:NO];
            break;

        case iTermJobManagerKillingModeForceUnrestorable:
            // TODO: Shouldn't this be sigkill?
            [self sendSignal:SIGHUP toProcessGroup:NO];
            break;

        case iTermJobManagerKillingModeProcessGroup:
            [self sendSignal:SIGHUP toProcessGroup:YES];
            break;
        case iTermJobManagerKillingModeBrokenPipe:
            break;
    }
}

- (pid_t)pidToWaitOn {
    return _childPid;
}

- (BOOL)isSessionRestorationPossible {
    return NO;
}

@end
