//
//  iTermPidInfoClient.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/11/20.
//

#import "iTermPidInfoClient.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermMalloc.h"
#import "iTermSlowOperationGateway.h"
#include <stdatomic.h>
#import <QuartzCore/QuartzCore.h>

@implementation iTermPidInfoClient {
    dispatch_queue_t _localQueue;
    dispatch_semaphore_t _sema;
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
        // The local queue will be used while waiting for the XPC job to start.
        _localQueue = dispatch_queue_create("com.iterm2.pidinfo", DISPATCH_QUEUE_CONCURRENT);
        // Don't let more than this many threads get wedged.
        _sema = dispatch_semaphore_create(32);
        _timeout = 0.5;
    }
    return self;
}

- (void)localGetPidInfoForProcessID:(int)pid
                            flavor:(int)flavor
                               arg:(uint64_t)arg
                        buffersize:(int)bufferSize
                         completion:(void (^)(int rc, NSData *buffer))completion {
    if (bufferSize > 1024 * 1024 || bufferSize < 0) {
        completion(-2, [NSData data]);
        return;
    }
    NSMutableData *result = [NSMutableData dataWithLength:bufferSize];

    __block atomic_flag finished = ATOMIC_FLAG_INIT;
    const long waitResult = dispatch_semaphore_wait(_sema, DISPATCH_TIME_NOW);
    if (waitResult) {
        DLog(@"semaphore_wait failed, return error");
        completion(-5, [NSData data]);
        return;
    }
    dispatch_async(_localQueue, ^{
        const int rc = proc_pidinfo(pid,
                                    flavor,
                                    arg,
                                    (bufferSize > 0) ? result.mutableBytes : NULL,
                                    bufferSize);
        dispatch_semaphore_signal(self->_sema);
        if (atomic_flag_test_and_set(&finished)) {
            return;
        }
        DLog(@"Completed");
        completion(rc, result);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (atomic_flag_test_and_set(&finished)) {
            return;
        }
        DLog(@"Timed out");
        completion(-4, [NSData data]);
    });
}

- (BOOL)ready {
    return [[iTermSlowOperationGateway sharedInstance] ready];
}

- (int)nextReqid {
    return [[iTermSlowOperationGateway sharedInstance] nextReqid];
}

- (void)asyncGetInfoForProcess:(int)pid
                        flavor:(int)flavor
                           arg:(uint64_t)arg
                    buffersize:(int)buffersize
                         reqid:(int)reqid
                    completion:(void (^)(int rc, NSData *buffer))completion {
    if (!self.ready) {
        DLog(@"Not ready");
        [self localGetPidInfoForProcessID:pid flavor:flavor arg:arg buffersize:buffersize completion:completion];
        return;
    }
    DLog(@"Ready");
    [[iTermSlowOperationGateway sharedInstance] asyncGetInfoForProcess:pid
                                                                flavor:flavor
                                                                   arg:arg
                                                            buffersize:buffersize
                                                                 reqid:reqid
                                                            completion:completion];
}

- (void)getMaximumNumberOfFileDescriptorsForProcess:(pid_t)pid
                                         completion:(void (^)(size_t count))completion {
    [self asyncGetInfoForProcess:pid
                          flavor:PROC_PIDTASKALLINFO
                             arg:0
                      buffersize:sizeof(struct proc_taskallinfo)
                           reqid:[self nextReqid]
                      completion:^(int rc, NSData * _Nonnull buffer) {
        DLog(@"get task info for pid %@ finished with rc %@", @(pid), @(rc));
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
        DLog(@"list fds finished with rc %@", @(rc));
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
        DLog(@"getMaximumNumberOfFileDescriptorsForProcess finished for %@ with %@", @(pid), @(count));
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
        DLog(@"Get number of file ports for pid %@ finished with rc %@", @(pid), @(rc));
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
        DLog(@"getNumberOfFilePortsInProcess:%@ finished with count=%@", @(pid), @(count));
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
            DLog(@"List file ports for pid %@ finished with rc %@", @(pid), @(rc));
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
        DLog(@"Get path info for pid %@ finished with rc %@", @(pid), @(ret));
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
