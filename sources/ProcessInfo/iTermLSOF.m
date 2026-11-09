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
#include <stdatomic.h>
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

// KERN_PROCARGS2 has each argument as its own string.
- (NSArray<NSString *> *)rawCommandLineArgumentsForProcess:(pid_t)pid {
    return [iTermLSOF rawCommandLineArgumentsForProcess:pid execName:nil];
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

// A shell at its prompt: it exec'ed (a forked subshell never does) and runs no script or -c
// command. Neither a subshell nor a script shell does job control, so whatever it runs stays in
// its group; when one leads the foreground group, the user's shell is the one that started it.
static BOOL iTermWalkProcessIsShellAtPrompt(const iTermWalkProcess *process,
                                            NSArray<NSString *> *(^arguments)(pid_t)) {
    return (process->didExec &&
            [iTermLSOF processNameIsAShell:[NSString stringWithUTF8String:process->name]] &&
            ![iTermLSOF shellArgumentsRunScriptOrCommand:arguments(process->pid)]);
}

// Finds the shell the user is in when the foreground job isn't a shell at its prompt. See
// +[iTermLSOF asyncWorkingDirectoryOfForegroundShellWithRootPid:...].
@interface iTermForegroundShellWalk : NSObject
// table holds iTermWalkProcess structs in any order.
- (instancetype)initWithTable:(NSData *)table
                    arguments:(NSArray<NSString *> *(^)(pid_t pid))arguments NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
// The pid of the shell whose directory to read, or -1 for none.
- (pid_t)shellWithRoot:(pid_t)root group:(pid_t)group;
@end

@implementation iTermLSOF {
    iTermSocketAddress *_socketAddress;
}

+ (id<iTermProcessDataSource>)processDataSource {
    return [iTermLSOFProxy sharedInstance];
}

// KERN_PROCARGS2 copies from the end of the process's argument area, so a buffer smaller than the
// area gets only its tail, which is padding. Ask for the size first (a few KB, where KERN_ARGMAX is
// 1 MB). With a byte to spare, a complete read comes back shorter than the buffer; one that fills
// it means an exec in between grew the area, so try again.
+ (NSData *)procargsForProcess:(pid_t)pid {
    int mib[3] = { CTL_KERN, KERN_PROCARGS2, pid };
    for (int attempt = 0; attempt < 2; attempt++) {
        size_t size = 0;
        if (sysctl(mib, 3, NULL, &size, NULL, 0) == -1 || size == 0) {
            return nil;
        }
        NSMutableData *data = [NSMutableData dataWithLength:size + 1];
        size_t length = data.length;
        if (sysctl(mib, 3, data.mutableBytes, &length, NULL, 0) == -1) {
            return nil;
        }
        if (length < data.length) {
            // Keep a terminator after the last string so parsers can't read past the end.
            const char *bytes = data.bytes;
            data.length = (length > 0 && bytes[length - 1] == 0) ? length : length + 1;
            return data;
        }
    }
    return nil;
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
    NSData *procargsData = [self procargsForProcess:pid];
    if (procargsData.length < sizeof(int)) {
        return nil;
    }
    const char *procargs = procargsData.bytes;
    const size_t length = procargsData.length;

    // Consume argc
    size_t offset = 0;
    int nargs;
    memmove(&nargs, procargs + offset, sizeof(int));
    offset += sizeof(int);

    // Skip exec_path
    const char *exec_path = procargs + offset;
    while (offset < length && procargs[offset] != 0) {
        ++offset;
    }

    // Skip trailing nulls
    while (offset < length && procargs[offset] == 0) {
        ++offset;
    }
    if (offset == length) {
        return nil;
    }
    if (execName) {
        *execName = [NSString stringWithUTF8String:exec_path];
    }

    // Pull out null terminated argv components
    NSMutableArray<NSString *> *argv = [NSMutableArray array];
    const char *start = procargs + offset;
    int argsConsumed = 0;
    while (offset < length && argsConsumed < nargs) {
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
    NSData *procargsData = [self procargsForProcess:pid];
    if (procargsData.length < sizeof(int)) {
        return nil;
    }
    const char *procargs = procargsData.bytes;
    const size_t length = procargsData.length;

    // Consume argc.
    size_t offset = 0;
    int nargs = 0;
    memmove(&nargs, procargs + offset, sizeof(int));
    offset += sizeof(int);

    // Skip exec_path and its trailing nulls.
    while (offset < length && procargs[offset] != 0) {
        ++offset;
    }
    while (offset < length && procargs[offset] == 0) {
        ++offset;
    }
    if (offset >= length) {
        return @[];
    }

    // Skip the argv strings (nargs null-terminated entries).
    int argsConsumed = 0;
    while (offset < length && argsConsumed < nargs) {
        if (procargs[offset] == 0) {
            ++argsConsumed;
        }
        ++offset;
    }

    // Skip any padding nulls before the environment block.
    while (offset < length && procargs[offset] == 0) {
        ++offset;
    }

    // The remaining null-terminated strings are the environment, terminated by
    // an empty string (i.e. a double null).
    NSMutableArray<NSString *> *env = [NSMutableArray array];
    const char *start = procargs + offset;
    while (offset < length) {
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

// has a controlling terminal and
// process group id = tty process group id
static BOOL iTermKinfoProcIsForeground(const struct kinfo_proc *kp) {
    return ((kp->kp_proc.p_flag & P_CONTROLT) &&
            kp->kp_eproc.e_pgid == kp->kp_eproc.e_tpgid);
}

// A failed KERN_PROC_ALL read is unexpected, so it goes to RLog. The process cache
// refreshes up to twice a second, so only log when reads start or stop failing; a
// persistent failure would otherwise flood the ring buffer. failure is nil on success.
static void iTermNoteProcessTableReadResult(NSString *failure) {
    static atomic_bool failing;
    const bool wasFailing = atomic_exchange(&failing, failure != nil);
    if (failure && !wasFailing) {
        RLog(@"%@; falling back to per-pid process lookups until it succeeds", failure);
    } else if (failure) {
        DLog(@"%@", failure);
    } else if (wasFailing) {
        RLog(@"KERN_PROC_ALL read succeeded again; no longer falling back to per-pid process lookups");
    }
}

// Every process's kinfo_proc from one KERN_PROC_ALL read, or nil with *failure set.
static NSData *iTermReadProcessTable(NSString **failure) {
    // KERN_PROC_PID walks the kernel's whole process list to find one pid, so asking
    // about every process one at a time costs O(n^2). One KERN_PROC_ALL read returns
    // the same kinfo_proc for every process at once.
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    // The table can grow between the size query and the read, so leave headroom and
    // retry a few times if it still outgrows the buffer.
    for (int attempt = 0; ; attempt++) {
        size_t size = 0;
        if (sysctl(mib, 3, NULL, &size, NULL, 0) < 0) {
            const int savedErrno = errno;
            *failure = [NSString stringWithFormat:@"KERN_PROC_ALL size query failed: errno=%d (%s), attempt %d",
                        savedErrno, strerror(savedErrno), attempt + 1];
            return nil;
        }
        size += size / 8 + 64 * sizeof(struct kinfo_proc);
        const size_t bufferSize = size;
        NSMutableData *data = [NSMutableData dataWithLength:bufferSize];
        if (sysctl(mib, 3, data.mutableBytes, &size, NULL, 0) == 0) {
            data.length = size;
            return data;
        }
        const int savedErrno = errno;
        if (savedErrno != ENOMEM || attempt == 3) {
            *failure = [NSString stringWithFormat:@"KERN_PROC_ALL read failed: errno=%d (%s), buffer %zu bytes, attempt %d",
                        savedErrno, strerror(savedErrno), bufferSize, attempt + 1];
            return nil;
        }
        DLog(@"KERN_PROC_ALL table outgrew a %zu-byte buffer; retrying", bufferSize);
    }
}

+ (BOOL)enumerateProcessTable:(void (^ NS_NOESCAPE)(pid_t pid, pid_t ppid, NSString *name, BOOL isForeground))block {
    NSString *failure = nil;
    NSData *data = iTermReadProcessTable(&failure);
    iTermNoteProcessTableReadResult(failure);
    if (!data) {
        return NO;
    }
    const struct kinfo_proc *procs = data.bytes;
    const size_t count = data.length / sizeof(struct kinfo_proc);
    for (size_t i = 0; i < count; i++) {
        const struct kinfo_proc *kp = &procs[i];
        // proc_pidinfo, which this replaces, fails for zombies, so they were never in
        // the collection. Keep it that way.
        if (kp->kp_proc.p_stat == SZOMB) {
            continue;
        }
        NSString *name = nil;
        if (kp->kp_proc.p_comm[0]) {
            char comm[MAXCOMLEN + 1];
            memcpy(comm, kp->kp_proc.p_comm, MAXCOMLEN);
            comm[MAXCOMLEN] = 0;
            name = [NSString stringWithUTF8String:comm];
        }
        block(kp->kp_proc.p_pid, kp->kp_eproc.e_ppid, name, iTermKinfoProcIsForeground(kp));
    }
    return YES;
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

    if (isForeground) {
        *isForeground = iTermKinfoProcIsForeground(&kp);
    }

    if (kp.kp_proc.p_comm[0]) {
        return [NSString stringWithUTF8String:kp.kp_proc.p_comm];
    } else {
        return nil;
    }
}

+ (NSString *)nameFailureDiagnosisForPid:(pid_t)pid {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    struct kinfo_proc kp;
    // Zero the whole struct so that, if the sysctl reports success but writes nothing
    // (Darwin returns 0 bytes for a pid that wasn't matched during its process-list
    // walk), p_stat/p_flag read back as 0 rather than as garbage.
    memset(&kp, 0, sizeof(kp));
    size_t bufSize = sizeof(kp);
    errno = 0;
    const int rc = sysctl(mib, 4, &kp, &bufSize, NULL, 0);
    if (rc < 0) {
        return [NSString stringWithFormat:@"sysctl KERN_PROC_PID error rc=%d errno=%d (%s)",
                rc, errno, strerror(errno)];
    }
    if (bufSize == 0) {
        return @"pid not in the kernel process list (not matched; likely exited or momentarily unreferenceable)";
    }
    if (kp.kp_proc.p_comm[0] == 0) {
        return [NSString stringWithFormat:@"matched but empty p_comm (p_stat=%d p_flag=0x%x; typically mid-exec)",
                (int)kp.kp_proc.p_stat, kp.kp_proc.p_flag];
    }
    return [NSString stringWithFormat:@"readable now as \"%s\" (original failure was transient)",
            kp.kp_proc.p_comm];
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
    return [self waitForWorkingDirectory:^(dispatch_queue_t queue, void (^block)(NSString *)) {
        [self asyncWorkingDirectoryOfProcess:pid queue:queue block:block];
    }];
}

+ (NSString *)workingDirectoryOfForegroundShellWithRootPid:(pid_t)rootPid
                                    foregroundProcessGroup:(pid_t)pgrp {
    DLog(@"Want working directory of foreground shell under %@ (pgrp %@) - SYNCHRONOUS METHOD!",
         @(rootPid), @(pgrp));
    return [self waitForWorkingDirectory:^(dispatch_queue_t queue, void (^block)(NSString *)) {
        [self asyncWorkingDirectoryOfForegroundShellWithRootPid:rootPid
                                         foregroundProcessGroup:pgrp
                                                          queue:queue
                                                          block:block];
    }];
}

+ (NSString *)waitForWorkingDirectory:(void (^ NS_NOESCAPE)(dispatch_queue_t queue,
                                                            void (^block)(NSString *)))lookup {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.iterm2.pwd", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    __block NSString *result = nil;
    lookup(queue, ^(NSString *pwd) {
        DLog(@"Got result: %@", pwd);
        result = pwd;
        dispatch_group_leave(group);
    });
    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW,
                                             0.5 * NSEC_PER_SEC));
    DLog(@"Result is %@", result);
    return result;
}

+ (BOOL)processNameIsAShell:(NSString *)name {
    static NSSet<NSString *> *shells;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shells = [[NSSet alloc] initWithArray:@[ @"zsh", @"bash", @"sh", @"fish", @"tcsh", @"csh",
                                                 @"ksh", @"dash", @"nu", @"xonsh", @"elvish" ]];
    });
    NSString *base = name.lastPathComponent;
    if ([base hasPrefix:@"-"]) {
        base = [base substringFromIndex:1];
    }
    return base.length > 0 && [shells containsObject:base];
}

