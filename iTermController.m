// -*- mode:objc -*-
// $Id: iTermController.m,v 1.78 2008-10-17 04:02:45 yfabian Exp $
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

// Debug option
#define DEBUG_ALLOC           0
#define DEBUG_METHOD_TRACE    0

#import "iTermController.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "VT100Screen.h"
#import "NSStringITerm.h"
#import "ITAddressBookMgr.h"
#import <iTermGrowlDelegate.h>
#import "PasteboardHistory.h"
#import <Carbon/Carbon.h>
#import "iTermApplicationDelegate.h"
#import "iTermApplication.h"
#import "UKCrashReporter/UKCrashReporter.h"
#import "PTYTab.h"
#import "iTermKeyBindingMgr.h"
#import "PseudoTerminal.h"
#import "iTermExpose.h"
#import "FutureMethods.h"
#import "GTMCarbonEvent.h"
#import "iTerm.h"
#import "WindowArrangements.h"
#import "NSView+iTerm.h"

//#define HOTKEY_WINDOW_VERBOSE_LOGGING
#ifdef HOTKEY_WINDOW_VERBOSE_LOGGING
#define HKWLog NSLog
#else
#define HKWLog(args...) \
do { \
if (gDebugLogging) { \
DebugLog([NSString stringWithFormat:args]); \
} \
} while (0)
#endif

@interface NSApplication (Undocumented)
- (void)_cycleWindowsReversed:(BOOL)back;
@end

// Constants for saved window arrangement key names.
static NSString* APPLICATION_SUPPORT_DIRECTORY = @"~/Library/Application Support";
static NSString *SUPPORT_DIRECTORY = @"~/Library/Application Support/iTerm";
static NSString *SCRIPT_DIRECTORY = @"~/Library/Application Support/iTerm/Scripts";

// Comparator for sorting encodings
static NSInteger _compareEncodingByLocalizedName(id a, id b, void *unused)
{
    NSString *sa = [NSString localizedNameOfStringEncoding:[a unsignedIntValue]];
    NSString *sb = [NSString localizedNameOfStringEncoding:[b unsignedIntValue]];
    return [sa caseInsensitiveCompare:sb];
}

static BOOL UncachedIsMountainLionOrLater(void) {
    unsigned major;
    unsigned minor;
    if ([iTermController getSystemVersionMajor:&major minor:&minor bugFix:nil]) {
        return (major == 10 && minor >= 8) || (major > 10);
    } else {
        return NO;
    }
}

BOOL IsMountainLionOrLater(void) {
    static BOOL result;
    static BOOL initialized;
    if (!initialized) {
        initialized = YES;
        result = UncachedIsMountainLionOrLater();
    }
    return result;
}

static BOOL UncachedIsLionOrLater(void) {
    unsigned major;
    unsigned minor;
    if ([iTermController getSystemVersionMajor:&major minor:&minor bugFix:nil]) {
        return (major == 10 && minor >= 7) || (major > 10);
    } else {
        return NO;
    }
}

BOOL IsLionOrLater(void) {
    static BOOL result;
    static BOOL initialized;
    if (!initialized) {
        initialized = YES;
        result = UncachedIsLionOrLater();
    }
    return result;
}

BOOL IsSnowLeopardOrLater(void) {
    unsigned major;
    unsigned minor;
    if ([iTermController getSystemVersionMajor:&major minor:&minor bugFix:nil]) {
        return (major == 10 && minor >= 6) || (major > 10);
    } else {
        return NO;
    }
}

BOOL IsLeopard(void) {
    unsigned major;
    unsigned minor;
    if ([iTermController getSystemVersionMajor:&major minor:&minor bugFix:nil]) {
        return (major == 10 && minor == 5);
    } else {
        return NO;
    }
}

@interface iTermController ()
- (void)restorePreviouslyActiveApp;
@end

@implementation iTermController

static iTermController* shared = nil;
static BOOL initDone = NO;

+ (iTermController*)sharedInstance;
{
    if(!shared && !initDone) {
        shared = [[iTermController alloc] init];
        initDone = YES;
    }

    return shared;
}

+ (void)sharedInstanceRelease
{
    [shared release];
    shared = nil;
}

// init
- (id)init
{
#if DEBUG_ALLOC
    NSLog(@"%s(%d):-[iTermController init]",
          __FILE__, __LINE__);
#endif
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

        // Activate Growl
        /*
         * Need to add routine in iTerm prefs for Growl support and
         * PLIST check here.
         */
        gd = [iTermGrowlDelegate sharedInstance];
    }

    return (self);
}

- (void)dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s(%d):-[iTermController dealloc]",
        __FILE__, __LINE__);
#endif
    // Close all terminal windows
    while ([terminalWindows count] > 0) {
        [[terminalWindows objectAtIndex:0] close];
    }
    NSAssert([terminalWindows count] == 0, @"Expected terminals to be gone");
    [terminalWindows release];

    // Release the GrowlDelegate
    if (gd) {
        [gd release];
    }
    [previouslyActiveAppPID_ release];

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

- (void)showHideFindBar
{
    [[[self currentTerminal] currentSession] toggleFind];
}

- (int)keyWindowIndexMemo
{
    return keyWindowIndexMemo_;
}

- (void)setKeyWindowIndexMemo:(int)i
{
    keyWindowIndexMemo_ = i;
}

- (void)newSessionInWindowAtIndex:(id) sender
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

- (IBAction)newSessionWithSameProfile:(id)sender
{
    Profile *bookmark = nil;
    if (FRONT) {
        bookmark = [[FRONT currentSession] addressBookEntry];
    }
    [self launchBookmark:bookmark inTerminal:FRONT];
}

- (IBAction)newSession:(id)sender
{
    DLog(@"iTermController newSession:");
    [self newSession:sender possiblyTmux:NO];
}

// Launch a new session using the default profile. If the current session is
// tmux and possiblyTmux is true, open a new tmux session.
- (void)newSession:(id)sender possiblyTmux:(BOOL)possiblyTmux
{
    DLog(@"newSession:%@ possiblyTmux:%d from %@", sender, (int)possiblyTmux, [NSThread callStackSymbols]);
    if (possiblyTmux &&
        FRONT &&
        [[FRONT currentSession] isTmuxClient]) {
        [FRONT newTmuxTab:sender];
    } else {
        [self launchBookmark:nil inTerminal:FRONT];
    }
}

