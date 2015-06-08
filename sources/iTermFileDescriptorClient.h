#ifndef __ITERM_FILE_DESCRIPTOR_CLIENT_H
#define __ITERM_FILE_DESCRIPTOR_CLIENT_H

#include <unistd.h>

typedef struct {
    int ok;
    const char *error;
    int ptyMasterFd;
    pid_t childPid;
    int socketFd;
    pid_t serverPid;
} iTermFileDescriptorServerConnection;

// Connects to the server at the given path (which is a Unix Domain Socket) and receives a file
// descriptor and PID for the child it owns. The socket is left open. When iTerm2 dies unexpectedly,
// the socket will be closed; the server won't accept another connection until that happens.
iTermFileDescriptorServerConnection iTermFileDescriptorClientRun(pid_t pid);

// Returns the file descriptor to a socket or -1. Follow this with a call to
// iTermFileDescriptorClientRead().
// This is used when the client and server connect prior to fork().
int iTermFileDescriptorClientConnect(const char *path);

// Blocks and reads a result from the socket.
iTermFileDescriptorServerConnection iTermFileDescriptorClientRead(int socketFd);

#endif  // __ITERM_FILE_DESCRIPTOR_CLIENT_H
