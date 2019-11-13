//
//  iTermMonoServerPTY.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/12/19.
//

#import "iTermMonoServerPTY.h"

#import "PTYTask+MRR.h"

#import "DebugLogging.h"
#import "iTermFileDescriptorSocketPath.h"
#import "iTermOrphanServerAdopter.h"
#import "iTermProcessCache.h"
#import "NSWorkspace+iTerm.h"
#import "TaskNotifier.h"

#import <AppKit/AppKit.h>
#import <signal.h>
#import <unistd.h>

@implementation iTermMonoServerPTY {
    int _fd;
    pid_t _serverPid;
    pid_t _serverChildPid;

    // File descriptor for unix domain socket connected to server. Only safe to close after server is dead.
    int _socketFd;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fd = -1;
        _serverPid = (pid_t)-1;
        _serverChildPid = -1;
        _socketFd = -1;
    }
    return self;
}

- (void)dealloc {
    [self shutdown];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p fd=%@ serverPid=%@ serverChildPid=%@ socketFd=%@>",
            self.class, self, @(_fd), @(_serverPid), @(_serverChildPid), @(_socketFd)];
}

- (void)shutdown {
    if (_serverChildPid) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_serverChildPid];
        // Kill a server-owned child.
        // TODO: Don't want to do this when Sparkle is upgrading.
        // TODO: The use of killpg seems pretty sketchy. It takes a pgid_t, not a
        // pid_t. Are they guaranteed to always be the same for process group
        // leaders?
        killpg(_serverChildPid, SIGHUP);
        _serverChildPid = -1;
    }
}

- (void)closeFileDescriptor {
    if (_fd != -1) {
        close(_fd);
        _fd = -1;
    }
}

- (BOOL)pidIsChild {
    return NO;
}

- (pid_t)serverPid {
    return _serverPid;
}

- (int)fd {
    return _fd;
}

- (pid_t)pid {
    return _serverChildPid;
}

- (void)sendSignal:(int)signo toServer:(BOOL)toServer {
    if (toServer && _serverPid != -1) {
        DLog(@"Sending signal to server %@", @(_serverPid));
        kill(_serverPid, signo);
    } else if (_serverChildPid != -1) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_serverChildPid];
        kill(_serverChildPid, signo);
    }
}

- (void)invalidate {
    _fd = -1;
}

- (BOOL)tryToAttachToServerWithProcessId:(pid_t)thePid {
    if (_serverChildPid != -1) {
        return NO;
    }

    // TODO: This server code is super scary so I'm NSLog'ing it to make it easier to recover
    // logs. These should eventually become DLog's and the log statements in the server should
    // become LOG_DEBUG level.
    DLog(@"tryToAttachToServerWithProcessId: Attempt to connect to server for pid %d", (int)thePid);
    iTermFileDescriptorServerConnection serverConnection = iTermFileDescriptorClientRun(thePid);
    if (!serverConnection.ok) {
        NSLog(@"Failed with error %s", serverConnection.error);
        return NO;
    } else {
        DLog(@"Succeeded.");
        [self attachToServer:serverConnection];

        // Prevent any future attempt to connect to this server as an orphan.
        char buffer[PATH_MAX + 1];
        iTermFileDescriptorSocketPath(buffer, sizeof(buffer), thePid);
        [[iTermOrphanServerAdopter sharedInstance] removePath:[NSString stringWithUTF8String:buffer]];
        [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
        return YES;
    }
}

- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection {
    _fd = serverConnection.ptyMasterFd;
    _serverPid = serverConnection.serverPid;
    _serverChildPid = serverConnection.childPid;
    if (_serverChildPid > 0) {
        [[iTermProcessCache sharedInstance] registerTrackedPID:_serverChildPid];
    }
    _socketFd = serverConnection.socketFd;
}

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
    close(_socketFd);
    _socketFd = -1;
}