// navigation
- (IBAction)previousTerminal:(id)sender
{
    [NSApp _cycleWindowsReversed:YES];
}
- (IBAction)nextTerminal:(id)sender
{
    [NSApp _cycleWindowsReversed:NO];
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
        NSAssert1(NO, @"Invalid input dialog button %d", button);
        return nil;
    }
}

- (void)saveWindowArrangement
{
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
    for (PseudoTerminal* terminal in terminalWindows) {
        if (![terminal isHotKeyWindow]) {
            [terminalArrangements addObject:[terminal arrangement]];
        }
    }

    [WindowArrangements setArrangement:terminalArrangements withName:name];
}

- (void)loadWindowArrangementWithName:(NSString *)theName
{
    NSArray* terminalArrangements = [WindowArrangements arrangementWithName:theName];
    if (terminalArrangements) {
        for (NSDictionary* terminalArrangement in terminalArrangements) {
            PseudoTerminal* term = [PseudoTerminal terminalWithArrangement:terminalArrangement];
            [self addInTerminals:term];
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
        if (x > frame.size.width - w) {
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
            NSTimeInterval current = [[aSession TEXTVIEW] selectionTime];
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
        [self restorePreviouslyActiveApp];
    }
    if (FRONT == theTerminalWindow) {
        [self setCurrentTerminal:nil];
    }
    if (theTerminalWindow) {
        [self removeFromTerminalsAtIndex:[terminalWindows indexOfObject:theTerminalWindow]];
    }
}

// Build sorted list of encodings
- (NSArray *) sortedEncodingList
{
    NSStringEncoding const *p;
    NSMutableArray *tmp = [NSMutableArray array];

    for (p = [NSString availableStringEncodings]; *p; ++p)
        [tmp addObject:[NSNumber numberWithUnsignedInt:*p]];
    [tmp sortUsingFunction:_compareEncodingByLocalizedName context:NULL];

    return (tmp);
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

- (void)_addBookmarksForTag:(NSString*)tag toMenu:(NSMenu*)aMenu target:(id)aTarget withShortcuts:(BOOL)withShortcuts selector:(SEL)selector alternateSelector:(SEL)alternateSelector openAllSelector:(SEL)openAllSelector
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

- (void)_newSessionsInManyWindowsInMenu:(NSMenu*)parent
{
    for (NSMenuItem* item in [parent itemArray]) {
        if (![item isSeparatorItem] && ![item submenu]) {
            NSString* guid = [item representedObject];
            Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
            if (bookmark) {
                [self launchBookmark:bookmark inTerminal:nil];
            }
        } else if (![item isSeparatorItem] && [item submenu]) {
            [self _newSessionsInManyWindowsInMenu:[item submenu]];
        }
    }
}

- (void)newSessionsInManyWindows:(id)sender
{
    [self _newSessionsInManyWindowsInMenu:[sender menu]];
}

- (PseudoTerminal*)_openNewSessionsFromMenu:(NSMenu*)parent inNewWindow:(BOOL)newWindow usedGuids:(NSMutableSet*)usedGuids bookmarks:(NSMutableArray*)bookmarks
{
    BOOL doOpen = usedGuids == nil;
    if (doOpen) {
        usedGuids = [NSMutableSet setWithCapacity:[[ProfileModel sharedInstance] numberOfBookmarks]];
        bookmarks = [NSMutableArray arrayWithCapacity:[[ProfileModel sharedInstance] numberOfBookmarks]];
    }

    PseudoTerminal* term = newWindow ? nil : [self currentTerminal];
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
            term = [self _openNewSessionsFromMenu:sub inNewWindow:newWindow usedGuids:usedGuids bookmarks:bookmarks];
        }
    }

    if (doOpen) {
        for (Profile* bookmark in bookmarks) {
            if (!term) {
                PTYSession* session = [self launchBookmark:bookmark inTerminal:nil];
                term = [[session tab] realParentWindow];
            } else {
                [self launchBookmark:bookmark inTerminal:term];
            }
        }
    }

    return term;
}

- (void)newSessionsInWindow:(id)sender
{
    [self _openNewSessionsFromMenu:[sender menu] inNewWindow:[sender isAlternate] usedGuids:nil bookmarks:nil];
}

- (void)newSessionsInNewWindow:(id)sender
{
    [self _openNewSessionsFromMenu:[sender menu] inNewWindow:YES
                         usedGuids:nil bookmarks:nil];
}

- (void)addBookmarksToMenu:(NSMenu *)aMenu withSelector:(SEL)selector openAllSelector:(SEL)openAllSelector startingAt:(int)startingAt
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

- (void)addBookmarksToMenu:(NSMenu *)aMenu startingAt:(int)startingAt
{
    [self addBookmarksToMenu:aMenu
                withSelector:@selector(newSessionInTabAtIndex:)
             openAllSelector:@selector(newSessionsInWindow:)
                  startingAt:startingAt];
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
        }
    }
}

- (int)_windowTypeForBookmark:(Profile*)aDict
{
    if ([aDict objectForKey:KEY_WINDOW_TYPE]) {
        int windowType = [[aDict objectForKey:KEY_WINDOW_TYPE] intValue];
        if (windowType == WINDOW_TYPE_FULL_SCREEN &&
            IsLionOrLater() &&
            [[PreferencePanel sharedInstance] lionStyleFullscreen]) {
            return WINDOW_TYPE_LION_FULL_SCREEN;
        } else {
            return windowType;
        }
    } else {
        return WINDOW_TYPE_NORMAL;
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
                                                 screen:[bookmark objectForKey:KEY_SCREEN] ? [[bookmark objectForKey:KEY_SCREEN] intValue] : -1
                                               isHotkey:NO] autorelease];
	if ([[bookmark objectForKey:KEY_HIDE_AFTER_OPENING] boolValue]) {
		[term hideAfterOpening];
	}
    [self addInTerminals:term];
    return term;
}

