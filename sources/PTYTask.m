#define MAXRW 1024

#import "Coprocess.h"
#import "DebugLogging.h"
#import "iTermMalloc.h"
#import "iTermNotificationController.h"
#import "iTermPosixTTYReplacements.h"
#import "iTermProcessCache.h"
#import "NSWorkspace+iTerm.h"
#import "PreferencePanel.h"
#import "PTYTask.h"
#import "PTYTask+MRR.h"
#import "TaskNotifier.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermLSOF.h"
#import "iTermLegacyJobManager.h"
#import "iTermMonoServerJobManager.h"
#import "iTermMultiServerJobManager.h"
#import "iTermOpenDirectory.h"
#import "iTermOrphanServerAdopter.h"
#import "iTermThreadSafety.h"
#import "iTermTmuxJobManager.h"
#import "NSDictionary+iTerm.h"

#include "iTermFileDescriptorClient.h"
#include "iTermFileDescriptorServer.h"
#include "iTermFileDescriptorSocketPath.h"
#include "legacy_server.h"
#include <dlfcn.h>
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/msg.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/user.h>
#include <unistd.h>
#include <util.h>

static void HandleSigChld(int n) {
    // This is safe to do because write(2) is listed in the sigaction(2) man page
    // as allowed in a signal handler. Calling a method is *NOT* safe since something might
    // be fiddling with the runtime. I saw a lot of crashes where CoreData got interrupted by
    // a sigchild while doing class_addMethod and that caused a crash because of a method call.
    UnblockTaskNotifier();
}

@interface PTYTask ()<iTermTask>
@property(atomic, assign) BOOL hasMuteCoprocess;
@property(atomic, readwrite) int fd;
@property(atomic, weak) iTermLoggingHelper *loggingHelper;
@property(atomic, strong) id<iTermJobManager> jobManager;
@end

@implementation PTYTask {
    int status;
    NSString* path;
    BOOL hasOutput;

    NSLock* writeLock;  // protects writeBuffer
    NSMutableData* writeBuffer;


    Coprocess *coprocess_;  // synchronized (self)
    BOOL brokenPipe_;  // synchronized (self)
    NSString *command_;  // Command that was run if launchWithPath:arguments:etc was called

    BOOL _paused;

    PTYTaskSize _desiredSize;
    CGFloat _lastScaleFactor;
    PTYTaskSize _lastSize;
    NSTimeInterval _timeOfLastSizeChange;
    BOOL _rateLimitedSetSizeToDesiredSizePending;
    BOOL _haveBumpedProcessCache;
    dispatch_queue_t _jobManagerQueue;
    BOOL _isTmuxTask;


    NSInteger _deferResizeCount;
    BOOL _haveDeferredResize;
    VT100GridSize _deferredSize;
    NSSize _deferredViewSize;
    CGFloat _deferredScaleFactor;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        const char *label = [iTermThread uniqueQueueLabelWithName:@"com.iterm2.job-manager"].UTF8String;
        _jobManagerQueue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL);
        _lastSize = (PTYTaskSize) {
            .cellSize = iTermTTYCellSizeMake(INFINITY, INFINITY),
            .pixelSize = iTermTTYPixelSizeMake(INFINITY, INFINITY)
        };
        writeBuffer = [[NSMutableData alloc] init];
        writeLock = [[NSLock alloc] init];
        if ([iTermAdvancedSettingsModel runJobsInServers]) {
            if ([iTermMultiServerJobManager available]) {
                self.jobManager = [[iTermMultiServerJobManager alloc] initWithQueue:_jobManagerQueue];
            } else {
                self.jobManager = [[iTermMonoServerJobManager alloc] initWithQueue:_jobManagerQueue];
            }
        } else {
            self.jobManager = [[iTermLegacyJobManager alloc] initWithQueue:_jobManagerQueue];
        }
        self.fd = -1;
    }
    return self;
}

- (void)dealloc {
    DLog(@"Dealloc PTYTask %p", self);
    // TODO: The use of killpg seems pretty sketchy. It takes a pgid_t, not a
    // pid_t. Are they guaranteed to always be the same for process group
    // leaders? It is not clear from git history why killpg is used here and
    // not in other places. I suspect it's what we ought to use everywhere.
    [self.jobManager killWithMode:iTermJobManagerKillingModeProcessGroup];
    if (_tmuxClientProcessID) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_tmuxClientProcessID.intValue];
    }

    [self closeFileDescriptorAndDeregisterIfPossible];

    @synchronized (self) {
        [[self coprocess] mainProcessDidTerminate];
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p jobManager=%@ pid=%@ fd=%@ tmuxClientProcessID=%@>",
            NSStringFromClass([self class]),
            self,
            self.jobManager,
            @(self.pid),
            @(self.fd),
            _tmuxClientProcessID];
}

