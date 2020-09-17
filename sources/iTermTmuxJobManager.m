//
//  iTermTmuxJobManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/28/20.
//

#import "iTermTmuxJobManager.h"

@implementation iTermTmuxJobManager

@synthesize fd = _fd;
@synthesize tty = _tty;
@synthesize queue = _queue;

+ (BOOL)available {
    return YES;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _fd = -1;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p read-only-fd=%d tty=%@>",
            NSStringFromClass([self class]), self, _fd, _tty];
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
        if (self.fd == -1) {
            return NO;
        }
        close(self.fd);
        self.fd = -1;
        return YES;
    }
}

- (void)forkAndExecWithTtyState:(iTermTTYState)ttyState
                        argpath:(NSString *)argpath
                           argv:(NSArray<NSString *> *)argv
                     initialPwd:(NSString *)initialPwd
                     newEnviron:(NSArray<NSString *> *)newEnviron
                           task:(id<iTermTask>)task
                     completion:(void (^)(iTermJobManagerForkAndExecStatus))completion  {
    assert(NO);
}

- (void)attachToServer:(iTermGeneralServerConnection)serverConnection
         withProcessID:(NSNumber *)thePid
                  task:(id<iTermTask>)task
            completion:(void (^)(iTermJobManagerAttachResults results))completion {
    assert(NO);
}

- (iTermJobManagerAttachResults)attachToServer:(iTermGeneralServerConnection)serverConnection
                                 withProcessID:(NSNumber *)thePid
                                          task:(id<iTermTask>)task {
    assert(NO);
}

- (void)killWithMode:(iTermJobManagerKillingMode)mode {
}

- (pid_t)externallyVisiblePid {
    return 0;
}

- (BOOL)hasJob {
    return YES;
}

- (BOOL)ioAllowed {
    @synchronized (self) {
        return self.fd >= 0;
    }
}

- (BOOL)isSessionRestorationPossible {
    return NO;
}

- (pid_t)pidToWaitOn {
    return 0;
}

- (id)sessionRestorationIdentifier {
    return nil;
}

- (BOOL)isReadOnly {
    return YES;
}

@end
