//
//  iTermLSOF.m
//  iTerm2
//
//  Created by George Nachman on 11/8/16.
//
//

#import "iTermLSOF.h"

#import "DebugLogging.h"
#import "iTermSocketAddress.h"
#import "NSStringITerm.h"
#include <arpa/inet.h>
#include <libproc.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysctl.h>

int iTermProcPidInfoWrapper(int pid, int flavor, uint64_t arg, void *buffer, int buffersize) {
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.iterm2.proc_pidinfo", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block int rc;
    char *temp = malloc(MAX(1, buffersize));
    dispatch_async(queue, ^{
        rc = proc_pidinfo(pid, flavor, arg, temp, buffersize);
        dispatch_semaphore_signal(sema);
    });
    const NSTimeInterval timeoutSeconds = 0.5;
    int timedOut = dispatch_semaphore_wait(sema,
                                           dispatch_time(DISPATCH_TIME_NOW,
                                                         timeoutSeconds * NSEC_PER_SEC));
    if (timedOut) {
        DLog(@"proc_pidinfo timed out");
        dispatch_async(queue, ^{
            DLog(@"about to free temp buffer due to timeout");
            free(temp);
        });
        return -1;
    }

    DLog(@"proc_pidinfo finished in time with rc=%@", @(rc));
    memmove(buffer, temp, buffersize);
    free(temp);

    return rc;
}

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
            [argv addObject:[string stringWithEscapedShellCharactersIncludingNewlines:YES]];
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

