//
//  iTermFileDescriptorMultiClient+MRR.m
//  iTerm2
//
//  Created by George Nachman on 8/9/19.
//

#import "iTermFileDescriptorMultiClient+MRR.h"

#import "DebugLogging.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermFileDescriptorServer.h"
#import "iTermPosixTTYReplacements.h"
#include <sys/un.h>

static const NSInteger numberOfFileDescriptorsToPreserve = 5;

static char **Make2DArray(NSArray<NSString *> *strings) {
    char **result = (char **)malloc(sizeof(char *) * (strings.count + 1));
    for (NSInteger i = 0; i < strings.count; i++) {
        result[i] = strdup(strings[i].UTF8String);
    }
    result[strings.count] = NULL;
    return result;
}

static void Free2DArray(char **array, NSInteger count) {
    for (NSInteger i = 0; i < count; i++) {
        free(array[i]);
    }
    free(array);
}

@implementation iTermFileDescriptorMultiClient (MRR)

iTermFileDescriptorMultiClientAttachStatus iTermConnectToUnixDomainSocket(NSString *pathString,
                                                                          int *fdOut,
                                                                          int async) {
    int interrupted = 0;
    int socketFd;
    int flags;

    const char *path = pathString.UTF8String;
    DLog(@"Trying to connect to %s", path);
    do {
        struct sockaddr_un remote;
        if (strlen(path) + 1 > sizeof(remote.sun_path)) {
            DLog(@"Path is too long: %s", path);
            return iTermFileDescriptorMultiClientAttachStatusFatalError;
        }

        DLog(@"Calling socket()");
        socketFd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (socketFd == -1) {
            DLog(@"Failed to create socket: %s\n", strerror(errno));
            return iTermFileDescriptorMultiClientAttachStatusFatalError;
        }
        remote.sun_family = AF_UNIX;
        strcpy(remote.sun_path, path);
        const socklen_t len = (socklen_t)(strlen(remote.sun_path) + sizeof(remote.sun_family) + 1);
        DLog(@"Calling fcntl() 1");
        flags = fcntl(socketFd, F_GETFL, 0);

        // Put the socket in nonblocking mode so connect can fail fast if another iTerm2 is connected
        // to this server.
        DLog(@"Calling fcntl() 2");
        fcntl(socketFd, F_SETFL, flags | O_NONBLOCK);

        DLog(@"Calling connect()");
        int rc = connect(socketFd, (struct sockaddr *)&remote, len);
        if (rc == -1) {
            if (errno == EINPROGRESS) {
                if (async) {
                    *fdOut = socketFd;
                    return iTermFileDescriptorMultiClientAttachStatusInProgress;
                }
                // per connect(2): EINPROGRESS means the connection cannot be completed
                // immediately, and you should select for writing to wait for completion.
                // See also: https://cr.yp.to/docs/connect.html
                int fds[1] = { socketFd };
                int results[1] = { 0 };
                iTermSelectForWriting(fds, 1, results, 0);
                *fdOut = socketFd;
                return iTermFileDescriptorMultiClientAttachStatusSuccess;
            }
            interrupted = (errno == EINTR);
            DLog(@"Connect failed: %s\n", strerror(errno));
            close(socketFd);
            if (!interrupted) {
                return iTermFileDescriptorMultiClientAttachStatusConnectFailed;
            }
            DLog(@"Trying again because connect returned EINTR.");
        } else {
            interrupted = 0;
        }
    } while (interrupted);
    *fdOut = socketFd;
    return iTermFileDescriptorMultiClientAttachStatusSuccess;
}

