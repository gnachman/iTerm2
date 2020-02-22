//
//  iTermLSOF.m
//  iTerm2
//
//  Created by George Nachman on 11/8/16.
//
//

#import "iTermLSOF.h"

#import "DebugLogging.h"
#import "iTermMalloc.h"
#import "iTermPidInfoClient.h"
#import "iTermProcessCache.h"
#import "iTermSocketAddress.h"
#import "iTermSyntheticConfParser.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#include <arpa/inet.h>
#include <libproc.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysctl.h>

@implementation iTermLSOF {
    iTermSocketAddress *_socketAddress;
}

+ (int)maximumLengthOfProcargs {
    int mib[3];
    int argmax;
    size_t syssize;

    mib[0] = CTL_KERN;
    mib[1] = KERN_ARGMAX;

    syssize = sizeof(argmax);
    if (sysctl(mib, 2, &argmax, &syssize, NULL, 0) == -1) {
        return -1;
    } else {
        return argmax;
    }
}

+ (char *)procargsForProcess:(pid_t)pid {
    int argmax = [self maximumLengthOfProcargs];
    if (argmax < 0) {
        return nil;
    }

    NSMutableData *procargsData = [NSMutableData dataWithLength:argmax];
    char *procargs = procargsData.mutableBytes;
    int mib[3] = { CTL_KERN, KERN_PROCARGS2, pid };
    size_t syssize = argmax;
    if (sysctl(mib, 3, procargs, &syssize, NULL, 0) == -1) {
        return nil;
    }
    return procargs;
}

+ (NSString *)commandForProcess:(pid_t)pid execName:(NSString **)execName {
    int argmax = [self maximumLengthOfProcargs];
    char *procargs = [self procargsForProcess:pid];

    // Consume argc
    size_t offset = 0;
    int nargs;
    if (procargs == nil) {
        return nil;
    }
    memmove(&nargs, procargs + offset, sizeof(int));
    offset += sizeof(int);

    // Skip exec_path
    char *exec_path = procargs + offset;
    while (offset < argmax && procargs[offset] != 0) {
        ++offset;
    }

    // Skip trailing nulls
    while (offset < argmax && procargs[offset] == 0) {
        ++offset;
    }
    if (offset == argmax) {
        return nil;
    }
    if (execName) {
        *execName = [NSString stringWithUTF8String:exec_path];
    }

    // Pull out null terminated argv components
    NSMutableArray<NSString *> *argv = [NSMutableArray array];
    char *start = procargs + offset;
    while (offset < argmax && argv.count < nargs) {
        if (procargs[offset] == 0) {
            NSString *string = [NSString stringWithUTF8String:start];
            [argv addObject:[string stringWithEscapedShellCharactersIncludingNewlines:YES] ?: @""];
            start = procargs + offset + 1;
        }
        offset++;
    }

    if (argv.count == 0) {
        return @"";
    }
    NSString *command = argv[0];
    NSRange lastSlash = [command rangeOfString:@"/" options:NSBackwardsSearch];
    if (lastSlash.location != NSNotFound) {
        argv[0] = [command substringFromIndex:lastSlash.location + 1];
    }
    return [argv componentsJoinedByString:@" "];
}

+ (void)getProcessIDsWithConnectionFromAddress:(iTermSocketAddress *)socketAddress
                                         queue:(dispatch_queue_t)queue
                                    completion:(void (^)(NSArray<NSNumber *> *))completion {
    NSMutableArray<NSNumber *> *results = [NSMutableArray array];

    dispatch_group_t group = dispatch_group_create();
    [self enumerateProcesses:^(pid_t pid, BOOL *stop) {
        [self enumerateFileDescriptorsInfoInProcess:pid
                                             ofType:PROX_FDTYPE_SOCKET
                                              group:group
                                              queue:queue
                                              block:^(struct socket_fdinfo *fdInfo,
                                                      BOOL *stop) {
            int family = [self addressFamilyForFDInfo:fdInfo];
            if (family != AF_INET && family != AF_INET6) {
                return;
            }
            struct sockaddr_storage local = [self localSocketAddressInFDInfo:fdInfo];
            if (![socketAddress isEqualToSockAddr:(struct sockaddr *)&local]) {
                return;
            }
            struct sockaddr_storage foreign = [self foreignSocketAddressInFDInfo:fdInfo];
            if (![iTermSocketAddress socketAddressIsLoopback:(struct sockaddr *)&foreign]) {
                return;
            }
            [results addObject:@(pid)];
        }];
    }];
    dispatch_group_notify(group, queue, ^{
        completion(results);
    });
}

