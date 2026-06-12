//
//  iTermFileDescriptorServerShared.c
//  iTerm2
//
//  Created by George Nachman on 11/26/19.
//

#include "iTermFileDescriptorServerShared.h"

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
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

static ssize_t iTermFileDescriptorWriteImpl(int fd,
                                            void *buffer,
                                            size_t bufferSize,
                                            int *errorOut) {
    const ssize_t rc = iTermFileDescriptorServerWrite(fd, buffer, bufferSize);
    if (rc == -1) {
        if (*errorOut) {
            *errorOut = errno;
        }
        FDLog(LOG_DEBUG, "iTermFileDescriptorServerWrite failed with %s", strerror(errno));
    } else {
        if (errorOut) {
            *errorOut = 0;
        }
        FDLog(LOG_DEBUG, "send %d bytes to client", (int)rc);
    }
    return rc;
}

// Returns number of bytes sent, or -1 for error.
ssize_t iTermFileDescriptorServerWriteLengthAndBuffer(int fd,
                                                      void *buffer,
                                                      size_t bufferSize,
                                                      int *errorOut) {
    unsigned char temp[sizeof(bufferSize)];
    memmove(temp, &bufferSize, sizeof(bufferSize));
    const ssize_t rc = iTermFileDescriptorWriteImpl(fd, temp, sizeof(temp), errorOut);
    if (rc != sizeof(temp)) {
        return rc;
    }

    return iTermFileDescriptorWriteImpl(fd, buffer, bufferSize, errorOut);
}

// Returns -1 on error
ssize_t iTermFileDescriptorServerWriteLengthAndBufferAndFileDescriptor(int connectionFd,
                                                                       void *buffer,
                                                                       size_t bufferSize,
                                                                       int fdToSend,
                                                                       int *errorOut) {
    // Write length
    unsigned char temp[sizeof(bufferSize)];
    memmove(temp, &bufferSize, sizeof(bufferSize));
    ssize_t rc = iTermFileDescriptorWriteImpl(connectionFd, temp, sizeof(temp), errorOut);
    if (rc != sizeof(temp)) {
        return rc;
    }

    // Write message with file descriptor
    rc = iTermFileDescriptorServerSendMessageAndFileDescriptor(connectionFd,
                                                               buffer,
                                                               bufferSize,
                                                               fdToSend);
    if (rc == -1) {
        if (errorOut) {
            *errorOut = errno;
        }
    } else {
        if (errorOut) {
            *errorOut = 0;
        }
    }
    return rc;
}

ssize_t iTermFileDescriptorServerWrite(int fd, void *buffer, size_t bufferSize) {
    assert(bufferSize > 0);
    FDLog(LOG_DEBUG, "Write message of length %d", (int)bufferSize);

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
    return rc <= 0 ? rc : offset;
}

ssize_t iTermFileDescriptorClientWrite(int fd, const void *buffer, size_t bufferSize) {
    ssize_t rc = -1;
    size_t totalWritten = 0;
    while (totalWritten < bufferSize) {
        int savedErrno = 0;
        do {
            errno = 0;
            const size_t bytesToWrite = bufferSize - totalWritten;
            rc = write(fd, (unsigned char *)buffer + totalWritten, bytesToWrite);
            savedErrno = errno;
            FDLog(LOG_DEBUG, "write of %d bytes returned %d, errno=%d", (int)bufferSize, (int)rc, (int)savedErrno);
        } while (rc == -1 && savedErrno == EINTR);
        if (rc <= 0) {
            if (savedErrno == EAGAIN && totalWritten > 0) {
                FDLog(LOG_DEBUG, "write: EAGAIN with totalWritten=%d", (int)totalWritten);
                return totalWritten;
            }
            errno = savedErrno;
            return rc;
        }
        totalWritten += rc;
    }
    return totalWritten;
}

