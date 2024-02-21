//
//  iTermMonoServerJobManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/16/19.
//

#import "iTermMonoServerJobManager.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermFileDescriptorSocketPath.h"
#import "iTermOrphanServerAdopter.h"
#import "iTermProcessCache.h"
#import "NSArray+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "PTYTask+MRR.h"
#import "TaskNotifier.h"

#import <Foundation/Foundation.h>

@interface iTermMonoServerJobManager()
@property (atomic, strong, readwrite) dispatch_queue_t queue;
@end

@implementation iTermMonoServerJobManager {
    pid_t _serverChildPid;
    pid_t _serverPid;

    // File descriptor for unix domain socket connected to server. Only safe to close after server is dead.
    pid_t _socketFd;
}

@synthesize fd = _fd;
@synthesize tty = _tty;
@synthesize queue;

+ (BOOL)available {
    return YES;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        self.queue = queue;
        _serverPid = (pid_t)-1;
        _serverChildPid = -1;
        _socketFd = -1;
        _fd = -1;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p fd=%d tty=%@ serverPid=%@ serverChildPid=%@ socketFd=%@>",
            NSStringFromClass([self class]), self,
            _fd, _tty, @(_serverPid), @(_serverChildPid), @(_socketFd)];
}

- (pid_t)childPid {
    return -1;
}

- (void)setChildPid:(pid_t)childPid {
    assert(NO);
}

- (BOOL)closeFileDescriptor {
    @synchronized (self) {
        if (self.fd == -1) {
            return NO;
        }
        close(self.fd);
        self.fd = -1;
        return YES;
    }
}

- (NSString *)pathToNewUnixDomainSocket {
    // Create a temporary filename for the unix domain socket. It'll only exist for a moment.
    NSString *tempPath = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"iTerm2-temp-socket."
                                                                             suffix:@""];
    return tempPath;
}

- (void)forkAndExecWithTtyState:(iTermTTYState)ttyState
                        argpath:(NSString *)argpath
                           argv:(NSArray<NSString *> *)argv
                     initialPwd:(NSString *)initialPwd
                     newEnviron:(NSArray<NSString *> *)newEnviron
                           task:(id<iTermTask>)task
                     completion:(void (^)(iTermJobManagerForkAndExecStatus))completion  {
    // Completion wrapper. NOT called on self.queue because that will deadlock.
    void (^wrapper)(iTermJobManagerForkAndExecStatus) = ^(iTermJobManagerForkAndExecStatus status) {
        if (status == iTermJobManagerForkAndExecStatusSuccess) {
            DLog(@"Register %@ after fork and exec", @(task.pid));
            [[TaskNotifier sharedInstance] registerTask:task];
        }
        completion(status);
    };

    __block iTermJobManagerForkAndExecStatus savedStatus = iTermJobManagerForkAndExecStatusSuccess;
    dispatch_sync(self.queue, ^{
        [self queueForkAndExecWithTtyState:ttyState
                                   argpath:argpath
                                      argv:argv
                                initialPwd:initialPwd
                                newEnviron:newEnviron
                                      task:task
                                completion:^(iTermJobManagerForkAndExecStatus status) {
            // Completion handler called after queueForkAndExecWithTtyState returns, but still
            // on self.queue.
            dispatch_async(dispatch_get_main_queue(), ^{
                wrapper(savedStatus);
            });
        }];
    });
}

- (void)queueForkAndExecWithTtyState:(iTermTTYState)ttyState
                             argpath:(NSString *)argpath
                                argv:(NSArray<NSString *> *)argv
                          initialPwd:(NSString *)initialPwd
                          newEnviron:(NSArray<NSString *> *)newEnviron
                                task:(id<iTermTask>)task
                          completion:(void (^)(iTermJobManagerForkAndExecStatus))completion {
    // Create a temporary filename for the unix domain socket. It'll only exist for a moment.
    DLog(@"get path to UDS");
    NSString *unixDomainSocketPath = [self pathToNewUnixDomainSocket];
    DLog(@"done");
    if (unixDomainSocketPath == nil) {
        completion(iTermJobManagerForkAndExecStatusTempFileError);
        return;
    }

    // Begin listening on that path as a unix domain socket.
    DLog(@"fork");

    iTermForkState forkState = {
        .connectionFd = -1,
        .deadMansPipe = { 0, 0 },
    };

    char **cArgv = [argv nullTerminatedCStringArray];
    char **cEnviron = [newEnviron nullTerminatedCStringArray];
    self.fd = iTermForkAndExecToRunJobInServer(&forkState,
                                               &ttyState,
                                               unixDomainSocketPath,
                                               argpath.UTF8String,
                                               cArgv,
                                               NO,
                                               initialPwd.UTF8String,
                                               cEnviron);
    iTermFreeeNullTerminatedCStringArray(cArgv);
    iTermFreeeNullTerminatedCStringArray(cEnviron);

    const int fd = self.fd;
    if (fd >= 0) {
        fcntl(self.fd, F_SETFL, O_NONBLOCK);
    }

    // If you get here you're the parent.
    _serverPid = forkState.pid;

    if (forkState.pid < (pid_t)0) {
        completion(iTermJobManagerForkAndExecStatusFailedToFork);
        return;
    }

    [self queueDidForkParent:&forkState
                    ttyState:ttyState
                        task:task
                  completion:completion];
}

