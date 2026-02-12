#define MAXRW 1024

#import "PTYTask.h"
#import "PTYTask+Private.h"

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

#import "iTerm2SharedARC-Swift.h"
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

@interface PTYTask(WinSizeControllerDelegate)<iTermWinSizeControllerDelegate>
@end

static void HandleSigChld(int n) {
    // This is safe to do because write(2) is listed in the sigaction(2) man page
    // as allowed in a signal handler. Calling a method is *NOT* safe since something might
    // be fiddling with the runtime. I saw a lot of crashes where CoreData got interrupted by
    // a sigchild while doing class_addMethod and that caused a crash because of a method call.
    UnblockTaskNotifier();
}

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

    dispatch_queue_t _jobManagerQueue;
    BOOL _isTmuxTask;

    // Dispatch sources for per-PTY I/O (fairness scheduler integration)
    dispatch_source_t _readSource;
    dispatch_source_t _writeSource;
    dispatch_queue_t _ioQueue;
    BOOL _readSourceSuspended;
    BOOL _writeSourceSuspended;

    // Dispatch sources for coprocess I/O (fairness scheduler integration)
    dispatch_source_t _coprocessReadSource;   // reads coprocess stdout
    dispatch_source_t _coprocessWriteSource;  // flushes outputBuffer to coprocess stdin
    BOOL _coprocessReadSourceSuspended;
    BOOL _coprocessWriteSourceSuspended;

    // Test hook to override shouldWrite for testing write source resume
    BOOL _testShouldWriteOverride;

    // Test hook to override jobManager.ioAllowed for predicate tests
    // nil = use real value, @YES = force true, @NO = force false
    NSNumber *_testIoAllowedOverride;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        const char *label = [iTermThread uniqueQueueLabelWithName:@"com.iterm2.job-manager"].UTF8String;
        _jobManagerQueue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL);
        _winSizeController = [[iTermWinSizeController alloc] init];
        _winSizeController.delegate = self;
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
    // Tear down dispatch sources before releasing
    [self teardownDispatchSources];
    // TODO: The use of killpg seems pretty sketchy. It takes a pgid_t, not a
    // pid_t. Are they guaranteed to always be the same for process group
    // leaders? It is not clear from git history why killpg is used here and
    // not in other places. I suspect it's what we ought to use everywhere.
    [self.jobManager killWithMode:iTermJobManagerKillingModeProcessGroup];
    if (_tmuxClientProcessID) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_tmuxClientProcessID.intValue];
    }
    [self.ioBuffer invalidate];

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
    // Update dispatch sources based on new paused state
    [self updateReadSourceState];
    [self updateWriteSourceState];
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

// This runs on the task notifier thread (legacy) or main thread
- (void)setCoprocess:(Coprocess *)coprocess {
    DLog(@"Set coprocess of %@ to %@", self, coprocess);

    // Tear down old coprocess dispatch sources before swapping the ivar.
    if ([self useDispatchSource] && _coprocessReadSource) {
        [self teardownCoprocessDispatchSources];
    }

    @synchronized (self) {
        coprocess_ = coprocess;
        self.hasMuteCoprocess = coprocess_.mute;
    }

    // Set up dispatch sources for the new coprocess (if using dispatch source path).
    if ([self useDispatchSource] && coprocess) {
        [self setupCoprocessDispatchSources:coprocess];
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

- (void)setIoBuffer:(iTermIOBuffer *)ioBuffer {
    iTermChannelJobManager *jobManager = [[iTermChannelJobManager alloc] initWithQueue:_jobManagerQueue];
    jobManager.ioBuffer = ioBuffer;
    _jobManager = jobManager;
}

- (iTermIOBuffer *)ioBuffer {
    return [[iTermChannelJobManager castFrom:_jobManager] ioBuffer];
}

- (int)readOnlyFileDescriptor {
    if (![_jobManager isKindOfClass:[iTermTmuxJobManager class]]) {
        return -1;
    }
    return _jobManager.fd;
}

// Send keyboard input, coprocess output, tmux commands, etc.
- (void)writeTask:(NSData *)data {
    [self writeTask:data coprocess:NO];
}

- (void)writeTask:(NSData *)data coprocess:(BOOL)fromCoprocessOutput {
    if (_isTmuxTask) {
        // Send keypresses to tmux.
        NSData *copyOfData = [data copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate tmuxClientWrite:copyOfData];
        });
        return;
    }
    if (self.sshIntegrationActive && fromCoprocessOutput) {
        NSData *copyOfData = [data copy];
        DLog(@"Direct data from coprocess to session to route to conductor: %@", data);
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.delegate taskDidReadFromCoprocessWhileSSHIntegrationInUse:copyOfData];
        });
        return;
    }
    iTermIOBuffer *ioBuffer = self.ioBuffer;
    if (ioBuffer) {
        [ioBuffer write:data];
        return;
    }
    // Write as much as we can now through the non-blocking pipe
    // Lock to protect the writeBuffer from the IO thread
    id<iTermJobManager> jobManager = self.jobManager;
    assert(!jobManager || !self.jobManager.isReadOnly);
    [writeLock lock];
    [writeBuffer appendData:data];
    [writeLock unlock];

    // Trigger write dispatch_source (no-op if not set up)
    // Must be outside writeLock because writeBufferDidChange -> shouldWrite takes writeLock
    [self writeBufferDidChange];
    [[TaskNotifier sharedInstance] unblock];  // Still needed for coprocess FD wake-up
}