static void iTermWalkProcessInit(iTermWalkProcess *process, const struct kinfo_proc *kp) {
    process->pid = kp->kp_proc.p_pid;
    process->ppid = kp->kp_eproc.e_ppid;
    process->pgid = kp->kp_eproc.e_pgid;
    process->didExec = (kp->kp_proc.p_flag & P_EXEC) != 0;
    process->tty = kp->kp_eproc.e_tdev;
    process->ttyForegroundProcessGroup = kp->kp_eproc.e_tpgid;
    memcpy(process->name, kp->kp_proc.p_comm, MAXCOMLEN);
    process->name[MAXCOMLEN] = 0;
}

+ (pid_t)foregroundShellPidWithRootPid:(pid_t)rootPid foregroundProcessGroup:(pid_t)pgrp {
    return [self foregroundShellPidWithRootPid:rootPid
                        foregroundProcessGroup:pgrp
                                        lookup:^BOOL(pid_t pid, iTermWalkProcess *process) {
        int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
        struct kinfo_proc kp;
        memset(&kp, 0, sizeof(kp));
        size_t size = sizeof(kp);
        if (sysctl(mib, 4, &kp, &size, NULL, 0) < 0 || size == 0 || kp.kp_proc.p_stat == SZOMB) {
            return NO;
        }
        iTermWalkProcessInit(process, &kp);
        return YES;
    }
                                  processTable:^NSData *{
        const uint64_t start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        NSString *failure = nil;
        NSData *data = iTermReadProcessTable(&failure);
        if (!data) {
            DLog(@"Can't read the process table: %@", failure);
            return nil;
        }
        const uint64_t read = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        const struct kinfo_proc *procs = data.bytes;
        const size_t count = data.length / sizeof(struct kinfo_proc);
        NSMutableData *table = [NSMutableData dataWithLength:count * sizeof(iTermWalkProcess)];
        iTermWalkProcess *processes = table.mutableBytes;
        size_t n = 0;
        for (size_t i = 0; i < count; i++) {
            // A zombie has exited. Leaving it out lets a job whose leader exited be found through
            // its other members.
            if (procs[i].kp_proc.p_stat != SZOMB) {
                iTermWalkProcessInit(&processes[n++], &procs[i]);
            }
        }
        table.length = n * sizeof(iTermWalkProcess);
        DLog(@"Read %@ processes in %@us, copied in %@us",
             @(count), @((read - start) / 1000), @((clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - read) / 1000));
        return table;
    }
                                     arguments:^NSArray<NSString *> *(pid_t pid) {
        return [self rawCommandLineArgumentsForProcess:pid execName:nil];
    }];
}

