
// Debug option
#define PtyTaskDebugLog(fmt, ...)
// Use this instead to debug this module:
// #define PtyTaskDebugLog NSLog

#define MAXRW 1024

#import "PTYTask.h"
#import "Coprocess.h"
#import "PreferencePanel.h"
#import "ProcessCache.h"
#import "TaskNotifier.h"
#include <dlfcn.h>
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/user.h>
#include <unistd.h>
#include <util.h>

#define CTRLKEY(c) ((c)-'A'+1)

NSString *kCoprocessStatusChangeNotification = @"kCoprocessStatusChangeNotification";

static void
setup_tty_param(struct termios* term,
                struct winsize* win,
                int width,
                int height,
                BOOL isUTF8)
{
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

@implementation PTYTask
{
    pid_t pid;
    int fd;
    int status;
    id<PTYTaskDelegate> delegate;
    NSString* tty;
    NSString* path;
    BOOL hasOutput;

    NSLock* writeLock;  // protects writeBuffer
    NSMutableData* writeBuffer;

    NSString* logPath;
    NSFileHandle* logHandle;

    Coprocess *coprocess_;  // synchronized (self)
    BOOL brokenPipe_;
	NSString *command_;  // Command that was run if launchWithPath:arguments:etc was called
}

- (id)init
{
    self = [super init];
    if (self) {
        pid = (pid_t)-1;
        status = 0;
        delegate = nil;
        fd = -1;
        tty = nil;
        logPath = nil;
        @synchronized(logHandle) {
            logHandle = nil;
        }
        hasOutput = NO;

        writeBuffer = [[NSMutableData alloc] init];
        writeLock = [[NSLock alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [[TaskNotifier sharedInstance] deregisterTask:self];

    if (pid > 0) {
        killpg(pid, SIGHUP);
    }

    if (fd >= 0) {
        PtyTaskDebugLog(@"dealloc: Close fd %d\n", fd);
        close(fd);
    }

    [writeLock release];
    [writeBuffer release];
    [tty release];
    [path release];
        [command_ release];

    @synchronized (self) {
        [[self coprocess] mainProcessDidTerminate];
        [coprocess_ release];
    }

    [super dealloc];
}

- (BOOL)hasBrokenPipe
{
    return brokenPipe_;
}

static void reapchild(int n)
{
  // This intentionally does nothing.
  // We cannot ignore SIGCHLD because Sparkle (the software updater) opens a
  // Safari control which uses some buggy Netscape code that calls wait()
  // until it succeeds. If we wait() on its pid, that process locks because
  // it doesn't check if wait()'s failure is ECHLD. Instead of wait()ing here,
  // we reap our children when our select() loop sees that a pipes is broken.
}

- (NSString *)command
{
        return command_;
}

- (void)launchWithPath:(NSString*)progpath
             arguments:(NSArray*)args
           environment:(NSDictionary*)env
                 width:(int)width
                height:(int)height
                isUTF8:(BOOL)isUTF8
{
    struct termios term;
    struct winsize win;
    char theTtyname[PATH_MAX];

    [command_ autorelease];
    command_ = [progpath copy];
    path = [progpath copy];

    setup_tty_param(&term, &win, width, height, isUTF8);
    // Register a handler for the child death signal.
    signal(SIGCHLD, reapchild);
    const char* argpath;
    argpath = [[progpath stringByStandardizingPath] UTF8String];

    int max = (args == nil) ? 0 : [args count];
    const char* argv[max + 2];

    argv[0] = [[progpath stringByStandardizingPath] UTF8String];
    if (args != nil) {
        int i;
        for (i = 0; i < max; ++i) {
            argv[i + 1] = [[args objectAtIndex:i] cString];
        }
    }
    argv[max + 1] = NULL;
    const int envsize = env.count;
    const char *envKeys[envsize];
    const char *envValues[envsize];

    // This quiets an analyzer warning about envKeys[i] being uninitialized in setenv().
    bzero(envKeys, sizeof(char *) * envsize);
    bzero(envValues, sizeof(char *) * envsize);

    // Copy values from env (our custom environment vars) into envDict
    int i = 0;
    for (NSString *k in env) {
        NSString *v = [env objectForKey:k];
        envKeys[i] = [k UTF8String];
        envValues[i] = [v UTF8String];
        i++;
    }

    // Note: stringByStandardizingPath will automatically call stringByExpandingTildeInPath.
    const char *initialPwd = [[[env objectForKey:@"PWD"] stringByStandardizingPath] UTF8String];
    pid = forkpty(&fd, theTtyname, &term, &win);
    if (pid == (pid_t)0) {
        // Do not start the new process with a signal handler.
        signal(SIGCHLD, SIG_DFL);
        signal(SIGPIPE, SIG_DFL);
        sigset_t signals;
        sigemptyset(&signals);
        sigaddset(&signals, SIGPIPE);
        sigprocmask(SIG_UNBLOCK, &signals, NULL);

        chdir(initialPwd);
        for (i = 0; i < envsize; i++) {
            // The analyzer warning below is an obvious lie.
            setenv(envKeys[i], envValues[i], 1);
        }
        execvp(argpath, (char* const*)argv);

        /* exec error */
        fprintf(stdout, "## exec failed ##\n");
        fprintf(stdout, "argpath=%s error=%s\n", argpath, strerror(errno));

        sleep(1);
        _exit(-1);
    } else if (pid < (pid_t)0) {
        PtyTaskDebugLog(@"%@ %s", progpath, strerror(errno));
        NSRunCriticalAlertPanel(@"Unable to Fork!",
                                @"iTerm cannot launch the program for this session.",
                                @"Ok",
                                nil,
                                nil);
        return;
    }

    tty = [[NSString stringWithUTF8String:theTtyname] retain];
    NSParameterAssert(tty != nil);

    fcntl(fd,F_SETFL,O_NONBLOCK);
    [[TaskNotifier sharedInstance] registerTask:self];
}

- (BOOL)wantsRead
{
    return YES;
}

- (BOOL)wantsWrite
{
    [writeLock lock];
    BOOL wantsWrite = [writeBuffer length] > 0;
    [writeLock unlock];
    return wantsWrite;
}

- (BOOL)writeBufferHasRoom
{
    const int kMaxWriteBufferSize = 1024 * 10;
    [writeLock lock];
    BOOL hasRoom = [writeBuffer length] < kMaxWriteBufferSize;
    [writeLock unlock];
    return hasRoom;
}

- (void)processRead
{
    int iterations = 10;
    int bytesRead = 0;

    NSMutableData* data = [NSMutableData dataWithLength:MAXRW * iterations];
    for (int i = 0; i < iterations; ++i) {
        // Only read up to MAXRW*iterations bytes, then release control
        ssize_t n = read(fd, [data mutableBytes] + bytesRead, MAXRW);
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

    [data setLength:bytesRead];
    hasOutput = YES;

    // Send data to the terminal
    [self readTask:data];
}

- (void)processWrite
{
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

- (BOOL)hasOutput
{
    return hasOutput;
}

- (void)setDelegate:(id)object
{
    delegate = object;
}

- (id)delegate
{
    return delegate;
}

- (void)logData:(NSData *)data {
    @synchronized(logHandle) {
        if ([self logging]) {
            [logHandle writeData:data];
        }
    }
}

// The bytes in data were just read from the fd.
- (void)readTask:(NSData*)data
{
    [self logData:data];

    // forward the data to our delegate
    if ([delegate respondsToSelector:@selector(readTask:)]) {
        // This waitsUntilDone because otherwise we can read data from a child process faster than
        // we can parse it. The main thread will quickly end up overloaded with calls to readTask:,
        // never catching up, and never having a chance to draw or respond to input.
        NSObject *delegateObj = delegate;
        [delegateObj performSelectorOnMainThread:@selector(readTask:)
                                      withObject:data
                                   waitUntilDone:YES];
    }

    @synchronized (self) {
        [coprocess_.outputBuffer appendData:data];
    }
}

- (void)writeTask:(NSData*)data
{
    // Write as much as we can now through the non-blocking pipe
    // Lock to protect the writeBuffer from the IO thread
    [writeLock lock];
    [writeBuffer appendData:data];
    [[TaskNotifier sharedInstance] unblock];
    [writeLock unlock];
}

- (void)brokenPipe
{
    brokenPipe_ = YES;
    [[TaskNotifier sharedInstance] deregisterTask:self];
    if ([delegate respondsToSelector:@selector(brokenPipe)]) {
        NSObject *delegateObj = delegate;
        [delegateObj performSelectorOnMainThread:@selector(brokenPipe)
                                      withObject:nil
                                   waitUntilDone:YES];
    }
}

- (void)sendSignal:(int)signo
{
    if (pid >= 0) {
        kill(pid, signo);
    }
}

- (void)setWidth:(int)width height:(int)height
{
    PtyTaskDebugLog(@"Set terminal size to %dx%d", width, height);
    struct winsize winsize;
    // TODO(georgen): Access to fd should be synchronoized or else it should not be allowed to call this function from the main thread.
    if (fd == -1) {
        return;
    }

    ioctl(fd, TIOCGWINSZ, &winsize);
    if ((winsize.ws_col != width) || (winsize.ws_row != height)) {
        winsize.ws_col = width;
        winsize.ws_row = height;
        ioctl(fd, TIOCSWINSZ, &winsize);
    }
}

- (int)fd
{
    return fd;
}

- (pid_t)pid
{
    return pid;
}

- (void)stop
{
    [self loggingStop];
    [self sendSignal:SIGHUP];

    if (fd >= 0) {
        close(fd);
    }
    // This isn't an atomic update, but select() should be resilient to
    // being passed a half-broken fd. We must change it because after this
    // function returns, a new task may be created with this fd and then
    // the select thread wouldn't know which task a fd belongs to.
    fd = -1;
}

- (int)status
{
    return status;
}

- (NSString*)tty
{
    return tty;
}

- (NSString*)path
{
    return path;
}

- (BOOL)loggingStartWithPath:(NSString*)aPath
{
    BOOL rc;
    @synchronized(logHandle) {
        [logPath autorelease];
        logPath = [[aPath stringByStandardizingPath] copy];

        [logHandle autorelease];
        logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (logHandle == nil) {
            NSFileManager* fm = [NSFileManager defaultManager];
            [fm createFileAtPath:logPath contents:nil attributes:nil];
            logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        }
        [logHandle retain];
        [logHandle seekToEndOfFile];

        rc = (logHandle == nil ? NO : YES);
    }
    return rc;
}

- (void)loggingStop
{
    @synchronized(logHandle) {
        [logHandle closeFile];

        [logPath autorelease];
        [logHandle autorelease];
        logPath = nil;
        logHandle = nil;
    }
}

- (BOOL)logging
{
    BOOL rc;
    @synchronized(logHandle) {
        rc = (logHandle == nil ? NO : YES);
    }
    return rc;
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"PTYTask(pid %d, fildes %d)", pid, fd];
}

// This is a stunningly brittle hack. Find the child of parentPid with the
// oldest start time. This relies on undocumented APIs, but short of forking
// ps, I can't see another way to do it.

- (pid_t)getFirstChildOfPid:(pid_t)parentPid
{
    int numBytes;
    numBytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (numBytes <= 0) {
        return -1;
    }

    int* pids = (int*) malloc(numBytes+sizeof(int));
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
        int rc = proc_pidinfo(pids[i],
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

// Get the name of this task's current job. It is quite approximate! Any
// arbitrary tty-controller in the tty's pgid that has this task as an ancestor
// may be chosen. This function also implements a chache to avoid doing the
// potentially expensive system calls too often.
- (NSString*)currentJob:(BOOL)forceRefresh
{
    return [[ProcessCache sharedInstance] jobNameWithPid:pid];
}

- (NSString*)getWorkingDirectory
{
    struct proc_vnodepathinfo vpi;
    int ret;
    /* This only works if the child process is owned by our uid */
    ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof(vpi));
    if (ret <= 0) {
        // The child was probably owned by root (which is expected if it's
        // a login shell. Use the cwd of its oldest child instead.
        pid_t childPid = [self getFirstChildOfPid:pid];
        if (childPid > 0) {
            ret = proc_pidinfo(childPid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof(vpi));
        }
    }
    if (ret <= 0) {
        /* An error occured */
        return nil;
    } else if (ret != sizeof(vpi)) {
        /* Now this is very bad... */
        return nil;
    } else {
        /* All is good */
        return [NSString stringWithUTF8String:vpi.pvi_cdir.vip_path];
    }
}

- (void)stopCoprocess
{
    pid_t thePid = 0;
    @synchronized (self) {
        if (coprocess_.pid > 0) {
            thePid = coprocess_.pid;
        }
        [coprocess_ terminate];
        [coprocess_ release];
        coprocess_ = nil;
    }
    if (thePid) {
        [[TaskNotifier sharedInstance] waitForPid:thePid];
    }
    [[TaskNotifier sharedInstance] performSelectorOnMainThread:@selector(notifyCoprocessChange)
                                                    withObject:nil
                                                 waitUntilDone:NO];
}

- (void)setCoprocess:(Coprocess *)coprocess
{
    @synchronized (self) {
        [coprocess_ autorelease];
        coprocess_ = [coprocess retain];
    }
    [[TaskNotifier sharedInstance] unblock];
}

- (Coprocess *)coprocess
{
    @synchronized (self) {
        return coprocess_;
    }
    return nil;
}

- (BOOL)hasCoprocess
{
    @synchronized (self) {
        return coprocess_ != nil;
    }
    return NO;
}

- (BOOL)hasMuteCoprocess
{
    @synchronized (self) {
        return coprocess_ != nil && coprocess_.mute;
    }
    return NO;
}

@end