+ (void)enumerateProcesses:(void(^)(pid_t, BOOL*))block {
    BOOL stop = NO;
    for (NSNumber *pidNumber in [self allPids]) {
        block(pidNumber.intValue, &stop);
        if (stop) {
            break;
        }
    }
}

+ (void)enumerateFileDescriptorsInfoInProcess:(pid_t)pid
                        withFilePortInfoArray:(struct proc_fileportinfo *)filePortInfoArray
                                       length:(int)count
                                       ofType:(int)fdType
                                        block:(void(^)(struct socket_fdinfo *, BOOL *))block {
    BOOL stop = NO;
    for (int j = 0; j < count; j++) {
        struct proc_fileportinfo *filePortInfo = &filePortInfoArray[j];
        if (filePortInfo->proc_fdtype == fdType) {
            struct socket_fdinfo socketFileDescriptorInfo;
            int numBytes = proc_pidfileportinfo(pid,
                                                filePortInfo->proc_fileport,
                                                PROC_PIDFILEPORTSOCKETINFO,
                                                &socketFileDescriptorInfo,
                                                sizeof(socketFileDescriptorInfo));
            if (numBytes > 0) {
                block(&socketFileDescriptorInfo, &stop);
                if (stop) {
                    return;
                }
            }
        }
    }
}

+ (void)enumerateFileDescriptorsInfoInProcess:(pid_t)pid
                              withFDInfoArray:(struct proc_fdinfo *)fds
                                       length:(int)count
                                       ofType:(int)fdType
                                        block:(void(^)(struct socket_fdinfo *, BOOL *))block {
    BOOL stop = NO;
    for (int j = 0; j < count; j++) {
        struct proc_fdinfo *fdinfo = &fds[j];
        if (fdinfo->proc_fdtype == PROX_FDTYPE_SOCKET) {
            int fd = fdinfo->proc_fd;
            struct socket_fdinfo socketFileDescriptorInfo;
            int numBytes = proc_pidfdinfo(pid,
                                          fd,
                                          PROC_PIDFDSOCKETINFO,
                                          &socketFileDescriptorInfo,
                                          sizeof(socketFileDescriptorInfo));
            if (numBytes > 0) {
                block(&socketFileDescriptorInfo, &stop);
                if (stop) {
                    return;
                }
            }
        }
    }
}

+ (void)enumerateFileDescriptorsInfoInProcess:(pid_t)pid
                                       ofType:(int)fdType
                                        group:(dispatch_group_t)group
                                        queue:(dispatch_queue_t)queue
                                        block:(void(^)(struct socket_fdinfo *, BOOL *))block {
    dispatch_group_enter(group);
    [[iTermPidInfoClient sharedInstance] getPortsInProcess:pid queue:queue completion:^(int count,
                                                                                        struct proc_fileportinfo * _Nonnull filePortInfoArray) {
        if (filePortInfoArray) {
            [self enumerateFileDescriptorsInfoInProcess:pid
                                  withFilePortInfoArray:filePortInfoArray
                                                 length:count
                                                 ofType:fdType
                                                  block:block];
            free(filePortInfoArray);
            dispatch_group_leave(group);
            return;
        }

        [[iTermPidInfoClient sharedInstance] getFileDescriptorsForProcess:pid queue:queue completion:^(int count, struct proc_fdinfo * _Nonnull fds) {
            if (!fds) {
                dispatch_group_leave(group);
                return;
            }
            [self enumerateFileDescriptorsInfoInProcess:pid
                                        withFDInfoArray:fds
                                                 length:count
                                                 ofType:fdType
                                                  block:block];
            free(fds);
            dispatch_group_leave(group);
        }];
    }];
}

+ (BOOL)fdInfoIsTCPSocket:(struct socket_fdinfo *)fdInfo {
    int addressFamily = fdInfo->psi.soi_family;
    if (addressFamily != AF_INET && addressFamily != AF_INET6) {
        return NO;
    }

    if (fdInfo->psi.soi_kind != SOCKINFO_TCP) {
        return NO;
    }
    if (fdInfo->psi.soi_protocol != IPPROTO_TCP) {
        return NO;
    }

    return YES;
}

+ (int)addressFamilyForFDInfo:(struct socket_fdinfo *)fdInfo {
    int addressFamily;
    if (fdInfo->psi.soi_family == AF_INET6 && (fdInfo->psi.soi_proto.pri_tcp.tcpsi_ini.insi_vflag & INI_IPV4)) {
        addressFamily = AF_INET;
    } else {
        addressFamily = fdInfo->psi.soi_family;
    }
    return addressFamily;
}

