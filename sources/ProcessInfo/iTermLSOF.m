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
#include <netinet/in.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/un.h>

@implementation iTermProcessFileDescriptor
@end

@interface iTermLSOFProxy: NSObject<iTermProcessDataSource>
@end

@implementation iTermLSOFProxy

+ (instancetype)sharedInstance {
    static iTermLSOFProxy *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermLSOFProxy alloc] init];
    });
    return instance;
}

- (NSArray<NSString *> *)commandLineArgumentsForProcess:(pid_t)pid execName:(NSString *__autoreleasing *)execName {
    return [iTermLSOF commandLineArgumentsForProcess:pid execName:execName];
}

- (NSString *)nameOfProcessWithPid:(pid_t)thePid isForeground:(BOOL *)isForeground {
    return [iTermLSOF nameOfProcessWithPid:thePid isForeground:isForeground];
}

- (NSDate *)startTimeForProcess:(pid_t)pid {
    return [iTermLSOF startTimeForProcess:pid];
}

- (dev_t)ttyRdevForFileDescriptor:(int)fd ofProcess:(pid_t)pid {
    return [iTermLSOF ttyRdevForFileDescriptor:fd ofProcess:pid];
}

@end

@implementation iTermLSOF {
    iTermSocketAddress *_socketAddress;
}

+ (id<iTermProcessDataSource>)processDataSource {
    return [iTermLSOFProxy sharedInstance];
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
    NSArray<NSString *> *argv = [self commandLineArgumentsForProcess:pid execName:execName];
    return [argv componentsJoinedByString:@" "];
}

+ (NSString *)displayCommandForProcess:(pid_t)pid execName:(NSString **)execName {
    NSArray<NSString *> *argv = [self rawCommandLineArgumentsForProcess:pid execName:execName];
    if (!argv) {
        return nil;
    }
    return [argv componentsJoinedByString:@" "];
}

+ (NSArray<NSString *> *)rawCommandLineArgumentsForProcess:(pid_t)pid execName:(NSString **)execName {
    int argmax = [self maximumLengthOfProcargs];
    char *procargs = [self procargsForProcess:pid];
    if (procargs == nil) {
        return nil;
    }

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
    int argsConsumed = 0;
    while (offset < argmax && argsConsumed < nargs) {
        if (procargs[offset] == 0) {
            NSString *string = [NSString stringWithUTF8String:start];
            if (string.length > 0) {
                [argv addObject:string];
            }
            argsConsumed++;
            start = procargs + offset + 1;
        }
        offset++;
    }

    if (argv.count == 0) {
        return @[];
    }
    NSString *command = argv[0];
    NSRange lastSlash = [command rangeOfString:@"/" options:NSBackwardsSearch];
    if (lastSlash.location != NSNotFound) {
        argv[0] = [command substringFromIndex:lastSlash.location + 1];
    }
    return argv;
}

+ (NSArray<NSString *> *)environmentForProcess:(pid_t)pid {
    const int argmax = [self maximumLengthOfProcargs];
    if (argmax < 0) {
        return nil;
    }
    char *procargs = [self procargsForProcess:pid];
    if (procargs == nil) {
        return nil;
    }

    // Consume argc.
    size_t offset = 0;
    int nargs = 0;
    memmove(&nargs, procargs + offset, sizeof(int));
    offset += sizeof(int);

    // Skip exec_path and its trailing nulls.
    while (offset < (size_t)argmax && procargs[offset] != 0) {
        ++offset;
    }
    while (offset < (size_t)argmax && procargs[offset] == 0) {
        ++offset;
    }
    if (offset >= (size_t)argmax) {
        return @[];
    }

    // Skip the argv strings (nargs null-terminated entries).
    int argsConsumed = 0;
    while (offset < (size_t)argmax && argsConsumed < nargs) {
        if (procargs[offset] == 0) {
            ++argsConsumed;
        }
        ++offset;
    }

    // Skip any padding nulls before the environment block.
    while (offset < (size_t)argmax && procargs[offset] == 0) {
        ++offset;
    }

    // The remaining null-terminated strings are the environment, terminated by
    // an empty string (i.e. a double null).
    NSMutableArray<NSString *> *env = [NSMutableArray array];
    char *start = procargs + offset;
    while (offset < (size_t)argmax) {
        if (procargs[offset] == 0) {
            if (start[0] == 0) {
                break;
            }
            NSString *entry = [NSString stringWithUTF8String:start];
            if (entry) {
                [env addObject:entry];
            }
            start = procargs + offset + 1;
        }
        ++offset;
    }
    return env;
}

static NSString *iTermTCPStateString(int state) {
    static NSArray<NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Indices match the tcpstates enum in <sys/proc_info.h>.
        names = @[ @"CLOSED", @"LISTEN", @"SYN_SENT", @"SYN_RCVD", @"ESTABLISHED",
                   @"CLOSE_WAIT", @"FIN_WAIT_1", @"CLOSING", @"LAST_ACK",
                   @"FIN_WAIT_2", @"TIME_WAIT" ];
    });
    if (state >= 0 && state < (int)names.count) {
        return names[state];
    }
    return [NSString stringWithFormat:@"%d", state];
}

