//
//  iTermMultiServerConnection.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/1/19.
//

#import "iTermMultiServerConnection.h"

#import "DebugLogging.h"
#import "iTermNotificationCenter.h"
#import "iTermProcessCache.h"
#import "iTermThreadSafety.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "TaskNotifier.h"
#include <sys/un.h>

@class iTermMultiServerConnectionState;

@interface iTermMultiServerConnectionGlobalState: iTermSynchronizedState<iTermMultiServerConnectionState *>
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, iTermMultiServerConnection *> *registry;
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, NSMutableArray<iTermCallback *> *> *pending;
@property (nonatomic, strong) iTermMultiServerConnection *primary;
@end

@implementation iTermMultiServerConnectionGlobalState
- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super initWithQueue:queue];
    if (self) {
        _registry = [NSMutableDictionary dictionary];
        _pending = [NSMutableDictionary dictionary];
    }
    return self;
}
@end

@class iTermMultiServerPerConnectionState;
@interface iTermMultiServerPerConnectionState: iTermSynchronizedState<iTermMultiServerPerConnectionState *>
@property (nonatomic, strong) iTermFileDescriptorMultiClient *client;
@property (nonatomic, strong, readonly) NSMutableArray<iTermFileDescriptorMultiClientChild *> *unattachedChildren;
@end

@implementation iTermMultiServerPerConnectionState
- (instancetype)initWithQueue:(dispatch_queue_t)queue client:(iTermFileDescriptorMultiClient *)client {
    self = [super initWithQueue:queue];
    if (self) {
        _client = client;
        _unattachedChildren = [NSMutableArray array];
    }
    return self;
}
@end

@interface iTermMultiServerConnection()
@property (nonatomic, readonly) iTermThread<iTermMultiServerPerConnectionState *> *thread;
@end

@implementation iTermMultiServerConnection

#pragma mark - Class Method APIs

+ (void)getOrCreatePrimaryConnectionWithCallback:(iTermCallback<id, iTermMultiServerConnection *> *)callback {
    [self.thread dispatchAsync:^(iTermMultiServerConnectionGlobalState * _Nonnull state) {
        [self getOrCreatePrimaryConnectionWithState:state callback:callback];
    }];
}

+ (void)getConnectionForSocketNumber:(int)number
                    createIfPossible:(BOOL)shouldCreate
                            callback:(iTermCallback<id, iTermResult<iTermMultiServerConnection *> *> *)callback {
    DLog(@"Want to get connection for socket %@. shouldCreate=%@", @(number), @(shouldCreate));
    [self.thread dispatchAsync:^(iTermMultiServerConnectionGlobalState * _Nonnull state) {
        [self connectionForSocketNumber:number
                       createIfPossible:shouldCreate
                                  state:state
                               callback:callback];
    }];
}

#pragma mark - Private Class Methods

+ (iTermThread<iTermMultiServerConnectionGlobalState *> *)thread {
    static iTermThread<iTermMultiServerConnectionGlobalState *> *thread;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        thread = [iTermThread withLabel:@"com.iterm2.multi-server-registry"
                           stateFactory:^iTermSynchronizedState * _Nullable(dispatch_queue_t  _Nonnull queue) {
            return [[iTermMultiServerConnectionGlobalState alloc] initWithQueue:queue];
        }];
    });
    return thread;
}

+ (void)findExistingPrimaryConnection:(iTermCallback<iTermMultiServerConnectionGlobalState *, iTermMultiServerConnection *> *)callback {
    [self.thread dispatchAsync:^(iTermMultiServerConnectionGlobalState *state) {
        [callback invokeWithObject:state.primary];
    }];
}

+ (void)findAnyConnectionCreatingIfNeededWithState:(iTermMultiServerConnectionGlobalState *)state
                                          callback:(iTermCallback<id, iTermMultiServerConnection *> *)callback {
    DLog(@"findAnyConnectionCreatingIfNeededWithState");
    [state check];

    iTermMultiServerConnection *anyConnection = state.registry.allValues.firstObject;
    if (anyConnection) {
        [callback invokeWithObject:anyConnection];
        return;
    }

    [self tryCreatingConnectionStartingAtNumber:1 failures:0 state:state callback:callback];
}