// Executes an addressbook command in new window or tab
- (id)launchBookmark:(NSDictionary *)bookmarkData
               inTerminal:(PseudoTerminal *)theTerm
    disableLionFullscreen:(BOOL)disableLionFullscreen
{
    PseudoTerminal *term;
    NSDictionary *aDict;

    aDict = bookmarkData;
    if (aDict == nil) {
        aDict = [self defaultBookmark];
    }

    // Where do we execute this command?
    BOOL toggle = NO;
    if (theTerm == nil) {
        [iTermController switchToSpaceInBookmark:aDict];
        int windowType = [self _windowTypeForBookmark:aDict];
        if (windowType == WINDOW_TYPE_LION_FULL_SCREEN && disableLionFullscreen) {
            windowType = WINDOW_TYPE_FULL_SCREEN;
        }
        if (windowType == WINDOW_TYPE_FULL_SCREEN && disableLionFullscreen) {
            // This is a shortcut to make fullscreen hotkey windows open
            // directly in fullscreen mode.
            windowType = WINDOW_TYPE_FORCE_FULL_SCREEN;
        }
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                                 windowType:windowType
                                                     screen:[aDict objectForKey:KEY_SCREEN] ? [[aDict objectForKey:KEY_SCREEN] intValue] : -1
                                                   isHotkey:disableLionFullscreen] autorelease];
		if ([[aDict objectForKey:KEY_HIDE_AFTER_OPENING] boolValue]) {
			[term hideAfterOpening];
        }
        [self addInTerminals:term];
        if (disableLionFullscreen) {
            // See comment above regarding hotkey windows.
            toggle = NO;
        } else {
            toggle = ([term windowType] == WINDOW_TYPE_FULL_SCREEN) ||
                     ([term windowType] == WINDOW_TYPE_LION_FULL_SCREEN);
        }
    } else {
        term = theTerm;
    }

    PTYSession* session = [term addNewSession:aDict];
    if (toggle) {
        [term delayedEnterFullscreen];
    }
    // This function is activated from the dock icon's context menu so make sure
    // that the new window is on top of all other apps' windows. For some reason,
    // makeKeyAndOrderFront does nothing.
    if (![[term window] isKeyWindow]) {
        [NSApp activateIgnoringOtherApps:YES];
        [[term window] makeKeyAndOrderFront:nil];
        [NSApp arrangeInFront:self];
    }

    return session;
}

- (id)launchBookmark:(NSDictionary *)bookmarkData inTerminal:(PseudoTerminal *)theTerm
{
    return [self launchBookmark:bookmarkData inTerminal:theTerm disableLionFullscreen:NO];
}

// I don't think this function is ever called.
- (id)launchBookmark:(NSDictionary *)bookmarkData
          inTerminal:(PseudoTerminal *)theTerm
         withCommand:(NSString *)command
{
    PseudoTerminal *term;
    NSDictionary *aDict;

    aDict = bookmarkData;
    if (aDict == nil) {
        aDict = [[ProfileModel sharedInstance] defaultBookmark];
        if (!aDict) {
            NSMutableDictionary* temp = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:temp];
            [temp setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
            aDict = temp;
        }
    }

    // Where do we execute this command?
    BOOL toggle = NO;
    if (theTerm == nil) {
        [iTermController switchToSpaceInBookmark:aDict];
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                                 windowType:[self _windowTypeForBookmark:aDict]
                                                     screen:[aDict objectForKey:KEY_SCREEN] ? [[aDict objectForKey:KEY_SCREEN] intValue] : -1] autorelease];
		if ([[aDict objectForKey:KEY_HIDE_AFTER_OPENING] boolValue]) {
			[term hideAfterOpening];
		}
        [self addInTerminals:term];
        toggle = (([term windowType] == WINDOW_TYPE_FULL_SCREEN) ||
                  ([term windowType] == WINDOW_TYPE_LION_FULL_SCREEN));
    } else {
        term = theTerm;
    }

    id result = [term addNewSession:aDict
                        withCommand:command
                     asLoginSession:NO
                      forObjectType:theTerm ? iTermTabObject : iTermWindowObject];
    if (toggle) {
        [term delayedEnterFullscreen];
    }
    return result;
}

- (id)launchBookmark:(NSDictionary *)bookmarkData
          inTerminal:(PseudoTerminal *)theTerm
             withURL:(NSString *)url
       forObjectType:(iTermObjectType)objectType
{
    PseudoTerminal *term;
    NSDictionary *aDict;

    aDict = bookmarkData;
    // Automatically fill in ssh command if command is exactly equal to $$ or it's a login shell.
    BOOL ignore;
    if (aDict == nil ||
		[[ITAddressBookMgr bookmarkCommand:aDict
							isLoginSession:&ignore
							 forObjectType:objectType] isEqualToString:@"$$"] ||
        ![[aDict objectForKey:KEY_CUSTOM_COMMAND] isEqualToString:@"Yes"]) {
        Profile* prototype = aDict;
        if (!prototype) {
            prototype = [[ProfileModel sharedInstance] defaultBookmark];
        }
        if (!prototype) {
            NSMutableDictionary* temp = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:temp];
            [temp setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
            prototype = temp;
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

    // Where do we execute this command?
    BOOL toggle = NO;
    if (theTerm == nil) {
        [iTermController switchToSpaceInBookmark:aDict];
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                                 windowType:[self _windowTypeForBookmark:aDict]
                                                     screen:[aDict objectForKey:KEY_SCREEN] ? [[aDict objectForKey:KEY_SCREEN] intValue] : -1] autorelease];
		if ([[aDict objectForKey:KEY_HIDE_AFTER_OPENING] boolValue]) {
			[term hideAfterOpening];
		}
        [self addInTerminals:term];
        toggle = (([term windowType] == WINDOW_TYPE_FULL_SCREEN) ||
                  ([term windowType] == WINDOW_TYPE_LION_FULL_SCREEN));
    } else {
        term = theTerm;
    }

    id result = [term addNewSession:aDict withURL:url forObjectType:objectType];
    if (toggle) {
        [term delayedEnterFullscreen];
    }
    return result;
}

