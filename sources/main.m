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
#import <signal.h>

#import "FutureMethods.h"
#import "iTermFileDescriptorSocketPath.h"
#import "PreferencePanel.h"
#import "iTermResourceLimitsHelper.h"
#import "iTermUserDefaults.h"
#import "legacy_server.h"
#import "shell_launcher.h"

int main(int argc, const char *argv[]) {
    if (argc >= 2 && !strcmp(argv[1], "--help")) {
        fprintf(stderr, "Usage: iTerm2 [--command=command] [-suite suite-name]\n");
        fprintf(stderr, "  --command=command: If given, open a window running `command` using `/usr/bin/login -fpq $USER $SHELL -c command`. Various launch actions are disabled, such as running auto-launch scripts, opening the default window arrangement (if so configured), and opening the profiles window (if so configured).\n");
        fprintf(stderr, "  -suite suite-name: If given, store all user defaults in the specified suite instead of the standard defaults. For example, -suite com.example.test stores preferences in com.example.test.\n");
#ifdef ITERM_DEBUG
        fprintf(stderr, "\nDebug options (ITERM_DEBUG build only):\n");
        fprintf(stderr, "  --use-default-config: Skip custom preferences, use built-in defaults\n");
        fprintf(stderr, "  --config=<path>: Load preferences from specified path or URL\n");
        fprintf(stderr, "  Note: These flags are mutually exclusive\n");
#endif
        return 0;
    }
    if (argc > 1 && !strcmp(argv[1], "--launch_shell")) {
        // In theory this is not used any more because the ShellLauncher executable should be used instead.
        return launch_shell(argc > 2 ? argv[2] : NULL, 0, NULL);
    } else if (argc > 1 && !strcmp(argv[1], "--server")) {
        // Run a server that spawns a job.
        return iterm2_server(argc - 2, (char *const *)argv + 2);
    }
    // Normal launch of GUI.
    // Parse -suite argument before any UserDefaults access.
    // Uses -suite (not --suite=) so Cocoa's argument parser treats it as a
    // standard -key value pair and doesn't misparse subsequent arguments.
    for (int i = 1; i + 1 < argc; i++) {
        if (strcmp(argv[i], "-suite") == 0) {
            NSString *suiteName = [NSString stringWithUTF8String:argv[i + 1]];
            [iTermUserDefaults setCustomSuiteName:suiteName];
            // Also set the custom socket prefix for file descriptor sockets
            NSString *prefix = [NSString stringWithFormat:@"%@.socket.", suiteName];
            iTermFileDescriptorSetSocketNamePrefix(prefix.UTF8String);
            break;
        }
    }
    if ([[iTermUserDefaults userDefaults] boolForKey:@"MetalCaptureEnabled"]) {
        setenv("MTL_CAPTURE_ENABLED", "1", 1);
    }
    iTermResourceLimitsHelperSaveCurrentLimits();
    signal(SIGPIPE, SIG_IGN);
    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGPIPE);
    sigprocmask(SIG_BLOCK, &signals, NULL);

    return NSApplicationMain(argc, argv);
}
