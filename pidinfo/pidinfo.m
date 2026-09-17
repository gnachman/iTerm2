//
//  pidinfo.m
//  pidinfo
//
//  Created by George Nachman on 1/11/20.
//

#import "pidinfo.h"

#import "iTermDirectoryEntry.h"
#import "iTermFileDescriptorServerShared.h"
#import "iTermGitClient.h"
#import "iTermOpenDirectory.h"
#import "iTermPathFinder.h"
#import "pidinfo-Swift.h"
#include <dirent.h>
#include <fcntl.h>
#include <libproc.h>
#include <mach-o/dyld.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <syslog.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

//#define ENABLE_RANDOM_WEDGING 1
//#define ENABLE_VERY_VERBOSE_LOGGING 1
//#define ENABLE_SLOW_ROOT 1

#if ENABLE_RANDOM_WEDGING || ENABLE_VERY_VERBOSE_LOGGING || ENABLE_SLOW_ROOT
#warning DO NOT SUBMIT - DEBUG SETTING ENABLED
#endif

@interface iTermGitRecentBranch: NSObject
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, copy) NSString *branch;
@end

@implementation iTermGitRecentBranch

- (NSComparisonResult)compare:(iTermGitRecentBranch *)other {
    return [self.date compare:other.date];
}

@end

@implementation pidinfo {
    dispatch_queue_t _queue;
    int _numWedged;
    _Atomic int _count;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.iterm2.pidinfo", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)runShellScript:(NSString *)script
                 shell:(NSString *)shell
           interactive:(BOOL)interactive
             withReply:(void (^)(NSData * _Nullable, NSData * _Nullable, int))reply {
    // 20s watchdog: above reallyRunShellScript's own 15s deadline, so in the
    // normal wedge case that method terminates the shell and replies first, and
    // this watchdog is only a backstop if the deadline logic itself fails.
    [self performRiskyBlockWithTimeout:20 block:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            // Watchdog fired: the shell wedged. Report a distinct negative
            // status so callers can tell this from a clean run (status 0).
            reply(nil, nil, -2);
            syslog(LOG_WARNING, "pidinfo wedged while running script");
            return;
        }
        [self reallyRunShellScript:script shell:shell interactive:interactive completion:^(NSData *output,
                                                                                           NSData *error,
                                                                                           int status) {
            if (!completion()) {
                syslog(LOG_INFO, "runShellScript finished after timing out");
                return;
            }
            reply(output, error, status);
        }];
    }];
}

static int MakeNonBlocking(int fd) {
    int flags = fcntl(fd, F_GETFL);
    int rc = 0;
    do {
        rc = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    } while (rc == -1 && errno == EINTR);
    return rc == -1;
}

// Cap on captured stdout/stderr. A producer that never stops (`yes`, `cat
// /dev/zero`, a runaway rc file) must not grow our buffers without bound.
static const NSUInteger kMaxShellOutputBytes = 1048576;  // 1 MB

typedef NS_ENUM(int, DrainResult) {
    DrainResultPending,  // no data right now, or hit the per-call budget: keep polling
    DrainResultDone,     // fd is finished (EOF or a hard read error): drop from the select set
};

// Drains what is currently readable on a nonblocking fd into `sink` (or discards
// it when sink is nil).
//
// Always bounded, whether or not there is a sink: it reads at most a fixed number
// of chunks per call and then returns DrainResultPending, so control returns to
// the caller's deadline / output-cap / process-exit checks even against a
// producer that keeps the fd perpetually readable (e.g. a backgrounded rc daemon
// spewing to the inherited stdout, where read never returns EAGAIN). The earlier
// version only bounded the sink case and would spin forever on a nil-sink discard
// drain.
//
// Returns DrainResultDone on EOF or a hard read error (anything but EINTR/EAGAIN,
// e.g. EIO) so the caller drops the fd from the select set instead of busy-
// spinning on a fd that select keeps reporting readable.
static DrainResult DrainFDNonBlocking(int fd, NSMutableData * _Nullable sink) {
    char buffer[65536];
    const int maxReadsPerCall = 64;  // 64 * 64 KB = 4 MB before yielding to the caller
    for (int i = 0; i < maxReadsPerCall; i++) {
        if (sink && sink.length > kMaxShellOutputBytes) {
            return DrainResultPending;  // over cap; caller notices and terminates the shell
        }
        const ssize_t n = read(fd, buffer, sizeof(buffer));
        if (n > 0) {
            if (sink) {
                [sink appendBytes:buffer length:n];
            }
            continue;
        }
        if (n == 0) {
            return DrainResultDone;  // EOF
        }
        // n < 0
        if (errno == EINTR) {
            continue;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return DrainResultPending;  // no data available now
        }
        return DrainResultDone;  // hard error (EIO, EBADF, …): treat the fd as finished
    }
    return DrainResultPending;  // hit the per-call budget; more may remain
}

