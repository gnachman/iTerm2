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

#import "FutureMethods.h"
#import "HotkeyWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSStringITerm.h"
#import "NSView+RecursiveDescription.h"
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
#import "iTermGrowlDelegate.h"
#import "iTermGrowlDelegate.h"
#import "iTermKeyBindingMgr.h"
#import "iTermPreferences.h"
#import "iTermRestorableSession.h"
#import "iTermWarning.h"
#include <objc/runtime.h>

@interface NSApplication (Undocumented)
- (void)_cycleWindowsReversed:(BOOL)back;
@end

// Constants for saved window arrangement key names.
static NSString* APPLICATION_SUPPORT_DIRECTORY = @"~/Library/Application Support";
static NSString *SUPPORT_DIRECTORY = @"~/Library/Application Support/iTerm";
static NSString *SCRIPT_DIRECTORY = @"~/Library/Application Support/iTerm/Scripts";

// Pref keys
static NSString *const kSelectionRespectsSoftBoundariesKey = @"Selection Respects Soft Boundaries";

static BOOL UncachedIsMavericksOrLater(void) {
    unsigned major;
    unsigned minor;
    if ([iTermController getSystemVersionMajor:&major minor:&minor bugFix:nil]) {
        return (major == 10 && minor >= 9) || (major > 10);
    } else {
        return NO;
    }
}

BOOL IsMavericksOrLater(void) {
    static BOOL result;
    static BOOL initialized;
    if (!initialized) {
        initialized = YES;
        result = UncachedIsMavericksOrLater();
    }
    return result;
}

static BOOL UncachedIsYosemiteOrLater(void) {
    unsigned major;
    unsigned minor;
    if ([iTermController getSystemVersionMajor:&major minor:&minor bugFix:nil]) {
        return (major == 10 && minor >= 10) || (major > 10);
    } else {
        return NO;
    }
}

BOOL IsYosemiteOrLater(void) {
    static BOOL result;
    static BOOL initialized;
    if (!initialized) {
        initialized = YES;
        result = UncachedIsYosemiteOrLater();
    }
    return result;
}


@implementation iTermController {
    NSMutableArray *_restorableSessions;
    NSMutableArray *_currentRestorableSessionsStack;

    // PseudoTerminal objects
    NSMutableArray *terminalWindows;
    id FRONT;
    ItermGrowlDelegate *gd;

    int keyWindowIndexMemo_;

    // For restoring previously active app when exiting hotkey window
    NSNumber *previouslyActiveAppPID_;
    id runningApplicationClass_;
}

static iTermController* shared = nil;
static BOOL initDone = NO;

+ (iTermController*)sharedInstance
{
    if (!shared && !initDone) {
        shared = [[iTermController alloc] init];
        initDone = YES;
    }

    return shared;
}

+ (void)sharedInstanceRelease {
    [shared release];
    shared = nil;
}

- (id)init {
    self = [super init];

    if (self) {
        UKCrashReporterCheckForCrash();

        runningApplicationClass_ = NSClassFromString(@"NSRunningApplication"); // 10.6
        // create the iTerm directory if it does not exist
        NSFileManager *fileManager = [NSFileManager defaultManager];

        // create the "~/Library/Application Support" directory if it does not exist
        if ([fileManager fileExistsAtPath:[APPLICATION_SUPPORT_DIRECTORY stringByExpandingTildeInPath]] == NO) {
            [fileManager createDirectoryAtPath:[APPLICATION_SUPPORT_DIRECTORY stringByExpandingTildeInPath]
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:nil];
        }

        if ([fileManager fileExistsAtPath:[SUPPORT_DIRECTORY stringByExpandingTildeInPath]] == NO) {
            [fileManager createDirectoryAtPath:[SUPPORT_DIRECTORY stringByExpandingTildeInPath]
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:nil];
        }

        terminalWindows = [[NSMutableArray alloc] init];
        keyWindowIndexMemo_ = -1;
        _restorableSessions = [[NSMutableArray alloc] init];
        _currentRestorableSessionsStack = [[NSMutableArray alloc] init];
        // Activate Growl
        /*
         * Need to add routine in iTerm prefs for Growl support and
         * PLIST check here.
         */
        gd = [iTermGrowlDelegate sharedInstance];
    }

    return (self);
}

