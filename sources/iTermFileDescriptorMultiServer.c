//
//  iTermFileDescriptorMultiServer.c
//  iTerm2
//
//  Created by George Nachman on 7/22/19.
//

#include "iTermFileDescriptorMultiServer.h"

#include "iTermCLogging.h"
#include "iTermFileDescriptorServerShared.h"

#include <Availability.h>
#include <Carbon/Carbon.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#ifndef ITERM_SERVER
#error ITERM_SERVER not defined. Build process is broken.
#endif

#if !DEBUG
#  if defined(__has_feature)
#    if __has_feature(undefined_behavior_sanitizer)
#error This file should not be built with UBSAN - doing so adds an implicit dependency on Xcode.
#    endif
#  endif
#endif

const char *gMultiServerSocketPath;

// On entry there should be three file descriptors:
// 0: A socket we can accept() on. listen() was already called on it.
// 1: A connection we can sendmsg() on. accept() was already called on it.
// 2: A pipe that can be used to detect this process's termination. Do nothing with it.
// 3: A pipe we can read on.
// 4: Advisory lock on iterm2-daemon-1.socket.lock. Remains open for the lifetime of the process.
typedef enum {
    iTermMultiServerFileDescriptorAcceptSocket = 0,
    iTermMultiServerFileDescriptorInitialWrite = 1,
    iTermMultiServerFileDescriptorDeadMansPipe = 2,
    iTermMultiServerFileDescriptorInitialRead = 3,
    iTermMultiServerFileDescriptorLock = 4
} iTermMultiServerFileDescriptor;

static int MakeBlocking(int fd);

#import "iTermFileDescriptorServer.h"
#import "iTermMultiServerProtocol.h"
#import "iTermPosixTTYReplacements.h"

#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>
#include <util.h>

static int gPipe[2];
static char *gPath;
static int use_spawn;

typedef struct {
    iTermMultiServerClientOriginatedMessage messageWithLaunchRequest;
    pid_t pid;
    int terminated;  // Nonzero if process is terminated and wait()ed on.
    int willTerminate;  // Preemptively terminated. Stop reporting its existence.
    int masterFd;  // Valid only if !terminated && !willTerminate
    int status;  // Only valid if terminated. Gives status from wait.
    const char *tty;
} iTermMultiServerChild;

static iTermMultiServerChild *children;
static int numberOfChildren;
static void CheckIfBootstrapPortIsDead(void);
static void CleanUp(void);

#pragma mark - Signal handlers

static void SigChildHandler(int arg) {
    // Wake the select loop.
    write(gPipe[1], "", 1);
}

#pragma mark - Inspect Children

static int GetNumberOfReportableChildren(void) {
    int n = 0;
    for (int i = 0; i < numberOfChildren; i++) {
        if (children[i].willTerminate) {
            continue;
        }
        n++;
    }
    return n;
}

#pragma mark - Mutate Children

static void LogChild(const iTermMultiServerChild *child) {
    FDLog(LOG_DEBUG, "masterFd=%d, pid=%d, willTerminate=%d, terminated=%d, status=%d, tty=%s", child->masterFd, child->pid, child->willTerminate, child->terminated, child->status, child->tty ?: "(null)");
}

static void AddChild(const iTermMultiServerRequestLaunch *launch,
                     int masterFd,
                     const char *tty,
                     const iTermForkState *forkState) {
    if (!children) {
        children = calloc(1, sizeof(iTermMultiServerChild));
    } else {
        assert((numberOfChildren + 1) < SIZE_MAX / sizeof(iTermMultiServerChild));
        children = realloc(children, (numberOfChildren + 1) * sizeof(iTermMultiServerChild));
    }
    const int i = numberOfChildren;
    numberOfChildren += 1;
    iTermMultiServerClientOriginatedMessage tempClientMessage = {
        .type = iTermMultiServerRPCTypeLaunch,
        .payload = {
            .launch = *launch
        }
    };

    // Copy the launch request into children[i].messageWithLaunchRequest. This is done because we
    // need to own our own pointers to arrays of strings.
    iTermClientServerProtocolMessage tempMessage;
    iTermClientServerProtocolMessageInitialize(&tempMessage);
    int status;
    status = iTermMultiServerProtocolEncodeMessageFromClient(&tempClientMessage, &tempMessage);
    assert(status == 0);
    status = iTermMultiServerProtocolParseMessageFromClient(&tempMessage,
                                                            &children[i].messageWithLaunchRequest);
    assert(status == 0);
    iTermClientServerProtocolMessageFree(&tempMessage);

    // Update for the remaining fields in children[i].
    children[i].masterFd = masterFd;
    children[i].pid = forkState->pid;
    children[i].willTerminate = 0;
    children[i].terminated = 0;
    children[i].status = 0;
    children[i].tty = strdup(tty);

    FDLog(LOG_DEBUG, "Added child %d:", i);
    LogChild(&children[i]);
}

