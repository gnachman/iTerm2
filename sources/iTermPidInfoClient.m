//
//  iTermPidInfoClient.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/11/20.
//

#import "iTermPidInfoClient.h"

#import "DebugLogging.h"
#import "iTermMalloc.h"
#import "pidinfo.h"
#import <QuartzCore/QuartzCore.h>

@implementation iTermPidInfoClient {
    NSXPCConnection *_connectionToService;
    NSTimeInterval _timeout;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static iTermPidInfoClient *instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        // Initialize a big timeout because it can take some time to launch the xpc job.
        _timeout = 10;
        [self connect];
        [_connectionToService.remoteObjectProxy handshakeWithReply:^{
            self->_timeout = 0.5;
        }];
    }
    return self;
}

- (void)didInvalidateConnection {
    [self connect];
}

- (void)connect {
    _connectionToService = [[NSXPCConnection alloc] initWithServiceName:@"com.iterm2.pidinfo"];
    _connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(pidinfoProtocol)];
    [_connectionToService resume];
    __weak __typeof(self) weakSelf;
    _connectionToService.invalidationHandler = ^{
        NSLog(@"Invalidated");
        [weakSelf didInvalidateConnection];
    };
}

- (int)nextReqid {
    static int next;
    @synchronized(self) {
        return next++;
    }
}

- (int)getPidInfoForProcessID:(int)pid
                       flavor:(int)flavor
                          arg:(uint64_t)arg
                       buffer:(void *)callerBuffer
                   buffersize:(int)bufferSize {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    __block NSData *data;
    __block int result;
    const CFTimeInterval startTime = CACurrentMediaTime();
    __block BOOL diagnose = NO;
    const int reqid = [self nextReqid];
    [self asyncGetInfoForProcess:pid flavor:flavor arg:arg buffersize:bufferSize reqid:reqid completion:^(int rc, NSData * _Nonnull buffer) {
        const CFTimeInterval endTime = CACurrentMediaTime();
//        NSLog(@"pidinfo %d rc=%@ dt=%dms", reqid, @(rc), (int)((endTime-startTime) * 1000));
        result = rc;
        data = [buffer copy];
        if (diagnose) {
            const CFTimeInterval endTime = CACurrentMediaTime();
            NSLog(@"pidinfo %d Finally completed after %dms", reqid, (int)((endTime-startTime) * 1000));
        }
        dispatch_group_leave(group);
    }];
    const int timedOut = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW,
                                                                  (int64_t)(_timeout * NSEC_PER_SEC)));
    const CFTimeInterval endTime = CACurrentMediaTime();
    if (timedOut) {
        diagnose = YES;
        NSLog(@"pidinfo %d Timed out after %dms", reqid, (int)((endTime-startTime) * 1000));
        return -4;
    } else if (result >= 0) {
//        NSLog(@"pidinfo %d good after %dms", reqid, (int)((endTime-startTime) * 1000));
        memmove(callerBuffer, data.bytes, MIN(bufferSize, data.length));
    } else {
        NSLog(@"pidinfo %d error after %dms", reqid, (int)((endTime-startTime) * 1000));
    }
    return result;
}

- (void)asyncGetInfoForProcess:(int)pid
                        flavor:(int)flavor
                           arg:(uint64_t)arg
                    buffersize:(int)buffersize
                         reqid:(int)reqid
                    completion:(void (^)(int rc, NSData *buffer))completion {
    [[_connectionToService remoteObjectProxy] getProcessInfoForProcessID:@(pid)
                                                                  flavor:@(flavor)
                                                                     arg:@(arg)
                                                                    size:@(buffersize)
                                                                   reqid:reqid
                                                               withReply:^(NSNumber *rc, NSData *buffer) {
        // Called on a private queue
        if (buffer.length != buffersize) {
            completion(-3, [NSData data]);
            return;
        }
        completion(rc.intValue, buffer);
    }];
}

- (void)getMaximumNumberOfFileDescriptorsForProcess:(pid_t)pid
                                         completion:(void (^)(size_t count))completion {
    [self asyncGetInfoForProcess:pid
                          flavor:PROC_PIDTASKALLINFO
                             arg:0
                      buffersize:sizeof(struct proc_taskallinfo)
                           reqid:[self nextReqid]
                      completion:^(int rc, NSData * _Nonnull buffer) {
        struct proc_taskallinfo tai;
        if (rc <= 0 || buffer.length != sizeof(tai)) {
            completion(0);
            return;
        }
        memmove(&tai, buffer.bytes, MIN(buffer.length, sizeof(tai)));
        completion(tai.pbsd.pbi_nfiles);
    }];
}

