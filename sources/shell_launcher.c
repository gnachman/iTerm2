// This function runs the user's shell, replacing the current process with the shell, and
// inserting a "-" at the start of argv[0] to make it think it's a login shell. Unfortunately,
// Apple's login(1) doesn't let you preseve the working directory and also start a login shell,
// which iTerm2 needs to be able to do. This is meant to be run this way:
//   /usr/bin/login -fpl $USER /full/path/to/iTerm.app --launch_shell

#include "shell_launcher.h"
#include <err.h>
#include <errno.h>
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

static const int kPtySlaveFileDescriptor = 1;
static const int kPtySocketFileDescriptor = 2;

int launch_shell(void) {
    const char *shell = getenv("SHELL");
    if (!shell) {
        err(1, "SHELL environment variable not set");
    }

    char *slash = strrchr(shell, '/');
    char *argv0;
    int len;
    if (slash) {
        len = asprintf(&argv0, "-%s", slash + 1);
    } else {
        len = asprintf(&argv0, "-%s", shell);
    }
    if (!argv0) {
        err(1, "asprintf returned NULL (out of memory?)");
    }
    if (len <= 0) {
        err(1, "failed to format shell's argv[0]");
    }
    if (len >= MAXPATHLEN) {
        errx(1, "shell path is too long");
    }

    execlp(shell, argv0, (char*)0);
    err(1, "Failed to exec %s with arg %s", shell, argv0);
}

// Precondition: PTY Master on fd 0, PTY Slave on fd 1
static void ExecChild(int argc, char *const *argv) {
    // Child process
    signal(SIGCHLD, SIG_DFL);

    // Dup slave to stdin and stderr. This closes the master (fd 0) in the process.
    dup2(kPtySlaveFileDescriptor, 0);
    dup2(kPtySlaveFileDescriptor, 2);

    // TODO: The first arg should be just the last path component.
    execvp(argv[0], argv);
}

static void CreateProcessGroup() {
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

// Precondition: PTY Master on fd 0, PTY Slave on fd 1, connected unix domain socket on fd 2
int iterm2_server(int argc, char *const *argv) {
    // Block SIGCHLD so we can handle it when we're ready.
    sigset_t signal_set;
    sigemptyset(&signal_set);
    sigaddset(&signal_set, SIGCHLD);
    sigprocmask(SIG_BLOCK, &signal_set, NULL);

    // Start the child.
    pid_t pid = fork();
    if (pid == 0) {
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