+ (pid_t)foregroundShellPidWithRootPid:(pid_t)rootPid
                foregroundProcessGroup:(pid_t)pgrp
                                lookup:(BOOL (^ NS_NOESCAPE)(pid_t pid, iTermWalkProcess *process))lookup
                          processTable:(NSData *(^ NS_NOESCAPE)(void))processTable
                             arguments:(NSArray<NSString *> *(^)(pid_t pid))arguments {
    // Most polls that matter land at a prompt (after Enter, an unverified push, or a title
    // change), where the leader alone settles it.
    iTermWalkProcess leader;
    if (lookup(pgrp, &leader) &&
        leader.pgid == pgrp &&
        iTermWalkProcessIsShellAtPrompt(&leader, arguments)) {
        DLog(@"Foreground shell is the leader %@ (%s)", @(pgrp), leader.name);
        return pgrp;
    }
    NSData *table = processTable();
    if (!table) {
        return -1;
    }
    iTermForegroundShellWalk *walk = [[iTermForegroundShellWalk alloc] initWithTable:table
                                                                           arguments:arguments];
    return [walk shellWithRoot:rootPid group:pgrp];
}

+ (BOOL)shellArgumentsRunScriptOrCommand:(NSArray<NSString *> *)argv {
    if (argv.count < 2) {
        // No arguments, or they couldn't be read (another user's process).
        return NO;
    }
    NSString *shell = argv[0].lastPathComponent;
    if ([shell hasPrefix:@"-"]) {
        shell = [shell substringFromIndex:1];
    }
    const BOOL fish = [shell isEqualToString:@"fish"];
    // Options whose value is the next argument, so it isn't mistaken for a script.
    NSString *shortOptionsWithValues = fish ? @"Cdfo" : @"oO";
    NSSet<NSString *> *longOptionsWithValues =
        fish ? [NSSet setWithArray:@[ @"--init-command", @"--debug", @"--debug-output", @"--features" ]]
             : [NSSet setWithArray:@[ @"--rcfile", @"--init-file", @"--emulate" ]];
    for (NSUInteger i = 1; i < argv.count; i++) {
        NSString *arg = argv[i];
        if ([arg isEqualToString:@"--"] || [arg isEqualToString:@"-"]) {
            // The end of the options. What follows is a script.
            return i + 1 < argv.count;
        }
        if ([arg hasPrefix:@"--"]) {
            if ([arg isEqualToString:@"--command"] || [arg hasPrefix:@"--command="]) {
                return YES;
            }
            if ([longOptionsWithValues containsObject:arg]) {
                i++;
            }
            continue;
        }
        if (arg.length > 1 && ([arg hasPrefix:@"-"] || [arg hasPrefix:@"+"])) {
            for (NSUInteger j = 1; j < arg.length; j++) {
                const unichar c = [arg characterAtIndex:j];
                if (c == 'c') {
                    return YES;
                }
                if (c == 's') {
                    // Commands come from stdin; any operands are positional parameters.
                    return NO;
                }
                if ([shortOptionsWithValues rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound) {
                    if (j + 1 == arg.length) {
                        i++;
                    }
                    break;
                }
            }
            continue;
        }
        return YES;
    }
    return NO;
}

+ (void)asyncWorkingDirectoryOfForegroundShellWithRootPid:(pid_t)rootPid
                                   foregroundProcessGroup:(pid_t)pgrp
                                                    queue:(dispatch_queue_t)queue
                                                    block:(void (^)(NSString *pwd))block {
    if (pgrp <= 0) {
        DLog(@"No foreground process group; reading the root %@", @(rootPid));
        [self asyncWorkingDirectoryOfProcess:rootPid queue:queue block:block];
        return;
    }
    // The walk is a few sysctls, which needn't run on the main thread.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const pid_t pid = [self foregroundShellPidWithRootPid:rootPid foregroundProcessGroup:pgrp];
        if (pid <= 0) {
            dispatch_async(queue, ^{
                block(nil);
            });
            return;
        }
        // Only the root gets the eldest-child fallback (for a root-owned login). Any other
        // process's ancestors may be in other directories.
        [self asyncWorkingDirectoryOfProcess:pid
                                 canFallBack:pid == rootPid
                                       queue:queue
                                       block:block];
    });
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
        if (!rawDir && canFallBack) {
            // The root pid is often /usr/bin/login running as root, whose vnode
            // info we're not allowed to read. That's expected and we recover via
            // the eldest child below, so log the miss at DLog. Only a real
            // give-up (no child to fall back to) is worth an RLog.
            DLog(@"Failed to get working directory of %@; will attempt fallback", @(pid));
            pid_t childPid = [self pidOfFirstChildOf:pid];
            if (childPid <= 0) {
                RLog(@"Failed to get working directory of %@ and it has no child to fall back to. Giving up.", @(pid));
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
            RLog(@"Failed to get working directory of %@", @(pid));
            block(nil);
            return;
        }
        NSString *dir = [[iTermSyntheticConfParser sharedInstance] pathByReplacingPrefixWithSyntheticRoot:rawDir];
        DLog(@"Result: %@ -> %@", rawDir, dir);
        block(dir);
        return;
    }];
}