+ (pid_t)processIDWithConnectionFromAddress:(iTermSocketAddress *)socketAddress {
    __block pid_t result = -1;
    [self enumerateProcesses:^(pid_t pid, BOOL *stop) {
        [self enumerateFileDescriptorsInfoInProcess:pid ofType:PROX_FDTYPE_SOCKET block:^(struct socket_fdinfo *fdInfo, BOOL *stop) {
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
            result = pid;
            *stop = YES;
        }];
    }];
    return result;
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

+ (void)enumerateFileDescriptorsInfoInProcess:(pid_t)pid ofType:(int)fdType block:(void(^)(struct socket_fdinfo *, BOOL *))block {
    int count = 0;
    struct proc_fileportinfo *filePortInfoArray = [self newFilePortsForProcess:pid count:&count];
    if (filePortInfoArray) {
        [self enumerateFileDescriptorsInfoInProcess:pid
                              withFilePortInfoArray:filePortInfoArray
                                             length:count
                                             ofType:fdType
                                              block:block];
        free(filePortInfoArray);
    } else {
        struct proc_fdinfo *fds = [self newFileDescriptorsForProcess:pid count:&count];
        if (fds) {
            [self enumerateFileDescriptorsInfoInProcess:pid
                                        withFDInfoArray:fds
                                                 length:count
                                                 ofType:fdType
                                                  block:block];
            free(fds);
            return;
        }
    }
}

+ (size_t)maximumNumberOfFileDescriptorsForProcess:(pid_t)pid {
    struct proc_taskallinfo tai;
    memset(&tai, 0, sizeof(tai));
    int numBytes = iTermProcPidInfoWrapper(pid, PROC_PIDTASKALLINFO, 0, &tai, sizeof(tai));
    if (numBytes <= 0) {
        return 0;
    }
    return tai.pbsd.pbi_nfiles;
}

+ (int)numberOfFilePortsForProcess:(pid_t)pid {
    int numBytes = iTermProcPidInfoWrapper(pid, PROC_PIDLISTFILEPORTS, 0, NULL, 0);
    if (numBytes <= 0) {
        return 0;
    }
    return numBytes / sizeof(struct proc_fileportinfo);
}

+ (struct proc_fdinfo *)newFileDescriptorsForProcess:(pid_t)pid count:(int *)count {
    size_t maxSize = [self maximumNumberOfFileDescriptorsForProcess:pid] * sizeof(struct proc_fdinfo);
    if (maxSize == 0) {
        return NULL;
    }
    struct proc_fdinfo *fds = malloc(maxSize);
    int numBytes = iTermProcPidInfoWrapper(pid, PROC_PIDLISTFDS, 0, fds, maxSize);
    if (numBytes <= 0) {
        free(fds);
        return NULL;
    }
    *count = numBytes / sizeof(struct proc_fdinfo);
    return fds;
}

+ (struct proc_fileportinfo *)newFilePortsForProcess:(pid_t)pid count:(int *)count {
    *count = [self numberOfFilePortsForProcess:pid];
    int size = *count * sizeof(struct proc_fileportinfo);
    if (size <= 0) {
        return NULL;
    }
    struct proc_fileportinfo *filePortInfoArray = malloc(size);
    int numBytes = iTermProcPidInfoWrapper(pid, PROC_PIDLISTFILEPORTS, 0, filePortInfoArray, size);
    if (numBytes <= 0) {
        free(filePortInfoArray);
        return NULL;
    }
    return filePortInfoArray;
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
    int *pids = (int *)malloc(bufferSize);
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
    int rc = iTermProcPidInfoWrapper(childPid,
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
    int numBytes;
    numBytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (numBytes <= 0) {
        return -1;
    }

    int* pids = (int*) malloc(numBytes + sizeof(int));
    // Save a magic int at the end to be sure that the buffer isn't overrun.
    const int PID_MAGIC = 0xdeadbeef;
    int magicIndex = numBytes/sizeof(int);
    pids[magicIndex] = PID_MAGIC;
    numBytes = proc_listpids(PROC_ALL_PIDS, 0, pids, numBytes);
    assert(pids[magicIndex] == PID_MAGIC);
    if (numBytes <= 0) {
        free(pids);
        return -1;
    }

    int numPids = numBytes / sizeof(int);

    long long oldestTime = 0;
    pid_t oldestPid = -1;
    for (int i = 0; i < numPids; ++i) {
        struct proc_taskallinfo taskAllInfo;
        int rc = iTermProcPidInfoWrapper(pids[i],
                                         PROC_PIDTASKALLINFO,
                                         0,
                                         &taskAllInfo,
                                         sizeof(taskAllInfo));
        if (rc <= 0) {
            continue;
        }

        pid_t ppid = taskAllInfo.pbsd.pbi_ppid;
        if (ppid == parentPid) {
            long long birthday = taskAllInfo.pbsd.pbi_start_tvsec * 1000000 + taskAllInfo.pbsd.pbi_start_tvusec;
            if (birthday < oldestTime || oldestTime == 0) {
                oldestTime = birthday;
                oldestPid = pids[i];
            }
        }
    }

    assert(pids[magicIndex] == PID_MAGIC);
    free(pids);
    return oldestPid;
}

+ (NSString *)workingDirectoryOfProcess:(pid_t)pid {
    DLog(@"Using OS magic to get the working directory");
    struct proc_vnodepathinfo vpi;
    int ret;

    // This only works if the child process is owned by our uid
    // Notably it seems to work (at least on 10.10) even if the process ID is
    // not owned by us.
    ret = iTermProcPidInfoWrapper(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof(vpi));
    if (ret <= 0) {
        // The child was probably owned by root (which is expected if it's
        // a login shell. Use the cwd of its oldest child instead.
        pid_t childPid = [self pidOfFirstChildOf:pid];
        if (childPid > 0) {
            ret = iTermProcPidInfoWrapper(childPid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof(vpi));
        }
    }
    if (ret <= 0) {
        // An error occurred
        DLog(@"Failed with error %d", ret);
        return nil;
    } else if (ret != sizeof(vpi)) {
        // Now this is very bad...
        DLog(@"Got a struct of the wrong size back");
        return nil;
    } else {
        // All is good
        NSString *dir = [NSString stringWithUTF8String:vpi.pvi_cdir.vip_path];
        DLog(@"Result: %@", dir);
        return dir;
    }
}

+ (void)asyncWorkingDirectoryOfProcess:(pid_t)pid block:(void (^)(NSString *pwd))block {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.iterm2.pwd", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(queue, ^{
        NSString *dir = [self workingDirectoryOfProcess:pid];
        dispatch_async(dispatch_get_main_queue(), ^{
            block(dir);
        });
    });
}

@end
