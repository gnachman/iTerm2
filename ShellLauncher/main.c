//
//  main.m
//  ShellLauncher
//
//  Created by George Nachman on 12/6/20.
//

#import "shell_launcher.h"
#include <string.h>

int main(int argc, const char * argv[]) {
    // argv[2] is the shell specifier: "SHELL=/path" for custom shell, "-" for $SHELL.
    // If argc < 3 then $SHELL is used.
    // argv[3]+ are extra args to pass to the shell
    const char *customShell = NULL;
    if (argc >= 3 && strcmp(argv[2], "-") != 0) {
        customShell = argv[2];
    }

    if (argc >= 3) {
        return launch_shell(customShell,
                            argc - 3,
                            &argv[3]);
    } else {
        return launch_shell(customShell,
                            0,
                            NULL);
    }
}