- (BOOL)willRestoreWindowsAtNextLaunch {
  return (![iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup] &&
          ![iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup] &&
          [[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"]);
}

- (BOOL)shouldLeaveSessionsRunningOnQuit {
    const BOOL sessionsWillRestore = ([iTermAdvancedSettingsModel runJobsInServers] &&
                                      [iTermAdvancedSettingsModel restoreWindowContents] &&
                                      self.willRestoreWindowsAtNextLaunch);
    iTermApplicationDelegate *itad =
        (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
    return (sessionsWillRestore &&
            (itad.sparkleRestarting || ![iTermAdvancedSettingsModel killJobsInServersOnQuit]));
}

- (void)dealloc {
    // Save hotkey window arrangement to user defaults before closing it.
    [[HotkeyWindowController sharedInstance] saveHotkeyWindowState];

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
        [terminalWindows autorelease];
    } else {
        // Close all terminal windows, killing jobs.
        while ([terminalWindows count] > 0) {
            [[terminalWindows objectAtIndex:0] close];
        }
        NSAssert([terminalWindows count] == 0, @"Expected terminals to be gone");
        [terminalWindows release];
    }

    // Release the GrowlDelegate
    if (gd) {
        [gd release];
    }
    [previouslyActiveAppPID_ release];
    [_restorableSessions release];
    [_currentRestorableSessionsStack release];
    [super dealloc];
}

- (PseudoTerminal*)keyTerminalWindow
{
    for (PseudoTerminal* pty in [self terminals]) {
        if ([[pty window] isKeyWindow]) {
            return pty;
        }
    }
    return nil;
}

- (void)updateWindowTitles
{
    for (PseudoTerminal* terminal in terminalWindows) {
        if ([terminal currentSessionName]) {
            [terminal setWindowTitle];
        }
    }
}

- (BOOL)haveTmuxConnection
{
    return [self anyTmuxSession] != nil;
}

- (PTYSession *)anyTmuxSession
{
    for (PseudoTerminal* terminal in terminalWindows) {
        for (PTYSession *session in [terminal allSessions]) {
            if ([session isTmuxClient] || [session isTmuxGateway]) {
                return session;
            }
        }
    }
    return nil;
}

// Action methods
- (IBAction)newWindow:(id)sender
{
    [self newWindow:sender possiblyTmux:NO];
}

- (void)newWindow:(id)sender possiblyTmux:(BOOL)possiblyTmux
{
    if (possiblyTmux &&
        FRONT &&
        [[FRONT currentSession] isTmuxClient]) {
        [FRONT newTmuxWindow:sender];
    } else {
        [self launchBookmark:nil inTerminal:nil];
    }
}

- (void)newSessionInTabAtIndex:(id)sender
{
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self launchBookmark:bookmark inTerminal:FRONT];
    }
}

- (BOOL)terminalIsObscured:(id<iTermWindowController>)terminal {
    BOOL windowIsObscured = NO;
    NSWindow *window = [terminal window];
    // occlusionState is new in 10.9.
    if ([window respondsToSelector:@selector(occlusionState)]) {
        NSWindowOcclusionState occlusionState = window.occlusionState;
        // The occlusionState tells if you if you're on another space or another app's window is
        // occluding yours, but for some reason one terminal window can occlude another without
        // it noticing, so we compute that ourselves.
        windowIsObscured = !(occlusionState & NSWindowOcclusionStateVisible);
    } else {
        // Use a very rough approximation. Users who complain should upgrade to 10.9.
        windowIsObscured = !window.isOnActiveSpace;
    }
    if (!windowIsObscured) {
        // Try to refine the guess by seeing if another terminal is covering this one.
        static const double kOcclusionThreshold = 0.4;
        if ([(PTYWindow *)terminal.window approximateFractionOccluded] > kOcclusionThreshold) {
            windowIsObscured = YES;
        }
    }
    return windowIsObscured;
}

- (int)keyWindowIndexMemo
{
    return keyWindowIndexMemo_;
}

- (void)setKeyWindowIndexMemo:(int)i
{
    keyWindowIndexMemo_ = i;
}

- (void)newSessionInWindowAtIndex:(id)sender
{
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self launchBookmark:bookmark inTerminal:nil];
    }
}

