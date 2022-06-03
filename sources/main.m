// -*- mode:objc -*-
// $Id: main.m,v 1.2 2008-08-29 23:35:29 delx Exp $
//
//  main.m
//  JTerminal
//
//  Created by kuma on Thu Nov 22 2001.
//  Copyright (c) 2001 Kiichi Kusama. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PreferencePanel.h"
#import <signal.h>
#import "FutureMethods.h"
#import "iTermResourceLimitsHelper.h"
#import "legacy_server.h"
#import "shell_launcher.h"

int main(int argc, const char *argv[]){
    if (argc > 1 && !strcmp(argv[1], "--launch_shell")) {
        // In theory this is not used any more because the ShellLauncher executable should be used instead.
        return launch_shell(argc > 2 ? argv[2] : NULL, 0, NULL);
    } else if (argc > 1 && !strcmp(argv[1], "--server")) {
        // Run a server that spawns a job.
        return iterm2_server(argc - 2, (char *const *)argv + 2);
    }
    // Normal launch of GUI.
    iTermResourceLimitsHelperSaveCurrentLimits();
    signal(SIGPIPE, SIG_IGN);
    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGPIPE);
    sigprocmask(SIG_BLOCK, &signals, NULL);

    return NSApplicationMain(argc, argv);
}
