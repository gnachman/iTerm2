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
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "TaskNotifier.h"

@implementation iTermMultiServerConnection {
    iTermFileDescriptorMultiClient *_client;
    BOOL _isPrimary;
    NSMutableArray<iTermFileDescriptorMultiClientChild *> *_unattachedChildren;
}

+ (instancetype)existingPrimaryConnection {
    for (iTermMultiServerConnection *connection in [self.registry allValues]) {
        if (connection->_isPrimary) {
            return connection;
        }
    };
    return nil;
}

+ (instancetype)anyConnectionCreatingIfNeeded {
    for (int i = 1; i < INT_MAX; i++) {
        iTermMultiServerConnection *instance = [self connectionForSocketNumber:i createIfPossible:YES];
        if (instance) {
            return instance;
        }
    }
    assert(NO);
}

+ (instancetype)primaryConnection {
    static iTermMultiServerConnection *instance;
    if (!instance || ![self.registry.allValues containsObject:instance]) {
        // Try to find a connection in the registry that is already labeled as primary.
        instance = [self existingPrimaryConnection];
        
        // If that doesn't work, try each socket number until we find one that already
        // exists or can be launched. This also sets its isPrimary flag.
        if (!instance) {
            instance = [self anyConnectionCreatingIfNeeded];
            instance->_isPrimary = YES;
        }
    };
    return instance;
}

+ (NSMutableDictionary<NSNumber *, iTermMultiServerConnection *> *)registry {
    static NSMutableDictionary<NSNumber *, iTermMultiServerConnection *> *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSMutableDictionary dictionary];
    });
    return registry;
}

+ (instancetype)connectionForSocketNumber:(int)number
                         createIfPossible:(BOOL)shouldCreate {
    iTermMultiServerConnection *result = self.registry[@(number)];
    if (result) {
        return result;
    }
    result = [[self alloc] initWithSocketNumber:number];
    assert(result);
    if (shouldCreate) {
        if (![result->_client attachOrLaunchServer]) {
            return nil;
        }
    } else {
        if (![result->_client attach]) {
            return nil;
        }
    }
    const BOOL isPrimary = (self.registry.count == 0);
    result->_isPrimary = isPrimary;
    self.registry[@(number)] = result;
    return result;
}

+ (NSString *)pathForNumber:(int)number {
    NSString *appSupportPath = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *filename = [NSString stringWithFormat:@"daemon-%d.socket", number];
    NSURL *url = [[NSURL fileURLWithPath:appSupportPath] URLByAppendingPathComponent:filename];
    return url.path;
}

- (instancetype)initWithSocketNumber:(int)number {
    self = [super init];
    if (self) {
        _socketNumber = number;
        _unattachedChildren = [NSMutableArray array];
        NSString *const path = [self.class pathForNumber:number];
        _client = [[iTermFileDescriptorMultiClient alloc] initWithPath:path];
        _client.delegate = self;
    }
    return self;
}

- (void)launchWithTTYState:(iTermTTYState *)ttyStatePtr
                   argpath:(const char *)argpath
                      argv:(const char **)argv
                initialPwd:(const char *)initialPwd
                newEnviron:(const char **)newEnviron
                completion:(void (^)(iTermFileDescriptorMultiClientChild *child,
                                     NSError *error))completion {
    if (!_client) {
        completion(nil,
                   [NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                                       code:iTermFileDescriptorMultiClientErrorCodeConnectionLost
                                   userInfo:nil]);
        return;
    }

    [_client launchChildWithExecutablePath:argpath
                                      argv:argv
                               environment:newEnviron
                                       pwd:initialPwd
                                  ttyState:ttyStatePtr
                                completion:^(iTermFileDescriptorMultiClientChild * _Nonnull child, NSError * _Nullable error) {
        if (error) {
            DLog(@"While creating child: %@", error);
        }
        completion(child, error);
    }];
}

- (iTermFileDescriptorMultiClientChild *)attachToProcessID:(pid_t)pid {
    iTermFileDescriptorMultiClientChild *child = [_unattachedChildren objectPassingTest:^BOOL(iTermFileDescriptorMultiClientChild *element, NSUInteger index, BOOL *stop) {
        return element.pid == pid;
    }];
    if (!child) {
        return nil;
    }
    [_unattachedChildren removeObject:child];
    return child;
}

- (void)waitForChild:(iTermFileDescriptorMultiClientChild *)child
removePreemptively:(BOOL)removePreemptively
        completion:(void (^)(int, NSError * _Nullable))completion {
    if (!_client) {
        completion(0, [NSError errorWithDomain:iTermFileDescriptorMultiClientErrorDomain
                                          code:iTermFileDescriptorMultiClientErrorCodeConnectionLost
                                      userInfo:nil]);
        return;
    }
    [_client waitForChild:child removePreemptively:removePreemptively completion:completion];
}

- (pid_t)pid {
    return _client.serverPID;
}

#pragma mark - iTermFileDescriptorMultiClientDelegate

- (void)fileDescriptorMultiClient:(iTermFileDescriptorMultiClient *)client
                 didDiscoverChild:(iTermFileDescriptorMultiClientChild *)child {
    [_unattachedChildren addObject:child];
}

- (void)fileDescriptorMultiClientDidClose:(iTermFileDescriptorMultiClient *)client {
    assert(client == _client);
    _client.delegate = nil;
    _client = nil;
    [[[self class] registry] removeObjectForKey:@(self.socketNumber)];
}

- (void)fileDescriptorMultiClient:(iTermFileDescriptorMultiClient *)client
                childDidTerminate:(iTermFileDescriptorMultiClientChild *)child {
    const pid_t pid = child.pid;
    [client waitForChild:child removePreemptively:NO completion:^(int status, NSError * _Nullable error) {
        if (error) {
            DLog(@"Failed to wait on child with pid %d: %@", pid, error);
            return;
        }
        DLog(@"Child with pid %d terminated with status %d", pid, status);

        // Post a notification that causes the task to be removed from the task notifier. Note that
        // this is usually unnecessary because the file descriptor will return 0 before we finish
        // round-tripping on Wait. This is a backstop in case of the unexpected.
        [[iTermMultiServerChildDidTerminateNotification notificationWithProcessID:child.pid
                                                                terminationStatus:child.terminationStatus] post];
    }];
}

@end