static void FreeChild(int i) {
    assert(i >= 0);
    assert(i < numberOfChildren);
    FDLog(LOG_DEBUG, "Free child %d", i);
    iTermMultiServerChild *child = &children[i];
    free((char *)child->tty);
    if (child->masterFd >= 0) {
        close(child->masterFd);
        child->masterFd = -1;
    }
    iTermMultiServerClientOriginatedMessageFree(&child->messageWithLaunchRequest);
    child->tty = NULL;
}

static void RemoveChild(int i) {
    assert(i >= 0);
    assert(i < numberOfChildren);

    FDLog(LOG_DEBUG, "Remove child %d", i);
    FreeChild(i);
    if (numberOfChildren == 1) {
        free(children);
        children = NULL;
    } else {
        const int afterCount = numberOfChildren - i - 1;
        memmove(children + i,
                children + i + 1,
                sizeof(*children) * afterCount);
        children = realloc(children, sizeof(*children) * (numberOfChildren - 1));
    }

    numberOfChildren -= 1;
}

#pragma mark - Launch

static int LaunchLegacy(const iTermMultiServerRequestLaunch *launch,
                  iTermForkState *forkState,
                  iTermTTYState *ttyStatePtr,
                  int *errorPtr) {
    iTermTTYStateInit(ttyStatePtr,
                      iTermTTYCellSizeMake(launch->columns, launch->rows),
                      iTermTTYPixelSizeMake(launch->pixel_width, launch->pixel_height),
                      launch->isUTF8);
    int fd;
    forkState->numFileDescriptorsToPreserve = 3;
    FDLog(LOG_DEBUG, "Forking...");
    forkState->pid = forkpty(&fd, ttyStatePtr->tty, &ttyStatePtr->term, &ttyStatePtr->win);
    if (forkState->pid == (pid_t)0) {
        // Child
        iTermExec(launch->path,
                  launch->argv,
                  1,  /* close file descriptors */
                  0,  /* restore resource limits */
                  forkState,
                  launch->pwd,
                  launch->envp,
                  fd);
    }
    if (forkState->pid == -1) {
        *errorPtr = errno;
        FDLog(LOG_DEBUG, "forkpty failed: %s", strerror(errno));
        return -1;
    }
    FDLog(LOG_DEBUG, "forkpty succeeded. Child pid is %d", forkState->pid);
    *errorPtr = 0;
    return fd;
}

static int LaunchModern(const iTermMultiServerRequestLaunch *launch,
                  iTermForkState *forkState,
                  iTermTTYState *ttyStatePtr,
                        int *errorPtr) {
    iTermTTYStateInit(ttyStatePtr,
                      iTermTTYCellSizeMake(launch->columns, launch->rows),
                      iTermTTYPixelSizeMake(launch->pixel_width, launch->pixel_height),
                      launch->isUTF8);
    int fd;
    forkState->numFileDescriptorsToPreserve = 3;
    FDLog(LOG_DEBUG, "Forking...");
    forkState->pid = forkpty(&fd, ttyStatePtr->tty, &ttyStatePtr->term, &ttyStatePtr->win);
    if (forkState->pid == (pid_t)0) {
        // Child
        int fds[] = { 0, 1, 2 };
        iTermSpawn(launch->path,
                   launch->argv,
                   fds,
                   forkState->numFileDescriptorsToPreserve,
                   launch->pwd,
                   launch->envp,
                   fd,
                   0);
    }
    if (forkState->pid == -1) {
        *errorPtr = errno;
        FDLog(LOG_DEBUG, "forkpty failed: %s", strerror(errno));
        return -1;
    }
    FDLog(LOG_DEBUG, "forkpty succeeded. Child pid is %d", forkState->pid);
    *errorPtr = 0;
    return fd;
}

static int Launch(const iTermMultiServerRequestLaunch *launch,
                  iTermForkState *forkState,
                  iTermTTYState *ttyStatePtr,
                  int *errorPtr) {
    if (use_spawn) {
        return LaunchModern(launch, forkState, ttyStatePtr, errorPtr);
    }
    return LaunchLegacy(launch, forkState, ttyStatePtr, errorPtr);
}

