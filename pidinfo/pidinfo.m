//
//  pidinfo.m
//  pidinfo
//
//  Created by George Nachman on 1/11/20.
//

#import "pidinfo.h"

#import "iTermFileDescriptorServerShared.h"
#import "iTermGitClient.h"
#import "iTermPathFinder.h"
#import "pidinfo-Swift.h"
#include <libproc.h>
#include <mach-o/dyld.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <syslog.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <time.h>

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
             withReply:(void (^)(NSData * _Nullable, NSData * _Nullable, int))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil, nil, 0);
            syslog(LOG_WARNING, "pidinfo wedged while running script");
            return;
        }
        [self reallyRunShellScript:script shell:shell completion:^(NSData *output,
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

- (NSString *)temporaryFileNameWithPrefix:(NSString *)prefix suffix:(NSString *)suffix {
    assert(strlen(suffix.UTF8String) < INT_MAX);
    NSString *template = [NSString stringWithFormat:@"%@XXXXXX%@", prefix ?: @"", suffix ?: @""];
    NSString *tempFileTemplate =
        [NSTemporaryDirectory() stringByAppendingPathComponent:template];
    const char *tempFileTemplateCString =
        [tempFileTemplate fileSystemRepresentation];
    char *tempFileNameCString = strdup(tempFileTemplateCString);
    int fileDescriptor = mkstemps(tempFileNameCString, (int)strlen(suffix.UTF8String));

    if (fileDescriptor == -1) {
        free(tempFileNameCString);
        return nil;
    }
    close(fileDescriptor);
    NSString *filename = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempFileNameCString
                                                                                     length:strlen(tempFileNameCString)];
    free(tempFileNameCString);
    return filename;
}

static int MakeNonBlocking(int fd) {
    int flags = fcntl(fd, F_GETFL);
    int rc = 0;
    do {
        rc = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    } while (rc == -1 && errno == EINTR);
    return rc == -1;
}

- (void)reallyRunShellScript:(NSString *)script shell:(NSString *)shell completion:(void (^)(NSData * _Nullable, NSData * _Nullable, int))completion {
    @try {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = shell;

        NSString *tempfile = [self temporaryFileNameWithPrefix:@"iTerm2-script" suffix:@"sh"];
        NSError *error = nil;
        [script writeToFile:tempfile atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            completion(nil, nil, 0);
            return;
        }
        chmod(tempfile.UTF8String, 0700);
        task.arguments = @[ @"-c", tempfile ];

        NSPipe *stdinPipe = [[NSPipe alloc] init];
        NSPipe *outputPipe = [[NSPipe alloc] init];
        NSPipe *errorPipe = [[NSPipe alloc] init];
        task.standardInput = stdinPipe;
        task.standardOutput = outputPipe;
        task.standardError = errorPipe;

        [task launch];

        NSFileHandle *outputHandle = outputPipe.fileHandleForReading;
        NSFileHandle *errorHandle = errorPipe.fileHandleForReading;
        NSMutableData *accumulatedOutput = [[NSMutableData alloc] init];
        NSMutableData *accumulatedError = [[NSMutableData alloc] init];

        MakeNonBlocking(outputHandle.fileDescriptor);
        MakeNonBlocking(errorHandle.fileDescriptor);

        while (1) {
            int fds[2] = { outputHandle.fileDescriptor, errorHandle.fileDescriptor };
            int results[2] = { 0, 0 };
            iTermSelect(fds, sizeof(fds) / sizeof(*fds), results, 0);
            if (results[0]) {
                NSData *data = outputHandle.availableData;
                if (data.length == 0) {
                    break;
                }
                [accumulatedOutput appendData:data];
            }
            if (results[1]) {
                NSData *data = errorHandle.availableData;
                if (data.length == 0) {
                    break;
                }
                [accumulatedError appendData:data];
            }
            if (accumulatedOutput.length > 1048576 ||
                accumulatedError.length > 1048576) {
                [task terminate];
                break;
            }
        }

        [task waitUntilExit];
        completion(accumulatedOutput, accumulatedError, task.terminationStatus);
    } @catch (NSException *exception) {
        completion(nil, nil, 0);
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
        const int rc = stat(path.UTF8String, &buf);
        const int error = (rc == 0) ? 0 : errno;
        
        if (!completion()) {
            return;
        }
        reply(buf, error);
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

- (NSArray<NSString *> *)contentsOfDirectory:(NSString *)directory
                                  withPrefix:(NSString *)prefix
                                  executable:(BOOL)executable {
    NSArray<NSString *> *relative = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] ?: @[];
    NSMutableArray<NSString*> *result = [NSMutableArray array];
    for (NSString *path in relative) {
        if (prefix.length == 0 || [path.lastPathComponent hasPrefix:prefix]) {
            NSString *fullPath = [directory stringByAppendingPathComponent:path];
            if (!executable || [[NSFileManager defaultManager] isExecutableFileAtPath:fullPath]) {
                [result addObject:fullPath];
            }
        }
    }
    return result;
}

- (NSArray<NSString *> *)reallyFindCompletionsWithPrefix:(NSString *)prefix
                                             inDirectory:(NSString *)directory
                                                maxCount:(NSInteger)maxCount
                                              executable:(BOOL)executable {
    if (![prefix hasPrefix:@"/"] && [directory hasPrefix:@"/"]) {
        // Can't use stringByAppendingPathComponent: because it doesn't do anything if prefix is
        // empty and we always want to append a / to directory.
        NSArray<NSString *> *temp = [self reallyFindCompletionsWithPrefix:[NSString stringWithFormat:@"%@/%@", directory, prefix]
                                                              inDirectory:@""
                                                                 maxCount:maxCount
                                                               executable:executable];
        NSString *prefixToRemove = [directory hasSuffix:@"/"] ? directory : [directory stringByAppendingString:@"/"];
        return [self array:temp byRemovingPrefix:prefixToRemove];
    }

    // If prefix is the exact name of a directory, return its contents.
    if ([prefix hasSuffix:@"/"]) {
        return [self contentsOfDirectory:prefix withPrefix:@"" executable:executable];
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
                                                executable:executable]];
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
                                                                    executable:executable] sortedArrayUsingSelector:@selector(compare:)];
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
                       timeout:(int)timeout
                    completion:(void (^)(iTermGitState * _Nullable))reply {
    [self performRiskyBlock:^(BOOL shouldPerform, BOOL (^ _Nullable completion)(void)) {
        if (!shouldPerform) {
            reply(nil);
            syslog(LOG_WARNING, "pidinfo wedged");
            return;
        }

        NSPipe *pipe = [NSPipe pipe];

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = [NSString stringWithCString:GetPathToSelf()
                                             encoding:NSUTF8StringEncoding];
        task.arguments = @[ @"--git-state", path, [@(timeout) stringValue] ];
        task.standardOutput = pipe;
        @try {
            [task launch];
        } @catch (NSException *exception) {
            syslog(LOG_ERR, "Exception when launch git state fetcher: %s", exception.description.UTF8String);
            reply(nil);
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
            // If it timed out don't even try to read because it could be incomplete.
            reply(nil);
            completion();
            return;
        }

        NSData *data = [fileHandle readDataToEndOfFile];
        NSError *error = nil;
        NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
        if (!decoder) {
            reply(nil);
            completion();
            return;
        }
                
        iTermGitState *state = [decoder decodeTopLevelObjectOfClass:[iTermGitState class]
                                                             forKey:@"state"
                                                              error:nil];
        reply(state);
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

@end