- (void)killWithMode:(iTermJobManagerKillingMode)mode {
    [self.jobManager killWithMode:mode];
    if (_tmuxClientProcessID) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_tmuxClientProcessID.intValue];
    }
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
    // Stop dispatch sources immediately to prevent handlers firing on a dead fd.
    // In fairness mode, tasks aren't in TaskNotifier._tasks so deregisterTask:
    // won't stop I/O — this is the only teardown path.
    // No-op in legacy mode (sources are nil).
    [self teardownDispatchSources];
    [[TaskNotifier sharedInstance] deregisterTask:self];
    [self.delegate threadedTaskBrokenPipe];
}

// Main queue
- (void)didRegister {
    DLog(@"didRegister %@", self);
    // Wire up backpressure dependencies BEFORE starting dispatch sources.
    // taskDidRegister: sets task.tokenExecutor so shouldRead can apply
    // backpressure. Starting sources first would allow unconditional reads
    // via the executor==nil fallback path in shouldRead.
    [self.delegate taskDidRegister:self];
    if ([iTermAdvancedSettingsModel useFairnessScheduler]) {
        [self setupDispatchSources];
    }
}

// I did extensive benchmarking in May of 2025 when using the VT100_GANG optimization fully.
// I saw that this function almost never produces more than 1024 bytes. I think what's
// happening is that the TTY driver has an internal buffer of 1024 bytes. Because token
// execution is slower than reading and parsing, we enter a backpressure situation. At that
// point, we are in a situation where each read gives 1024 bytes and allows the PTY to fill
// with the next 1024 bytes. That becomes the stead state. Consequently, the semaphore that
// defines the depth of our queue also determines (in the steady state) how much data can be
// buffered and it's 1024 bytes * initial semaphore count.
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

#pragma mark - Dispatch Source Management (Fairness Scheduler)

// LIFECYCLE: Only call after fd >= 0 (i.e., after process launch succeeds)
- (void)setupDispatchSources {
    NSAssert(self.fd >= 0, @"setupDispatchSources called with invalid fd");

    _ioQueue = dispatch_queue_create("com.iterm2.pty-io", DISPATCH_QUEUE_SERIAL);

    // Read source - starts SUSPENDED, will be resumed by updateReadSourceState if conditions allow
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                         self.fd, 0, _ioQueue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_readSource, ^{
        [weakSelf handleReadEvent];
    });
    dispatch_resume(_readSource);  // Must resume before we can suspend
    dispatch_suspend(_readSource); // Start suspended - updateReadSourceState will resume
    _readSourceSuspended = YES;

    // Write source - starts SUSPENDED until writeBuffer has data
    _writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE,
                                          self.fd, 0, _ioQueue);
    dispatch_source_set_event_handler(_writeSource, ^{
        [weakSelf handleWriteEvent];
    });
    dispatch_resume(_writeSource);  // Must resume before we can suspend
    dispatch_suspend(_writeSource); // Start suspended - updateWriteSourceState will resume
    _writeSourceSuspended = YES;

    // Initial state sync - resume sources if conditions allow
    [self updateReadSourceState];
    [self updateWriteSourceState];
}

