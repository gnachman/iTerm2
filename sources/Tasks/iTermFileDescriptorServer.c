#include "iTermFileDescriptorServer.h"
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

// These variables are global because signal handlers use them.
static pid_t gChildPid;
static char *gPath;
static int gPipe[2];

static pid_t Wait(void) {
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
    _exit(1);
}


static int SendFileDescriptorAndWait(int connectionFd) {
    FDLog(LOG_DEBUG, "send master fd and child pid %d", (int)gChildPid);
    int rc = iTermFileDescriptorServerSendMessageAndFileDescriptor(connectionFd, &gChildPid, sizeof(gChildPid), 0);
    if (rc <= 0) {
        FDLog(LOG_NOTICE, "send failed %s", strerror(errno));
        close(connectionFd);
        return 0;
    }

    FDLog(LOG_DEBUG, "All done. Waiting for client to disconnect or child to die.");
    int fds[2] = { gPipe[0], connectionFd };
    int results[2];
    iTermSelect(fds, sizeof(fds) / sizeof(*fds), results, 0);
    FDLog(LOG_DEBUG, "select returned. child dead=%d, connection closed=%d", results[0], results[1]);
    close(connectionFd);

    FDLog(LOG_DEBUG, "Connection closed.");
    // If the pipe has been written to then results[0] will be nonzero. That
    // means the child process has died and we can terminate. The server's
    // termination signals the client that the child is dead.
    return (results[0]);
}

static int PerformAcceptActivity(int socketFd) {
    int connectionFd = iTermFileDescriptorServerAcceptAndClose(socketFd);
    if (connectionFd == -1) {
        FDLog(LOG_DEBUG, "accept failed %s", strerror(errno));
        return 0;
    }

    return SendFileDescriptorAndWait(connectionFd);
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
    SetRunningServer();
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

