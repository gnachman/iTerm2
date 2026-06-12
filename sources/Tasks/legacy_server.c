//
//  legacy_server.c
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/6/20.
//

#include "legacy_server.h"

#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <paths.h>
#include <sys/msg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <unistd.h>
#include <util.h>
#include <stdio.h>
#include <signal.h>
#include <syslog.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include "iTermFileDescriptorServer.h"
#include "iTermFileDescriptorClient.h"
#include "iTermFileDescriptorSocketPath.h"

#include <mach/mach.h>
#include <servers/bootstrap.h>


static const int kPtySlaveFileDescriptor = 1;
static const int kPtySocketFileDescriptor = 2;


// Precondition: PTY Master on fd 0, PTY Slave on fd 1
static void ExecChild(int argc, char *const *argv) {
    // Child process
    signal(SIGCHLD, SIG_DFL);

    // Dup slave to stdin and stderr. This closes the master (fd 0) in the process.
    dup2(kPtySlaveFileDescriptor, 0);
    dup2(kPtySlaveFileDescriptor, 2);

    // TODO: The first arg should be just the last path component.
    execvp(argv[0], argv);
    int error = errno;
    printf("Failed to exec %s: %s\n", argv[0], strerror(errno));
    if (error == ENOENT) {
        printf("PATH=%s\n", getenv("PATH") ?: _PATH_DEFPATH);
    }
}

static void CreateProcessGroup(void) {
    pid_t pid = getpid();
    if (setpgid(pid, pid) < 0) {
        syslog(LOG_ERR, "setpgid(%d) failed: %s", pid, strerror(errno));
        return;
    }

    // This is copied from bash. The Linux man page for tcsetpgrp mentions you need to block SIGTTOU,
    // Mac OS's is silent on the matter, but bash is tested in the real world so better safe than
    // sorry.
    sigset_t signalsToBlock;
    sigemptyset(&signalsToBlock);
    sigaddset(&signalsToBlock, SIGTTIN);
    sigaddset(&signalsToBlock, SIGTTOU);
    sigaddset(&signalsToBlock, SIGTSTP);
    sigaddset(&signalsToBlock, SIGCHLD);

    sigset_t savedBlockedSignals;
    sigemptyset(&savedBlockedSignals);
    if (sigprocmask(SIG_BLOCK, &signalsToBlock, &savedBlockedSignals) < 0) {
        syslog(LOG_ERR, "sigprocmask in CreateProcessGroup failed: %s", strerror(errno));
        return;
    }
    if (tcsetpgrp(0, pid) < 0) {
        syslog(LOG_ERR, "tcsetpgrp(0, %d) failed: %s", pid, strerror(errno));
    }
    if (sigprocmask(SIG_SETMASK, &savedBlockedSignals, NULL) < 0) {
        syslog(LOG_ERR, "sigprocmask call to restore signals failed: %s", strerror(errno));
    }
}

static void
closefrom_fallback(int lowfd) {
    // Fall back on sysconf(_SC_OPEN_MAX).  We avoid checking
    // resource limits since it is possible to open a file descriptor
    // and then drop the rlimit such that it is below the open fd.
    //
    long maxfd = sysconf(_SC_OPEN_MAX);
    if (maxfd < 0) {
        maxfd = _POSIX_OPEN_MAX;
    }

    for (long fd = lowfd; fd < maxfd; fd++) {
        close(fd);
    }
}

static void
sudo_closefrom(int lowfd) {
    const char *path = "/dev/fd";
    DIR *dirp;
    if ((dirp = opendir(path)) != NULL) {
        struct dirent *dent;
        while ((dent = readdir(dirp)) != NULL) {
            int fd = atoi(dent->d_name);
            if (fd > lowfd && fd != dirfd(dirp)) {
                close(fd);
            }
        }
        closedir(dirp);
    } else {
        closefrom_fallback(lowfd);
    }
}

// On a traditional BSD system, the UID associated with a process controls the capabilities
// of that process. But this is not true on MacOS. For example, a Daemon whose UID is set to
// that of the logged in console user is not equivalent to an application that has been
// launched by that same user. The reason is that additionally to BSD process contexts MacOS
// has the Mach bootstrap process contexts, called namespaces.
// Bootstrap namespaces are arranged hierarchically. There is a System global namespace, below
// it we have a per-user namespace (non GUI), and below it we have a per-session GUI namespace,
// created by the WindowServer when the user logs in via GUI. (this namespace changes in some
// situations and it also changes when the user login/logout from the GUI session).