// TEARDOWN: Must resume suspended sources before canceling to avoid crash
- (void)teardownDispatchSources {
    // Also tear down coprocess sources — they share _ioQueue.
    [self teardownCoprocessDispatchSources];

    dispatch_queue_t ioQueue = _ioQueue;
    dispatch_source_t readSource = _readSource;
    dispatch_source_t writeSource = _writeSource;

    // Clear source ivars first - this prevents updateReadSourceState/updateWriteSourceState
    // from dispatching any NEW blocks (they check _readSource/_writeSource != nil first).
    _readSource = nil;
    _writeSource = nil;

    if (!ioQueue) {
        return;
    }

    // Check if we're already on ioQueue to avoid deadlock from dispatch_sync.
    const char *currentLabel = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    const char *ioQueueLabel = dispatch_queue_get_label(ioQueue);
    BOOL onIOQueue = (currentLabel != NULL && ioQueueLabel != NULL &&
                      strcmp(currentLabel, ioQueueLabel) == 0);

    if (onIOQueue) {
        // Already on ioQueue - do teardown inline with current state.
        // No race here since we're already serialized on ioQueue.
        if (readSource) {
            if (_readSourceSuspended) {
                dispatch_resume(readSource);
            }
            dispatch_source_cancel(readSource);
        }
        if (writeSource) {
            if (_writeSourceSuspended) {
                dispatch_resume(writeSource);
            }
            dispatch_source_cancel(writeSource);
        }
    } else {
        // Not on ioQueue - use sync to capture state, then async to teardown.
        // The sync ensures all prior updateRead/WriteSourceState blocks have completed,
        // giving us the actual current state.
        __block BOOL readSuspended = NO;
        __block BOOL writeSuspended = NO;
        dispatch_sync(ioQueue, ^{
            readSuspended = self->_readSourceSuspended;
            writeSuspended = self->_writeSourceSuspended;
        });

        // Now teardown synchronously with the captured (consistent) state.
        // Using dispatch_sync ensures all cleanup completes before we return,
        // preventing races where the task is deallocated while blocks are pending.
        // No self access here - just the captured sources and suspend flags.
        dispatch_sync(ioQueue, ^{
            if (readSource) {
                if (readSuspended) {
                    dispatch_resume(readSource);
                }
                dispatch_source_cancel(readSource);
            }
            if (writeSource) {
                if (writeSuspended) {
                    dispatch_resume(writeSource);
                }
                dispatch_source_cancel(writeSource);
            }
        });
    }
}

#pragma mark - Unified State Check

// Helper to get effective ioAllowed, considering test override
- (BOOL)effectiveIoAllowed {
    if (_testIoAllowedOverride != nil) {
        return _testIoAllowedOverride.boolValue;
    }
    return self.jobManager.ioAllowed;
}

// All conditions that affect whether we should read
- (BOOL)shouldRead {
    iTermTokenExecutor *executor = (iTermTokenExecutor *)self.tokenExecutor;
    if (!executor) {
        // No executor means no backpressure tracking - allow reads
        return !self.paused && [self effectiveIoAllowed];
    }
    return !self.paused &&
           [self effectiveIoAllowed] &&
           executor.backpressureLevel < BackpressureLevelHeavy;
}

// All conditions that affect whether we should write
- (BOOL)shouldWrite {
    if (self.paused) {
        return NO;
    }
    // Test hook allows bypassing jobManager constraints for testing write source resume
    if (!_testShouldWriteOverride && (self.jobManager.isReadOnly || ![self effectiveIoAllowed])) {
        return NO;
    }
    [writeLock lock];
    BOOL hasData = [writeBuffer length] > 0;
    [writeLock unlock];
    return hasData;
}

// Called whenever ANY condition affecting read state changes
- (void)updateReadSourceState {
    if (!_ioQueue || !_readSource) {
        return;
    }
    BOOL shouldRead = [self shouldRead];
    dispatch_async(_ioQueue, ^{
        if (shouldRead && self->_readSourceSuspended && self->_readSource) {
            dispatch_resume(self->_readSource);
            self->_readSourceSuspended = NO;
        } else if (!shouldRead && !self->_readSourceSuspended && self->_readSource) {
            dispatch_suspend(self->_readSource);
            self->_readSourceSuspended = YES;
        }
    });
}

