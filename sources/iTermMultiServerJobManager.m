//
//  iTermMultiServerJobManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/25/19.
//

#import "iTermMultiServerJobManager.h"

#import "DebugLogging.h"
#import "iTermFileDescriptorMultiClient.h"
#import "iTermMultiServerConnection.h"
#import "iTermNotificationCenter.h"
#import "iTermProcessCache.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "TaskNotifier.h"

NSString *const iTermMultiServerRestorationKeyType = @"Type";
NSString *const iTermMultiServerRestorationKeyVersion = @"Version";
NSString *const iTermMultiServerRestorationKeySocket = @"Socket";
NSString *const iTermMultiServerRestorationKeyChildPID = @"Child PID";

// Value for iTermMultiServerRestorationKeyType
static NSString *const iTermMultiServerRestorationType = @"multiserver";
static const int iTermMultiServerMaximumSupportedRestorationIdentifierVersion = 1;

@interface iTermMultiServerJobManager()
@property (atomic, strong, readwrite) dispatch_queue_t queue;
@end

@implementation iTermMultiServerJobManager {
    iTermMultiServerConnection *_conn;
    iTermFileDescriptorMultiClientChild *_child;
}

@synthesize queue;

+ (BOOL)getGeneralConnection:(iTermGeneralServerConnection *)generalConnection
   fromRestorationIdentifier:(NSDictionary *)dict {
    NSString *type = dict[iTermMultiServerRestorationKeyType];
    if (![type isEqual:iTermMultiServerRestorationType]) {
        return NO;
    }

    NSNumber *version = [NSNumber castFrom:dict[iTermMultiServerRestorationKeyVersion]];
    if (!version || version.intValue < 0 || version.intValue > iTermMultiServerMaximumSupportedRestorationIdentifierVersion) {
        return NO;
    }

    NSNumber *socketNumber = [NSNumber castFrom:dict[iTermMultiServerRestorationKeySocket]];
    if (!socketNumber || socketNumber.intValue <= 0) {
        return NO;
    }
    NSNumber *childPidNumber = [NSNumber castFrom:dict[iTermMultiServerRestorationKeyChildPID]];
    if (!childPidNumber || childPidNumber.intValue < 0) {
        return NO;
    }
    memset(generalConnection, 0, sizeof(*generalConnection));
    generalConnection->type = iTermGeneralServerConnectionTypeMulti;
    generalConnection->multi.number = socketNumber.intValue;
    generalConnection->multi.pid = childPidNumber.intValue;
    return YES;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        self.queue = queue;
        static dispatch_once_t onceToken;
        static id subscriber;
        dispatch_once(&onceToken, ^{
            subscriber = [[NSObject alloc] init];
            [iTermMultiServerChildDidTerminateNotification subscribe:subscriber
                                                               block:
             ^(iTermMultiServerChildDidTerminateNotification * _Nonnull notification) {
                [[TaskNotifier sharedInstance] pipeDidBreakForExternalProcessID:notification.pid
                                                                         status:notification.terminationStatus];
            }];
        });
    }
    return self;
}

- (NSString *)description {
    __block NSString *result = nil;
    dispatch_sync(self.queue, ^{
        result = [NSString stringWithFormat:@"<%@: %p child=%@ connection=%@>",
                  NSStringFromClass([self class]), self, _child, _conn];
    });
    return result;
}

- (void)forkAndExecWithTtyState:(iTermTTYState *)ttyStatePtr
                        argpath:(const char *)argpath
                           argv:(const char **)argv
                     initialPwd:(const char *)initialPwd
                     newEnviron:(const char **)newEnviron
                           task:(id<iTermTask>)task
                     completion:(void (^)(iTermJobManagerForkAndExecStatus))completion {
    dispatch_sync(self.queue, ^{
        [self queueForkAndExecWithTtyState:ttyStatePtr
                                   argpath:argpath
                                      argv:argv
                                initialPwd:initialPwd
                                newEnviron:newEnviron
                                      task:task
                                completion:completion];
    });
}