static int SendLaunchResponse(int fd, int status, pid_t pid, int masterFd, const char *tty, unsigned long long uniqueId) {
    iTermClientServerProtocolMessage obj;
    iTermClientServerProtocolMessageInitialize(&obj);

    iTermMultiServerServerOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeLaunch,
        .payload = {
            .launch = {
                .status = status,
                .pid = pid,
                .uniqueId = uniqueId,
                .tty = tty
            }
        }
    };
    const int rc = iTermMultiServerProtocolEncodeMessageFromServer(&message, &obj);
    if (rc) {
        FDLog(LOG_ERR, "Error encoding launch response");
        return -1;
    }

    ssize_t result;
    if (masterFd >= 0) {
        // Happy path. Send the file descriptor.
        FDLog(LOG_DEBUG, "NOTE: sending file descriptor");
        int error = 0;
        result = iTermFileDescriptorServerWriteLengthAndBufferAndFileDescriptor(fd,
                                                                                obj.ioVectors[0].iov_base,
                                                                                obj.ioVectors[0].iov_len,
                                                                                masterFd,
                                                                                &error);
        if (result < 0) {
            FDLog(LOG_ERR, "ERROR: SendLaunchResponse: Failed to send master FD with %s", strerror(error));
        }
    } else {
        // Error happened. Don't send a file descriptor.
        FDLog(LOG_ERR, "ERROR: *not* sending file descriptor");
        int error;
        result = iTermFileDescriptorServerWriteLengthAndBuffer(fd,
                                                               obj.ioVectors[0].iov_base,
                                                               obj.ioVectors[0].iov_len,
                                                               &error);
        if (result < 0) {
            FDLog(LOG_ERR, "SendMsg failed with %s", strerror(error));
        }
    }
    iTermClientServerProtocolMessageFree(&obj);
    return result == -1;
}

static int HandleLaunchRequest(int fd, const iTermMultiServerRequestLaunch *launch) {
    FDLog(LOG_DEBUG, "HandleLaunchRequest fd=%d", fd);
    iTermForkState forkState = {
        .connectionFd = -1,
        .deadMansPipe = { 0, 0 },
    };
    iTermTTYState ttyState;
    memset(&ttyState, 0, sizeof(ttyState));

    int error = 0;
    int masterFd = Launch(launch, &forkState, &ttyState, &error);
    if (masterFd < 0) {
        return SendLaunchResponse(fd,
                                  -1 /* status */,
                                  0 /* pid */,
                                  -1 /* masterFd */,
                                  "" /* tty */,
                                  launch->uniqueId);
    }

    // Happy path
    AddChild(launch, masterFd, ttyState.tty, &forkState);
    return SendLaunchResponse(fd,
                              0 /* status */,
                              forkState.pid,
                              masterFd,
                              ttyState.tty,
                              launch->uniqueId);
}

#pragma mark - Report Termination

static int ReportTermination(int fd, pid_t pid) {
    FDLog(LOG_DEBUG, "Report termination pid=%d fd=%d", (int)pid, fd);

    iTermClientServerProtocolMessage obj;
    iTermClientServerProtocolMessageInitialize(&obj);

    iTermMultiServerServerOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeTermination,
        .payload = {
            .termination = {
                .pid = pid,
            }
        }
    };
    const int rc = iTermMultiServerProtocolEncodeMessageFromServer(&message, &obj);
    if (rc) {
        FDLog(LOG_ERR, "Failed to encode termination report");
        return -1;
    }

    int error;
    ssize_t result = iTermFileDescriptorServerWriteLengthAndBuffer(fd,
                                                                   obj.ioVectors[0].iov_base,
                                                                   obj.ioVectors[0].iov_len,
                                                                   &error);
    if (result < 0) {
        FDLog(LOG_ERR, "SendMsg failed with %s", strerror(error));
    }
    iTermClientServerProtocolMessageFree(&obj);
    return result == -1;
}

#pragma mark - Report Child

static void PopulateReportChild(const iTermMultiServerChild *child, int isLast, iTermMultiServerReportChild *out) {
    iTermMultiServerReportChild temp = {
        .isLast = isLast,
        .pid = child->pid,
        .path = child->messageWithLaunchRequest.payload.launch.path,
        .argv = child->messageWithLaunchRequest.payload.launch.argv,
        .argc = child->messageWithLaunchRequest.payload.launch.argc,
        .envp = child->messageWithLaunchRequest.payload.launch.envp,
        .envc = child->messageWithLaunchRequest.payload.launch.envc,
        .isUTF8 = child->messageWithLaunchRequest.payload.launch.isUTF8,
        .pwd = child->messageWithLaunchRequest.payload.launch.pwd,
        .terminated = !!child->terminated,
        .tty = child->tty
    };
    *out = temp;
}

static int ReportChild(int fd, const iTermMultiServerChild *child, int isLast) {
    FDLog(LOG_DEBUG, "Report child fd=%d isLast=%d:", fd, isLast);
    LogChild(child);

    iTermClientServerProtocolMessage obj;
    iTermClientServerProtocolMessageInitialize(&obj);

    iTermMultiServerServerOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeReportChild,
    };
    PopulateReportChild(child, isLast, &message.payload.reportChild);
    const int rc = iTermMultiServerProtocolEncodeMessageFromServer(&message, &obj);
    if (rc) {
        FDLog(LOG_ERR, "Failed to encode report child");
        return -1;
    }

    int theError = 0;
    ssize_t bytes = iTermFileDescriptorServerWriteLengthAndBufferAndFileDescriptor(fd,
                                                                                   obj.ioVectors[0].iov_base,
                                                                                   obj.ioVectors[0].iov_len,
                                                                                   child->masterFd,
                                                                                   &theError);
    if (bytes < 0) {
        FDLog(LOG_ERR, "SendMsg failed with %s", strerror(theError));
        assert(theError != EAGAIN);
    } else {
        FDLog(LOG_DEBUG, "Reported child successfully");
    }
    iTermClientServerProtocolMessageFree(&obj);
    return bytes < 0;
}