// meant for action for menu items that have a submenu
- (void)noAction:(id)sender
{
}

- (void)newSessionWithSameProfile:(id)sender {
    Profile *bookmark = nil;
    if (FRONT) {
        bookmark = [[FRONT currentSession] profile];
    }
    [self launchBookmark:bookmark inTerminal:FRONT];
}

// Launch a new session using the default profile. If the current session is
// tmux and possiblyTmux is true, open a new tmux session.
- (void)newSession:(id)sender possiblyTmux:(BOOL)possiblyTmux {
    DLog(@"newSession:%@ possiblyTmux:%d from %@",
         sender, (int)possiblyTmux, [NSThread callStackSymbols]);
    if (possiblyTmux &&
        FRONT &&
        [[FRONT currentSession] isTmuxClient]) {
        [FRONT newTmuxTab:sender];
    } else {
        [self launchBookmark:nil inTerminal:FRONT];
    }
}

- (NSArray *)terminalsSortedByNumber {
    return [terminalWindows sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [@([obj1 number]) compare:@([obj2 number])];
    }];
}

- (IBAction)previousTerminal:(id)sender {
    NSArray *windows = [self terminalsSortedByNumber];
    if (windows.count < 2) {
        return;
    }
    NSUInteger index = [windows indexOfObject:FRONT];
    if (index == NSNotFound) {
        DLog(@"Index of terminal not found, so cycle.");
        [NSApp _cycleWindowsReversed:YES];
    } else {
        int i = index;
        i += terminalWindows.count - 1;
        [[windows[i % windows.count] window] makeKeyAndOrderFront:nil];
    }
}

- (IBAction)nextTerminal:(id)sender {
    NSArray *windows = [self terminalsSortedByNumber];
    if (windows.count < 2) {
        return;
    }
    NSUInteger index = [windows indexOfObject:FRONT];
    if (index == NSNotFound) {
        DLog(@"Index of terminal not found, so cycle.");
        [NSApp _cycleWindowsReversed:NO];
    } else {
        int i = index;
        i++;
        [[windows[i % windows.count] window] makeKeyAndOrderFront:nil];
    }
}

- (NSString *)_showAlertWithText:(NSString *)prompt defaultInput:(NSString *)defaultValue {
    NSAlert *alert = [NSAlert alertWithMessageText:prompt
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];

    NSTextField *input = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)] autorelease];
    [input setStringValue:defaultValue];
    [alert setAccessoryView:input];
    [alert layout];
    [[alert window] makeFirstResponder:input];
    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        [input validateEditing];
        return [input stringValue];
    } else if (button == NSAlertAlternateReturn) {
        return nil;
    } else {
        NSAssert1(NO, @"Invalid input dialog button %d", (int) button);
        return nil;
    }
}

- (void)saveWindowArrangement:(BOOL)allWindows {
    NSString *name = [self _showAlertWithText:@"Name for saved window arrangement:"
                                 defaultInput:[NSString stringWithFormat:@"Arrangement %d", 1+[WindowArrangements count]]];
    if (!name) {
        return;
    }
    if ([WindowArrangements hasWindowArrangement:name]) {
        if (NSRunAlertPanel(@"Replace Existing Saved Window Arrangement?",
                            @"There is an existing saved window arrangement with this name. Would you like to replace it with the current arrangement?",
                            @"Yes",
                            @"No",
                            nil) != NSAlertDefaultReturn) {
            return;
        }
    }
    NSMutableArray* terminalArrangements = [NSMutableArray arrayWithCapacity:[terminalWindows count]];
    if (allWindows) {
        for (PseudoTerminal* terminal in terminalWindows) {
            if (![terminal isHotKeyWindow]) {
                [terminalArrangements addObject:[terminal arrangement]];
            }
        }
    } else {
        PseudoTerminal *currentTerminal = [self currentTerminal];
        if (!currentTerminal) {
            return;
        }
        [terminalArrangements addObject:[currentTerminal arrangement]];
    }
    [WindowArrangements setArrangement:terminalArrangements withName:name];
}

