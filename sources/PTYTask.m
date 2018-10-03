#define MAXRW 1024

#import "Coprocess.h"
#import "DebugLogging.h"
#import "iTermNotificationController.h"
#import "iTermProcessCache.h"
#import "NSWorkspace+iTerm.h"
#import "PreferencePanel.h"
#import "PTYTask.h"
#import "TaskNotifier.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermLSOF.h"
#import "iTermOrphanServerAdopter.h"
#import <OpenDirectory/OpenDirectory.h>

#include "iTermFileDescriptorClient.h"
#include "iTermFileDescriptorServer.h"
#include "iTermFileDescriptorSocketPath.h"
#include "shell_launcher.h"
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

#define CTRLKEY(c) ((c)-'A'+1)
const int kNumFileDescriptorsToDup = NUM_FILE_DESCRIPTORS_TO_PASS_TO_SERVER;

NSString *kCoprocessStatusChangeNotification = @"kCoprocessStatusChangeNotification";

typedef struct {
    pid_t pid;
    int connectionFd;
    int deadMansPipe[2];
    int numFileDescriptorsToPreserve;
} iTermForkState;

typedef struct {
    struct termios term;
    struct winsize win;
    char tty[PATH_MAX];
} iTermTTYState;

static void
setup_tty_param(iTermTTYState *ttyState,
                int width,
                int height,
                BOOL isUTF8) {
    struct termios *term = &ttyState->term;
    struct winsize *win = &ttyState->win;

    memset(term, 0, sizeof(struct termios));
    memset(win, 0, sizeof(struct winsize));

    // UTF-8 input will be added on demand.
    term->c_iflag = ICRNL | IXON | IXANY | IMAXBEL | BRKINT | (isUTF8 ? IUTF8 : 0);
    term->c_oflag = OPOST | ONLCR;
    term->c_cflag = CREAD | CS8 | HUPCL;
    term->c_lflag = ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL;

    term->c_cc[VEOF] = CTRLKEY('D');
    term->c_cc[VEOL] = -1;
    term->c_cc[VEOL2] = -1;
    term->c_cc[VERASE] = 0x7f;           // DEL
    term->c_cc[VWERASE] = CTRLKEY('W');
    term->c_cc[VKILL] = CTRLKEY('U');
    term->c_cc[VREPRINT] = CTRLKEY('R');
    term->c_cc[VINTR] = CTRLKEY('C');
    term->c_cc[VQUIT] = 0x1c;           // Control+backslash
    term->c_cc[VSUSP] = CTRLKEY('Z');
    term->c_cc[VDSUSP] = CTRLKEY('Y');
    term->c_cc[VSTART] = CTRLKEY('Q');
    term->c_cc[VSTOP] = CTRLKEY('S');
    term->c_cc[VLNEXT] = CTRLKEY('V');
    term->c_cc[VDISCARD] = CTRLKEY('O');
    term->c_cc[VMIN] = 1;
    term->c_cc[VTIME] = 0;
    term->c_cc[VSTATUS] = CTRLKEY('T');

    term->c_ispeed = B38400;
    term->c_ospeed = B38400;

    win->ws_row = height;
    win->ws_col = width;
    win->ws_xpixel = 0;
    win->ws_ypixel = 0;
}

static void iTermSignalSafeWrite(int fd, const char *message) {
    int len = 0;
    for (int i = 0; message[i]; i++) {
        len++;
    }
    int rc;
    do {
        rc = write(fd, message, len);
    } while (rc < 0 && (errno == EAGAIN || errno == EINTR));
}

static void iTermSignalSafeWriteInt(int fd, int n) {
    if (n == INT_MIN) {
        iTermSignalSafeWrite(fd, "int_min");
        return;
    }
    if (n < 0) {
        iTermSignalSafeWrite(fd, "-");
        n = -n;
    }
    if (n < 10) {
        char str[2] = { n + '0', 0 };
        iTermSignalSafeWrite(fd, str);
        return;
    }
    iTermSignalSafeWriteInt(fd, n / 10);
    iTermSignalSafeWriteInt(fd, n % 10);
}

static void iTermDidForkChild(const char *argpath,
                              const char **argv,
                              BOOL closeFileDescriptors,
                              const iTermForkState *forkState,
                              const char *initialPwd,
                              char **newEnviron) {
    // BE CAREFUL WHAT YOU DO HERE!
    // See man sigaction for the list of legal function calls to make between fork and exec.
    signal(SIGCHLD, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGPIPE);
    sigprocmask(SIG_UNBLOCK, &signals, NULL);

    // Apple opens files without the close-on-exec flag (e.g., Extras2.rsrc).
    // See issue 2662.
    if (closeFileDescriptors) {
        // If running jobs in servers close file descriptors after exec when it's safe to
        // enumerate files in /dev/fd. This is the potentially very slow path (issue 5391).
        for (int j = forkState->numFileDescriptorsToPreserve; j < getdtablesize(); j++) {
            close(j);
        }
    }

    chdir(initialPwd);

    // Sub in our environ for the existing one. Since Mac OS doesn't have execvpe, this hack
    // does the job.
    extern char **environ;
    environ = newEnviron;
    execvp(argpath, (char* const*)argv);

    // NOTE: This won't be visible when jobs run in servers :(
    // exec error
    int e = errno;
    iTermSignalSafeWrite(1, "## exec failed ##\n");
    iTermSignalSafeWrite(1, "Program: ");
    iTermSignalSafeWrite(1, argpath);
    iTermSignalSafeWrite(1, "\nErrno: ");
    if (e == ENOENT) {
        iTermSignalSafeWrite(1, "\nNo such file or directory");
    } else {
        iTermSignalSafeWrite(1, "\nErrno: ");
        iTermSignalSafeWriteInt(1, e);
    }
    iTermSignalSafeWrite(1, "\n");

    sleep(1);
}