#pragma mark - Termination Handling

static pid_t WaitPidNoHang(pid_t pid, int *statusOut) {
    FDLog(LOG_DEBUG, "Wait on pid %d", pid);
    pid_t result;
    do {
        result = waitpid(pid, statusOut, WNOHANG);
    } while (result < 0 && errno == EINTR);
    return result;
}

static int WaitForAllProcesses(int connectionFd) {
    FDLog(LOG_DEBUG, "WaitForAllProcesses connectionFd=%d", connectionFd);

    FDLog(LOG_DEBUG, "Emptying pipe...");
    ssize_t rc;
    do {
        char c;
        rc = read(gPipe[0], &c, sizeof(c));
    } while (rc > 0 || (rc == -1 && errno == EINTR));
    if (rc < 0 && errno != EAGAIN) {
        FDLog(LOG_ERR, "Read of gPipe[0] failed with %s", strerror(errno));
    }
    FDLog(LOG_DEBUG, "Done emptying pipe. Wait on non-terminated children.");
    for (int i = 0; i < numberOfChildren; i++) {
        if (children[i].terminated) {
            continue;
        }
        const pid_t pid = WaitPidNoHang(children[i].pid, &children[i].status);
        if (pid > 0) {
            FDLog(LOG_DEBUG, "Child with pid %d exited with status %d", (int)pid, children[i].status);
            children[i].terminated = 1;
            if (!children[i].willTerminate &&
                connectionFd >= 0 &&
                ReportTermination(connectionFd, children[i].pid)) {
                FDLog(LOG_DEBUG, "ReportTermination returned an error");
                return -1;
            }
        }
    }
    FDLog(LOG_DEBUG, "Finished making waitpid calls");
    return 0;
}

#pragma mark - Report Children

static int ReportChildren(int fd) {
    FDLog(LOG_DEBUG, "Reporting children...");
    // Iterate backwards because ReportAndRemoveDeadChild deletes the index passed to it.
    const int numberOfReportableChildren = GetNumberOfReportableChildren();
    int numberSent = 0;
    for (int i = numberOfChildren - 1; i >= 0; i--) {
        if (children[i].willTerminate) {
            continue;
        }
        if (ReportChild(fd, &children[i], numberSent + 1 == numberOfReportableChildren)) {
            FDLog(LOG_ERR, "ReportChild returned an error code");
            return -1;
        }
        numberSent += 1;
    }
    FDLog(LOG_DEBUG, "Done reporting children...");
    return 0;
}

#pragma mark - Handshake

static int HandleHandshake(int fd, iTermMultiServerRequestHandshake *handshake) {
    FDLog(LOG_DEBUG, "Handle handshake maximumProtocolVersion=%d", handshake->maximumProtocolVersion);;
    iTermClientServerProtocolMessage obj;
    iTermClientServerProtocolMessageInitialize(&obj);

    if (handshake->maximumProtocolVersion < iTermMultiServerProtocolVersion2) {
        FDLog(LOG_ERR, "Maximum protocol version is too low: %d", handshake->maximumProtocolVersion);
        return -1;
    }
    iTermMultiServerServerOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeHandshake,
        .payload = {
            .handshake = {
                .protocolVersion = iTermMultiServerProtocolVersion2,
                .numChildren = GetNumberOfReportableChildren(),
                .pid = getpid()
            }
        }
    };
    const int rc = iTermMultiServerProtocolEncodeMessageFromServer(&message, &obj);
    if (rc) {
        FDLog(LOG_ERR, "Failed to encode handshake response");
        return -1;
    }

    int error;
    ssize_t bytes = iTermFileDescriptorServerWriteLengthAndBuffer(fd,
                                                                  obj.ioVectors[0].iov_base,
                                                                  obj.ioVectors[0].iov_len,
                                                                  &error);
    if (bytes < 0) {
        FDLog(LOG_ERR, "SendMsg failed with %s", strerror(error));
    }

    iTermClientServerProtocolMessageFree(&obj);
    if (bytes < 0) {
        return -1;
    }
    return ReportChildren(fd);
}

#pragma mark - Wait

static int GetChildIndexByPID(pid_t pid) {
    for (int i = 0; i < numberOfChildren; i++) {
        if (children[i].pid == pid) {
            return i;
        }
    }
    return -1;
}