// Called whenever ANY condition affecting write state changes
- (void)updateWriteSourceState {
    if (!_ioQueue || !_writeSource) {
        return;
    }
    BOOL shouldWrite = [self shouldWrite];
    dispatch_async(_ioQueue, ^{
        if (shouldWrite && self->_writeSourceSuspended && self->_writeSource) {
            dispatch_resume(self->_writeSource);
            self->_writeSourceSuspended = NO;
        } else if (!shouldWrite && !self->_writeSourceSuspended && self->_writeSource) {
            dispatch_suspend(self->_writeSource);
            self->_writeSourceSuspended = YES;
        }
    });
}

#pragma mark - Dispatch Source Event Handlers

- (void)handleReadEvent {
    // Match processRead's batching: read up to 4KB (4 * MAXRW) per event
    // to reduce dispatch overhead while maintaining responsiveness.
    int iterations = 4;
    int totalBytesRead = 0;
    BOOL gotEOF = NO;
    char buffer[MAXRW * iterations];

    for (int i = 0; i < iterations; ++i) {
        ssize_t n = read(self.fd, buffer + totalBytesRead, MAXRW);
        if (n < 0) {
            if (errno != EAGAIN && errno != EINTR) {
                [self brokenPipe];
                return;
            }
            // EAGAIN/EINTR - stop reading but process what we have
            break;
        }
        if (n == 0) {
            // EOF - PTY slave side closed (child exited).
            // Deliver any buffered bytes before signaling broken pipe.
            gotEOF = YES;
            break;
        }
        totalBytesRead += n;
        if (n < MAXRW) {
            // Got less than requested - no more data available
            break;
        }
    }

    if (totalBytesRead > 0) {
        hasOutput = YES;

        // Send data to delegate via non-blocking path
        // (addTokens internally calls notifyScheduler which kicks FairnessScheduler)
        [self.delegate threadedReadTask:buffer length:totalBytesRead];

        // Route PTY output to coprocess (same as readTask:length:)
        @synchronized (self) {
            if (coprocess_ && !self.sshIntegrationActive) {
                [self writeToCoprocess:[NSData dataWithBytes:buffer length:totalBytesRead]];
            }
        }

        // Re-check state after read (backpressure may have increased)
        [self updateReadSourceState];
    }

    if (gotEOF) {
        [self brokenPipe];
    }
}

- (void)handleWriteEvent {
    [self processWrite];  // Existing method - drains writeBuffer

    // Re-check state after write (buffer may now be empty)
    [self updateWriteSourceState];

    // Write buffer shrank — coprocess read source may now be eligible to resume
    // (it suspends when writeBufferHasRoom returns NO).
    [self updateCoprocessReadSourceState];
}

// Called when data is added to writeBuffer
- (void)writeBufferDidChange {
    [self updateWriteSourceState];
}

#pragma mark - Coprocess Dispatch Sources (Fairness Scheduler)

- (void)setupCoprocessDispatchSources:(Coprocess *)coprocess {
    NSAssert(_ioQueue != nil, @"setupCoprocessDispatchSources called before _ioQueue created");

    int readFd = [coprocess readFileDescriptor];
    int writeFd = [coprocess writeFileDescriptor];
    if (readFd < 0 || writeFd < 0) {
        return;
    }

    __weak typeof(self) weakSelf = self;

    // Read source — reads coprocess stdout, feeds data back as PTY input
    _coprocessReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                                   readFd, 0, _ioQueue);
    dispatch_source_set_event_handler(_coprocessReadSource, ^{
        [weakSelf handleCoprocessReadEvent];
    });
    dispatch_resume(_coprocessReadSource);
    dispatch_suspend(_coprocessReadSource);
    _coprocessReadSourceSuspended = YES;

    // Write source — flushes outputBuffer to coprocess stdin
    _coprocessWriteSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE,
                                                    writeFd, 0, _ioQueue);
    dispatch_source_set_event_handler(_coprocessWriteSource, ^{
        [weakSelf handleCoprocessWriteEvent];
    });
    dispatch_resume(_coprocessWriteSource);
    dispatch_suspend(_coprocessWriteSource);
    _coprocessWriteSourceSuspended = YES;

    [self updateCoprocessReadSourceState];
    [self updateCoprocessWriteSourceState];
}