- (void)queueDidForkParent:(const iTermForkState *)forkStatePtr
                  ttyState:(iTermTTYState)ttyState
                      task:(id<iTermTask>)task
                completion:(void (^)(iTermJobManagerForkAndExecStatus))completion {
    // Make sure the master side of the pty is closed on future exec() calls.
    DLog(@"fcntl");
    fcntl(self.fd, F_SETFD, fcntl(self.fd, F_GETFD) | FD_CLOEXEC);

    // The client and server connected to each other before forking. The server
    // will send us the child pid now. We don't really need the rest of the
    // stuff in serverConnection since we already know it, but that's ok.
    iTermForkState forkState = *forkStatePtr;
    DLog(@"Begin handshake");
    int connectionFd = forkState.connectionFd;
    int deadmansPipeFd = forkState.deadMansPipe[0];
    // This takes about 200ms on a fast machine so pop off to a background queue to do it.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        iTermFileDescriptorServerConnection serverConnection = iTermFileDescriptorClientRead(connectionFd,
                                                                                             deadmansPipeFd);
        dispatch_async(self.queue, ^{
            iTermJobManagerForkAndExecStatus status =
            [self queueDidCompleteHandshakeWithForkState:forkState
                                                ttyState:ttyState
                                        serverConnection:serverConnection
                                                    task:task];
            completion(status);
        });
    });
}

- (iTermJobManagerForkAndExecStatus)queueDidCompleteHandshakeWithForkState:(iTermForkState)state
                                                                  ttyState:(const iTermTTYState)ttyState
                                                          serverConnection:(iTermFileDescriptorServerConnection)serverConnection
                                                                      task:(id<iTermTask>)task {
    DLog(@"Handshake complete");
    close(state.deadMansPipe[0]);
    if (serverConnection.ok) {
        // We intentionally leave connectionFd open. If iTerm2 stops unexpectedly then its closure
        // lets the server know it should call accept(). We now have two copies of the master PTY
        // file descriptor. Let's close the original one because attachToServer: will use the
        // copy in serverConnection.
        close(_fd);
        DLog(@"close fd");
        _fd = -1;

        // The serverConnection has the wrong server PID because the connection was made prior
        // to fork(). Update serverConnection with the real server PID.
        serverConnection.serverPid = state.pid;

        // Connect this task to the server's PIDs and file descriptor.
        DLog(@"attaching...");
        iTermGeneralServerConnection general = {
            .type = iTermGeneralServerConnectionTypeMono,
            .mono = serverConnection
        };
        [self queueAttachToServer:general task:task];
        DLog(@"attached. Set nonblocking");
        self.tty = [NSString stringWithUTF8String:ttyState.tty];

        int flags = fcntl(_fd, F_GETFL);
        fcntl(_fd, F_SETFL, flags | O_NONBLOCK);

        DLog(@"fini");
        return iTermJobManagerForkAndExecStatusSuccess;
    }
    close(_fd);
    DLog(@"Server died immediately!");
    DLog(@"fini");
    return iTermJobManagerForkAndExecStatusTaskDiedImmediately;
}

// After this returns you must do:
//     [[TaskNotifier sharedInstance] registerTask:task];
// but not on self.queue!
- (void)queueAttachToServer:(iTermGeneralServerConnection)serverConnection
                       task:(id<iTermTask>)task {
    assert(serverConnection.type == iTermGeneralServerConnectionTypeMono);
    assert([iTermAdvancedSettingsModel runJobsInServers]);
    _fd = serverConnection.mono.ptyMasterFd;
    _serverPid = serverConnection.mono.serverPid;
    _serverChildPid = serverConnection.mono.childPid;
    _socketFd = serverConnection.mono.socketFd;
    if (_serverChildPid > 0) {
        [[iTermProcessCache sharedInstance] registerTrackedPID:_serverChildPid];
    }
}

// NOTE: The caller assumes this is synchronous and can't fail when it knows it's a monoserver.
- (void)attachToServer:(iTermGeneralServerConnection)serverConnection
         withProcessID:(NSNumber *)pidNumber
                  task:(id<iTermTask>)task
            completion:(void (^)(iTermJobManagerAttachResults results))completion {
    completion([self attachToServer:serverConnection
                      withProcessID:pidNumber
                               task:task]);
}