static int HandleWait(int fd, iTermMultiServerRequestWait *wait) {
    FDLog(LOG_DEBUG, "Handle wait request for pid=%d preemptive=%d", wait->pid, wait->removePreemptively);

    iTermClientServerProtocolMessage obj;
    iTermClientServerProtocolMessageInitialize(&obj);

    int childIndex = GetChildIndexByPID(wait->pid);
    int status = 0;
    iTermMultiServerResponseWaitResultType resultType = iTermMultiServerResponseWaitResultTypeStatusIsValid;
    if (childIndex < 0) {
        resultType = iTermMultiServerResponseWaitResultTypeNoSuchChild;
    } else if (!children[childIndex].terminated) {
        if (wait->removePreemptively) {
            children[childIndex].willTerminate = 1;
            close(children[childIndex].masterFd);
            children[childIndex].masterFd = -1;
            status = 0;
            resultType = iTermMultiServerResponseWaitResultTypePreemptive;
        } else {
            resultType = iTermMultiServerResponseWaitResultTypeNotTerminated;
        }
    } else {
        status = children[childIndex].status;
    }
    iTermMultiServerServerOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeWait,
        .payload = {
            .wait = {
                .pid = wait->pid,
                .status = status,
                .resultType = resultType
            }
        }
    };
    const int rc = iTermMultiServerProtocolEncodeMessageFromServer(&message, &obj);
    if (rc) {
        FDLog(LOG_ERR, "Failed to encode wait response");
        return -1;
    }

    int error;
    ssize_t bytes = iTermFileDescriptorServerWriteLengthAndBuffer(fd,
                                                                  obj.ioVectors[0].iov_base,
                                                                  obj.ioVectors[0].iov_len,
                                                                  &error);
    if (bytes < 0) {
        FDLog(LOG_ERR, "SendMsg failed with %s", strerror(error));
    }

    iTermClientServerProtocolMessageFree(&obj);
    if (bytes < 0) {
        return -1;
    }

    if (resultType == iTermMultiServerResponseWaitResultTypeStatusIsValid) {
        RemoveChild(childIndex);
    }
    return 0;
}

#pragma mark - Requests

static void HexDump(iTermClientServerProtocolMessage *message) {
    char buffer[80];
    const unsigned char *bytes = (const unsigned char *)message->message.msg_iov[0].iov_base;
    int addr = 0;
    int offset = 0;
    FDLog(LOG_DEBUG, "- Begin hex dump of message -");
    for (int i = 0; i < message->message.msg_iov[0].iov_len; i++) {
        if (i % 16 == 0 && i > 0) {
            FDLog(LOG_DEBUG, "%4d  %s", addr, buffer);
            addr = i;
            offset = 0;
        }
        offset += snprintf(buffer + offset, sizeof(buffer) - offset, "%02x ", bytes[i]);
    }
    if (offset > 0) {
        FDLog(LOG_DEBUG, "%04d  %s", addr, buffer);
    }
    FDLog(LOG_DEBUG, "- End hex dump of message -");
}

static int ReadRequest(int fd, iTermMultiServerClientOriginatedMessage *out) {
    iTermClientServerProtocolMessage message;
    FDLog(LOG_DEBUG, "Reading a request...");
    int status = iTermMultiServerRead(fd, &message);
    if (status) {
        FDLog(LOG_DEBUG, "Read failed");
        goto done;
    }

    memset(out, 0, sizeof(*out));

    status = iTermMultiServerProtocolParseMessageFromClient(&message, out);
    if (status) {
        FDLog(LOG_ERR, "Parse failed with status %d", status);
        HexDump(&message);
    } else {
        FDLog(LOG_DEBUG, "Parsed message from client:");
        iTermMultiServerProtocolLogMessageFromClient(out);
    }
    iTermClientServerProtocolMessageFree(&message);

done:
    if (status) {
        iTermMultiServerClientOriginatedMessageFree(out);
    }
    return status;
}

static int ReadAndHandleRequest(int readFd, int writeFd) {
    iTermMultiServerClientOriginatedMessage request;
    if (ReadRequest(readFd, &request)) {
        return -1;
    }
    FDLog(LOG_DEBUG, "Handle request of type %d", (int)request.type);
    iTermMultiServerProtocolLogMessageFromClient(&request);
    int result = 0;
    switch (request.type) {
        case iTermMultiServerRPCTypeHandshake:
            result = HandleHandshake(writeFd, &request.payload.handshake);
            break;
        case iTermMultiServerRPCTypeWait:
            result = HandleWait(writeFd, &request.payload.wait);
            break;
        case iTermMultiServerRPCTypeLaunch:
            result = HandleLaunchRequest(writeFd, &request.payload.launch);
            break;
        case iTermMultiServerRPCTypeTermination:
            FDLog(LOG_ERR, "Ignore termination message");
            break;
        case iTermMultiServerRPCTypeReportChild:
            FDLog(LOG_ERR, "Ignore report child message");
            break;
        case iTermMultiServerRPCTypeHello:
            FDLog(LOG_ERR, "Ignore hello");
            break;
    }
    iTermMultiServerClientOriginatedMessageFree(&request);
    return result;
}