static NSString *iTermSocketEndpointString(const struct in_sockinfo *in, BOOL local) {
    char buf[INET6_ADDRSTRLEN] = { 0 };
    const int port = ntohs((uint16_t)(local ? in->insi_lport : in->insi_fport));
    if (in->insi_vflag & INI_IPV6) {
        const struct in6_addr *addr = local ? &in->insi_laddr.ina_6 : &in->insi_faddr.ina_6;
        inet_ntop(AF_INET6, addr, buf, sizeof(buf));
        return [NSString stringWithFormat:@"[%s]:%d", buf, port];
    }
    const struct in_addr *addr = local ? &in->insi_laddr.ina_46.i46a_addr4 : &in->insi_faddr.ina_46.i46a_addr4;
    inet_ntop(AF_INET, addr, buf, sizeof(buf));
    return [NSString stringWithFormat:@"%s:%d", buf, port];
}

+ (void)populateDescriptor:(iTermProcessFileDescriptor *)descriptor
            fromSocketInfo:(const struct socket_info *)si {
    switch (si->soi_kind) {
        case SOCKINFO_TCP: {
            const struct tcp_sockinfo *tcp = &si->soi_proto.pri_tcp;
            descriptor.type = @"TCP";
            descriptor.detail = [NSString stringWithFormat:@"%@ → %@ (%@)",
                                 iTermSocketEndpointString(&tcp->tcpsi_ini, YES),
                                 iTermSocketEndpointString(&tcp->tcpsi_ini, NO),
                                 iTermTCPStateString(tcp->tcpsi_state)];
            break;
        }
        case SOCKINFO_IN: {
            const struct in_sockinfo *in = &si->soi_proto.pri_in;
            descriptor.type = (si->soi_protocol == IPPROTO_UDP) ? @"UDP" : @"IP";
            descriptor.detail = [NSString stringWithFormat:@"%@ → %@",
                                 iTermSocketEndpointString(in, YES),
                                 iTermSocketEndpointString(in, NO)];
            break;
        }
        case SOCKINFO_UN: {
            const struct un_sockinfo *un = &si->soi_proto.pri_un;
            descriptor.type = @"unix";
            descriptor.detail = [NSString stringWithUTF8String:un->unsi_addr.ua_sun.sun_path] ?: @"";
            break;
        }
        default:
            descriptor.type = @"socket";
            descriptor.detail = @"";
            break;
    }
}

+ (iTermProcessFileDescriptor *)descriptorForFd:(const struct proc_fdinfo *)fdinfo pid:(pid_t)pid {
    iTermProcessFileDescriptor *descriptor = [[iTermProcessFileDescriptor alloc] init];
    descriptor.fd = fdinfo->proc_fd;
    descriptor.detail = @"";
    switch (fdinfo->proc_fdtype) {
        case PROX_FDTYPE_VNODE: {
            descriptor.type = @"file";
            struct vnode_fdinfowithpath info;
            const int rc = proc_pidfdinfo(pid, fdinfo->proc_fd, PROC_PIDFDVNODEPATHINFO, &info, sizeof(info));
            if (rc == sizeof(info)) {
                descriptor.detail = [NSString stringWithUTF8String:info.pvip.vip_path] ?: @"";
            }
            break;
        }
        case PROX_FDTYPE_SOCKET: {
            descriptor.type = @"socket";
            struct socket_fdinfo info;
            const int rc = proc_pidfdinfo(pid, fdinfo->proc_fd, PROC_PIDFDSOCKETINFO, &info, sizeof(info));
            if (rc == sizeof(info)) {
                [self populateDescriptor:descriptor fromSocketInfo:&info.psi];
            }
            break;
        }
        case PROX_FDTYPE_PIPE:
            descriptor.type = @"pipe";
            break;
        case PROX_FDTYPE_KQUEUE:
            descriptor.type = @"kqueue";
            break;
        case PROX_FDTYPE_PSEM:
            descriptor.type = @"sem";
            break;
        case PROX_FDTYPE_PSHM:
            descriptor.type = @"shm";
            break;
        default:
            descriptor.type = @"other";
            break;
    }
    return descriptor;
}

+ (NSArray<iTermProcessFileDescriptor *> *)fileDescriptorsForProcess:(pid_t)pid {
    const int bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (bufferSize <= 0) {
        return nil;
    }
    struct proc_fdinfo *fds = (struct proc_fdinfo *)iTermMalloc(bufferSize);
    const int bytesReturned = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, bufferSize);
    if (bytesReturned <= 0) {
        free(fds);
        return nil;
    }
    const int count = bytesReturned / (int)sizeof(struct proc_fdinfo);
    NSMutableArray<iTermProcessFileDescriptor *> *result = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        [result addObject:[self descriptorForFd:&fds[i] pid:pid]];
    }
    free(fds);
    return result;
}