#pragma mark - APIs

- (BOOL)paused {
    @synchronized(self) {
        return _paused;
    }
}

- (void)setPaused:(BOOL)paused {
    @synchronized(self) {
        _paused = paused;
    }
    // Start/stop selecting on our FD
    [[TaskNotifier sharedInstance] unblock];
    [_delegate taskDidChangePaused:self paused:paused];
}

- (pid_t)pidToWaitOn {
    return self.jobManager.pidToWaitOn;
}

- (BOOL)isSessionRestorationPossible {
    return self.jobManager.isSessionRestorationPossible;
}

- (id)sessionRestorationIdentifier {
    return self.jobManager.sessionRestorationIdentifier;
}

- (int)fd {
    assert(self.jobManager);
    return self.jobManager.fd;
}

- (void)setFd:(int)fd {
    assert(self.jobManager);
    self.jobManager.fd = fd;
}

- (pid_t)pid {
    return self.jobManager.externallyVisiblePid;
}

- (int)status {
    return status;
}

- (NSString *)path {
    return path;
}

- (NSString *)getWorkingDirectory {
    DLog(@"Want working directory of %@ - SYNCHRONOUS", @(self.pid));
    if (self.pid == -1) {
        DLog(@"Want to use the kernel to get the working directory but pid = -1");
        return nil;
    }
    return [iTermLSOF workingDirectoryOfProcess:self.pid];
}

- (void)getWorkingDirectoryWithCompletion:(void (^)(NSString *pwd))completion {
    DLog(@"Want working directory of %@ - async", @(self.pid));
    if (self.pid == -1) {
        DLog(@"Want to use the kernel to get the working directory but pid = -1");
        completion(nil);
        return;
    }
    [iTermLSOF asyncWorkingDirectoryOfProcess:self.pid queue:dispatch_get_main_queue() block:completion];
}

- (Coprocess *)coprocess {
    @synchronized (self) {
        return coprocess_;
    }
    return nil;
}

// This runs on the task notifier thread
- (void)setCoprocess:(Coprocess *)coprocess {
    @synchronized (self) {
        coprocess_ = coprocess;
        self.hasMuteCoprocess = coprocess_.mute;
    }
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.delegate taskMuteCoprocessDidChange:self hasMuteCoprocess:self.hasMuteCoprocess];
    });
    [[TaskNotifier sharedInstance] unblock];
}

- (BOOL)writeBufferHasRoom {
    const int kMaxWriteBufferSize = 1024 * 10;
    [writeLock lock];
    BOOL hasRoom = [writeBuffer length] < kMaxWriteBufferSize;
    [writeLock unlock];
    return hasRoom;
}

- (BOOL)hasCoprocess {
    @synchronized (self) {
        return coprocess_ != nil;
    }
    return NO;
}

- (BOOL)passwordInput {
    struct termios termAttributes;
    if ([iTermAdvancedSettingsModel detectPasswordInput] &&
        self.fd > 0 &&
        isatty(self.fd) &&
        tcgetattr(self.fd, &termAttributes) == 0) {
        return !(termAttributes.c_lflag & ECHO) && (termAttributes.c_lflag & ICANON);
    } else {
        return NO;
    }
}

- (BOOL)hasBrokenPipe {
    @synchronized(self) {
        return brokenPipe_;
    }
}

- (NSString *)originalCommand {
    return command_;
}

