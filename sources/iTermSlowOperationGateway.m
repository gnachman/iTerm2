//
//  iTermSlowOperationGateway.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/20.
//

#import "iTermSlowOperationGateway.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermOpenDirectory.h"
#import "ProfileModel.h"
#import "pidinfo.h"
#include <stdatomic.h>

@interface iTermSlowOperationGateway()
@property (nonatomic, readwrite) BOOL ready;
@end

@implementation iTermSlowOperationGateway {
    NSXPCConnection *_connectionToService;
    NSTimeInterval _timeout;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static iTermSlowOperationGateway *instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _timeout = 0.5;
        [self connect];
        __weak __typeof(self) weakSelf = self;
        [_connectionToService.remoteObjectProxy handshakeWithReply:^{
            weakSelf.ready = YES;
        }];
    }
    return self;
}

- (void)didInvalidateConnection {
    self.ready = NO;
    [self connect];
}

- (void)connect {
    _connectionToService = [[NSXPCConnection alloc] initWithServiceName:@"com.iterm2.pidinfo"];
    _connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(pidinfoProtocol)];
    [_connectionToService resume];
    __weak __typeof(self) weakSelf;
    _connectionToService.invalidationHandler = ^{
        DLog(@"Invalidated");
        [weakSelf didInvalidateConnection];
    };
}

- (int)nextReqid {
    static int next;
    @synchronized(self) {
        return next++;
    }
}

- (void)checkIfDirectoryExists:(NSString *)directory
                    completion:(void (^)(BOOL))completion {
    if (!self.ready) {
        return;
    }
    [[_connectionToService remoteObjectProxy] checkIfDirectoryExists:directory
                                                           withReply:^(NSNumber * _Nullable exists) {
        if (!exists) {
            return;
        }
        completion(exists.boolValue);
    }];
}

- (void)exfiltrateEnvironmentVariableNamed:(NSString *)name
                                     shell:(NSString *)shell
                                completion:(void (^)(NSString * _Nonnull))completion {
    [[_connectionToService remoteObjectProxy] runShellScript:[NSString stringWithFormat:@"echo $%@", name]
                                                       shell:shell
                                                   withReply:^(NSData * _Nullable data,
                                                               NSData * _Nullable error,
                                                               int status) {
        completion(status == 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil);
    }];
}

- (void)asyncGetInfoForProcess:(int)pid
                        flavor:(int)flavor
                           arg:(uint64_t)arg
                    buffersize:(int)buffersize
                         reqid:(int)reqid
                    completion:(void (^)(int rc, NSData *buffer))completion {
    __block atomic_flag finished = ATOMIC_FLAG_INIT;
    [[_connectionToService remoteObjectProxy] getProcessInfoForProcessID:@(pid)
                                                                  flavor:@(flavor)
                                                                     arg:@(arg)
                                                                    size:@(buffersize)
                                                                   reqid:reqid
                                                               withReply:^(NSNumber *rc, NSData *buffer) {
        // Called on a private queue
        if (atomic_flag_test_and_set(&finished)) {
            DLog(@"Return early because already timed out for pid %@", @(pid));
            return;
        }
        DLog(@"Completed with rc=%@", rc);
        if (buffer.length != buffersize) {
            completion(-3, [NSData data]);
            return;
        }
        completion(rc.intValue, buffer);
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (atomic_flag_test_and_set(&finished)) {
            return;
        }
        DLog(@"Timed out");
        completion(-4, [NSData data]);
    });
}

@end