+ (void)tryCreatingConnectionStartingAtNumber:(int)i
                                     failures:(int)failures
                                        state:(iTermMultiServerConnectionGlobalState *)state
                                     callback:(iTermCallback<id, iTermMultiServerConnection *> *)callback {
    DLog(@"tryCreatingConnectionStartingAtNumber: %@", @(i));
    [self connectionForSocketNumber:i
                   createIfPossible:YES
                              state:state
                           callback:[self.thread newCallbackWithBlock:^(iTermMultiServerConnectionGlobalState *state,
                                                                        iTermResult<iTermMultiServerConnection *> *result) {
        [result handleObject:
         ^(iTermMultiServerConnection * _Nonnull object) {
            [callback invokeWithObject:object];
        } error:
         ^(NSError * _Nonnull error) {
            DLog(@"tryCreatingConnectionStartingAtNumber: Failed, trying the next number.");
            if (failures >= 5) {
                [callback invokeWithObject:nil];
                return;
            }
            [self tryCreatingConnectionStartingAtNumber:i + 1
                                               failures:failures + 1
                                                  state:state
                                               callback:callback];
        }];
    }]];
}

+ (void)getOrCreatePrimaryConnectionWithState:(iTermMultiServerConnectionGlobalState *)state
                                     callback:(iTermCallback<id, iTermMultiServerConnection *> *)callback {
    if (state.primary && [state.registry.allValues containsObject:state.primary]) {
        [callback invokeWithObject:state.primary];
        return;
    }

    [self findAnyConnectionCreatingIfNeededWithState:state callback:callback];
}

+ (BOOL)available {
    return [self pathIsSafe:[self pathForNumber:1000]];
}

+ (void)connectionForSocketNumber:(int)number
                 createIfPossible:(BOOL)shouldCreate
                            state:(iTermMultiServerConnectionGlobalState *)globalState
                         callback:(iTermCallback<id, iTermResult<iTermMultiServerConnection *> *> *)callback {
    iTermMultiServerConnection *result = globalState.registry[@(number)];
    if (result) {
        DLog(@"Already have a good server connection for %@", @(number));
        [callback invokeWithObject:[iTermResult withObject:result]];
        return;
    }

    NSMutableArray<iTermCallback *> *pendingCallbacks = globalState.pending[@(number)];
    if (pendingCallbacks) {
        DLog(@"Add to pending callback for socket %@", @(number));
        [pendingCallbacks addObject:callback];
        return;
    }

    result = [[self alloc] initWithSocketNumber:number];
    assert(result);

    globalState.pending[@(number)] = [NSMutableArray arrayWithObject:callback];

    DLog(@"Don't have an existing or pending connection for %@", @(number));
    [result.thread dispatchAsync:^(iTermMultiServerPerConnectionState * _Nullable connectionState) {
        if (shouldCreate) {
            // Attach or launch
            DLog(@"Attach or launch socket %@", @(number));
            [connectionState.client attachToOrLaunchNewDaemonWithCallback:[self.thread newCallbackWithBlock:^(iTermMultiServerConnectionGlobalState *globalState, NSNumber *statusNumber) {
                iTermResult *resultObject;
                if (!statusNumber.boolValue) {
                    DLog(@"Failed to attach or launch socket %@", @(number));
                    resultObject = [iTermResult withError:self.cannotConnectError];
                } else {
                    DLog(@"Succeeded to attach or launch socket %@", @(number));
                    resultObject = [iTermResult withObject:result];
                    [self addConnection:result number:number state:globalState];
                }
                [self invokePendingCallbacksForSocketNumber:number
                                                      state:globalState
                                                     result:resultObject];
            }]];
            return;
        }

        // Attach
        DLog(@"Attach to %@", @(number));
        [connectionState.client attachWithCallback:[self.thread newCallbackWithBlock:^(iTermMultiServerConnectionGlobalState *globalState, NSNumber *statusNumber) {
            if (!statusNumber.boolValue) {
                DLog(@"Attach failed for socket %@", @(number));
                [self invokePendingCallbacksForSocketNumber:number
                                                      state:globalState
                                                     result:[iTermResult withError:self.cannotConnectError]];
            } else {
                [self addConnection:result number:number state:globalState];
                DLog(@"Attach succeeded for socket %@", @(number));
                [self invokePendingCallbacksForSocketNumber:number
                                                      state:globalState
                                                     result:[iTermResult withObject:result]];
            }
        }]];
    }];
}

