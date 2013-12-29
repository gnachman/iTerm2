//
//  AppleScriptTest.m
//  iTerm
//
//  Created by Alberto Miguel Pose on 28/12/13.
//
//

#import "AppleScriptTest.h"

#import <AppKit/NSWorkspace.h>
#import "iTermTests.h"

@implementation AppleScriptTest

- (void)testAppleScriptSplitCommand {
    // ------ Arrange ------
    NSURL *appURL = [NSURL fileURLWithPath:@"./iTerm.app"];
    NSWorkspace *sharedWorkspace = [NSWorkspace sharedWorkspace];

    BOOL isRunning = [sharedWorkspace launchApplication:[appURL path]];

    // Make sure iTerm is running before executing AppleScript
    assert(isRunning);

    // We inject the exact path of the executable to the script in order not
    // to interfere with other iTerm instances that may be present.
    NSString *script = [NSString stringWithFormat:
        @"tell application\"%@\"                                                            \n"
         "  activate                                                                        \n"
         "  set oldSessionCount to (count of (sessions of current terminal))                \n"
         "  -- by default splits horizontally                                               \n"
         "  tell current terminal to split                                                  \n"
         "  tell current terminal to split direction \"vertical\"                           \n"
         "  tell current terminal to split direction \"horizontal\"                         \n"
         "  tell current terminal to split direction \"vertical\" session \"Default\"       \n"
         "  tell current terminal to split direction \"horizontal\" session \"Default\"     \n"
         "  set newSessionCount to (count of (sessions of current terminal))                \n"
         "end tell                                                                          \n"
         "{oldSessionCount, newSessionCount}                                                \n",
        [appURL path]
    ];
    NSAppleScript *appleScript = [[[NSAppleScript alloc] initWithSource:script] autorelease];
    NSDictionary *errorInfo = NULL;

    // ------- Act -------
    NSAppleEventDescriptor *eventDescriptor = [appleScript executeAndReturnError:&errorInfo];

    // ------ Assert -----
    // no errors were thrown in the AppleScript script
    assert(NULL == errorInfo);

    int sessionCountBefore = [[eventDescriptor descriptorAtIndex:1] int32Value];
    int sessionCountAfter = [[eventDescriptor descriptorAtIndex:2] int32Value];

    // newly created sessions are present
    assert(sessionCountBefore + 5 == sessionCountAfter);

    // ---- Free/Clean up -----
    for (NSRunningApplication *app in [sharedWorkspace runningApplications]) {
        NSString *launchedAppPath = [appURL path];
        NSString *appPath = [[app executableURL] path];

        // Removing the "/Contents/MacOS/iTerm" part of the path to match
        if([appPath hasSuffix:@"/Contents/MacOS/iTerm"]) {
            NSUInteger lengthToTrim = [appPath length] - [@"/Contents/MacOS/iTerm" length];

            appPath = [appPath substringToIndex:lengthToTrim];

            if ([launchedAppPath isEqualToString:appPath] ) {
                [app forceTerminate];
            }
        }
    }
}

@end
