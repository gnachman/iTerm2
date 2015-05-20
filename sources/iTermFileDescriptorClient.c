#include "iTermFileDescriptorClient.h"
#include "iTermFileDescriptorServer.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

const char *kFileDescriptorClientErrorCouldNotConnect = "Couldn't connect";

static ssize_t ReadMessage(int fd, void *buffer, size_t bufferCapacity) {
    struct msghdr message = { 0 };
    struct iovec ioVector[1];

    message.msg_name = NULL;
    message.msg_namelen = 0;

    ioVector[0].iov_base = buffer;
    ioVector[0].iov_len = bufferCapacity;
    message.msg_iov = ioVector;
    message.msg_iovlen = 1;

    return recvmsg(fd, &message, 0);
}

// Reads a message on the socket, and fills in receivedFileDescriptorPtr with a
// file descriptor if one was passed.
static ssize_t ReceiveMessageAndFileDescriptor(int fd,
                                               void *buffer,
                                               size_t bufferCapacity,
                                               int *receivedFileDescriptorPtr) {
    printf("ReceiveMessageAndFileDescriptor\n");
    struct msghdr message;
    struct iovec ioVector[1];
    FileDescriptorControlMessage controlMessage;

    message.msg_control = controlMessage.control;
    message.msg_controllen = sizeof(controlMessage.control);

    message.msg_name = NULL;
    message.msg_namelen = 0;

    ioVector[0].iov_base = buffer;
    ioVector[0].iov_len = bufferCapacity;
    message.msg_iov = ioVector;
    message.msg_iovlen = 1;

    ssize_t n = recvmsg(fd, &message, 0);
    if (n <= 0) {
        printf("error from recvmsg %s\n", strerror(errno));
        return n;
    }
    printf("recvmsg returned %d\n", (int)n);

    struct cmsghdr *messageHeader = CMSG_FIRSTHDR(&message);
    if (messageHeader != NULL && messageHeader->cmsg_len == CMSG_LEN(sizeof(int))) {
        if (messageHeader->cmsg_level != SOL_SOCKET) {
            printf("Wrong cmsg level\n");
            return -1;
        }
        if (messageHeader->cmsg_type != SCM_RIGHTS) {
            printf("Wrong cmsg type\n");
            return -1;
        }
        printf("Got a fd\n");
        *receivedFileDescriptorPtr = *((int *)CMSG_DATA(messageHeader));
    } else {
        printf("No descriptor passed\n");
        *receivedFileDescriptorPtr = -1;       // descriptor was not passed
    }

    printf("Return %d\n", (int)n);
    return n;
}

// Reads a file descriptor from a socket. Returns 0 on success, -1 on failure.
static int ReadOneFileDescriptor(int socketFd, int *fileDescriptor) {
    printf("Read one file descriptor\n");
    char buf[1] = { 0 };
    int fd;
    int n = ReceiveMessageAndFileDescriptor(socketFd, buf, sizeof(buf), &fd);
    if (n != 1) {
        return -1;
    }
    if (fd == -1) {
        return -1;
    }

    printf("buf=%.*s, fd=%d\n", n, buf, fd);
    *fileDescriptor = fd;
    return 0;
}

static int FileDescriptorClientConnect(char *path) {
    int socketFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (socketFd == -1) {
        return -1;
    }

    struct sockaddr_un remote;
    remote.sun_family = AF_UNIX;
    strcpy(remote.sun_path, path);
    int len = strlen(remote.sun_path) + sizeof(remote.sun_family) + 1;
    if (connect(socketFd, (struct sockaddr *)&remote, len) == -1) {
        return -1;
    }

    return socketFd;
}

FileDescriptorClientResult FileDescriptorClientRun(char *path) {
    FileDescriptorClientResult result = { 0 };

    int socketFd = FileDescriptorClientConnect(path);
    if (socketFd < 0) {
        result.error = kFileDescriptorClientErrorCouldNotConnect;
        return result;
    }

    if (ReadOneFileDescriptor(socketFd, &result.ptyMasterFd)) {
        result.error = "Failed to read file descriptor";
        close(socketFd);
        return result;
    }
    if (ReadMessage(socketFd, &result.childPid, sizeof(int)) < sizeof(int)) {
        result.error = "Failed to read PID";
        return result;
    }

    close(socketFd);
    result.ok = 1;
    return result;
}