// Like login_tty but makes fd 0 the master, fd 1 the slave, fd 2 an open unix-domain socket
// for transferring file descriptors, and fd 3 the write end of a pipe that closes when the server
// dies.
// IMPORTANT: This runs between fork and exec. Careful what you do.
static void MyLoginTTY(int master, int slave, int serverSocketFd, int deadMansPipeWriteEnd) {
    setsid();
    ioctl(slave, TIOCSCTTY, NULL);

    // This array keeps track of which file descriptors are in use and should not be dup2()ed over.
    // It has |inuseCount| valid elements. inuse must have inuseCount + arraycount(orig) elements.
    int inuse[3 * kNumFileDescriptorsToDup] = {
       0, 1, 2, 3,  // FDs get duped to the lowest numbers so reserve them
       master, slave, serverSocketFd, deadMansPipeWriteEnd,  // FDs to get duped, which mustn't be overwritten
       -1, -1, -1, -1 };  // Space for temp values to ensure they don't get reused
    int inuseCount = 2 * kNumFileDescriptorsToDup;

    // File descriptors get dup2()ed to temporary numbers first to avoid stepping on each other or
    // on any of the desired final values. Their temporary values go in here. The first is always
    // master, then slave, then server socket.
    int temp[kNumFileDescriptorsToDup];

    // The original file descriptors to renumber.
    int orig[kNumFileDescriptorsToDup] = { master, slave, serverSocketFd, deadMansPipeWriteEnd };

    for (int o = 0; o < sizeof(orig) / sizeof(*orig); o++) {  // iterate over orig
        int original = orig[o];

        // Try to find a candidate file descriptor that is not important to us (i.e., does not belong
        // to the inuse array).
        for (int candidate = 0; candidate < sizeof(inuse) / sizeof(*inuse); candidate++) {
            BOOL isInUse = NO;
            for (int i = 0; i < sizeof(inuse) / sizeof(*inuse); i++) {
                if (inuse[i] == candidate) {
                    isInUse = YES;
                    break;
                }
            }
            if (!isInUse) {
                // t is good. dup orig[o] to t and close orig[o]. Save t in temp[o].
                inuse[inuseCount++] = candidate;
                temp[o] = candidate;
                dup2(original, candidate);
                close(original);
                break;
            }
        }
    }

    // Dup the temp values to their desired values (which happens to equal the index in temp).
    // Close the temp file descriptors.
    for (int i = 0; i < sizeof(orig) / sizeof(*orig); i++) {
        dup2(temp[i], i);
        close(temp[i]);
    }
}

// Just like forkpty but fd 0 the master and fd 1 the slave.
static int MyForkPty(int *amaster,
                     iTermTTYState *ttyState,
                     int serverSocketFd,
                     int deadMansPipeWriteEnd) {
    assert([iTermAdvancedSettingsModel runJobsInServers]);
    int master;
    int slave;

    iTermFileDescriptorServerLog("Calling openpty");
    if (openpty(&master, &slave, ttyState->tty, &ttyState->term, &ttyState->win) == -1) {
        NSLog(@"openpty failed: %s", strerror(errno));
        return -1;
    }

    iTermFileDescriptorServerLog("Calling fork");
    pid_t pid = fork();
    switch (pid) {
        case -1:
            // error
            NSLog(@"Fork failed: %s", strerror(errno));
            return -1;

        case 0:
            // child
            MyLoginTTY(master, slave, serverSocketFd, deadMansPipeWriteEnd);
            return 0;

        default:
            // parent
            *amaster = master;
            close(slave);
            close(serverSocketFd);
            close(deadMansPipeWriteEnd);
            return pid;
    }
}

