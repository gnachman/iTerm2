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
#import "NSWorkspace+iTerm.h"
#import "PTYTask+MRR.h"
#import "TaskNotifier.h"

#import <Foundation/Foundation.h>

@implementation iTermMonoServerJobManager {
    pid_t _serverChildPid;
    pid_t _serverPid;

    // File descriptor for unix domain socket connected to server. Only safe to close after server is dead.
    pid_t _socketFd;
}

@synthesize fd = _fd;
@synthesize tty = _tty;

- (instancetype)init {
    self = [super init];
    if (self) {
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

- (NSString *)pathToNewUnixDomainSocket {
    // Create a temporary filename for the unix domain socket. It'll only exist for a moment.
    NSString *tempPath = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"iTerm2-temp-socket."
                                                                             suffix:@""];
    return tempPath;
}

- (void)forkAndExecWithTtyState:(iTermTTYState *)ttyStatePtr
                        argpath:(const char *)argpath
                           argv:(const char **)argv
                     initialPwd:(const char *)initialPwd
                     newEnviron:(char **)newEnviron
                    synchronous:(BOOL)synchronous
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

    self.fd = iTermForkAndExecToRunJobInServer(&forkState,
                                               ttyStatePtr,
                                               unixDomainSocketPath,
                                               argpath,
                                               argv,
                                               NO,
                                               initialPwd,
                                               newEnviron);
    // If you get here you're the parent.
    _serverPid = forkState.pid;

    if (forkState.pid < (pid_t)0) {
        completion(iTermJobManagerForkAndExecStatusFailedToFork);
        return;
    }

    [self didForkParent:&forkState
               ttyState:ttyStatePtr
            synchronous:synchronous
                   task:task
             completion:completion];
}

- (void)didForkParent:(const iTermForkState *)forkStatePtr
             ttyState:(iTermTTYState *)ttyStatePtr
          synchronous:(BOOL)synchronous
                 task:(id<iTermTask>)task
           completion:(void (^)(iTermJobManagerForkAndExecStatus))completion {
    // Make sure the master side of the pty is closed on future exec() calls.
    DLog(@"fcntl");
    fcntl(self.fd, F_SETFD, fcntl(self.fd, F_GETFD) | FD_CLOEXEC);

    // The client and server connected to each other before forking. The server
    // will send us the child pid now. We don't really need the rest of the
    // stuff in serverConnection since we already know it, but that's ok.
    iTermForkState forkState = *forkStatePtr;
    iTermTTYState ttyState = *ttyStatePtr;
    DLog(@"Begin handshake");
    int connectionFd = forkState.connectionFd;
    int deadmansPipeFd = forkState.deadMansPipe[0];
    // This takes about 200ms on a fast machine so pop off to a background queue to do it.
    if (!synchronous) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            iTermFileDescriptorServerConnection serverConnection = iTermFileDescriptorClientRead(connectionFd,
                                                                                                 deadmansPipeFd);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self didCompleteHandshakeWithForkState:forkState
                                               ttyState:ttyState
                                       serverConnection:serverConnection
                                                   task:task
                                             completion:completion];
            });
        });
    } else {
        iTermFileDescriptorServerConnection serverConnection = iTermFileDescriptorClientRead(connectionFd,
                                                                                             deadmansPipeFd);
        [self didCompleteHandshakeWithForkState:forkState
                                       ttyState:ttyState
                               serverConnection:serverConnection
                                           task:task
                                     completion:completion];
    }
}

- (void)didCompleteHandshakeWithForkState:(iTermForkState)state
                                 ttyState:(const iTermTTYState)ttyState
                         serverConnection:(iTermFileDescriptorServerConnection)serverConnection
                                     task:(id<iTermTask>)task
                               completion:(void (^)(iTermJobManagerForkAndExecStatus))completion {
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
        [self attachToServer:serverConnection task:task];
        DLog(@"attached. Set nonblocking");
        self.tty = [NSString stringWithUTF8String:ttyState.tty];
        fcntl(_fd, F_SETFL, O_NONBLOCK);
        DLog(@"fini");
        completion(iTermJobManagerForkAndExecStatusSuccess);
    } else {
        close(_fd);
        DLog(@"Server died immediately!");
        DLog(@"fini");
        completion(iTermJobManagerForkAndExecStatusTaskDiedImmediately);
    }
}

- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection
                  task:(id<iTermTask>)task {
    assert([iTermAdvancedSettingsModel runJobsInServers]);
    _fd = serverConnection.ptyMasterFd;
    _serverPid = serverConnection.serverPid;
    _serverChildPid = serverConnection.childPid;
    if (_serverChildPid > 0) {
        [[iTermProcessCache sharedInstance] registerTrackedPID:_serverChildPid];
    }
    _socketFd = serverConnection.socketFd;
    [[TaskNotifier sharedInstance] registerTask:task];
}

- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection
         withProcessID:(NSNumber *)pidNumber
                  task:(id<iTermTask>)task {
    [self attachToServer:serverConnection task:task];
    if (pidNumber == nil) {
        return;
    }

    const pid_t thePid = pidNumber.integerValue;
    // Prevent any future attempt to connect to this server as an orphan.
    char buffer[PATH_MAX + 1];
    iTermFileDescriptorSocketPath(buffer, sizeof(buffer), thePid);
    [[iTermOrphanServerAdopter sharedInstance] removePath:[NSString stringWithUTF8String:buffer]];
    [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
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
        DLog(@"Sending signal to server %@", @(_serverPid));
        kill(_serverPid, signo);
        return;
    }
    if (_serverChildPid < 0) {
        return;
    }
    [[iTermProcessCache sharedInstance] unregisterTrackedPID:_serverChildPid];
    kill(_serverChildPid, signo);
}

// Sends a signal to the server. This breaks it out of accept()ing forever when iTerm2 quits.
- (void)killServerIfRunning {
    if (_serverPid < 0) {
        return;
    }
    // This makes the server unlink its socket and exit immediately.
    kill(_serverPid, SIGUSR1);

    // Mac OS seems to have a bug in waitpid. I've seen a case where the child has exited
    // (ps shows it in parens) but when the parent calls waitPid it just hangs. Rather than
    // wait here, I'll add the server to the deadpool. The TaskNotifier thread can wait
    // on it when it spins. I hope in this weird case that waitpid doesn't take long to run
    // and that it's rare enough that the zombies don't pile up. Not much else I can do.
    [[TaskNotifier sharedInstance] waitForPid:_serverPid];

    // Don't want to leak these. They exist to let the server know when iTerm2 crashes, but if
    // the server is dead it's not needed any more.
    [self closeSocketFd];
}

- (void)killWithMode:(iTermJobManagerKillingMode)mode {
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
    return _serverChildPid;
}

- (BOOL)hasJob {
    return _serverChildPid != -1;
}

- (id)sessionRestorationIdentifier {
    return @(_serverPid);
}

@end
