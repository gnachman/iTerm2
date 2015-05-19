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
static int gChildDeathPipeFd;
static int gSocketFd;
static int gReturnCode;
static int gChildIsDead;
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

static void SigChildHandler(int arg) {
    if (wait(&gReturnCode) == gChildPid) {
        // TODO: Does this need to be a nonblocking write?
        write(gChildDeathPipeFd, &gReturnCode, sizeof(gReturnCode));
        close(gSocketFd);
        gChildIsDead = 1;
    }
}

static void HandleSIGUSR1(int arg) {
    kill(gChildPid, SIGHUP);
}

int FileDescriptorServerRun(char *path, pid_t childPid) {
    gChildPid = childPid;
    // We get this when iTerm2 crashes. Ignore it.
    signal(SIGHUP, SIG_IGN);
    signal(SIGUSR1, HandleSIGUSR1);

    gSocketFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (gSocketFd == -1) {
        return 1;
    }

    struct sockaddr_un local;
    local.sun_family = AF_UNIX;
    strcpy(local.sun_path, path);
    unlink(local.sun_path);
    int len = strlen(local.sun_path) + sizeof(local.sun_family) + 1;
    if (bind(gSocketFd, (struct sockaddr *)&local, len) == -1) {
        return 1;
    }

    if (listen(gSocketFd, kMaxConnections) == -1) {
        return 1;
    }

    int pipeFds[2];
    int rc = pipe(pipeFds);
    if (rc) {
        return 1;
    }

    gChildDeathPipeFd = pipeFds[1];
    // There's a race here; if the child dies before this point, we'll not know. Maybe try waiting
    // after installing the handler?
    signal(SIGCHLD, SigChildHandler);

    f = fopen("/tmp/log.txt", "w");
    while (!gChildIsDead) {
        fd_set rfds;
        fd_set wfds;
        fd_set efds;
        int highfd;

        FD_ZERO(&rfds);
        FD_ZERO(&wfds);
        FD_ZERO(&efds);

        FD_SET(pipeFds[0], &rfds);
        FD_SET(gSocketFd, &rfds);
        highfd = pipeFds[0];
        if (gSocketFd > highfd) {
            highfd = gSocketFd;
        }

        fprintf(f, "Calling select...\n"); fflush(f);
        if (select(highfd + 1, &rfds, &wfds, &efds, NULL) < 0) {
            fprintf(f, "Select returned error\n"); fflush(f);
            continue;
        }
        fprintf(f, "Select returned nonnegative"); fflush(f);

        if (FD_ISSET(pipeFds[0], &rfds)) {
            // sigchild tickled the pipe so exit.
            fprintf(f, "Pipe is readable, I guess my child is dead.\n"); fflush(f);
            return gReturnCode;
        }

        if (FD_ISSET(gSocketFd, &rfds)) {
            fprintf(f, "Socket is readable, call accept...\n"); fflush(f);
            // incoming unix domain socket connection to get FDs
            struct sockaddr_un remote;
            socklen_t sizeOfRemote = sizeof(remote);
            int connectionFd = accept(gSocketFd, (struct sockaddr *)&remote, &sizeOfRemote);
            if (connectionFd == -1) {
                fprintf(f, "accept failed %s\n", strerror(errno)); fflush(f);
                return 1;
            }

            fprintf(f, "send PTY fd\n"); fflush(f);
            rc = SendMessageAndFileDescriptor(connectionFd, "m", 3);  // PTY master
            if (rc <= 0) {
                fprintf(f, "send failed %s\n", strerror(errno)); fflush(f);
                close(connectionFd);
                continue;
            }

            fprintf(f, "send read end of pipe fd\n"); fflush(f);
            rc = SendMessageAndFileDescriptor(connectionFd, "p", pipeFds[0]);
            if (rc <= 0) {
                fprintf(f, "send failed %s\n", strerror(errno)); fflush(f);
                close(connectionFd);
                continue;
            }

            fprintf(f, "send pid\n"); fflush(f);
            rc = SendMessage(connectionFd, &gChildPid, sizeof(gChildPid));
            if (rc <= 0) {
                fprintf(f, "send failed %s\n", strerror(errno)); fflush(f);
                close(connectionFd);
                continue;
            }

            fprintf(f, "All done!"); fflush(f);
            close(connectionFd);
        }
    }
    fprintf(f, "Child is dead\n");
    fflush(f);
    return 1;
}