- (void)getFileDescriptorsForProcess:(pid_t)pid
                               count:(size_t)count
                               queue:(dispatch_queue_t)queue
                          completion:(void (^)(int count, struct proc_fdinfo *fds))completion {
    const size_t maxSize = count * sizeof(struct proc_fdinfo);
    if (maxSize > 1024 * 1024) {
        dispatch_async(queue, ^{
            completion(0, NULL);
        });
        return;
    }
    struct proc_fdinfo *fds = iTermMalloc(maxSize);
    [self asyncGetInfoForProcess:pid flavor:PROC_PIDLISTFDS arg:0 buffersize:maxSize reqid:[self nextReqid] completion:^(int rc, NSData * _Nonnull buffer) {
        if (rc <= 0) {
            free(fds);
            dispatch_async(queue, ^{
                completion(0, NULL);
            });
            return;
        }
        memmove(fds, buffer.bytes, MIN(maxSize, buffer.length));
        dispatch_async(queue, ^{
            completion(rc / sizeof(struct proc_fdinfo), fds);
        });
    }];
}

- (void)getFileDescriptorsForProcess:(pid_t)pid
                               queue:(dispatch_queue_t)queue
                          completion:(void (^)(int count, struct proc_fdinfo *fds))completion {
    [self getMaximumNumberOfFileDescriptorsForProcess:pid completion:^(size_t count) {
        if (count == 0) {
            dispatch_async(queue, ^{
                completion(0, NULL);
            });
            return;
        }
        [self getFileDescriptorsForProcess:pid count:count queue:queue completion:completion];
    }];
}

- (void)getNumberOfFilePortsInProcess:(pid_t)pid
                                queue:(dispatch_queue_t)queue
                           completion:(void (^)(int count))completion {
    [self asyncGetInfoForProcess:pid flavor:PROC_PIDLISTFILEPORTS arg:0 buffersize:0 reqid:[self nextReqid] completion:^(int rc, NSData * _Nonnull buffer) {
        if (rc <= 0) {
            dispatch_async(queue, ^{
                completion(0);
            });
            return;
        }
        dispatch_async(queue, ^{
            completion(rc / sizeof(struct proc_fileportinfo));
        });
    }];
}

- (void)getPortsInProcess:(pid_t)pid
                    queue:(dispatch_queue_t)queue
               completion:(void (^)(int count, struct proc_fileportinfo *fds))completion {
    [self getNumberOfFilePortsInProcess:pid queue:queue completion:^(int count) {
        const int size = count * sizeof(struct proc_fileportinfo);
        if (size <= 0) {
            dispatch_async(queue, ^{
                completion(0, NULL);
            });
            return;
        }
        [self asyncGetInfoForProcess:pid
                              flavor:PROC_PIDLISTFILEPORTS
                                 arg:0
                          buffersize:size
                               reqid:[self nextReqid]
                          completion:^(int rc, NSData * _Nonnull buffer) {
            if (rc <= 0) {
                dispatch_async(queue, ^{
                    completion(0, NULL);
                });
                return;
            }
            struct proc_fileportinfo *filePortInfoArray = iTermMalloc(size);
            memmove(filePortInfoArray, buffer.bytes, MIN(size, buffer.length));
            dispatch_async(queue, ^{
                completion(count, filePortInfoArray);
            });
        }];
    }];
}

- (void)getWorkingDirectoryOfProcessWithID:(pid_t)pid
                                     queue:(dispatch_queue_t)queue
                                completion:(void (^)(NSString *rawDir))completion {
    [self asyncGetInfoForProcess:pid
                          flavor:PROC_PIDVNODEPATHINFO
                             arg:0
                      buffersize:sizeof(struct proc_vnodepathinfo)
                           reqid:[self nextReqid]
                      completion:^(int ret, NSData * _Nonnull buffer) {
        if (ret <= 0) {
            // An error occurred
            DLog(@"Failed with error %d", ret);
            dispatch_async(queue, ^{
                completion(nil);
            });
            return;
        }
        struct proc_vnodepathinfo vpi;
        if (ret != sizeof(vpi)) {
            // Now this is very bad...
            DLog(@"Got a struct of the wrong size back");
            dispatch_async(queue, ^{
                completion(nil);
            });
            return;
        }
        memmove(&vpi, buffer.bytes, MIN(sizeof(vpi), buffer.length));
        // All is good
        NSString *rawDir = [NSString stringWithUTF8String:vpi.pvi_cdir.vip_path];
        dispatch_async(queue, ^{
            completion(rawDir);
        });
    }];
}

@end
