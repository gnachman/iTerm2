//
//  PTYTask+MRR.m
//  iTerm2Shared
//
//  Created by George Nachman on 4/22/19.
//

#if __has_feature(objc_arc)
#error This file must never be ARCified because it is not safe between fork and exec.
#endif

#import "PTYTask+MRR.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#include "iTermFileDescriptorClient.h"
#include "iTermFileDescriptorServer.h"
#include "iTermFileDescriptorSocketPath.h"
#import "iTermPosixTTYReplacements.h"
#import "iTermResourceLimitsHelper.h"
#include "legacy_server.h"

#include <sys/ioctl.h>

int iTermForkAndExecToRunJobInServer(iTermForkState *forkState,
                                     iTermTTYState *ttyState,
                                     NSString *tempPath,
                                     const char *argpath,
                                     char **argv,
                                     BOOL closeFileDescriptors,
                                     const char *initialPwd,
                                     char **newEnviron) {
    // Get ready to run the server in a thread.
    __block int serverConnectionFd = -1;
    DLog(@"iTermForkAndExecToRunJobInServer");
    int serverSocketFd = iTermFileDescriptorServerSocketBindListen(tempPath.UTF8String);

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    // In another thread, accept on the unix domain socket. Since it's
    // already listening, there's no race here. connect will block until
    // accept is called if the main thread wins the race. accept will block
    // til connect is called if the background thread wins the race.
    iTermFileDescriptorServerLog("Kicking off a background job to accept() in the server");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        iTermFileDescriptorServerLog("Now running the accept queue block");
        serverConnectionFd = iTermFileDescriptorServerAcceptAndClose(serverSocketFd);

        // Let the main thread go. This is necessary to ensure that
        // serverConnectionFd is written to before the main thread uses it.
        iTermFileDescriptorServerLog("Signal the semaphore");
        dispatch_semaphore_signal(semaphore);
    });

    // Connect to the server running in a thread.
    forkState->connectionFd = iTermFileDescriptorClientConnect(tempPath.UTF8String);
    assert(forkState->connectionFd != -1);  // If this happens the block dispatched above never returns. Ran out of FDs, presumably.

    // Wait for serverConnectionFd to be written to.
    iTermFileDescriptorServerLog("Waiting for the semaphore");
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    iTermFileDescriptorServerLog("The semaphore was signaled");

    dispatch_release(semaphore);

    // Remove the temporary file. The server will create a new socket file
    // if the client dies. That file's name is dependent on its process ID,
    // which we don't know yet, so that's why this temp file dance has to
    // be done.
    unlink(tempPath.UTF8String);

    // Now fork. This variant of forkpty passes through the master, slave,
    // and serverConnectionFd to the child job.
    pipe(forkState->deadMansPipe);

    // This closes serverConnectionFd and deadMansPipe[1] in the parent process but not the child.
    iTermFileDescriptorServerLog("Calling MyForkPty");
    forkState->numFileDescriptorsToPreserve = kNumFileDescriptorsToDup;
    DLog(@"Calling iTermPosixTTYReplacementForkPty");
    int fd = -1;
    assert([iTermAdvancedSettingsModel runJobsInServers]);
    forkState->pid = iTermPosixTTYReplacementForkPty(&fd, ttyState, serverConnectionFd, forkState->deadMansPipe[1]);

    if (forkState->pid == (pid_t)0) {
        // Child
        iTermExec(argpath, argv, closeFileDescriptors, 1, forkState, initialPwd, newEnviron, 1);
    }

    return fd;
}

int iTermForkAndExecToRunJobDirectly(iTermForkState *forkState,
                                     iTermTTYState *ttyState,
                                     const char *argpath,
                                     char **argv,
                                     BOOL closeFileDescriptors,
                                     const char *initialPwd,
                                     char **newEnviron) {
    int fd;
    forkState->numFileDescriptorsToPreserve = 3;
    forkState->pid = forkpty(&fd, ttyState->tty, &ttyState->term, &ttyState->win);
    if (forkState->pid == (pid_t)0) {
        // Child
        iTermExec(argpath, argv, closeFileDescriptors, 1, forkState, initialPwd, newEnviron, 1);
    }
    return fd;
}