#pragma mark - Core

static void AcceptAndReject(int socket) {
    FDLog(LOG_DEBUG, "Calling accept()...");
    int fd = iTermFileDescriptorServerAccept(socket);
    if (fd < 0) {
        FDLog(LOG_ERR, "Don't send message: accept failed");
        return;
    }

    FDLog(LOG_DEBUG, "Received connection attempt while already connected. Send rejection.");

    iTermMultiServerServerOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeHandshake,
        .payload = {
            .handshake = {
                .protocolVersion = iTermMultiServerProtocolVersionRejected,
                .numChildren = 0,
            }
        }
    };
    iTermClientServerProtocolMessage obj;
    iTermClientServerProtocolMessageInitialize(&obj);
    const int rc = iTermMultiServerProtocolEncodeMessageFromServer(&message, &obj);
    if (rc) {
        FDLog(LOG_ERR, "Failed to encode version-rejected");
        goto done;
    }
    int error;
    const ssize_t result = iTermFileDescriptorServerWriteLengthAndBuffer(fd,
                                                                         obj.ioVectors[0].iov_base,
                                                                         obj.ioVectors[0].iov_len,
                                                                         &error);
    if (result < 0) {
        FDLog(LOG_ERR, "SendMsg failed with %s", strerror(error));
    }

    iTermClientServerProtocolMessageFree(&obj);

done:
    close(fd);
}

// There is a client connected. Respond to requests from it until it disconnects, then return.
static void SelectLoop(int acceptFd, int writeFd, int readFd) {
    FDLog(LOG_DEBUG, "Begin SelectLoop.");
    while (1) {
        static const int fdCount = 3;
        int fds[fdCount] = { gPipe[0], acceptFd, readFd };
        int results[fdCount];
        FDLog(LOG_DEBUG, "Calling select()");
        iTermSelect(fds, sizeof(fds) / sizeof(*fds), results, 1 /* wantErrors */);
        CheckIfBootstrapPortIsDead();

        if (results[2]) {
            // readFd
            FDLog(LOG_DEBUG, "select: have data to read");
            if (ReadAndHandleRequest(readFd, writeFd)) {
                FDLog(LOG_DEBUG, "ReadAndHandleRequest returned failure code.");
                if (results[0]) {
                    FDLog(LOG_DEBUG, "Client hung up and also have SIGCHLD to deal with. Wait for processes.");
                    WaitForAllProcesses(-1);
                }
                break;
            }
        }
        if (results[0]) {
            // gPipe[0]
            FDLog(LOG_DEBUG, "select: SIGCHLD happened during select");
            if (WaitForAllProcesses(writeFd)) {
                break;
            }
        }
        if (results[1]) {
            // socketFd
            FDLog(LOG_DEBUG, "select: socket is readable");
            AcceptAndReject(acceptFd);
        }
    }
    FDLog(LOG_DEBUG, "Exited select loop.");
    close(writeFd);
}

static int MakeAndSendPipe(int unixDomainSocketFd) {
    int fds[2];
    if (pipe(fds) != 0) {
        return -1;
    }

    int readPipe = fds[0];
    int writePipe = fds[1];

    iTermClientServerProtocolMessage obj;
    iTermClientServerProtocolMessageInitialize(&obj);
    iTermMultiServerServerOriginatedMessage message = {
        .type = iTermMultiServerRPCTypeHello,
    };
    const int encodeRC = iTermMultiServerProtocolEncodeMessageFromServer(&message, &obj);
    if (encodeRC) {
        FDLog(LOG_ERR, "Error encoding hello");
        return -1;
    }

    int sendFDError = 0;
    const ssize_t rc = iTermFileDescriptorServerWriteLengthAndBufferAndFileDescriptor(unixDomainSocketFd,
                                                                                      obj.ioVectors[0].iov_base,
                                                                                      obj.ioVectors[0].iov_len,
                                                                                      writePipe,
                                                                                      &sendFDError);
    iTermClientServerProtocolMessageFree(&obj);
    if (rc == -1) {
        FDLog(LOG_ERR, "Failed to send write file descriptor: %s", strerror(sendFDError));
        close(readPipe);
        readPipe = -1;
    }

    FDLog(LOG_DEBUG, "Sent write end of pipe");
    close(writePipe);
    return readPipe;
}