static int iTermForkToRunJobInServer(iTermForkState *forkState,
                                     iTermTTYState *ttyState,
                                     NSString *tempPath) {
    int serverSocketFd = iTermFileDescriptorServerSocketBindListen(tempPath.UTF8String);

    // Get ready to run the server in a thread.
    __block int serverConnectionFd = -1;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    // In another thread, accept on the unix domain socket. Since it's
    // already listening, there's no race here. connect will block until
    // accept is called if the main thread wins the race. accept will block
    // til connect is called if the background thread wins the race.
    iTermFileDescriptorServerLog("Kicking off a background job to accept() in the server");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        iTermFileDescriptorServerLog("Now running the accept queue block");
        serverConnectionFd = iTermFileDescriptorServerAccept(serverSocketFd);

        // Let the main thread go. This is necessary to ensure that
        // serverConnectionFd is written to before the main thread uses it.
        iTermFileDescriptorServerLog("Signal the semaphore");
        dispatch_semaphore_signal(semaphore);
    });

    // Connect to the server running in a thread.
    forkState->connectionFd = iTermFileDescriptorClientConnect(tempPath.UTF8String);
    assert(forkState->connectionFd != -1);  // If this happens the block dispatched above never returns. Ran out of FDs, presumably.

    // Wait for serverConnectionFd to be written to.
    iTermFileDescriptorServerLog("Waiting for the semaphore");
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    iTermFileDescriptorServerLog("The semaphore was signaled");

    dispatch_release(semaphore);

    // Remove the temporary file. The server will create a new socket file
    // if the client dies. That file's name is dependent on its process ID,
    // which we don't know yet, so that's why this temp file dance has to
    // be done.
    unlink(tempPath.UTF8String);

    // Now fork. This variant of forkpty passes through the master, slave,
    // and serverConnectionFd to the child job.
    pipe(forkState->deadMansPipe);

    // This closes serverConnectionFd and deadMansPipe[1] in the parent process but not the child.
    iTermFileDescriptorServerLog("Calling MyForkPty");
    forkState->numFileDescriptorsToPreserve = kNumFileDescriptorsToDup;
    int fd;
    forkState->pid = MyForkPty(&fd, ttyState, serverConnectionFd, forkState->deadMansPipe[1]);
    return fd;
}

static void HandleSigChld(int n) {
    // This is safe to do because write(2) is listed in the sigaction(2) man page
    // as allowed in a signal handler. Calling a method is *NOT* safe since something might
    // be fiddling with the runtime. I saw a lot of crashes where CoreData got interrupted by
    // a sigchild while doing class_addMethod and that caused a crash because of a method call.
    UnblockTaskNotifier();
}

@interface PTYTaskLock : NSObject
@end

@implementation PTYTaskLock
@end

@interface PTYTask ()
@property(atomic, assign) BOOL hasMuteCoprocess;
@property(atomic, assign) BOOL coprocessOnlyTaskIsDead;
@property(atomic, retain) NSFileHandle *logHandle;
@property(nonatomic, copy) NSString *logPath;
@end

@implementation PTYTask {
    NSString *_tty;
    pid_t _serverPid;  // -1 when servers are not in use.
    pid_t _serverChildPid;  // -1 when servers are not in use.
    pid_t _childPid;  // -1 when servers are in use; otherwise is pid of child.
    int fd;
    int status;
    NSString* path;
    BOOL hasOutput;

    NSLock* writeLock;  // protects writeBuffer
    NSMutableData* writeBuffer;


    Coprocess *coprocess_;  // synchronized (self)
    BOOL brokenPipe_;
    NSString *command_;  // Command that was run if launchWithPath:arguments:etc was called

    // Number of spins of the select loop left before we tell the delegate we were deregistered.
    int _spinsNeeded;
    BOOL _paused;

    int _socketFd;  // File descriptor for unix domain socket connected to server. Only safe to close after server is dead.

    VT100GridSize _desiredSize;
    NSTimeInterval _timeOfLastSizeChange;
    BOOL _rateLimitedSetSizeToDesiredSizePending;
}

// This is (I hope) the equivalent of the command "dscl . read /Users/$USER UserShell", which
// appears to be how you get the user's shell nowadays. Returns nil if it can't be gotten.
+ (NSString *)userShell {
    if (![iTermAdvancedSettingsModel useOpenDirectory]) {
        return nil;
    }

    DLog(@"Trying to figure out the user's shell.");
    NSError *error = nil;
    ODNode *node = [ODNode nodeWithSession:[ODSession defaultSession]
                                      type:kODNodeTypeLocalNodes
                                     error:&error];
    if (!node) {
        DLog(@"Failed to get node for default session: %@", error);
        return nil;
    }
    ODQuery *query = [ODQuery queryWithNode:node
                             forRecordTypes:kODRecordTypeUsers
                                  attribute:kODAttributeTypeRecordName
                                  matchType:kODMatchEqualTo
                                queryValues:NSUserName()
                           returnAttributes:kODAttributeTypeStandardOnly
                             maximumResults:0
                                      error:&error];
    if (!query) {
        DLog(@"Failed to query for record matching user name: %@", error);
        return nil;
    }
    DLog(@"Performing synchronous request.");
    NSArray *result = [query resultsAllowingPartial:NO error:nil];
    DLog(@"Got %lu results", (unsigned long)result.count);
    ODRecord *record = [result firstObject];
    DLog(@"Record is %@", record);
    NSArray *shells = [record valuesForAttribute:kODAttributeTypeUserShell error:&error];
    if (!shells) {
        DLog(@"Error getting shells: %@", error);
        return nil;
    }
    DLog(@"Result has these shells: %@", shells);
    NSString *shell = [shells firstObject];
    DLog(@"Returning %@", shell);
    return shell;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serverPid = (pid_t)-1;
        _socketFd = -1;
        _childPid = (pid_t)-1;
        fd = -1;
        _serverChildPid = -1;
        writeBuffer = [[NSMutableData alloc] init];
        writeLock = [[NSLock alloc] init];
    }
    return self;
}

