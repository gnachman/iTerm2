#include "iTermFileDescriptorServer.h"
#include <errno.h>
#include <signal.h>
#include <stdarg.h>
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
static int gChildDied;
static char gPath[1024];
static int gConnectionFd;

static void LOG(char *format, ...) {
    va_list varArgsList;
    va_start(varArgsList, format);
    char temp[1024];
    vsnprintf(temp, sizeof(temp), format, varArgsList);
    va_end(varArgsList);

    fprintf(f, "%d: %s\n", (int)getpid(), temp);
    fflush(f);
}

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

    int rc = sendmsg(connectionFd, &message, 0);
    while (rc == -1 && errno == EINTR && !gChildDied) {
        rc = sendmsg(connectionFd, &message, 0);
    }
    return rc;
}

static ssize_t ReadMessage(int fd, void *buffer, size_t bufferCapacity) {
    struct msghdr message = { 0 };
    struct iovec ioVector[1];

    message.msg_name = NULL;
    message.msg_namelen = 0;

    ioVector[0].iov_base = buffer;
    ioVector[0].iov_len = bufferCapacity;
    message.msg_iov = ioVector;
    message.msg_iovlen = 1;

    LOG("Call recvmsg");
    int rc = recvmsg(fd, &message, 0);
    while (rc == -1 && errno == EINTR && !gChildDied) {
        LOG("recvmsg got interrupted but the child is still alive");
        rc = recvmsg(fd, &message, 0);
    }
    LOG("recvmsg returned %d %s", rc, strerror(errno));
    return rc;
}

static pid_t Wait() {
    LOG("Waiting...");
    pid_t pid;
    do {
        pid = waitpid(gChildPid, &gReturnCode, 0);
    } while (pid == -1 && errno == EINTR);
    LOG("Wait returned %d %s", (int)pid, strerror(errno));
    return pid;
}

static void SigChildHandler(int arg) {
    if (Wait() == gChildPid) {
        gChildDied = 1;  // In case the server is currently connected, prevent SocketBindListen from running.
        // This will wake up PerformAcceptActivity and make the server exit.
        close(gSocketFd);
        close(gConnectionFd);
    } else {
        // Something weird happened.
        unlink(gPath);
        exit(1);
    }
}

static int PerformAcceptActivity() {
    // incoming unix domain socket connection to get FDs
    struct sockaddr_un remote;
    socklen_t sizeOfRemote = sizeof(remote);
    gConnectionFd = accept(gSocketFd, (struct sockaddr *)&remote, &sizeOfRemote);
    if (gConnectionFd == -1) {
        LOG("accept failed %s", strerror(errno));
        return 1;
    }
    close(gSocketFd);

    LOG("send master");
    int rc = SendMessageAndFileDescriptor(gConnectionFd, "m", 0);
    if (rc <= 0) {
        LOG("send failed %s", strerror(errno));
        close(gConnectionFd);
        return 0;
    }

    LOG("send pid");
    rc = SendMessage(gConnectionFd, &gChildPid, sizeof(gChildPid));
    if (rc <= 0) {
        LOG("send failed %s", strerror(errno));
        close(gConnectionFd);
        return 0;
    }

    LOG("All done. Waiting for client to disconnect.");
    char buffer[1];
    ssize_t n = ReadMessage(gConnectionFd, buffer, sizeof(buffer));

    LOG("Read returned %d (error: %s)", (int)n, strerror(errno));
    close(gConnectionFd);

    LOG("Connection closed.");

    return 0;
}

static int SocketBindListen(char *path) {
    if (gChildDied) {
        LOG("SocketBindListen failing immediately because the child has died");
        return -1;
    }

    gSocketFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (gSocketFd == -1) {
        LOG("socket() failed: %s", strerror(errno));
        return 1;
    }

    struct sockaddr_un local;
    local.sun_family = AF_UNIX;
    strcpy(local.sun_path, path);
    unlink(local.sun_path);
    int len = strlen(local.sun_path) + sizeof(local.sun_family) + 1;
    if (bind(gSocketFd, (struct sockaddr *)&local, len) == -1) {
        LOG("bind() failed: %s", strerror(errno));
        return 1;
    }

    if (listen(gSocketFd, kMaxConnections) == -1) {
        LOG("listen() failed: %s", strerror(errno));
        return 1;
    }
    return 0;
}

static int Initialize(char *path, pid_t childPid) {
    f = fopen("/tmp/log.txt", "a");
    snprintf(gPath, sizeof(gPath), "%s", path);
    // We get this when iTerm2 crashes. Ignore it.
    LOG("Installing SIGHUP handler.");
    signal(SIGHUP, SIG_IGN);

    // Listen on a Unix Domain Socket.
    LOG("Calling SocketBindListen.");
    if (SocketBindListen(path)) {
        LOG("SocketBindListen failed");
        return 1;
    }

    // Handle CHLD signal when child dies so we can wake up select and terminate the server.
    // This must be done after SocketBindListen succeeds. There should have been a preexisting
    // handler to kill us if the child dies before this point.
    LOG("Installing SIGCHLD handler.");
    gChildPid = childPid;
    signal(SIGCHLD, SigChildHandler);

    return 0;
}

static int MainLoop(char *path) {
    // PerformAcceptActivity will return an error only if the child dies.
    LOG("Entering main loop.");
    while (!PerformAcceptActivity()) {
        LOG("Accept activity finished.");

        if (SocketBindListen(path)) {
            LOG("SocketBindListen failed");
            return 1;
        }
    }

    LOG("Child is presumed dead with return code %d", gReturnCode);
    return gReturnCode;
}

int FileDescriptorServerRun(char *path, pid_t childPid) {
    int rc = Initialize(path, childPid);
    if (rc) {
        LOG("Initialize failed with code %d", rc);
    } else {
        rc = MainLoop(path);
        LOG("Server exited with code %d", rc);
    }
    LOG("Unlink %s", path);
    unlink(path);
    return rc;
}