// Runs `script` in the user's login shell. When `interactive` is YES the shell
// runs with -i so it sources the user's interactive rc files (.zshrc/.bashrc/
// config.fish/etc.), where CLAUDE_CONFIG_DIR and similar are usually set; a bare
// -c shell sources none of those (zsh sources only .zshenv, bash nothing). Pass
// NO for the fast path (PATH/SSH_AUTH_SOCK come from the exported environment),
// since sourcing a heavy rc costs seconds and, with no controlling tty, also
// prints job-control complaints to stderr.
//
// Either way, the command's OWN stdout is redirected to a private FIFO in an
// unguessable 0700 mkdtemp directory. In interactive mode this is essential: rc
// files and shell greetings/banners (fish_greeting, oh-my-zsh nags, MOTD echoes,
// the xonsh banner) freely write to stdout and would otherwise corrupt the
// captured output. Whatever they print lands on the shell's real stdout, which we
// drain and discard, so `output` is the exact command output on every shell. (In
// non-interactive mode there is no such noise, but the FIFO is harmless.)
//
// Completion is detected from the SHELL PROCESS exiting (polled), NOT from its
// stdout/stderr pipes reaching EOF: interactive rc files routinely background a
// long-lived daemon (ssh-agent, gpg-agent, powerline-daemon, any `foo &`) that
// inherits the shell's stdout/stderr write ends and keeps them open after the
// shell itself exits, so those pipes may never EOF.
//
// A negative status distinguishes "could not run to completion" from a real run:
// -1 for the >1 MB-output kill, and -2 for everything else we abort ourselves
// (setup failure of temp dir / FIFO / launch, the 15s deadline kill, or a select
// error), versus the shell's own >= 0 exit status on success.
- (void)reallyRunShellScript:(NSString *)script shell:(NSString *)shell interactive:(BOOL)interactive completion:(void (^)(NSData * _Nullable, NSData * _Nullable, int))completion {
    // Unguessable, private (0700) working directory holding both the script file
    // and the output FIFO. mkdtemp gives us the unguessable name and tight perms.
    NSString *dirTemplate =
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"iTerm2-shellrun.XXXXXXXX"];
    char *dirBuf = strdup(dirTemplate.fileSystemRepresentation);
    if (!dirBuf) {
        completion(nil, nil, -2);
        return;
    }
    char *dir = mkdtemp(dirBuf);
    if (!dir) {
        free(dirBuf);
        completion(nil, nil, -2);
        return;
    }
    NSString *dirPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:dir
                                                                                    length:strlen(dir)];
    free(dirBuf);

    // Everything below runs the command and fills these; completion is called
    // exactly once, after the @try and after cleanup, so a throwing reply block
    // (which would trigger @catch) can never double-invoke it.
    int fifoReadFD = -1;
    int fifoWriteFD = -1;
    NSTask *task = nil;
    NSData *resultOutput = nil;
    NSData *resultError = nil;
    int resultStatus = 0;
    BOOL ok = NO;

    @try {
        // do/while(0): a setup failure `break`s to cleanup without calling
        // completion here (keeping completion single-call).
        do {
            NSString *fifoPath = [dirPath stringByAppendingPathComponent:@"out"];
            // The redirect below single-quotes this path. A single-quoted string
            // containing no single quote is a literal in bash/zsh/tcsh/fish/xonsh
            // alike, so this is portable and doesn't depend on TMPDIR being free
            // of spaces or metacharacters. The one thing single-quoting can't
            // survive is an embedded single quote, so bail if the path has one
            // (it never should: it's TMPDIR + an mkdtemp alphanumeric suffix +
            // "/out").
            if ([fifoPath containsString:@"'"]) {
                break;
            }
            if (mkfifo(fifoPath.fileSystemRepresentation, 0600) != 0) {
                break;
            }

            NSString *scriptPath = [dirPath stringByAppendingPathComponent:@"script"];
            // Redirect ONLY the command's stdout to the FIFO. rc-file/banner output,
            // which was written to the shell's stdout before this command runs, is
            // left on the shell's real stdout (drained and discarded below).
            // PRECONDITION (see the protocol header): `script` is a SINGLE command.
            // Appending `> fifo` binds to the last command only, so in a compound
            // script (`a && b`, `a; b`) earlier output would be silently dropped.
            // Making the redirect wrap the whole script is not portable across the
            // shells we support (`{ …; }` breaks fish/csh), hence the precondition.
            NSString *trimmed =
                [script stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *fullScript = [NSString stringWithFormat:@"%@ > '%@'\n", trimmed, fifoPath];
            NSError *writeError = nil;
            [fullScript writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
            if (writeError) {
                break;
            }
            chmod(scriptPath.fileSystemRepresentation, 0700);

            // Open the read end nonblocking (so the open itself doesn't wait for a
            // writer), plus a write end we hold open for the whole run. The held
            // writer keeps the read end from ever reporting EOF, so a nonblocking
            // read of the FIFO returns EAGAIN (not 0) when momentarily empty.
            fifoReadFD = open(fifoPath.fileSystemRepresentation, O_RDONLY | O_NONBLOCK);
            if (fifoReadFD < 0) {
                break;
            }
            fifoWriteFD = open(fifoPath.fileSystemRepresentation, O_WRONLY | O_NONBLOCK);
            if (fifoWriteFD < 0) {
                break;
            }

            task = [[NSTask alloc] init];
            task.launchPath = shell;
            task.arguments = interactive ? @[ @"-i", @"-c", scriptPath ] : @[ @"-c", scriptPath ];
            // Null stdin: an interactive shell must not block trying to read input.
            task.standardInput = [NSFileHandle fileHandleWithNullDevice];
            NSPipe *outputPipe = [[NSPipe alloc] init];  // rc/banner noise: drained and discarded
            NSPipe *errorPipe = [[NSPipe alloc] init];
            task.standardOutput = outputPipe;
            task.standardError = errorPipe;

            [task launch];

            const int shellOutFD = outputPipe.fileHandleForReading.fileDescriptor;
            const int shellErrFD = errorPipe.fileHandleForReading.fileDescriptor;
            MakeNonBlocking(shellOutFD);
            MakeNonBlocking(shellErrFD);

            NSMutableData *accumulatedOutput = [[NSMutableData alloc] init];
            NSMutableData *accumulatedError = [[NSMutableData alloc] init];
            // 0 = ran to completion; -1 = killed for exceeding the output cap;
            // -2 = killed for exceeding the wall-clock deadline.
            int failureStatus = 0;
            BOOL shellOutEOF = NO;
            BOOL shellErrEOF = NO;
            BOOL fifoDone = NO;
            // Hard wall-clock deadline. An interactive (-i) shell sources the
            // user's full rc, which can hang indefinitely (a network-mounted
            // prompt hook, a `read` in a conditional, conda on a slow volume),
            // and our own poll loop has no other way to stop. Kept below the
            // performRiskyBlock watchdog (20s, set on the runShellScript entry)
            // so we terminate and clean up ourselves before the watchdog gives
            // up — otherwise the process, this thread, the FIFO, and the temp
            // dir would leak permanently and completion would never fire.
            const NSTimeInterval deadline =
                [NSProcessInfo processInfo].systemUptime + 15.0;

            // Poll: select with a short timeout so we periodically re-check
            // whether the shell process has exited, then drain whatever is
            // readable. We can't wait for the pipes to EOF (a backgrounded rc
            // daemon may hold them open forever), so process exit is the signal.
            // Once a fd is finished (EOF, or a hard read error) we drop it from
            // the set, otherwise it stays perpetually select-readable and would
            // busy-spin. The FIFO normally never finishes (the held writer keeps
            // it from EOF) so it only wakes on real data; but it too is dropped
            // on a hard error, or it would spin to the deadline. The loop still
            // terminates on process exit, so dropping every fd is harmless.
            while (1) {
                fd_set readset;
                FD_ZERO(&readset);
                int maxFD = -1;
                if (!fifoDone) {
                    FD_SET(fifoReadFD, &readset);
                    if (fifoReadFD > maxFD) { maxFD = fifoReadFD; }
                }
                if (!shellOutEOF) {
                    FD_SET(shellOutFD, &readset);
                    if (shellOutFD > maxFD) { maxFD = shellOutFD; }
                }
                if (!shellErrEOF) {
                    FD_SET(shellErrFD, &readset);
                    if (shellErrFD > maxFD) { maxFD = shellErrFD; }
                }
                struct timeval tv = { .tv_sec = 0, .tv_usec = 100000 };  // 100 ms
                // nfds is maxFD + 1; 0 (all fds dropped) makes select a plain
                // 100 ms sleep, after which the exit/deadline checks still run.
                const int selected = select(maxFD + 1, &readset, NULL, NULL, &tv);
                if (selected > 0) {
                    if (!fifoDone && FD_ISSET(fifoReadFD, &readset)) {
                        fifoDone = (DrainFDNonBlocking(fifoReadFD, accumulatedOutput) == DrainResultDone);
                    }
                    if (!shellOutEOF && FD_ISSET(shellOutFD, &readset)) {
                        shellOutEOF = (DrainFDNonBlocking(shellOutFD, nil) == DrainResultDone);  // rc/banner noise
                    }
                    if (!shellErrEOF && FD_ISSET(shellErrFD, &readset)) {
                        shellErrEOF = (DrainFDNonBlocking(shellErrFD, accumulatedError) == DrainResultDone);
                    }
                } else if (selected < 0 && errno != EINTR) {
                    // Our own polling broke; we have NOT observed the shell
                    // exit. Terminate and take the grace/kill path rather than
                    // falling through to a waitUntilExit that could block on a
                    // still-running shell forever.
                    syslog(LOG_WARNING, "pidinfo: select failed (%s); terminating shell", strerror(errno));
                    [task terminate];
                    failureStatus = -2;
                    break;
                }
                if (accumulatedOutput.length > kMaxShellOutputBytes ||
                    accumulatedError.length > kMaxShellOutputBytes) {
                    [task terminate];
                    failureStatus = -1;
                    break;
                }
                if ([NSProcessInfo processInfo].systemUptime > deadline) {
                    syslog(LOG_WARNING, "pidinfo: shell script exceeded deadline; terminating");
                    [task terminate];
                    failureStatus = -2;
                    break;
                }
                if (!task.isRunning) {
                    // Shell exited. One last nonblocking drain to pick up bytes
                    // buffered in the FIFO/pipes between the final select and now.
                    DrainFDNonBlocking(fifoReadFD, accumulatedOutput);
                    DrainFDNonBlocking(shellOutFD, nil);
                    DrainFDNonBlocking(shellErrFD, accumulatedError);
                    break;
                }
            }

            if (failureStatus != 0) {
                // We SIGTERM'd the shell. Give it a short grace to die, then
                // SIGKILL so a shell ignoring SIGTERM can't linger. Don't
                // waitUntilExit unconditionally (it could block); the fds close
                // below and any writer hits EPIPE on the gone FIFO.
                const NSTimeInterval graceEnd =
                    [NSProcessInfo processInfo].systemUptime + 1.0;
                while (task.isRunning &&
                       [NSProcessInfo processInfo].systemUptime < graceEnd) {
                    usleep(50000);  // 50 ms
                }
                if (task.isRunning) {
                    kill(task.processIdentifier, SIGKILL);
                }
                resultStatus = failureStatus;  // resultOutput/Error stay nil
                ok = YES;
            } else {
                [task waitUntilExit];
                resultOutput = accumulatedOutput;
                resultError = accumulatedError;
                resultStatus = (int)task.terminationStatus;
                ok = YES;
            }
        } while (0);
    } @catch (NSException *exception) {
        ok = NO;
    }

    if (fifoReadFD >= 0) {
        close(fifoReadFD);
    }
    if (fifoWriteFD >= 0) {
        close(fifoWriteFD);
    }
    [[NSFileManager defaultManager] removeItemAtPath:dirPath error:nil];

    if (ok) {
        completion(resultOutput, resultError, resultStatus);
    } else {
        // Setup failure (do/while break) or a launch exception: "could not run",
        // distinct from a clean run's >= 0 status.
        completion(nil, nil, -2);
    }
}

- (void)getProcessInfoForProcessID:(NSNumber *)pid
                            flavor:(NSNumber *)flavor
                               arg:(NSNumber *)arg
                              size:(NSNumber *)size
                             reqid:(int)reqid
                         withReply:(void (^)(NSNumber *, NSData *))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^completion)(void)) {
        if (!shouldPerform) {
            reply(@-1, [NSData data]);
            syslog(LOG_WARNING,
                   "pidinfo %d detected wedged proc_pidinfo for process ID %d, flavor %d. Count is %d.",
                   reqid, pid.intValue, flavor.intValue, self->_numWedged);
            return;
        }
        [self reallyGetProcessInfoForProcessID:pid flavor:flavor arg:arg size:size reqid:reqid withReply:^(NSNumber *number, NSData *data) {
            if (!completion()) {
                syslog(LOG_INFO, "pidinfo reqid %d finished after timing out", reqid);
                return;
            }
            reply(number, data);
        }];
    }];
}

