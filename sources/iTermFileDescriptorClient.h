#ifndef __ITERM_FILE_DESCRIPTOR_CLIENT_H
#define __ITERM_FILE_DESCRIPTOR_CLIENT_H

#include <unistd.h>

extern const char *kFileDescriptorClientErrorCouldNotConnect;

typedef struct {
    int ok;
    const char *error;
    int ptyMasterFd;
    pid_t childPid;
    int socketFd;
    pid_t serverPid;
} FileDescriptorClientResult;

// Connects to the server at the given path (which is a Unix Domain Socket) and receives a file
// descriptor and PID for the child it owns. The socket is left open. When iTerm2 dies unexpectedly,
// the socket will be closed; the server won't accept another connection until that happens.
FileDescriptorClientResult FileDescriptorClientRun(pid_t pid);

#endif  // __ITERM_FILE_DESCRIPTOR_CLIENT_H