static int iTermMultiServerAccept(int socketFd) {
    // incoming unix domain socket connection to get FDs
    int connectionFd = -1;
    while (1) {
        int fds[] = { socketFd, gPipe[0] };
        int results[2] = { 0, 0 };
        FDLog(LOG_DEBUG, "iTermMultiServerAccept calling iTermSelect...");
        iTermSelect(fds, sizeof(fds) / sizeof(*fds), results, 1);
        FDLog(LOG_DEBUG, "iTermSelect returned.");
        if (results[1]) {
            FDLog(LOG_DEBUG, "SIGCHLD pipe became readable while waiting for connection. Calling wait...");
            WaitForAllProcesses(-1);
            FDLog(LOG_DEBUG, "Done wait()ing on all children");
        }
        if (results[0]) {
            FDLog(LOG_DEBUG, "Socket became readable. Calling accept()...");
            connectionFd = iTermFileDescriptorServerAccept(socketFd);
            if (connectionFd != -1) {
                break;
            }
        }
        FDLog(LOG_DEBUG, "accept() returned %d error=%s", connectionFd, strerror(errno));
    }
    return connectionFd;
}

// Alternates between running the select loop and accepting a new connection.
static void MainLoop(char *path, int acceptFd, int initialWriteFd, int initialReadFd) {
    FDLog(LOG_DEBUG, "Entering main loop.");
    assert(acceptFd >= 0);
    assert(acceptFd != initialWriteFd);
    assert(initialWriteFd >= 0);
    assert(initialReadFd >= 0);

    int writeFd = initialWriteFd;
    int readFd = initialReadFd;
    MakeBlocking(writeFd);
    MakeBlocking(readFd);

    do {
        if (writeFd >= 0 && readFd >= 0) {
            SelectLoop(acceptFd, writeFd, readFd);
        }

        if (GetNumberOfReportableChildren() == 0) {
            // Not attached and no children? Quit rather than leave a useless daemon running.
            FDLog(LOG_DEBUG, "Exiting because no reportable children remain. %d terminating.", numberOfChildren);
            return;
        }

        // You get here after the connection is lost. Accept.
        FDLog(LOG_DEBUG, "Calling iTermMultiServerAccept");
        writeFd = iTermMultiServerAccept(acceptFd);
        if (writeFd == -1) {
            FDLog(LOG_ERR, "iTermMultiServerAccept failed: %s", strerror(errno));
            break;
        }
        CheckIfBootstrapPortIsDead();
        FDLog(LOG_DEBUG, "Accept returned a valid file descriptor %d", writeFd);
        readFd = MakeAndSendPipe(writeFd);
        MakeBlocking(writeFd);
        MakeBlocking(readFd);
    } while (writeFd >= 0 && readFd >= 0);
    FDLog(LOG_DEBUG, "Returning from MainLoop because of an error.");
}

#pragma mark - Bootstrap

static int MakeNonBlocking(int fd) {
    int flags = fcntl(fd, F_GETFL);
    int rc = 0;
    do {
        rc = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    } while (rc == -1 && errno == EINTR);
    return rc == -1;
}

static int MakeBlocking(int fd) {
    int flags = fcntl(fd, F_GETFL);
    int rc = 0;
    do {
        rc = fcntl(fd, F_SETFL, flags & (~O_NONBLOCK));
    } while (rc == -1 && errno == EINTR);
    FDLog(LOG_DEBUG, "MakeBlocking(%d) returned %d (%s)", fd, rc, strerror(errno));
    return rc == -1;
}

static int MakeStandardFileDescriptorsNonBlocking(void) {
    int status = 1;

    if (MakeNonBlocking(iTermMultiServerFileDescriptorAcceptSocket)) {
        goto done;
    }
    if (MakeBlocking(iTermMultiServerFileDescriptorInitialWrite)) {
        goto done;
    }
    if (MakeBlocking(iTermMultiServerFileDescriptorDeadMansPipe)) {
        goto done;
    }
    if (MakeBlocking(iTermMultiServerFileDescriptorInitialRead)) {
        goto done;
    }
    status = 0;

done:
    return status;
}

static int MakePipe(void) {
    if (pipe(gPipe) < 0) {
        FDLog(LOG_ERR, "Failed to create pipe: %s", strerror(errno));
        return 1;
    }

    // Make pipes nonblocking
    for (int i = 0; i < 2; i++) {
        if (MakeNonBlocking(gPipe[i])) {
            FDLog(LOG_ERR, "Failed to set gPipe[%d] nonblocking: %s", i, strerror(errno));
            return 2;
        }
    }
    return 0;
}