- (void)teardownCoprocessDispatchSources {
    dispatch_source_t readSource = _coprocessReadSource;
    dispatch_source_t writeSource = _coprocessWriteSource;

    _coprocessReadSource = nil;
    _coprocessWriteSource = nil;

    if (!_ioQueue) {
        return;
    }

    // Check if we're already on ioQueue to avoid deadlock.
    const char *currentLabel = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    const char *ioQueueLabel = dispatch_queue_get_label(_ioQueue);
    BOOL onIOQueue = (currentLabel != NULL && ioQueueLabel != NULL &&
                      strcmp(currentLabel, ioQueueLabel) == 0);

    if (onIOQueue) {
        if (readSource) {
            if (_coprocessReadSourceSuspended) {
                dispatch_resume(readSource);
            }
            dispatch_source_cancel(readSource);
        }
        if (writeSource) {
            if (_coprocessWriteSourceSuspended) {
                dispatch_resume(writeSource);
            }
            dispatch_source_cancel(writeSource);
        }
        _coprocessReadSourceSuspended = NO;
        _coprocessWriteSourceSuspended = NO;
    } else {
        __block BOOL readSuspended = NO;
        __block BOOL writeSuspended = NO;
        dispatch_sync(_ioQueue, ^{
            readSuspended = self->_coprocessReadSourceSuspended;
            writeSuspended = self->_coprocessWriteSourceSuspended;
        });
        dispatch_sync(_ioQueue, ^{
            if (readSource) {
                if (readSuspended) {
                    dispatch_resume(readSource);
                }
                dispatch_source_cancel(readSource);
            }
            if (writeSource) {
                if (writeSuspended) {
                    dispatch_resume(writeSource);
                }
                dispatch_source_cancel(writeSource);
            }
            self->_coprocessReadSourceSuspended = NO;
            self->_coprocessWriteSourceSuspended = NO;
        });
    }
}

#pragma mark - Coprocess Event Handlers

- (void)handleCoprocessReadEvent {
    Coprocess *coprocess;
    @synchronized (self) {
        coprocess = coprocess_;
    }
    if (!coprocess || [coprocess eof]) {
        return;
    }

    [coprocess read];

    if ([coprocess eof]) {
        [self handleCoprocessEOF];
        return;
    }

    NSData *data = [coprocess.inputBuffer copy];
    [coprocess.inputBuffer setLength:0];
    if (data.length > 0) {
        [self writeTask:data coprocess:YES];
    }

    [self updateCoprocessReadSourceState];
}

- (void)handleCoprocessWriteEvent {
    Coprocess *coprocess;
    @synchronized (self) {
        coprocess = coprocess_;
    }
    if (!coprocess || [coprocess eof]) {
        return;
    }

    @synchronized (self) {
        [coprocess write];
    }

    [self updateCoprocessWriteSourceState];
}

- (void)handleCoprocessEOF {
    Coprocess *coprocess;
    @synchronized (self) {
        coprocess = coprocess_;
    }
    if (!coprocess) {
        return;
    }

    pid_t pid = coprocess.pid;
    [coprocess terminate];

    @synchronized (self) {
        coprocess_ = nil;
        self.hasMuteCoprocess = NO;
    }

    [self teardownCoprocessDispatchSources];

    if (pid > 0) {
        [[TaskNotifier sharedInstance] waitForPid:pid];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.delegate taskMuteCoprocessDidChange:weakSelf hasMuteCoprocess:NO];
        [[TaskNotifier sharedInstance] notifyCoprocessChange];
    });
}

#pragma mark - Coprocess Source State Management

