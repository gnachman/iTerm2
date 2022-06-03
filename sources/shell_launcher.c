 // This function runs the user's shell, replacing the current process with the shell, and
// inserting a "-" at the start of argv[0] to make it think it's a login shell. Unfortunately,
// Apple's login(1) doesn't let you preserve the working directory and also start a login shell,
// which iTerm2 needs to be able to do. This is meant to be run this way:
//   /usr/bin/login -fpl $USER /full/path/to/ShellLauncher --launch_shell

#include "shell_launcher.h"

#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <unistd.h>

static const char *UnprefixedCustomShell(const char *shell) {
    if (shell == NULL) {
        return NULL;
    }
    const char *prefix = "SHELL=";
    const size_t len = strlen(prefix);
    if (!strncmp(shell, prefix, len)) {
        return shell + len;
    }
    return NULL;
}

int launch_shell(const char *customShell, int num_extra_args, const char **extra_args) {
    const char *shell = UnprefixedCustomShell(customShell) ? : getenv("SHELL");
    if (!shell) {
        err(1, "SHELL environment variable not set");
    }
    if (customShell) {
        extern const char **environ;
        for (int i = 0; environ[i] != NULL; i++) {
            if (!strncmp(environ[i], "SHELL=", strlen("SHELL="))) {
                environ[i] = customShell;
                break;
            }
        }
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

    char *argv[num_extra_args + 2];
    argv[0] = argv0;
    int i;
    for (i = 0; i < num_extra_args; i++) {
        argv[i + 1] = strdup(extra_args[i]);
    }
    argv[i + 1] = NULL;

    execvp(shell, argv);
    err(1, "Failed to exec %s with arg %s", shell, argv0);
}