static int InitializeSignals(void) {
    // We get this when iTerm2 crashes. Ignore it.
    FDLog(LOG_DEBUG, "Installing SIGHUP handler.");
    sig_t rc = signal(SIGHUP, SIG_IGN);
    if (rc == SIG_ERR) {
        FDLog(LOG_ERR, "signal(SIGHUP, SIG_IGN) failed with %s", strerror(errno));
        return 1;
    }

    // Unblock SIGCHLD.
    sigset_t signal_set;
    sigemptyset(&signal_set);
    sigaddset(&signal_set, SIGCHLD);
    FDLog(LOG_DEBUG, "Unblocking SIGCHLD.");
    if (sigprocmask(SIG_UNBLOCK, &signal_set, NULL) == -1) {
        FDLog(LOG_ERR, "sigprocmask(SIG_UNBLOCK, &signal_set, NULL) failed with %s", strerror(errno));
        return 1;
    }

    FDLog(LOG_DEBUG, "Installing SIGCHLD handler.");
    rc = signal(SIGCHLD, SigChildHandler);
    if (rc == SIG_ERR) {
        FDLog(LOG_ERR, "signal(SIGCHLD, SigChildHandler) failed with %s", strerror(errno));
        return 1;
    }

    FDLog(LOG_DEBUG, "signals initialized");
    return 0;
}

static void InitializeLogging(void) {
    openlog("iTerm2-Server", LOG_PID | LOG_NDELAY, LOG_USER);
    setlogmask(LOG_UPTO(LOG_DEBUG));
}

static void QuitCleanly(void) {
    FDLog(LOG_ERR, "QuitCleanly");
    CleanUp();
    _exit(0);
}

// NOTE: If I am ever forced to use a CFRunLoop in this process, then I can get a callback when
// the port is invalidated by using CFMachPortCreateWithPort, CFMachPortSetInvalidationCallBack,
// CFRunLoopAddSource, and CFRunLoopRun. See TN2050 mirrored at:
// https://www.fenestrated.net/mirrors/Apple%20Technotes%20(As%20of%202002)/tn/tn2050.html
static void CheckIfBootstrapPortIsDead(void) {
    mach_port_t port = 0;
    if (task_get_bootstrap_port(mach_task_self(), &port) != KERN_SUCCESS) {
        FDLog(LOG_ERR, "Unable to get the bootstrap port! errno=%d", errno);
        QuitCleanly();
    }
    mach_port_type_t type = 0;
    if (mach_port_type(mach_task_self(), port, &type) != KERN_SUCCESS) {
        FDLog(LOG_ERR, "Unable to get the type of the bootstrap port! errno=%d", errno);
        QuitCleanly();
    }
    if (type == MACH_PORT_TYPE_DEAD_NAME) {
        FDLog(LOG_ERR, "The bootstrap port has type DEAD. This indicates the user's session has died and this process is unusable. This can happen after a logout-login sequence. iTermServer will now terminate.");
        QuitCleanly();
    }
    FDLog(LOG_DEBUG, "Bootstrap port isn't dead yet.");
}

static int Initialize(char *path) {
    InitializeLogging();

    FDLog(LOG_DEBUG, "Server starting Initialize()");

    if (MakeStandardFileDescriptorsNonBlocking()) {
        return 1;
    }

    gPath = strdup(path);

    if (MakePipe()) {
        return 1;
    }

    if (InitializeSignals()) {
        return 1;
    }
    chdir("/");

    use_spawn = getenv("ITERM_FDMS_USE_SPAWN") != NULL;

    return 0;
}

static int iTermFileDescriptorMultiServerDaemonize(void) {
    switch (fork()) {
        case -1:
            // Error
            return -1;
        case 0:
            // Child
            break;
        default:
            // Parent
            _exit(0);
    }

    if (setsid() == -1) {
        return -1;
    }

    return 0;
}

static void CleanUp(void) {
    FDLog(LOG_DEBUG, "Cleaning up to exit");
    if (!gPath) {
        FDLog(LOG_DEBUG, "Don't have a socket path to remove.");
        return;
    }
    FDLog(LOG_DEBUG, "Unlink %s", gPath);
    unlink(gPath);
}

static int iTermFileDescriptorMultiServerRun(char *path, int socketFd, int writeFD, int readFD) {
    const int daemonize = 0;

    if (daemonize) {
        iTermFileDescriptorMultiServerDaemonize();
    }

    SetRunningServer();
    // If iTerm2 dies while we're blocked in sendmsg we get a deadly sigpipe.
    signal(SIGPIPE, SIG_IGN);
    int rc = Initialize(path);
    if (rc) {
        FDLog(LOG_ERR, "Initialize failed with code %d", rc);
    } else {
        MainLoop(path, socketFd, writeFD, readFD);
        // MainLoop never returns, except by dying on a signal.
    }
    CleanUp();
    return 1;
}

// There should be a single command-line argument, which is the path to the unix-domain socket
// I'll use.
int main(int argc, char *argv[]) {
    assert(argc == 2);
    gMultiServerSocketPath = argv[1];
    iTermFileDescriptorMultiServerRun(argv[1],
                                      iTermMultiServerFileDescriptorAcceptSocket,
                                      iTermMultiServerFileDescriptorInitialWrite,
                                      iTermMultiServerFileDescriptorInitialRead);
    return 1;
}