+ (struct sockaddr_storage)localSocketAddressInFDInfo:(struct socket_fdinfo *)fdInfo {
    int addressFamily = [self addressFamilyForFDInfo:fdInfo];
    int localPort = fdInfo->psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport;
    struct sockaddr_storage storage = { 0 };
    storage.ss_family = addressFamily;

    switch (addressFamily) {
        case AF_INET: {
            struct sockaddr_in *result = (struct sockaddr_in *)&storage;
            result->sin_len = sizeof(struct sockaddr_in);
            result->sin_port = localPort;
            result->sin_addr = fdInfo->psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.ina_46.i46a_addr4;
            break;
        }

        case AF_INET6: {
            struct sockaddr_in6 *result = (struct sockaddr_in6 *)&storage;
            result->sin6_len = sizeof(struct sockaddr_in);
            result->sin6_family = addressFamily;
            result->sin6_port = localPort;
            result->sin6_addr = fdInfo->psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.ina_6;
            break;
        }

        default:
            assert(false);
    }
    return storage;
}

+ (struct sockaddr_storage)foreignSocketAddressInFDInfo:(struct socket_fdinfo *)fdInfo {
    int addressFamily = [self addressFamilyForFDInfo:fdInfo];
    int foreignPort = fdInfo->psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport;
    struct sockaddr_storage storage = { 0 };
    storage.ss_family = addressFamily;

    switch (addressFamily) {
        case AF_INET: {
            struct sockaddr_in *result = (struct sockaddr_in *)&storage;
            result->sin_len = sizeof(struct sockaddr_in);
            result->sin_port = foreignPort;
            result->sin_addr = fdInfo->psi.soi_proto.pri_tcp.tcpsi_ini.insi_faddr.ina_46.i46a_addr4;
            break;
        }

        case AF_INET6: {
            struct sockaddr_in6 *result = (struct sockaddr_in6 *)&storage;
            result->sin6_len = sizeof(struct sockaddr_in);
            result->sin6_family = addressFamily;
            result->sin6_port = foreignPort;
            result->sin6_addr = fdInfo->psi.soi_proto.pri_tcp.tcpsi_ini.insi_faddr.ina_6;
            break;
        }

        default:
            assert(false);
    }
    return storage;
}

+ (NSArray<NSNumber *> *)allPids {
    const int bufferSize = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bufferSize <= 0) {
        return @[];
    }

    // Put all the pids of running jobs in the pids array.
    int *pids = (int *)iTermMalloc(bufferSize);
    const int bytesReturned = proc_listpids(PROC_ALL_PIDS, 0, pids, bufferSize);
    if (bytesReturned <= 0) {
        free(pids);
        return @[];
    }

    const int numPids = bytesReturned / sizeof(int);

    NSMutableArray<NSNumber *> *pidsArray = [NSMutableArray array];
    for (int i = 0; i < numPids; i++) {
        [pidsArray addObject:@(pids[i])];
    }

    free(pids);

    return pidsArray;
}

// Returns 0 on failure.
+ (pid_t)ppidForPid:(pid_t)childPid {
    struct proc_bsdshortinfo taskShortInfo;
    memset(&taskShortInfo, 0, sizeof(taskShortInfo));
    int rc = proc_pidinfo(childPid,
                          PROC_PIDT_SHORTBSDINFO,
                          0,
                          &taskShortInfo,
                          sizeof(taskShortInfo));
    if (rc <= 0) {
        return 0;
    } else {
        return taskShortInfo.pbsi_ppid;
    }
}

// Use sysctl magic to get the name of a process and whether it is controlling
// the tty. This code was adapted from ps, here:
// http://opensource.apple.com/source/adv_cmds/adv_cmds-138.1/ps/
//
// The equivalent in ps would be:
//   ps -aef -o stat
// If a + occurs in the STAT column then it is considered to be a foreground
// job.
+ (NSString *)nameOfProcessWithPid:(pid_t)thePid isForeground:(BOOL *)isForeground {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, thePid };
    struct kinfo_proc kp;
    size_t bufSize = sizeof(kp);

    kp.kp_proc.p_comm[0] = 0;
    if (sysctl(mib, 4, &kp, &bufSize, NULL, 0) < 0) {
        return nil;
    }

    // has a controlling terminal and
    // process group id = tty process group id
    if (isForeground) {
        *isForeground = ((kp.kp_proc.p_flag & P_CONTROLT) &&
                         kp.kp_eproc.e_pgid == kp.kp_eproc.e_tpgid);
    }

    if (kp.kp_proc.p_comm[0]) {
        return [NSString stringWithUTF8String:kp.kp_proc.p_comm];
    } else {
        return nil;
    }
}