iTermUnixDomainSocketConnectResult iTermCreateConnectedUnixDomainSocket(NSString *pathString,
                                                                        int closeAfterAccept) {
    const char *path = pathString.UTF8String;
    NSString *lockPath = [[NSString stringWithUTF8String:path] stringByAppendingString:@".lock"];
    iTermUnixDomainSocketConnectResult result = {
        .ok = NO,
        .lockFD = iTermAcquireAdvisoryLock(lockPath.UTF8String)
    };

    if (result.lockFD < 0) {
        DLog(@"Failed to acquire lock.");
        return (iTermUnixDomainSocketConnectResult) {
            .ok = NO,
            .listenFD = -1,
            .acceptedFD = -1,
            .connectedFD = -1,
            .readFD = -1,
            .lockFD = -1
        };
    }

    // Per https://stackoverflow.com/questions/17769964/linux-sockets-non-blocking-connect
    // To do an async connect you have to first listen, then connect, then accept.
    result.listenFD = iTermFileDescriptorServerSocketBindListen(path);

    DLog(@"Connect asynchronously to UDS at %s", path);
    const iTermFileDescriptorMultiClientAttachStatus connectStatus =
        iTermConnectToUnixDomainSocket(pathString,
                                       &result.connectedFD,
                                       1 /* async */);

    switch (connectStatus) {
        case iTermFileDescriptorMultiClientAttachStatusSuccess:
        case iTermFileDescriptorMultiClientAttachStatusInProgress:
            // I don't know why, but connect() doesn't return EINPROGRESS. It returns 0. I can't
            // get it to take the InProgress code path!
            break;
        case iTermFileDescriptorMultiClientAttachStatusConnectFailed:
        case iTermFileDescriptorMultiClientAttachStatusFatalError:
            // It's pretty weird if this fails.
            close(result.listenFD);
            close(result.lockFD);
            return (iTermUnixDomainSocketConnectResult) {
                .ok = NO,
                .listenFD = -1,
                .acceptedFD = -1,
                .connectedFD = -1,
                .readFD = -1,
                .lockFD = -1
            };
    }
    iTermFileDescriptorServerLog("Now calling accept");
    if (closeAfterAccept) {
        result.acceptedFD = iTermFileDescriptorServerAcceptAndClose(result.listenFD);
    } else {
        result.acceptedFD = iTermFileDescriptorServerAccept(result.listenFD);
    }

    if (result.acceptedFD < 0) {
        iTermFileDescriptorServerLog("Accept failed with %s", strerror(errno));
        close(result.listenFD);
        return (iTermUnixDomainSocketConnectResult) {
            .ok = NO,
            .listenFD = -1,
            .acceptedFD = -1,
            .connectedFD = -1,
            .readFD = -1
        };
    }

    // This is here because it might be useful in theory, but I cannot test it. According to the
    // man page for connect, it should return EINPROGRESS for a nonblocking socket. If that were
    // to happen we would need to wait for the remote to accept(). This will block until that
    // happens.
    int fds[1] = { result.connectedFD };
    int results[1] = { 0 };
    iTermSelectForWriting(fds, 1, results, 0);

    // https://cr.yp.to/docs/connect.html
    // Again, I can't get this to happen, but if EINPROGRESS *did* occur and then the remote closed
    // the socket, it should leave an error in the so_err sockopt.
    int option_value = 0;
    socklen_t option_len = sizeof(option_value);
    const int rc = getsockopt(result.connectedFD, SOL_SOCKET, SO_ERROR, &option_value, &option_len);
    if (rc < 0 || option_value) {
        iTermFileDescriptorServerLog("getsockopt failed with %s", strerror(errno));
        close(result.listenFD);
        close(result.connectedFD);
        close(result.acceptedFD);
        return (iTermUnixDomainSocketConnectResult) {
            .ok = NO,
            .listenFD = -1,
            .acceptedFD = -1,
            .connectedFD = -1,
            .readFD = -1
        };
    }

    result.ok = YES;
    result.readFD = result.connectedFD;
    return result;
}

- (iTermUnixDomainSocketConnectResult)createAttachedSocketAtPath:(NSString *)path {
    DLog(@"iTermForkAndExecToRunJobInServer");
    return iTermCreateConnectedUnixDomainSocket(path, NO /* closeAfterAccept */);
}

// NOTE: Sets _readFD and _writeFD as side-effects when returned forkState.pid >= 0.
- (iTermForkState)launchWithSocketPath:(NSString *)path
                            executable:(NSString *)executable
                                readFD:(int *)readFDOut
                               writeFD:(int *)writeFDOut {
    assert([iTermAdvancedSettingsModel runJobsInServers]);

    iTermForkState forkState = {
        .pid = -1,
        .connectionFd = 0,
        .deadMansPipe = { 0, 0 },
        .numFileDescriptorsToPreserve = numberOfFileDescriptorsToPreserve,
        .writeFd = -1
    };

    int pipeFds[2];
    if (pipe(pipeFds) == -1) {
        DLog(@"Failed to create file descriptors in pipe(): %s", strerror(errno));
        return forkState;
    }

    // Get ready to run the server in a thread.
    const iTermUnixDomainSocketConnectResult connectResult = [self createAttachedSocketAtPath:path];
    *readFDOut = connectResult.readFD;

    if (!connectResult.ok) {
        return forkState;
    }

    forkState.connectionFd = connectResult.connectedFD;
    forkState.writeFd = pipeFds[1];

    pipe(forkState.deadMansPipe);

    NSArray<NSString *> *argv = @[ executable, path ];
    char **cargv = Make2DArray(argv);
    NSArray<NSString *> *env = @[];
    if ([iTermAdvancedSettingsModel disclaimChildren]) {
        env = [env arrayByAddingObject:@"ITERM_FDMS_USE_SPAWN=1"];
    }
    char **cenv = Make2DArray(env);
    const char *argpath = executable.UTF8String;

    int fds[] = {
        connectResult.listenFD,
        connectResult.acceptedFD,
        forkState.deadMansPipe[1],
        pipeFds[0],
        connectResult.lockFD
    };
    assert(sizeof(fds) / sizeof(*fds) == numberOfFileDescriptorsToPreserve);

    forkState.pid = fork();
    switch (forkState.pid) {
        case -1:
            // error
            iTermFileDescriptorServerLog("Fork failed: %s", strerror(errno));
            close(connectResult.listenFD);
            close(connectResult.acceptedFD);
            close(connectResult.lockFD);
            close(forkState.deadMansPipe[1]);
            Free2DArray(cargv, argv.count);
            close(pipeFds[0]);
            *writeFDOut = pipeFds[1];
            Free2DArray((char **)cenv, 0);
            return forkState;

        case 0: {
            // child
            close(pipeFds[1]);
            iTermPosixMoveFileDescriptors(fds, numberOfFileDescriptorsToPreserve);
            iTermExec(argpath,
                      cargv,
                      YES,  // closeFileDescriptors
                      YES, // restoreResourceLimits
                      &forkState,
                      "/",  // initialPwd
                      cenv,  // newEnviron
                      1);  // errorFd
            return forkState;
        }
        default:
            // parent
            close(connectResult.listenFD);
            close(connectResult.acceptedFD);
            close(connectResult.lockFD);
            close(forkState.deadMansPipe[1]);
            Free2DArray(cargv, argv.count);
            close(pipeFds[0]);
            *writeFDOut = pipeFds[1];
            Free2DArray((char **)cenv, 0);
            return forkState;
    }
}

@end
