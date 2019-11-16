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
#import "TaskNotifier.h"

@implementation iTermMonoServerJobManager

@synthesize fd = _fd;
@synthesize tty = _tty;
@synthesize serverPid = _serverPid;
@synthesize serverChildPid = _serverChildPid;
@synthesize socketFd = _socketFd;

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

- (void)finishHandshakeWithJobInServer:(const iTermForkState *)forkStatePtr
                              ttyState:(const iTermTTYState *)ttyStatePtr
                           synchronous:(BOOL)synchronous
                                  task:(id<iTermTask>)task
                            completion:(void (^)(BOOL taskDiedImmediately))completion {
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
                               completion:(void (^)(BOOL taskDiedImmediately))completion {
    DLog(@"Handshake complete");
    close(state.deadMansPipe[0]);
    BOOL taskDiedImmediately = NO;
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
    } else {
        close(_fd);
        DLog(@"Server died immediately!");
        taskDiedImmediately = YES;
    }
    DLog(@"fini");
    if (completion) {
        completion(taskDiedImmediately);
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
         withProcessID:(pid_t)thePid
                  task:(id<iTermTask>)task {
    [self attachToServer:serverConnection task:task];

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

@end