// This is a stunningly brittle hack. Find the child of parentPid with the
// oldest start time. This relies on undocumented APIs, but short of forking
// ps, I can't see another way to do it.
+ (pid_t)pidOfFirstChildOf:(pid_t)parentPid {
    DLog(@"Want to find first child of process %@", @(parentPid));
    iTermProcessInfo *parentInfo = [[iTermProcessCache sharedInstance] processInfoForPid:parentPid];
    if (!parentInfo) {
        DLog(@"Forcing a synchronous update of the process cache");
        [[iTermProcessCache sharedInstance] updateSynchronously];
        parentInfo = [[iTermProcessCache sharedInstance] processInfoForPid:parentPid];
    }
    if (!parentInfo) {
        DLog(@"No parent with pid %@", @(parentPid));
        return -1;
    }
    iTermProcessInfo *firstChild = [parentInfo.children minWithBlock:^NSComparisonResult(iTermProcessInfo *obj1, iTermProcessInfo *obj2) {
        return [obj1.startTime compare:obj2.startTime];
    }];
    if (!firstChild) {
        DLog(@"Process is childless");
        return -1;
    }
    return firstChild.processID;
}

+ (NSDate *)startTimeForProcess:(pid_t)pid {
    DLog(@"Want start time for %@", @(pid));
    struct proc_taskallinfo taskAllInfo;
    const int rc = proc_pidinfo(pid,
                                PROC_PIDTASKALLINFO,
                                0,
                                &taskAllInfo,
                                sizeof(taskAllInfo));
    if (rc <= 0) {
        DLog(@"Failed to get task all info");
        return nil;
    }

    double birthday = taskAllInfo.pbsd.pbi_start_tvsec;
    birthday += taskAllInfo.pbsd.pbi_start_tvusec / 1000000.0;
    return [NSDate dateWithTimeIntervalSince1970:birthday];
}

+ (NSString *)workingDirectoryOfProcess:(pid_t)pid {
    DLog(@"Want working directory of process %@ - SYNCHRONOUS METHOD!", @(pid));
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.iterm2.pwd", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    __block NSString *result = nil;
    [self asyncWorkingDirectoryOfProcess:pid queue:queue block:^(NSString *pwd) {
        result = pwd;
        dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW,
                                             0.5 * NSEC_PER_SEC));
    DLog(@"Result is %@", result);
    return result;
}

+ (void)asyncWorkingDirectoryOfProcess:(pid_t)pid
                                 queue:(dispatch_queue_t)queue
                                 block:(void (^)(NSString *pwd))block {
    [self asyncWorkingDirectoryOfProcess:pid
                             canFallBack:YES
                                   queue:queue
                                   block:block];
}

+ (void)asyncWorkingDirectoryOfProcess:(pid_t)pid
                           canFallBack:(BOOL)canFallBack
                                 queue:(dispatch_queue_t)queue
                                 block:(void (^)(NSString *pwd))block {
    DLog(@"Want working directory of %@", @(pid));
    [[iTermPidInfoClient sharedInstance] getWorkingDirectoryOfProcessWithID:pid
                                                                      queue:queue
                                                                 completion:^(NSString *rawDir) {
        if (!rawDir) {
            DLog(@"Failed to get working directory of %@", @(pid));
        }
        if (!rawDir && canFallBack) {
            DLog(@"Will attempt fallback");
            pid_t childPid = [self pidOfFirstChildOf:pid];
            if (childPid <= 0) {
                DLog(@"Failed to get first child. Giving up.");
                block(nil);
                return;
            }
            // pid might be owned by root. Try again with its eldest child.
            DLog(@"Try again with eldest child");
            [self asyncWorkingDirectoryOfProcess:childPid
                                     canFallBack:NO
                                           queue:queue
                                           block:block];
            return;
        }
        if (!rawDir) {
            DLog(@"Failing");
            block(nil);
            return;
        }
        if (@available(macOS 10.15, *)) {
            NSString *dir = [[iTermSyntheticConfParser sharedInstance] pathByReplacingPrefixWithSyntheticRoot:rawDir];
            DLog(@"Result: %@ -> %@", rawDir, dir);
            block(dir);
            return;
        }
        // pre-10.15 code path - no synthetics existed
        DLog(@"Result: %@", rawDir);
        block(rawDir);
    }];
}

@end
