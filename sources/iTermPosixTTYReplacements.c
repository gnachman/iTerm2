//
//  iTermPosixTTYReplacements.c
//  iTerm2
//
//  Created by George Nachman on 7/25/19.
//

#import "iTermPosixTTYReplacements.h"
#import "iTermFileDescriptorServer.h"
#import "iTermResourceLimitsHelper.h"
#import "legacy_server.h"

#include <assert.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/errno.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <unistd.h>
#include <util.h>

#define CTRLKEY(c) ((c)-'A'+1)

// https://gitlab.com/gnachman/iterm2/-/issues/10360
int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t attrs, int disclaim)
    API_AVAILABLE(macosx(10.14));

const int kNumFileDescriptorsToDup = NUM_FILE_DESCRIPTORS_TO_PASS_TO_SERVER;

void iTermPosixMoveFileDescriptors(int *orig, int count) {
    // This array keeps track of which file descriptors are in use and should not be dup2()ed over.
    // It has |inuseCount| valid elements. inuse must have inuseCount + arraycount(orig) elements.
    int inuse[count * 3];
    for (int i = 0; i < count; i++) {
        inuse[i] = i;
        inuse[count * 1 + i] = orig[i];
        inuse[count * 2 + i] = -1;
    }
    int inuseCount = 2 * count;
    // File descriptors get dup2()ed to temporary numbers first to avoid stepping on each other or
    // on any of the desired final values. Their temporary values go in here. The first is always
    // master, then slave, then server socket.
    int temp[count];

    for (int o = 0; o < count; o++) {  // iterate over orig
        int original = orig[o];

        // Try to find a candidate file descriptor that is not important to us (i.e., does not belong
        // to the inuse array).
        for (int candidate = 0; candidate < sizeof(inuse) / sizeof(*inuse); candidate++) {
            int isInUse = 0;
            for (int i = 0; i < sizeof(inuse) / sizeof(*inuse); i++) {
                if (inuse[i] == candidate) {
                    isInUse = 1;
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
    for (int i = 0; i < count; i++) {
        dup2(temp[i], i);
        close(temp[i]);
    }
}

// Like login_tty but makes fd 0 the master, fd 1 the slave, fd 2 an open unix-domain socket
// for transferring file descriptors, and fd 3 the write end of a pipe that closes when the server
// dies.
// IMPORTANT: This runs between fork and exec. Careful what you do.
static void iTermPosixTTYReplacementLoginTTY(int master,
                                             int slave,
                                             int serverSocketFd,
                                             int deadMansPipeWriteEnd) {
    setsid();
    ioctl(slave, TIOCSCTTY, NULL);

    int orig[NUM_FILE_DESCRIPTORS_TO_PASS_TO_SERVER] = { master, slave, serverSocketFd, deadMansPipeWriteEnd };
    iTermPosixMoveFileDescriptors(orig, NUM_FILE_DESCRIPTORS_TO_PASS_TO_SERVER);
}

int iTermPosixTTYReplacementForkPty(int *amaster,
                                    iTermTTYState *ttyState,
                                    int serverSocketFd,
                                    int deadMansPipeWriteEnd) {
    int master;
    int slave;

    iTermFileDescriptorServerLog("Calling openpty");
    if (openpty(&master, &slave, ttyState->tty, &ttyState->term, &ttyState->win) == -1) {
        iTermFileDescriptorServerLog("openpty failed: %s", strerror(errno));
        return -1;
    }

    iTermFileDescriptorServerLog("Calling fork");
    pid_t pid = fork();
    switch (pid) {
        case -1:
            // error
            iTermFileDescriptorServerLog("Fork failed: %s", strerror(errno));
            return -1;

        case 0:
            // child
            iTermPosixTTYReplacementLoginTTY(master, slave, serverSocketFd, deadMansPipeWriteEnd);
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

static void iTermSpawnFailed(const char *argpath, int errorFd, const char *message) {
    iTermSignalSafeWrite(errorFd, "## spawn failed ##\n");
    iTermSignalSafeWrite(errorFd, "Program: ");
    iTermSignalSafeWrite(errorFd, argpath);
    iTermSignalSafeWrite(errorFd, "\n");
    iTermSignalSafeWrite(errorFd, message);
    iTermSignalSafeWrite(errorFd, "\n");

    sleep(1);
    _exit(1);
}

static void iTermSpawnInitializeAttrs(const char *argpath, int errorFd, posix_spawnattr_t *attrsPtr) {
    short flags = 0;
    // Default signals
    flags |= POSIX_SPAWN_SETSIGDEF;
    // Close all file descriptors except those created by file actions.
    flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;
    // Act like exec, not fork+exec
    flags |= POSIX_SPAWN_SETEXEC;

    int rc = posix_spawnattr_init(attrsPtr);
    if (rc != 0) {
        iTermSpawnFailed(argpath, errorFd, strerror(errno));
    }
    rc = posix_spawnattr_setflags(attrsPtr, flags);
    if (rc != 0) {
        iTermSpawnFailed(argpath, errorFd, strerror(errno));
    }
    rc = responsibility_spawnattrs_setdisclaim(attrsPtr, 1);
    if (rc != 0) {
        iTermSpawnFailed(argpath, errorFd, strerror(errno));
    }
}

static void iTermSpawnInitializeActions(const char *argpath,
                                        int errorFd,
                                        posix_spawn_file_actions_t *actionsPtr,
                                        int closeFileDescriptors,
                                        int numFileDescriptorsToPreserve,
                                        const char *initialPwd) API_AVAILABLE(macosx(10.15)) {
    int rc = posix_spawn_file_actions_init(actionsPtr);
    if (rc != 0) {
        iTermSpawnFailed(argpath, errorFd, strerror(errno));
    }
    if (closeFileDescriptors) {
        // Move fds 0..<n to n..<2*n and add actions to dup them back so POSIX_SPAWN_CLOEXEC_DEFAULT
        // can close anything else that's open.
        for (int i = 0; i < numFileDescriptorsToPreserve; i++) {
            const int temp = numFileDescriptorsToPreserve + i;
            close(temp);
            dup2(i, temp);
            posix_spawn_file_actions_adddup2(actionsPtr, temp, i);
        }
    }
    if (initialPwd) {
        posix_spawn_file_actions_addchdir_np(actionsPtr, initialPwd);
    }
}

// uses posix_spawn with POSIX_SPAWN_SETEXEC to emulate exec but with more features.
void iTermSpawnExec(char *argpath,
                    char *const *argv,
                    int closeFileDescriptors,
                    int restoreResourceLimits,
                    const iTermForkState *forkState,
                    const char *initialPwd,
                    char *const *newEnviron,
                    int errorFd) API_AVAILABLE(macosx(10.15)) {
    posix_spawnattr_t attrs;
    iTermSpawnInitializeAttrs(argpath, errorFd, &attrs);

    posix_spawn_file_actions_t actions;
    iTermSpawnInitializeActions(argpath,
                                errorFd,
                                &actions,
                                closeFileDescriptors,
                                forkState->numFileDescriptorsToPreserve,
                                initialPwd);

    // setrlimit is *not* documented as being safe to use between fork and exec, but I believe it to
    // be safe nonetheless. The implementation is simply to make a system call. Neither memory
    // allocation nor mutex locking occurs in user space. There isn't any other way to do this besides
    // passing the desired limits to the child process, which is pretty gross.
    if (restoreResourceLimits) {
        iTermResourceLimitsHelperRestoreSavedLimits();
    }

    posix_spawn(NULL,
                argpath,
                &actions,
                &attrs,
                argv,
                newEnviron);

    if (errorFd >= 0) {
        int e = errno;
        iTermSignalSafeWrite(errorFd, "## exec failed ##\n");
        iTermSignalSafeWrite(errorFd, "Program: ");
        iTermSignalSafeWrite(errorFd, argpath);
        if (e == ENOENT) {
            iTermSignalSafeWrite(errorFd, "\nNo such file or directory");
        } else {
            iTermSignalSafeWrite(errorFd, "\nErrno: ");
            iTermSignalSafeWriteInt(errorFd, e);
            iTermSignalSafeWrite(errorFd, "\nMessage: ");
            iTermSignalSafeWrite(errorFd, strerror(e));
        }
        iTermSignalSafeWrite(errorFd, "\n");
    }

    sleep(1);
    _exit(1);
}

void iTermExec(const char *argpath,
               const char **argv,
               int closeFileDescriptors,
               int restoreResourceLimits,
               const iTermForkState *forkState,
               const char *initialPwd,
               const char **newEnviron,
               int errorFd) {
    // BE CAREFUL WHAT YOU DO HERE!
    // See man sigaction for the list of legal function calls to make between fork and exec.

    // Do not start the new process with a signal handler.
    for (int i = 1; i < 32; i++) {
        signal(i, SIG_DFL);
    }

    // Unblock all signals.
    sigset_t signals;
    sigemptyset(&signals);
    sigprocmask(SIG_SETMASK, &signals, NULL);

    // Apple opens files without the close-on-exec flag (e.g., Extras2.rsrc).
    // See issue 2662.
    if (closeFileDescriptors) {
        // If running jobs in servers close file descriptors after exec when it's safe to
        // enumerate files in /dev/fd. This is the potentially very slow path (issue 5391).
        const int dtableSize = getdtablesize();
        for (int j = forkState->numFileDescriptorsToPreserve; j < dtableSize; j++) {
            close(j);
        }
    }

    // setrlimit is *not* documented as being safe to use between fork and exec, but I believe it to
    // be safe nonetheless. The implementation is simply to make a system call. Neither memory
    // allocation nor mutex locking occurs in user space. There isn't any other way to do this besides
    // passing the desired limits to the child process, which is pretty gross.
    if (restoreResourceLimits) {
        iTermResourceLimitsHelperRestoreSavedLimits();
    }

    if (initialPwd) {
        chdir(initialPwd);
    }

    // Sub in our environ for the existing one. Since Mac OS doesn't have execvpe, this hack
    // does the job.
    extern const char **environ;
    environ = newEnviron;
    execvp(argpath, (char* const*)argv);

    if (errorFd >= 0) {
        int e = errno;
        iTermSignalSafeWrite(errorFd, "## exec failed ##\n");
        iTermSignalSafeWrite(errorFd, "Program: ");
        iTermSignalSafeWrite(errorFd, argpath);
        if (e == ENOENT) {
            iTermSignalSafeWrite(errorFd, "\nNo such file or directory");
        } else {
            iTermSignalSafeWrite(errorFd, "\nErrno: ");
            iTermSignalSafeWriteInt(errorFd, e);
        }
        iTermSignalSafeWrite(errorFd, "\n");
    }

    sleep(1);
    _exit(1);
}

void iTermSignalSafeWrite(int fd, const char *message) {
    int len = 0;
    for (int i = 0; message[i]; i++) {
        len++;
    }
    ssize_t rc;
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