- (void)tryOpenArrangement:(NSDictionary *)terminalArrangement {
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
        PseudoTerminal* term = [PseudoTerminal terminalWithArrangement:terminalArrangement];
        if (term) {
          [self addTerminalWindow:term];
        }
    }
}

- (void)loadWindowArrangementWithName:(NSString *)theName
{
    NSArray* terminalArrangements = [WindowArrangements arrangementWithName:theName];
    if (terminalArrangements) {
        for (NSDictionary* terminalArrangement in terminalArrangements) {
            [self tryOpenArrangement:terminalArrangement];
        }
    }
}

// Return all the terminals in the given screen.
- (NSArray*)_terminalsInScreen:(NSScreen*)screen
{
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:0];
    for (PseudoTerminal* term in terminalWindows) {
        if (![term isHotKeyWindow] &&
            [[term window] deepestScreen] == screen) {
            [result addObject:term];
        }
    }
    return result;
}

// Arrange terminals horizontally, in multiple rows if needed.
- (void)arrangeTerminals:(NSArray*)terminals inFrame:(NSRect)frame
{
    if ([terminals count] == 0) {
        return;
    }

    // Determine the new width for all windows, not less than some minimum.
    int x = frame.origin.x;
    int w = frame.size.width / [terminals count];
    int minWidth = 400;
    for (PseudoTerminal* term in terminals) {
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
    for (PseudoTerminal* terminal in terminals) {
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
            PseudoTerminal* t = [terminalsCopy objectAtIndex:j];
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
        NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:3];

        [dict setObject:[terminal window] forKey:NSViewAnimationTargetKey];
        [dict setObject:[NSValue valueWithRect:[[terminal window] frame]]
                 forKey:NSViewAnimationStartFrameKey];
        int y = highestTop - [[terminal window] frame].size.height;
        int h = MIN(maxHeight, [[terminal window] frame].size.height);
        if (rows > 1) {
            // The first row can be a bit ragged vertically but subsequent rows line up
            // at the tops of the windows.
            y = frame.origin.y + frame.size.height - h;
        }
        [dict setObject:[NSValue valueWithRect:NSMakeRect(x,
                                                          y + yOffset,
                                                          w,
                                                          h)]
                 forKey:NSViewAnimationEndFrameKey];
        x += w;
        if (x > frame.size.width + frame.origin.x - w) {
            // Wrap around to the next row of windows.
            x = frame.origin.x;
            yOffset -= maxHeight;
        }
        NSViewAnimation* theAnim = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObjects:dict, nil]];

        // Set some additional attributes for the animation.
        [theAnim setDuration:0.75];
        [theAnim setAnimationCurve:NSAnimationEaseInOut];

        // Run the animation.
        [theAnim startAnimation];

        // The animation has finished, so go ahead and release it.
        [theAnim release];
    }
}

- (void)arrangeHorizontally
{
    [iTermExpose exitIfActive];

    // Un-full-screen each window. This is done in two steps because
    // toggleFullScreenMode deallocs self.
    PseudoTerminal* waitFor = nil;
    for (PseudoTerminal* t in terminalWindows) {
        if ([t anyFullScreen]) {
            if ([t lionFullScreen]) {
                waitFor = t;
            }
            [t toggleFullScreenMode:self];
        }
    }

    if (waitFor) {
        [self performSelector:@selector(arrangeHorizontally) withObject:nil afterDelay:0.5];
        return;
    }

    // For each screen, find the terminals in it and arrange them. This way
    // terminals don't move from screen to screen in this operation.
    for (NSScreen* screen in [NSScreen screens]) {
        [self arrangeTerminals:[self _terminalsInScreen:screen]
                       inFrame:[screen visibleFrame]];
    }
    for (PseudoTerminal* t in terminalWindows) {
        [[t window] orderFront:nil];
    }
}

