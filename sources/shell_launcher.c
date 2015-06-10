// This function the user's shell, replacing the current process with the shell, and
// inserting a "-" at the start of argv[0] to make it think it's a login shell. Unfortunately,
// Apple's login(1) doesn't let you preseve the working directory and also start a login shell,
// which iTerm2 needs to be able to do. This is meant to be run this way:
//   /usr/bin/login -fpl $USER iTerm.app --launch_shell

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
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
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

// Our child process died before the server got spun up. Wait for it to avoid a
// zombie and then exit. The actual exit status doesn't matter.
static void HandleEarlySigChild(int sig) {
    int status;
    pid_t pid;
    do {
        pid = wait(&status);
    } while (pid == -1 && errno == EINTR);
    _exit(status);
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

// Precondition: PTY Master on fd 0, PTY Slave on fd 1, connected unix domain socket on fd 2
int iterm2_server(int argc, char *const *argv) {
    // Set up a signal handler that makes the server die with the child's status code if the child
    // dies before the server is done setting itself up.
    signal(SIGCHLD, HandleEarlySigChild);

    // Start the child.
    pid_t pid = fork();
    if (pid == 0) {
        ExecChild(argc, argv);
        return -1;
    } else if (pid > 0) {
        // Prepare to run the server.

        // Don't need the slave here.
        close(kPtySlaveFileDescriptor);
        setsid();
        char path[PATH_MAX + 1];
        iTermFileDescriptorSocketPath(path, sizeof(path), getpid());

        // Run the server.
        int status = iTermFileDescriptorServerRun(path, pid, kPtySocketFileDescriptor);
        return status;
    } else {
        // Fork returned an error!
        printf("fork failed: %s", strerror(errno));
        return 1;
    }
}