- (void)launchScript:(id)sender
{
    NSString *fullPath = [NSString stringWithFormat:@"%@/%@", [SCRIPT_DIRECTORY stringByExpandingTildeInPath], [sender title]];

    if ([[[sender title] pathExtension] isEqualToString:@"scpt"]) {
        NSAppleScript *script;
        NSDictionary *errorInfo = [NSDictionary dictionary];
        NSURL *aURL = [NSURL fileURLWithPath:fullPath];

        // Make sure our script suite registry is loaded
        [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

        script = [[NSAppleScript alloc] initWithContentsOfURL:aURL error:&errorInfo];
        [script executeAndReturnError:&errorInfo];
        [script release];
    }
    else {
        [[NSWorkspace sharedWorkspace] launchApplication:fullPath];
    }

}

- (PTYTextView *) frontTextView
{
    return ([[FRONT currentSession] TEXTVIEW]);
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

#pragma mark hotkey window

- (void)storePreviouslyActiveApp
{
    if (IsLeopard()) {
        // Visor has a 10.5 path, but it is very hacky and apparently has a crash. 10.5 is moribund
        // so I'm going to omit it.
        return;
    } else {
        // 10.6+ path
        NSDictionary *activeAppDict = [[NSWorkspace sharedWorkspace] activeApplication];
        [previouslyActiveAppPID_ release];
        previouslyActiveAppPID_ = nil;
        if (![[activeAppDict objectForKey:@"NSApplicationBundleIdentifier"] isEqualToString:@"com.googlecode.iterm2"]) {
            previouslyActiveAppPID_ = [[activeAppDict objectForKey:@"NSApplicationProcessIdentifier"] copy];
        }
    }
}

- (void)restorePreviouslyActiveApp
{
    if (IsLeopard()) {
        // See note in storePreviouslyActiveApp.
        return;
    } else {
        // 10.6+ path
        if (!previouslyActiveAppPID_) {
            return;
        }

        id app;
        // NSInvocation hackery because we need to build against the 10.5 sdk and call a
        // 10.6 function.

        // app = [runningApplicationClass_ runningApplicationWithProcessIdentifier:[previouslyActiveAppPID_ intValue]];
        NSMethodSignature *sig = [runningApplicationClass_->isa instanceMethodSignatureForSelector:@selector(runningApplicationWithProcessIdentifier:)];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:runningApplicationClass_];
        [inv setSelector:@selector(runningApplicationWithProcessIdentifier:)];
        int appId = [previouslyActiveAppPID_ intValue];
        [inv setArgument:&appId atIndex:2];
        [inv invoke];
        [inv getReturnValue:&app];

        if (app) {
            NSLog(@"Restore app %@", app);
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
}

static PseudoTerminal* GetHotkeyWindow()
{
    iTermController* cont = [iTermController sharedInstance];
    NSArray* terminals = [cont terminals];
    for (PseudoTerminal* term in terminals) {
        if ([term isHotKeyWindow]) {
            return term;
        }
    }
    return nil;
}

- (PseudoTerminal*)hotKeyWindow
{
    return GetHotkeyWindow();
}

static void RollInHotkeyTerm(PseudoTerminal* term)
{
    HKWLog(@"Roll in [show] visor");
    NSScreen* screen = [term screen];
    if (!screen) {
        screen = [NSScreen mainScreen];
    }
    NSRect screenFrame = [screen visibleFrame];

    NSRect rect = [[term window] frame];
    [NSApp activateIgnoringOtherApps:YES];
    [[term window] setFrame:rect display:YES];
    [[term window] makeKeyAndOrderFront:nil];
    switch ([term windowType]) {
        case WINDOW_TYPE_NORMAL:
            rect.origin.x = -rect.size.width;
            rect.origin.y = -rect.size.height;
            [[term window] setFrame:rect display:NO];

            rect.origin.x = screenFrame.origin.x + (screenFrame.size.width - rect.size.width) / 2;
            rect.origin.y = screenFrame.origin.y + (screenFrame.size.height - rect.size.height) / 2;
            [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
            [[[term window] animator] setFrame:rect display:YES];
            [[[term window] animator] setAlphaValue:1];
            break;

        case WINDOW_TYPE_TOP:
            rect.origin.y = screenFrame.origin.y + screenFrame.size.height - rect.size.height;
            [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
            [[[term window] animator] setFrame:rect display:YES];
            [[[term window] animator] setAlphaValue:1];
            break;

        case WINDOW_TYPE_BOTTOM:
            rect.origin.y = screenFrame.origin.y;
            [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
            [[[term window] animator] setFrame:rect display:YES];
            [[[term window] animator] setAlphaValue:1];
            break;

        case WINDOW_TYPE_LEFT:
            rect.origin.x = screenFrame.origin.x;
            rect.origin.y = screenFrame.origin.y;

            [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
            [[[term window] animator] setFrame:rect display:YES];
            [[[term window] animator] setAlphaValue:1];
            break;

        case WINDOW_TYPE_LION_FULL_SCREEN:  // Shouldn't happen
        case WINDOW_TYPE_FULL_SCREEN:
            [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
            [[[term window] animator] setAlphaValue:1];
            [[term window] makeKeyAndOrderFront:nil];
            // This prevents the findbar, when hidden, from taking focus (bug 1490)
            [[term currentSession] takeFocus];
            [term hideMenuBar];
            break;
    }
    [[iTermController sharedInstance] performSelector:@selector(rollInFinished)
                                           withObject:nil
                                           afterDelay:[[NSAnimationContext currentContext] duration]];
}

- (void)rollInFinished
{
    rollingIn_ = NO;
    PseudoTerminal* term = GetHotkeyWindow();
    [[term window] makeKeyAndOrderFront:nil];
    [[term window] makeFirstResponder:[[term currentSession] TEXTVIEW]];
}

// http://www.cocoadev.com/index.pl?DeterminingOSVersion
+ (BOOL)getSystemVersionMajor:(unsigned *)major
                        minor:(unsigned *)minor
                       bugFix:(unsigned *)bugFix;
{
    OSErr err;
    SInt32 systemVersion, versionMajor, versionMinor, versionBugFix;
    if ((err = Gestalt(gestaltSystemVersion, &systemVersion)) != noErr) {
        return NO;
    }
    if (systemVersion < 0x1040) {
        if (major) {
            *major = ((systemVersion & 0xF000) >> 12) * 10 + ((systemVersion & 0x0F00) >> 8);
        }
        if (minor) {
            *minor = (systemVersion & 0x00F0) >> 4;
        }
        if (bugFix) {
            *bugFix = (systemVersion & 0x000F);
        }
    } else {
        if ((err = Gestalt(gestaltSystemVersionMajor, &versionMajor)) != noErr) {
            return NO;
        }
        if ((err = Gestalt(gestaltSystemVersionMinor, &versionMinor)) != noErr) {
            return NO;
        }
        if ((err = Gestalt(gestaltSystemVersionBugFix, &versionBugFix)) != noErr) {
            return NO;
        }
        if (major) {
            *major = versionMajor;
        }
        if (minor) {
            *minor = versionMinor;
        }
        if (bugFix) {
            *bugFix = versionBugFix;
        }
    }

    return YES;
}

static BOOL OpenHotkeyWindow()
{
    HKWLog(@"Open visor");
    iTermController* cont = [iTermController sharedInstance];
    Profile* bookmark = [[PreferencePanel sharedInstance] hotkeyBookmark];
    if (bookmark) {
        if ([[bookmark objectForKey:KEY_WINDOW_TYPE] intValue] == WINDOW_TYPE_LION_FULL_SCREEN) {
            // Lion fullscreen doesn't make sense with hotkey windows. Change
            // window type to traditional fullscreen.
            NSMutableDictionary* replacement = [NSMutableDictionary dictionaryWithDictionary:bookmark];
            [replacement setObject:[NSNumber numberWithInt:WINDOW_TYPE_FULL_SCREEN]
                            forKey:KEY_WINDOW_TYPE];
            bookmark = replacement;
        }
        PTYSession* session = [cont launchBookmark:bookmark inTerminal:nil disableLionFullscreen:YES];
        PseudoTerminal* term = [[session tab] realParentWindow];
        [term setIsHotKeyWindow:YES];

        if ([term windowType] == WINDOW_TYPE_FULL_SCREEN) {
            [[term window] setAlphaValue:0];
        } else {
            // place it above the screen so it can be rolled in.
            NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
            NSRect rect = [[term window] frame];
            if ([term windowType] == WINDOW_TYPE_TOP) {
                rect.origin.y = screenFrame.origin.y + screenFrame.size.height + rect.size.height;
            } else if ([term windowType] == WINDOW_TYPE_BOTTOM) {
                 rect.origin.y = screenFrame.origin.y - rect.size.height;
            } else if ([term windowType] == WINDOW_TYPE_LEFT) {
              rect.origin.x = screenFrame.origin.x - rect.size.width;
            } else {
                rect.origin.y = -rect.size.height;
                rect.origin.x = -rect.size.width;
            }
            if (IsSnowLeopardOrLater() && !IsLionOrLater()) {
                // TODO: When upgrading to the 10.6 SDK, remove the conditional and the
                // const below:
                [[term window] setCollectionBehavior:[[term window] collectionBehavior] | FutureNSWindowCollectionBehaviorStationary];
            }
            if (IsLionOrLater()) {
                [[term window] setCollectionBehavior:[[term window] collectionBehavior] & ~NSWindowCollectionBehaviorFullScreenPrimary];
            }
        }
        RollInHotkeyTerm(term);
        return YES;
    }
    return NO;
}

- (void)showNonHotKeyWindowsAndSetAlphaTo:(float)a
{
    PseudoTerminal* hotkeyTerm = GetHotkeyWindow();
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        [[term window] setAlphaValue:a];
        if (term != hotkeyTerm) {
            [[term window] makeKeyAndOrderFront:nil];
        }
    }
    // Unhide all windows and bring the one that was at the top to the front.
    int i = [[iTermController sharedInstance] keyWindowIndexMemo];
    if (i >= 0 && i < [[[iTermController sharedInstance] terminals] count]) {
        [[[[[iTermController sharedInstance] terminals] objectAtIndex:i] window] makeKeyAndOrderFront:nil];
    }
}

- (BOOL)rollingInHotkeyTerm
{
    return rollingIn_;
}

static void RollOutHotkeyTerm(PseudoTerminal* term, BOOL itermWasActiveWhenHotkeyOpened)
{
    HKWLog(@"Roll out [hide] visor");
    if (![[term window] isVisible]) {
        HKWLog(@"RollOutHotkeyTerm returning because term isn't visible.");
        return;
    }
    BOOL temp = [term isHotKeyWindow];
    NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
    NSRect rect = [[term window] frame];
    switch ([term windowType]) {
        case WINDOW_TYPE_NORMAL:
            rect.origin.x = -rect.size.width;
            rect.origin.y = -rect.size.height;
            [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
            [[[term window] animator] setFrame:rect display:YES];
            [[[term window] animator] setAlphaValue:0];
            break;

        case WINDOW_TYPE_TOP:
            rect.origin.y = screenFrame.size.height;
            [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
            [[[term window] animator] setFrame:rect display:YES];
            [[[term window] animator] setAlphaValue:0];
            break;

        case WINDOW_TYPE_BOTTOM:
            rect.origin.y = screenFrame.origin.y-rect.size.height;
            [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
            [[[term window] animator] setFrame:rect display:YES];
            [[[term window] animator] setAlphaValue:0];
            break;

        case WINDOW_TYPE_LEFT:
            rect.origin.x = -rect.size.width;
            [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
            [[[term window] animator] setFrame:rect display:YES];
            [[[term window] animator] setAlphaValue:0];
            break;

        case WINDOW_TYPE_LION_FULL_SCREEN:  // Shouldn't happen
        case WINDOW_TYPE_FULL_SCREEN:
            [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
            [[[term window] animator] setAlphaValue:0];
            break;
    }

    [[iTermController sharedInstance] performSelector:@selector(restoreNormalcy:)
                                           withObject:term
                                           afterDelay:[[NSAnimationContext currentContext] duration]];
    [term setIsHotKeyWindow:temp];
}

- (void)doNotOrderOutWhenHidingHotkeyWindow
{
    itermWasActiveWhenHotkeyOpened = YES;
}

- (void)restoreNormalcy:(PseudoTerminal*)term
{
    if (!itermWasActiveWhenHotkeyOpened) {
        [NSApp hide:nil];
        [self performSelector:@selector(unhide) withObject:nil afterDelay:0.1];
    } else {
        PseudoTerminal* currentTerm = [self currentTerminal];
        if (currentTerm && ![currentTerm isHotKeyWindow] && [currentTerm fullScreen]) {
            [currentTerm hideMenuBar];
        } else {
            [currentTerm showMenuBar];
        }
    }

    if ([[PreferencePanel sharedInstance] closingHotkeySwitchesSpaces]) {
        [[term window] orderOut:self];
    } else {
        // Place behind all other windows at this level
        [[term window] orderWindow:NSWindowBelow relativeTo:0];
        // If you orderOut the hotkey term (term variable) then it switches to the
        // space in which your next window exists. So leave key status in the hotkey
        // window although it's invisible.
    }
}

- (void)unhide
{
    [NSApp unhideWithoutActivation];
    for (PseudoTerminal* t in [[iTermController sharedInstance] terminals]) {
        if (![t isHotKeyWindow]) {
            [[[t window] animator] setAlphaValue:1];
        }
    }
}

- (void)showHotKeyWindow
{
    [self storePreviouslyActiveApp];
    itermWasActiveWhenHotkeyOpened = [NSApp isActive];
    PseudoTerminal* hotkeyTerm = GetHotkeyWindow();
    if (hotkeyTerm) {
        HKWLog(@"Showing existing visor");
        int i = 0;
        [[iTermController sharedInstance] setKeyWindowIndexMemo:-1];
        for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
            if ([NSApp isActive]) {
                if (term != hotkeyTerm && [[term window] isKeyWindow]) {
                    [[iTermController sharedInstance] setKeyWindowIndexMemo:i];
                }
            }
            i++;
        }
        HKWLog(@"Activate iterm2");
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        rollingIn_ = YES;
        RollInHotkeyTerm(hotkeyTerm);
    } else {
        HKWLog(@"Open new visor window");
        if (OpenHotkeyWindow()) {
            rollingIn_ = YES;
        }
    }
}

- (BOOL)isHotKeyWindowOpen
{
    PseudoTerminal* term = GetHotkeyWindow();
    return term && [[term window] isVisible];
}

- (BOOL)_isAnyNontHotKeyWindowVisible
{
    PseudoTerminal* hotkeyTerm = GetHotkeyWindow();
    BOOL isAnyNonHotWindowVisible = NO;
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        if (term != hotkeyTerm) {
            if ([[term window] isVisible]) {
                HKWLog(@"found visible non-visor window");
                isAnyNonHotWindowVisible = YES;
                break;
            }
        }
    }
    return isAnyNonHotWindowVisible;
}

- (void)fastHideHotKeyWindow
{
    HKWLog(@"fastHideHotKeyWindow");
    PseudoTerminal* term = GetHotkeyWindow();
    if (term) {
        HKWLog(@"fastHideHotKeyWindow - found a hot term");
        // Temporarily tell the hotkeywindow that it's not hot so that it doesn't try to hide itself
        // when losing key status.
        BOOL temp = [term isHotKeyWindow];
        [term setIsHotKeyWindow:NO];

        // Immediately hide the hotkey window.
        [[term window] orderOut:nil];

        // Move the hotkey window to its offscreen location or its natural alpha value.
        NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
        NSRect rect = [[term window] frame];
        switch ([term windowType]) {
            case WINDOW_TYPE_NORMAL:
                rect.origin.x = -rect.size.width;
                rect.origin.y = -rect.size.height;
                [[term window] setFrame:rect display:YES];
                break;

            case WINDOW_TYPE_TOP:
                // Note that this rect is different than in RollOutHotkeyTerm(). For some reason,
                // in this code path, the screen's origin is not included. I don't know why.
                rect.origin.y = screenFrame.size.height + screenFrame.origin.y;
                HKWLog(@"FAST: Set y=%f", rect.origin.y);
                [[term window] setFrame:rect display:YES];
                break;
            case WINDOW_TYPE_BOTTOM:
                rect.origin.y = screenFrame.origin.y - rect.size.height;
                HKWLog(@"FAST: Set y=%f", rect.origin.y);
                [[term window] setFrame:rect display:YES];
                break;

            case WINDOW_TYPE_LEFT:
                rect.origin.x = screenFrame.origin.x - rect.size.width;
                HKWLog(@"FAST: Set y=%f", rect.origin.y);
                [[term window] setFrame:rect display:YES];
                break;


            case WINDOW_TYPE_LION_FULL_SCREEN:  // Shouldn't happen.
            case WINDOW_TYPE_FULL_SCREEN:
                [[term window] setAlphaValue:0];
                break;
        }

        // Immediately show all other windows.
        [self showNonHotKeyWindowsAndSetAlphaTo:1];

        // Restore hotkey window's status.
        [term setIsHotKeyWindow:temp];
    }
}

- (void)hideHotKeyWindow:(PseudoTerminal*)hotkeyTerm
{
    HKWLog(@"Hide visor.");
    if ([[hotkeyTerm window] isVisible]) {
        HKWLog(@"key window is %@", [NSApp keyWindow]);
        NSWindow *theKeyWindow = [NSApp keyWindow];
        if (!theKeyWindow ||
            ([theKeyWindow isKindOfClass:[PTYWindow class]] &&
             [(PseudoTerminal*)[theKeyWindow windowController] isHotKeyWindow])) {
            [self restorePreviouslyActiveApp];
        }
    }
    RollOutHotkeyTerm(hotkeyTerm, itermWasActiveWhenHotkeyOpened);
}

void OnHotKeyEvent(void)
{
    HKWLog(@"hotkey pressed");
    PreferencePanel* prefPanel = [PreferencePanel sharedInstance];
    if ([prefPanel hotkeyTogglesWindow]) {
        HKWLog(@"visor enabled");
        PseudoTerminal* hotkeyTerm = GetHotkeyWindow();
        if (hotkeyTerm) {
            HKWLog(@"already have a visor created");
            if ([[hotkeyTerm window] alphaValue] == 1) {
                HKWLog(@"visor opaque");
                [[iTermController sharedInstance] hideHotKeyWindow:hotkeyTerm];
            } else {
                HKWLog(@"visor not opaque");
                [[iTermController sharedInstance] showHotKeyWindow];
            }
        } else {
            HKWLog(@"no visor created yet");
            [[iTermController sharedInstance] showHotKeyWindow];
        }
    } else if ([NSApp isActive]) {
        NSWindow* prefWindow = [prefPanel window];
        NSWindow* appKeyWindow = [[NSApplication sharedApplication] keyWindow];
        if (prefWindow != appKeyWindow ||
            ![iTermApplication isTextFieldInFocus:[prefPanel hotkeyField]]) {
            [NSApp hide:nil];
        }
    } else {
        iTermController* controller = [iTermController sharedInstance];
        int n = [controller numberOfTerminals];
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        if (n == 0) {
            [controller newWindow:nil];
        }
    }
}

- (BOOL)eventIsHotkey:(NSEvent*)e
{
    const int mask = (NSCommandKeyMask | NSAlternateKeyMask | NSShiftKeyMask | NSControlKeyMask);
    return (hotkeyCode_ &&
            ([e modifierFlags] & mask) == (hotkeyModifiers_ & mask) &&
            [e keyCode] == hotkeyCode_);
}

/*
 * The callback is passed a proxy for the tap, the event type, the incoming event,
 * and the refcon the callback was registered with.
 * The function should return the (possibly modified) passed in event,
 * a newly constructed event, or NULL if the event is to be deleted.
 *
 * The CGEventRef passed into the callback is retained by the calling code, and is
 * released after the callback returns and the data is passed back to the event
 * system.  If a different event is returned by the callback function, then that
 * event will be released by the calling code along with the original event, after
 * the event data has been passed back to the event system.
 */
static CGEventRef OnTappedEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    iTermController* cont = refcon;
    if (type == kCGEventTapDisabledByTimeout) {
        NSLog(@"kCGEventTapDisabledByTimeout");
        if (cont->machPortRef) {
            NSLog(@"Re-enabling event tap");
            CGEventTapEnable(cont->machPortRef, true);
        }
        return NULL;
    } else if (type == kCGEventTapDisabledByUserInput) {
        NSLog(@"kCGEventTapDisabledByUserInput");
        if (cont->machPortRef) {
            NSLog(@"Re-enabling event tap");
            CGEventTapEnable(cont->machPortRef, true);
        }
        return NULL;
    }

    NSEvent* cocoaEvent = [NSEvent eventWithCGEvent:event];
    BOOL callDirectly = NO;
    BOOL local = NO;
    if ([NSApp isActive]) {
        // Remap modifier keys only while iTerm2 is active; otherwise you could just use the
        // OS's remap feature.
        NSString* unmodkeystr = [cocoaEvent charactersIgnoringModifiers];
        unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
        unsigned int modflag = [cocoaEvent modifierFlags];
        NSString *keyBindingText;
        PreferencePanel* prefPanel = [PreferencePanel sharedInstance];
        BOOL tempDisabled = [prefPanel remappingDisabledTemporarily];
        int action = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                       modifiers:modflag
                                                            text:&keyBindingText
                                              keyMappings:nil];
        BOOL isDoNotRemap = (action == KEY_ACTION_DO_NOT_REMAP_MODIFIERS);
        local = action == KEY_ACTION_REMAP_LOCALLY;
        CGEventRef eventCopy = CGEventCreateCopy(event);
        if (local) {
            // The remapping should be applied and sent to [NSApp sendEvent:]
            // and not be returned from here. Apply the remapping to a copy
            // of the original event.
            CGEventRef temp = event;
            event = eventCopy;
            eventCopy = temp;
        }
        BOOL keySheetOpen = [[prefPanel keySheet] isKeyWindow] && [prefPanel keySheetIsOpen];
        if ((!tempDisabled && !isDoNotRemap) ||  // normal case, whether keysheet is open or not
            (!tempDisabled && isDoNotRemap && keySheetOpen)) {  // about to change dnr to non-dnr
            [iTermKeyBindingMgr remapModifiersInCGEvent:event
                                              prefPanel:prefPanel];
            cocoaEvent = [NSEvent eventWithCGEvent:event];
        }
        if (local) {
            // Now that the cocoaEvent has the remapped version, restore
            // the original event.
            CGEventRef temp = event;
            event = eventCopy;
            eventCopy = temp;
        }
        CFRelease(eventCopy);
        if (tempDisabled && !isDoNotRemap) {
            callDirectly = YES;
        }
    } else {
        // Update cocoaEvent with a remapped modifier (if it appropriate to do
        // so). This has an effect only if the remapped key is the hotkey.
        CGEventRef eventCopy = CGEventCreateCopy(event);
        NSString* unmodkeystr = [cocoaEvent charactersIgnoringModifiers];
        unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
        unsigned int modflag = [cocoaEvent modifierFlags];
        NSString *keyBindingText;
        int action = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                       modifiers:modflag
                                                            text:&keyBindingText
                                                     keyMappings:nil];
        BOOL isDoNotRemap = (action == KEY_ACTION_DO_NOT_REMAP_MODIFIERS) || (action == KEY_ACTION_REMAP_LOCALLY);
        if (!isDoNotRemap) {
            [iTermKeyBindingMgr remapModifiersInCGEvent:eventCopy
                                              prefPanel:[PreferencePanel sharedInstance]];
        }
        cocoaEvent = [NSEvent eventWithCGEvent:eventCopy];
        CFRelease(eventCopy);
    }
#ifdef USE_EVENT_TAP_FOR_HOTKEY
    if ([cont eventIsHotkey:cocoaEvent]) {
        OnHotKeyEvent();
        return NULL;
    }
#endif

    if (callDirectly) {
        // Send keystroke directly to preference panel when setting do-not-remap for a key; for
        // system keys, NSApp sendEvent: is never called so this is the last chance.
        [[PreferencePanel sharedInstance] shortcutKeyDown:cocoaEvent];
        return nil;
    }
    if (local) {
        // Send event directly to iTerm2 and do not allow other apps to see the
        // event at all.
        [NSApp sendEvent:cocoaEvent];
        return nil;
    } else {
        // Normal case.
        return event;
    }
}

- (NSEvent*)runEventTapHandler:(NSEvent*)event
{
    CGEventRef newEvent = OnTappedEvent(nil, kCGEventKeyDown, [event CGEvent], self);
    if (newEvent) {
        return [NSEvent eventWithCGEvent:newEvent];
    } else {
        return nil;
    }
}

- (void)unregisterHotkey
{
    hotkeyCode_ = 0;
    hotkeyModifiers_ = 0;
#ifndef USE_EVENT_TAP_FOR_HOTKEY
    [[GTMCarbonEventDispatcherHandler sharedEventDispatcherHandler] unregisterHotKey:carbonHotKey_];
    [carbonHotKey_ release];
    carbonHotKey_ = nil;
#endif
}

- (BOOL)haveEventTap
{
    return machPortRef != 0;
}

- (void)stopEventTap
{
    if ([self haveEventTap]) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                              eventSrc,
                              kCFRunLoopCommonModes);
        CFMachPortInvalidate(machPortRef); // switches off the event tap;
        CFRelease(machPortRef);
    }
}

- (BOOL)startEventTap
{
#ifdef FAKE_EVENT_TAP
    return YES;
#endif

    if (![self haveEventTap]) {
        DebugLog(@"Register event tap.");
        machPortRef = CGEventTapCreate(kCGHIDEventTap,
                                       kCGTailAppendEventTap,
                                       kCGEventTapOptionDefault,
                                       CGEventMaskBit(kCGEventKeyDown),
                                       (CGEventTapCallBack)OnTappedEvent,
                                       self);
        if (machPortRef) {
            eventSrc = CFMachPortCreateRunLoopSource(NULL, machPortRef, 0);
            if (eventSrc == NULL) {
                DebugLog(@"CFMachPortCreateRunLoopSource failed.");
                NSLog(@"CFMachPortCreateRunLoopSource failed.");
                CFRelease(machPortRef);
                machPortRef = 0;
                return NO;
            } else {
                DebugLog(@"Adding run loop source.");
                // Get the CFRunLoop primitive for the Carbon Main Event Loop, and add the new event souce
                CFRunLoopAddSource(CFRunLoopGetCurrent(),
                                   eventSrc,
                                   kCFRunLoopCommonModes);
                CFRelease(eventSrc);
            }
            return YES;
        } else {
            return NO;
        }
    } else {
        return YES;
    }
}

- (BOOL)registerHotkey:(int)keyCode modifiers:(int)modifiers
{
    if (carbonHotKey_) {
        [self unregisterHotkey];
    }
    hotkeyCode_ = keyCode;
    hotkeyModifiers_ = modifiers & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSShiftKeyMask);
#ifdef USE_EVENT_TAP_FOR_HOTKEY
    if (![self startEventTap]) {
        switch (NSRunAlertPanel(@"Could not enable hotkey",
                                @"You have assigned a \"hotkey\" that opens iTerm2 at any time. To use it, you must turn on \"access for assistive devices\" in the Universal Access preferences panel in System Preferences and restart iTerm2.",
                                @"OK",
                                @"Open System Preferences",
                                @"Disable Hotkey",
                                nil)) {
            case NSAlertOtherReturn:
                [[PreferencePanel sharedInstance] disableHotkey];
                break;

            case NSAlertAlternateReturn:
                [[NSWorkspace sharedWorkspace] openFile:@"/System/Library/PreferencePanes/UniversalAccessPref.prefPane"];
                return NO;
        }
    }
    return YES;
#else
    carbonHotKey_ = [[[GTMCarbonEventDispatcherHandler sharedEventDispatcherHandler]
                      registerHotKey:keyCode
                      modifiers:hotkeyModifiers_
                      target:self
                      action:@selector(carbonHotkeyPressed)
                      userInfo:nil
                      whenPressed:YES] retain];
    return YES;
#endif
}

- (void)carbonHotkeyPressed
{
    OnHotKeyEvent();
}

- (void)beginRemappingModifiers
{
    if (![self startEventTap]) {
        switch (NSRunAlertPanel(@"Could not remap modifiers",
                                @"You have chosen to remap certain modifier keys. For this to work for all key combinations (such as cmd-tab), you must turn on \"access for assistive devices\" in the Universal Access preferences panel in System Preferences and restart iTerm2.",
                                @"OK",
                                @"Open System Preferences",
                                nil,
                                nil)) {
            case NSAlertAlternateReturn:
                [[NSWorkspace sharedWorkspace] openFile:@"/System/Library/PreferencePanes/UniversalAccessPref.prefPane"];
                break;
        }
    }
}

- (void)dumpViewHierarchy {
    for (PseudoTerminal *term in [self terminals]) {
        DebugLog([NSString stringWithFormat:@"Terminal %@ at %@", [term window], [NSValue valueWithRect:[[term window] frame]]]);
        DebugLog([[[term window] contentView] hierarchicalDescription]);
    }
}

@end

// keys for to-many relationships:
NSString *terminalsKey = @"terminals";

// Scripting support
@implementation iTermController (KeyValueCoding)

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key
{
    BOOL ret;
    // NSLog(@"key = %@", key);
    ret = [key isEqualToString:@"terminals"] || [key isEqualToString:@"currentTerminal"];
    return (ret);
}

// accessors for to-many relationships:
- (NSArray*)terminals
{
    // NSLog(@"iTerm: -terminals");
    return (terminalWindows);
}

- (void)setTerminals:(NSArray*)terminals
{
    // no-op
}

// accessors for to-many relationships:
// (See NSScriptKeyValueCoding.h)
-(id)valueInTerminalsAtIndex:(unsigned)theIndex
{
    //NSLog(@"iTerm: valueInTerminalsAtIndex %d: %@", theIndex, [terminalWindows objectAtIndex: theIndex]);
    return ([terminalWindows objectAtIndex:theIndex]);
}

- (void)setCurrentTerminal:(PseudoTerminal*)thePseudoTerminal
{
    FRONT = thePseudoTerminal;

    // make sure this window is the key window
    if ([thePseudoTerminal windowInited] && [[thePseudoTerminal window] isKeyWindow] == NO) {
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

-(void)replaceInTerminals:(PseudoTerminal *)object atIndex:(unsigned)theIndex
{
    // NSLog(@"iTerm: replaceInTerminals 0x%x atIndex %d", object, theIndex);
    [terminalWindows replaceObjectAtIndex:theIndex withObject:object];
    [self updateWindowTitles];
}

- (void)addInTerminals:(PseudoTerminal*)object
{
    // NSLog(@"iTerm: addInTerminals 0x%x", object);
    [self insertInTerminals:object atIndex:[terminalWindows count]];
    [self updateWindowTitles];
}

- (void)insertInTerminals:(PseudoTerminal*)object
{
    // NSLog(@"iTerm: insertInTerminals 0x%x", object);
    [self insertInTerminals:object atIndex:[terminalWindows count]];
    [self updateWindowTitles];
}

-(void)insertInTerminals:(PseudoTerminal *)object atIndex:(unsigned)theIndex
{
    if ([terminalWindows containsObject:object] == YES) {
        return;
    }

    [terminalWindows insertObject:object atIndex:theIndex];
    [self updateWindowTitles];
    if (![object isInitialized]) {
        [object initWithSmartLayout:YES
                         windowType:WINDOW_TYPE_NORMAL
                             screen:-1];
    }
}

-(void)removeFromTerminalsAtIndex:(unsigned)theIndex
{
    // NSLog(@"iTerm: removeFromTerminalsAtInde %d", theIndex);
    [terminalWindows removeObjectAtIndex:theIndex];
    [self updateWindowTitles];
}

// a class method to provide the keys for KVC:
- (NSArray*)kvcKeys
{
    static NSArray *_kvcKeys = nil;
    if( nil == _kvcKeys ){
        _kvcKeys = [[NSArray alloc] initWithObjects:
            terminalsKey,  nil ];
    }
    return _kvcKeys;
}

@end