- (PTYSession *)sessionWithMostRecentSelection
{
    NSTimeInterval latest = 0;
    PTYSession *best = nil;
    for (PseudoTerminal *term in [self terminals]) {
        PTYTab *aTab = [term currentTab];
        for (PTYSession *aSession in [aTab sessions]) {
            NSTimeInterval current = [[aSession textview] selectionTime];
            if (current > latest) {
                latest = current;
                best = aSession;
            }
        }
    }
    return best;
}

- (PseudoTerminal*)currentTerminal
{
    return FRONT;
}

- (void)terminalWillClose:(PseudoTerminal*)theTerminalWindow
{
    if ([theTerminalWindow isHotKeyWindow]) {
        [[iTermController sharedInstance] restorePreviouslyActiveApp];
    }
    if (FRONT == theTerminalWindow) {
        [self setCurrentTerminal:nil];
    }
    if (theTerminalWindow) {
        [self removeTerminalWindow:theTerminalWindow];
    }
}

- (void)storePreviouslyActiveApp
{
    NSDictionary *activeAppDict = [[NSWorkspace sharedWorkspace] activeApplication];
    [previouslyActiveAppPID_ release];
    previouslyActiveAppPID_ = nil;
    if (![[activeAppDict objectForKey:@"NSApplicationBundleIdentifier"] isEqualToString:@"com.googlecode.iterm2"]) {
        previouslyActiveAppPID_ = [[activeAppDict objectForKey:@"NSApplicationProcessIdentifier"] copy];
    }
}

- (void)restorePreviouslyActiveApp
{
    if (!previouslyActiveAppPID_) {
        return;
    }

    id app;
    // NSInvocation hackery because we need to build against the 10.5 sdk and call a
    // 10.6 function.

    // app = [runningApplicationClass_ runningApplicationWithProcessIdentifier:[previouslyActiveAppPID_ intValue]];
    NSMethodSignature *sig = [object_getClass(runningApplicationClass_) instanceMethodSignatureForSelector:@selector(runningApplicationWithProcessIdentifier:)];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:runningApplicationClass_];
    [inv setSelector:@selector(runningApplicationWithProcessIdentifier:)];
    int appId = [previouslyActiveAppPID_ intValue];
    [inv setArgument:&appId atIndex:2];
    [inv invoke];
    [inv getReturnValue:&app];

    if (app) {
        DLog(@"Restore app %@", app);
        //[app activateWithOptions:0];
        sig = [[app class] instanceMethodSignatureForSelector:@selector(activateWithOptions:)];
        assert(sig);
        inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:app];
        [inv setSelector:@selector(activateWithOptions:)];
        int opts = 0;
        [inv setArgument:&opts atIndex:2];
        [inv invoke];
    }
    [previouslyActiveAppPID_ release];
    previouslyActiveAppPID_ = nil;
}