- (void)dealloc {
    [[TaskNotifier sharedInstance] deregisterTask:self];

    // TODO: The use of killpg seems pretty sketchy. It takes a pgid_t, not a
    // pid_t. Are they guaranteed to always be the same for process group
    // leaders?
    if (_childPid > 0) {
        // Terminate an owned child.
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_childPid];
        killpg(_childPid, SIGHUP);
    } else if (_serverChildPid) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_serverChildPid];
        // Kill a server-owned child.
        // TODO: Don't want to do this when Sparkle is upgrading.
        killpg(_serverChildPid, SIGHUP);
    }

    [self closeFileDescriptor];
    [_logPath release];
    [_logHandle closeFile];
    [_logHandle release];
    [writeLock release];
    [writeBuffer release];
    [_tty release];
    [path release];
    [command_ release];

    @synchronized (self) {
        [[self coprocess] mainProcessDidTerminate];
        [coprocess_ release];
    }

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"PTYTask(child pid %d, server-child pid %d, filedesc %d)",
              _serverChildPid, _serverPid, fd];
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
}

- (BOOL)pidIsChild {
    return _serverChildPid == -1 && _childPid != -1;
}

- (pid_t)serverPid {
    return _serverPid;
}

- (int)fd {
    return fd;
}

- (pid_t)pid {
    if (_serverChildPid != -1) {
        return _serverChildPid;
    } else {
        return _childPid;
    }
}

- (int)status {
    return status;
}

- (NSString *)path {
    return path;
}

- (NSString *)getWorkingDirectory {
    if (self.pid == -1) {
        DLog(@"Want to use the kernel to get the working directory but pid = -1");
        return nil;
    }
    return [iTermLSOF workingDirectoryOfProcess:self.pid];
}

- (BOOL)logging {
    @synchronized(self) {
        return (_logHandle != nil);
    }
}

- (Coprocess *)coprocess {
    @synchronized (self) {
        return coprocess_;
    }
    return nil;
}

- (void)setCoprocess:(Coprocess *)coprocess {
    @synchronized (self) {
        [coprocess_ autorelease];
        coprocess_ = [coprocess retain];
        self.hasMuteCoprocess = coprocess_.mute;
    }
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
        fd > 0 &&
        isatty(fd) &&
        tcgetattr(fd, &termAttributes) == 0) {
        return !(termAttributes.c_lflag & ECHO) && (termAttributes.c_lflag & ICANON);
    } else {
        return NO;
    }
}

- (BOOL)hasBrokenPipe {
    return brokenPipe_;
}

- (NSString *)originalCommand {
    return command_;
}

- (void)launchWithPath:(NSString *)progpath
             arguments:(NSArray *)args
           environment:(NSDictionary *)env
                 width:(int)width
                height:(int)height
                isUTF8:(BOOL)isUTF8
           autologPath:(NSString *)autologPath
           synchronous:(BOOL)synchronous
            completion:(void (^)(void))completion {
    DLog(@"launchWithPath:%@ args:%@ env:%@ width:%@ height:%@ isUTF8:%@ autologPath:%@ synchronous:%@",
         progpath, args, env, @(width), @(height), @(isUTF8), autologPath, @(synchronous));

    if ([iTermAdvancedSettingsModel runJobsInServers]) {
        // We want to run
        //   iTerm2 --server progpath args
        NSArray *updatedArgs = [@[ @"--server", progpath ] arrayByAddingObjectsFromArray:args];
        [self reallyLaunchWithPath:[[NSBundle mainBundle] executablePath]
                         arguments:updatedArgs
                       environment:env
                             width:width
                            height:height
                            isUTF8:isUTF8
                       autologPath:autologPath
                       synchronous:synchronous
                        completion:completion];
    } else {
        [self reallyLaunchWithPath:progpath
                         arguments:args
                       environment:env
                             width:width
                            height:height
                            isUTF8:isUTF8
                       autologPath:autologPath
                       synchronous:synchronous
                        completion:completion];
    }
}

// Get the name of this task's current job. It is quite approximate! Any
// arbitrary tty-controller in the tty's pgid that has this task as an ancestor
// may be chosen. This function also implements a cache to avoid doing the
// potentially expensive system calls too often.
- (NSString *)currentJob:(BOOL)forceRefresh pid:(pid_t *)pid {
    iTermProcessInfo *info = [[iTermProcessCache sharedInstance] deepestForegroundJobForPid:self.pid];
    if (!info) {
        return nil;
    }

    if (pid) {
        *pid = info.processID;
    }
    return info.name;
}

- (void)writeTask:(NSData *)data {
    if (self.isCoprocessOnly) {
        // Send keypresses to tmux.
        [_delegate retain];
        NSData *copyOfData = [data copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate writeForCoprocessOnlyTask:copyOfData];
            [_delegate release];
            [copyOfData release];
        });
    } else {
        // Write as much as we can now through the non-blocking pipe
        // Lock to protect the writeBuffer from the IO thread
        [writeLock lock];
        [writeBuffer appendData:data];
        [[TaskNotifier sharedInstance] unblock];
        [writeLock unlock];
    }
}

