//
//  PTYTask+MRR.m
//  iTerm2Shared
//
//  Created by George Nachman on 4/22/19.
//

#if __has_feature(objc_arc)
#error This file must never be ARCified because it is not safe between fork and exec.
#endif

#import "PTYTask+MRR.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#include "iTermFileDescriptorClient.h"
#include "iTermFileDescriptorServer.h"
#include "iTermFileDescriptorSocketPath.h"
#import "iTermResourceLimitsHelper.h"
#include "shell_launcher.h"

#include <sys/ioctl.h>

static const int kNumFileDescriptorsToDup = NUM_FILE_DESCRIPTORS_TO_PASS_TO_SERVER;

void iTermSignalSafeWrite(int fd, const char *message) {
    int len = 0;
    for (int i = 0; message[i]; i++) {
        len++;
    }
    int rc;
    do {
        rc = write(fd, message, len);
    } while (rc < 0 && (errno == EAGAIN || errno == EINTR));
}

void iTermSignalSafeWriteInt(int fd, int n) {
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

static void iTermDidForkChild(const char *argpath,
                              const char **argv,
                              BOOL closeFileDescriptors,
                              const iTermForkState *forkState,
                              const char *initialPwd,
                              char **newEnviron) {
    // BE CAREFUL WHAT YOU DO HERE!
    // See man sigaction for the list of legal function calls to make between fork and exec.

    // Do not start the new process with a signal handler.
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

    // setrlimit is *not* documented as being safe to use between fork and exec, but I believe it to
    // be safe nonetheless. The implementation is simply to make a system call. Neither memory
    // allocation nor mutex locking occurs in user space. There isn't any other way to do this besides
    // passing the desired limits to the child process, which is pretty gross.
    iTermResourceLimitsHelperRestoreSavedLimits();
    
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


int iTermForkAndExecToRunJobInServer(iTermForkState *forkState,
                                     iTermTTYState *ttyState,
                                     NSString *tempPath,
                                     const char *argpath,
                                     const char **argv,
                                     BOOL closeFileDescriptors,
                                     const char *initialPwd,
                                     char **newEnviron) {
    // Get ready to run the server in a thread.
    __block int serverConnectionFd = -1;
    DLog(@"iTermForkAndExecToRunJobInServer");
    int serverSocketFd = iTermFileDescriptorServerSocketBindListen(tempPath.UTF8String);

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
    DLog(@"Calling MyForkPty");
    int fd = -1;
    forkState->pid = MyForkPty(&fd, ttyState, serverConnectionFd, forkState->deadMansPipe[1]);

    if (forkState->pid == (pid_t)0) {
        // Child
        iTermDidForkChild(argpath, argv, closeFileDescriptors, forkState, initialPwd, newEnviron);
        _exit(-1);
    }

    return fd;
}

int iTermForkAndExecToRunJobDirectly(iTermForkState *forkState,
                                     iTermTTYState *ttyState,
                                     const char *argpath,
                                     const char **argv,
                                     BOOL closeFileDescriptors,
                                     const char *initialPwd,
                                     char **newEnviron) {
    int fd;
    forkState->numFileDescriptorsToPreserve = 3;
    forkState->pid = forkpty(&fd, ttyState->tty, &ttyState->term, &ttyState->win);
    if (forkState->pid == (pid_t)0) {
        // Child
        iTermDidForkChild(argpath, argv, closeFileDescriptors, forkState, initialPwd, newEnviron);
        _exit(-1);
    }
    return fd;
}

