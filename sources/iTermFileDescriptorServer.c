#include "iTermFileDescriptorServer.h"
#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <syslog.h>
#include <unistd.h>

static const int kMaxConnections = 1;
static int gRunningServer;

// These variables are global because signal handlers use them.
static pid_t gChildPid;
static char *gPath;
static int gPipe[2];

void iTermFileDescriptorServerLog(char *format, ...) {
    va_list args;
    va_start(args, format);
    char temp[1000];
    snprintf(temp, sizeof(temp) - 1, "%s(%d) %s", gRunningServer ? "Server" : "ParentServer", getpid(), format);
    vsyslog(LOG_DEBUG, temp, args);
    va_end(args);
}

static ssize_t SendMessageAndFileDescriptor(int connectionFd,
                                            void *buffer,
                                            size_t bufferSize,
                                            int fdToSend) {
    iTermFileDescriptorControlMessage controlMessage;
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
    iov[0].iov_base = buffer;
    iov[0].iov_len = bufferSize;
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


int iTermSelect(int *fds, int count, int *results) {
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
        FDLog(LOG_DEBUG, "Calling select...");
        result = select(max + 1, &readset, NULL, NULL, NULL);
        theError = errno;
        FDLog(LOG_DEBUG, "select returned %d, error = %s", result, strerror(theError));
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

int iTermFileDescriptorServerAccept(int socketFd) {
    // incoming unix domain socket connection to get FDs
    struct sockaddr_un remote;
    socklen_t sizeOfRemote = sizeof(remote);
    int connectionFd = -1;
    do {
        FDLog(LOG_DEBUG, "accept()");
        connectionFd = accept(socketFd, (struct sockaddr *)&remote, &sizeOfRemote);
        FDLog(LOG_DEBUG, "accept() returned %d error=%s", connectionFd, strerror(errno));
    } while (connectionFd == -1 && errno == EINTR);
    if (connectionFd != -1) {
        close(socketFd);
    }
    return connectionFd;
}

static int SendFileDescriptorAndWait(int connectionFd) {
    FDLog(LOG_DEBUG, "send master fd and child pid %d", (int)gChildPid);
    int rc = SendMessageAndFileDescriptor(connectionFd, &gChildPid, sizeof(gChildPid), 0);
    if (rc <= 0) {
        FDLog(LOG_NOTICE, "send failed %s", strerror(errno));
        close(connectionFd);
        return 0;
    }

    FDLog(LOG_DEBUG, "All done. Waiting for client to disconnect or child to die.");
    int fds[2] = { gPipe[0], connectionFd };
    int results[2];
    iTermSelect(fds, sizeof(fds) / sizeof(*fds), results);
    FDLog(LOG_DEBUG, "select returned. child dead=%d, connection closed=%d", results[0], results[1]);
    close(connectionFd);

    FDLog(LOG_DEBUG, "Connection closed.");
    // If the pipe has been written to then results[0] will be nonzero. That
    // means the child process has died and we can terminate. The server's
    // termination signals the client that the child is dead.
    return (results[0]);
}

static int PerformAcceptActivity(int socketFd) {
    int connectionFd = iTermFileDescriptorServerAccept(socketFd);
    if (connectionFd == -1) {
        FDLog(LOG_DEBUG, "accept failed %s", strerror(errno));
        return 0;
    }

    return SendFileDescriptorAndWait(connectionFd);
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
    strcpy(local.sun_path, path);
    unlink(local.sun_path);
    int len = strlen(local.sun_path) + sizeof(local.sun_family) + 1;
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

static int Initialize(char *path, pid_t childPid) {
    openlog("iTerm2-Server", LOG_PID | LOG_NDELAY, LOG_USER);
    setlogmask(LOG_UPTO(LOG_DEBUG));
    FDLog(LOG_DEBUG, "Server starting Initialize()");
    gPath = strdup(path);
    // We get this when iTerm2 crashes. Ignore it.
    FDLog(LOG_DEBUG, "Installing SIGHUP handler.");
    signal(SIGHUP, SIG_IGN);

    pipe(gPipe);

    FDLog(LOG_DEBUG, "Installing SIGCHLD handler.");
    gChildPid = childPid;
    signal(SIGCHLD, SigChildHandler);
    signal(SIGUSR1, SigUsr1Handler);

    // Unblock SIGCHLD.
    sigset_t signal_set;
    sigemptyset(&signal_set);
    sigaddset(&signal_set, SIGCHLD);
    FDLog(LOG_DEBUG, "Unblocking SIGCHLD.");
    sigprocmask(SIG_UNBLOCK, &signal_set, NULL);

    return 0;
}

static void MainLoop(char *path) {
    // Listen on a Unix Domain Socket.
    FDLog(LOG_DEBUG, "Entering main loop.");
    int socketFd;
    do {
        FDLog(LOG_DEBUG, "Calling iTermFileDescriptorServerSocketBindListen.");
        socketFd = iTermFileDescriptorServerSocketBindListen(path);
        if (socketFd < 0) {
            FDLog(LOG_DEBUG, "iTermFileDescriptorServerSocketBindListen failed");
            return;
        }
        FDLog(LOG_DEBUG, "Calling PerformAcceptActivity");
    } while (!PerformAcceptActivity(socketFd));
}

int iTermFileDescriptorServerRun(char *path, pid_t childPid, int connectionFd) {
    gRunningServer = 1;
    // syslog raises sigpipe when the parent job dies on 10.12.
    signal(SIGPIPE, SIG_IGN);
    int rc = Initialize(path, childPid);
    if (rc) {
        FDLog(LOG_DEBUG, "Initialize failed with code %d", rc);
    } else {
        FDLog(LOG_DEBUG, "Sending file descriptor and waiting on initial connection");
        if (!SendFileDescriptorAndWait(connectionFd)) {
            MainLoop(path);
        }
        // MainLoop never returns, except by dying on a signal.
    }
    FDLog(LOG_DEBUG, "Unlink %s", path);
    unlink(path);
    return 1;
}