- (void)_addBookmark:(Profile*)bookmark
              toMenu:(NSMenu*)aMenu
              target:(id)aTarget
       withShortcuts:(BOOL)withShortcuts
            selector:(SEL)selector
   alternateSelector:(SEL)alternateSelector
{
    NSMenuItem* aMenuItem = [[NSMenuItem alloc] initWithTitle:[bookmark objectForKey:KEY_NAME]
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
            openAllSelector:(SEL)openAllSelector
{
    NSMenuItem* aMenuItem = [[NSMenuItem alloc] initWithTitle:tag action:@selector(noAction:) keyEquivalent:@""];
    NSMenu* subMenu = [[[NSMenu alloc] init] autorelease];
    int count = 0;
    int MAX_MENU_ITEMS = 100;
    if ([tag isEqualToString:@"bonjour"]) {
        MAX_MENU_ITEMS = 50;
    }
    for (int i = 0; i < [[ProfileModel sharedInstance] numberOfBookmarks]; ++i) {
        Profile* bookmark = [[ProfileModel sharedInstance] profileAtIndex:i];
        NSArray* tags = [bookmark objectForKey:KEY_TAGS];
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

- (PseudoTerminal *)terminalWithTab:(PTYTab *)tab
{
    for (PseudoTerminal *term in [self terminals]) {
        if ([[term tabs] containsObject:tab]) {
            return term;
        }
    }
    return nil;
}

- (PseudoTerminal *)terminalWithSession:(PTYSession *)session
{
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

- (void)openNewSessionsFromMenu:(NSMenu*)theMenu inNewWindow:(BOOL)newWindow
{
    NSArray *bookmarks = [self bookmarksInMenu:theMenu];
    static const int kWarningThreshold = 10;
    if ([bookmarks count] > kWarningThreshold) {
        if (![self shouldOpenManyProfiles:bookmarks.count]) {
            return;
        }
    }

    PseudoTerminal* term = newWindow ? nil : [self currentTerminal];
    for (Profile* bookmark in bookmarks) {
        if (!term) {
            PTYSession* session = [self launchBookmark:bookmark inTerminal:nil];
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
    for (NSMenuItem* item in [parent itemArray]) {
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
            NSMenu* sub = [item submenu];
            [self getBookmarksInMenu:sub
                           usedGuids:usedGuids
                           bookmarks:bookmarks];
        }
    }
}

- (void)newSessionsInWindow:(id)sender
{
    [self openNewSessionsFromMenu:[sender menu] inNewWindow:[sender isAlternate]];
}

- (void)newSessionsInNewWindow:(id)sender
{
    [self openNewSessionsFromMenu:[sender menu] inNewWindow:YES];
}

- (void)addBookmarksToMenu:(NSMenu *)aMenu
              withSelector:(SEL)selector
           openAllSelector:(SEL)openAllSelector
                startingAt:(int)startingAt
{
    JournalParams params;
    params.selector = selector;
    params.openAllSelector = openAllSelector;
    params.alternateSelector = @selector(newSessionInWindowAtIndex:);
    params.alternateOpenAllSelector = @selector(newSessionsInWindow:);
    params.target = self;

    ProfileModel* bm = [ProfileModel sharedInstance];
    int N = [bm numberOfBookmarks];
    for (int i = 0; i < N; i++) {
        Profile* b = [bm profileAtIndex:i];
        [bm addBookmark:b
                 toMenu:aMenu
         startingAtItem:startingAt
               withTags:[b objectForKey:KEY_TAGS]
                 params:&params
                  atPos:i];
    }
}

- (void)irAdvance:(int)dir
{
    [FRONT irAdvance:dir];
}

+ (void)switchToSpaceInBookmark:(Profile*)aDict
{
    if ([aDict objectForKey:KEY_SPACE]) {
        int spaceNum = [[aDict objectForKey:KEY_SPACE] intValue];
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
        }
    }
}

- (int)windowTypeForBookmark:(Profile*)aDict
{
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

- (void)reloadAllBookmarks
{
    int n = [self numberOfTerminals];
    for (int i = 0; i < n; ++i) {
        PseudoTerminal* pty = [self terminalAtIndex:i];
        [pty reloadBookmarks];
    }
}


- (Profile *)defaultBookmark
{
    Profile *aDict = [[ProfileModel sharedInstance] defaultBookmark];
    if (!aDict) {
        NSMutableDictionary* temp = [[[NSMutableDictionary alloc] init] autorelease];
        [ITAddressBookMgr setDefaultsInBookmark:temp];
        [temp setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        aDict = temp;
    }
    return aDict;
}

- (PseudoTerminal *)openWindow
{
    Profile *bookmark = [self defaultBookmark];
    [iTermController switchToSpaceInBookmark:bookmark];
    PseudoTerminal *term;
    term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                             windowType:WINDOW_TYPE_NORMAL
                                        savedWindowType:WINDOW_TYPE_NORMAL
                                                 screen:[bookmark objectForKey:KEY_SCREEN] ? [[bookmark objectForKey:KEY_SCREEN] intValue] : -1
                                               isHotkey:NO] autorelease];
    if ([[bookmark objectForKey:KEY_HIDE_AFTER_OPENING] boolValue]) {
        [term hideAfterOpening];
    }
    [self addTerminalWindow:term];
    return term;
}

- (PTYSession *)launchBookmark:(NSDictionary *)bookmarkData inTerminal:(PseudoTerminal *)theTerm {
    return [self launchBookmark:bookmarkData
                     inTerminal:theTerm
                        withURL:nil
                       isHotkey:NO
                        makeKey:YES
                        command:nil
                          block:nil];
}

- (NSDictionary *)profile:(NSDictionary *)aDict
        modifiedToOpenURL:(NSString *)url
            forObjectType:(iTermObjectType)objectType
{
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
            if ([urlRep user]) {
                [tempString appendFormat:@"-l %@ ", [urlRep user]];
            }
            if ([urlRep port]) {
                [tempString appendFormat:@"-p %@ ", [urlRep port]];
            }
            if ([urlRep host]) {
                [tempString appendString:[urlRep host]];
            }
            [tempDict setObject:tempString forKey:KEY_COMMAND];
            [tempDict setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
            aDict = tempDict;
        } else if ([urlType compare:@"ftp" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithFormat:@"ftp %@", url];
            [tempDict setObject:tempString forKey:KEY_COMMAND];
            [tempDict setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
            aDict = tempDict;
        } else if ([urlType compare:@"telnet" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithString:@"telnet "];
            if ([urlRep user]) {
                [tempString appendFormat:@"-l %@ ", [urlRep user]];
            }
            if ([urlRep host]) {
                [tempString appendString:[urlRep host]];
                if ([urlRep port]) [tempString appendFormat:@" %@", [urlRep port]];
            }
            [tempDict setObject:tempString forKey:KEY_COMMAND];
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
                      isHotkey:(BOOL)isHotkey
                       makeKey:(BOOL)makeKey
                       command:(NSString *)command
                         block:(PTYSession *(^)(PseudoTerminal *))block {
    PseudoTerminal *term;
    NSDictionary *aDict;
    const iTermObjectType objectType = theTerm ? iTermTabObject : iTermWindowObject;

    aDict = bookmarkData;
    if (aDict == nil) {
        aDict = [self defaultBookmark];
    }

    if (url) {
        // Automatically fill in ssh command if command is exactly equal to $$ or it's a login shell.
        aDict = [self profile:aDict modifiedToOpenURL:url forObjectType:objectType];
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
            term = theTerm;
            [term finishInitializationWithSmartLayout:YES
                                           windowType:windowType
                                      savedWindowType:WINDOW_TYPE_NORMAL
                                               screen:[aDict objectForKey:KEY_SCREEN] ? [[aDict objectForKey:KEY_SCREEN] intValue] : -1
                                             isHotkey:isHotkey];
        } else {
            term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                                     windowType:windowType
                                                savedWindowType:WINDOW_TYPE_NORMAL
                                                         screen:[aDict objectForKey:KEY_SCREEN] ? [[aDict objectForKey:KEY_SCREEN] intValue] : -1
                                                       isHotkey:isHotkey] autorelease];
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
        term = theTerm;
    }

    PTYSession* session = nil;

    if (block) {
        session = block(term);
    } else if (url) {
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
        [NSApp activateIgnoringOtherApps:YES];
        [[term window] makeKeyAndOrderFront:nil];
        [NSApp arrangeInFront:self];
    }

    return session;
}

- (void)launchScript:(id)sender {
    NSString *fullPath = [NSString stringWithFormat:@"%@/%@", [SCRIPT_DIRECTORY stringByExpandingTildeInPath], [sender title]];

    if ([[[sender title] pathExtension] isEqualToString:@"scpt"]) {
        NSAppleScript *script;
        NSDictionary *errorInfo = nil;
        NSURL *aURL = [NSURL fileURLWithPath:fullPath];

        // Make sure our script suite registry is loaded
        [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

        script = [[NSAppleScript alloc] initWithContentsOfURL:aURL error:&errorInfo];
        if (script) {
            [script executeAndReturnError:&errorInfo];
            if (errorInfo) {
                [self showAlertForScript:fullPath error:errorInfo];
            }
            [script release];
        } else {
            [self showAlertForScript:fullPath error:errorInfo];
        }
    } else {
        [[NSWorkspace sharedWorkspace] launchApplication:fullPath];
    }

}

- (void)showAlertForScript:(NSString *)fullPath error:(NSDictionary *)errorInfo {
    NSValue *range = errorInfo[NSAppleScriptErrorRange];
    NSString *location = @"Location of error not known.";
    if (range) {
        location = [NSString stringWithFormat:@"The error starts at byte %d of the script.",
                    (int)[range rangeValue].location];
    }
    NSAlert *alert = [NSAlert alertWithMessageText:@"Error running script"
                                     defaultButton:@"OK"
                                   alternateButton:nil
                                       otherButton:nil
                         informativeTextWithFormat:@"Script at \"%@\" failed.\n\nThe error was: \"%@\"\n\n%@",
                      fullPath, errorInfo[NSAppleScriptErrorMessage], location];
    [alert runModal];
}

- (PTYTextView *)frontTextView
{
    return ([[FRONT currentSession] textview]);
}

-(int)numberOfTerminals
{
    return [terminalWindows count];
}

- (NSUInteger)indexOfTerminal:(PseudoTerminal*)terminal
{
    return [terminalWindows indexOfObject:terminal];
}

-(PseudoTerminal*)terminalAtIndex:(int)i
{
    return [terminalWindows objectAtIndex:i];
}

- (int)allocateWindowNumber
{
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

- (PseudoTerminal*)terminalWithNumber:(int)n
{
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

// http://cocoadev.com/DeterminingOSVersion
+ (BOOL)getSystemVersionMajor:(unsigned int *)major
                        minor:(unsigned int *)minor
                       bugFix:(unsigned int *)bugFix {
    NSDictionary *version = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    NSString *productVersion = [version objectForKey:@"ProductVersion"];
    DLog(@"product version is %@", productVersion);
    NSArray *parts = [productVersion componentsSeparatedByString:@"."];
    if (parts.count == 0) {
        return NO;
    }
    if (major) {
        *major = [[parts objectAtIndex:0] intValue];
        if (*major < 10) {
            return NO;
        }
    }
    if (minor) {
        *minor = 0;
        if (parts.count > 1) {
            *minor = [[parts objectAtIndex:1] intValue];
        }
    }
    if (bugFix) {
        *bugFix = 0;
        if (parts.count > 2) {
            *bugFix = [[parts objectAtIndex:2] intValue];
        }
    }
    return YES;
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
    [[NSUserDefaults standardUserDefaults] setObject:appCast forKey:@"SUFeedURL"];
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
        [_restorableSessions addObject:session];
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
            [aSession.shell sendSignal:SIGHUP];
        }
    }
}

// accessors for to-many relationships:
- (NSArray*)terminals {
    return (terminalWindows);
}

- (void)setCurrentTerminal:(PseudoTerminal *)thePseudoTerminal {
    FRONT = thePseudoTerminal;

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
    if ([terminalWindows containsObject:terminalWindow] == YES) {
        return;
    }

    [terminalWindows addObject:terminalWindow];
    [self updateWindowTitles];
}

- (void)removeTerminalWindow:(PseudoTerminal *)terminalWindow {
    [terminalWindows removeObject:terminalWindow];
    [self updateWindowTitles];
}

@end

