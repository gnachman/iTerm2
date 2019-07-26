#ifndef __ITERM_FILE_DESCRIPTOR_SERVER_H
#define __ITERM_FILE_DESCRIPTOR_SERVER_H

#include "iTermFileDescriptorServerShared.h"

// Spin up a new server. |connectionFd| comes from iTermFileDescriptorServerAcceptAndClose(),
// which should be run prior to fork()ing.
int iTermFileDescriptorServerRun(char *path, pid_t childPid, int connectionFd);

// Wait for a client connection on |socketFd|, which comes from
// iTermFileDescriptorServerSocketBindListen(). Returns a connection file descriptor,
// suitable to pass to iTermFileDescriptorServerRun() in |connectionFd|.
int iTermFileDescriptorServerAcceptAndClose(int socketFd);

void iTermFileDescriptorServerLog(char *format, ...);

void SetRunningServer(void);

#endif  // __ITERM_FILE_DESCRIPTOR_SERVER_H