+ (void)invokePendingCallbacksForSocketNumber:(int)number
                                        state:(iTermMultiServerConnectionGlobalState *)globalState
                                       result:(iTermResult *)resultObject {
    NSMutableArray<iTermCallback *> *pendingCallbacks = globalState.pending[@(number)];
    [globalState.pending removeObjectForKey:@(number)];
    for (iTermCallback *callback in pendingCallbacks) {
        DLog(@"Running pending callback for %@ with result %@", @(number), resultObject);
        [callback invokeWithObject:resultObject];
    }
}

+ (NSError *)cannotConnectError {
    return [NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                               code:iTermFileDescriptorMultiClientErrorCannotConnect
                           userInfo:nil];
}

+ (void)addConnection:(iTermMultiServerConnection *)result
               number:(NSInteger)number
                state:(iTermMultiServerConnectionGlobalState *)state {
    DLog(@"Register connection number %@", @(number));
    state.registry[@(number)] = result;
    if (!state.primary) {
        state.primary = result;
    }
}

+ (BOOL)pathIsSafe:(NSString *)path {
    struct sockaddr_un addr;
    return (strlen(path.UTF8String) + 1 <= sizeof(addr.sun_path));
}

+ (NSString *)pathForNumber:(int)number {
    // Normally use application support for the socket because that's where we keep everything
    // else. But for some users the path may be too long to fit in sockaddr_un.sun_path, in which
    // case we'll fall back to their home directory.
    NSString *appSupportPath = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *normalFilename = [NSString stringWithFormat:@"iterm2-daemon-%d.socket", number];
    NSURL *normalURL = [[NSURL fileURLWithPath:appSupportPath] URLByAppendingPathComponent:normalFilename];
    if ([self pathIsSafe:normalURL.path] && [[NSFileManager defaultManager] directoryIsWritable:appSupportPath]) {
        return normalURL.path;
    }

    NSString *homedir = NSHomeDirectory();
    NSString *dotdir = [homedir stringByAppendingPathComponent:@".iterm2"];
    NSString *shortFilename = [NSString stringWithFormat:@"%d.socket", number];
    NSURL *shortURL = [[NSURL fileURLWithPath:dotdir] URLByAppendingPathComponent:shortFilename];

    BOOL isdir = NO;

    // Try to create ~/.iterm2
    // NOTE: If this fails we return the known-to-be-too-long normal path. It is important to check
    // that the path is legal before using it.
    if (![[NSFileManager defaultManager] fileExistsAtPath:dotdir isDirectory:&isdir]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:dotdir withIntermediateDirectories:NO attributes:nil error:&error];
        if (error) {
            // Failed to create it.
            // check.
            return normalURL.path;
        }
    }
    if (!isdir) {
        // Can't put a directory there because a file already exists.
        return normalURL.path;
    }

    return shortURL.path;
}

#pragma mark - Instance Methods

- (instancetype)initWithSocketNumber:(int)number {
    self = [super init];
    if (self) {
        _thread = [iTermThread withLabel:@"com.iterm2.multi-server-conn" stateFactory:^iTermSynchronizedState * _Nullable(dispatch_queue_t  _Nonnull queue) {
            NSString *const path = [self.class pathForNumber:number];
            iTermFileDescriptorMultiClient *client = [[iTermFileDescriptorMultiClient alloc] initWithPath:path];
            client.delegate = self;
            return [[iTermMultiServerPerConnectionState alloc] initWithQueue:queue client:client];
        }];
        _socketNumber = number;
    }
    return self;
}

#pragma mark - Instance Method APIs

- (pid_t)pid {
    __block pid_t pid;
    [_thread dispatchSync:^(iTermMultiServerPerConnectionState * _Nullable state) {
        pid = state.client.serverPID;
    }];
    return pid;
}