@end


// Bounds, in case pid reuse during the snapshot makes a cycle.
static const int iTermForegroundShellWalkMaximumAncestors = 64;
static const int iTermForegroundShellWalkMaximumRelayDepth = 8;

static int iTermWalkProcessComparePids(const void *a, const void *b) {
    const pid_t lhs = ((const iTermWalkProcess *)a)->pid;
    const pid_t rhs = ((const iTermWalkProcess *)b)->pid;
    return (lhs > rhs) - (lhs < rhs);
}

// Whether a process is on a terminal other than `tty`. One with no terminal isn't.
static BOOL iTermWalkProcessIsOnOtherTerminal(const iTermWalkProcess *process, dev_t tty) {
    return process->tty != tty && process->tty != NODEV;
}

@implementation iTermForegroundShellWalk {
    // Sorted by pid.
    NSMutableData *_table;
    const iTermWalkProcess *_processes;
    NSInteger _count;
    // _parents[i] is the index of _processes[i]'s parent, or -1 if it isn't in the table.
    NSMutableData *_parentData;
    const NSInteger *_parents;
    NSArray<NSString *> *(^_arguments)(pid_t);
    // Terminals already searched, so a cycle can't recurse.
    NSMutableSet<NSNumber *> *_visitedTTYs;
}

