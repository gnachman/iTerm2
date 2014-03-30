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

// NOTE: This test is finicky because its behavior can change depending on user preferences and how
// iTerm windows are restored. It might also require the user to interact with a close confirmation
// dialog.
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
        @"tell application\"%@\"                                                                    \n"
         "  activate                                                                                \n"
         "  set oldSessionCount to (count of (sessions of current terminal))                        \n"
         "  -- by default splits horizontally                                                       \n"
         "  tell current terminal to split                                                          \n"
         "  tell current terminal to split direction \"vertical\"                                   \n"
         "  tell current terminal to split direction \"horizontal\"                                 \n"
         "  tell current terminal to split direction \"vertical\" profile \"Default\"               \n"
         "  tell current terminal to split direction \"horizontal\" profile \"Default\"             \n"
         "  set newSessionCount to (count of (sessions of current terminal))                        \n"
         " -- cleanup, close 6 sessions (so iTerm does not prompt to exit and quit application      \n"
         "  tell current terminal                                                                   \n"
         "      repeat 6 times                                                                      \n"
         "          tell current session to terminate                                               \n"
         "      end repeat                                                                          \n"
         "  end tell                                                                                \n"
         "  quit                                                                                    \n"
         "end tell                                                                                  \n"
         "{oldSessionCount, newSessionCount}                                                        \n",
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
}

@end