- (void)checkIfDirectoryExists:(NSString *)directory withReply:(void (^)(NSNumber * _Nullable))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil);
            return;
        }
        BOOL isDirectory = NO;
        const BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&isDirectory];
        if (!completion()) {
            return;
        }
        NSNumber *result = @(exists && isDirectory);
        reply(result);
    }];
}

- (void)statFile:(NSString *)path
       withReply:(void (^)(struct stat statbuf, int error))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        struct stat buf = { 0 };
        if (!shouldPerform) {
            reply(buf, -1);
            return;
        }
        const int rc = stat([path stringByExpandingTildeInPath].UTF8String, &buf);
        const int error = (rc == 0) ? 0 : errno;
        
        if (!completion()) {
            return;
        }
        reply(buf, error);
    }];
}

BOOL FileIsRegularExecutableFile(NSString *filename) {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Resolve symbolic links
    NSString *resolvedPath = [fileManager destinationOfSymbolicLinkAtPath:filename error:nil];
    if (resolvedPath) {
        if (![resolvedPath hasPrefix:@"/"]) {
            // Make the resolved path absolute
            NSString *symlinkDir = [filename stringByDeletingLastPathComponent];
            resolvedPath = [symlinkDir stringByAppendingPathComponent:resolvedPath];
            resolvedPath = [resolvedPath stringByStandardizingPath]; // Resolve ".." and "." path components
        }
        filename = resolvedPath;
    }

    NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:filename error:nil];
    if (fileAttributes) {
        NSString *fileType = [fileAttributes objectForKey:NSFileType];

        if ([fileType isEqualToString:NSFileTypeRegular]) {
            return [fileManager isExecutableFileAtPath:filename];
        }
    }
    return NO;
}

