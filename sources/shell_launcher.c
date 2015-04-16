// This function the user's shell, replacing the current process with the shell, and
// inserting a "-" at the start of argv[0] to make it think it's a login shell. Unfortunately,
// Apple's login(1) doesn't let you preseve the working directory and also start a login shell,
// which iTerm2 needs to be able to do. This is meant to be run this way:
//   /usr/bin/login -fpl $USER iTerm.app --launch_shell

#include "shell_launcher.h"
#include <err.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <unistd.h>
#include <util.h>
#include <stdio.h>

int launch_shell(void)
{
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
    return 1;
}