- (iTermJobManagerAttachResults)attachToServer:(iTermGeneralServerConnection)serverConnection
                                 withProcessID:(NSNumber *)pidNumber
                                          task:(id<iTermTask>)task {
    const iTermJobManagerAttachResults results = iTermJobManagerAttachResultsAttached | iTermJobManagerAttachResultsRegistered;
    dispatch_sync(self.queue, ^{
        [self queueAttachToServer:serverConnection task:task];
    });
    DLog(@"Register task for %@", pidNumber);
    [[TaskNotifier sharedInstance] registerTask:task];
    if (pidNumber == nil) {
        return results;
    }

    const pid_t thePid = pidNumber.integerValue;
    // Prevent any future attempt to connect to this server as an orphan.
    char buffer[PATH_MAX + 1];
    iTermFileDescriptorSocketPath(buffer, sizeof(buffer), thePid);
    [[iTermOrphanServerAdopter sharedInstance] removePath:[NSString stringWithUTF8String:buffer]];
    [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
    return results;
}

- (void)closeSocketFd {
    close(_socketFd);
    _socketFd = -1;
}

- (void)sendSignal:(int)signo toServer:(BOOL)toServer {
    if (toServer) {
        if (_serverPid < 0) {
            return;
        }
        DLog(@"Sending signal %@ to server %@", @(signo), @(_serverPid));
        kill(_serverPid, signo);
        return;
    }
    if (_serverChildPid <= 0) {
        return;
    }
    [[iTermProcessCache sharedInstance] unregisterTrackedPID:_serverChildPid];
    DLog(@"Sending signal %@ to child %@", @(signo), @(_serverChildPid));
    kill(_serverChildPid, signo);
}

// Sends a signal to the server. This breaks it out of accept()ing forever when iTerm2 quits.
- (void)killServerIfRunning {
    __block pid_t serverPid = 0;
    dispatch_sync(self.queue, ^{
        if (_serverPid < 0) {
            return;
        }
        // This makes the server unlink its socket and exit immediately.
        DLog(@"Sending SIGUSR1 to server %@", @(_serverChildPid));
        kill(_serverPid, SIGUSR1);
        serverPid = _serverPid;
        // Don't want to leak these. They exist to let the server know when iTerm2 crashes, but if
        // the server is dead it's not needed any more.
        [self closeSocketFd];
    });
    // Mac OS seems to have a bug in waitpid. I've seen a case where the child has exited
    // (ps shows it in parens) but when the parent calls waitPid it just hangs. Rather than
    // wait here, I'll add the server to the deadpool. The TaskNotifier thread can wait
    // on it when it spins. I hope in this weird case that waitpid doesn't take long to run
    // and that it's rare enough that the zombies don't pile up. Not much else I can do.
    [[TaskNotifier sharedInstance] waitForPid:serverPid];
}

- (void)killWithMode:(iTermJobManagerKillingMode)mode {
    DLog(@"%@ killWithMode:%@", self, @(mode));
    switch (mode) {
        case iTermJobManagerKillingModeRegular:
            [self sendSignal:SIGHUP toServer:NO];
            break;

        case iTermJobManagerKillingModeForce:
            [self sendSignal:SIGKILL toServer:NO];
            break;

        case iTermJobManagerKillingModeForceUnrestorable:
            [self sendSignal:SIGKILL toServer:YES];
            [self sendSignal:SIGHUP toServer:NO];
            break;

        case iTermJobManagerKillingModeProcessGroup:
            if (_serverChildPid > 0) {
                [[iTermProcessCache sharedInstance] unregisterTrackedPID:_serverChildPid];
                // Kill a server-owned child.
                // TODO: Don't want to do this when Sparkle is upgrading.
                killpg(_serverChildPid, SIGHUP);
            }
            break;

        case iTermJobManagerKillingModeBrokenPipe:
            [self killServerIfRunning];
            break;
    }
}

- (pid_t)pidToWaitOn {
    // Prevent server from becoming a zombie.
    return _serverPid;
}

- (BOOL)isSessionRestorationPossible {
    return _serverChildPid > 0;
}

- (pid_t)externallyVisiblePid {
    __block pid_t result = 0;
    dispatch_sync(self.queue, ^{
        result = _serverChildPid;
    });
    return result;
}

- (BOOL)hasJob {
    __block BOOL result = NO;
    dispatch_sync(self.queue, ^{
        result = (_serverChildPid != -1);
    });
    return result;
}

- (id)sessionRestorationIdentifier {
    __block id result;
    dispatch_sync(self.queue, ^{
        result = @(_serverPid);
    });
    return result;
}

- (BOOL)ioAllowed {
    __block BOOL result;
    dispatch_sync(self.queue, ^{
        result = (_fd != -1);
    });
    return result;
}

- (BOOL)isReadOnly {
    return NO;
}

@end