ssize_t iTermFileDescriptorServerSendMessageAndFileDescriptor(int connectionFd,
                                                              void *buffer,
                                                              size_t bufferSize,
                                                              int fdToSend) {
    // sendmsg wants to send the whole buffer atomically so it has a small upper bound on message
    // size. The client-server protocol allows a message to be fragmented as long as the first
    // one has the file descriptor.
    //
    // Despite what the man page says, I have seen sendmsg fail with EMSGSIZE with a buffer
    // size of IOV_MAX. My theory is that the control block can count against that limit in
    // some circumstances.
    //
    // Furthermore, if you try to send an empty message, that will also fail with EMSGSIZE.
    // So we set the limit to one byte.
    const int maxBufferSize = 1;

    if (bufferSize > maxBufferSize) {
        const ssize_t firstResult = iTermFileDescriptorServerSendMessageAndFileDescriptor(connectionFd,
                                                                                          buffer,
                                                                                          maxBufferSize,
                                                                                          fdToSend);
        if (firstResult <= 0) {
            return firstResult;
        }
        ssize_t remainingSize = bufferSize;
        remainingSize -= firstResult;
        assert(remainingSize > 0);

        // Now write the remainder. Because this doesn't use sendmsg there's no size limit problem.
        int error = 0;
        const ssize_t secondResult = iTermFileDescriptorWriteImpl(connectionFd,
                                                                  buffer + maxBufferSize,
                                                                  remainingSize,
                                                                  &error);
        if (secondResult <= 0) {
            return secondResult;
        }
        return bufferSize;
    }

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
    if (bufferSize > 0) {
        message.msg_iov = iov;
        message.msg_iovlen = 1;
    } else {
        message.msg_iov = NULL;
        message.msg_iovlen = 0;
    }

    FDLog(LOG_DEBUG, "Send message of length %d, iovlen=%d along with file descriptor %d",
          (int)bufferSize, (int)message.msg_iovlen, fdToSend);

    ssize_t rc = sendmsg(connectionFd, &message, 0);
    while (rc == -1 && errno == EINTR) {
        rc = sendmsg(connectionFd, &message, 0);
    }
    if (rc >= 0 && rc < bufferSize) {
        // I don't know if this is possible, but you don't want to send the file descriptor
        // more than once or it will create multiple file descriptors in the recipient.
        char *temp = buffer;
        return iTermFileDescriptorServerWrite(connectionFd, temp + rc, bufferSize - rc);
    }
    return rc;
}

/* Selects for reading */
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

/* Selects for writing */
int iTermSelectForWriting(int *fds, int count, int *results, int wantErrors) {
    int result;
    int theError;
    fd_set writeset;
    fd_set errorset;
    do {
        FD_ZERO(&writeset);
        FD_ZERO(&errorset);
        int max = 0;
        for (int i = 0; i < count; i++) {
            if (fds[i] > max) {
                max = fds[i];
            }
            FD_SET(fds[i], &writeset);
            if (wantErrors) {
                FD_SET(fds[i], &errorset);
            }
        }
        FDLog(LOG_DEBUG, "Calling select...");
        result = select(max + 1, NULL, &writeset, wantErrors ? &errorset : NULL, NULL);
        theError = errno;
        FDLog(LOG_DEBUG, "select returned %d, error = %s", result, strerror(theError));
    } while (result == -1 && theError == EINTR);

    int n = 0;
    for (int i = 0; i < count; i++) {
        results[i] = FD_ISSET(fds[i], &writeset) || (wantErrors && FD_ISSET(fds[i], &errorset));
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

int iTermAcquireAdvisoryLock(const char *path) {
    int fd;
    do {
        FDLog(LOG_DEBUG, "Attempting to lock %s", path);
        fd = open(path, O_CREAT | O_TRUNC | O_EXLOCK | O_NONBLOCK, 0600);
    } while (fd < 0 && errno == EINTR);
    if (fd < 0) {
        FDLog(LOG_DEBUG, "Failed: %s", strerror(errno));
        return -1;
    }
    FDLog(LOG_DEBUG, "Lock acquired");
    return fd;
}