static BOOL FileIsRegularExecutableFileUsingSearchPathsIfNeeded(NSString *filename,
                                                                NSArray<NSString *> *paths) {
    if ([filename hasPrefix:@"/"]) {
        return FileIsRegularExecutableFile(filename);
    }
    // Search $PATH
    for (NSString *path in paths) {
        NSString *fullPath = [path stringByAppendingPathComponent:filename];

        if (FileIsRegularExecutableFile(fullPath)) {
            return YES;
        }
    }
    return NO;
}

- (void)checkIfExecutableRegularFile:(NSString *)filename
                         searchPaths:(NSArray<NSString *> *)searchPaths
                           withReply:(void (^)(NSNumber * _Nullable exists))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil);
            return;
        }
        const BOOL exists = FileIsRegularExecutableFileUsingSearchPathsIfNeeded(filename, searchPaths);
        if (!completion()) {
            return;
        }
        NSNumber *result = @(exists);
        reply(result);
    }];
}

// Usage:
// [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^completion)(void)) {
//   if (!shouldPerform) {
//     reply(FAILURE);
//     return;
//   }
//   [self doSlowOperationWithCompletion:^{
//     if (!completion()) {
//       return;
//     }
//     reply(SUCCESS);
//   }];
// }];
- (void)performRiskyBlock:(void (^)(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)))block {
#if DEBUG
    const NSTimeInterval timeout = 30;
#else
    const NSTimeInterval timeout = 10;
#endif
    [self performRiskyBlockWithTimeout:timeout block:block];
}

