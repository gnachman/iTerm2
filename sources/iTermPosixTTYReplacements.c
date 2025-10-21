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
#include <os/availability.h>
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
// https://web.archive.org/web/20240208193541/https://www.qt.io/blog/the-curious-case-of-the-responsible-process
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

static void MakeBlocking(int fd) {
    int flags = fcntl(fd, F_GETFL);
    int rc = 0;
    do {
        rc = fcntl(fd, F_SETFL, flags & (~O_NONBLOCK));
    } while (rc == -1 && errno == EINTR);
}

// Like strerror but it's signal-safe.
const char *iTermStrerror(int err) {
    switch (err) {
        case EPERM:           return "Operation not permitted";
        case ENOENT:          return "No such file or directory";
        case ESRCH:           return "No such process";
        case EINTR:           return "Interrupted system call";
        case EIO:             return "Input/output error";
        case ENXIO:           return "Device not configured";
        case E2BIG:           return "Argument list too long";
        case ENOEXEC:         return "Exec format error";
        case EBADF:           return "Bad file descriptor";
        case ECHILD:          return "No child processes";
        case EDEADLK:         return "Resource deadlock avoided";
        case ENOMEM:          return "Cannot allocate memory";
        case EACCES:          return "Permission denied";
        case EFAULT:          return "Bad address";
        case EBUSY:           return "Device or resource busy";
        case EEXIST:          return "File exists";
        case EXDEV:           return "Cross-device link";
        case ENODEV:          return "Operation not supported by device";
        case ENOTDIR:         return "Not a directory";
        case EISDIR:          return "Is a directory";
        case EINVAL:          return "Invalid argument";
        case ENFILE:          return "Too many open files in system";
        case EMFILE:          return "Too many open files";
        case ENOTTY:          return "Inappropriate ioctl for device";
        case EFBIG:           return "File too large";
        case ENOSPC:          return "No space left on device";
        case ESPIPE:          return "Illegal seek";
        case EROFS:           return "Read-only file system";
        case EMLINK:          return "Too many links";
        case EPIPE:           return "Broken pipe";
        case EDOM:            return "Numerical argument out of domain";
        case ERANGE:          return "Result too large";
        case EAGAIN:          return "Resource temporarily unavailable";
        case EINPROGRESS:     return "Operation now in progress";
        case EALREADY:        return "Operation already in progress";
        case ENOTSOCK:        return "Socket operation on non-socket";
        case EDESTADDRREQ:    return "Destination address required";
        case EMSGSIZE:        return "Message too long";
        case EPROTOTYPE:      return "Protocol wrong type for socket";
        case ENOPROTOOPT:     return "Protocol not available";
        case EPROTONOSUPPORT: return "Protocol not supported";
        case ENOTSUP:         return "Operation not supported";
        case EAFNOSUPPORT:    return "Address family not supported";
        case EADDRINUSE:      return "Address already in use";
        case EADDRNOTAVAIL:   return "Can't assign requested address";
        case ENETDOWN:        return "Network is down";
        case ENETUNREACH:     return "Network unreachable";
        case ENETRESET:       return "Network dropped connection on reset";
        case ECONNABORTED:    return "Software caused connection abort";
        case ECONNRESET:      return "Connection reset by peer";
        case ENOBUFS:         return "No buffer space available";
        case EISCONN:         return "Socket is already connected";
        case ENOTCONN:        return "Socket is not connected";
        case ETIMEDOUT:       return "Operation timed out";
        case ECONNREFUSED:    return "Connection refused";
        case ELOOP:           return "Too many levels of symbolic links";
        case ENAMETOOLONG:    return "File name too long";
        case EHOSTUNREACH:    return "No route to host";
        case ENOTEMPTY:       return "Directory not empty";
        case EDQUOT:          return "Disc quota exceeded";
        case ESTALE:          return "Stale NFS file handle";
        case ENOLCK:          return "No locks available";
        case ENOSYS:          return "Function not implemented";
        case EOVERFLOW:       return "Value too large for data type";
        case ECANCELED:       return "Operation canceled";
        case EIDRM:           return "Identifier removed";
        case ENOMSG:          return "No message of desired type";
        case EILSEQ:          return "Illegal byte sequence";
        case EBADMSG:         return "Bad message";
        case EPROTO:          return "Protocol error";
        case ETIME:           return "STREAM ioctl timeout";
        case ENOPOLICY:       return "No such policy registered";
        case ENOTRECOVERABLE: return "State not recoverable";
        case EOWNERDEAD:      return "Previous owner died";
        case ENOTCAPABLE:     return "Capabilities insufficient";
        default:              return NULL;
    }
}

