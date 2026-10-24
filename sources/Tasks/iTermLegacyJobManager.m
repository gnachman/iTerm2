//
//  iTermLegacyJobManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/16/19.
//

#import "iTermLegacyJobManager.h"

#import "DebugLogging.h"
#import "iTermProcessCache.h"
#import "NSArray+iTerm.h"
#import "PTYTask+MRR.h"
#import "TaskNotifier.h"
#import "iTerm2SharedARC-Swift.h"

@interface iTermLegacyJobManager()
@property (atomic) pid_t childPid;
@property (atomic, readwrite) iTermOwnedFileDescriptor *ownedFileDescriptor;
@end

@implementation iTermLegacyJobManager

@synthesize tty = _tty;
@synthesize queue = _queue;

+ (BOOL)available {
    return YES;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _queue = queue;
        // Never nil, so messaging it never returns 0 for "no descriptor".
        _ownedFileDescriptor = [[iTermOwnedFileDescriptor alloc] initWithFileDescriptor:-1];
        self.childPid = -1;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p fd=%@ tty=%@ childPid=%@>",
            NSStringFromClass([self class]), self, self.ownedFileDescriptor, _tty, @(self.childPid)];
}

// Takes ownership of `fd`. Any previous descriptor must already be closed.
- (void)takeOwnershipOfFileDescriptor:(int)fd {
    ITAssertWithMessage(self.ownedFileDescriptor.isClosed,
                        @"Replacing open file descriptor %@ with %@", self.ownedFileDescriptor, @(fd));
    self.ownedFileDescriptor = [[iTermOwnedFileDescriptor alloc] initWithFileDescriptor:fd];
}

// Ties the descriptor's lifetime to this object's rather than to whoever else holds the wrapper.
// A lease (such as a task I/O monitor's) still keeps it open until it is released.
- (void)dealloc {
    [self.ownedFileDescriptor close];
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

- (BOOL)closeFileDescriptor {
    @synchronized (self) {
        if (self.ownedFileDescriptor.isClosed) {
            return NO;
        }
        [self.ownedFileDescriptor close];
        return YES;
    }
}

- (void)forkAndExecWithTtyState:(iTermTTYState)ttyState
                        argpath:(NSString *)argpath
                           argv:(NSArray<NSString *> *)argv
                     initialPwd:(NSString *)initialPwd
                     newEnviron:(NSArray<NSString *> *)newEnviron
                           task:(id<iTermTask>)task
                     completion:(void (^)(iTermJobManagerForkAndExecStatus,
                                          NSNumber *))completion  {
    dispatch_async(self.queue, ^{
        const iTermJobManagerForkAndExecStatus status =
        [self queueForkAndExecWithTtyState:ttyState
                                   argpath:argpath
                                      argv:argv
                                initialPwd:initialPwd
                                newEnviron:newEnviron
                                      task:task];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == iTermJobManagerForkAndExecStatusSuccess) {
                RLog(@"Register task for pid %@", @(self.childPid));
                [[TaskNotifier sharedInstance] registerTask:task];
            }
            if (completion) {
                completion(status, nil);
            }
        });
    });
}

- (iTermJobManagerForkAndExecStatus)queueForkAndExecWithTtyState:(iTermTTYState)ttyState
                                                         argpath:(NSString *)argpath
                                                            argv:(NSArray<NSString *> *)argv
                                                      initialPwd:(NSString *)initialPwd
                                                      newEnviron:(NSArray<NSString *> *)newEnviron
                                                            task:(id<iTermTask>)task {
    iTermForkState forkState = {
        .connectionFd = -1,
        .deadMansPipe = { 0, 0 },
    };
    char **cArgv = [argv nullTerminatedCStringArray];
    char **cEnviron = [newEnviron nullTerminatedCStringArray];
    const int fd = iTermForkAndExecToRunJobDirectly(&forkState,
                                               &ttyState,
                                               argpath.UTF8String,
                                               cArgv,
                                               YES,
                                               initialPwd.UTF8String,
                                               cEnviron);
    iTermFreeeNullTerminatedCStringArray(cArgv);
    iTermFreeeNullTerminatedCStringArray(cEnviron);
    [self takeOwnershipOfFileDescriptor:fd];

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
    [self.ownedFileDescriptor withFileDescriptor:^(int fd) {
        fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC);
        fcntl(fd, F_SETFL, O_NONBLOCK);
    }];
    self.tty = [NSString stringWithUTF8String:ttyState.tty];
    return iTermJobManagerForkAndExecStatusSuccess;
}

- (void)attachToServer:(iTermGeneralServerConnection)serverConnection
         withProcessID:(NSNumber *)thePid
                  task:(id<iTermTask>)task
            completion:(void (^)(iTermJobManagerAttachResults))completion {
    completion(iTermJobManagerAttachResultsAttached | iTermJobManagerAttachResultsRegistered);
}

- (iTermJobManagerAttachResults)attachToServer:(iTermGeneralServerConnection)serverConnection
                                 withProcessID:(NSNumber *)thePid
                                          task:(id<iTermTask>)task {
    return iTermJobManagerAttachResultsAttached | iTermJobManagerAttachResultsRegistered;
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
        RLog(@"Kill process group %@ with signal %@", @(self.childPid), @(signo));
        killpg(self.childPid, signo);
    } else {
        RLog(@"Kill process %@ with signal %@", @(self.childPid), @(signo));
        kill(self.childPid, signo);
    }
    DLog(@"%@", [NSThread callStackSymbols]);
}

- (void)killWithMode:(iTermJobManagerKillingMode)mode {
    RLog(@"%@ killWithMode:%@", self, @(mode));
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
    return !self.ownedFileDescriptor.isClosed;
}

- (BOOL)isReadOnly {
    return NO;
}

@end