- (NSArray<iTermFileDescriptorMultiClientChild *> *)unattachedChildren {
    __block NSArray<iTermFileDescriptorMultiClientChild *> *result;
    [_thread dispatchSync:^(iTermMultiServerPerConnectionState * _Nullable state) {
        result = state.unattachedChildren;
    }];
    return result;
}

- (void)attachToProcessID:(pid_t)pid
                 callback:(iTermCallback<id, iTermFileDescriptorMultiClientChild *> *)callback {
    [_thread dispatchAsync:^(iTermMultiServerPerConnectionState * _Nullable state) {
        iTermFileDescriptorMultiClientChild *child =
        [state.unattachedChildren objectPassingTest:^BOOL(iTermFileDescriptorMultiClientChild *element,
                                                          NSUInteger index,
                                                          BOOL *stop) {
            return element.pid == pid;
        }];
        if (!child) {
            DLog(@"Failed to attach to child with pid %@ - not in unattached children", @(pid));
            [callback invokeWithObject:nil];
            return;
        }
        DLog(@"Attached to pid %@. Remove unattached child", @(pid));
        [state.unattachedChildren removeObject:child];
        [callback invokeWithObject:child];
    }];
}

// These C pointers live until the callback is run.
- (void)launchWithTTYState:(iTermTTYState)ttyState
                   argpath:(const char *)argpath
                      argv:(char **)argv
                initialPwd:(const char *)initialPwd
                newEnviron:(char **)newEnviron
                  callback:(iTermCallback<id, iTermResult<iTermFileDescriptorMultiClientChild *> *> *)callback {
    DLog(@"begin");
    [_thread dispatchAsync:^(iTermMultiServerPerConnectionState * _Nullable state) {
        DLog(@"dispatched");
        if (!state.client) {
            DLog(@"No client");
            NSError *error = [NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                                                 code:iTermFileDescriptorMultiClientErrorCodeConnectionLost
                                             userInfo:nil];
            [callback invokeWithObject:[iTermResult withError:error]];
            return;
        }

        [state.client launchChildWithExecutablePath:argpath
                                               argv:argv
                                        environment:newEnviron
                                                pwd:initialPwd
                                           ttyState:ttyState
                                           callback:callback];
    }];
}

// Called on job manager's queue from queueAttachToServer:withProcessID:task: and queueKillWithMode:
- (void)waitForChild:(iTermFileDescriptorMultiClientChild *)child
  removePreemptively:(BOOL)removePreemptively
            callback:(iTermCallback<id, iTermResult<NSNumber *> *> *)callback {
    [_thread dispatchAsync:^(iTermMultiServerPerConnectionState * _Nullable state) {
        if (!state.client) {
            NSError *error = [NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                                                 code:iTermFileDescriptorMultiClientErrorCodeConnectionLost
                                             userInfo:nil];
            [callback invokeWithObject:[iTermResult withError:error]];
            return;
        }
        [state.client waitForChild:child removePreemptively:removePreemptively callback:callback];
    }];
}

#pragma mark - iTermFileDescriptorMultiClientDelegate

- (void)fileDescriptorMultiClient:(iTermFileDescriptorMultiClient *)client
                 didDiscoverChild:(iTermFileDescriptorMultiClientChild *)child {
    [_thread dispatchAsync:^(iTermMultiServerPerConnectionState * _Nullable state) {
        DLog(@"Discovered child %@. Add to unattached children.", child);
        [state.unattachedChildren addObject:child];
    }];
}

- (void)fileDescriptorMultiClientDidClose:(iTermFileDescriptorMultiClient *)client {
    [[iTermMultiServerConnection thread] dispatchAsync:^(iTermMultiServerConnectionGlobalState * _Nullable state) {
        [state.registry removeObjectForKey:@(self.socketNumber)];
        [self.thread dispatchAsync:^(iTermMultiServerPerConnectionState * _Nullable state) {
            assert(client == state.client);
            state.client.delegate = nil;
            state.client = nil;
        }];
    }];
}

- (void)fileDescriptorMultiClient:(iTermFileDescriptorMultiClient *)client
                childDidTerminate:(iTermFileDescriptorMultiClientChild *)child {
    [client waitForChild:child
      removePreemptively:NO
                callback:nil];
}

@end
