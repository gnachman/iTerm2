#include "iTermFileDescriptorServer.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

static const int kMaxConnections = 1;
static int gSocketFd;
static int gReturnCode;
static pid_t gChildPid;
static FILE *f;

static ssize_t SendMessage(int connectionFd, void *buffer, int length) {
    struct msghdr message = { 0 };

    message.msg_name = NULL;
    message.msg_namelen = 0;

    struct iovec iov[1];
    iov[0].iov_base = buffer;
    iov[0].iov_len = length;
    message.msg_iov = iov;
    message.msg_iovlen = 1;

    return sendmsg(connectionFd, &message, 0);
}

static ssize_t SendMessageAndFileDescriptor(int connectionFd,
                                            char *stringToSend,
                                            int fdToSend) {
    FileDescriptorControlMessage controlMessage;
    struct msghdr message;
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
    iov[0].iov_base = stringToSend;
    iov[0].iov_len = strlen(stringToSend);
    message.msg_iov = iov;
    message.msg_iovlen = 1;

    return sendmsg(connectionFd, &message, 0);
}

static pid_t Wait() {
    pid_t pid;
    do {
        pid = waitpid(gChildPid, &gReturnCode, 0);
    } while (pid == -1 && errno == EINTR);
    return pid;
}

static void SigChildHandler(int arg) {
    if (Wait() == gChildPid) {
        // This will wake up PerformAcceptActivity and make the server exit.
        close(gSocketFd);
    } else {
        // Something weird happened.
        exit(1);
    }
}

static int PerformAcceptActivity() {
    // incoming unix domain socket connection to get FDs
    struct sockaddr_un remote;
    socklen_t sizeOfRemote = sizeof(remote);
    int connectionFd = accept(gSocketFd, (struct sockaddr *)&remote, &sizeOfRemote);
    if (connectionFd == -1) {
        fprintf(f, "accept failed %s\n", strerror(errno)); fflush(f);
        return 1;
    }

    fprintf(f, "send master\n"); fflush(f);
    int rc = SendMessageAndFileDescriptor(connectionFd, "m", 0);
    if (rc <= 0) {
        fprintf(f, "send failed %s\n", strerror(errno)); fflush(f);
        close(connectionFd);
        return 0;
    }

    fprintf(f, "send pid\n"); fflush(f);
    rc = SendMessage(connectionFd, &gChildPid, sizeof(gChildPid));
    if (rc <= 0) {
        fprintf(f, "send failed %s\n", strerror(errno)); fflush(f);
        close(connectionFd);
        return 0;
    }

    fprintf(f, "All done!"); fflush(f);
    close(connectionFd);

    return 0;
}

static int SocketBindListen(char *path) {
    gSocketFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (gSocketFd == -1) {
        fprintf(f, "socket() failed: %s", strerror(errno)); fflush(f);
        return 1;
    }

    struct sockaddr_un local;
    local.sun_family = AF_UNIX;
    strcpy(local.sun_path, path);
    unlink(local.sun_path);
    int len = strlen(local.sun_path) + sizeof(local.sun_family) + 1;
    if (bind(gSocketFd, (struct sockaddr *)&local, len) == -1) {
        fprintf(f, "bind() failed: %s", strerror(errno)); fflush(f);
        return 1;
    }

    if (listen(gSocketFd, kMaxConnections) == -1) {
        fprintf(f, "listen() failed: %s", strerror(errno)); fflush(f);
        return 1;
    }
    return 0;
}

int FileDescriptorServerRun(char *path, pid_t childPid) {
    f = fopen("/tmp/log.txt", "w");

    // We get this when iTerm2 crashes. Ignore it.
    fprintf(f, "Installing SIGHUP handler.\n"); fflush(f);
    signal(SIGHUP, SIG_IGN);

    // Listen on a Unix Domain Socket.
    fprintf(f, "Calling SocketBindListen.\n"); fflush(f);
    if (SocketBindListen(path)) {
        fprintf(f, "SocketBindListen failed\n"); fflush(f);
        return 1;
    }

    // Handle CHLD signal when child dies so we can wake up select and terminate the server.
    // This must be done after SocketBindListen succeeds. There should have been a preexisting
    // handler to kill us if the child dies before this point.
    fprintf(f, "Installing SIGCHLD handler.\n"); fflush(f);
    gChildPid = childPid;
    signal(SIGCHLD, SigChildHandler);

    // PerformAcceptActivity will return an error only if the child dies.
    fprintf(f, "Entering main loop.\n"); fflush(f);
    while (!PerformAcceptActivity()) {
        fprintf(f, "Accept activity finished.\n"); fflush(f);
    }

    fprintf(f, "Child is presumed dead with return code %d\n", gReturnCode); fflush(f);
    return gReturnCode;
}