- (void)sendSignal:(int)signo toServer:(BOOL)toServer {
    if (toServer && _serverPid != -1) {
        DLog(@"Sending signal to server %@", @(_serverPid));
        kill(_serverPid, signo);
    } else if (_serverChildPid != -1) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_serverChildPid];
        kill(_serverChildPid, signo);
    } else if (_childPid >= 0) {
        [[iTermProcessCache sharedInstance] unregisterTrackedPID:_childPid];
        kill(_childPid, signo);
    }
}

- (void)setSize:(VT100GridSize)size {
    DLog(@"Set terminal size to %@", VT100GridSizeDescription(size));
    if (self.fd == -1) {
        return;
    }

    _desiredSize = size;
    [self rateLimitedSetSizeToDesiredSize];
}

- (void)stop {
    self.paused = NO;
    [self stopLogging];
    [self sendSignal:SIGHUP toServer:NO];
    [self killServerIfRunning];

    if (fd >= 0) {
        [self closeFileDescriptor];
        [[TaskNotifier sharedInstance] deregisterTask:self];
        // Require that it spin twice so we can be completely sure that the task won't get called
        // again. If we add the observer just before select() was going to be called, it wouldn't
        // mean anything; but after the second call, we know we've been moved into the dead pool.
        @synchronized(self) {
            _spinsNeeded = 2;
        }
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(notifierDidSpin)
                                                     name:kTaskNotifierDidSpin
                                                   object:nil];
        // Force a spin
        [[TaskNotifier sharedInstance] unblock];

        // This isn't an atomic update, but select() should be resilient to
        // being passed a half-broken fd. We must change it because after this
        // function returns, a new task may be created with this fd and then
        // the select thread wouldn't know which task a fd belongs to.
        fd = -1;
    }
    if (self.isCoprocessOnly) {
        self.coprocessOnlyTaskIsDead = YES;
    }
}

- (BOOL)startLoggingToFileWithPath:(NSString*)aPath shouldAppend:(BOOL)shouldAppend {
    @synchronized(self) {
        self.logPath = [aPath stringByStandardizingPath];

        [_logHandle closeFile];
        self.logHandle = [NSFileHandle fileHandleForWritingAtPath:_logPath];
        if (_logHandle == nil) {
            NSFileManager *fileManager = [NSFileManager defaultManager];
            [fileManager createFileAtPath:_logPath contents:nil attributes:nil];
            self.logHandle = [NSFileHandle fileHandleForWritingAtPath:_logPath];
        }
        if (shouldAppend) {
            [_logHandle seekToEndOfFile];
        } else {
            [_logHandle truncateFileAtOffset:0];
        }

        return self.logging;
    }
}

- (void)stopLogging {
    @synchronized(self) {
        [_logHandle closeFile];
        self.logPath = nil;
        self.logHandle = nil;
    }
}

- (void)brokenPipe {
    brokenPipe_ = YES;
    [[TaskNotifier sharedInstance] deregisterTask:self];
    [self.delegate threadedTaskBrokenPipe];
}