- (void)launchWithPath:(NSString *)progpath
             arguments:(NSArray *)args
           environment:(NSDictionary *)env
           customShell:(NSString *)customShell
              gridSize:(VT100GridSize)gridSize
              viewSize:(NSSize)viewSize
      maybeScaleFactor:(CGFloat)maybeScaleFactor
                isUTF8:(BOOL)isUTF8
            completion:(void (^)(void))completion {
    DLog(@"launchWithPath:%@ args:%@ env:%@ grisSize:%@ isUTF8:%@",
         progpath, args, env, VT100GridSizeDescription(gridSize), @(isUTF8));

    if ([iTermAdvancedSettingsModel runJobsInServers] && ![iTermMultiServerJobManager available]) {
        // We want to run
        //   iTerm2 --server progpath args
        NSArray *updatedArgs = [@[ @"--server", progpath ] arrayByAddingObjectsFromArray:args];
        if (![iTermAdvancedSettingsModel bootstrapDaemon]) {
            env = [env dictionaryBySettingObject:@"1" forKey:@"ITERM2_DISABLE_BOOTSTRAP"];
        }
        [self reallyLaunchWithPath:[[NSBundle mainBundle] executablePath]
                         arguments:updatedArgs
                       environment:env
                       customShell:customShell
                          gridSize:gridSize
                          viewSize:viewSize
                  maybeScaleFactor:maybeScaleFactor
                            isUTF8:isUTF8
                        completion:completion];
    } else {
        [self reallyLaunchWithPath:progpath
                         arguments:args
                       environment:env
                       customShell:customShell
                          gridSize:gridSize
                          viewSize:viewSize
                  maybeScaleFactor:maybeScaleFactor
                            isUTF8:isUTF8
                        completion:completion];
    }
}

- (void)setTmuxClientProcessID:(NSNumber *)tmuxClientProcessID {
    if ([NSObject object:tmuxClientProcessID isEqualToObject:_tmuxClientProcessID]) {
        return;
    }
    DLog(@"Set tmux client process ID for %@ to %@", self, tmuxClientProcessID);
    if (_tmuxClientProcessID) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_tmuxClientProcessID.intValue];
    }
    if (tmuxClientProcessID) {
        [[iTermProcessCache sharedInstance] registerTrackedPID:tmuxClientProcessID.intValue];
    }
    _tmuxClientProcessID = tmuxClientProcessID;
}

- (void)setReadOnlyFileDescriptor:(int)readOnlyFileDescriptor {
    iTermTmuxJobManager *jobManager = [[iTermTmuxJobManager alloc] initWithQueue:self->_jobManagerQueue];
    jobManager.fd = readOnlyFileDescriptor;
    DLog(@"Configure %@ as tmux task", self);
    _jobManager = jobManager;
    [[TaskNotifier sharedInstance] registerTask:self];
}

- (int)readOnlyFileDescriptor {
    if (![_jobManager isKindOfClass:[iTermTmuxJobManager class]]) {
        return -1;
    }
    return _jobManager.fd;
}

- (void)fetchProcessInfoForCurrentJobWithCompletion:(void (^)(iTermProcessInfo *))completion {
    const pid_t pid = self.tmuxClientProcessID ? self.tmuxClientProcessID.intValue : self.pid;
    iTermProcessInfo *info = [[iTermProcessCache sharedInstance] deepestForegroundJobForPid:pid];
    DLog(@"%@ fetch process info for %@", self, @(pid));
    if (info.name) {
        DLog(@"Return name synchronously");
        completion(info);
    } else if (info) {
        DLog(@"Have info for pid %@ but no name", @(pid));
    }

    if (pid <= 0) {
        DLog(@"Lack a good pid");
        completion(nil);
        return;
    }
    if (_haveBumpedProcessCache) {
        DLog(@"Already bumped process cache");
        [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
        return;
    }
    _haveBumpedProcessCache = YES;
    DLog(@"Requesting immediate update");
    [[iTermProcessCache sharedInstance] requestImmediateUpdateWithCompletionBlock:^{
        completion([[iTermProcessCache sharedInstance] deepestForegroundJobForPid:pid]);
    }];
}

- (iTermProcessInfo *)cachedProcessInfoIfAvailable {
    const pid_t pid = self.pid;
    iTermProcessInfo *info = [[iTermProcessCache sharedInstance] deepestForegroundJobForPid:pid];
    if (info.name) {
        return info;
    }

    if (pid > 0 && _haveBumpedProcessCache) {
        _haveBumpedProcessCache = YES;
        [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
    }

    return nil;
}

- (void)writeTask:(NSData *)data {
    if (_isTmuxTask) {
        // Send keypresses to tmux.
        NSData *copyOfData = [data copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate tmuxClientWrite:copyOfData];
        });
        return;
    }
    // Write as much as we can now through the non-blocking pipe
    // Lock to protect the writeBuffer from the IO thread
    id<iTermJobManager> jobManager = self.jobManager;
    assert(!jobManager || !self.jobManager.isReadOnly);
    [writeLock lock];
    [writeBuffer appendData:data];
    [[TaskNotifier sharedInstance] unblock];
    [writeLock unlock];
}

- (void)killWithMode:(iTermJobManagerKillingMode)mode {
    [self.jobManager killWithMode:mode];
    if (_tmuxClientProcessID) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_tmuxClientProcessID.intValue];
    }
}