- (void)updateCoprocessReadSourceState {
    if (!_ioQueue || !_coprocessReadSource) {
        return;
    }
    BOOL shouldResume;
    @synchronized (self) {
        shouldResume = coprocess_ && ![coprocess_ eof] && [self writeBufferHasRoom];
    }
    dispatch_async(_ioQueue, ^{
        if (shouldResume && self->_coprocessReadSourceSuspended && self->_coprocessReadSource) {
            dispatch_resume(self->_coprocessReadSource);
            self->_coprocessReadSourceSuspended = NO;
        } else if (!shouldResume && !self->_coprocessReadSourceSuspended && self->_coprocessReadSource) {
            dispatch_suspend(self->_coprocessReadSource);
            self->_coprocessReadSourceSuspended = YES;
        }
    });
}

- (void)updateCoprocessWriteSourceState {
    if (!_ioQueue || !_coprocessWriteSource) {
        return;
    }
    BOOL shouldResume;
    @synchronized (self) {
        shouldResume = coprocess_ && [coprocess_ wantToWrite];
    }
    dispatch_async(_ioQueue, ^{
        if (shouldResume && self->_coprocessWriteSourceSuspended && self->_coprocessWriteSource) {
            dispatch_resume(self->_coprocessWriteSource);
            self->_coprocessWriteSourceSuspended = NO;
        } else if (!shouldResume && !self->_coprocessWriteSourceSuspended && self->_coprocessWriteSource) {
            dispatch_suspend(self->_coprocessWriteSource);
            self->_coprocessWriteSourceSuspended = YES;
        }
    });
}

- (void)stopCoprocess {
    [self teardownCoprocessDispatchSources];

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

+ (NSMutableDictionary *)mutableEnvironmentDictionary {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    extern char **environ;
    if (environ != NULL) {
        NSSet<NSString *> *forbiddenKeys = [NSSet setWithArray:@[ @"NSZombieEnabled",
                                                                  @"MallocStackLogging"]];
        for (int i = 0; environ[i]; i++) {
            NSString *kvp = [NSString stringWithUTF8String:environ[i]];
            NSRange equalsRange = [kvp rangeOfString:@"="];
            if (equalsRange.location != NSNotFound) {
                NSString *key = [kvp substringToIndex:equalsRange.location];
                NSString *value = [kvp substringFromIndex:equalsRange.location + 1];
                if (![forbiddenKeys containsObject:key]) {
                    result[key] = value;
                }
            } else {
                result[kvp] = @"";
            }
        }
    }
    return result;
}

// Returns a NSMutableDictionary containing the key-value pairs defined in the
// global "environ" variable.
- (NSMutableDictionary *)mutableEnvironmentDictionary {
    return [PTYTask mutableEnvironmentDictionary];
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
    iTermTTYStateInit(&ttyState,
                      newSize.cellSize,
                      newSize.pixelSize,
                      isUTF8);
    [_winSizeController setInitialSize:gridSize
                              viewSize:pointSize
                           scaleFactor:maybeScaleFactor];
    
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
     ^(iTermJobManagerForkAndExecStatus status, NSNumber *optionalErrorCode) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self didForkAndExec:progpath
                      withStatus:status
               optionalErrorCode:optionalErrorCode];
            if (completion) {
                completion();
            }
        });
    }];
}