+ (dev_t)ttyRdevForFileDescriptor:(int)fd ofProcess:(pid_t)pid {
    struct vnode_fdinfowithpath info;
    const int rc = proc_pidfdinfo(pid, fd, PROC_PIDFDVNODEPATHINFO, &info, sizeof(info));
    if (rc != sizeof(info)) {
        return 0;
    }
    // Only character special devices have a meaningful rdev. Pipes and sockets are
    // a different fd type entirely and never reach this code; a regular file is a
    // vnode but not a character device.
    if ((info.pvip.vip_vi.vi_stat.vst_mode & S_IFMT) != S_IFCHR) {
        return 0;
    }
    // proc_pidfdinfo reports an rdev for ANY character device, including /dev/null,
    // /dev/zero, etc. We only want terminals, so a redirection to /dev/null is not
    // mistaken for the session's controlling tty. On macOS pty slaves are
    // /dev/ttysNNN and the controlling-terminal alias is /dev/tty, so they all
    // share the /dev/tty prefix.
    NSString *path = [NSString stringWithUTF8String:info.pvip.vip_path] ?: @"";
    if (![path hasPrefix:@"/dev/tty"]) {
        return 0;
    }
    return info.pvip.vip_vi.vi_stat.vst_rdev;
}

+ (NSArray<NSString *> *)commandLineArgumentsForProcess:(pid_t)pid execName:(NSString **)execName {
    NSArray<NSString *> *raw = [self rawCommandLineArgumentsForProcess:pid execName:execName];
    if (!raw) {
        return nil;
    }
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:raw.count];
    for (NSString *arg in raw) {
        [result addObject:[self escapedArgument:arg] ?: @""];
    }
    return result;
}

+ (NSString *)escapedArgument:(NSString *)arg {
    if (arg.length == 0) {
        return @"\"\"";  // Empty string needs to be quoted
    }

    // Check if the string needs any escaping at all
    NSCharacterSet *shellSpecialChars = [NSCharacterSet characterSetWithCharactersInString:[NSString shellEscapableCharacters]];
    NSCharacterSet *controlChars = [NSCharacterSet controlCharacterSet];
    if ([arg rangeOfCharacterFromSet:shellSpecialChars].location == NSNotFound &&
        [arg rangeOfCharacterFromSet:controlChars].location == NSNotFound) {
        // No special characters, return as-is
        return arg;
    }

    // Check for characters that are dangerous inside double quotes.
    // Parens are meaningful for fish.
    // Also exclude control characters (except tab which we explicitly allow)
    static NSCharacterSet *doubleQuoteUnsafe;
    {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSMutableCharacterSet *characterSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"\"$`\\!()"];
            NSMutableCharacterSet *unsafeControls = [[NSCharacterSet controlCharacterSet] mutableCopy];
            [unsafeControls removeCharactersInString:@"\t"];  // tab is okay in double quotes
            [characterSet formUnionWithCharacterSet:unsafeControls];
            [characterSet addCharactersInRange:NSMakeRange(0, 1)];
            doubleQuoteUnsafe = characterSet;
        });
    }
    if ([arg rangeOfCharacterFromSet:doubleQuoteUnsafe].location == NSNotFound) {
        return [NSString stringWithFormat:@"\"%@\"", arg];
    }

    // Try single quotes if the string doesn't contain problematic characters
    // While single quotes make everything literal in POSIX shells, we need to be conservative
    // to ensure proper round-tripping across bash, zsh, fish, and tcsh.
    static NSCharacterSet *singleQuoteUnsafe;
    {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSMutableCharacterSet *characterSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"'"];
            [characterSet formUnionWithCharacterSet:[NSCharacterSet controlCharacterSet]];
            [characterSet addCharactersInRange:NSMakeRange(0, 1)];
            singleQuoteUnsafe = characterSet;
        });
    }
    if ([arg rangeOfCharacterFromSet:singleQuoteUnsafe].location == NSNotFound) {
        return [NSString stringWithFormat:@"'%@'", arg];
    }

    // Fall back to the comprehensive escaping method which handles all edge cases
    // and ensures proper round-tripping across different shells
    return [arg stringWithEscapedShellCharactersIncludingNewlines:YES];
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
        RLog(@"Forcing a synchronous update of the process cache");
        [[iTermProcessCache sharedInstance] updateSynchronously];
        parentInfo = [[iTermProcessCache sharedInstance] processInfoForPid:parentPid];
    }
    if (!parentInfo) {
        RLog(@"No parent with pid %@", @(parentPid));
        return -1;
    }
    iTermProcessInfo *firstChild = [parentInfo.children minWithBlock:^NSComparisonResult(iTermProcessInfo *obj1, iTermProcessInfo *obj2) {
        return [obj1.startTime compare:obj2.startTime];
    }];
    if (!firstChild) {
        RLog(@"Process is childless");
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
        DLog(@"Get result for pid %@: %@", @(pid), pwd);
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
        DLog(@"getWorkingDirectoyrOfProcessWithID:%@ returned %@", @(pid), rawDir);
        if (!rawDir) {
            RLog(@"Failed to get working directory of %@", @(pid));
        }
        if (!rawDir && canFallBack) {
            RLog(@"Will attempt fallback");
            pid_t childPid = [self pidOfFirstChildOf:pid];
            if (childPid <= 0) {
                RLog(@"Failed to get first child. Giving up.");
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
