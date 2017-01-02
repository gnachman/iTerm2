#include "iTermFileDescriptorClient.h"
#include "iTermFileDescriptorSocketPath.h"
#include "iTermFileDescriptorServer.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#define FDLog(level, format, ...) syslog(LOG_DEBUG, "Client(%d) " format, getpid(), ##__VA_ARGS__)

// Reads a message on the socket, and fills in receivedFileDescriptorPtr with a
// file descriptor if one was passed.
static ssize_t ReceiveMessageAndFileDescriptor(int fd,
                                               void *buffer,
                                               size_t bufferCapacity,
                                               int *receivedFileDescriptorPtr,
                                               int deadMansPipeReadEnd) {
    // Loop because sometimes the dynamic loader spews warnings (for example, when malloc logging
    // is enabled)
    while (1) {
        FDLog(LOG_DEBUG, "ReceiveMessageAndFileDescriptor\n");
        struct msghdr message;
        struct iovec ioVector[1];
        iTermFileDescriptorControlMessage controlMessage;

        message.msg_control = controlMessage.control;
        message.msg_controllen = sizeof(controlMessage.control);

        message.msg_name = NULL;
        message.msg_namelen = 0;

        ioVector[0].iov_base = buffer;
        ioVector[0].iov_len = bufferCapacity;
        message.msg_iov = ioVector;
        message.msg_iovlen = 1;

        ssize_t n;
        do {
            // There used to be a race condition where the server would die
            // really early and then we'd get stuck in recvmsg. See issue 4383.
            if (deadMansPipeReadEnd >= 0) {
                FDLog(LOG_DEBUG, "Calling select to get a file descriptor...");
                int fds[2] = { fd, deadMansPipeReadEnd };
                int readable[2];
                iTermSelect(fds, 2, readable);
                if (readable[1]) {
                    FDLog(LOG_DEBUG, "Server was dead before recevmsg. Did the shell terminate immediately?");
                    return -1;
                }
                FDLog(LOG_DEBUG, "assuming socket is readable");
            }
            FDLog(LOG_DEBUG, "calling recvmsg...");
            n = recvmsg(fd, &message, 0);
            FDLog(LOG_DEBUG, "recvmsg returned %zd, errno=%s\n", n, (n < 0 ? strerror(errno) : "n/a"));
        } while (n < 0 && errno == EINTR);

        if (n <= 0) {
            FDLog(LOG_NOTICE, "error from recvmsg %s\n", strerror(errno));
            return n;
        }
        FDLog(LOG_DEBUG, "recvmsg returned %d\n", (int)n);

        struct cmsghdr *messageHeader = CMSG_FIRSTHDR(&message);
        if (messageHeader != NULL && messageHeader->cmsg_len == CMSG_LEN(sizeof(int))) {
            if (messageHeader->cmsg_level != SOL_SOCKET) {
                FDLog(LOG_NOTICE, "Wrong cmsg level\n");
                return -1;
            }
            if (messageHeader->cmsg_type != SCM_RIGHTS) {
                FDLog(LOG_NOTICE, "Wrong cmsg type\n");
                return -1;
            }
            FDLog(LOG_DEBUG, "Got a fd\n");
            *receivedFileDescriptorPtr = *((int *)CMSG_DATA(messageHeader));
            FDLog(LOG_DEBUG, "Return %d\n", (int)n);
            return n;
        } else {
            FDLog(LOG_DEBUG, "No descriptor passed\n");
            *receivedFileDescriptorPtr = -1;       // descriptor was not passed, try again.
            // This is the only case where the loop repeats.
        }
    }
}

int iTermFileDescriptorClientConnect(const char *path) {
    int interrupted = 0;
    int socketFd;
    int flags;

    FDLog(LOG_DEBUG, "Trying to connect to %s", path);
    do {
        FDLog(LOG_DEBUG, "Calling socket()");
        socketFd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (socketFd == -1) {
            FDLog(LOG_NOTICE, "Failed to create socket: %s\n", strerror(errno));
            return -1;
        }

        struct sockaddr_un remote;
        remote.sun_family = AF_UNIX;
        strcpy(remote.sun_path, path);
        int len = strlen(remote.sun_path) + sizeof(remote.sun_family) + 1;
        FDLog(LOG_DEBUG, "Calling fcntl() 1");
        flags = fcntl(socketFd, F_GETFL, 0);

        // Put the socket in nonblocking mode so connect can fail fast if another iTerm2 is connected
        // to this server.
        FDLog(LOG_DEBUG, "Calling fcntl() 2");
        fcntl(socketFd, F_SETFL, flags | O_NONBLOCK);

        FDLog(LOG_DEBUG, "Calling connect()");
        int rc = connect(socketFd, (struct sockaddr *)&remote, len);
        if (rc == -1) {
            interrupted = (errno == EINTR);
            FDLog(LOG_DEBUG, "Connect failed: %s\n", strerror(errno));
            close(socketFd);
            if (!interrupted) {
                return -1;
            }
            FDLog(LOG_DEBUG, "Trying again because connect returned EINTR.");
        } else {
            // Make socket block again.
            interrupted = 0;
            FDLog(LOG_DEBUG, "Connected. Calling fcntl() 3");
            fcntl(socketFd, F_SETFL, flags & ~O_NONBLOCK);
        }
    } while (interrupted);

    return socketFd;
}

static int FileDescriptorClientConnectPid(pid_t pid) {
    char path[PATH_MAX + 1];
    iTermFileDescriptorSocketPath(path, sizeof(path), pid);

    FDLog(LOG_DEBUG, "Connect to path %s\n", path);
    return iTermFileDescriptorClientConnect(path);
}

iTermFileDescriptorServerConnection iTermFileDescriptorClientRun(pid_t pid) {
    int socketFd = FileDescriptorClientConnectPid(pid);
    if (socketFd < 0) {
        iTermFileDescriptorServerConnection result = { 0 };
        result.error = strerror(errno);
        return result;
    }

    iTermFileDescriptorServerConnection result = iTermFileDescriptorClientRead(socketFd, -1);
    result.serverPid = pid;
    FDLog(LOG_DEBUG, "Success: process id is %d, pty master fd is %d\n\n",
           (int)pid, result.ptyMasterFd);

    return result;
}

iTermFileDescriptorServerConnection iTermFileDescriptorClientRead(int socketFd, int deadMansPipeReadEnd) {
    iTermFileDescriptorServerConnection result = { 0 };
    int rc = ReceiveMessageAndFileDescriptor(socketFd,
                                             &result.childPid,
                                             sizeof(result.childPid),
                                             &result.ptyMasterFd,
                                             deadMansPipeReadEnd);
    if (rc == -1 || result.ptyMasterFd == -1) {
        result.error = "Failed to read message from server";
        close(socketFd);
        return result;
    }

    result.ok = 1;
    result.socketFd = socketFd;

    return result;
}

