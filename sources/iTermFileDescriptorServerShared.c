//
//  iTermFileDescriptorServerShared.c
//  iTerm2
//
//  Created by George Nachman on 11/26/19.
//

#include "iTermFileDescriptorServerShared.h"

#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/un.h>
#include <syslog.h>
#include <unistd.h>

static int gRunningServer;

// Listen queue limit
static const int kMaxConnections = 1;

void SetRunningServer(void) {
    gRunningServer = 1;
}

void iTermFileDescriptorServerLog(char *format, ...) {
    va_list args;
    va_start(args, format);
    char temp[1000];
    snprintf(temp, sizeof(temp) - 1, "%s(%d) %s", gRunningServer ? "Server" : "ParentServer", getpid(), format);
    vsyslog(LOG_DEBUG, temp, args);
    va_end(args);
}

int iTermFileDescriptorServerAcceptAndClose(int socketFd) {
    int fd = iTermFileDescriptorServerAccept(socketFd);
    if (fd != -1) {
        close(socketFd);
    }
    return fd;
}

int iTermFileDescriptorServerAccept(int socketFd) {
    // incoming unix domain socket connection to get FDs
    struct sockaddr_un remote;
    socklen_t sizeOfRemote = sizeof(remote);
    int connectionFd = -1;
    do {
        FDLog(LOG_DEBUG, "Calling accept()...");
        connectionFd = accept(socketFd, (struct sockaddr *)&remote, &sizeOfRemote);
        FDLog(LOG_DEBUG, "accept() returned %d error=%s", connectionFd, strerror(errno));
    } while (connectionFd == -1 && errno == EINTR);
    return connectionFd;
}

// Returns number of bytes sent, or -1 for error.
ssize_t iTermFileDescriptorServerSendMessage(int fd,
                                             void *buffer,
                                             size_t bufferSize,
                                             int *errorOut) {
    struct msghdr message;
    memset(&message, 0, sizeof(message));

    struct iovec iov[1];
    iov[0].iov_base = buffer;
    iov[0].iov_len = bufferSize;
    message.msg_iov = iov;
    message.msg_iovlen = 1;

    errno = 0;
    ssize_t rc = sendmsg(fd, &message, 0);
    while (rc == -1 && errno == EINTR) {
        rc = sendmsg(fd, &message, 0);
    }
    if (rc == -1) {
        if (errorOut) {
            *errorOut = errno;
        }
        FDLog(LOG_DEBUG, "sendmsg failed with %s", strerror(errno));
    } else {
        if (errorOut) {
            *errorOut = 0;
        }
        FDLog(LOG_DEBUG, "send %d bytes to client", (int)rc);
    }
    return rc;
}

static ssize_t Write(int fd, void *buffer, size_t bufferSize) {
    ssize_t rc = -1;
    size_t offset = 0;
    while (offset < bufferSize) {
        do {
            errno = 0;
            rc = write(fd, buffer + offset, bufferSize - offset);
        } while (rc == -1 && errno == EINTR);
        if (rc <= 0) {
            break;
        }
        offset += rc;
    }
    if (rc == -1) {
        FDLog(LOG_DEBUG, "write failed with %s", strerror(errno));
    } else {
        FDLog(LOG_DEBUG, "write %d bytes to server", (int)rc);
    }
    return rc;
}

ssize_t iTermFileDescriptorClientWrite(int fd, void *buffer, size_t bufferSize) {
    size_t length = bufferSize;
    ssize_t n = Write(fd, (void *)&length, sizeof(length));
    if (n != sizeof(length)) {
        return n;
    }

    return Write(fd, buffer, bufferSize);
}

ssize_t iTermFileDescriptorServerSendMessageAndFileDescriptor(int connectionFd,
                                                              void *buffer,
                                                              size_t bufferSize,
                                                              int fdToSend) {
    FDLog(LOG_DEBUG, "Send file descriptor %d", fdToSend);
    struct msghdr message;
    memset(&message, 0, sizeof(message));

    iTermFileDescriptorControlMessage controlMessage;
    memset(&controlMessage, 0, sizeof(controlMessage));

    message.msg_control = controlMessage.control;
    message.msg_controllen = sizeof(controlMessage.control);

    struct cmsghdr *messageHeader = CMSG_FIRSTHDR(&message);
    messageHeader->cmsg_len = CMSG_LEN(sizeof(int));
    messageHeader->cmsg_level = SOL_SOCKET;
    messageHeader->cmsg_type = SCM_RIGHTS;
    *((int *) CMSG_DATA(messageHeader)) = fdToSend;

    message.msg_name = NULL;
    message.msg_namelen = 0;

    struct iovec iov[1];
    iov[0].iov_base = buffer;
    iov[0].iov_len = bufferSize;
    message.msg_iov = iov;
    message.msg_iovlen = 1;

    ssize_t rc = sendmsg(connectionFd, &message, 0);
    while (rc == -1 && errno == EINTR) {
        rc = sendmsg(connectionFd, &message, 0);
    }
    return rc;
}

int iTermSelect(int *fds, int count, int *results, int wantErrors) {
    int result;
    int theError;
    fd_set readset;
    fd_set errorset;
    do {
        FD_ZERO(&readset);
        FD_ZERO(&errorset);
        int max = 0;
        for (int i = 0; i < count; i++) {
            if (fds[i] > max) {
                max = fds[i];
            }
            FD_SET(fds[i], &readset);
            if (wantErrors) {
                FD_SET(fds[i], &errorset);
            }
        }
        FDLog(LOG_DEBUG, "Calling select...");
        result = select(max + 1, &readset, NULL, wantErrors ? &errorset : NULL, NULL);
        theError = errno;
        FDLog(LOG_DEBUG, "select returned %d, error = %s", result, strerror(theError));
    } while (result == -1 && theError == EINTR);

    int n = 0;
    for (int i = 0; i < count; i++) {
        results[i] = FD_ISSET(fds[i], &readset) || (wantErrors && FD_ISSET(fds[i], &errorset));
        if (results[i]) {
            n++;
        }
    }
    return n;
}

static socklen_t SizeTToSockLenT(size_t size) {
    assert(size <= INT32_MAX);
    return (socklen_t)size;
}

int iTermFileDescriptorServerSocketBindListen(const char *path) {
    int socketFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (socketFd == -1) {
        FDLog(LOG_NOTICE, "socket() failed: %s", strerror(errno));
        return -1;
    }
    // Mask off all permissions for group and other. Only user can use this socket.
    mode_t oldMask = umask(S_IRWXG | S_IRWXO);

    struct sockaddr_un local;
    local.sun_family = AF_UNIX;
    assert((uint64_t)strlen(path) + 1 < (uint64_t)sizeof(local.sun_path));
    strcpy(local.sun_path, path);
    unlink(local.sun_path);
    socklen_t len = SizeTToSockLenT(strlen(local.sun_path)) + SizeTToSockLenT(sizeof(local.sun_family)) + 1;
    if (bind(socketFd, (struct sockaddr *)&local, len) == -1) {
        FDLog(LOG_NOTICE, "bind() failed: %s", strerror(errno));
        umask(oldMask);
        return -1;
    }
    FDLog(LOG_DEBUG, "bind() created %s", local.sun_path);

    if (listen(socketFd, kMaxConnections) == -1) {
        FDLog(LOG_DEBUG, "listen() failed: %s", strerror(errno));
        umask(oldMask);
        return -1;
    }
    umask(oldMask);
    return socketFd;
}