- (void)incrementDeferResizeCount:(NSInteger)delta {
    if (delta == 0) {
        return;
    }
    assert(delta >= -1 && delta <= 1);
    _deferResizeCount += delta;
    assert(_deferResizeCount >= 0);
    DLog(@"For %@, delta=%@ count=%@", self, @(delta), @(_deferResizeCount));
    if (_deferResizeCount == 0 && _haveDeferredResize) {
        _haveDeferredResize = NO;
        [self setSize:_deferredSize
             viewSize:_deferredViewSize
          scaleFactor:_deferredScaleFactor];
    }
}

// NOTE: maybeScaleFactor will be 0 if the session is not attached to a window. For example, if
// a different space is active.
- (BOOL)setSize:(VT100GridSize)size
       viewSize:(NSSize)viewSize
    scaleFactor:(CGFloat)maybeScaleFactor {

    if (_deferResizeCount > 0) {
        DLog(@"Defer resize to %@ because count is %@",
             VT100GridSizeDescription(size), @(_deferResizeCount));
        _haveDeferredResize = YES;
        _deferredSize = size;
        _deferredViewSize = viewSize;
        _deferredScaleFactor = maybeScaleFactor;
        return YES;
    }

    CGFloat scaleFactor = maybeScaleFactor;
    if (scaleFactor < 1) {
        scaleFactor = _lastScaleFactor;
    } else {
        _lastScaleFactor = scaleFactor;
    }
    if (scaleFactor < 1) {
        scaleFactor = 2;
    }
    DLog(@"Set terminal size to %@; %@ * scaleFactor=%f for %@\n%@",
         VT100GridSizeDescription(size), NSStringFromSize(viewSize), scaleFactor, self.delegate,
         [NSThread callStackSymbols]);
    if (self.fd == -1) {
        DLog(@"I have no file descriptor so not setting size.");
        return NO;
    }

    _desiredSize.cellSize = iTermTTYCellSizeMake(size.width, size.height);
    _desiredSize.pixelSize = iTermTTYPixelSizeMake(viewSize.width * scaleFactor,
                                                   viewSize.height * scaleFactor);

    if (PTYTaskSizeEqual(_lastSize, _desiredSize)) {
        DLog(@"Size didn't change");
        return YES;
    }
    [self rateLimitedSetSizeToDesiredSize];
    return YES;
}

- (void)stop {
    DLog(@"stop %@", self);
    self.paused = NO;
    [self.loggingHelper stop];
    [self killWithMode:iTermJobManagerKillingModeRegular];

    // Ensure the server is broken out of accept()ing for future connections
    // in case the child doesn't die right away.
    [self killWithMode:iTermJobManagerKillingModeBrokenPipe];

    [self closeFileDescriptorAndDeregisterIfPossible];
}

- (void)brokenPipe {
    DLog(@"brokenPipe %@", self);
    @synchronized(self) {
        brokenPipe_ = YES;
    }
    [[TaskNotifier sharedInstance] deregisterTask:self];
    [self.delegate threadedTaskBrokenPipe];
}

// Main queue
- (void)didRegister {
    DLog(@"didRegister %@", self);
    [self.delegate taskDidRegister:self];
}

- (void)processRead {
    int iterations = 4;
    int bytesRead = 0;

    char buffer[MAXRW * iterations];
    for (int i = 0; i < iterations; ++i) {
        // Only read up to MAXRW*iterations bytes, then release control
        ssize_t n = read(self.fd, buffer + bytesRead, MAXRW);
        if (n < 0) {
            // There was a read error.
            if (errno != EAGAIN && errno != EINTR) {
                // It was a serious error.
                [self brokenPipe];
                return;
            } else {
                // We could read again in the case of EINTR but it would
                // complicate the code with little advantage. Just bail out.
                n = 0;
            }
        }
        bytesRead += n;
        if (n < MAXRW) {
            // If we read fewer bytes than expected, return. For some apparently
            // undocumented reason, read() never returns more than 1024 bytes
            // (at least on OS 10.6), so that's what MAXRW is set to. If that
            // ever goes down this'll break.
            break;
        }
    }

    hasOutput = YES;

    // Send data to the terminal
    [self readTask:buffer length:bytesRead];
}

