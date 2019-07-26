//
//  iTermFileDescriptorMultiClient+MRR.m
//  iTerm2
//
//  Created by George Nachman on 8/9/19.
//

#import "iTermFileDescriptorMultiClient+MRR.h"
#import "iTermFileDescriptorMultiClient+Protected.h"

#import "DebugLogging.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermFileDescriptorServer.h"
#import "iTermPosixTTYReplacements.h"
#include <sys/un.h>

static const NSInteger numberOfFileDescriptorsToPreserve = 4;

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

iTermFileDescriptorMultiClientAttachStatus iTermConnectToUnixDomainSocket(const char *path, int *fdOut) {
    int interrupted = 0;
    int socketFd;
    int flags;

    DLog(@"Trying to connect to %s", path);
    do {
        DLog(@"Calling socket()");
        socketFd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (socketFd == -1) {
            DLog(@"Failed to create socket: %s\n", strerror(errno));
            return iTermFileDescriptorMultiClientAttachStatusFatalError;
        }

        struct sockaddr_un remote;
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
            interrupted = (errno == EINTR);
            DLog(@"Connect failed: %s\n", strerror(errno));
            close(socketFd);
            if (!interrupted) {
                return iTermFileDescriptorMultiClientAttachStatusConnectFailed;
            }
            DLog(@"Trying again because connect returned EINTR.");
        } else {
            // Make socket block again.
            interrupted = 0;
            DLog(@"Connected. Calling fcntl() 3");
            fcntl(socketFd, F_SETFL, flags & ~O_NONBLOCK);
        }
    } while (interrupted);
    *fdOut = socketFd;
    return iTermFileDescriptorMultiClientAttachStatusSuccess;
}

int iTermCreateConnectedUnixDomainSocket(const char *path,
                                         int closeAfterAccept,
                                         int *listenFDOut,
                                         int *acceptedFDOut,
                                         int *connectFDOut) {
    *listenFDOut = iTermFileDescriptorServerSocketBindListen(path);

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    // In another thread, accept on the unix domain socket. Since it's
    // already listening, there's no race here. connect will block until
    // accept is called if the main thread wins the race. accept will block
    // til connect is called if the background thread wins the race.
    iTermFileDescriptorServerLog("Kicking off a background job to accept() in the server");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        iTermFileDescriptorServerLog("Now running the accept queue block");
        if (closeAfterAccept) {
            *acceptedFDOut = iTermFileDescriptorServerAcceptAndClose(*listenFDOut);
        } else {
            *acceptedFDOut = iTermFileDescriptorServerAccept(*listenFDOut);
        }

        // Let the main thread go. This is necessary to ensure that
        // *acceptedFDOut is written to before the main thread uses it.
        iTermFileDescriptorServerLog("Signal the semaphore");
        dispatch_semaphore_signal(semaphore);
    });

    // Connect to the server running in a thread.
    switch (iTermConnectToUnixDomainSocket(path, connectFDOut)) {
        case iTermFileDescriptorMultiClientAttachStatusSuccess:
            break;
        case iTermFileDescriptorMultiClientAttachStatusConnectFailed:
        case iTermFileDescriptorMultiClientAttachStatusFatalError:
            // It's pretty weird if this fails.
            dispatch_release(semaphore);
            close(*acceptedFDOut);
            close(*listenFDOut);
            *listenFDOut = -1;
            *acceptedFDOut = -1;
            *connectFDOut = -1;
            return NO;
    }

    // Wait until the background thread finishes accepting.
    iTermFileDescriptorServerLog("Waiting for the semaphore");
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    iTermFileDescriptorServerLog("The semaphore was signaled");
    dispatch_release(semaphore);

    return YES;
}

// NOTE: Sets _readFD as client file descriptor as a side-effect
- (BOOL)createAttachedSocketAtPath:(NSString *)path
                            listen:(int *)listenFDOut  // has called listen() on this one
                          accepted:(int *)acceptedFDOut  // has called accept() on this one
                         connected:(int *)connectedFDOut {  // has called connect() on this one
    DLog(@"iTermForkAndExecToRunJobInServer");
    BOOL ok = iTermCreateConnectedUnixDomainSocket(path.UTF8String,
                                                   NO,  /* closeAfterAccept */
                                                   listenFDOut,
                                                   acceptedFDOut,
                                                   connectedFDOut);
    if (ok) {
        _readFD = *connectedFDOut;
    }
    return ok;
}

// NOTE: Sets _readFD and _writeFD as side-effects when returned forkState.pid >= 0.
- (iTermForkState)launchWithSocketPath:(NSString *)path
                            executable:(NSString *)executable {
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
    int listenFd;
    int acceptedFd;
    int connectedFd;

    const BOOL ok = [self createAttachedSocketAtPath:path listen:&listenFd accepted:&acceptedFd connected:&connectedFd];
    if (!ok) {
        return forkState;
    }

    forkState.connectionFd = connectedFd;
    forkState.writeFd = pipeFds[1];

    pipe(forkState.deadMansPipe);

    NSArray<NSString *> *argv = @[ executable, path ];
    char **cargv = Make2DArray(argv);
    const char **cenv = (const char **)Make2DArray(@[]);
    const char *argpath = executable.UTF8String;

    int fds[] = { listenFd, acceptedFd, forkState.deadMansPipe[1], pipeFds[0] };
    assert(sizeof(fds) / sizeof(*fds) == numberOfFileDescriptorsToPreserve);

    forkState.pid = fork();
    switch (forkState.pid) {
        case -1:
            // error
            iTermFileDescriptorServerLog("Fork failed: %s", strerror(errno));
            return forkState;

        case 0: {
            // child
            close(pipeFds[1]);
            iTermPosixMoveFileDescriptors(fds, numberOfFileDescriptorsToPreserve);
            iTermExec(argpath,
                      (const char **)cargv,
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
            close(listenFd);
            close(acceptedFd);
            close(forkState.deadMansPipe[1]);
            Free2DArray(cargv, argv.count);
            close(pipeFds[0]);
            _writeFD = pipeFds[1];
            Free2DArray((char **)cenv, 0);
            return forkState;
    }
}

@end
