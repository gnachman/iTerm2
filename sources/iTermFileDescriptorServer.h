#ifndef __ITERM_FILE_DESCRIPTOR_SERVER_H
#define __ITERM_FILE_DESCRIPTOR_SERVER_H

#include <sys/socket.h>

// Because xcode is hot garbage, syslog(LOG_DEBUG) goes to its console so we turn that off for debug builds.
#if DEBUG
#define FDLog(level, format, ...) do { \
    if (level < LOG_DEBUG) { \
        syslog(level, "Client(%d) " format, getpid(), ##__VA_ARGS__); \
    } \
} while (0)
#else
#define FDLog(level, format, ...) syslog(level, "Client(%d) " format, getpid(), ##__VA_ARGS__)
#endif

typedef union {
    struct cmsghdr cm;
    char control[CMSG_SPACE(sizeof(int))];
} iTermFileDescriptorControlMessage;

// Spin up a new server. |connectionFd| comes from iTermFileDescriptorServerAccept(),
// which should be run prior to fork()ing.
int iTermFileDescriptorServerRun(char *path, pid_t childPid, int connectionFd);

// Create a socket and listen on it. Returns the socket's file descriptor.
// This is used for connecting a client and server prior to fork.
// Follow it with a call to iTermFileDescriptorServerAccept().
int iTermFileDescriptorServerSocketBindListen(const char *path);

// Wait for a client connection on |socketFd|, which comes from
// iTermFileDescriptorServerSocketBindListen(). Returns a connection file descriptor,
// suitable to pass to iTermFileDescriptorServerRun() in |connectionFd|.
int iTermFileDescriptorServerAccept(int socketFd);

// Takes an array of file descriptors and its length as input. `results` should be an array of
// equal length. On return, the readable FDs will have the corresponding value in `results` set to
// true. Takes care of EINTR. Return value is number of readable FDs.
int iTermSelect(int *fds, int count, int *results);

void iTermFileDescriptorServerLog(char *format, ...);

#endif  // __ITERM_FILE_DESCRIPTOR_SERVER_H