- (void)processWrite {
    // Retain to prevent the object from being released during this method
    // Lock to protect the writeBuffer from the main thread
    [writeLock lock];

    // Only write up to MAXRW bytes, then release control
    char* ptr = [writeBuffer mutableBytes];
    unsigned int length = [writeBuffer length];
    if (length > MAXRW) {
        length = MAXRW;
    }
    ssize_t written = write(self.fd, [writeBuffer mutableBytes], length);

    // No data?
    if ((written < 0) && (!(errno == EAGAIN || errno == EINTR))) {
        [self brokenPipe];
    } else if (written > 0) {
        // Shrink the writeBuffer
        length = [writeBuffer length] - written;
        memmove(ptr, ptr+written, length);
        [writeBuffer setLength:length];
    }

    // Clean up locks
    [writeLock unlock];
}

- (void)stopCoprocess {
    pid_t thePid = 0;
    @synchronized (self) {
        if (coprocess_.pid > 0) {
            thePid = coprocess_.pid;
        }
        [coprocess_ terminate];
        coprocess_ = nil;
        self.hasMuteCoprocess = NO;
    }
    [self.delegate taskMuteCoprocessDidChange:self hasMuteCoprocess:self.hasMuteCoprocess];

    if (thePid) {
        [[TaskNotifier sharedInstance] waitForPid:thePid];
    }
    [[TaskNotifier sharedInstance] performSelectorOnMainThread:@selector(notifyCoprocessChange)
                                                    withObject:nil
                                                 waitUntilDone:NO];
}

- (void)setJobManagerType:(iTermGeneralServerConnectionType)type {
    assert([self canAttach]);
    assert([NSThread isMainThread]);
    switch (type) {
        case iTermGeneralServerConnectionTypeMono:
            if ([self.jobManager isKindOfClass:[iTermMonoServerJobManager class]]) {
                return;
            }
            DLog(@"Replace jobmanager %@ with monoserver instance", self.jobManager);
            self.jobManager = [[iTermMonoServerJobManager alloc] initWithQueue:self->_jobManagerQueue];
            return;

        case iTermGeneralServerConnectionTypeMulti:
            if ([self.jobManager isKindOfClass:[iTermMultiServerJobManager class]]) {
                return;
            }
            DLog(@"Replace jobmanager %@ with multiserver instance", self.jobManager);
            self.jobManager = [[iTermMultiServerJobManager alloc] initWithQueue:self->_jobManagerQueue];
            return;
    }
    ITAssertWithMessage(NO, @"Unrecognized job type %@", @(type));
}

// This works for any kind of connection. It finishes the process of attaching a PTYTask to a child
// that we know is in a server, either newly launched or an orphan.
- (void)attachToServer:(iTermGeneralServerConnection)serverConnection
            completion:(void (^)(iTermJobManagerAttachResults))completion {
    assert([self canAttach]);
    [self setJobManagerType:serverConnection.type];
    [_jobManager attachToServer:serverConnection
                  withProcessID:nil
                           task:self
                     completion:completion];
}

- (iTermJobManagerAttachResults)attachToServer:(iTermGeneralServerConnection)serverConnection {
    assert([self canAttach]);
    [self setJobManagerType:serverConnection.type];
    if (serverConnection.type == iTermGeneralServerConnectionTypeMulti) {
        DLog(@"PTYTask: attach to multiserver %@", @(serverConnection.multi.number));
    }
    return [_jobManager attachToServer:serverConnection
                         withProcessID:nil
                                  task:self];
}

- (BOOL)canAttach {
    if (![iTermAdvancedSettingsModel runJobsInServers]) {
        return NO;
    }
    if (self.jobManager.hasJob) {
        return NO;
    }
    return YES;
}

// Monoserver only. Used when restoring a non-ophan session. May block while connecting to the
// server. Deletes the socket after connecting.
- (BOOL)tryToAttachToServerWithProcessId:(pid_t)thePid tty:(NSString *)tty {
    if (![self canAttach]) {
        return NO;
    }

    DLog(@"tryToAttachToServerWithProcessId: Attempt to connect to server for pid %d, tty %@", (int)thePid, tty);
    iTermFileDescriptorServerConnection serverConnection = iTermFileDescriptorClientRun(thePid);
    if (!serverConnection.ok) {
        NSLog(@"Failed with error %s", serverConnection.error);
        return NO;
    }
    DLog(@"Succeeded.");
    iTermGeneralServerConnection general = {
        .type = iTermGeneralServerConnectionTypeMono,
        .mono = serverConnection
    };
    [self setJobManagerType:general.type];
    // This assumes the monoserver finishes synchronously and can't fail.
    [self.jobManager attachToServer:general
                      withProcessID:@(thePid)
                               task:self
                         completion:^(iTermJobManagerAttachResults results) {}];
    [self setTty:tty];
    return YES;
}

