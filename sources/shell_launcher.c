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

static const int kPtySlaveFileDescriptor = 1;

static void ExecCommand(void) {
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

static void Die(int sig) {
    int status;
    pid_t pid;
    do {
        pid = wait(&status);
    } while (pid == -1 && errno == EINTR);
    _exit(status);
}

static void ExecChild() {
    // Child process
    signal(SIGCHLD, SIG_DFL);

    // Dup slave to stdin and stderr. This closes the master (fd 0) in the process.
    dup2(kPtySlaveFileDescriptor, 0);
    dup2(kPtySlaveFileDescriptor, 2);

    ExecCommand();
}

// PTY Master on fd 0, PTY Slave on fd 1
int launch_shell(void) {
    // Set up a signal handler that makes the server die with the child's status code if the child
    // dies before the server is done setting itself up.
    signal(SIGCHLD, Die);

    // Start the child.
    pid_t pid = fork();
    if (pid == 0) {
        ExecChild();
        return -1;
    } else if (pid > 0) {
        // Prepare to run the server.

        // Don't need the slave here.
        close(kPtySlaveFileDescriptor);
        setsid();
        char path[256];
        snprintf(path, sizeof(path), "/tmp/iTerm2.socket.%d", getpid());

        // Run the server.
        int status = FileDescriptorServerRun(path, pid);
        return status;
    } else {
        // Fork returned an error!
        printf("fork failed: %s", strerror(errno));
        return 1;
    }
}
