//
//  AppleScriptTest.m
//  iTerm
//
//  Created by Alberto Miguel Pose on 28/12/13.
//
//

#import "AppleScriptTest.h"

#import <AppKit/NSWorkspace.h>
#import <ScriptingBridge/ScriptingBridge.h>
#import "iTermTests.h"
#import "iTerm2GeneratedScriptingBridge.h"
#import "NSStringITerm.h"

static NSString *const kTestAppName = @"iTerm2ForApplescriptTesting.app";
static NSString *const kTestBundleId = @"com.googlecode.iterm2.applescript";

@implementation AppleScriptTest

- (NSURL *)appUrl {
    return [NSURL fileURLWithPath:[@"./" stringByAppendingString:kTestAppName]];
}

- (void)setup {
    // ------ Arrange ------
    NSURL *appURL = [self appUrl];
    NSWorkspace *sharedWorkspace = [NSWorkspace sharedWorkspace];

    [self killTestApp];

    // Nuke its prefs
    NSString *defaultsDelete = [NSString stringWithFormat:@"defaults delete %@", kTestBundleId];
    system([defaultsDelete UTF8String]);

    // Start it up fresh
    BOOL isRunning = [sharedWorkspace launchApplication:[appURL path]];
    assert(isRunning);
}

- (void)teardown {
    [self killTestApp];
}

- (NSArray *)processIdsForTestApp {
    NSMutableArray *array = [NSMutableArray array];
    for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if ([app.bundleIdentifier isEqualToString:kTestBundleId]) {
            [array addObject:@(app.processIdentifier)];
        }
    }
    return array;
}

- (void)killTestApp {
    // Find all running instances of iTerm2ForApplescriptTesting
    NSArray *pids = [self processIdsForTestApp];

    // Kill them.
    pid_t thePid = 0;
    for (NSNumber *n in pids) {
        kill([n intValue], SIGKILL);
        thePid = [n intValue];
    }

    // Wait for it to die
    if (thePid) {
        BOOL running = NO;
        do {
            running = NO;
            int rc = kill(thePid, 0);
            if (rc && errno == ESRCH) {
                running = NO;
            } else {
                running = YES;
                usleep(100000);
            }
        } while (running);
    } else {
        // For some reason the scripting bridge test produces an app that doesn't show up in
        // runningApplications.
        system("killall -9 iTerm2ForApplescriptTesting");
    }
}

- (NSString *)scriptWithCommands:(NSArray *)commands outputs:(NSArray *)outputs {
    NSURL *appURL = [self appUrl];
    return [NSString stringWithFormat:
            @"tell application \"%@\"\n"
            @"  activate\n"
            @"  %@\n"
            @"end tell\n"
            @"{%@}\n",
            [appURL path],
            [commands componentsJoinedByString:@"\n"],
            outputs ? [outputs componentsJoinedByString:@", "] : 0];
}

- (NSAppleEventDescriptor *)runScript:(NSString *)script {
    NSAppleScript *appleScript = [[[NSAppleScript alloc] initWithSource:script] autorelease];
    NSDictionary *errorInfo = NULL;
    NSAppleEventDescriptor *eventDescriptor = [appleScript executeAndReturnError:&errorInfo];
    if (errorInfo) {
        NSLog(@"Script:\n%@\n\nFailed with error:\n%@",
              script, errorInfo);
        assert(false);
    }
    return eventDescriptor;
}

- (void)testScriptingBridge {
    iTerm2Application *iterm = [SBApplication applicationWithBundleIdentifier:kTestBundleId];
    [iterm activate];
    [iterm createWindowWithDefaultProfileCommand:nil];
    iTerm2Window *terminal = [iterm currentWindow];
    [terminal.currentSession writeContentsOfFile:nil text:@"echo Testing123" newline:NO];
    for (int i = 0; i < 10; i++) {
        NSString *contents = [terminal.currentSession text];
        if ([contents containsString:@"Testing123"]) {
            return;
        }
        usleep(200000);
    }
    assert(false);
}