- (void)performRiskyBlockWithTimeout:(NSTimeInterval)timeout
                               block:(void (^)(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)))block {
    __block _Atomic BOOL done = NO;
    __block _Atomic BOOL wedged = NO;
    _count++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(timeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (done) {
            return;
        }
        wedged = YES;
        block(NO, nil);
        self->_numWedged++;

        if (self->_numWedged > 128) {
            syslog(LOG_ERR, "There are more than 128 wedged threads. Restarting.");
            _exit(0);
        }
    });
    dispatch_async(_queue, ^{
        block(YES, ^{
            self->_count--;
            if (wedged) {
              // Finished after timeout.
              self->_numWedged--;
              syslog(LOG_INFO,
                     "pidinfo detected slow but not wedged proc_pidinfo. Count is now %d.",
                     self->_numWedged);
                return NO;
            }
            done = YES;
            return YES;
        });
    });
}

- (void)handshakeWithReply:(void (^)(void))reply {
    reply();
}

#if ENABLE_VERY_VERBOSE_LOGGING
static double TimespecToSeconds(struct timespec* ts) {
    return (double)ts->tv_sec + (double)ts->tv_nsec / 1000000000.0;
}
#endif

#if ENABLE_SLOW_ROOT
- (void)maybeDelayWithFlavor:(int)flavor
                       reqid:(int)reqid
                      result:(NSData *)result {
    if (flavor != PROC_PIDVNODEPATHINFO) {
        return;
    }
    if (result.length != sizeof(struct proc_vnodepathinfo)) {
        return;
    }
    struct proc_vnodepathinfo *vpiPtr = (struct proc_vnodepathinfo *)result.bytes;
    NSString *rawDir = [NSString stringWithUTF8String:vpiPtr->pvi_cdir.vip_path];
    if (![rawDir isEqualToString:@"/"]) {
        return;
    }
    syslog(LOG_ERR, "pidinfo %d responding slowly because directory is root.", reqid);
    [NSThread sleepForTimeInterval:0.25];
}
#endif

- (void)reallyGetProcessInfoForProcessID:(NSNumber *)pid
                                  flavor:(NSNumber *)flavor
                                     arg:(NSNumber *)arg
                                    size:(NSNumber *)size
                                   reqid:(int)reqid
                               withReply:(void (^)(NSNumber *, NSData *))reply {
    if (size.doubleValue > 1024 * 1024 || size.doubleValue < 0) {
        dispatch_async(dispatch_get_main_queue(), ^{ reply(@-2, [NSData data]); });
        return;
    }
    const int safeLength = size.intValue;
    NSMutableData *result = [NSMutableData dataWithLength:size.unsignedIntegerValue];
#if ENABLE_VERY_VERBOSE_LOGGING
    syslog(LOG_DEBUG, "pidinfo %d will call proc_pidinfo(pid=%d, flavor=%d). wedged=%d count=%d",
           reqid, pid.intValue, flavor.intValue, _numWedged, _count);
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
#endif
#if ENABLE_RANDOM_WEDGING
    if (random() % 10 == 0) {
        syslog(LOG_WARNING, "pidinfo will wedge this thread intentionally.");
        while (1) {
            sleep(1);
        }
    }
#endif
    const int rc = proc_pidinfo(pid.intValue,
                                flavor.intValue,
                                arg.unsignedIntegerValue,
                                (size.integerValue > 0) ? result.mutableBytes : NULL,
                                safeLength);
    if (rc <= 0) {
        const int copyOfErrno = errno;
        NSString *message = [NSString stringWithFormat:@"proc_pidinfo flavor=%@ pid=%@ arg=%@ size=%@ returned %@ with errno %@",
                             flavor, pid, arg, size, @(rc), @(copyOfErrno)];
        syslog(LOG_WARNING, "%s", message.UTF8String);
    }
#if ENABLE_SLOW_ROOT
    if (rc > 0) {
        [self maybeDelayWithFlavor:flavor.intValue
                             reqid:reqid
                            result:result];
    }
#endif
    struct timespec end;
    clock_gettime(CLOCK_MONOTONIC, &end);
#if ENABLE_VERY_VERBOSE_LOGGING
    const int ms = (TimespecToSeconds(&end)-TimespecToSeconds(&start)) * 1000;
    syslog(LOG_DEBUG, "pidinfo %d finished proc_pidinfo(pid=%d, flavor=%d) in %dms",
           reqid, pid.intValue, flavor.intValue, ms);
#endif
    dispatch_async(dispatch_get_main_queue(), ^{ reply(@(rc), result); });
}

// When folders is true we only return folders. When it's false, we return anything.
- (NSArray<NSString *> *)contentsOfDirectory:(NSString *)directory
                                  withPrefix:(NSString *)prefix
                                  executable:(BOOL)executable 
                                     folders:(BOOL)folders {
    NSArray<NSString *> *relative = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] ?: @[];
    NSMutableArray<NSString*> *result = [NSMutableArray array];
    for (NSString *path in relative) {
        if (prefix.length == 0 || [path.lastPathComponent hasPrefix:prefix]) {
            NSString *fullPath = [directory stringByAppendingPathComponent:path];
            if (!executable || [[NSFileManager defaultManager] isExecutableFileAtPath:fullPath]) {
                if (!folders || [self fileIsFolder:fullPath]) {
                    [result addObject:fullPath];
                }
            }
        }
    }
    return result;
}

- (BOOL)fileIsFolder:(NSString *)path {
    BOOL isFolder = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isFolder]) {
        return NO;
    }
    return isFolder;
}

