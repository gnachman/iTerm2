//
//  iTermLSOF.m
//  iTerm2
//
//  Created by George Nachman on 11/8/16.
//
//

#import "iTermLSOF.h"

#import "iTermSocketAddress.h"
#import "ProcessCache.h"
#include <arpa/inet.h>
#include <libproc.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysctl.h>

int iTermProcPidInfoWrapper(int pid, int flavor, uint64_t arg,  void *buffer, int buffersize) {
    return proc_pidinfo(pid, flavor, arg, buffer, buffersize);
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
            [argv addObject:string];
            start = procargs + offset + 1;
        }
        offset++;
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
    for (NSNumber *pidNumber in [ProcessCache allPids]) {
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

@end