// Main queue
- (void)didForkAndExec:(NSString *)progpath
            withStatus:(iTermJobManagerForkAndExecStatus)status
     optionalErrorCode:(NSNumber *)optionalErrorCode {
    switch (status) {
        case iTermJobManagerForkAndExecStatusSuccess:
            // Parent
            [self setTty:self.jobManager.tty];
            DLog(@"finished succesfully");
            break;

        case iTermJobManagerForkAndExecStatusTempFileError:
            [self showFailedToCreateTempSocketError];
            break;

        case iTermJobManagerForkAndExecStatusFailedToFork: {
            DLog(@"Unable to fork %@: %s", progpath, strerror(optionalErrorCode.intValue));
            NSString *error = @"Unable to fork child process: you may have too many processes already running.";
            if (optionalErrorCode) {
                error = [NSString stringWithFormat:@"%@ The system error was: %s", error, strerror(optionalErrorCode.intValue)];
            }
            [[iTermNotificationController sharedInstance] notify:@"Unable to fork!"
                                                 withDescription:error];
            [self.delegate taskDiedWithError:error];
            break;
        }

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

// iTermTask @optional protocol method
// Returns YES to indicate PTYTask uses dispatch_source for I/O instead of select().
// TaskNotifier will skip adding this task's FD to select() fd_sets.
- (BOOL)useDispatchSource {
    return [iTermAdvancedSettingsModel useFairnessScheduler];
}

- (BOOL)hasOutput {
    return hasOutput;
}

- (void)writeToCoprocess:(NSData *)data {
    @synchronized (self) {
        [coprocess_.outputBuffer appendData:data];
    }
    // Wake the coprocess write source so the buffer gets drained.
    [self updateCoprocessWriteSourceState];
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
        if (coprocess_ && !self.sshIntegrationActive) {
            [self writeToCoprocess:[NSData dataWithBytes:buffer length:length]];
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

#pragma mark - iTermLoggingHelper

// NOTE: This can be called before the task is launched. It is not used when logging plain text.
- (void)loggingHelperStart:(iTermLoggingHelper *)loggingHelper {
    self.loggingHelper = loggingHelper;
}

- (void)loggingHelperStop:(iTermLoggingHelper *)loggingHelper {
    self.loggingHelper = nil;
}

@end

@implementation PTYTask(WinSizeControllerDelegate)

- (BOOL)winSizeControllerIsReady {
    return self.fd != -1;
}

- (void)winSizeControllerSetGridSize:(VT100GridSize)gridSize
                            viewSize:(NSSize)pointSize
                         scaleFactor:(CGFloat)scaleFactor {
    PTYTaskSize desiredSize = {
        .cellSize = iTermTTYCellSizeMake(gridSize.width, gridSize.height),
        .pixelSize = iTermTTYPixelSizeMake(pointSize.width * scaleFactor,
                                           pointSize.height * scaleFactor)
    };
    iTermSetTerminalSize(self.fd, desiredSize);
    [self.delegate taskDidResizeToGridSize:gridSize pixelSize:NSMakeSize(desiredSize.pixelSize.width,
                                                                         desiredSize.pixelSize.height)];
}

@end

@implementation PTYTask (Testing)

- (BOOL)testHasReadSource {
    return _readSource != nil;
}

- (BOOL)testHasWriteSource {
    return _writeSource != nil;
}

- (BOOL)testIsReadSourceSuspended {
    return _readSourceSuspended;
}

- (BOOL)testIsWriteSourceSuspended {
    return _writeSourceSuspended;
}

- (BOOL)testWriteBufferHasData {
    [writeLock lock];
    BOOL hasData = [writeBuffer length] > 0;
    [writeLock unlock];
    return hasData;
}

- (void)testSetFd:(int)fd {
    // MultiServerJobManager.setFd: asserts fd == -1 and does nothing.
    // Replace with LegacyJobManager which has a simple fd property.
    if (![self.jobManager isKindOfClass:[iTermLegacyJobManager class]]) {
        self.jobManager = [[iTermLegacyJobManager alloc] initWithQueue:_jobManagerQueue];
    }
    self.jobManager.fd = fd;
}

- (void)testSetupDispatchSourcesForTesting {
    [self setupDispatchSources];
}

- (void)testTeardownDispatchSourcesForTesting {
    [self teardownDispatchSources];
}

- (void)testAppendDataToWriteBuffer:(NSData *)data {
    [writeLock lock];
    [writeBuffer appendData:data];
    [writeLock unlock];
}

- (BOOL)testShouldWriteOverride {
    return _testShouldWriteOverride;
}

- (void)setTestShouldWriteOverride:(BOOL)testShouldWriteOverride {
    _testShouldWriteOverride = testShouldWriteOverride;
}

- (NSNumber *)testIoAllowedOverride {
    return _testIoAllowedOverride;
}

- (void)setTestIoAllowedOverride:(NSNumber *)testIoAllowedOverride {
    _testIoAllowedOverride = testIoAllowedOverride;
}

- (void)testWaitForIOQueue {
    if (!_ioQueue) {
        return;
    }
    // Dispatch a sync block to the ioQueue - this will wait until
    // all previously queued async work has completed
    dispatch_sync(_ioQueue, ^{
        // Empty block - just waiting for queue to drain
    });
}

- (void)testWriteFromCoprocess:(NSData *)data {
    [self writeTask:data coprocess:YES];
}

@end
