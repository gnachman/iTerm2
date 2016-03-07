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

// Reads a message on the socket, and fills in receivedFileDescriptorPtr with a
// file descriptor if one was passed.
static ssize_t ReceiveMessageAndFileDescriptor(int fd,
                                               void *buffer,
                                               size_t bufferCapacity,
                                               int *receivedFileDescriptorPtr) {
    // Loop because sometimes the dynamic loader spews warnings (for example, when malloc logging
    // is enabled)
    while (1) {
        syslog(LOG_NOTICE, "ReceiveMessageAndFileDescriptor\n");
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
            syslog(LOG_NOTICE, "calling recvmsg...");
            n = recvmsg(fd, &message, 0);
            syslog(LOG_NOTICE, "recvmsg returned %zd, errno=%s\n", n, (n < 0 ? strerror(errno) : "n/a"));
        } while (n < 0 && errno == EINTR);

        if (n <= 0) {
            syslog(LOG_NOTICE, "error from recvmsg %s\n", strerror(errno));
            return n;
        }
        syslog(LOG_NOTICE, "recvmsg returned %d\n", (int)n);

        struct cmsghdr *messageHeader = CMSG_FIRSTHDR(&message);
        if (messageHeader != NULL && messageHeader->cmsg_len == CMSG_LEN(sizeof(int))) {
            if (messageHeader->cmsg_level != SOL_SOCKET) {
                syslog(LOG_NOTICE, "Wrong cmsg level\n");
                return -1;
            }
            if (messageHeader->cmsg_type != SCM_RIGHTS) {
                syslog(LOG_NOTICE, "Wrong cmsg type\n");
                return -1;
            }
            syslog(LOG_NOTICE, "Got a fd\n");
            *receivedFileDescriptorPtr = *((int *)CMSG_DATA(messageHeader));
            syslog(LOG_NOTICE, "Return %d\n", (int)n);
            return n;
        } else {
            syslog(LOG_NOTICE, "No descriptor passed\n");
            *receivedFileDescriptorPtr = -1;       // descriptor was not passed, try again.
            // This is the only case where the loop repeats.
        }
    }
}

int iTermFileDescriptorClientConnect(const char *path) {
    int interrupted = 0;
    int socketFd;
    int flags;

    do {
        socketFd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (socketFd == -1) {
            syslog(LOG_NOTICE, "Failed to create socket: %s\n", strerror(errno));
            return -1;
        }

        struct sockaddr_un remote;
        remote.sun_family = AF_UNIX;
        strcpy(remote.sun_path, path);
        int len = strlen(remote.sun_path) + sizeof(remote.sun_family) + 1;
        flags = fcntl(socketFd, F_GETFL, 0);

        // Put the socket in nonblocking mode so connect can fail fast if another iTerm2 is connected
        // to this server.
        fcntl(socketFd, F_SETFL, flags | O_NONBLOCK);

        int rc = connect(socketFd, (struct sockaddr *)&remote, len);
        if (rc == -1) {
            interrupted = (errno == EINTR);
            syslog(LOG_NOTICE, "Connect failed: %s\n", strerror(errno));
            close(socketFd);
            if (!interrupted) {
                return -1;
            }
            syslog(LOG_NOTICE, "Trying again because connect returned EINTR.");
        } else {
            // Make socket block again.
            interrupted = 0;
            fcntl(socketFd, F_SETFL, flags & ~O_NONBLOCK);
        }
    } while (interrupted);

    return socketFd;
}

static int FileDescriptorClientConnectPid(pid_t pid) {
    char path[PATH_MAX + 1];
    iTermFileDescriptorSocketPath(path, sizeof(path), pid);

    syslog(LOG_NOTICE, "Connect to path %s\n", path);
    return iTermFileDescriptorClientConnect(path);
}

iTermFileDescriptorServerConnection iTermFileDescriptorClientRun(pid_t pid) {
    int socketFd = FileDescriptorClientConnectPid(pid);
    if (socketFd < 0) {
        iTermFileDescriptorServerConnection result = { 0 };
        result.error = strerror(errno);
        return result;
    }

    iTermFileDescriptorServerConnection result = iTermFileDescriptorClientRead(socketFd);
    result.serverPid = pid;
    syslog(LOG_NOTICE, "Success: process id is %d, pty master fd is %d\n\n",
           (int)pid, result.ptyMasterFd);

    return result;
}

iTermFileDescriptorServerConnection iTermFileDescriptorClientRead(int socketFd) {
    iTermFileDescriptorServerConnection result = { 0 };
    int rc = ReceiveMessageAndFileDescriptor(socketFd,
                                             &result.childPid,
                                             sizeof(result.childPid),
                                             &result.ptyMasterFd);
    if (rc == -1 || result.ptyMasterFd == -1) {
        result.error = "Failed to read message from server";
        close(socketFd);
        return result;
    }

    result.ok = 1;
    result.socketFd = socketFd;

    return result;
}