- (void)queueForkAndExecWithTtyState:(iTermTTYState *)ttyStatePtr
                        argpath:(const char *)argpath
                           argv:(const char **)argv
                     initialPwd:(const char *)initialPwd
                     newEnviron:(const char **)newEnviron
                           task:(id<iTermTask>)task
                     completion:(void (^)(iTermJobManagerForkAndExecStatus))completion {
    _conn = [iTermMultiServerConnection primaryConnection];
    [_conn launchWithTTYState:ttyStatePtr
                      argpath:argpath
                         argv:argv
                   initialPwd:initialPwd
                   newEnviron:newEnviron
                   completion:^(iTermFileDescriptorMultiClientChild *child,
                                NSError *error) {
        self->_child = child;
        if (child != NULL) {
            // Happy path
            dispatch_async(dispatch_get_main_queue(), ^{
                [[iTermProcessCache sharedInstance] registerTrackedPID:child.pid];
                [[TaskNotifier sharedInstance] registerTask:task];
                [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
                completion(iTermJobManagerForkAndExecStatusSuccess);
            });
            return;
        }

        // Handle errors
        assert([error.domain isEqualToString:iTermFileDescriptorMultiClientErrorDomain]);
        const iTermFileDescriptorMultiClientErrorCode code = (iTermFileDescriptorMultiClientErrorCode)error.code;
        switch (code) {
            case iTermFileDescriptorMultiClientErrorCodePreemptiveWaitResponse:
            case iTermFileDescriptorMultiClientErrorCodeConnectionLost:
            case iTermFileDescriptorMultiClientErrorCodeNoSuchChild:
            case iTermFileDescriptorMultiClientErrorCodeCanNotWait:
            case iTermFileDescriptorMultiClientErrorCodeUnknown:
                completion(iTermJobManagerForkAndExecStatusServerError);
                return;
            case iTermFileDescriptorMultiClientErrorCodeForkFailed:
                completion(iTermJobManagerForkAndExecStatusFailedToFork);
                return;
        }
        assert(NO);
    }];
}

- (int)fd {
    __block int result = -1;
    dispatch_sync(self.queue, ^{
        result = _child ? _child.fd : -1;
    });
    return result;
}

- (BOOL)ioAllowed {
    __block BOOL result = NO;
    dispatch_sync(self.queue, ^{
        result = (_child != nil && _child.fd >= 0);
    });
    return result;
}

- (void)setFd:(int)fd {
    assert(fd == -1);
}

- (NSString *)tty {
    __block NSString *result = nil;
    dispatch_sync(self.queue, ^{
        result = [_child.tty copy];
    });
    return result;
}

- (void)setTty:(NSString *)tty {
    dispatch_sync(self.queue, ^{
        ITAssertWithMessage([NSObject object:tty isEqualToObject:_child.tty],
                            @"setTty:%@ when _child.tty=%@", tty, _child.tty);
    });
}

- (pid_t)externallyVisiblePid {
    __block pid_t result = 0;
    dispatch_sync(self.queue, ^{
        result = _child.pid;
    });
    return result;
}

- (BOOL)hasJob {
    __block BOOL result = NO;
    dispatch_sync(self.queue, ^{
        result = (_child != nil);
    });
    return result;
}

- (id)sessionRestorationIdentifier {
    ITBetaAssert(_conn != nil, @"nil connection");
    __block id result = nil;
    dispatch_sync(self.queue, ^{
        if (!_conn) {
            result = nil;
            return;
        }
        result = @{ iTermMultiServerRestorationKeyType: iTermMultiServerRestorationType,
                    iTermMultiServerRestorationKeyVersion: @(iTermMultiServerMaximumSupportedRestorationIdentifierVersion),
                    iTermMultiServerRestorationKeySocket: @(_conn.socketNumber),
                    iTermMultiServerRestorationKeyChildPID: @(_child.pid) };
    });
    return result;
}

- (pid_t)pidToWaitOn {
    return -1;
}

- (BOOL)isSessionRestorationPossible {
    __block BOOL result = NO;
    dispatch_sync(self.queue, ^{
        result = (_child != nil);
    });
    return result;
}

- (BOOL)attachToServer:(iTermGeneralServerConnection)serverConnection
         withProcessID:(NSNumber *)thePid
                  task:(id<iTermTask>)task {
    __block BOOL shouldRegister = NO;
    __block pid_t pid = 0;
    dispatch_sync(self.queue, ^{
        shouldRegister = [self queueAttachToServer:serverConnection withProcessID:thePid task:task];
        pid = _child.pid;
    });
    if (!shouldRegister) {
        return NO;
    }
    [[iTermProcessCache sharedInstance] registerTrackedPID:pid];
    [[TaskNotifier sharedInstance] registerTask:task];
    [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
    return YES;
}

- (BOOL)queueAttachToServer:(iTermGeneralServerConnection)serverConnection
              withProcessID:(NSNumber *)thePid
                       task:(id<iTermTask>)task {
    assert(serverConnection.type == iTermGeneralServerConnectionTypeMulti);
    assert(!_conn);
    assert(!_child);
    _conn = [iTermMultiServerConnection connectionForSocketNumber:serverConnection.multi.number
                                                 createIfPossible:NO];
    if (!_conn) {
        [task brokenPipe];
        return NO;
    }
    if (thePid != nil) {
        assert(thePid.integerValue == serverConnection.multi.pid);
    }
    _child = [_conn attachToProcessID:serverConnection.multi.pid];
    if (!_child) {
        // Happens when doing Quit (killing all children) followed by relaunching. Don't want a
        // broken pipe in that case.
        return NO;
    }
    if (_child.hasTerminated) {
        const pid_t pid = _child.pid;
        [_conn waitForChild:_child removePreemptively:NO completion:^(int status, NSError *error) {
            if (error) {
                DLog(@"Failed to wait on child with pid %d: %@", pid, error);
            } else {
                DLog(@"Child with pid %d terminated with status %d", pid, status);
            }
        }];
        [task brokenPipe];
        return NO;
    }
    return YES;
}

- (void)sendSignal:(int)signo toServer:(BOOL)toServer {
    if (toServer) {
        if (_conn.pid <= 0) {
            return;
        }
        DLog(@"Sending signal to server %@", @(_conn.pid));
        kill(_conn.pid, signo);
        return;
    }
    if (_child.pid <= 0) {
        return;
    }
    [[iTermProcessCache sharedInstance] unregisterTrackedPID:_child.pid];
    killpg(_child.pid, signo);
}

- (void)killWithMode:(iTermJobManagerKillingMode)mode {
    dispatch_sync(self.queue, ^{
        [self queueKillWithMode:mode];
    });
}

- (void)queueKillWithMode:(iTermJobManagerKillingMode)mode {
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
            if (_child.pid > 0) {
                [[iTermProcessCache sharedInstance] unregisterTrackedPID:_child.pid];
                // Kill a server-owned child.
                // TODO: Don't want to do this when Sparkle is upgrading.
                killpg(_child.pid, SIGHUP);
            }
            break;

        case iTermJobManagerKillingModeBrokenPipe:
            // This is irrelevant for the multiserver. Monoserver needs to ensure the server
            // dies even when the child is persistent, but multiserver can survive
            // its children.
            break;
    }
    if (_child.haveWaited) {
        return;
    }
    const pid_t pid = _child.pid;
    [_conn waitForChild:_child removePreemptively:YES completion:^(int status, NSError *error) {
        DLog(@"Preemptive wait for %d finished with status %d error %@", pid, status, error);
    }];
}

@end