- (NSArray<NSString *> *)reallyFindCompletionsWithPrefix:(NSString *)prefix
                                             inDirectory:(NSString *)directory
                                                maxCount:(NSInteger)maxCount
                                              executable:(BOOL)executable
                                                 folders:(BOOL)folders {
    if (![prefix hasPrefix:@"/"] && [directory hasPrefix:@"/"]) {
        // Can't use stringByAppendingPathComponent: because it doesn't do anything if prefix is
        // empty and we always want to append a / to directory.
        NSArray<NSString *> *temp = [self reallyFindCompletionsWithPrefix:[NSString stringWithFormat:@"%@/%@", directory, prefix]
                                                              inDirectory:@""
                                                                 maxCount:maxCount
                                                               executable:executable
                                                                  folders:folders];
        NSString *prefixToRemove = [directory hasSuffix:@"/"] ? directory : [directory stringByAppendingString:@"/"];
        return [self array:temp byRemovingPrefix:prefixToRemove];
    }

    // If prefix is the exact name of a directory, return its contents.
    if ([prefix hasSuffix:@"/"]) {
        return [self contentsOfDirectory:prefix 
                              withPrefix:@""
                              executable:executable
                                 folders:folders];
    }

    NSMutableArray<NSString *> *results = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    const BOOL exists = [fm fileExistsAtPath:prefix isDirectory:&isDirectory];
    if (exists && isDirectory) {
        [results addObject:[prefix stringByAppendingString:@"/"]];
    }

    NSString *container = [prefix stringByDeletingLastPathComponent];
    if (container.length == 0) {
        return results;
    }

    [results addObjectsFromArray:[self contentsOfDirectory:container
                                                withPrefix:prefix.lastPathComponent
                                                executable:executable
                                                   folders:folders]];
    return results;
}

- (void)findCompletionsWithPrefix:(NSString *)prefix
                    inDirectories:(NSArray<NSString *> *)directories
                              pwd:(NSString *)pwd
                         maxCount:(NSInteger)maxCount
                       executable:(BOOL)executable
                        withReply:(void (^)(NSArray<NSString *> *))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil);
            syslog(LOG_WARNING, "pidinfo wedged while searching for completions");
            return;
        }
        if (prefix.length == 0) {
            reply(@[]);
            return;
        }
        NSMutableArray<NSString *> *combined = [NSMutableArray array];

        // Seach for subdirectories.
        NSArray<NSString *> *temp = [[self reallyFindCompletionsWithPrefix:prefix
                                                               inDirectory:pwd
                                                                  maxCount:maxCount
                                                                executable:YES
                                                                   folders:YES] sortedArrayUsingSelector:@selector(compare:)];
        [combined addObjectsFromArray:[self array:temp byRemovingPrefix:prefix]];

        // Search each provided directory.
        for (NSString *relativeDirectory in directories) {
            NSString *directory;
            if ([relativeDirectory hasPrefix:@"/"]) {
                directory = relativeDirectory;
            } else {
                if (!pwd) {
                    continue;
                }
                directory = [pwd stringByAppendingPathComponent:relativeDirectory];
            }
            NSArray<NSString *> *temp = [[self reallyFindCompletionsWithPrefix:prefix
                                                                   inDirectory:directory
                                                                      maxCount:maxCount
                                                                    executable:executable
                                                                       folders:NO] sortedArrayUsingSelector:@selector(compare:)];
            [combined addObjectsFromArray:[self array:temp byRemovingPrefix:prefix]];
            if (combined.count > maxCount) {
                break;
            }
        }
        NSArray<NSString *> *completions = combined;
        if (completions.count > maxCount) {
            completions = [completions subarrayWithRange:NSMakeRange(0, maxCount)];
        }
        if (!completion()) {
            syslog(LOG_INFO, "findCompletions finished after timing out");
            return;
        }
        reply(completions);
    }];
}

- (NSArray<NSString *> *)array:(NSArray<NSString *> *)input byRemovingPrefix:(NSString *)prefix {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *fq in input) {
        NSString *truncated = [fq substringFromIndex:prefix.length];
        if (truncated.length > 0) {
            [result addObject:truncated];
        }
    }
    return result;
}

- (void)setPriority:(int)newPriority {
    int rc = setpriority(PRIO_PROCESS, 0, newPriority);
    if (rc) {
        syslog(LOG_ERR, "setpriority(%d): %s", newPriority, strerror(errno));
    }
}

static const char *GetPathToSelf(void) {
    // First ask how much memory we need to store the path.
    uint32_t size = 0;
    char placeholder[1];
    _NSGetExecutablePath(placeholder, &size);

    // Allocate memory and get the path and return it. Plus an extra byte because I live in fear.
    char *pathToExecutable = malloc(size + 1);
    if (_NSGetExecutablePath(pathToExecutable, &size) != 0) {
        free(pathToExecutable);
        return nil;
    }

    return pathToExecutable;
}

