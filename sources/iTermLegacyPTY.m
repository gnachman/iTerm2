//
//  iTermLegacyPTY.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/12/19.
//

#import "iTermLegacyPTY.h"

#import "iTermProcessCache.h"
#import "PTYTask+MRR.h"

#include <signal.h>
#include <unistd.h>

@implementation iTermLegacyPTY {
    int _fd;
    pid_t _childPid;  // -1 when servers are in use; otherwise is pid of child.
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _childPid = (pid_t)-1;
        _fd = -1;
    }
    return self;
}

- (void)dealloc {
    [self shutdown];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p fd=%@ childPid=%@>", self.class, self, @(_fd), @(_childPid)];
}

- (void)shutdown {
    if (_childPid > 0) {
        // Terminate an owned child.
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_childPid];
        // TODO: The use of killpg seems pretty sketchy. It takes a pgid_t, not a
        // pid_t. Are they guaranteed to always be the same for process group
        // leaders?
        killpg(_childPid, SIGHUP);
        _childPid = -1;
    }
}

- (void)closeFileDescriptor {
    if (_fd != -1) {
        close(_fd);
        _fd = -1;
    }
}

- (BOOL)pidIsChild {
    return _childPid != -1;
}

- (pid_t)serverPid {
    return -1;
}

- (int)fd {
    return _fd;
}

- (pid_t)pid {
    return _childPid;
}

- (void)sendSignal:(int)signo toServer:(BOOL)toServer {
    if (_childPid >= 0) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_childPid];
        kill(_childPid, signo);
    }
}

- (void)invalidate {
    _fd = -1;
}

- (BOOL)tryToAttachToServerWithProcessId:(pid_t)thePid {
    return NO;
}

- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection {
    assert(NO);
}

- (void)killServerIfRunning {
}

- (void)didForkParent:(const iTermForkState *)forkState
             ttyState:(iTermTTYState *)ttyState
          synchronous:(BOOL)synchronous
           completion:(void (^)(NSString *tty, BOOL failedImmediately, BOOL shouldRegister))completion {
    fcntl(_fd, F_SETFL, O_NONBLOCK);
    completion([NSString stringWithUTF8String:ttyState->tty],
               NO,
               YES);
}

- (BOOL)forkAndExecWithEnvironment:(char **)newEnviron
                         forkState:(iTermForkState *)forkState
                          ttyState:(iTermTTYState *)ttyState
                           argPath:(const char *)argpath
                              argv:(const char **)argv
                        initialPwd:(const char *)initialPwd {
    _fd = iTermForkAndExecToRunJobDirectly(forkState,
                                           ttyState,
                                           argpath,
                                           argv,
                                           YES /* closeFileDescriptors */,
                                           initialPwd,
                                           newEnviron);
    // If you get here you're the parent.
    _childPid = forkState->pid;
    if (_childPid > 0) {
        [[iTermProcessCache sharedInstance] registerTrackedPID:_childPid];
    }
    return YES;
}

- (BOOL)isatty {
    return YES;
}

@end

