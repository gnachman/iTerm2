//
//  shell_launcher.h
//  iTerm
//
//  Created by George Nachman on 9/15/13.
//
//

#ifndef iTerm_shell_launcher_h
#define iTerm_shell_launcher_h

#include <sys/types.h>
#include <sys/socket.h>

// Replaces the current process with $SHELL as a login session. If successful, it does not return.
int launch_shell(const char *customShell, int num_extra_args, const char **extra_args);

#endif
