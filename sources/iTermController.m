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
#import "iTerm2SharedARC-Swift.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermBuriedSessions.h"
#import "iTermHotKeyController.h"
#import "iTermMissionControlHacks.h"
#import "iTermPresentationController.h"
#import "iTermProfileModelJournal.h"
#import "iTermRestorableStateController.h"
#import "iTermSessionFactory.h"
#import "iTermSessionLauncher.h"
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
#import "iTermFullScreenWindowManager.h"
#import "iTermNotificationController.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermRestorableSession.h"
#import "iTermSetCurrentTerminalHelper.h"
#import "iTermSystemVersion.h"
#import "iTermUserDefaults.h"
#import "iTermWarning.h"
#import "PTYWindow.h"

#include <objc/runtime.h>

@import Sparkle;

NSString *const iTermSnippetsTagsDidChange = @"iTermSnippetsTagsDidChange";

@interface NSApplication (Undocumented)
- (void)_cycleWindowsReversed:(BOOL)back;
@end

extern NSString *const iTermProcessTypeDidChangeNotification;

// Pref keys
static iTermController *gSharedInstance;

@interface iTermController()<iTermSetCurrentTerminalHelperDelegate, iTermPresentationControllerDelegate>
@end

@implementation iTermController {
    NSMutableArray *_restorableSessions;
    NSMutableArray *_currentRestorableSessionsStack;

    NSMutableArray<PseudoTerminal *> *_terminalWindows;
    PseudoTerminal *_frontTerminalWindowController;
    iTermFullScreenWindowManager *_fullScreenWindowManager;
    BOOL _willPowerOff;
    BOOL _arrangeHorizontallyPendingFullScreenTransitions;
    iTermSetCurrentTerminalHelper *_setCurrentTerminalHelper;
}

+ (iTermController *)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSharedInstance = [[iTermController alloc] init];
    });

    return gSharedInstance;
}

+ (void)releaseSharedInstance {
    DLog(@"releaseSharedInstance");
    [gSharedInstance cleanUpIfNeeded];
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

        _setCurrentTerminalHelper = [[iTermSetCurrentTerminalHelper alloc] init];
        _setCurrentTerminalHelper.delegate = self;
        _terminalWindows = [[NSMutableArray alloc] init];
        _restorableSessions = [[NSMutableArray alloc] init];
        _currentRestorableSessionsStack = [[NSMutableArray alloc] init];
        [iTermNotificationController sharedInstance];

        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(workspaceWillPowerOff:)
                                                                   name:NSWorkspaceWillPowerOffNotification
                                                                 object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidExitFullScreen:)
                                                     name:NSWindowDidExitFullScreenNotification
                                                   object:nil];
        [[iTermPresentationController sharedInstance] setDelegate:self];
    }

    return (self);
}

- (BOOL)willRestoreWindowsAtNextLaunch {
  return (![iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup] &&
          ![iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup] &&
          [iTermRestorableStateController stateRestorationEnabled]);
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
    DLog(@"dealloc");
    [self cleanUpIfNeeded];

    [_restorableSessions release];
    [_currentRestorableSessionsStack release];
    [_fullScreenWindowManager release];
    [_lastSelectionPromise release];
    [_setCurrentTerminalHelper release];
    [super dealloc];
}

- (void)cleanUpIfNeeded {
    @synchronized([iTermController class]) {
        static BOOL needsCleanUp = YES;
        if (!needsCleanUp) {
            return;
        }
        needsCleanUp = NO;
    }
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
        DLog(@"Intentionally leaving sessions running on quit");
        [_terminalWindows autorelease];
    } else {
        DLog(@"Will close all terminal windows to kill jobs: %@", _terminalWindows);
        // Terminate buried sessions
        [[iTermBuriedSessions sharedInstance] terminateAll];
        // Close all terminal windows, killing jobs.
        while ([_terminalWindows count] > 0) {
            [[_terminalWindows objectAtIndex:0] close];
        }
        ITAssertWithMessage([_terminalWindows count] == 0, @"Expected terminals to be gone");
        [_terminalWindows release];
    }
    _terminalWindows = nil;
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
        if ([terminal undecoratedWindowTitle]) {
            [terminal setWindowTitle];
        }
    }
}

- (void)updateProcessType {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermProcessTypeDidChangeNotification
                                                        object:nil];
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
    DLog(@"newWindow:%@ possiblyTmux:%@", sender, @(possiblyTmux));
    if (possiblyTmux &&
        _frontTerminalWindowController &&
        [[_frontTerminalWindowController currentSession] isTmuxClient]) {
        DLog(@"Creating a new tmux window");
        [_frontTerminalWindowController newTmuxWindow:sender];
    } else {
        [iTermSessionLauncher launchBookmark:nil
                                  inTerminal:nil
                          respectTabbingMode:YES
                                  completion:nil];
    }
}

