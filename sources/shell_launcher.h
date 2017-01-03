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

#define NUM_FILE_DESCRIPTORS_TO_PASS_TO_SERVER 4

// Run a server that launches the program in argv[0] and creates a FileDescriptorServer.
int iterm2_server(int argc, char *const *argv);

// Replaces the current process with $SHELL as a login session. If successful, it does not return.
int launch_shell(void);

#endif