// Multiserver only. Used when restoring a non-orphan session. May block while connecting to the
// server.
- (iTermJobManagerAttachResults)tryToAttachToMultiserverWithRestorationIdentifier:(NSDictionary *)restorationIdentifier {
    if (![self canAttach]) {
        return 0;
    }
    iTermGeneralServerConnection generalConnection;
    if (![iTermMultiServerJobManager getGeneralConnection:&generalConnection
                                fromRestorationIdentifier:restorationIdentifier]) {
        return 0;
    }

    DLog(@"tryToAttachToMultiserverWithRestorationIdentifier:%@", restorationIdentifier);
    return [self attachToServer:generalConnection];
}

- (void)partiallyAttachToMultiserverWithRestorationIdentifier:(NSDictionary *)restorationIdentifier
                                                   completion:(void (^)(id<iTermJobManagerPartialResult>))completion {
    if (!self.canAttach) {
        completion(0);
        return;
    }
    iTermGeneralServerConnection generalConnection;
    if (![iTermMultiServerJobManager getGeneralConnection:&generalConnection
                                fromRestorationIdentifier:restorationIdentifier]) {
        completion(0);
        return;
    }
    if (generalConnection.type != iTermGeneralServerConnectionTypeMulti) {
        assert(NO);
    }
    [_jobManager asyncPartialAttachToServer:generalConnection
                              withProcessID:@(generalConnection.multi.pid)
                                 completion:completion];
}

- (iTermJobManagerAttachResults)finishAttachingToMultiserver:(id<iTermJobManagerPartialResult>)partialResult
                                                  jobManager:(id<iTermJobManager>)jobManager
                                                       queue:(dispatch_queue_t)queue {
    assert([NSThread isMainThread]);
    self.jobManager = jobManager;
    _jobManagerQueue = queue;
    return [_jobManager finishAttaching:partialResult task:self];
}

- (void)registerTmuxTask {
    _isTmuxTask = YES;
    DLog(@"Register pid %@ as coprocess-only task", @(self.pid));
    [[TaskNotifier sharedInstance] registerTask:self];
}

#pragma mark - Private

#pragma mark Task Launching Helpers

// Returns a NSMutableDictionary containing the key-value pairs defined in the
// global "environ" variable.
- (NSMutableDictionary *)mutableEnvironmentDictionary {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    extern char **environ;
    if (environ != NULL) {
        for (int i = 0; environ[i]; i++) {
            NSString *kvp = [NSString stringWithUTF8String:environ[i]];
            NSRange equalsRange = [kvp rangeOfString:@"="];
            if (equalsRange.location != NSNotFound) {
                NSString *key = [kvp substringToIndex:equalsRange.location];
                NSString *value = [kvp substringFromIndex:equalsRange.location + 1];
                result[key] = value;
            } else {
                result[kvp] = @"";
            }
        }
    }
    return result;
}

- (NSArray<NSString *> *)environWithOverrides:(NSDictionary *)env {
    NSMutableDictionary *environmentDict = [self mutableEnvironmentDictionary];
    for (NSString *k in env) {
        environmentDict[k] = env[k];
    }
    [environmentDict removeObjectForKey:@"SHLVL"];  // Issue 9756
    NSMutableArray<NSString *> *environment = [NSMutableArray array];
    for (NSString *k in environmentDict) {
        NSString *temp = [NSString stringWithFormat:@"%@=%@", k, environmentDict[k]];
        [environment addObject:temp];
    }
    return environment;
}

- (NSDictionary *)environmentBySettingShell:(NSDictionary *)originalEnvironment {
    NSString *shell = [iTermOpenDirectory userShell];
    if (!shell) {
        return originalEnvironment;
    }
    NSMutableDictionary *newEnvironment = [originalEnvironment mutableCopy];
    newEnvironment[@"SHELL"] = [shell copy];
    return newEnvironment;
}

- (void)setCommand:(NSString *)command {
    command_ = [command copy];
}

- (NSString *)tty {
    return self.jobManager.tty;
}

- (void)setTty:(NSString *)tty {
    self.jobManager.tty = tty;
    if ([NSThread isMainThread]) {
        [self.delegate taskDidChangeTTY:self];
    } else {
        __weak id<PTYTaskDelegate> delegate = self.delegate;
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [delegate taskDidChangeTTY:strongSelf];
            }
        });
    }
}