- (void)newSessionInTabAtIndex:(id)sender {
    Profile *bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [iTermSessionLauncher launchBookmark:bookmark
                                  inTerminal:_frontTerminalWindowController
                          respectTabbingMode:NO
                                  completion:nil];
    }
}

- (BOOL)terminalIsObscured:(id<iTermWindowController>)terminal {
    return [self terminalIsObscured:terminal
                          threshold:[iTermAdvancedSettingsModel notificationOcclusionThreshold]];
}

- (BOOL)terminalIsObscured:(id<iTermWindowController>)terminal threshold:(double)threshold {
    BOOL windowIsObscured = NO;
    NSWindow *window = [terminal window];
    NSWindowOcclusionState occlusionState = window.occlusionState;
    // The occlusionState tells if you if you're on another space or another app's window is
    // occluding yours, but for some reason one terminal window can occlude another without
    // it noticing, so we compute that ourselves.
    windowIsObscured = !(occlusionState & NSWindowOcclusionStateVisible);
    if (!windowIsObscured) {
        // Try to refine the guess by seeing if another terminal is covering this one.
        if ([(iTermTerminalWindow *)terminal.window approximateFractionOccluded] > threshold) {
            windowIsObscured = YES;
        }
    }
    return windowIsObscured;
}

- (void)newSessionInWindowAtIndex:(id)sender {
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (profile) {
        [iTermSessionLauncher launchBookmark:profile
                                  inTerminal:nil
                          respectTabbingMode:NO
                                  completion:nil];
    }
}

// meant for action for menu items that have a submenu
- (void)noAction:(id)sender {
}

- (void)newSessionWithSameProfile:(id)sender newWindow:(BOOL)newWindow {
    Profile *bookmark = nil;
    if (_frontTerminalWindowController) {
        const BOOL tmux = [[_frontTerminalWindowController currentSession] isTmuxClient];
        if (tmux) {
            if (newWindow) {
                [_frontTerminalWindowController newTmuxWindow:sender];
            } else {
                [_frontTerminalWindowController newTmuxTabAtIndex:nil];
            }
            return;
        }
        bookmark = [[_frontTerminalWindowController currentSession] profile];
    }
    BOOL divorced = ([[ProfileModel sessionsInstance] bookmarkWithGuid:bookmark[KEY_GUID]] != nil);
    if (divorced) {
        DLog(@"Creating a new session with a sessions instance guid");
        NSString *guid = [ProfileModel freshGuid];
        bookmark = [bookmark dictionaryBySettingObject:guid forKey:KEY_GUID];
    }
    PseudoTerminal *windowController = (newWindow) ? nil : _frontTerminalWindowController;
    [iTermSessionLauncher launchBookmark:bookmark
                              inTerminal:windowController
                      respectTabbingMode:newWindow
                              completion:^(PTYSession *session) {
        if (divorced) {
            [session divorceAddressBookEntryFromPreferences];
            [session refreshOverriddenFields];
        }
    }];
}

// Launch a new session using the default profile. If the current session is
// tmux and possiblyTmux is true, open a new tmux session.
- (void)newSession:(id)sender possiblyTmux:(BOOL)possiblyTmux index:(NSNumber *)index {
    DLog(@"newSession:%@ possiblyTmux:%d from %@",
         sender, (int)possiblyTmux, [NSThread callStackSymbols]);
    if (possiblyTmux &&
        _frontTerminalWindowController &&
        [[_frontTerminalWindowController currentSession] isTmuxClient]) {
        [_frontTerminalWindowController newTmuxTabAtIndex:index];
    } else {
        [iTermSessionLauncher launchBookmark:nil
                                  inTerminal:_frontTerminalWindowController
                                     withURL:nil
                            hotkeyWindowType:iTermHotkeyWindowTypeNone
                                     makeKey:YES
                                 canActivate:YES
                          respectTabbingMode:NO
                                       index:index
                                     command:nil
                                 makeSession:nil
                              didMakeSession:nil
                                  completion:nil];
    }
}

- (NSArray<PTYSession *> *)allSessions {
    return [_terminalWindows flatMapWithBlock:^NSArray *(PseudoTerminal *anObject) {
        return anObject.allSessions;
    }];
}