// Hierarchically,
// each level can access all their above-levels namespace services (their parents services)
// ----
//     System_Namespace
//          Per-User_Namespace
//              Per-Session_Namespace(GUI WindowServer)
// ----
// Technically the GUI per-session namespace is called 'Aqua' Session by Apple's API docs.
//
// Issue 4147 happens because the forked daemon is running in the Aqua session namespace. So
// when the user logout or a GUI crash happens, the forked daemon remains isolated in a lost
// per-session namespace. It partially loses its IPC capabilities to communicate with other
// processes. Partially because it gets isolated only on the Mach portion of the kernel. But
// on the BSD portion of the kernel the daemon is fine (file system, networking, pipes, etc).
// Everytime the GUI (WindowServer) restarts, another per-session namespace is created below
// the per-user namespace for that given user UID.
//
// So, before forking our iTerm2 Daemon we need to move it from the 'per-session' namespace
// where it is running to a level above it: To the 'per-user' namespace. This is necessary to
// keep the daemon accessible and securely working when the user logs out from the GUI session,
// or if the user changes the session via FastUserSwitching, or in case of crashes of the GUI
// session. (In a crash, WindowServer will recreate a new per-session namespace).
//
// By moving iTerm-Server Daemon we make it be available as a service to any 'per-session'
// namespace that already exists [the current one], or any new 'per-session' namespaces that
// may in future be (re)created below it.
//
// Important is to mention that its availability is to serve just the same user (the same UID).
// This is what we want, because all other BSD preparations here is done to create the
// iTerm-Server to serve just that given user who started it. If another user is logged-in via
// GUI via fast user switching, this other user will have its own Per-User session, and will
// have below it his Aqua per-session GUI belonging to its UID, and his programs running there,
// including his own iTerm-Server daemons forked just for it's UID use.
// Security on MacOS is provided by BSD Kernel portion + Mach Kernel portion.
// ----
//   System_Namespace [System]
//      |
//      ------ PerUSER_Namespace [Background] [user 501]
//      |      |
//      |      ----- PerSESSION_Namespace [Aqua] (GUI WindowServer) [user 501]
//      |
//      |
//      ------ PerUSER_Namespace [Background] [user 502]
//             |
//             ----- PerSESSION_Namespace [Aqua] (GUI WindowServer) [user 502]
// ----
//
// This way iTerm2 daemon is in conformation with current MacOS security rules mechanics,
// and we completely eliminate all the problems that raised issue 4147. Per-user namespace is
// the correct place for a user daemon to live and service it's services to the namespaces
// levels below it.
//
// *The Per-User namespace is the parent for all other context namespace for a given user. It
// is never destroyed by GUI logout or crashes. And it will exist until there is at least one
// daemon or service running on it, for that given user. [* from Apples documentation]
//
// That's the exact namespace where Launchd places daemons for a given user.
void MoveOutOfAquaSession(void) { // FIX for issue 4147
    // This function must be called just before fork();
    //
    // This funcion move the process from the Aqua 'per-sesion' namespace to the
    // same user 'per-user' namespace. This method is the standard method used
    // by Apple for doing this kind of move. It is exactly the same move method
    // used by Launchd.
    mach_port_t parent = MACH_PORT_NULL;
    kern_return_t kr;

    kr = bootstrap_parent(bootstrap_port, &parent);

    if (kr == KERN_SUCCESS) {
        // Detach server daemon process from the user's Aqua 'per-session' namespace,
        // and move it to the same UID 'per-user' namespace (just one level up).
        mach_port_mod_refs(mach_task_self(), bootstrap_port, MACH_PORT_RIGHT_SEND, -1);
        task_set_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, parent);

        return; /* All Done! now return, as we are ready to begin forking! */
    }
    // Never reach. Unless if we had failed to get the parent bootstrap port, which according
    // to Apple's documentation never happens. But I already saw rare weird system situations
    // where it may happen.
    // Almost impossible, but if it happens, for sure is a BUG. So log it just in case.
    FDLog(LOG_ERR, "BUG: Error getting parent BS port! Please report this msg and code: '%x'", kr);
}

// Precondition: PTY Master on fd 0, PTY Slave on fd 1, connected unix domain socket on fd 2
int iterm2_server(int argc, char *const *argv) {
    // Block SIGCHLD so we can handle it when we're ready.
    sigset_t signal_set;
    sigemptyset(&signal_set);
    sigaddset(&signal_set, SIGCHLD);
    sigprocmask(SIG_BLOCK, &signal_set, NULL);

    sudo_closefrom(NUM_FILE_DESCRIPTORS_TO_PASS_TO_SERVER);

    if (getenv("ITERM2_DISABLE_BOOTSTRAP")) {
        unsetenv("ITERM2_DISABLE_BOOTSTRAP");
    } else {
        // Let's move to the 'per-user' namespace! [Must be done here, just before the fork()]
        MoveOutOfAquaSession();
    }

    // Start the child.
    pid_t pid = fork();
    if (pid == 0) {
        // Keep only stdin, stdout, and stderr.
        for (int i = 3; i < NUM_FILE_DESCRIPTORS_TO_PASS_TO_SERVER; i++) {
            close(i);
        }

        // See discussion in issue 4288. For shells that don't have job control, this keeps SIGINT
        // from propagating up to the server. In other words, if the child process we exec below
        // installs a handler for SIGINT, this prevents SIGINT from percolating up and murdering
        // the server process. You can test this by setting your profile's command to the "catch"
        // program (cc tests/catch.c -o catch) and pressing ^C. The session should not terminate.
        CreateProcessGroup();

        // Unblock SIGCHLD in the child process.
        sigemptyset(&signal_set);
        sigaddset(&signal_set, SIGCHLD);
        sigprocmask(SIG_UNBLOCK, &signal_set, NULL);

        ExecChild(argc, argv);
        return -1;
    } else if (pid > 0) {
        // Prepare to run the server.

        // Don't need the slave here.
        close(kPtySlaveFileDescriptor);
        setsid();
        char path[PATH_MAX + 1];
        iTermFileDescriptorSocketPath(path, sizeof(path), getpid());

        // Run the server. It will unblock SIGCHILD when it's ready.
        int status = iTermFileDescriptorServerRun(path, pid, kPtySocketFileDescriptor);
        return status;
    } else {
        // Fork returned an error!
        printf("fork failed: %s", strerror(errno));
        return 1;
    }
}
