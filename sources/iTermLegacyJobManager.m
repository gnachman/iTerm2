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

@interface iTermLegacyJobManager()
@property (atomic) pid_t childPid;
@end

@implementation iTermLegacyJobManager

@synthesize fd = _fd;
@synthesize tty = _tty;
@synthesize queue = _queue;

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _queue = queue;
        _fd = -1;
        self.childPid = -1;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p fd=%d tty=%@ childPid=%@>",
            NSStringFromClass([self class]), self, _fd, _tty, @(self.childPid)];
}

- (pid_t)serverPid {
    return -1;
}

- (void)setServerPid:(pid_t)serverPid {
    assert(NO);
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
                     newEnviron:(const char **)newEnviron
                           task:(id<iTermTask>)task
                     completion:(void (^)(iTermJobManagerForkAndExecStatus))completion {
    __block iTermJobManagerForkAndExecStatus status = iTermJobManagerForkAndExecStatusSuccess;
    dispatch_sync(self.queue, ^{
        status =
        [self queueForkAndExecWithTtyState:ttyStatePtr
                                   argpath:argpath
                                      argv:argv
                                initialPwd:initialPwd
                                newEnviron:newEnviron
                                      task:task];
    });
    if (status == iTermJobManagerForkAndExecStatusSuccess) {
        [[TaskNotifier sharedInstance] registerTask:task];
    }
    if (completion) {
        completion(status);
    }
}

- (iTermJobManagerForkAndExecStatus)queueForkAndExecWithTtyState:(iTermTTYState *)ttyStatePtr
                                                         argpath:(const char *)argpath
                                                            argv:(const char **)argv
                                                      initialPwd:(const char *)initialPwd
                                                      newEnviron:(const char **)newEnviron
                                                            task:(id<iTermTask>)task {
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
    self.childPid = forkState.pid;
    if (self.childPid > 0) {
        [[iTermProcessCache sharedInstance] registerTrackedPID:self.childPid];
    }
    if (forkState.pid < (pid_t)0) {
        return iTermJobManagerForkAndExecStatusFailedToFork;
    }

    // Make sure the master side of the pty is closed on future exec() calls.
    DLog(@"fcntl");
    fcntl(self.fd, F_SETFD, fcntl(self.fd, F_GETFD) | FD_CLOEXEC);

    self.tty = [NSString stringWithUTF8String:ttyStatePtr->tty];
    fcntl(self.fd, F_SETFL, O_NONBLOCK);
    return iTermJobManagerForkAndExecStatusSuccess;
}

- (BOOL)attachToServer:(iTermGeneralServerConnection)serverConnection
         withProcessID:(NSNumber *)thePid
                  task:(id<iTermTask>)task {
    return YES;
}

- (void)sendSignal:(int)signo toProcessGroup:(BOOL)toProcessGroup {
    dispatch_async(self.queue, ^{
        [self queueSendSignal:signo toProcessGroup:toProcessGroup];
    });
}

- (void)queueSendSignal:(int)signo toProcessGroup:(BOOL)toProcessGroup {
    if (self.childPid <= 0) {
        return;
    }
    [[iTermProcessCache sharedInstance] unregisterTrackedPID:self.childPid];
    if (toProcessGroup) {
        killpg(self.childPid, signo);
    } else {
        kill(self.childPid, signo);
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
    return self.childPid;
}

- (BOOL)isSessionRestorationPossible {
    return NO;
}

- (pid_t)externallyVisiblePid {
    return self.childPid;
}

- (BOOL)hasJob {
    return self.childPid != -1;
}

- (id)sessionRestorationIdentifier {
    return nil;
}

- (BOOL)ioAllowed {
    return self.fd >= 0;
}

@end