- (void)reallyLaunchWithPath:(NSString *)progpath
                   arguments:(NSArray *)args
                 environment:(NSDictionary *)env
                 customShell:(NSString *)customShell
                    gridSize:(VT100GridSize)gridSize
                    viewSize:(NSSize)pointSize
            maybeScaleFactor:(CGFloat)maybeScaleFactor
                      isUTF8:(BOOL)isUTF8
                  completion:(void (^)(void))completion {
    NSSize viewSize = pointSize;
    if (maybeScaleFactor > 0) {
        viewSize.width *= maybeScaleFactor;
        viewSize.height *= maybeScaleFactor;
        _lastScaleFactor = maybeScaleFactor;
    }
    DLog(@"reallyLaunchWithPath:%@ args:%@ env:%@ gridSize:%@ viewSize:%@ isUTF8:%@",
         progpath, args, env,VT100GridSizeDescription(gridSize), NSStringFromSize(viewSize), @(isUTF8));

    __block iTermTTYState ttyState;
    PTYTaskSize newSize = {
        .cellSize = iTermTTYCellSizeMake(gridSize.width, gridSize.height),
        .pixelSize = iTermTTYPixelSizeMake(viewSize.width, viewSize.height)
    };
    DLog(@"Initialize tty with cell size %d x %d, pixel size %d x %d",
         newSize.cellSize.width,
         newSize.cellSize.height,
         newSize.pixelSize.width,
         newSize.pixelSize.height);
    _lastSize = newSize;
    iTermTTYStateInit(&ttyState,
                      newSize.cellSize,
                      newSize.pixelSize,
                      isUTF8);
    [self setCommand:progpath];
    if (customShell) {
        DLog(@"Use custom shell");
        env = [env dictionaryBySettingObject:customShell forKey:@"SHELL"];
    } else {
        env = [self environmentBySettingShell:env];
    }

    DLog(@"After setting shell environment is %@", env);
    path = [progpath copy];
    NSString *commandToExec = [progpath stringByStandardizingPath];

    // Register a handler for the child death signal. There is some history here.
    // Originally, a do-nothing handler was registered with the following comment:
    //   We cannot ignore SIGCHLD because Sparkle (the software updater) opens a
    //   Safari control which uses some buggy Netscape code that calls wait()
    //   until it succeeds. If we wait() on its pid, that process locks because
    //   it doesn't check if wait()'s failure is ECHLD. Instead of wait()ing here,
    //   we reap our children when our select() loop sees that a pipes is broken.
    // In response to bug 2903, wherein select() fails to return despite the file
    // descriptor having EOF status, I changed the handler to unblock the task
    // notifier.
    signal(SIGCHLD, HandleSigChld);

    NSMutableArray<NSString *> *argv = [NSMutableArray array];
    [argv addObject:[progpath stringByStandardizingPath]];
    [argv addObjectsFromArray:args];

    DLog(@"Preparing to launch a job. Command is %@ and args are %@", commandToExec, args);
    DLog(@"Environment is\n%@", env);
    NSArray<NSString *> *newEnviron = [self environWithOverrides:env];

    // Note: stringByStandardizingPath will automatically call stringByExpandingTildeInPath.
    NSString *initialPwd = [[env objectForKey:@"PWD"] stringByStandardizingPath];
    DLog(@"initialPwd=%@, jobManager=%@", initialPwd, self.jobManager);
    [self.jobManager forkAndExecWithTtyState:ttyState
                                     argpath:commandToExec
                                        argv:argv
                                  initialPwd:initialPwd ?: NSHomeDirectory()
                                  newEnviron:newEnviron
                                        task:self
                                  completion:
     ^(iTermJobManagerForkAndExecStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self didForkAndExec:progpath
                      withStatus:status
                     errorNumber:errno];
            if (completion) {
                completion();
            }
        });
    }];
}

// Main queue
- (void)didForkAndExec:(NSString *)progpath
            withStatus:(iTermJobManagerForkAndExecStatus)status
           errorNumber:(int)errorNumber {
    switch (status) {
        case iTermJobManagerForkAndExecStatusSuccess:
            // Parent
            [self setTty:self.jobManager.tty];
            DLog(@"finished succesfully");
            break;

        case iTermJobManagerForkAndExecStatusTempFileError:
            [self showFailedToCreateTempSocketError];
            break;

        case iTermJobManagerForkAndExecStatusFailedToFork:
            DLog(@"Unable to fork %@: %s", progpath, strerror(errorNumber));
            [[iTermNotificationController sharedInstance] notify:@"Unable to fork!"
                                                 withDescription:@"You may have too many processes already running."];
            break;

        case iTermJobManagerForkAndExecStatusTaskDiedImmediately:
        case iTermJobManagerForkAndExecStatusServerError:
        case iTermJobManagerForkAndExecStatusServerLaunchFailed:
            [self.delegate taskDiedImmediately];
            break;

    }
}