- (void)requestGitStateForPath:(NSString *)path
                       gitBase:(NSString * _Nullable)gitBase
                       timeout:(int)timeout
              includeDiffStats:(BOOL)includeDiffStats
                    completion:(void (^)(iTermGitState * _Nullable, BOOL timedOut))reply {
    // The git subprocess SIGKILLs itself at `timeout` seconds; give the wedge watchdog that long
    // plus a small grace for fork/XPC overhead so it doesn't fire before the subprocess can
    // finish. The default performRiskyBlock watchdog (10s release / 30s debug) is sized for
    // proc_pidinfo calls and would spuriously report "wedged" for any git timeout above those
    // values.
    const NSTimeInterval wedgeTimeout = MAX((NSTimeInterval)timeout + 5, 10);
    [self performRiskyBlockWithTimeout:wedgeTimeout block:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil, YES);
            syslog(LOG_WARNING, "pidinfo wedged");
            return;
        }

        NSPipe *pipe = [NSPipe pipe];

        NSTask *task = [[NSTask alloc] init];
        const char *pathToSelf = GetPathToSelf();
        task.launchPath = [NSString stringWithCString:pathToSelf
                                             encoding:NSUTF8StringEncoding];
        if (pathToSelf) {
            free((void *)pathToSelf);
        }
        // Empty string means "no override" downstream — keeps the
        // arg vector positional so the child can branch on
        // gitBase.length. Trim for safety: a stray newline coming
        // from a free-form text field would land inside argv.
        NSString *trimmedBase = [gitBase ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        task.arguments = @[ @"--git-state",
                            path,
                            [@(timeout) stringValue],
                            includeDiffStats ? @"1" : @"0",
                            trimmedBase ];
        task.standardOutput = pipe;
        @try {
            [task launch];
        } @catch (NSException *exception) {
            syslog(LOG_ERR, "Exception when launch git state fetcher: %s", exception.description.UTF8String);
            reply(nil, NO);
            completion();
            return;
        }

        const pid_t childPID = task.processIdentifier;
        iTermCPUGovernor *governor = [[iTermCPUGovernor alloc] initWithPID:childPID
                                                                 dutyCycle:0.5];
        // Allow 100% CPU utilization for the first x seconds.
        [governor setGracePeriodDuration:1.0];
        const NSInteger token = [governor incr];
        NSFileHandle *fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:pipe.fileHandleForReading.fileDescriptor
                                                                 closeOnDealloc:YES];
        [task waitUntilExit];
        [governor decr:token];
        if (task.terminationReason == NSTaskTerminationReasonUncaughtSignal) {
            // The child was killed by SIGKILL from its own timeout watchdog (see
            // PIDInfoGitState.m). Don't read output because it may be incomplete.
            reply(nil, YES);
            completion();
            return;
        }

        NSData *data = [fileHandle readDataToEndOfFile];
        NSError *error = nil;
        NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
        if (!decoder) {
            reply(nil, NO);
            completion();
            return;
        }

        iTermGitState *state = [decoder decodeTopLevelObjectOfClass:[iTermGitState class]
                                                             forKey:@"state"
                                                              error:nil];
        reply(state, NO);
        completion();
    }];
}

- (void)fetchRecentBranchesAt:(NSString *)path count:(NSInteger)maxCount completion:(void (^)(NSArray<NSString *> *))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil);
            syslog(LOG_WARNING, "pidinfo wedged");
            return;
        }
        [self setPriority:20];
        reply([self recentBranchesAt:path count:maxCount]);
        completion();
    }];
}

- (NSArray<NSString *> *)recentBranchesAt:(NSString *)path count:(NSInteger)maxCount {
    iTermGitClient *client = [[iTermGitClient alloc] initWithRepoPath:path];
    if (!client) {
        return nil;
    }
    // git for-each-ref --count=maxCount --sort=-commiterdate refs/heads/ --format=%(refname:short)
    NSMutableArray<iTermGitRecentBranch *> *recentBranches = [NSMutableArray array];
    NSMutableSet<NSString *> *shortNames = [NSMutableSet set];
    [client forEachReference:^(git_reference * _Nonnull ref, BOOL * _Nonnull stop) {
        NSString *fullName = [client fullNameForReference:ref];
        if (![iTermGitClient name:fullName matchesPattern:@"refs/heads"]) {
            NSLog(@"%@ does not match pattern", fullName);
            return;
        }
        NSString *shortName = [client shortNameForReference:ref];
        if (!shortName) {
            return;
        }
        if ([shortNames containsObject:shortName]) {
            return;
        }
        [shortNames addObject:shortName];
        iTermGitRecentBranch *rb = [[iTermGitRecentBranch alloc] init];
        rb.date = [client commiterDateAt:ref];
        NSLog(@"MATCHED: %@ %@", shortName, rb.date);
        rb.branch = shortName;
        [recentBranches addObject:rb];
    }];
    [recentBranches sortUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    for (iTermGitRecentBranch *rb in recentBranches.reverseObjectEnumerator) {
        [results addObject:rb.branch];
        if (results.count == maxCount) {
            break;
        }
    }
    return results;
}

void iTermMutatePathFindersDict(void (^NS_NOESCAPE block)(NSMutableDictionary<NSNumber *, iTermPathFinder *> *dict)) {
    static NSMutableDictionary<NSNumber *, iTermPathFinder *> *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [NSMutableDictionary dictionary];
    });
    @synchronized (instance) {
        block(instance);
    }
}

