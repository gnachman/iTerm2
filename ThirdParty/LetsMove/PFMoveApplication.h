//
//  PFMoveApplication.h, version 1.25
//  LetsMove
//
//  Created by Andy Kim at Potion Factory LLC on 9/17/09
//
//  The contents of this file are dedicated to the public domain.

#ifdef __cplusplus
extern "C" {
#endif
	
#import <Foundation/Foundation.h>

/**
 Moves the running application to ~/Applications or /Applications if the former does not exist.
 After the move, it relaunches app from the new location.
 DOES NOT work for sandboxed applications.
 
 Call from \c NSApplication's delegate method \c -applicationWillFinishLaunching: method. */
void PFMoveToApplicationsFolderIfNecessary(void);

/**
 Check whether an app move is currently in progress.
 Returns YES if LetsMove is currently in-progress trying to move the app to the Applications folder, or NO otherwise.
 This can be used to work around a crash with apps that terminate after last window is closed.
 See https://github.com/potionfactory/LetsMove/issues/64 for details. */
BOOL PFMoveIsInProgress(void);

/**
 iTerm2: shell-quoted arguments appended to `open <app>` when relaunching, so a copy started with
 -suite NAME comes back with the same settings suite. Returns an empty string when there is no
 -suite argument. Takes the process arguments, including argv[0]. */
NSString *PFMoveRelaunchOpenArgumentsSuffix(NSArray<NSString *> *processArguments);

#ifdef __cplusplus
}
#endif
