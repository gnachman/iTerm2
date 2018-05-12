/*
 **  iTermController.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the main application delegate and handles the addressbook functions.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "iTermController.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermBuriedSessions.h"
#import "iTermHotKeyController.h"
#import "iTermWebSocketCookieJar.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "NSWindow+iTerm.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PasteboardHistory.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYWindow.h"
#import "UKCrashReporter.h"
#import "VT100Screen.h"
#import "WindowArrangements.h"
#import "iTerm.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermExpose.h"
#import "iTermFullScreenWindowManager.h"
#import "iTermNotificationController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermRestorableSession.h"
#import "iTermSystemVersion.h"
#import "iTermWarning.h"
#import "PTYWindow.h"
#include <objc/runtime.h>

@interface NSApplication (Undocumented)
- (void)_cycleWindowsReversed:(BOOL)back;
@end

// Pref keys
static NSString *const kSelectionRespectsSoftBoundariesKey = @"Selection Respects Soft Boundaries";
static iTermController *gSharedInstance;

@implementation iTermController {
    NSMutableArray *_restorableSessions;
    NSMutableArray *_currentRestorableSessionsStack;

    NSMutableArray<PseudoTerminal *> *_terminalWindows;
    PseudoTerminal *_frontTerminalWindowController;
    iTermFullScreenWindowManager *_fullScreenWindowManager;
    BOOL _willPowerOff;
    BOOL _arrangeHorizontallyPendingFullScreenTransitions;
}

+ (iTermController *)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSharedInstance = [[iTermController alloc] init];
    });

    return gSharedInstance;
}

+ (void)releaseSharedInstance {
    [gSharedInstance release];
    gSharedInstance = nil;
}

+ (NSString *)installationId {
    NSString *const kInstallationIdKey = @"NoSyncInstallationId";
    NSString *installationId = [[NSUserDefaults standardUserDefaults] stringForKey:kInstallationIdKey];
    if (!installationId) {
        installationId = [NSString uuid];
        [[NSUserDefaults standardUserDefaults] setObject:installationId forKey:kInstallationIdKey];
    }
    return installationId;
}

+ (NSUInteger)shard {
    static const NSUInteger kNumberOfShards = 100;
    NSString *installationId = [iTermController installationId];
    return [installationId hashWithDJB2] % kNumberOfShards;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        UKCrashReporterCheckForCrash();

        // create the "~/Library/Application Support/iTerm2" directory if it does not exist
        [[NSFileManager defaultManager] applicationSupportDirectory];

        _terminalWindows = [[NSMutableArray alloc] init];
        _restorableSessions = [[NSMutableArray alloc] init];
        _currentRestorableSessionsStack = [[NSMutableArray alloc] init];
        // Activate Growl. This loads the Growl framework and initializes it.
        [iTermNotificationController sharedInstance];

        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(workspaceWillPowerOff:)
                                                                   name:NSWorkspaceWillPowerOffNotification
                                                                 object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidExitFullScreen:)
                                                     name:NSWindowDidExitFullScreenNotification
                                                   object:nil];
    }

    return (self);
}

- (void)migrateApplicationSupportDirectoryIfNeeded {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *modern = [fileManager applicationSupportDirectory];
    NSString *legacy = [fileManager legacyApplicationSupportDirectory];

    if ([fileManager itemIsSymlink:legacy]) {
        // Looks migrated, or crazy and impossible to reason about.
        return;
    }

    if ([fileManager itemIsDirectory:modern] && [fileManager itemIsDirectory:legacy]) {
        // This is the normal code path for migrating users.
        const BOOL legacyEmpty = [fileManager directoryEmpty:legacy];

        if (legacyEmpty) {
            [fileManager removeItemAtPath:legacy error:nil];
            [fileManager createSymbolicLinkAtPath:legacy withDestinationPath:modern error:nil];
            return;
        }

        const BOOL modernEmpty = [fileManager directoryEmpty:modern];
        if (modernEmpty) {
            [fileManager removeItemAtPath:modern error:nil];
            [fileManager moveItemAtPath:legacy toPath:modern error:nil];
            [fileManager createSymbolicLinkAtPath:legacy withDestinationPath:modern error:nil];
            return;
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Manual Update Needed";
        alert.informativeText = @"iTerm2's Application Support directory has changed.\n\n"
            @"Previously, both ~/Library/Application Support/iTerm and ~/Library/Application Support/iTerm2 were supported.\n\n"
            @"Now, only the iTerm2 version is supported. But you have files in both so please move everything from iTerm to iTerm2.";
        [alert addButtonWithTitle:@"Open in Finder"];
        [alert addButtonWithTitle:@"I Fixed It"];
        [alert addButtonWithTitle:@"Not Now"];
        switch ([alert runModal]) {
            case NSAlertFirstButtonReturn:
                [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:legacy],
                                                                              [NSURL fileURLWithPath:modern] ]];
                [self migrateApplicationSupportDirectoryIfNeeded];
                break;

            case NSAlertThirdButtonReturn:
                return;

            default:
                [self migrateApplicationSupportDirectoryIfNeeded];
                break;
        }
    }
}

- (BOOL)willRestoreWindowsAtNextLaunch {
  return (![iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup] &&
          ![iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup] &&
          [[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"]);
}

- (BOOL)shouldLeaveSessionsRunningOnQuit {
    if (_willPowerOff) {
        // For issue 4147.
        return NO;
    }
    const BOOL sessionsWillRestore = ([iTermAdvancedSettingsModel runJobsInServers] &&
                                      [iTermAdvancedSettingsModel restoreWindowContents] &&
                                      self.willRestoreWindowsAtNextLaunch);
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    return (sessionsWillRestore &&
            (itad.sparkleRestarting || ![iTermAdvancedSettingsModel killJobsInServersOnQuit]));
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // Save hotkey window arrangement to user defaults before closing it.
    [[iTermHotKeyController sharedInstance] saveHotkeyWindowStates];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];

    if (self.shouldLeaveSessionsRunningOnQuit) {
        // We don't want to kill running jobs. This can be for one of two reasons:
        //
        // 1. Sparkle is restarting the app. Because jobs are run in servers and window
        //    restoration is on, we don't want to close term windows because that will
        //    send SIGHUP to the job processes. Normally this path is taken during
        //    a user-initiated quit, so we want the jobs killed, but not in this case.
        // 2. The user has set a pref to not kill jobs on quit.
        //
        // In either case, we only get here if we're pretty sure everything will get restored
        // nicely.
        [_terminalWindows autorelease];
    } else {
        // Close all terminal windows, killing jobs.
        while ([_terminalWindows count] > 0) {
            [[_terminalWindows objectAtIndex:0] close];
        }
        NSAssert([_terminalWindows count] == 0, @"Expected terminals to be gone");
        [_terminalWindows release];
    }

    [_restorableSessions release];
    [_currentRestorableSessionsStack release];
    [_fullScreenWindowManager release];
    [_lastSelection release];
    [super dealloc];
}

- (PseudoTerminal*)keyTerminalWindow {
    for (PseudoTerminal *pty in [self terminals]) {
        if ([[pty window] isKeyWindow]) {
            return pty;
        }
    }
    return nil;
}

- (void)updateWindowTitles {
    for (PseudoTerminal *terminal in _terminalWindows) {
        if ([terminal currentSessionName]) {
            [terminal setWindowTitle];
        }
    }
}

- (BOOL)haveTmuxConnection {
    return [self anyTmuxSession] != nil;
}

- (PTYSession *)anyTmuxSession {
    for (PseudoTerminal *terminal in _terminalWindows) {
        for (PTYSession *session in [terminal allSessions]) {
            if ([session isTmuxClient] || [session isTmuxGateway]) {
                return session;
            }
        }
    }
    for (PTYSession *session in [[iTermBuriedSessions sharedInstance] buriedSessions]) {
        if ([session isTmuxClient] || [session isTmuxGateway]) {
            return session;
        }
    }
    return nil;
}

// Action methods
- (IBAction)newWindow:(id)sender {
    [self newWindow:sender possiblyTmux:NO];
}

- (void)newWindow:(id)sender possiblyTmux:(BOOL)possiblyTmux {
    DLog(@"newWindow:%@ posiblyTmux:%@", sender, @(possiblyTmux));
    if (possiblyTmux &&
        _frontTerminalWindowController &&
        [[_frontTerminalWindowController currentSession] isTmuxClient]) {
        DLog(@"Creating a new tmux window");
        [_frontTerminalWindowController newTmuxWindow:sender];
    } else {
        [self launchBookmark:nil inTerminal:nil];
    }
}

- (void)newSessionInTabAtIndex:(id)sender {
    Profile *bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self launchBookmark:bookmark inTerminal:_frontTerminalWindowController];
    }
}

- (BOOL)terminalIsObscured:(id<iTermWindowController>)terminal {
    BOOL windowIsObscured = NO;
    NSWindow *window = [terminal window];
    NSWindowOcclusionState occlusionState = window.occlusionState;
    // The occlusionState tells if you if you're on another space or another app's window is
    // occluding yours, but for some reason one terminal window can occlude another without
    // it noticing, so we compute that ourselves.
    windowIsObscured = !(occlusionState & NSWindowOcclusionStateVisible);
    if (!windowIsObscured) {
        // Try to refine the guess by seeing if another terminal is covering this one.
        static const double kOcclusionThreshold = 0.4;
        if ([(iTermTerminalWindow *)terminal.window approximateFractionOccluded] > kOcclusionThreshold) {
            windowIsObscured = YES;
        }
    }
    return windowIsObscured;
}

- (void)newSessionInWindowAtIndex:(id)sender {
    Profile *bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self launchBookmark:bookmark inTerminal:nil];
    }
}

// meant for action for menu items that have a submenu
- (void)noAction:(id)sender {
}

- (void)newSessionWithSameProfile:(id)sender {
    Profile *bookmark = nil;
    if (_frontTerminalWindowController) {
        bookmark = [[_frontTerminalWindowController currentSession] profile];
    }
    [self launchBookmark:bookmark inTerminal:_frontTerminalWindowController];
}

// Launch a new session using the default profile. If the current session is
// tmux and possiblyTmux is true, open a new tmux session.
- (void)newSession:(id)sender possiblyTmux:(BOOL)possiblyTmux {
    DLog(@"newSession:%@ possiblyTmux:%d from %@",
         sender, (int)possiblyTmux, [NSThread callStackSymbols]);
    if (possiblyTmux &&
        _frontTerminalWindowController &&
        [[_frontTerminalWindowController currentSession] isTmuxClient]) {
        [_frontTerminalWindowController newTmuxTab:sender];
    } else {
        [self launchBookmark:nil inTerminal:_frontTerminalWindowController];
    }
}

- (NSArray<PseudoTerminal *> *)terminalsSortedByNumber {
    return [_terminalWindows sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [@([obj1 number]) compare:@([obj2 number])];
    }];
}

- (void)previousTerminal {
    NSArray<PseudoTerminal *> *windows = [self terminalsSortedByNumber];
    if (windows.count < 2) {
        return;
    }
    NSUInteger index = [windows indexOfObject:_frontTerminalWindowController];
    if (index == NSNotFound) {
        DLog(@"Index of terminal not found, so cycle.");
        [NSApp _cycleWindowsReversed:YES];
    } else {
        NSInteger i = index;
        i += _terminalWindows.count - 1;
        [[windows[i % windows.count] window] makeKeyAndOrderFront:nil];
    }
}

- (void)nextTerminal {
    NSArray<PseudoTerminal *> *windows = [self terminalsSortedByNumber];
    if (windows.count < 2) {
        return;
    }
    NSUInteger index = [windows indexOfObject:_frontTerminalWindowController];
    if (index == NSNotFound) {
        DLog(@"Index of terminal not found, so cycle.");
        [NSApp _cycleWindowsReversed:NO];
    } else {
        NSUInteger i = index;
        i++;
        [[windows[i % windows.count] window] makeKeyAndOrderFront:nil];
    }
}

- (void)repairSavedArrangementNamed:(NSString *)savedArrangementName
               replacingMissingGUID:(NSString *)guidToReplace
                           withGUID:(NSString *)replacementGuid {
    NSArray *terminalArrangements = [WindowArrangements arrangementWithName:savedArrangementName];
    Profile *goodProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:replacementGuid];
    if (goodProfile) {
        NSMutableArray *repairedArrangements = [NSMutableArray array];
        for (NSDictionary *terminalArrangement in terminalArrangements) {
            [repairedArrangements addObject:[PseudoTerminal repairedArrangement:terminalArrangement
                                                       replacingProfileWithGUID:guidToReplace
                                                                    withProfile:goodProfile]];
        }
        [WindowArrangements setArrangement:repairedArrangements withName:savedArrangementName];
    }
}

- (void)saveWindowArrangement:(BOOL)allWindows {
    NSString *name = [WindowArrangements nameForNewArrangement];
    if (!name) {
        return;
    }
    [self saveWindowArrangmentForAllWindows:allWindows name:name];
}

- (void)saveWindowArrangmentForAllWindows:(BOOL)allWindows name:(NSString *)name {
    if (allWindows) {
        NSMutableArray *terminalArrangements = [NSMutableArray arrayWithCapacity:[_terminalWindows count]];
        for (PseudoTerminal *terminal in _terminalWindows) {
            NSDictionary *arrangement = [terminal arrangement];
            if (arrangement) {
                [terminalArrangements addObject:arrangement];
            }
        }
        if (terminalArrangements.count) {
            [WindowArrangements setArrangement:terminalArrangements withName:name];
        }
    } else {
        PseudoTerminal *currentTerminal = [self currentTerminal];
        if (!currentTerminal) {
            return;
        }
        [self saveWindowArrangementForWindow:currentTerminal name:name];
    }
}

- (void)saveWindowArrangementForWindow:(PseudoTerminal *)currentTerminal name:(NSString *)name {
    NSMutableArray *terminalArrangements = [NSMutableArray arrayWithCapacity:[_terminalWindows count]];
    NSDictionary *arrangement = [currentTerminal arrangement];
    if (arrangement) {
        [terminalArrangements addObject:arrangement];
    }
    if (terminalArrangements.count) {
        [WindowArrangements setArrangement:terminalArrangements withName:name];
    }
}

- (void)tryOpenArrangement:(NSDictionary *)terminalArrangement {
    [self tryOpenArrangement:terminalArrangement asTabsInWindow:nil];
}

- (void)tryOpenArrangement:(NSDictionary *)terminalArrangement asTabsInWindow:(PseudoTerminal *)term {
    if (term) {
        [term restoreTabsFromArrangement:terminalArrangement sessions:nil];
        return;
    }
    BOOL shouldDelay = NO;
    DLog(@"Try to open arrangement %p...", terminalArrangement);
    if ([PseudoTerminal willAutoFullScreenNewWindow] &&
        [PseudoTerminal anyWindowIsEnteringLionFullScreen]) {
        DLog(@"Prevented by autofullscreen + a window entering.");
        shouldDelay = YES;
    }
    if ([PseudoTerminal arrangementIsLionFullScreen:terminalArrangement] &&
        [PseudoTerminal anyWindowIsEnteringLionFullScreen]) {
        DLog(@"Prevented by fs arrangement + a window entering.");
        shouldDelay = YES;
    }
    if (shouldDelay) {
        DLog(@"Trying again in .25 sec");
        [self performSelector:_cmd withObject:terminalArrangement afterDelay:0.25];
    } else {
        DLog(@"Opening it.");
        PseudoTerminal *term = [PseudoTerminal terminalWithArrangement:terminalArrangement
                                              forceOpeningHotKeyWindow:NO];
        if (term) {
          [self addTerminalWindow:term];
        }
    }
}

- (BOOL)loadWindowArrangementWithName:(NSString *)theName asTabsInTerminal:(PseudoTerminal *)term {
    BOOL ok = NO;
    _savedArrangementNameBeingRestored = [[theName retain] autorelease];
    NSArray *terminalArrangements = [WindowArrangements arrangementWithName:theName];
    if (terminalArrangements) {
        for (NSDictionary *terminalArrangement in terminalArrangements) {
            [self tryOpenArrangement:terminalArrangement asTabsInWindow:term];
            ok = YES;
        }
    }
    _savedArrangementNameBeingRestored = nil;
    return ok;
}

- (void)loadWindowArrangementWithName:(NSString *)theName {
    [self loadWindowArrangementWithName:theName asTabsInTerminal:nil];
}

// Return all the terminals in the given screen.
- (NSArray*)terminalsInScreen:(NSScreen *)screen {
    NSMutableArray *result = [NSMutableArray array];
    for (PseudoTerminal *term in _terminalWindows) {
        if (![term isHotKeyWindow] &&
            [[term window] deepestScreen] == screen) {
            [result addObject:term];
        }
    }
    return result;
}

// Arrange terminals horizontally, in multiple rows if needed.
- (void)arrangeTerminals:(NSArray *)terminals inFrame:(NSRect)frame {
    if ([terminals count] == 0) {
        return;
    }

    // Determine the new width for all windows, not less than some minimum.
    int x = frame.origin.x;
    int w = frame.size.width / [terminals count];
    int minWidth = 400;
    for (PseudoTerminal *term in terminals) {
        int termMinWidth = [term minWidth];
        minWidth = MAX(minWidth, termMinWidth);
    }
    if (w < minWidth) {
        // Width would be too narrow. Pick the smallest width larger than minWidth
        // that evenly  divides the screen up horizontally.
        int maxWindowsInOneRow = floor(frame.size.width / minWidth);
        w = frame.size.width / maxWindowsInOneRow;
    }

    // Find the window whose top is nearest the top of the screen. That will be the
    // new top of all the windows in the first row.
    int highestTop = 0;
    for (PseudoTerminal *terminal in terminals) {
        NSRect r = [[terminal window] frame];
        if (r.origin.y < frame.origin.y) {
            // Bottom of window is below dock. Pretend its bottom abuts the dock.
            r.origin.y = frame.origin.y;
        }
        int top = r.origin.y + r.size.height;
        if (top > highestTop) {
            highestTop = top;
        }
    }

    // Ensure the bottom of the last row of windows will be above the bottom of the screen.
    int rows = ceil((w * [terminals count]) / frame.size.width);

    int maxHeight = frame.size.height / rows;

    if (rows > 1 && highestTop - maxHeight * rows < frame.origin.y) {
        highestTop = frame.origin.y + maxHeight * rows;
    }

    if (highestTop > frame.origin.y + frame.size.height) {
        // Don't let the top of the first row go above the top of the screen. This is just
        // paranoia.
        highestTop = frame.origin.y + frame.size.height;
    }

    int yOffset = 0;
    NSMutableArray *terminalsCopy = [NSMutableArray arrayWithArray:terminals];

    // Grab the window that would move the least and move it. This isn't a global
    // optimum, but it is reasonably stable.
    while ([terminalsCopy count] > 0) {
        // Find the leftmost terminal.
        PseudoTerminal* terminal = nil;
        int bestDistance = 0;
        int bestIndex = 0;

        for (int j = 0; j < [terminalsCopy count]; ++j) {
            PseudoTerminal *t = [terminalsCopy objectAtIndex:j];
            if (t) {
                NSRect r = [[t window] frame];
                int y = highestTop - r.size.height + yOffset;
                int dx = x - r.origin.x;
                int dy = y - r.origin.y;
                int distance = dx*dx + dy*dy;
                if (terminal == nil || distance < bestDistance) {
                    bestDistance = distance;
                    terminal = t;
                    bestIndex = j;
                }
            }
        }
        assert(terminal);

        // Remove it from terminalsCopy.
        [terminalsCopy removeObjectAtIndex:bestIndex];

        // Create an animation to move it to its new position.
        int y = highestTop - [[terminal window] frame].size.height;
        int h = MIN(maxHeight, [[terminal window] frame].size.height);
        if (rows > 1) {
            // The first row can be a bit ragged vertically but subsequent rows line up
            // at the tops of the windows.
            y = frame.origin.y + frame.size.height - h;
        }
        NSDictionary *dict = @{ NSViewAnimationTargetKey: [terminal window],
                                NSViewAnimationStartFrameKey: [NSValue valueWithRect:[[terminal window] frame]],
                                NSViewAnimationEndFrameKey: [NSValue valueWithRect:NSMakeRect(x,
                                                                                              y + yOffset,
                                                                                              w,
                                                                                              h)] };
        x += w;
        if (x > frame.size.width + frame.origin.x - w) {
            // Wrap around to the next row of windows.
            x = frame.origin.x;
            yOffset -= maxHeight;
        }
        NSViewAnimation *theAnim = [[[NSViewAnimation alloc] initWithViewAnimations:@[ dict ]] autorelease];

        // Set some additional attributes for the animation.
        [theAnim setDuration:0.75];
        [theAnim setAnimationCurve:NSAnimationEaseInOut];

        // Run the animation.
        [theAnim startAnimation];
    }
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
    DLog(@"Controller: window exited fullscreen");
    if (_arrangeHorizontallyPendingFullScreenTransitions &&
        [[iTermFullScreenWindowManager sharedInstance] numberOfQueuedTransitions] == 0) {
        _arrangeHorizontallyPendingFullScreenTransitions = NO;
        [self arrangeHorizontally];
    }
}

- (void)arrangeHorizontally {
    DLog(@"Arrange horizontally");
    [iTermExpose exitIfActive];

    // Un-full-screen each window. This is done in two steps because
    // toggleFullScreenMode deallocs self.
    for (PseudoTerminal *windowController in _terminalWindows) {
        if ([windowController anyFullScreen]) {
            if (windowController.window.isFullScreen) {
                // Lion fullscreen
                DLog(@"Enqueue window %@", windowController.window);
                _arrangeHorizontallyPendingFullScreenTransitions = YES;
                [[iTermFullScreenWindowManager sharedInstance] makeWindowExitFullScreen:windowController.ptyWindow];
            } else if (windowController.fullScreen) {
                // Traditional fullscreen
                DLog(@"Exit traditional fullscreen");
                [windowController toggleFullScreenMode:self];
            }
        }
    }
    if (_arrangeHorizontallyPendingFullScreenTransitions) {
        return;
    }

    DLog(@"Actually arranging");

    // For each screen, find the terminals in it and arrange them. This way
    // terminals don't move from screen to screen in this operation.
    for (NSScreen* screen in [NSScreen screens]) {
        [self arrangeTerminals:[self terminalsInScreen:screen]
                       inFrame:[screen visibleFrame]];
    }
    for (PseudoTerminal *t in _terminalWindows) {
        [[t window] orderFront:nil];
    }
}

- (PseudoTerminal *)currentTerminal {
    return _frontTerminalWindowController;
}

- (void)terminalWillClose:(PseudoTerminal*)theTerminalWindow {
    if (_frontTerminalWindowController == theTerminalWindow) {
        [self setCurrentTerminal:nil];
    }
    if (theTerminalWindow) {
        [self removeTerminalWindow:theTerminalWindow];
    }
}

- (void)_addBookmark:(Profile*)bookmark
              toMenu:(NSMenu*)aMenu
              target:(id)aTarget
       withShortcuts:(BOOL)withShortcuts
            selector:(SEL)selector
   alternateSelector:(SEL)alternateSelector {
    NSMenuItem *aMenuItem = [[NSMenuItem alloc] initWithTitle:[bookmark objectForKey:KEY_NAME]
                                                       action:selector
                                                keyEquivalent:@""];
    if (withShortcuts) {
        if ([bookmark objectForKey:KEY_SHORTCUT] != nil) {
            NSString* shortcut = [bookmark objectForKey:KEY_SHORTCUT];
            shortcut = [shortcut lowercaseString];
            [aMenuItem setKeyEquivalent:shortcut];
        }
    }

    unsigned int modifierMask = NSCommandKeyMask | NSControlKeyMask;
    [aMenuItem setKeyEquivalentModifierMask:modifierMask];
    [aMenuItem setRepresentedObject:[bookmark objectForKey:KEY_GUID]];
    [aMenuItem setTarget:aTarget];
    [aMenu addItem:aMenuItem];
    [aMenuItem release];

    if (alternateSelector) {
        aMenuItem = [[NSMenuItem alloc] initWithTitle:[bookmark objectForKey:KEY_NAME]
                                               action:alternateSelector
                                        keyEquivalent:@""];
        if (withShortcuts) {
            if ([bookmark objectForKey:KEY_SHORTCUT] != nil) {
                NSString* shortcut = [bookmark objectForKey:KEY_SHORTCUT];
                shortcut = [shortcut lowercaseString];
                [aMenuItem setKeyEquivalent:shortcut];
            }
        }

        modifierMask = NSCommandKeyMask | NSControlKeyMask;
        [aMenuItem setRepresentedObject:[bookmark objectForKey:KEY_GUID]];
        [aMenuItem setTarget:self];

        [aMenuItem setKeyEquivalentModifierMask:modifierMask | NSAlternateKeyMask];
        [aMenuItem setAlternate:YES];
        [aMenu addItem:aMenuItem];
        [aMenuItem release];
    }
}

- (void)_addBookmarksForTag:(NSString*)tag
                     toMenu:(NSMenu*)aMenu
                     target:(id)aTarget
              withShortcuts:(BOOL)withShortcuts
                   selector:(SEL)selector
          alternateSelector:(SEL)alternateSelector
            openAllSelector:(SEL)openAllSelector {
    NSMenuItem *aMenuItem = [[NSMenuItem alloc] initWithTitle:tag action:@selector(noAction:) keyEquivalent:@""];
    NSMenu *subMenu = [[[NSMenu alloc] init] autorelease];
    int count = 0;
    int MAX_MENU_ITEMS = 100;
    if ([tag isEqualToString:@"bonjour"]) {
        MAX_MENU_ITEMS = 50;
    }
    for (int i = 0; i < [[ProfileModel sharedInstance] numberOfBookmarks]; ++i) {
        Profile *bookmark = [[ProfileModel sharedInstance] profileAtIndex:i];
        NSArray *tags = [bookmark objectForKey:KEY_TAGS];
        for (int j = 0; j < [tags count]; ++j) {
            if ([tag localizedCaseInsensitiveCompare:[tags objectAtIndex:j]] == NSOrderedSame) {
                ++count;
                if (count <= MAX_MENU_ITEMS) {
                    [self _addBookmark:bookmark
                                toMenu:subMenu
                                target:aTarget
                         withShortcuts:withShortcuts
                              selector:selector
                     alternateSelector:alternateSelector];
                }
                break;
            }
        }
    }
    if ([[ProfileModel sharedInstance] numberOfBookmarks] > MAX_MENU_ITEMS) {
        int overflow = [[ProfileModel sharedInstance] numberOfBookmarks] - MAX_MENU_ITEMS;
        NSMenuItem* overflowItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"[%d profiles not shown]", overflow]
                                                           action:nil
                                                    keyEquivalent:@""];
        [subMenu addItem:overflowItem];
        [overflowItem release];
    }
    [aMenuItem setSubmenu:subMenu];
    [aMenuItem setTarget:self];
    [aMenu addItem:aMenuItem];
    [aMenuItem release];

    if (openAllSelector && count > 1) {
        [subMenu addItem:[NSMenuItem separatorItem]];
        aMenuItem = [[NSMenuItem alloc] initWithTitle:@"Open All"
                                               action:openAllSelector
                                        keyEquivalent:@""];
        unsigned int modifierMask = NSCommandKeyMask | NSControlKeyMask;
        [aMenuItem setKeyEquivalentModifierMask:modifierMask];
        [aMenuItem setRepresentedObject:subMenu];
        if ([self respondsToSelector:openAllSelector]) {
            [aMenuItem setTarget:self];
        } else {
            assert([aTarget respondsToSelector:openAllSelector]);
            [aMenuItem setTarget:aTarget];
        }
        [subMenu addItem:aMenuItem];
        [aMenuItem release];

        // Add alternate -------------------------------------------------------
        aMenuItem = [[NSMenuItem alloc] initWithTitle:@"Open All in New Window"
                                               action:openAllSelector
                                        keyEquivalent:@""];
        modifierMask = NSCommandKeyMask | NSControlKeyMask;
        [aMenuItem setAlternate:YES];
        [aMenuItem setKeyEquivalentModifierMask:modifierMask | NSAlternateKeyMask];
        [aMenuItem setRepresentedObject:subMenu];
        if ([self respondsToSelector:openAllSelector]) {
            [aMenuItem setTarget:self];
        } else {
            assert([aTarget respondsToSelector:openAllSelector]);
            [aMenuItem setTarget:aTarget];
        }
        [subMenu addItem:aMenuItem];
        [aMenuItem release];
    }
}

- (PseudoTerminal *)terminalWithTab:(PTYTab *)tab {
    for (PseudoTerminal *term in [self terminals]) {
        if ([[term tabs] containsObject:tab]) {
            return term;
        }
    }
    return nil;
}

- (PseudoTerminal *)terminalWithSession:(PTYSession *)session {
    for (PseudoTerminal *term in [self terminals]) {
        if ([[term allSessions] containsObject:session]) {
            return term;
        }
    }
    return nil;
}

- (BOOL)shouldOpenManyProfiles:(int)count {
    NSString *theTitle = [NSString stringWithFormat:@"You are about to open %d profiles.", count];
    iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:theTitle
                                   actions:@[ @"OK", @"Cancel" ]
                                identifier:@"AboutToOpenManyProfiles"
                               silenceable:kiTermWarningTypePermanentlySilenceable];
    switch (selection) {
        case kiTermWarningSelection0:
            return YES;

        case kiTermWarningSelection1:
            return NO;

        default:
            return YES;
    }
}

- (void)openNewSessionsFromMenu:(NSMenu *)theMenu inNewWindow:(BOOL)newWindow {
    NSArray *bookmarks = [self bookmarksInMenu:theMenu];
    static const int kWarningThreshold = 10;
    if ([bookmarks count] > kWarningThreshold) {
        if (![self shouldOpenManyProfiles:bookmarks.count]) {
            return;
        }
    }

    PseudoTerminal *term = newWindow ? nil : [self currentTerminal];
    for (Profile *bookmark in bookmarks) {
        if (!term) {
            PTYSession *session = [self launchBookmark:bookmark inTerminal:nil];
            if (session) {
                term = [self terminalWithSession:session];
            }
        } else {
            [self launchBookmark:bookmark inTerminal:term];
        }
    }
}

- (NSArray *)bookmarksInMenu:(NSMenu *)theMenu {
    NSMutableSet *usedGuids = [NSMutableSet set];
    NSMutableArray *bookmarks = [NSMutableArray array];
    [self getBookmarksInMenu:theMenu usedGuids:usedGuids bookmarks:bookmarks];
    return bookmarks;
}

// Recursively descends the menu, finding all bookmarks that aren't already in usedGuids (which
// should be empty when called from outside).
- (void)getBookmarksInMenu:(NSMenu *)parent
                 usedGuids:(NSMutableSet *)usedGuids
                 bookmarks:(NSMutableArray *)bookmarks {
    for (NSMenuItem *item in [parent itemArray]) {
        if (![item isSeparatorItem] && ![item submenu] && ![item isAlternate]) {
            NSString* guid = [item representedObject];
            Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
            if (bookmark) {
                if (![usedGuids containsObject:guid]) {
                    [usedGuids addObject:guid];
                    [bookmarks addObject:bookmark];
                }
            }
        } else if (![item isSeparatorItem] && [item submenu] && ![item isAlternate]) {
            NSMenu *sub = [item submenu];
            [self getBookmarksInMenu:sub
                           usedGuids:usedGuids
                           bookmarks:bookmarks];
        }
    }
}

- (void)newSessionsInWindow:(id)sender {
    [self openNewSessionsFromMenu:[sender menu] inNewWindow:[sender isAlternate]];
}

- (void)newSessionsInNewWindow:(id)sender {
    [self openNewSessionsFromMenu:[sender menu] inNewWindow:YES];
}

- (void)addBookmarksToMenu:(NSMenu *)aMenu
              withSelector:(SEL)selector
           openAllSelector:(SEL)openAllSelector
                startingAt:(int)startingAt {
    JournalParams params;
    params.selector = selector;
    params.openAllSelector = openAllSelector;
    params.alternateSelector = @selector(newSessionInWindowAtIndex:);
    params.alternateOpenAllSelector = @selector(newSessionsInWindow:);
    params.target = self;

    ProfileModel *bm = [ProfileModel sharedInstance];
    int N = [bm numberOfBookmarks];
    for (int i = 0; i < N; i++) {
        Profile *b = [bm profileAtIndex:i];
        [bm addBookmark:b
                 toMenu:aMenu
         startingAtItem:startingAt
               withTags:[b objectForKey:KEY_TAGS]
                 params:&params
                  atPos:i];
    }
}

- (void)irAdvance:(int)dir {
    [_frontTerminalWindowController irAdvance:dir];
}

+ (void)switchToSpaceInBookmark:(Profile *)aDict {
    if (aDict[KEY_SPACE]) {
        int spaceNum = [aDict[KEY_SPACE] intValue];
        if (spaceNum > 0 && spaceNum < 10) {
            // keycodes for digits 1-9. Send control-n to switch spaces.
            // TODO: This would get remapped by the event tap. It requires universal access to be on and
            // spaces to be configured properly. But we don't tell the users this.
            int codes[] = { 18, 19, 20, 21, 23, 22, 26, 28, 25 };
            CGEventRef e = CGEventCreateKeyboardEvent (NULL, (CGKeyCode)codes[spaceNum - 1], true);
            CGEventSetFlags(e, kCGEventFlagMaskControl);
            CGEventPost(kCGSessionEventTap, e);
            CFRelease(e);

            e = CGEventCreateKeyboardEvent (NULL, (CGKeyCode)codes[spaceNum - 1], false);
            CGEventSetFlags(e, kCGEventFlagMaskControl);
            CGEventPost(kCGSessionEventTap, e);
            CFRelease(e);

            // Give the space-switching animation time to get started; otherwise a window opened
            // subsequent to this will appear in the previous space. This is short enough of a
            // delay that it's not annoying when you're already there.
            [NSThread sleepForTimeInterval:0.3];

            [NSApp activateIgnoringOtherApps:YES];
        }
    }
}

- (iTermWindowType)windowTypeForBookmark:(Profile *)aDict {
    if ([aDict objectForKey:KEY_WINDOW_TYPE]) {
        int windowType = [[aDict objectForKey:KEY_WINDOW_TYPE] intValue];
        if (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN &&
            [iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscren]) {
            return WINDOW_TYPE_LION_FULL_SCREEN;
        } else {
            return windowType;
        }
    } else {
        return WINDOW_TYPE_NORMAL;
    }
}

- (void)reloadAllBookmarks {
    int n = [self numberOfTerminals];
    for (int i = 0; i < n; ++i) {
        PseudoTerminal* pty = [self terminalAtIndex:i];
        [pty reloadBookmarks];
    }
}


- (Profile *)defaultBookmark {
    Profile *aDict = [[ProfileModel sharedInstance] defaultBookmark];
    if (!aDict) {
        NSMutableDictionary *temp = [[[NSMutableDictionary alloc] init] autorelease];
        [ITAddressBookMgr setDefaultsInBookmark:temp];
        [temp setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        aDict = temp;
    }
    return aDict;
}

- (PseudoTerminal *)openTmuxIntegrationWindowUsingProfile:(Profile *)profile {
    [iTermController switchToSpaceInBookmark:profile];
    iTermWindowType windowType;
    if ([iTermAdvancedSettingsModel serializeOpeningMultipleFullScreenWindows]) {
        windowType = [self windowTypeForBookmark:profile];
    } else {
        windowType = [iTermProfilePreferences intForKey:KEY_WINDOW_TYPE inProfile:profile];
    }
    PseudoTerminal *term =
        [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                          windowType:windowType
                                     savedWindowType:WINDOW_TYPE_NORMAL
                                              screen:[iTermProfilePreferences intForKey:KEY_SCREEN inProfile:profile]
                                    hotkeyWindowType:iTermHotkeyWindowTypeNone] autorelease];
    if ([iTermProfilePreferences boolForKey:KEY_HIDE_AFTER_OPENING inProfile:profile]) {
        [term hideAfterOpening];
    }
    iTermProfileHotKey *profileHotKey =
        [[iTermHotKeyController sharedInstance] didCreateWindowController:term
                                                              withProfile:profile
                                                                     show:NO];
    [profileHotKey setAllowsStateRestoration:NO];

    [self addTerminalWindow:term];
    return term;
}

- (void)didFinishCreatingTmuxWindow:(PseudoTerminal *)windowController {
    [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:windowController] showHotKeyWindow];
}

- (void)makeTerminalWindowFullScreen:(NSWindowController<iTermWindowController> *)term {
    [[iTermFullScreenWindowManager sharedInstance] makeWindowEnterFullScreen:term.ptyWindow];
}

- (PTYSession *)launchBookmark:(NSDictionary *)bookmarkData inTerminal:(PseudoTerminal *)theTerm {
    return [self launchBookmark:bookmarkData
                     inTerminal:theTerm
                        withURL:nil
                       hotkeyWindowType:iTermHotkeyWindowTypeNone
                        makeKey:YES
                    canActivate:YES
                        command:nil
                          block:nil];
}

- (NSDictionary *)profile:(NSDictionary *)aDict
        modifiedToOpenURL:(NSString *)url
            forObjectType:(iTermObjectType)objectType {
    if (aDict == nil ||
        [[ITAddressBookMgr bookmarkCommand:aDict
                             forObjectType:objectType] isEqualToString:@"$$"] ||
        ![[aDict objectForKey:KEY_CUSTOM_COMMAND] isEqualToString:@"Yes"]) {
        Profile* prototype = aDict;
        if (!prototype) {
            prototype = [self defaultBookmark];
        }

        NSMutableDictionary *tempDict = [NSMutableDictionary dictionaryWithDictionary:prototype];
        NSURL *urlRep = [NSURL URLWithString:url];
        NSString *urlType = [urlRep scheme];

        if ([urlType compare:@"ssh" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithString:@"ssh "];
            NSString *username = [urlRep user];
            if (username) {
                NSMutableCharacterSet *legalCharacters = [NSMutableCharacterSet alphanumericCharacterSet];
                [legalCharacters addCharactersInString:@"_-+."];
                NSCharacterSet *illegalCharacters = [legalCharacters invertedSet];
                NSRange range = [username rangeOfCharacterFromSet:illegalCharacters];
                if (range.location != NSNotFound) {
                    ELog(@"username %@ contains illegal character at position %@", username, @(range.location));
                    return nil;
                }
                [tempString appendFormat:@"-l %@ ", [[urlRep user] stringWithEscapedShellCharactersIncludingNewlines:YES]];
            }
            if ([urlRep port]) {
                [tempString appendFormat:@"-p %@ ", [urlRep port]];
            }
            NSString *hostname = [urlRep host];
            if (hostname) {
                NSCharacterSet *legalCharacters = [NSCharacterSet characterSetWithCharactersInString:@":abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-."];
                NSCharacterSet *illegalCharacters = [legalCharacters invertedSet];
                NSRange range = [hostname rangeOfCharacterFromSet:illegalCharacters];
                if (range.location != NSNotFound) {
                    ELog(@"Hostname %@ contains illegal character at position %@", hostname, @(range.location));
                    return nil;
                }
                [tempString appendString:[hostname stringWithEscapedShellCharactersIncludingNewlines:YES]];
            }
            [tempDict setObject:tempString forKey:KEY_COMMAND_LINE];
            [tempDict setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
            aDict = tempDict;
        } else if ([urlType compare:@"ftp" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithFormat:@"ftp %@", url];
            [tempDict setObject:tempString forKey:KEY_COMMAND_LINE];
            [tempDict setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
            aDict = tempDict;
        } else if ([urlType compare:@"telnet" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithString:@"telnet "];
            if ([urlRep user]) {
                [tempString appendFormat:@"-l %@ ", [[urlRep user] stringWithEscapedShellCharactersIncludingNewlines:YES]];
            }
            if ([urlRep host]) {
                [tempString appendString:[[urlRep host] stringWithEscapedShellCharactersIncludingNewlines:YES]];
                if ([urlRep port]) [tempString appendFormat:@" %@", [urlRep port]];
            }
            [tempDict setObject:tempString forKey:KEY_COMMAND_LINE];
            [tempDict setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
            aDict = tempDict;
        }
        if (!aDict) {
            aDict = tempDict;
        }
    }

    return aDict;
}

- (PTYSession *)launchBookmark:(NSDictionary *)bookmarkData
                    inTerminal:(PseudoTerminal *)theTerm
                       withURL:(NSString *)url
              hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
                       makeKey:(BOOL)makeKey
                   canActivate:(BOOL)canActivate
                       command:(NSString *)command
                         block:(PTYSession *(^)(Profile *, PseudoTerminal *))block {
    DLog(@"launchBookmark:inTerminal:withUrl:isHotkey:makeKey:canActivate:command:block:");
    DLog(@"Profile:\n%@", bookmarkData);
    DLog(@"URL: %@", url);
    DLog(@"hotkey window type: %@", @(hotkeyWindowType));
    DLog(@"makeKey: %@", @(makeKey));
    DLog(@"canActivate: %@", @(canActivate));
    DLog(@"command: %@", command);

    PseudoTerminal *term;
    NSDictionary *aDict;
    const iTermObjectType objectType = theTerm ? iTermTabObject : iTermWindowObject;
    const BOOL isHotkey = (hotkeyWindowType != iTermHotkeyWindowTypeNone);

    aDict = bookmarkData;
    if (aDict == nil) {
        aDict = [self defaultBookmark];
    }

    if (url) {
        DLog(@"Add URL to profile");
        // Automatically fill in ssh command if command is exactly equal to $$ or it's a login shell.
        aDict = [self profile:aDict modifiedToOpenURL:url forObjectType:objectType];
        if (aDict == nil) {
            // Bogus hostname detected
            return nil;
        }
    }
    if (!bookmarkData) {
        DLog(@"Using profile:\n%@", aDict);
    }
    if (theTerm && [[aDict objectForKey:KEY_PREVENT_TAB] boolValue]) {
        theTerm = nil;
    }

    // Where do we execute this command?
    BOOL toggle = NO;
    if (theTerm == nil || ![theTerm windowInitialized]) {
        [iTermController switchToSpaceInBookmark:aDict];
        int windowType = [self windowTypeForBookmark:aDict];
        if (isHotkey && windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
            windowType = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
        }
        if (theTerm) {
            DLog(@"Finish initialization of an existing window controller");
            term = theTerm;
            [term finishInitializationWithSmartLayout:YES
                                           windowType:windowType
                                      savedWindowType:WINDOW_TYPE_NORMAL
                                               screen:[aDict objectForKey:KEY_SCREEN] ? [[aDict objectForKey:KEY_SCREEN] intValue] : -1
                                     hotkeyWindowType:hotkeyWindowType];
        } else {
            DLog(@"Create a new window controller");
            term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                                     windowType:windowType
                                                savedWindowType:WINDOW_TYPE_NORMAL
                                                         screen:[aDict objectForKey:KEY_SCREEN] ? [[aDict objectForKey:KEY_SCREEN] intValue] : -1
                                               hotkeyWindowType:hotkeyWindowType] autorelease];
        }
        if ([[aDict objectForKey:KEY_HIDE_AFTER_OPENING] boolValue]) {
            [term hideAfterOpening];
        }
        [self addTerminalWindow:term];
        if (isHotkey) {
            // See comment above regarding hotkey windows.
            toggle = NO;
        } else {
            toggle = ([term windowType] == WINDOW_TYPE_LION_FULL_SCREEN);
        }
    } else {
        DLog(@"Use an existing window");
        term = theTerm;
    }

    PTYSession* session = nil;

    if (block) {
        DLog(@"Create a session via callback");
        session = block(aDict, term);
    } else if (url) {
        DLog(@"Creating a new session");
        session = [term createSessionWithProfile:aDict
                                         withURL:url
                                   forObjectType:objectType
                                serverConnection:NULL];
    } else {
        session = [term createTabWithProfile:aDict withCommand:command];
    }
    if (!session && term.numberOfTabs == 0) {
        [[term window] close];
        return nil;
    }

    if (toggle) {
        [term delayedEnterFullscreen];
    }
    if (makeKey && ![[term window] isKeyWindow]) {
        // When this function is activated from the dock icon's context menu make sure
        // that the new window is on top of all other apps' windows. For some reason,
        // makeKeyAndOrderFront does nothing.
        if ([term.window isKindOfClass:[iTermPanel class]]) {
            canActivate = NO;
        }
        if (canActivate) {
            // activateIgnoringApp: happens asynchronously which means doing makeKeyAndOrderFront:
            // immediately after it won't do what you want. Issue 6397
            NSWindow *termWindow = [[term window] retain];
            [[iTermApplication sharedApplication] activateAppWithCompletion:^{
                [termWindow makeKeyAndOrderFront:nil];
                [termWindow release];
            }];
        } else {
            [[term window] makeKeyAndOrderFront:nil];
        }
        if (canActivate) {
            [NSApp arrangeInFront:self];
        }
    }

    return session;
}

- (PTYTextView *)frontTextView {
    return ([[_frontTerminalWindowController currentSession] textview]);
}

- (int)numberOfTerminals {
    return [_terminalWindows count];
}

- (NSUInteger)indexOfTerminal:(PseudoTerminal*)terminal {
    return [_terminalWindows indexOfObject:terminal];
}

-(PseudoTerminal *)terminalAtIndex:(int)i {
    return [_terminalWindows objectAtIndex:i];
}

- (PseudoTerminal *)terminalForWindow:(NSWindow *)window {
    for (PseudoTerminal *term in _terminalWindows) {
        if (term.window == window) {
            return term;
        }
    }
    return nil;
}

- (int)allocateWindowNumber {
    NSMutableSet* numbers = [NSMutableSet setWithCapacity:[self numberOfTerminals]];
    for (PseudoTerminal* term in [self terminals]) {
        [numbers addObject:[NSNumber numberWithInt:[term number]]];
    }
    for (int i = 0; i < [self numberOfTerminals] + 1; i++) {
        if (![numbers containsObject:[NSNumber numberWithInt:i]]) {
            return i;
        }
    }
    assert(false);
    return 0;
}

- (PseudoTerminal *)terminalWithNumber:(int)n {
    for (PseudoTerminal* term in [self terminals]) {
        if ([term number] == n) {
            return term;
        }
    }
    return nil;
}

- (PseudoTerminal *)terminalWithGuid:(NSString *)guid {
    for (PseudoTerminal *term in [self terminals]) {
        if ([[term terminalGuid] isEqualToString:guid]) {
            return term;
        }
    }
    return nil;
}

- (void)dumpViewHierarchy {
    for (PseudoTerminal *term in [self terminals]) {
        DebugLog([NSString stringWithFormat:@"Terminal %@ at %@", [term window], [NSValue valueWithRect:[[term window] frame]]]);
        DebugLog([[[term window] contentView] iterm_recursiveDescription]);
    }
}

- (void)refreshSoftwareUpdateUserDefaults {
    BOOL checkForTestReleases = [iTermPreferences boolForKey:kPreferenceKeyCheckForTestReleases];
    NSString *appCast = checkForTestReleases ?
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"] :
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForFinal"];
    NSURL *url = [NSURL URLWithString:appCast];
    NSNumber *shard = @([iTermController shard]);
    url = [url URLByAppendingQueryParameter:[NSString stringWithFormat:@"shard=%@", shard]];
    [[NSUserDefaults standardUserDefaults] setObject:url.absoluteString forKey:@"SUFeedURL"];
    // Allow Sparkle to update from a zip file containing an "iTerm" directory,
    // even though our bundle name is now "iTerm2". I had to add this feature
    // to my fork of Sparkle so I could change the app's name without breaking
    // auto-update. https://github.com/gnachman/Sparkle, commit
    // bd6a8df6e63b843f1f8aff79f40bd70907761a99.
    [[NSUserDefaults standardUserDefaults] setObject:@"iTerm"
                                              forKey:@"SUFeedAlternateAppNameKey"];
}

- (BOOL)selectionRespectsSoftBoundaries {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSelectionRespectsSoftBoundariesKey];
}

- (void)setSelectionRespectsSoftBoundaries:(BOOL)selectionRespectsSoftBoundaries {
    [[NSUserDefaults standardUserDefaults] setBool:selectionRespectsSoftBoundaries
                                            forKey:kSelectionRespectsSoftBoundariesKey];
}

- (void)addRestorableSession:(iTermRestorableSession *)session {
    if (!self.currentRestorableSession) {
        [_restorableSessions addObject:session];
    }
}

- (void)pushCurrentRestorableSession:(iTermRestorableSession *)session {
    [_currentRestorableSessionsStack insertObject:session
                                          atIndex:0];
}

- (void)commitAndPopCurrentRestorableSession {
    iTermRestorableSession *session = self.currentRestorableSession;
    assert(session);
    if (session) {
        if (session.sessions.count > 0) {
            [_restorableSessions addObject:session];
        }
        [_currentRestorableSessionsStack removeObjectAtIndex:0];
    }
}

- (iTermRestorableSession *)currentRestorableSession {
    return _currentRestorableSessionsStack.count ? _currentRestorableSessionsStack[0] : nil;
}

- (void)removeSessionFromRestorableSessions:(PTYSession *)session {
    NSInteger index =
        [_restorableSessions indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            iTermRestorableSession *restorableSession = obj;
            if ([restorableSession.sessions containsObject:session]) {
                *stop = YES;
                return YES;
            } else {
                return NO;
            }
        }];
    if (index != NSNotFound) {
        [_restorableSessions removeObjectAtIndex:index];
    }
}

- (iTermRestorableSession *)popRestorableSession {
    if (!_restorableSessions.count) {
        return nil;
    }
    iTermRestorableSession *restorableSession = [[[_restorableSessions lastObject] retain] autorelease];
    [_restorableSessions removeLastObject];
    return restorableSession;
}

- (BOOL)hasRestorableSession {
    return _restorableSessions.count > 0;
}

- (void)killRestorableSessions {
    assert([iTermAdvancedSettingsModel runJobsInServers]);
    for (iTermRestorableSession *restorableSession in _restorableSessions) {
        for (PTYSession *aSession in restorableSession.sessions) {
            if (aSession.shell.serverPid != -1) {
                [aSession.shell sendSignal:SIGKILL toServer:YES];
            }
            [aSession.shell sendSignal:SIGHUP toServer:YES];
        }
    }
}

// This exists because I don't trust -[NSApp keyWindow]. I've seen all kinds of weird behavior from it.
- (BOOL)anyVisibleWindowIsKey {
    DLog(@"Searching for key window...");
    for (NSWindow *window in [(iTermApplication *)NSApp orderedWindowsPlusVisibleHotkeyPanels]) {
        if (window.isKeyWindow) {
            DLog(@"Key ordered window is %@", window);
            return YES;
        }
    }
    DLog(@"No key window");
    return NO;
}

// I don't trust -[NSApp mainWindow].
- (BOOL)anyWindowIsMain {
    for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
        if ([window isMainWindow]) {
            return YES;
        }
    }
    return NO;
}

// Returns all terminal windows that are key.
- (NSArray<iTermTerminalWindow *> *)keyTerminalWindows {
    NSMutableArray<iTermTerminalWindow *> *temp = [NSMutableArray array];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        iTermTerminalWindow *window = [term ptyWindow];
        if ([window isKeyWindow]) {
            [temp addObject:window];
        }
    }
    return temp;
}

// accessors for to-many relationships:
- (NSArray *)terminals {
    return _terminalWindows;
}

- (void)setCurrentTerminal:(PseudoTerminal *)thePseudoTerminal {
    _frontTerminalWindowController = thePseudoTerminal;

    // make sure this window is the key window
    if ([thePseudoTerminal windowInitialized] && [[thePseudoTerminal window] isKeyWindow] == NO) {
        [[thePseudoTerminal window] makeKeyAndOrderFront:self];
        if ([thePseudoTerminal fullScreen]) {
          [thePseudoTerminal hideMenuBar];
        }
    }

    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:thePseudoTerminal
                                                      userInfo:nil];

}

- (void)addTerminalWindow:(PseudoTerminal *)terminalWindow {
    if ([_terminalWindows containsObject:terminalWindow] == YES) {
        return;
    }

    [_terminalWindows addObject:terminalWindow];
    [self updateWindowTitles];
}

- (void)removeTerminalWindow:(PseudoTerminal *)terminalWindow {
    [_terminalWindows removeObject:terminalWindow];
    [self updateWindowTitles];
}

- (void)workspaceWillPowerOff:(NSNotification *)notification {
    _willPowerOff = YES;
    if ([iTermAdvancedSettingsModel killSessionsOnLogout] && [iTermAdvancedSettingsModel runJobsInServers]) {
        [self killRestorableSessions];
    }
}

- (NSInteger)numberOfDecodesPending {
    return [[self.terminals filteredArrayUsingBlock:^BOOL(PseudoTerminal *anObject) {
        return anObject.restorableStateDecodePending;
    }] count];
}

- (void)openSingleUseWindowWithCommand:(NSString *)command {
    [self openSingleUseWindowWithCommand:command inject:nil];
}

- (void)openSingleUseWindowWithCommand:(NSString *)command inject:(NSData *)injection {
    if ([command hasSuffix:@"&"] && command.length > 1) {
        command = [command substringToIndex:command.length - 1];
        system(command.UTF8String);
        return;
    }
    NSString *escapedCommand = [command stringWithEscapedShellCharactersIncludingNewlines:YES];
    command = [NSString stringWithFormat:@"sh -c \"%@\"", escapedCommand];
    Profile *windowProfile = [self defaultBookmark];
    if ([windowProfile[KEY_WINDOW_TYPE] integerValue] == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN ||
        [windowProfile[KEY_WINDOW_TYPE] integerValue] == WINDOW_TYPE_LION_FULL_SCREEN) {
        windowProfile = [windowProfile dictionaryBySettingObject:@(WINDOW_TYPE_NORMAL) forKey:KEY_WINDOW_TYPE];
    }

    [self launchBookmark:windowProfile
              inTerminal:nil
                 withURL:nil
        hotkeyWindowType:iTermHotkeyWindowTypeNone
                 makeKey:YES
             canActivate:YES
                 command:command
                   block:^PTYSession *(Profile *profile, PseudoTerminal *term) {
                       profile = [profile dictionaryBySettingObject:@"" forKey:KEY_INITIAL_TEXT];
                       profile = [profile dictionaryBySettingObject:@NO forKey:KEY_CLOSE_SESSIONS_ON_END];
                       term.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenNone;
                       PTYSession *session = [term createTabWithProfile:profile withCommand:command];
                       session.isSingleUseSession = YES;
                       if (injection) {
                           [session injectData:injection];
                       }
                       return session;
                   }];
}

@end