- (instancetype)initWithTable:(NSData *)table
                    arguments:(NSArray<NSString *> *(^)(pid_t pid))arguments {
    self = [super init];
    if (self) {
        const uint64_t start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        _table = [table mutableCopy];
        _count = _table.length / sizeof(iTermWalkProcess);
        qsort(_table.mutableBytes, _count, sizeof(iTermWalkProcess), iTermWalkProcessComparePids);
        _processes = _table.bytes;
        _parentData = [NSMutableData dataWithLength:_count * sizeof(NSInteger)];
        NSInteger *parents = _parentData.mutableBytes;
        for (NSInteger i = 0; i < _count; i++) {
            parents[i] = [self indexOfPid:_processes[i].ppid];
        }
        _parents = parents;
        _arguments = [arguments copy];
        _visitedTTYs = [NSMutableSet set];
        DLog(@"Indexed %@ processes in %@us",
             @(_count), @((clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1000));
    }
    return self;
}

- (NSInteger)indexOfPid:(pid_t)pid {
    NSInteger low = 0;
    NSInteger high = _count - 1;
    while (low <= high) {
        const NSInteger mid = low + (high - low) / 2;
        const pid_t value = _processes[mid].pid;
        if (value == pid) {
            return mid;
        }
        if (value < pid) {
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    return -1;
}

- (BOOL)isShellAtPrompt:(NSInteger)i {
    return iTermWalkProcessIsShellAtPrompt(&_processes[i], _arguments);
}

- (pid_t)shellWithRoot:(pid_t)root group:(pid_t)group {
    BOOL unused = NO;
    return [self shellWithRoot:root group:group depth:0 found:&unused];
}

// Searches the terminal whose foreground process group is `group` and whose session started at
// `root`. depth is 0 for the session's own terminal and counts relays below it. For a relayed
// terminal, *found says whether it has an interactive shell, and so whether the return value
// (which may still be -1) is the answer. If not, the caller uses its own.
- (pid_t)shellWithRoot:(pid_t)root group:(pid_t)group depth:(int)depth found:(BOOL *)found {
    const BOOL relayed = depth > 0;
    *found = YES;
    NSInteger leader = [self indexOfPid:group];
    if (leader >= 0 && _processes[leader].pgid != group) {
        leader = -1;
    }
    if (leader >= 0 && [self isShellAtPrompt:leader]) {
        DLog(@"Foreground shell is the leader %@ (%s) at depth %@", @(group), _processes[leader].name, @(depth));
        return group;
    }
    if (leader < 0 && group == root) {
        DLog(@"Root %@ is unknown; using it", @(root));
        return root;
    }

    // The foreground job is a command. Find the shell that started it.
    BOOL candidateIsShell = NO;
    NSInteger start = -1;
    const pid_t candidate = [self shellThatStartedJob:group
                                                 root:root
                                               leader:leader
                                              isShell:&candidateIsShell
                                                start:&start];
    if (relayed && candidate < 0) {
        // Something is odd, e.g., the job is starting or exiting. Report nothing rather than
        // the outer shell, which may not be the one the user is in.
        return -1;
    }

    // A job that relays another terminal: the user is typing into whatever runs on it.
    const NSInteger relay = start >= 0 ? [self relayBelowGroup:group tty:_processes[start].tty] : -1;
    if (relay >= 0 && depth < iTermForegroundShellWalkMaximumRelayDepth) {
        const iTermWalkProcess *process = &_processes[relay];
        DLog(@"Job %@ relays terminal %@ through %@ (%s)", @(group), @(process->tty), @(process->pid), process->name);
        BOOL innerFound = NO;
        const pid_t inner = [self shellWithRoot:process->pid
                                          group:process->ttyForegroundProcessGroup
                                          depth:depth + 1
                                          found:&innerFound];
        if (innerFound) {
            DLog(@"Foreground shell is %@, on terminal %@", @(inner), @(process->tty));
            return inner;
        }
        DLog(@"No interactive shell on terminal %@", @(process->tty));
    }
    if (relayed) {
        *found = candidateIsShell;
        return candidateIsShell ? candidate : -1;
    }
    return candidate;
}

// The shell that started the job in `group`, or root if the walk reaches it, or -1 if it can't be
// found (including when the walk leaves the root's tree). *isShell says whether it's an
// interactive shell. *start is the index of the job's process the walk began at.
- (pid_t)shellThatStartedJob:(pid_t)group
                        root:(pid_t)root
                      leader:(NSInteger)leader
                     isShell:(BOOL *)isShell
                       start:(NSInteger *)start {
    const NSInteger rootIndex = [self indexOfPid:root];
    if (group == root) {
        // The root itself runs the job, e.g., the session runs a script, not a shell.
        *start = rootIndex;
        *isShell = NO;
        return root;
    }
    if (leader < 0) {
        // The leader exited while the rest of the job runs (`ps aux | less` once ps finishes), or
        // its pid was reused. The shell that started the job is above any process still in it.
        DLog(@"No leader of process group %@; trying its other members", @(group));
        leader = [self anyMemberOfGroup:group];
        if (leader < 0) {
            DLog(@"No member of process group %@", @(group));
            return -1;
        }
        if (_processes[leader].pid == root) {
            *start = leader;
            *isShell = NO;
            return root;
        }
    }
    *start = leader;
    // Only a shell doing job control puts a command in a new process group, so the nearest
    // ancestor outside the foreground group is the shell that started the foreground job.
    // Subshells and shells running scripts within the job are skipped, whatever their names.
    NSInteger i = leader;
    for (int steps = 0; steps < iTermForegroundShellWalkMaximumAncestors; steps++) {
        const pid_t ppid = _processes[i].ppid;
        if (ppid <= 1) {
            // Not below the root, e.g., the process launchd adopted after its parent exited.
            // Some other shell's directory would be wrong, so give nothing.
            DLog(@"Process group %@ isn't below %@", @(group), @(root));
            return -1;
        }
        if (ppid == root) {
            DLog(@"Reached the root %@ walking up from %@", @(root), @(group));
            *isShell = rootIndex >= 0 && [self isShellAtPrompt:rootIndex];
            return root;
        }
        i = _parents[i];
        if (i < 0) {
            DLog(@"Can't find process %@ while walking up from %@", @(ppid), @(group));
            return -1;
        }
        if (_processes[i].pgid != group) {
            DLog(@"%@ (%s) started the job %@", @(ppid), _processes[i].name, @(group));
            *isShell = [iTermLSOF processNameIsAShell:[NSString stringWithUTF8String:_processes[i].name]];
            return ppid;
        }
    }
    DLog(@"Gave up walking up from %@", @(group));
    return -1;
}

// Prefers a member that still has its parent: one launchd adopted no longer leads to the shell.
- (NSInteger)anyMemberOfGroup:(pid_t)group {
    NSInteger best = -1;
    for (NSInteger i = 0; i < _count; i++) {
        if (_processes[i].pgid != group) {
            continue;
        }
        if (_processes[i].ppid > 1) {
            // The table is sorted, so this has the lowest pid of those with parents.
            return i;
        }
        if (best < 0) {
            best = i;
        }
    }
    return best;
}

// The index of the process at the top of the only other terminal below the job in `group`, which
// is on `tty`, or -1 if there's none or more than one. A process on another terminal is below the
// job if its ancestors reach a member of the job before any process on another terminal, which
// also makes it the topmost on its own: relays nested in it are found by the search on its
// terminal, not counted here. Processes without a terminal (e.g., those Claude Code runs) don't
// count, but what they start does.
- (NSInteger)relayBelowGroup:(pid_t)group tty:(dev_t)tty {
    if (tty == NODEV) {
        return -1;
    }
    [_visitedTTYs addObject:@(tty)];
    NSInteger relay = -1;
    for (NSInteger i = 0; i < _count; i++) {
        if (!iTermWalkProcessIsOnOtherTerminal(&_processes[i], tty) ||
            ![self isBelowGroup:group tty:tty index:i]) {
            continue;
        }
        if (relay >= 0) {
            DLog(@"Both %@ and %@ below job %@ are on other terminals", @(_processes[relay].pid), @(_processes[i].pid), @(group));
            return -1;
        }
        relay = i;
    }
    if (relay < 0) {
        return -1;
    }
    if ([_visitedTTYs containsObject:@(_processes[relay].tty)]) {
        DLog(@"Terminal %@ was already searched", @(_processes[relay].tty));
        return -1;
    }
    if (_processes[relay].ttyForegroundProcessGroup <= 0) {
        DLog(@"Terminal %@ has no foreground process group", @(_processes[relay].tty));
        return -1;
    }
    return relay;
}

// Whether the ancestors of _processes[index] reach a member of `group` before any process on a
// terminal other than `tty`.
- (BOOL)isBelowGroup:(pid_t)group tty:(dev_t)tty index:(NSInteger)index {
    NSInteger i = _parents[index];
    for (int steps = 0; i >= 0 && steps < iTermForegroundShellWalkMaximumAncestors; steps++) {
        const iTermWalkProcess *process = &_processes[i];
        if (process->pgid == group) {
            return YES;
        }
        if (iTermWalkProcessIsOnOtherTerminal(process, tty)) {
            return NO;
        }
        i = _parents[i];
    }
    return NO;
}

@end