void iTermExec(const char *argpath,
               char **argv,
               int closeFileDescriptors,
               int restoreResourceLimits,
               const iTermForkState *forkState,
               const char *initialPwd,
               char **newEnviron,
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
    extern char **environ;
    environ = newEnviron;
    execvp(argpath, (char* const*)argv);

    if (errorFd >= 0) {
        const int e = errno;

        MakeBlocking(errorFd);
        iTermSignalSafeWrite(errorFd, "\n\n\n\n");
        iTermSignalSafeWrite(errorFd, "\033[97;41mThe program could not be run (execvp failed)\033[m\n\n");
        iTermSignalSafeWrite(errorFd, "The failing command was:\n");
        iTermSignalSafeWrite(errorFd, argpath);
        // Skip 0 because argv[0] is not informative to the user.
        for (int i = 1; argv[i]; i++) {
            iTermSignalSafeWrite(errorFd, " ");
            iTermSignalSafeWrite(errorFd, argv[i]);
        }
        iTermSignalSafeWrite(errorFd, "\n\n");
        iTermSignalSafeWrite(errorFd, "The reason for the failure was: ");
        const char *str = iTermStrerror(e);
        if (str) {
            iTermSignalSafeWrite(errorFd, str);
            iTermSignalSafeWrite(errorFd, " (errno ");
            iTermSignalSafeWriteInt(errorFd, e);
            iTermSignalSafeWrite(errorFd, ")");
        } else {
            iTermSignalSafeWrite(errorFd, "error number ");
            iTermSignalSafeWriteInt(errorFd, e);
        }
        iTermSignalSafeWrite(errorFd, "\n");
        iTermSignalSafeWrite(errorFd, "\n");
        switch (e) {
            case ENOENT:
                iTermSignalSafeWrite(errorFd, "The command specified in this profile is probably incorrect. Ensure you have provided the full path to the command in Settings > Profiles > General and that you have spelled it correctly. Your $PATH is not searched, so you must provide an absolute path.\n");

                break;
            case E2BIG: {
                iTermSignalSafeWrite(errorFd, "The number of bytes in the new process's argument list is larger than the system-imposed limit.  This limit is specified by the sysctl(3) MIB variable KERN_ARGMAX. The environment is:\n");
                for (int i = 0; environ[i]; i++) {
                    iTermSignalSafeWrite(errorFd, environ[i]);
                    iTermSignalSafeWrite(errorFd, "\n");
                }
                break;
            }
            case EACCES:
                iTermSignalSafeWrite(errorFd, "This error can occur for any of the following reasons:\n");
                iTermSignalSafeWrite(errorFd, "  * Search permission is denied for a component of the path prefix.\n");
                iTermSignalSafeWrite(errorFd, "  * The new process file is not an ordinary file.\n");
                iTermSignalSafeWrite(errorFd, "  * The new process file mode denies execute permission.\n");
                iTermSignalSafeWrite(errorFd, "  * The new process file is on a filesystem mounted with execution disabled (MNT_NOEXEC in ⟨sys/mount.h⟩).\n");
                break;
            case EINVAL:
            case EFAULT:
                iTermSignalSafeWrite(errorFd, "This appears to be a bug in iTerm2. Please report it at https://iterm2.com/bugs.");
                break;
            case EIO:
                iTermSignalSafeWrite(errorFd, "An I/O error occurred while reading from the file system.");
                break;
            case ELOOP:
                iTermSignalSafeWrite(errorFd, "Too many symbolic links were encountered in translating the pathname. This is probably a looping symbolic link.");
                break;
            case ENAMETOOLONG:
                iTermSignalSafeWrite(errorFd, "A component of a pathname exceeded ");
                iTermSignalSafeWriteInt(errorFd, NAME_MAX);
                iTermSignalSafeWrite(errorFd, " characters, or an entire path name exceeded ");
                iTermSignalSafeWriteInt(errorFd, PATH_MAX);
                iTermSignalSafeWrite(errorFd, " characters.");
                break;
            case ENOEXEC:
                iTermSignalSafeWrite(errorFd, "The new process file has the appropriate access permission, but has an unrecognized format (e.g., an invalid magic number in its header).");
                break;
            case ENOMEM:
                iTermSignalSafeWrite(errorFd, "The new process requires more virtual memory than is allowed by the imposed maximum (getrlimit(2)). Check if your system is low on memory using Activity Monitor.");
                break;
            case ENOTDIR:
                iTermSignalSafeWrite(errorFd, "A component of the path prefix is not a directory.");
                break;
            case ETXTBSY:
                iTermSignalSafeWrite(errorFd, "The new process file is a pure procedure (shared text) file that is currently open for writing or reading by some process.");
                break;
            default:
                iTermSignalSafeWrite(errorFd, "This error code is unexpected. Please report the value of Errno at https://iterm2.com/bugs.");
        }
    }
    iTermSignalSafeWrite(errorFd, "\e]1337;ExecFailed\e\\");

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


#pragma mark - Spawn

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

// Returns true on success.
static int iTermSpawnInitializeAttrs(const char *argpath, int errorFd, posix_spawnattr_t *attrsPtr, int fork) {
    short flags = 0;
    // Use spawn-sigdefault in attrs rather than inheriting parent's signal
    // actions (vis-a-vis caught vs default action)
    flags |= POSIX_SPAWN_SETSIGDEF;
    // Use spawn-sigmask of attrs for the initial signal mask.
    flags |= POSIX_SPAWN_SETSIGMASK;
    // Close all file descriptors except those created by file actions.
    flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;

    if (!fork) {
        // Act like exec, not fork+exec. This is necessary because the tty is
        // messed up when you don't use the flag. I'm not sure why.
        flags |= POSIX_SPAWN_SETEXEC;
    }

    int rc = posix_spawnattr_init(attrsPtr);
    if (rc != 0) {
        iTermSpawnFailed(argpath, errorFd, strerror(errno));
        return 0;
    }
    rc = posix_spawnattr_setflags(attrsPtr, flags);
    if (rc != 0) {
        iTermSpawnFailed(argpath, errorFd, strerror(errno));
        return 0;
    }
    rc = responsibility_spawnattrs_setdisclaim(attrsPtr, 1);
    if (rc != 0) {
        iTermSpawnFailed(argpath, errorFd, strerror(errno));
        return 0;
    }

    // Do not start the new process with signal handlers.
    sigset_t default_signals;
    sigfillset(&default_signals);
    for (int i = 1; i < NSIG; i++) {
        sigdelset(&default_signals, i);
    }
    posix_spawnattr_setsigdefault(attrsPtr, &default_signals);

    // Unblock all signals.
    sigset_t signals;
    sigemptyset(&signals);
    posix_spawnattr_setsigmask(attrsPtr, &signals);

    return 1;
}

static void iTermSpawnInitializeActions(const char *argpath,
                                        int errorFd,
                                        posix_spawn_file_actions_t *actionsPtr,
                                        const int *fds,
                                        int numFds,
                                        const char *initialPwd) API_AVAILABLE(macosx(10.15)) {
    int rc = posix_spawn_file_actions_init(actionsPtr);
    if (rc != 0) {
        iTermSpawnFailed(argpath, errorFd, strerror(errno));
    }
    for (int i = 0; i < numFds; i++) {
        if (fds[i] != i) {
            posix_spawn_file_actions_adddup2(actionsPtr, fds[i], i);
        } else {
            posix_spawn_file_actions_addinherit_np(actionsPtr, i);
        }
    }
    if (initialPwd) {
        posix_spawn_file_actions_addchdir_np(actionsPtr, initialPwd);
    }
}

// An alternative to iTermExec. It disclaims ownership to improve TCC behavior. See issue 10360.
// fds is an array of file descriptors that should survive in the child duped to 0, 1, ....
// Error output is written to errorFd.
// If fork is true, this is a standard posix_spawn. Otherwise, it replaces the current image.
// That's necessary because when forking the tty gets messed up for some reason I can't understand.
pid_t iTermSpawn(const char *argpath,
                char *const *argv,
                const int *fds,
                int numFds,
                const char *initialPwd,
                char **newEnviron,
                int errorFd,
                int fork) API_AVAILABLE(macosx(10.15)) {
    posix_spawnattr_t attrs;
    if (!iTermSpawnInitializeAttrs(argpath, errorFd, &attrs, fork)) {
        _exit(0);
    }

    posix_spawn_file_actions_t actions;
    iTermSpawnInitializeActions(argpath,
                                errorFd,
                                &actions,
                                fds,
                                numFds,
                                initialPwd);

    pid_t pid = -1;
    int rc;
    do {
        rc = posix_spawn(&pid,
                         argpath,
                         &actions,
                         &attrs,
                         argv,
                         newEnviron);
    } while (rc != 0 && errno == EAGAIN);

    if (rc != 0) {
        const int e = errno;
        iTermSignalSafeWrite(errorFd, "## spawn failed ##\n");
        iTermSignalSafeWrite(errorFd, "Program: ");
        iTermSignalSafeWrite(errorFd, argpath);
        iTermSignalSafeWrite(errorFd, "\n");
        if (e == ENOENT) {
            iTermSignalSafeWrite(errorFd, "\nNo such file or directory");
        } else {
            iTermSignalSafeWrite(errorFd, "\nErrno: ");
            iTermSignalSafeWriteInt(errorFd, e);
            iTermSignalSafeWrite(errorFd, "\nMessage: ");
            iTermSignalSafeWrite(errorFd, strerror(e));
        }
        iTermSignalSafeWrite(errorFd, "\n");
        _exit(1);
    }
    return pid;
}