- (void)showFailedToCreateTempSocketError {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Error";
    alert.informativeText = [NSString stringWithFormat:@"An error was encountered while creating a temporary file with mkstemps. Verify that %@ exists and is writable.", NSTemporaryDirectory()];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

#pragma mark I/O

- (BOOL)wantsRead {
    if (self.paused) {
        return NO;
    }
    return self.jobManager.ioAllowed;
}

- (BOOL)wantsWrite {
    if (self.paused) {
        return NO;
    }
    if (self.jobManager.isReadOnly) {
        return NO;
    }
    [writeLock lock];
    const BOOL wantsWrite = [writeBuffer length] > 0;
    [writeLock unlock];
    if (!wantsWrite) {
        return NO;
    }
    return self.jobManager.ioAllowed;
}

- (BOOL)hasOutput {
    return hasOutput;
}

// The bytes in data were just read from the fd.
- (void)readTask:(char *)buffer length:(int)length {
    if (self.loggingHelper) {
        [self.loggingHelper logData:[NSData dataWithBytes:buffer
                                                   length:length]];
    }

    // The delegate is responsible for parsing VT100 tokens here and sending them off to the
    // main thread for execution. If its queues get too large, it can block.
    [self.delegate threadedReadTask:buffer length:length];

    @synchronized (self) {
        if (coprocess_) {
            [coprocess_.outputBuffer appendData:[NSData dataWithBytes:buffer length:length]];
        }
    }
}

- (void)closeFileDescriptorAndDeregisterIfPossible {
    assert(self.jobManager);
    const int fd = self.fd;
    if ([self.jobManager closeFileDescriptor]) {
        DLog(@"Deregister file descriptor %d for process %@ after closing it", fd, @(self.pid));
        [[TaskNotifier sharedInstance] deregisterTask:self];
    }
}

#pragma mark Terminal Size

- (void)rateLimitedSetSizeToDesiredSize {
    DLog(@"%@", self.delegate);
    if (_rateLimitedSetSizeToDesiredSizePending) {
        DLog(@"Already have a pending size change");
        return;
    }

    static const NSTimeInterval kDelayBetweenSizeChanges = 0.2;
    if ([NSDate timeIntervalSinceReferenceDate] - _timeOfLastSizeChange < kDelayBetweenSizeChanges) {
        // Avoid problems with signal coalescing of SIGWINCH preventing redraw for the second size
        // change. For example, issue 5096 and 4494.
        _rateLimitedSetSizeToDesiredSizePending = YES;
        DLog(@" ** Rate limiting **");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDelayBetweenSizeChanges * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DLog(@"Have waited %@ sec", @(kDelayBetweenSizeChanges));
            self->_rateLimitedSetSizeToDesiredSizePending = NO;
            [self setTerminalSizeToDesiredSize];
        });
    } else {
        [self setTerminalSizeToDesiredSize];
    }
}

- (void)setTerminalSizeToDesiredSize {
    DLog(@"Set size of %@ from (%@x%@ cells, %@x%@px) to (%@x%@ cells, %@x%@ px)",
         self.delegate,
         @(_lastSize.cellSize.width),
         @(_lastSize.cellSize.height),
         @(_lastSize.pixelSize.width),
         @(_lastSize.pixelSize.height),

         @(_desiredSize.cellSize.width),
         @(_desiredSize.cellSize.height),
         @(_desiredSize.pixelSize.width),
         @(_desiredSize.pixelSize.height));
    _timeOfLastSizeChange = [NSDate timeIntervalSinceReferenceDate];
    _lastSize = _desiredSize;

    iTermSetTerminalSize(self.fd, _desiredSize);
}

#pragma mark - iTermLoggingHelper

// NOTE: This can be called before the task is launched. It is not used when logging plain text.
- (void)loggingHelperStart:(iTermLoggingHelper *)loggingHelper {
    self.loggingHelper = loggingHelper;
}

- (void)loggingHelperStop:(iTermLoggingHelper *)loggingHelper {
    self.loggingHelper = nil;
}

@end

