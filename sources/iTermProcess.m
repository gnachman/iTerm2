//
//  iTermProcess.m
//  iTerm2
//
//  Created by George Nachman on 5/28/24.
//

#import "iTermProcess.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "iTermMalloc.h"
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

extern char **environ;

pid_t iTermStartProcess(NSURL *url, NSArray<NSString *> *args, int fd_in, int fd_out) {
    posix_spawn_file_actions_t actions;

    // Initialize the file actions object
    int status = posix_spawn_file_actions_init(&actions);
    if (status != 0) {
        DLog(@"posix_spawn_file_actions_init");
        return -1;
    }

    // Set up attrs
    posix_spawnattr_t attrs;
    {
        short flags = 0;
        // Use spawn-sigdefault in attrs rather than inheriting parent's signal
        // actions (vis-a-vis caught vs default action)
        flags |= POSIX_SPAWN_SETSIGDEF;
        // Use spawn-sigmask of attrs for the initial signal mask.
        flags |= POSIX_SPAWN_SETSIGMASK;
        // Close all file descriptors except those created by file actions.
        flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;

        int rc = posix_spawnattr_init(&attrs);
        if (rc != 0) {
            DLog(@"posix_spawnattr_init");
            return -1;
        }
        rc = posix_spawnattr_setflags(&attrs, flags);
        if (rc != 0) {
            DLog(@"posix_spawnattr_setflags");
            return -1;
        }

        // Do not start the new process with signal handlers.
        sigset_t default_signals;
        sigfillset(&default_signals);
        for (int i = 1; i < NSIG; i++) {
            sigdelset(&default_signals, i);
        }
        posix_spawnattr_setsigdefault(&attrs, &default_signals);

        // Unblock all signals.
        sigset_t signals;
        sigemptyset(&signals);
        posix_spawnattr_setsigmask(&attrs, &signals);
    }
    
    // Redirect standard input
    status = posix_spawn_file_actions_adddup2(&actions, fd_in, STDIN_FILENO);
    if (status != 0) {
        DLog(@"posix_spawn_file_actions_adddup2 for stdin");
        posix_spawn_file_actions_destroy(&actions);
        return -1;
    }

    // Redirect standard output
    status = posix_spawn_file_actions_adddup2(&actions, fd_out, STDOUT_FILENO);
    if (status != 0) {
        DLog(@"posix_spawn_file_actions_adddup2 for stdout");
        posix_spawn_file_actions_destroy(&actions);
        return -1;
    }

    // Make argv out of C strings.
    char **argv = [args nullTerminatedCStringArray];

    // Spawn the process
    pid_t pid = 0;
    status = posix_spawn(&pid, url.path.UTF8String, &actions, &attrs, argv, environ);

    iTermFreeeNullTerminatedCStringArray(argv);

    if (status == 0) {
        DLog(@"Process spawned successfully, PID: %d\n", pid);
    } else {
        DLog(@"posix_spawn");
        pid = -1;
    }

    // Clean up file actions
    posix_spawn_file_actions_destroy(&actions);

    return pid;
}

int iTermProcessExitStatus(int status) {
    return WEXITSTATUS(status);
}