- (void)processRead {
    int iterations = 4;
    int bytesRead = 0;

    char buffer[MAXRW * iterations];
    for (int i = 0; i < iterations; ++i) {
        // Only read up to MAXRW*iterations bytes, then release control
        ssize_t n = read(fd, buffer + bytesRead, MAXRW);
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
    [self retain];
    [writeLock lock];

    // Only write up to MAXRW bytes, then release control
    char* ptr = [writeBuffer mutableBytes];
    unsigned int length = [writeBuffer length];
    if (length > MAXRW) {
        length = MAXRW;
    }
    ssize_t written = write(fd, [writeBuffer mutableBytes], length);

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
    [self autorelease];
}

- (void)stopCoprocess {
    pid_t thePid = 0;
    @synchronized (self) {
        if (coprocess_.pid > 0) {
            thePid = coprocess_.pid;
        }
        [coprocess_ terminate];
        [coprocess_ release];
        coprocess_ = nil;
        self.hasMuteCoprocess = NO;
    }
    if (thePid) {
        [[TaskNotifier sharedInstance] waitForPid:thePid];
    }
    [[TaskNotifier sharedInstance] performSelectorOnMainThread:@selector(notifyCoprocessChange)
                                                    withObject:nil
                                                 waitUntilDone:NO];
}

- (void)logData:(const char *)buffer length:(int)length {
    @synchronized(self) {
        if ([self logging]) {
            @try {
                [_logHandle writeData:[NSData dataWithBytes:buffer
                                                     length:length]];
            } @catch (NSException *exception) {
                DLog(@"Exception while logging %@ bytes of data: %@", @(length), exception);
                [self stopLogging];
            }
        }
    }
}

- (BOOL)tryToAttachToServerWithProcessId:(pid_t)thePid {
    if (![iTermAdvancedSettingsModel runJobsInServers]) {
        return NO;
    }
    if (_serverChildPid != -1) {
        return NO;
    }

    // TODO: This server code is super scary so I'm NSLog'ing it to make it easier to recover
    // logs. These should eventually become DLog's and the log statements in the server should
    // become LOG_DEBUG level.
    DLog(@"tryToAttachToServerWithProcessId: Attempt to connect to server for pid %d", (int)thePid);
    iTermFileDescriptorServerConnection serverConnection = iTermFileDescriptorClientRun(thePid);
    if (!serverConnection.ok) {
        NSLog(@"Failed with error %s", serverConnection.error);
        return NO;
    } else {
        DLog(@"Succeeded.");
        [self attachToServer:serverConnection];

        // Prevent any future attempt to connect to this server as an orphan.
        char buffer[PATH_MAX + 1];
        iTermFileDescriptorSocketPath(buffer, sizeof(buffer), thePid);
        [[iTermOrphanServerAdopter sharedInstance] removePath:[NSString stringWithUTF8String:buffer]];
        [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
        return YES;
    }
}

- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection {
    assert([iTermAdvancedSettingsModel runJobsInServers]);
    fd = serverConnection.ptyMasterFd;
    _serverPid = serverConnection.serverPid;
    _serverChildPid = serverConnection.childPid;
    if (_serverChildPid > 0) {
        [[iTermProcessCache sharedInstance] registerTrackedPID:_serverChildPid];
    }
    _socketFd = serverConnection.socketFd;
    [[TaskNotifier sharedInstance] registerTask:self];
}

// Sends a signal to the server. This breaks it out of accept()ing forever when iTerm2 quits.
- (void)killServerIfRunning {
    if (_serverPid >= 0) {
        // This makes the server unlink its socket and exit immediately.
        kill(_serverPid, SIGUSR1);

        // Mac OS seems to have a bug in waitpid. I've seen a case where the child has exited
        // (ps shows it in parens) but when the parent calls waitPid it just hangs. Rather than
        // wait here, I'll add the server to the deadpool. The TaskNotifier thread can wait
        // on it when it spins. I hope in this weird case that waitpid doesn't take long to run
        // and that it's rare enough that the zombies don't pile up. Not much else I can do.
        [[TaskNotifier sharedInstance] waitForPid:_serverPid];

        // Don't want to leak these. They exist to let the server know when iTerm2 crashes, but if
        // the server is dead it's not needed any more.
        close(_socketFd);
        _socketFd = -1;
        NSLog(@"File descriptor server exited with status %d", status);
    }
}

- (void)registerAsCoprocessOnlyTask {
    self.isCoprocessOnly = YES;
    [[TaskNotifier sharedInstance] registerTask:self];
}

- (void)writeToCoprocessOnlyTask:(NSData *)data {
    if (self.coprocess) {
        TaskNotifier *taskNotifier = [TaskNotifier sharedInstance];
        [taskNotifier lock];
        @synchronized (self) {
            [self.coprocess.outputBuffer appendData:data];
        }
        [taskNotifier unlock];

        // Wake up the task notifier so the coprocess's output buffer will be sent to its file
        // descriptor.
        [taskNotifier unblock];
    }
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

// Returns an array of C strings terminated with a null pointer of the form
// KEY=VALUE that is based on this process's "environ" variable. Values passed
// in "env" are added or override existing environment vars. Both the returned
// array and all string pointers within it are malloced and should be free()d
// by the caller.
- (char **)environWithOverrides:(NSDictionary *)env {
    NSMutableDictionary *environmentDict = [self mutableEnvironmentDictionary];
    for (NSString *k in env) {
        environmentDict[k] = env[k];
    }
    char **environment = malloc(sizeof(char*) * (environmentDict.count + 1));
    int i = 0;
    for (NSString *k in environmentDict) {
        NSString *temp = [NSString stringWithFormat:@"%@=%@", k, environmentDict[k]];
        environment[i++] = strdup([temp UTF8String]);
    }
    environment[i] = NULL;
    return environment;
}

- (NSDictionary *)environmentBySettingShell:(NSDictionary *)originalEnvironment {
    NSString *shell = [PTYTask userShell];
    if (!shell) {
        return originalEnvironment;
    }
    NSMutableDictionary *newEnvironment = [[originalEnvironment mutableCopy] autorelease];
    newEnvironment[@"SHELL"] = [[shell copy] autorelease];
    return newEnvironment;
}

- (void)setCommand:(NSString *)command {
    [command_ autorelease];
    command_ = [command copy];
}

- (void)populateArgvArray:(const char **)argv
              fromProgram:(NSString *)progpath
                     args:(NSArray *)args
                    count:(int)max {
    argv[0] = [[progpath stringByStandardizingPath] UTF8String];
    if (args != nil) {
        int i;
        for (i = 0; i < max; ++i) {
            argv[i + 1] = [args[i] UTF8String];
        }
    }
    argv[max + 1] = NULL;
}

- (void)showFailedToCreateTempSocketError {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"Error";
    alert.informativeText = [NSString stringWithFormat:@"An error was encountered while creating a temporary file with mkstemps. Verify that %@ exists and is writable.", NSTemporaryDirectory()];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)forkToRunJobDirectlyWithForkState:(iTermForkState *)forkState
                                 ttyState:(iTermTTYState *)ttyState {
    forkState->pid = _childPid = forkpty(&fd, ttyState->tty, &ttyState->term, &ttyState->win);
    if (_childPid > 0) {
        [[iTermProcessCache sharedInstance] registerTrackedPID:_childPid];
    }
    forkState->numFileDescriptorsToPreserve = 3;
}

- (void)failedToForkWithEnvironment:(char **)newEnviron program:(NSString *)progpath {
    DLog(@"Unable to fork %@: %s", progpath, strerror(errno));
    [[iTermNotificationController sharedInstance] notify:@"Unable to fork!" withDescription:@"You may have too many processes already running."];
    [self freeEnvironment:newEnviron];
}

- (void)freeEnvironment:(char **)newEnviron {
    for (int j = 0; newEnviron[j]; j++) {
        free(newEnviron[j]);
    }
    free(newEnviron);
}

- (void)finishHandshakeWithJobInServer:(const iTermForkState *)forkState ttyState:(const iTermTTYState *)ttyState {
    DLog(@"begin handshake");
    iTermFileDescriptorServerConnection serverConnection =
    iTermFileDescriptorClientRead(forkState->connectionFd, forkState->deadMansPipe[0]);
    DLog(@"got connection");
    close(forkState->deadMansPipe[0]);
    DLog(@"closed dead mans pipe");
    if (serverConnection.ok) {
        // We intentionally leave connectionFd open. If iTerm2 stops unexpectedly then its closure
        // lets the server know it should call accept(). We now have two copies of the master PTY
        // file descriptor. Let's close the original one because attachToServer: will use the
        // copy in serverConnection.
        close(fd);
        DLog(@"close fd");
        fd = -1;

        // The serverConnection has the wrong server PID because the connection was made prior
        // to fork(). Update serverConnection with the real server PID.
        serverConnection.serverPid = forkState->pid;

        // Connect this task to the server's PIDs and file descriptor.
        DLog(@"attaching...");
        [self attachToServer:serverConnection];
        DLog(@"attached. Set nonblocking");
        self.tty = [NSString stringWithUTF8String:ttyState->tty];
        fcntl(fd, F_SETFL, O_NONBLOCK);
    } else {
        close(fd);
        NSLog(@"Server died immediately!");
        [_delegate taskDiedImmediately];
    }
    DLog(@"fini");
}

- (NSString *)tty {
    @synchronized([PTYTaskLock class]) {
        return [[_tty retain] autorelease];
    }
}

- (void)setTty:(NSString *)tty {
    @synchronized([PTYTaskLock class]) {
        [_tty autorelease];
        _tty = [tty copy];
    }
    if ([NSThread isMainThread]) {
        [self.delegate taskDidChangeTTY:self];
    } else {
        __weak id<PTYTaskDelegate> delegate = self.delegate;
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([weakSelf retain]) {
                [delegate taskDidChangeTTY:weakSelf];
            }
            [weakSelf release];
        });
    }
}

- (void)finishLaunchingDirectChild:(iTermTTYState *)ttyState {
    self.tty = [NSString stringWithUTF8String:ttyState->tty];
    fcntl(fd, F_SETFL, O_NONBLOCK);
    [[TaskNotifier sharedInstance] registerTask:self];
}

- (void)didForkParent:(const iTermForkState *)forkState newEnviron:(char **)newEnviron ttyState:(iTermTTYState *)ttyState {
    DLog(@"free environment");
    [self freeEnvironment:newEnviron];

    // Make sure the master side of the pty is closed on future exec() calls.
    DLog(@"fcntl");
    fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC);

    if (forkState->connectionFd > 0) {
        // Jobs run in servers. The client and server connected to each other
        // before forking. The server will send us the child pid now. We don't
        // really need the rest of the stuff in serverConnection since we already know
        // it, but that's ok.
        [self finishHandshakeWithJobInServer:forkState ttyState:ttyState];
    } else {
        // Jobs are direct children of iTerm2
        [self finishLaunchingDirectChild:ttyState];
    }
}