- (void)testCreateWindowWithDefaultProfile {
    NSArray *commands = @[ @"set oldWindowCount to (count of windows)",
                           @"create window with default profile",
                           @"set newWindowCount to (count of windows)" ];
    NSArray *outputs = @[ @"oldWindowCount", @"newWindowCount" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    assert(eventDescriptor);

    assert([[eventDescriptor descriptorAtIndex:2] int32Value] == [[eventDescriptor descriptorAtIndex:1] int32Value] + 1);
}

- (void)testCreateWindowWithNamedProfile {
    NSArray *commands = @[ @"set oldWindowCount to (count of windows)",
                           @"create window with profile \"Default\"",
                           @"set newWindowCount to (count of windows)" ];
    NSArray *outputs = @[ @"oldWindowCount", @"newWindowCount" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    assert(eventDescriptor);

    assert([[eventDescriptor descriptorAtIndex:1] int32Value] == 0);
    assert([[eventDescriptor descriptorAtIndex:2] int32Value] == 1);
}

- (void)testCreateWindowWithDefaultProfileAndCommand {
    NSArray *commands = @[ @"create window with default profile command \"touch /tmp/rancommand\"" ];
    unlink("/tmp/rancommand");
    NSString *script = [self scriptWithCommands:commands
                                        outputs:nil];
    [self runScript:script];

    // Wait for the command to finish running. It gets half a second.
    BOOL ok = NO;
    for (int i = 0; i < 5; i++) {
        ok = [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/rancommand"];
        if (!ok) {
            usleep(100000);
        }
    }
    assert(ok);
}

- (void)testSelectWindow {
    // Beccause windows are ordered by their z-position, the first window is
    // the most recently created one. In the past, there was a "terminal
    // windows" property that was ordered by creation time.
    NSArray *commands = @[ @"create window with default profile",
                           @"tell current session of current window",
                           @"  write text \"echo NUMBER ONE\"",
                           @"end tell",
                           @"create window with default profile",
                           @"tell current session of current window",
                           @"  write text \"echo NUMBER TWO\"",
                           @"end tell",
                           @"delay 0.2",  // Give write text time to echo result back
                           @"set secondWindowContents to (text of current session of current window)",
                           @"select second window",
                           @"set firstWindowContents to (text of current session of current window)" ];
    NSArray *outputs = @[ @"firstWindowContents", @"secondWindowContents" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    NSString *firstWindowContents = [[eventDescriptor descriptorAtIndex:1] stringValue];
    NSString *secondWindowContents = [[eventDescriptor descriptorAtIndex:2] stringValue];

    assert([firstWindowContents containsString:@"NUMBER ONE"]);
    assert([secondWindowContents containsString:@"NUMBER TWO"]);
}

- (void)testSelectTab {
    NSArray *commands = @[ @"create window with default profile",
                           @"tell current session of current window",
                           @"  write text \"echo NUMBER ONE\"",
                           @"end tell",
                           @"tell current window",
                           @"  create tab with default profile",
                           @"end tell",
                           @"tell current session of current window",
                           @"  write text \"echo NUMBER TWO\"",
                           @"end tell",
                           @"delay 0.2",  // Give write text time to echo result back
                           @"set secondTabContents to (text of current session of current window)",
                           @"tell first tab of current window",
                           @"  select",
                           @"end tell",
                           @"set firstTabContents to (text of current session of current window)" ];
    NSArray *outputs = @[ @"firstTabContents", @"secondTabContents" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    NSString *firstTabContents = [[eventDescriptor descriptorAtIndex:1] stringValue];
    NSString *secondTabContents = [[eventDescriptor descriptorAtIndex:2] stringValue];

    assert([firstTabContents containsString:@"NUMBER ONE"]);
    assert([secondTabContents containsString:@"NUMBER TWO"]);
}

- (void)testSelectSession {
    NSArray *commands = @[ @"create window with default profile",
                           @"tell current session of current window",
                           @"  write text \"echo NUMBER ONE\"",
                           @"end tell",
                           @"tell current session of current tab of current window",
                           @"  split horizontally with default profile",
                           @"end tell",
                           @"tell current session of current window",
                           @"  write text \"echo NUMBER TWO\"",
                           @"end tell",
                           @"delay 0.2",  // Give write text time to echo result back
                           @"set secondSessionContents to (text of current session of current window)",
                           @"tell first session of current tab of current window",
                           @"  select",
                           @"end tell",
                           @"set firstSessionContents to (text of current session of current window)" ];
    NSArray *outputs = @[ @"firstSessionContents", @"secondSessionContents" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    NSString *firstSessionContents = [[eventDescriptor descriptorAtIndex:1] stringValue];
    NSString *secondSessionContents = [[eventDescriptor descriptorAtIndex:2] stringValue];

    assert([firstSessionContents containsString:@"NUMBER ONE"]);
    assert([secondSessionContents containsString:@"NUMBER TWO"]);
}

- (void)testSplitHorizontallyWithDefaultProfile {
    NSArray *commands = @[ @"create window with profile \"Default\"",
                           @"set oldSessionCount to (count of sessions in first tab in first window)",
                           @"tell current session of current window",
                           @"  split horizontally with default profile",
                           @"end tell",
                           @"set newSessionCount to (count of sessions in first tab in first window)" ];
    NSArray *outputs = @[ @"oldSessionCount", @"newSessionCount" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    assert(eventDescriptor);

    assert([[eventDescriptor descriptorAtIndex:1] int32Value] == 1);
    assert([[eventDescriptor descriptorAtIndex:2] int32Value] == 2);
}

- (void)testSplitVerticallyWithDefaultProfile {
    NSArray *commands = @[ @"create window with profile \"Default\"",
                           @"set oldSessionCount to (count of sessions in first tab in first window)",
                           @"tell current session of current window",
                           @"  split vertically with default profile",
                           @"end tell",
                           @"set newSessionCount to (count of sessions in first tab in first window)" ];
    NSArray *outputs = @[ @"oldSessionCount", @"newSessionCount" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    assert(eventDescriptor);

    assert([[eventDescriptor descriptorAtIndex:1] int32Value] == 1);
    assert([[eventDescriptor descriptorAtIndex:2] int32Value] == 2);
}

- (void)testCreateTabWithDefaultProfile {
    NSArray *commands = @[ @"create window with default profile",
                           @"set oldTabCount to (count of tabs in first window)",
                           @"tell current window",
                           @"  create tab with default profile",
                           @"end tell",
                           @"set newTabCount to (count of tabs in first window)" ];
    NSArray *outputs = @[ @"oldTabCount", @"newTabCount" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    assert(eventDescriptor);

    assert([[eventDescriptor descriptorAtIndex:1] int32Value] == 1);
    assert([[eventDescriptor descriptorAtIndex:2] int32Value] == 2);
}

- (void)testCreateTabWithNamedProfile {
    NSArray *commands = @[ @"create window with default profile",
                           @"set oldTabCount to (count of tabs in first window)",
                           @"tell current window",
                           @"  create tab with profile \"Default\"",
                           @"end tell",
                           @"set newTabCount to (count of tabs in first window)" ];
    NSArray *outputs = @[ @"oldTabCount", @"newTabCount" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    assert(eventDescriptor);

    assert([[eventDescriptor descriptorAtIndex:1] int32Value] == 1);
    assert([[eventDescriptor descriptorAtIndex:2] int32Value] == 2);
}

- (void)testResizeSession {
    NSArray *commands = @[ @"create window with default profile",
                           @"set oldRows to (rows in current session of current window)",
                           @"set oldColumns to (columns in current session of current window)",
                           @"tell current session of current window",
                           @"  set rows to 20",
                           @"  set columns to 30",
                           @"end tell",
                           @"set newRows to (rows in current session of current window)",
                           @"set newColumns to (columns in current session of current window)" ];

    NSArray *outputs = @[ @"oldRows", @"oldColumns", @"newRows", @"newColumns" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    assert(eventDescriptor);

    assert([[eventDescriptor descriptorAtIndex:1] int32Value] == 25);
    assert([[eventDescriptor descriptorAtIndex:2] int32Value] == 80);
    assert([[eventDescriptor descriptorAtIndex:3] int32Value] == 20);
    assert([[eventDescriptor descriptorAtIndex:4] int32Value] == 30);
}

- (void)testWriteContentsOfFile {
    NSString *helloWorld = @"Hello world";
    [helloWorld writeToFile:@"/tmp/testFile"
                 atomically:NO
                   encoding:NSUTF8StringEncoding
                      error:NULL];

    NSArray *commands = @[ @"create window with default profile",
                           @"tell current session of current window",
                           @"delay 0.2",  // Wait for prompt to finish being written
                           @"  write text \"cat > /dev/null\"",
                           @"  write contents of file \"/tmp/testFile\"",
                           @"end tell",
                           @"delay 0.2",  // Give write text time to echo result back
                           @"set sessionContents to (text of current session of current window)" ];
    NSArray *outputs = @[ @"sessionContents" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    NSString *contents = [[eventDescriptor descriptorAtIndex:1] stringValue];

    assert([contents containsString:helloWorld]);
}

- (void)testTty {
    NSArray *commands = @[ @"create window with default profile",
                           @"set ttyName to (tty of current session of current window)" ];
    NSArray *outputs = @[ @"ttyName" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    NSString *contents = [[eventDescriptor descriptorAtIndex:1] stringValue];

    assert([contents hasPrefix:@"/dev/ttys"]);
}

- (void)testUniqueId {
    NSArray *commands = @[ @"create window with default profile",
                           @"create window with default profile",
                           @"set firstUniqueId to (unique ID of current session of first window)",
                           @"set secondUniqueId to (unique ID of current session of second window)" ];
    NSArray *outputs = @[ @"firstUniqueId", @"secondUniqueId" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    NSString *uid1 = [[eventDescriptor descriptorAtIndex:1] stringValue];
    NSString *uid2 = [[eventDescriptor descriptorAtIndex:2] stringValue];
    assert(uid1.length > 0);
    assert(uid2.length > 0);
    assert(![uid1 isEqualToString:uid2]);
}

- (void)testSetGetColors {
    NSArray *colors = @[ @"foreground color",
                         @"background color",
                         @"bold color",
                         @"cursor color",
                         @"cursor text color",
                         @"selected text color",
                         @"selection color",
                         @"ANSI black color",
                         @"ANSI red color",
                         @"ANSI green color",
                         @"ANSI yellow color",
                         @"ANSI blue color",
                         @"ANSI magenta color",
                         @"ANSI cyan color",
                         @"ANSI white color",
                         @"ANSI bright black color",
                         @"ANSI bright red color",
                         @"ANSI bright green color",
                         @"ANSI bright yellow color",
                         @"ANSI bright blue color",
                         @"ANSI bright magenta color",
                         @"ANSI bright cyan color",
                         @"ANSI bright white color" ];
    NSMutableArray *commands = [NSMutableArray arrayWithArray:@[ @"create window with default profile",
                                                                 @"tell current session of current window" ]];
    NSMutableArray *outputs = [NSMutableArray array];
    for (NSString *color in colors) {
        NSString *name = [color stringByReplacingOccurrencesOfString:@" " withString:@""];
        [commands addObject:[NSString stringWithFormat:@"set old%@ to %@", name, color]];
        [commands addObject:[NSString stringWithFormat:@"set %@ to {65535, 0, 0, 0}", color]];
        [commands addObject:[NSString stringWithFormat:@"set new%@ to %@", name, color]];
        [outputs addObject:[NSString stringWithFormat:@"old%@", name]];
        [outputs addObject:[NSString stringWithFormat:@"new%@", name]];
    }

    [commands addObject:@"end tell"];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];

    int i = 1;
    for (NSString *name in outputs) {
        NSString *value = [NSString stringWithFormat:@"{%d, %d, %d, %d}",
                           [[[eventDescriptor descriptorAtIndex:i] descriptorAtIndex:1] int32Value],
                           [[[eventDescriptor descriptorAtIndex:i] descriptorAtIndex:2] int32Value],
                           [[[eventDescriptor descriptorAtIndex:i] descriptorAtIndex:3] int32Value],
                           [[[eventDescriptor descriptorAtIndex:i] descriptorAtIndex:4] int32Value]];

        if ([name hasPrefix:@"old"]) {
            assert(![value isEqualToString:@"{65535, 0, 0, 0}"]);
        } else {
            assert([value isEqualToString:@"{65535, 0, 0, 0}"]);
        }
        i++;
    }
}

- (void)testSetGetName {
    NSArray *commands = @[ @"create window with default profile",
                           @"set oldName to name of current session of current window",
                           @"tell current session of current window",
                           @"  set name to \"Testing\"",
                           @"end tell",
                           @"set newName to name of current session of current window" ];
    NSArray *outputs = @[ @"oldName", @"newName" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    NSString *oldName = [[eventDescriptor descriptorAtIndex:1] stringValue];
    NSString *newName = [[eventDescriptor descriptorAtIndex:2] stringValue];
    assert(![oldName isEqualToString:newName]);
    assert([newName isEqualToString:@"Testing"]);
}

- (void)testIsAtShellPrompt {
    NSArray *commands = @[ @"create window with default profile",
                           @"delay 0.5",
                           @"tell current session of current window",
                           @"  set beforeSleep to (is at shell prompt)",
                           @"  write text \"cat\"",
                           @"  delay 0.2",
                           @"  set afterSleep to (is at shell prompt)",
                           @"end tell" ];
    NSArray *outputs = @[ @"beforeSleep", @"afterSleep" ];
    NSString *script = [self scriptWithCommands:commands
                                        outputs:outputs];
    NSAppleEventDescriptor *eventDescriptor = [self runScript:script];
    BOOL beforeSleep = [[eventDescriptor descriptorAtIndex:1] booleanValue];
    BOOL afterSleep = [[eventDescriptor descriptorAtIndex:2] booleanValue];

    // This test will fail if shell integration is not installed
    assert(beforeSleep);
    assert(!afterSleep);
}

@end
