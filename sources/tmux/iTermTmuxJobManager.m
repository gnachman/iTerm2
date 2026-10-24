//
//  iTermTmuxJobManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/28/20.
//

#import "iTermTmuxJobManager.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"

@implementation iTermTmuxJobManager

@synthesize tty = _tty;
@synthesize queue = _queue;

+ (BOOL)available {
    return YES;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        // Never nil, so messaging it never returns 0 for "no descriptor".
        _ownedFileDescriptor = [[iTermOwnedFileDescriptor alloc] initWithFileDescriptor:-1];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p read-only-fd=%@ tty=%@>",
            NSStringFromClass([self class]), self, self.ownedFileDescriptor, _tty];
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
        return !self.ownedFileDescriptor.isClosed;
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