- (void)didCompleteHandshakeWithForkState:(iTermForkState)state
                                 ttyState:(const iTermTTYState)ttyState
                         serverConnection:(iTermFileDescriptorServerConnection)serverConnection
                               completion:(void (^)(NSString *tty, BOOL failedImmediately, BOOL shouldRegister))completion {
    DLog(@"Handshake complete");
    close(state.deadMansPipe[0]);
    if (serverConnection.ok) {
        // We intentionally leave connectionFd open. If iTerm2 stops unexpectedly then its closure
        // lets the server know it should call accept(). We now have two copies of the master PTY
        // file descriptor. Let's close the original one because attachToServer: will use the
        // copy in serverConnection. The call to attachToServer: below replaces _fd with the
        // one in `serverConnection`.
        close(_fd);
        DLog(@"close fd");
        _fd = -1;

        // The serverConnection has the wrong server PID because the connection was made prior
        // to fork(). Update serverConnection with the real server PID.
        serverConnection.serverPid = state.pid;

        // Connect this task to the server's PIDs and file descriptor.
        DLog(@"attaching...");
        [self attachToServer:serverConnection];
        DLog(@"attached. Set nonblocking");
        fcntl(_fd, F_SETFL, O_NONBLOCK);
        completion([NSString stringWithUTF8String:ttyState.tty], NO, YES);
        return;
    }

    close(_fd);
    _fd = -1;
    DLog(@"Server died immediately!");
    completion(nil, YES, NO);
}

- (void)didForkParent:(const iTermForkState *)forkStatePtr
             ttyState:(iTermTTYState *)ttyStatePtr
          synchronous:(BOOL)synchronous
           completion:(void (^)(NSString *tty, BOOL failedImmediately, BOOL shouldRegister))completion {
    // Jobs run in servers. The client and server connected to each other
    // before forking. The server will send us the child pid now. We don't
    // really need the rest of the stuff in serverConnection since we already know
    // it, but that's ok.
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
                                             completion:completion];
            });
        });
    } else {
        iTermFileDescriptorServerConnection serverConnection = iTermFileDescriptorClientRead(connectionFd,
                                                                                             deadmansPipeFd);
        [self didCompleteHandshakeWithForkState:forkState
                                       ttyState:ttyState
                               serverConnection:serverConnection
                                     completion:completion];
    }
}

- (void)showFailedToCreateTempSocketError {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Error";
    alert.informativeText = [NSString stringWithFormat:@"An error was encountered while creating a temporary file with mkstemps. Verify that %@ exists and is writable.", NSTemporaryDirectory()];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (NSString *)pathToNewUnixDomainSocket {
    // Create a temporary filename for the unix domain socket. It'll only exist for a moment.
    NSString *tempPath = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"iTerm2-temp-socket."
                                                                             suffix:@""];
    if (tempPath == nil) {
        [self showFailedToCreateTempSocketError];
    }
    return tempPath;
}

- (BOOL)forkAndExecWithEnvironment:(char **)newEnviron
                         forkState:(iTermForkState *)forkState
                          ttyState:(iTermTTYState *)ttyState
                           argPath:(const char *)argpath
                              argv:(const char **)argv
                        initialPwd:(const char *)initialPwd {
    // Create a temporary filename for the unix domain socket. It'll only exist for a moment.
    DLog(@"get path to UDS");
    NSString *unixDomainSocketPath = [self pathToNewUnixDomainSocket];
    DLog(@"done");
    if (unixDomainSocketPath == nil) {
        return NO;
    }

    // Begin listening on that path as a unix domain socket.
    DLog(@"fork");

    _fd = iTermForkAndExecToRunJobInServer(forkState,
                                           ttyState,
                                           unixDomainSocketPath,
                                           argpath,
                                           argv,
                                           NO,
                                           initialPwd,
                                           newEnviron);
    // If you get here you're the parent.
    _serverPid = forkState->pid;
    return YES;
}

- (BOOL)isatty {
    return YES;
}

@end