- (NSString *)pathToNewUnixDomainSocket {
    // Create a temporary filename for the unix domain socket. It'll only exist for a moment.
    NSString *tempPath = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"iTerm2-temp-socket."
                                                                             suffix:@""];
    if (tempPath == nil) {
        [self showFailedToCreateTempSocketError];
    }
    return tempPath;
}

- (void)reallyLaunchWithPath:(NSString *)progpath
                   arguments:(NSArray *)args
                 environment:(NSDictionary *)env
                       width:(int)width
                      height:(int)height
                      isUTF8:(BOOL)isUTF8
                 autologPath:(NSString *)autologPath
                 synchronous:(BOOL)synchronous
                  completion:(void (^)(void))completion {
    DLog(@"reallyLaunchWithPath:%@ args:%@ env:%@ width:%@ height:%@ isUTF8:%@ autologPath:%@ synchronous:%@",
         progpath, args, env, @(width), @(height), @(isUTF8), autologPath, @(synchronous));
    if (autologPath) {
        [self startLoggingToFileWithPath:autologPath shouldAppend:NO];
    }

    iTermTTYState ttyState;
    setup_tty_param(&ttyState, width, height, isUTF8);

    [self setCommand:progpath];
    env = [self environmentBySettingShell:env];
    DLog(@"After setting shell environment is %@", env);
    path = [progpath copy];
    NSString *commandToExec = [progpath stringByStandardizingPath];
    const char *argpath = [commandToExec UTF8String];

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

    int max = (args == nil) ? 0 : [args count];
    const char* argv[max + 2];
    [self populateArgvArray:argv fromProgram:progpath args:args count:max];

    DLog(@"Preparing to launch a job. Command is %@ and args are %@", commandToExec, args);
    DLog(@"Environment is\n%@", env);
    char **newEnviron = [self environWithOverrides:env];

    // Note: stringByStandardizingPath will automatically call stringByExpandingTildeInPath.
    const char *initialPwd = [[[env objectForKey:@"PWD"] stringByStandardizingPath] UTF8String];
    DLog(@"initialPwd=%s", initialPwd);
    iTermForkState forkState = {
        .connectionFd = -1,
        .deadMansPipe = { 0, 0 },
    };

    const BOOL runJobsInServers = [iTermAdvancedSettingsModel runJobsInServers];
    BOOL closeFileDescriptors = !runJobsInServers;
    if (runJobsInServers) {
        // Create a temporary filename for the unix domain socket. It'll only exist for a moment.
        DLog(@"get path to UDS");
        NSString *tempPath = [self pathToNewUnixDomainSocket];
        DLog(@"done");
        if (tempPath == nil) {
            [self freeEnvironment:newEnviron];
            if (completion != nil) {
                completion();
            }
            return;
        }

        // Begin listening on that path as a unix domain socket.
        DLog(@"fork");
        fd = iTermForkToRunJobInServer(&forkState, &ttyState, tempPath);
        DLog(@"done forking");
        _serverPid = forkState.pid;
    } else {
        [self forkToRunJobDirectlyWithForkState:&forkState ttyState:&ttyState];
    }
    if (forkState.pid == (pid_t)0) {
        // Child
        // Do not start the new process with a signal handler.
        iTermDidForkChild(argpath, argv, closeFileDescriptors, &forkState, initialPwd, newEnviron);
        _exit(-1);
    } else if (forkState.pid < (pid_t)0) {
        // Error
        [self failedToForkWithEnvironment:newEnviron program:progpath];
        if (completion != nil) {
            completion();
        }
        return;
    }
    // Parent
    [self didForkParent:&forkState newEnviron:newEnviron ttyState:&ttyState];
    if (completion != nil) {
        completion();
    }
}