- (NSArray<PseudoTerminal *> *)terminalsSortedByNumber {
    return [_terminalWindows sortedArrayUsingComparator:^NSComparisonResult(PseudoTerminal *obj1, PseudoTerminal *obj2) {
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

- (BOOL)arrangementWithName:(NSString *)arrangementName
         hasSessionWithGUID:(NSString *)guid
                        pwd:(NSString *)pwd {
    NSArray *windowArrangements = [WindowArrangements arrangementWithName:arrangementName];
    if (!windowArrangements) {
        return NO;
    }
    return [windowArrangements anyWithBlock:^BOOL(id anObject) {
        NSDictionary *dict = [PseudoTerminal arrangementForSessionWithGUID:guid inWindowArrangement:anObject];
        if (!dict) {
            return NO;
        }
        NSString *actualPWD = [PTYSession initialWorkingDirectoryFromArrangement:dict];
        return [actualPWD isEqual:pwd];
    }];
}

- (void)repairSavedArrangementNamed:(NSString *)arrangementName
replaceInitialDirectoryForSessionWithGUID:(NSString *)guid
                               with:(NSString *)replacementOldCWD {
    NSArray *terminalArrangements = [WindowArrangements arrangementWithName:arrangementName];
    NSArray *repairedArrangements = [terminalArrangements mapWithBlock:^id(NSDictionary *terminalArrangement) {
        return [PseudoTerminal repairedArrangement:terminalArrangement
                  replacingOldCWDOfSessionWithGUID:guid
                                        withOldCWD:replacementOldCWD];
    }];
    [WindowArrangements setArrangement:repairedArrangements
                              withName:arrangementName];
}

- (void)saveWindowArrangement:(BOOL)allWindows {
    NSString *name = [WindowArrangements nameForNewArrangement];
    if (!name) {
        return;
    }
    [self saveWindowArrangementForAllWindows:allWindows name:name];
}

- (void)saveWindowArrangementForAllWindows:(BOOL)allWindows name:(NSString *)name {
    if (allWindows) {
        NSMutableArray *terminalArrangements = [NSMutableArray arrayWithCapacity:[_terminalWindows count]];
        for (PseudoTerminal *terminal in _terminalWindows) {
            NSDictionary *arrangement = [terminal arrangement];
            if (arrangement) {
                [terminalArrangements addObject:arrangement];
            }
        }
        [WindowArrangements setArrangement:terminalArrangements withName:name];
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

- (void)tryOpenArrangement:(NSDictionary *)terminalArrangement
                     named:(NSString *)arrangementName
            asTabsInWindow:(PseudoTerminal *)term {
    if (term) {
        [term restoreTabsFromArrangement:terminalArrangement
                                   named:arrangementName
                                sessions:nil
                      partialAttachments:nil];
        return;
    }
    const BOOL lionFullScreen = [PseudoTerminal arrangementIsLionFullScreen:terminalArrangement];
    [PseudoTerminal performWhenWindowCreationIsSafeForLionFullScreen:lionFullScreen
                                                               block:^{

        DLog(@"Opening it.");
        PseudoTerminal *term = [PseudoTerminal terminalWithArrangement:terminalArrangement
                                                                 named:arrangementName
                                              forceOpeningHotKeyWindow:NO];
        if (term) {
          [self addTerminalWindow:term];
        }
    }];
}

- (BOOL)loadWindowArrangementWithName:(NSString *)theName asTabsInTerminal:(PseudoTerminal *)term {
    BOOL ok = NO;
    NSArray *terminalArrangements = [WindowArrangements arrangementWithName:theName];
    if (terminalArrangements) {
        for (NSDictionary *terminalArrangement in terminalArrangements) {
            [self tryOpenArrangement:terminalArrangement named:theName asTabsInWindow:term];
            ok = YES;
        }
    }
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

- (NSArray<NSString *> *)currentSnippetsFilter {
    return self.currentTerminal.currentSnippetTags ?: @[];
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

    unsigned int modifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
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

        modifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
        [aMenuItem setRepresentedObject:[bookmark objectForKey:KEY_GUID]];
        [aMenuItem setTarget:self];

        [aMenuItem setKeyEquivalentModifierMask:modifierMask | NSEventModifierFlagOption];
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
        unsigned int modifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
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
        modifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
        [aMenuItem setAlternate:YES];
        [aMenuItem setKeyEquivalentModifierMask:modifierMask | NSEventModifierFlagOption];
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
                               silenceable:kiTermWarningTypePermanentlySilenceable
                                    window:nil];
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
    NSArray *profiles = [self bookmarksInMenu:theMenu];
    static const int kWarningThreshold = 10;
    if ([profiles count] > kWarningThreshold) {
        if (![self shouldOpenManyProfiles:profiles.count]) {
            return;
        }
    }

    PseudoTerminal *term = newWindow ? nil : [self currentTerminal];
    [self openSessionsFromProfiles:profiles inWindowController:term];
}

- (void)openSessionsFromProfiles:(NSArray<Profile *> *)profiles inWindowController:(PseudoTerminal *)term {
    if (profiles.count == 0) {
        return;
    }
    Profile *head = profiles.firstObject;
    NSArray<Profile *> *tail = [profiles subarrayFromIndex:1];
    [iTermSessionLauncher launchBookmark:head inTerminal:term respectTabbingMode:NO completion:^(PTYSession * _Nonnull session) {
        PseudoTerminal *nextTerm = term;
        if (!term && session) {
            nextTerm = [self terminalWithSession:session];
        }
        [self openSessionsFromProfiles:tail inWindowController:nextTerm];
    }];
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

- (NSString *)ancestryIdentifierForMenu:(NSMenu *)menu {
    if (!menu.supermenu) {
        return menu.title;
    }
    return [menu.title stringByAppendingFormat:@".%@", [self ancestryIdentifierForMenu:menu.supermenu]];
}

- (void)addBookmarksToMenu:(NSMenu *)aMenu
                 supermenu:(NSMenu *)supermenu
              withSelector:(SEL)selector
           openAllSelector:(SEL)openAllSelector
                startingAt:(int)startingAt {
    iTermProfileModelJournalParams *params = [[[iTermProfileModelJournalParams alloc] init] autorelease];
    params.selector = selector;
    params.openAllSelector = openAllSelector;
    params.alternateSelector = @selector(newSessionInWindowAtIndex:);
    params.alternateOpenAllSelector = @selector(newSessionsInWindow:);
    params.target = self;

    ProfileModel *bm = [ProfileModel sharedInstance];
    int N = [bm numberOfBookmarks];
    for (int i = 0; i < N; i++) {
        Profile *b = [bm profileAtIndex:i];
        [bm.menuController addBookmark:b
                                toMenu:aMenu
                        startingAtItem:startingAt
                              withTags:[b objectForKey:KEY_TAGS]
                                params:params
                                 atPos:i
                            identifier:nil];
    }
}

- (void)irAdvance:(int)dir {
    [_frontTerminalWindowController irAdvance:dir];
}

+ (void)switchToSpaceInBookmark:(Profile *)aDict {
    if (!aDict[KEY_SPACE]) {
        return;
    }
    const int spaceNum = [aDict[KEY_SPACE] intValue];
    if (spaceNum <= 0 || spaceNum >= 10) {
        return;
    }
    [iTermMissionControlHacks switchToSpace:spaceNum];
}

- (iTermWindowType)windowTypeForBookmark:(Profile *)aDict {
    if ([aDict objectForKey:KEY_WINDOW_TYPE]) {
        const iTermWindowType windowType = iTermThemedWindowType([[aDict objectForKey:KEY_WINDOW_TYPE] intValue]);
        if (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN &&
            [iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscreen]) {
            return WINDOW_TYPE_LION_FULL_SCREEN;
        } else {
            return windowType;
        }
    } else {
        return iTermWindowDefaultType();
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

- (PseudoTerminal *)openTmuxIntegrationWindowUsingProfile:(Profile *)profile
                                         perWindowSetting:(NSString *)perWindowSetting {
    [iTermController switchToSpaceInBookmark:profile];
    iTermWindowType windowType;
    if ([iTermAdvancedSettingsModel serializeOpeningMultipleFullScreenWindows]) {
        windowType = [self windowTypeForBookmark:profile];
    } else {
        windowType = iTermThemedWindowType([iTermProfilePreferences intForKey:KEY_WINDOW_TYPE inProfile:profile]);
    }
    PseudoTerminal *term =
        [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                          windowType:windowType
                                     savedWindowType:windowType
                                              screen:[iTermProfilePreferences intForKey:KEY_SCREEN inProfile:profile]
                                    hotkeyWindowType:iTermHotkeyWindowTypeNone
                                             profile:profile] autorelease];
    if ([iTermProfilePreferences boolForKey:KEY_HIDE_AFTER_OPENING inProfile:profile]) {
        [term hideAfterOpening];
    }
    if (term.windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        [term delayedEnterFullscreen];
    } else {
        iTermProfileHotKey *profileHotKey =
        [[iTermHotKeyController sharedInstance] didCreateWindowController:term
                                                              withProfile:profile];
        [profileHotKey setAllowsStateRestoration:NO];
    }

    [self addTerminalWindow:term];
    [term setTmuxPerWindowSetting:perWindowSetting];
    return term;
}

- (void)didFinishCreatingTmuxWindow:(PseudoTerminal *)windowController {
    [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:windowController] showHotKeyWindow];
    [windowController ensureSaneFrame];
}

- (void)makeTerminalWindowFullScreen:(NSWindowController<iTermWindowController> *)term {
    [[iTermFullScreenWindowManager sharedInstance] makeWindowEnterFullScreen:term.ptyWindow];
}

- (PseudoTerminal *)windowControllerForNewTabWithProfile:(Profile *)profile
                                               candidate:(PseudoTerminal *)preferredWindowController
                                      respectTabbingMode:(BOOL)respectTabbingMode {
    const BOOL preventTab = [profile[KEY_PREVENT_TAB] boolValue];
    if (preventTab) {
        return nil;
    }
    if (!respectTabbingMode || [iTermAdvancedSettingsModel disregardDockSettingToOpenTabsInsteadOfWindows]) {
        return preferredWindowController;
    }
    switch ([iTermUserDefaults appleWindowTabbingMode]) {
        case iTermAppleWindowTabbingModeManual:
            return preferredWindowController;
        case iTermAppleWindowTabbingModeAlways:
            if (preferredWindowController) {
                return preferredWindowController;
            }
            [self maybeWarnAboutOpeningInTab];
            return [self currentTerminal];
        case iTermAppleWindowTabbingModeFullscreen: {
            if (preferredWindowController) {
                return preferredWindowController;
            }
            PseudoTerminal *tempTerm = [[iTermController sharedInstance] currentTerminal];
            if (tempTerm && tempTerm.windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
                [self maybeWarnAboutOpeningInTab];
                return tempTerm;
            }
            return nil;
        }
    }
}

- (void)maybeWarnAboutOpeningInTab {
#if ENABLE_RESPECT_DOCK_PREFER_TABS_SETTING
    NSString *const firstVersionRespectingSetting = @"SET THIS";
    if (iTermUserDefaults.haveBeenWarnedAboutTabDockSetting) {
        return;
    }
    id<SUVersionComparison> comparator = [SUStandardVersionComparator defaultComparator];
    const BOOL haveUsedOlderVersion = [[iTermPreferences allAppVersionsUsedOnThisMachine].allObjects anyWithBlock:^BOOL(NSString *version) {
        return [comparator compareVersion:firstVersionRespectingSetting toVersion:version] == NSOrderedDescending;
    }];
    if (!haveUsedOlderVersion) {
        return;
    }
    [[iTermNotificationController sharedInstance] postNotificationWithTitle:@"Creating a tab"
                                                                     detail:@"The system preference to open a tab instead of a window is now respected in iTerm2."
                                                                        URL:[NSURL URLWithString:@"https://gitlab.com/gnachman/iterm2/wikis/Prefer-Tabs-When-Opening-Documents"]];
    iTermUserDefaults.haveBeenWarnedAboutTabDockSetting = YES;
#endif
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
    DLog(@"Search for terminal with guid %@", guid);
    for (PseudoTerminal *term in [self terminals]) {
        if ([[term terminalGuid] isEqualToString:guid]) {
            DLog(@"Found it");
            return term;
        }
        DLog(@"%@", term.terminalGuid);
    }
    return nil;
}

- (PTYTab *)tabWithID:(NSString *)tabID {
    if (tabID.length == 0) {
        return nil;
    }
    NSCharacterSet *nonNumericCharacterSet = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([tabID rangeOfCharacterFromSet:nonNumericCharacterSet].location != NSNotFound) {
        return nil;
    }

    int numericID = tabID.intValue;
    for (PseudoTerminal *term in [self terminals]) {
        for (PTYTab *tab in term.tabs) {
            if (tab.uniqueId == numericID) {
                return tab;
            }
        }
    }
    return nil;
}

- (PTYTab *)tabWithGUID:(NSString *)guid {
    for (PseudoTerminal *term in self.terminals) {
        for (PTYTab *tab in term.tabs) {
            if ([tab.stringUniqueIdentifier isEqualToString:guid]) {
                return tab;
            }
        }
    }
    return nil;
}

- (PseudoTerminal *)windowForSessionWithGUID:(NSString *)guid {
    PTYSession *session = [self sessionWithGUID:guid];
    if (!session) {
        return nil;
    }
    return [self windowForSession:session];
}

- (PseudoTerminal *)windowForSession:(PTYSession *)session {
    PTYTab *tab = [self tabForSession:session];
    if (!tab) {
        return nil;
    }
    return [self windowForTab:tab];
}

- (PTYTab *)tabForSession:(PTYSession *)session {
    return [PTYTab castFrom:session.delegate];
}

- (PseudoTerminal *)windowForTab:(PTYTab *)tab {
    return [PseudoTerminal castFrom:tab.realParentWindow];
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
    DLog(@"killRestorableSessions");
    assert([iTermAdvancedSettingsModel runJobsInServers]);
    for (iTermRestorableSession *restorableSession in _restorableSessions) {
        for (PTYSession *aSession in restorableSession.sessions) {
            // Ensure servers are dead.
            [aSession.shell killWithMode:iTermJobManagerKillingModeForceUnrestorable];
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

- (void)setCurrentTerminal:(PseudoTerminal *)currentTerminal {
    [_setCurrentTerminalHelper setCurrentTerminal:currentTerminal];
}

- (void)addTerminalWindow:(PseudoTerminal *)terminalWindow {
    if ([_terminalWindows containsObject:terminalWindow] == YES) {
        return;
    }

    [_terminalWindows addObject:terminalWindow];
    [self updateWindowTitles];
    [self updateProcessType];
    [[iTermPresentationController sharedInstance] update];
}

- (void)removeTerminalWindow:(PseudoTerminal *)terminalWindow {
    [_terminalWindows removeObject:terminalWindow];
    [self updateWindowTitles];
    [self updateProcessType];
    [[iTermPresentationController sharedInstance] update];
}

- (PTYSession *)sessionWithGUID:(NSString *)identifier {
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        for (PTYSession *session in term.allSessions) {
            if ([session.guid isEqualToString:identifier]) {
                return session;
            }
        }
    }
    return nil;
}

- (void)workspaceWillPowerOff:(NSNotification *)notification {
    if ([iTermAdvancedSettingsModel killSessionsOnLogout] && [iTermAdvancedSettingsModel runJobsInServers]) {
        _willPowerOff = YES;
        [self killRestorableSessions];
    }
}

- (NSInteger)numberOfDecodesPending {
    const NSInteger result = [[self.terminals filteredArrayUsingBlock:^BOOL(PseudoTerminal *anObject) {
        return anObject.restorableStateDecodePending;
    }] count];
    DLog(@"%@", @(result));
    return result;
}

- (NSString *)shCommandLineWithCommand:(NSString *)command
                             arguments:(NSArray<NSString *> *)arguments
                       escapeArguments:(BOOL)escapeArguments {
    NSArray<NSString *> *const escapedArguments = [arguments mapWithBlock:^id(NSString *anObject) {
        if (escapeArguments) {
            return [anObject stringWithBackslashEscapedShellCharactersIncludingNewlines:YES];
        } else {
            return anObject;
        }
    }];
    NSString *const escapedCommand = escapeArguments ? [command stringWithBackslashEscapedShellCharactersIncludingNewlines:YES] : command;
    NSArray<NSString *> *const combinedArray = [@[escapedCommand] arrayByAddingObjectsFromArray:escapedArguments];
    NSString *const commandLine = [combinedArray componentsJoinedByString:@" "];
    return [NSString stringWithFormat:@"sh -c \"%@\"", commandLine];
}

- (NSWindow *)openWindow:(BOOL)makeWindow 
                 command:(NSString *)command
               directory:(NSString *)directory
                hostname:(NSString *)hostname
                username:(NSString *)username {
    MutableProfile *profile = [[[[ProfileModel sharedInstance] defaultProfile] mutableCopy] autorelease];
    if (directory) {
        profile[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryCustomValue;
        profile[KEY_WORKING_DIRECTORY] = directory;
    } else {
        profile[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryHomeValue;
    }
    if (hostname) {
        profile[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeSSHValue;
        iTermSSHConfiguration *sshConfig = [[[iTermSSHConfiguration alloc] init] autorelease];
        profile[KEY_SSH_CONFIG] = sshConfig.dictionaryValue;
        if (username) {
            profile[KEY_COMMAND_LINE] = [NSString stringWithFormat:@"%@@%@", username, hostname];
        } else {
            profile[KEY_COMMAND_LINE] = hostname;
        }
    }
    profile[KEY_INITIAL_TEXT] = command;
    PseudoTerminal *term = [self currentTerminal];
    if (makeWindow || !term) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                                 windowType:WINDOW_TYPE_NORMAL
                                            savedWindowType:WINDOW_TYPE_NORMAL
                                                     screen:-1
                                           hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                    profile:profile] autorelease];
        [self addTerminalWindow:term];
    }

    DLog(@"Open login window");
    void (^makeSession)(Profile *, PseudoTerminal *, void (^)(PTYSession *)) =
    ^(Profile *profile, PseudoTerminal *term, void (^makeSessionCompletion)(PTYSession *))  {
        term.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenNone;

        [term asyncCreateTabWithProfile:profile
                            withCommand:nil
                            environment:nil
                               tabIndex:nil
                         didMakeSession:^(PTYSession *session) {
            makeSessionCompletion(session);
        }
                             completion:nil];
    };
    [iTermSessionLauncher launchBookmark:profile
                              inTerminal:term
                                 withURL:nil
                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                 makeKey:YES
                             canActivate:YES
                      respectTabbingMode:NO
                                   index:nil
                                 command:nil
                             makeSession:makeSession
                          didMakeSession:^(PTYSession *session) { }
                              completion:^(PTYSession * _Nonnull session, BOOL ok) {
    }];
    [term.window makeKeyAndOrderFront:nil];
    return term.window;
}

- (NSWindow *)openSingleUseLoginWindowAndWrite:(NSData *)data completion:(void (^)(PTYSession *session))completion {
    MutableProfile *profile = [[[[ProfileModel sharedInstance] defaultProfile] mutableCopy] autorelease];
    profile[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryHomeValue;
    profile[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeCustomShellValue;
    if ([profile[KEY_WINDOW_TYPE] integerValue] == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN ||
        [profile[KEY_WINDOW_TYPE] integerValue] == WINDOW_TYPE_LION_FULL_SCREEN) {
        profile[KEY_WINDOW_TYPE] = @(iTermWindowDefaultType());
    }

    PseudoTerminal *term = nil;
    term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                             windowType:WINDOW_TYPE_ACCESSORY
                                        savedWindowType:WINDOW_TYPE_ACCESSORY
                                                 screen:-1
                                       hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                profile:profile] autorelease];
    [self addTerminalWindow:term];

    DLog(@"Open login window");
    void (^makeSession)(Profile *, PseudoTerminal *, void (^)(PTYSession *)) =
    ^(Profile *profile, PseudoTerminal *term, void (^makeSessionCompletion)(PTYSession *))  {
        profile = [profile dictionaryBySettingObject:@"" forKey:KEY_INITIAL_TEXT];
        profile = [profile dictionaryBySettingObject:@(iTermSessionEndActionClose)
                                              forKey:KEY_SESSION_END_ACTION];
        term.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenNone;
        profile = [profile dictionaryBySettingObject:@0 forKey:KEY_UNDO_TIMEOUT];

        [term asyncCreateTabWithProfile:profile
                            withCommand:nil
                            environment:nil
                               tabIndex:nil
                         didMakeSession:^(PTYSession *session) {
            session.shortLivedSingleUse = YES;
            session.isSingleUseSession = YES;
            if (data) {
                [session writeLatin1EncodedData:data broadcastAllowed:NO reporting:NO];
            }
            makeSessionCompletion(session);
        }
                             completion:nil];
    };
    [iTermSessionLauncher launchBookmark:profile
                              inTerminal:term
                                 withURL:nil
                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                 makeKey:YES
                             canActivate:YES
                      respectTabbingMode:NO
                                   index:nil
                                 command:nil
                             makeSession:makeSession
                          didMakeSession:^(PTYSession *session) { }
                              completion:^(PTYSession * _Nonnull session, BOOL ok) {
        if (completion) {
            completion(ok ? session : nil);
        }
    }];
    [term.window makeKeyAndOrderFront:nil];
    return term.window;
}

// This is meant for standalone command lines when used with DoNotEscape, like: man date || sleep 3
- (void)openSingleUseWindowWithCommand:(NSString *)rawCommand
                                inject:(NSData *)injection
                           environment:(NSDictionary *)environment
                                   pwd:(NSString *)initialPWD
                               options:(iTermSingleUseWindowOptions)options
                        didMakeSession:(void (^)(PTYSession *session))didMakeSession
                            completion:(void (^)(void))completion {
    NSMutableString *temp = [[rawCommand mutableCopy] autorelease];
    [temp escapeCharacters:@"\\\""];

    [self openSingleUseWindowWithCommand:temp
                               arguments:nil
                                  inject:injection
                             environment:environment
                                     pwd:initialPWD
                                 options:options
                          didMakeSession:didMakeSession
                              completion:completion];
}

- (void)openSingleUseWindowWithCommand:(NSString *)rawCommand
                             arguments:(NSArray<NSString *> *)arguments
                                inject:(NSData *)injection
                           environment:(NSDictionary *)environment
                                   pwd:(NSString *)initialPWD
                               options:(iTermSingleUseWindowOptions)options
                        didMakeSession:(void (^)(PTYSession *session))didMakeSession
                            completion:(void (^)(void))completion {
    if (!arguments && [rawCommand hasSuffix:@"&"] && rawCommand.length > 1) {
        rawCommand = [rawCommand substringToIndex:rawCommand.length - 1];
        system(rawCommand.UTF8String);
        if (didMakeSession) {
            didMakeSession(nil);
        }
        return;
    }

    MutableProfile *windowProfile = [[[self defaultBookmark] mutableCopy] autorelease];
    if ([windowProfile[KEY_WINDOW_TYPE] integerValue] == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN ||
        [windowProfile[KEY_WINDOW_TYPE] integerValue] == WINDOW_TYPE_LION_FULL_SCREEN) {
        windowProfile[KEY_WINDOW_TYPE] = @(iTermWindowDefaultType());
    }
    if (initialPWD) {
        windowProfile[KEY_WORKING_DIRECTORY] = initialPWD;
        windowProfile[KEY_CUSTOM_DIRECTORY] = @"Yes";
    }
    const BOOL bury = !!(options & iTermSingleUseWindowOptionsInitiallyBuried);
    const BOOL shortLived = !!(options & iTermSingleUseWindowOptionsShortLived);

    PseudoTerminal *term = nil;
    term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                             windowType:WINDOW_TYPE_ACCESSORY
                                        savedWindowType:WINDOW_TYPE_ACCESSORY
                                                 screen:-1
                                       hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                profile:windowProfile] autorelease];
    [self addTerminalWindow:term];

    NSString *command = [self shCommandLineWithCommand:rawCommand
                                             arguments:arguments ?: @[]
                                       escapeArguments:!(options & iTermSingleUseWindowOptionsDoNotEscapeArguments)];
    if (options & iTermSingleUseWindowOptionsCommandNotSwiftyString) {
        command = [command stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    }
    DLog(@"Open single-use window with command: %@", command);
    void (^makeSession)(Profile *, PseudoTerminal *, void (^)(PTYSession *)) =
    ^(Profile *profile, PseudoTerminal *term, void (^makeSessionCompletion)(PTYSession *))  {
        profile = [profile dictionaryBySettingObject:@"" forKey:KEY_INITIAL_TEXT];
        const BOOL closeSessionsOnEnd = !!(options & iTermSingleUseWindowOptionsCloseOnTermination);
        profile = [profile dictionaryBySettingObject:@(closeSessionsOnEnd ? iTermSessionEndActionClose : iTermSessionEndActionDefault)
                                              forKey:KEY_SESSION_END_ACTION];
        term.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenNone;
        if (shortLived) {
            profile = [profile dictionaryBySettingObject:@0 forKey:KEY_UNDO_TIMEOUT];
        }

        [term asyncCreateTabWithProfile:profile
                            withCommand:command
                            environment:environment
                               tabIndex:nil
                         didMakeSession:^(PTYSession *session) {
            if (shortLived) {
                session.shortLivedSingleUse = YES;
            }
            session.isSingleUseSession = YES;
            if (injection) {
                [session injectData:injection];
            }
            if (completion) {
                __block BOOL completionBlockRun = NO;
                [[NSNotificationCenter defaultCenter] addObserverForName:PTYSessionTerminatedNotification
                                                                  object:session
                                                                   queue:nil
                                                              usingBlock:^(NSNotification * _Nonnull note) {
                    if (completionBlockRun) {
                        return;
                    }
                    completionBlockRun = YES;
                    completion();
                }];
            }
            makeSessionCompletion(session);
        }
                             completion:nil];
    };
    [iTermSessionLauncher launchBookmark:windowProfile
                              inTerminal:term
                                 withURL:nil
                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                 makeKey:YES
                             canActivate:YES
                      respectTabbingMode:NO
                                   index:nil
                                 command:command
                             makeSession:makeSession
                          didMakeSession:^(PTYSession *session) {
        if (bury) {
            [session bury];
        }
        if (didMakeSession) {
            didMakeSession(session);
        }
    }
                              completion:nil];
}

#pragma mark - iTermSetCurrentTerminalHelperDelegate

- (void)reallySetCurrentTerminal:(PseudoTerminal *)thePseudoTerminal {
    DLog(@"Actually make terminal current: %@", thePseudoTerminal);
    _frontTerminalWindowController = thePseudoTerminal;

    // make sure this window is the key window
    if ([thePseudoTerminal windowInitialized] && [[thePseudoTerminal window] isKeyWindow] == NO) {
        [[thePseudoTerminal window] makeKeyAndOrderFront:self];
        if ([thePseudoTerminal fullScreen]) {
            [[iTermPresentationController sharedInstance] update];
        }
    }

    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:thePseudoTerminal
                                                      userInfo:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSnippetsTagsDidChange object:nil];
}

#pragma mark - iTermPresentationControllerDelegate

- (NSArray<id<iTermPresentationControllerManagedWindowController>> *)presentationControllerManagedWindows {
    return _terminalWindows;
}

@end

