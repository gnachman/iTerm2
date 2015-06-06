#include "iTermFileDescriptorServer.h"
#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/un.h>
#include <syslog.h>
#include <unistd.h>

static const int kMaxConnections = 1;

// This is global so that signal handlers can use it.
static pid_t gChildPid;

static char gPath[1024];
static int gConnectionFd;
static int gPipe[2];

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
    while (rc == -1 && errno == EINTR) {
        rc = sendmsg(connectionFd, &message, 0);
    }
    return rc;
}

static pid_t Wait() {
    pid_t pid;
    do {
        int status;
        pid = waitpid(gChildPid, &status, 0);
    } while (pid == -1 && errno == EINTR);
    return pid;
}

static void SigChildHandler(int arg) {
    if (Wait() == gChildPid) {
        // Wake up the select loop and exit.
        write(gPipe[1], "", 1);
    } else {
        // Something weird happened.
        unlink(gPath);
        exit(1);
    }
}

static void SigUsr1Handler(int arg) {
    unlink(gPath);
    exit(1);
}


static int Select(int *fds, int count, int *results) {
    int result;
    int theError;
    fd_set readset;
    do {
        FD_ZERO(&readset);
        int max = 0;
        for (int i = 0; i < count; i++) {
            if (fds[i] > max) {
                max = fds[i];
            }
            FD_SET(fds[i], &readset);
        }
        syslog(LOG_NOTICE, "Calling select...");
        result = select(max + 1, &readset, NULL, NULL, NULL);
        theError = errno;
        syslog(LOG_NOTICE, "select returned %d, error = %s", result, strerror(theError));
    } while (result == -1 && theError == EINTR);

    int n = 0;
    for (int i = 0; i < count; i++) {
        results[i] = FD_ISSET(fds[i], &readset);
        if (results[i]) {
            n++;
        }
    }
    return n;
}

static int PerformAcceptActivity(int socketFd) {
    // incoming unix domain socket connection to get FDs
    struct sockaddr_un remote;
    socklen_t sizeOfRemote = sizeof(remote);
    do {
        gConnectionFd = accept(socketFd, (struct sockaddr *)&remote, &sizeOfRemote);
    } while (gConnectionFd == -1 && errno == EINTR);
    if (gConnectionFd == -1) {
        syslog(LOG_NOTICE, "accept failed %s", strerror(errno));
        return 0;
    }
    close(socketFd);

    syslog(LOG_NOTICE, "send master");
    int rc = SendMessageAndFileDescriptor(gConnectionFd, "m", 0);
    if (rc <= 0) {
        syslog(LOG_NOTICE, "send failed %s", strerror(errno));
        close(gConnectionFd);
        return 0;
    }

    syslog(LOG_NOTICE, "send pid");
    rc = SendMessage(gConnectionFd, &gChildPid, sizeof(gChildPid));
    if (rc <= 0) {
        syslog(LOG_NOTICE, "send failed %s", strerror(errno));
        close(gConnectionFd);
        return 0;
    }

    syslog(LOG_NOTICE, "All done. Waiting for client to disconnect or child to die.");
    int fds[2] = { gPipe[0], gConnectionFd };
    int results[2];
    Select(fds, sizeof(fds) / sizeof(*fds), results);
    syslog(LOG_NOTICE, "select returned. child dead=%d, connection closed=%d", results[0], results[1]);
    close(gConnectionFd);

    syslog(LOG_NOTICE, "Connection closed.");
    // If the pipe has been written to then results[0] will be nonzero. That
    // means the child process has died and we can terminate. The server's
    // termination signals the client that the child is dead.
    return (results[0]);
}

static int SocketBindListen(char *path) {
    int socketFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (socketFd == -1) {
        syslog(LOG_NOTICE, "socket() failed: %s", strerror(errno));
        return -1;
    }

    struct sockaddr_un local;
    local.sun_family = AF_UNIX;
    strcpy(local.sun_path, path);
    unlink(local.sun_path);
    int len = strlen(local.sun_path) + sizeof(local.sun_family) + 1;
    if (bind(socketFd, (struct sockaddr *)&local, len) == -1) {
        syslog(LOG_NOTICE, "bind() failed: %s", strerror(errno));
        return -1;
    }

    if (listen(socketFd, kMaxConnections) == -1) {
        syslog(LOG_NOTICE, "listen() failed: %s", strerror(errno));
        return -1;
    }
    return socketFd;
}

static int Initialize(char *path, pid_t childPid) {
    openlog("iTerm2-Server", LOG_PID | LOG_NDELAY, LOG_USER);
    setlogmask(LOG_UPTO(LOG_DEBUG));
    snprintf(gPath, sizeof(gPath), "%s", path);
    // We get this when iTerm2 crashes. Ignore it.
    syslog(LOG_NOTICE, "Installing SIGHUP handler.");
    signal(SIGHUP, SIG_IGN);

    pipe(gPipe);

    syslog(LOG_NOTICE, "Installing SIGCHLD handler.");
    gChildPid = childPid;
    signal(SIGCHLD, SigChildHandler);
    signal(SIGUSR1, SigUsr1Handler);

    return 0;
}

static void MainLoop(char *path) {
    // Listen on a Unix Domain Socket.
    syslog(LOG_NOTICE, "Entering main loop.");
    int socketFd;
    do {
        syslog(LOG_NOTICE, "Calling SocketBindListen.");
        socketFd = SocketBindListen(path);
        if (socketFd < 0) {
            syslog(LOG_NOTICE, "SocketBindListen failed");
            return;
        }
        syslog(LOG_NOTICE, "Calling PerformAcceptActivity");
    } while (!PerformAcceptActivity(socketFd));
}

int FileDescriptorServerRun(char *path, pid_t childPid) {
    int rc = Initialize(path, childPid);
    if (rc) {
        syslog(LOG_NOTICE, "Initialize failed with code %d", rc);
    } else {
        MainLoop(path);
        // MainLoop never returns, except by dying on a signal.
    }
    syslog(LOG_NOTICE, "Unlink %s", path);
    unlink(path);
    return 1;
}