#pragma mark I/O

- (BOOL)wantsRead {
    return !self.paused;
}

- (BOOL)wantsWrite {
    if (self.paused) {
        return NO;
    }
    [writeLock lock];
    BOOL wantsWrite = [writeBuffer length] > 0;
    [writeLock unlock];
    return wantsWrite;
}

- (BOOL)hasOutput {
    return hasOutput;
}

// The bytes in data were just read from the fd.
- (void)readTask:(char *)buffer length:(int)length {
    [self logData:buffer length:length];

    // The delegate is responsible for parsing VT100 tokens here and sending them off to the
    // main thread for execution. If its queues get too large, it can block.
    [self.delegate threadedReadTask:buffer length:length];

    @synchronized (self) {
        if (coprocess_) {
            [coprocess_.outputBuffer appendData:[NSData dataWithBytes:buffer length:length]];
        }
    }
}

- (void)closeFileDescriptor {
    if (fd != -1) {
        close(fd);
    }
}

#pragma mark Terminal Size

- (void)rateLimitedSetSizeToDesiredSize {
    if (_rateLimitedSetSizeToDesiredSizePending) {
        return;
    }

    static const NSTimeInterval kDelayBetweenSizeChanges = 0.2;
    if ([NSDate timeIntervalSinceReferenceDate] - _timeOfLastSizeChange < kDelayBetweenSizeChanges) {
        // Avoid problems with signal coalescing of SIGWINCH preventing redraw for the second size
        // change. For example, issue 5096 and 4494.
        _rateLimitedSetSizeToDesiredSizePending = YES;
        DLog(@" ** Rate limiting **");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDelayBetweenSizeChanges * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            _rateLimitedSetSizeToDesiredSizePending = NO;
            [self setTerminalSizeToDesiredSize];
        });
    } else {
        [self setTerminalSizeToDesiredSize];
    }
}

- (void)setTerminalSizeToDesiredSize {
    DLog(@"Set size of %@ to %@", _delegate, VT100GridSizeDescription(_desiredSize));
    _timeOfLastSizeChange = [NSDate timeIntervalSinceReferenceDate];

    struct winsize winsize;
    ioctl(fd, TIOCGWINSZ, &winsize);
    if (winsize.ws_col != _desiredSize.width || winsize.ws_row != _desiredSize.height) {
        DLog(@"Actually setting the size");
        winsize.ws_col = _desiredSize.width;
        winsize.ws_row = _desiredSize.height;
        ioctl(fd, TIOCSWINSZ, &winsize);
    }
}

#pragma mark Process Tree

- (pid_t)getFirstChildOfPid:(pid_t)parentPid {
    return [iTermLSOF pidOfFirstChildOf:parentPid];
}

#pragma mark - Notifications

// This runs in TaskNotifier's thread.
- (void)notifierDidSpin {
    BOOL unblock = NO;
    @synchronized(self) {
        unblock = (--_spinsNeeded) > 0;
    }
    if (unblock) {
        // Force select() to return so we get another spin even if there is no
        // activity on the file descriptors.
        [[TaskNotifier sharedInstance] unblock];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [self.delegate taskWasDeregistered];
    }
}

@end