- (void)findExistingFileWithPrefix:(NSString *)prefix
                            suffix:(NSString *)suffix
                  workingDirectory:(NSString *)workingDirectory
                    trimWhitespace:(BOOL)trimWhitespace
                     pathsToIgnore:(NSString *)pathsToIgnore
                allowNetworkMounts:(BOOL)allowNetworkMounts
                             reqid:(int)reqid
                             reply:(void (^)(NSString *path, int prefixChars, int suffixChars, BOOL workingDirectoryIsLocal))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^completion)(void)) {
        if (!shouldPerform) {
            reply(nil, 0, 0, NO);
            syslog(LOG_WARNING, "pidinfo wedged in findExistingFile %d. count=%d", reqid, self->_numWedged);
            return;
        }

        iTermPathFinder *pathfinder = [[iTermPathFinder alloc] initWithPrefix:prefix
                                                                       suffix:suffix
                                                             workingDirectory:workingDirectory
                                                               trimWhitespace:trimWhitespace
                                                                       ignore:pathsToIgnore
                                                           allowNetworkMounts:allowNetworkMounts];
        pathfinder.reqid = reqid;
        iTermMutatePathFindersDict(^(NSMutableDictionary<NSNumber *, iTermPathFinder *> *dict) {
            dict[@(reqid)] = pathfinder;
        });
        pathfinder.fileManager = [NSFileManager defaultManager];
        __weak __typeof(pathfinder) weakPathfinder = pathfinder;
        DLog(@"[%d] Start %@ + %@", reqid,
             [prefix substringFromIndex:MAX(10, prefix.length) - 10],
             [suffix substringToIndex:MIN(suffix.length, 10)]);
        [pathfinder searchSynchronously];
        if (!completion()) {
            syslog(LOG_INFO, "findExistingFile %d finished after timing out.", reqid);
        }
        DLog(@"[%d] Finish with result %@", reqid, weakPathfinder.path);
        reply(weakPathfinder.path,
              weakPathfinder.prefixChars,
              weakPathfinder.suffixChars,
              weakPathfinder.workingDirectoryIsLocal);
    }];
}

- (void)cancelFindExistingFileRequest:(int)reqid reply:(void (^)(void))reply {
    __block iTermPathFinder *pathFinder;
    DLog(@"[%d] Cancel", reqid);
    iTermMutatePathFindersDict(^(NSMutableDictionary<NSNumber *, iTermPathFinder *> *dict) {
        pathFinder = dict[@(reqid)];
        dict[@(reqid)] = nil;
    });
    [pathFinder cancel];
    reply();
}

- (void)executeShellCommand:(NSString *)command
                       args:(NSArray<NSString *> *)args
                        dir:(NSString *)dir
                        env:(NSDictionary<NSString *, NSString *> *)env
                      reply:(void (^)(NSData *stdout,
                                      NSData *stderr,
                                      uint8_t status,
                                      NSTaskTerminationReason reason))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^completion)(void)) {
        if (!shouldPerform) {
            reply(nil, 0, 0, NO);
            syslog(LOG_WARNING, "pidinfo wedged in executeShellCommand. count=%d",
                   self->_numWedged);
            return;
        }

        NSPipe *stdoutPipe = [NSPipe pipe];
        NSPipe *stderrPipe = [NSPipe pipe];
        NSPipe *stdinPipe = [NSPipe pipe];

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = command;
        task.arguments = args;
        task.standardInput = stdinPipe;
        task.standardOutput = stdoutPipe;
        task.standardError = stderrPipe;

        [task launch];

        [stdinPipe.fileHandleForWriting closeFile];
        NSData *stdout = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
        NSData *stderr = [stderrPipe.fileHandleForReading readDataToEndOfFile];

        [task waitUntilExit];

        if (!completion()) {
            syslog(LOG_INFO, "executeShellCommand finished after timing out.");
        }
        DLog(@"Finished with stdout %@", stdout);
        reply(stdout, stderr, task.terminationStatus, task.terminationReason);
    }];
}

- (void)fetchDirectoryListingOfPath:(NSString *)path
                         completion:(void (^)(NSArray<iTermDirectoryEntry *> *entries))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^completion)(void)) {
        if (!shouldPerform) {
            reply(@[]);
            syslog(LOG_WARNING, "pidinfo wedged in fetchDirectoryListingOfPath. count=%d",
                   self->_numWedged);
            return;
        }

        if (!completion()) {
            syslog(LOG_INFO, "fetchDirectoryListingOfPath finished after timing out.");
        }
        reply([self reallyFetchDirectoryListingOfPath:path]);
    }];
}

- (void)fetchUserShellWithReply:(void (^)(NSString * _Nullable))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil);
            syslog(LOG_WARNING,
                   "pidinfo wedged in fetchUserShell. count=%d",
                   self->_numWedged);
            return;
        }
        NSString *shell = [iTermOpenDirectory performBlockingLookup];
        if (!completion()) {
            syslog(LOG_INFO, "fetchUserShell finished after timing out.");
            return;
        }
        reply(shell);
    }];
}

- (NSArray<iTermDirectoryEntry *> *)reallyFetchDirectoryListingOfPath:(NSString *)path {
    NSMutableArray<iTermDirectoryEntry *> *entries = [NSMutableArray array];
    DIR *dir = opendir([path fileSystemRepresentation]);
    if (!dir) {
        return entries;
    }
    struct dirent *dent;
    while ((dent = readdir(dir)) != NULL) {
        NSString *fileName = [NSString stringWithUTF8String:dent->d_name];
        if ([fileName isEqualToString:@"."] || [fileName isEqualToString:@".."]) {
            continue;
        }
        NSString *fullPath = [path stringByAppendingPathComponent:fileName];
        struct stat statBuf;
        if (stat([fullPath fileSystemRepresentation], &statBuf) == 0) {
            iTermDirectoryEntry *entry = [[iTermDirectoryEntry alloc] initWithName:fileName
                                                                           statBuf:statBuf];
            [entries addObject:entry];
        }
    }
    closedir(dir);
    return entries;
}

@end


