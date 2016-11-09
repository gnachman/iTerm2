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

#define IPv6_2_IPv4(v6) (((uint8_t *)((struct in6_addr *)v6)->s6_addr)+12)

@implementation iTermLSOF {
    iTermSocketAddress *_socketAddress;
}

+ (pid_t)processIDWithConnectionFromAddress:(iTermSocketAddress *)socketAddress {
    iTermLSOF *lsof = [[self alloc] initWithSocketAddress:socketAddress];
    return [lsof processId];
}

- (instancetype)initWithSocketAddress:(iTermSocketAddress *)socketAddress {
    self = [super init];
    if (self) {
        _socketAddress = socketAddress;
    }
    return self;
}

- (pid_t)processId {
    if (!_socketAddress.isLoopback) {
        return -1;
    }

    for (NSNumber *pidNumber in [ProcessCache allPids]) {
        if ([self checkProcess:pidNumber.intValue]) {
            return pidNumber.intValue;
        }
    }

    return -1;
}

- (BOOL)checkProcess:(pid_t)pid {
    NSLog(@"Check pid %d", pid);
    int count = 0;
    struct proc_fileportinfo *filePortInfoArray = [self newFilePortsForProcess:pid count:&count];
    if (filePortInfoArray) {
        NSLog(@"Using port info");
        for (int j = 0; j < count; j++) {
            struct proc_fileportinfo *filePortInfo = &filePortInfoArray[j];
            if (filePortInfo->proc_fdtype == PROX_FDTYPE_SOCKET) {
                struct socket_fdinfo socketFileDescriptorInfo;
                int numBytes = proc_pidfileportinfo(pid,
                                                    filePortInfo->proc_fileport,
                                                    PROC_PIDFILEPORTSOCKETINFO,
                                                    &socketFileDescriptorInfo,
                                                    sizeof(socketFileDescriptorInfo));
                if (numBytes > 0) {
                    if ([self checkSocketFileDescriptorInfo:socketFileDescriptorInfo process:pid]) {
                        return YES;
                    }
                }
            }
        }
    } else {
        NSLog(@"Trying fds");
        struct proc_fdinfo *fds = [self newFileDescriptorsForProcess:pid count:&count];
        if (!fds) {
            return NO;
        }
        NSLog(@"Using fds. Have %d of them", count);
        for (int j = 0; j < count; j++) {
            struct proc_fdinfo *fdinfo = &fds[j];
            if (fdinfo->proc_fdtype == PROX_FDTYPE_SOCKET) {
                NSLog(@"fd index %d is a socket. proc_fd=%d", j, fdinfo->proc_fd);
                int fd = fdinfo->proc_fd;
                struct socket_fdinfo socketFileDescriptorInfo;
                int numBytes = proc_pidfdinfo(pid,
                                              fd,
                                              PROC_PIDFDSOCKETINFO,
                                              &socketFileDescriptorInfo,
                                              sizeof(socketFileDescriptorInfo));
                if (numBytes > 0) {
                    if ([self checkSocketFileDescriptorInfo:socketFileDescriptorInfo process:pid]) {
                        return YES;
                    }
                }
            }
        }
    }
    return NO;
}

- (size_t)numberOfFileDescriptorsForProcess:(pid_t)pid {
    struct proc_taskallinfo tai;
    memset(&tai, 0, sizeof(tai));
    int numBytes = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &tai, sizeof(tai));
    if (numBytes <= 0) {
        return 0;
    }
    return tai.pbsd.pbi_nfiles;
}

- (int)numberOfFilePortsForProcess:(pid_t)pid {
    int numBytes = proc_pidinfo(pid, PROC_PIDLISTFILEPORTS, 0, NULL, 0);
    if (numBytes <= 0) {
        return 0;
    }
    return numBytes / sizeof(struct proc_fileportinfo);
}

- (struct proc_fdinfo *)newFileDescriptorsForProcess:(pid_t)pid count:(int *)count {
    *count = [self numberOfFileDescriptorsForProcess:pid];
    size_t maxSize = *count * sizeof(struct proc_fdinfo);
    if (maxSize == 0) {
        return NULL;
    }
    struct proc_fdinfo *fds = malloc(maxSize);
    int numBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, maxSize);
    if (numBytes <= 0) {
        free(fds);
        return NULL;
    }
    *count = numBytes / sizeof(struct proc_fdinfo);
    return fds;
}

- (struct proc_fileportinfo *)newFilePortsForProcess:(pid_t)pid count:(int *)count {
    *count = [self numberOfFilePortsForProcess:pid];
    int size = *count * sizeof(struct proc_fileportinfo);
    if (size <= 0) {
        return NULL;
    }
    struct proc_fileportinfo *filePortInfoArray = malloc(size);
    int numBytes = proc_pidinfo(pid, PROC_PIDLISTFILEPORTS, 0, filePortInfoArray, size);
    if (numBytes <= 0) {
        free(filePortInfoArray);
        return NULL;
    }
    return filePortInfoArray;
}

- (BOOL)checkSocketFileDescriptorInfo:(struct socket_fdinfo)socketFileDescriptorInfo
                              process:(pid_t)pid {
    int addressFamily = socketFileDescriptorInfo.psi.soi_family;
    if (addressFamily != AF_INET && addressFamily != AF_INET6) {
        return NO;
    }

    if (socketFileDescriptorInfo.psi.soi_kind != SOCKINFO_TCP) {
        return NO;
    }
    if (socketFileDescriptorInfo.psi.soi_protocol != IPPROTO_TCP) {
        return NO;
    }

    void *localAddress = &socketFileDescriptorInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.ina_6;
    void *foreignAddress = &socketFileDescriptorInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_faddr.ina_6;
    int localPort = ntohs(socketFileDescriptorInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport);
    int foreignPort = ntohs(socketFileDescriptorInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_fport);
    NSLog(@"%d->%d pid=%d", localPort, foreignPort, pid);
    if (IN6_IS_ADDR_UNSPECIFIED((struct in6_addr *)foreignAddress) && foreignPort == 0) {
        foreignAddress = NULL;
    }

    if (socketFileDescriptorInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_vflag & INI_IPV4) {
        addressFamily = AF_INET;
        if (localAddress) {
            localAddress = IPv6_2_IPv4(localAddress);
        }
        if (foreignAddress) {
            foreignAddress = IPv6_2_IPv4(foreignAddress);
        }
    }
    if (addressFamily == AF_INET && localAddress && foreignAddress) {
        struct in_addr *ip4LocalAddress = (struct in_addr *)localAddress;
        struct in_addr *ip4ForeignAddress = (struct in_addr *)foreignAddress;

        NSLog(@"%x:%d -> %x:%d pid=%d", ip4LocalAddress->s_addr, localPort, ip4ForeignAddress->s_addr, foreignPort, pid);
        if (ntohl(ip4LocalAddress->s_addr) == INADDR_LOOPBACK &&
            ntohl(ip4ForeignAddress->s_addr) == INADDR_LOOPBACK &&
            localPort == _socketAddress.port) {
            return YES;
        }
    }

    return NO;
}

@end
