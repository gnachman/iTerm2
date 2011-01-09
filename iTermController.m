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

#import <iTerm/iTermController.h>
#import <iTerm/PreferencePanel.h>
#import <iTerm/PseudoTerminal.h>
#import <iTerm/PTYSession.h>
#import <iTerm/VT100Screen.h>
#import <iTerm/NSStringITerm.h>
#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/iTermGrowlDelegate.h>
#import "PasteboardHistory.h"
#import <Carbon/Carbon.h>
#import "iTermApplicationDelegate.h"
#import "iTermApplication.h"
#import "UKCrashReporter/UKCrashReporter.h"

@interface NSApplication (Undocumented)
- (void)_cycleWindowsReversed:(BOOL)back;
@end

// Constants for saved window arrangement key names.
static NSString* DEFAULT_ARRANGEMENT_NAME = @"Default";
static NSString* APPLICATION_SUPPORT_DIRECTORY = @"~/Library/Application Support";
static NSString *SUPPORT_DIRECTORY = @"~/Library/Application Support/iTerm";
static NSString *SCRIPT_DIRECTORY = @"~/Library/Application Support/iTerm/Scripts";
static NSString* WINDOW_ARRANGEMENTS = @"Window Arrangements";

// Comparator for sorting encodings
static NSInteger _compareEncodingByLocalizedName(id a, id b, void *unused)
{
    NSString *sa = [NSString localizedNameOfStringEncoding: [a unsignedIntValue]];
    NSString *sb = [NSString localizedNameOfStringEncoding: [b unsignedIntValue]];
    return [sa caseInsensitiveCompare: sb];
}


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

    UKCrashReporterCheckForCrash();

    // create the iTerm directory if it does not exist
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // create the "~/Library/Application Support" directory if it does not exist
    if([fileManager fileExistsAtPath: [APPLICATION_SUPPORT_DIRECTORY stringByExpandingTildeInPath]] == NO)
        [fileManager createDirectoryAtPath: [APPLICATION_SUPPORT_DIRECTORY stringByExpandingTildeInPath] attributes: nil];

    if([fileManager fileExistsAtPath: [SUPPORT_DIRECTORY stringByExpandingTildeInPath]] == NO)
        [fileManager createDirectoryAtPath: [SUPPORT_DIRECTORY stringByExpandingTildeInPath] attributes: nil];

    terminalWindows = [[NSMutableArray alloc] init];

    // Activate Growl
    /*
     * Need to add routine in iTerm prefs for Growl support and
     * PLIST check here.
     */
    gd = [iTermGrowlDelegate sharedInstance];

    return (self);
}

- (void) dealloc
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
    if(gd)
        [gd release];

    [super dealloc];
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
    [self launchBookmark:nil inTerminal: nil];
}

- (void) newSessionInTabAtIndex: (id) sender
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self launchBookmark:bookmark inTerminal:FRONT];
    }
}

- (void) showHideFindBar
{
    [[self currentTerminal] showHideFindBar];
}

- (void)newSessionInWindowAtIndex: (id) sender
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self launchBookmark:bookmark inTerminal:nil];
    }
}

// meant for action for menu items that have a submenu
- (void) noAction: (id) sender
{

}

- (IBAction)newSession:(id)sender
{
    [self launchBookmark:nil inTerminal: FRONT];
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

- (BOOL)hasWindowArrangement
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:WINDOW_ARRANGEMENTS] objectForKey:DEFAULT_ARRANGEMENT_NAME] != nil;
}

- (void)saveWindowArrangement
{
    NSMutableArray* terminalArrangements = [NSMutableArray arrayWithCapacity:[terminalWindows count]];
    for (PseudoTerminal* terminal in terminalWindows) {
        [terminalArrangements addObject:[terminal arrangement]];
    }
    NSMutableDictionary* arrangements = [NSMutableDictionary dictionaryWithObject:terminalArrangements
                                                                           forKey:DEFAULT_ARRANGEMENT_NAME];
    [[NSUserDefaults standardUserDefaults] setObject:arrangements forKey:WINDOW_ARRANGEMENTS];

    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSavedArrangementChanged"
                                                        object:nil
                                                      userInfo:nil];
}

- (void)loadWindowArrangement
{
    NSDictionary* arrangements = [[NSUserDefaults standardUserDefaults] objectForKey:WINDOW_ARRANGEMENTS];
    NSArray* terminalArrangements = [arrangements objectForKey:DEFAULT_ARRANGEMENT_NAME];
    for (NSDictionary* terminalArrangement in terminalArrangements) {
        PseudoTerminal* term = [PseudoTerminal terminalWithArrangement:terminalArrangement];
        [self addInTerminals:term];
    }
}

// Return all the terminals in the given screen.
- (NSArray*)_terminalsInScreen:(NSScreen*)screen
{
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:0];
    for (PseudoTerminal* term in terminalWindows) {
        if ([[term window] deepestScreen] == screen) {
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
    float x = 0;
    float w = frame.size.width / [terminals count];
    float minWidth = 400;
    for (PseudoTerminal* term in terminals) {
        float termMinWidth = [term minWidth];
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
    float highestTop = 0;
    for (PseudoTerminal* terminal in terminals) {
        NSRect r = [[terminal window] frame];
        if (r.origin.y < frame.origin.y) {
            // Bottom of window is below dock. Pretend its bottom abuts the dock.
            r.origin.y = frame.origin.y;
        }
        float top = r.origin.y + r.size.height;
        if (top > highestTop) {
            highestTop = top;
        }
    }

    // Ensure the bottom of the last row of windows will be above the bottom of the screen.
    int rows = ceil((w * (float)[terminals count]) / frame.size.width);
    float maxHeight = frame.size.height / rows;
    if (rows > 1 && highestTop - maxHeight * rows < frame.origin.y) {
        highestTop = frame.origin.y + maxHeight * rows;
    }

    if (highestTop > frame.origin.y + frame.size.height) {
        // Don't let the top of the first row go above the top of the screen. This is just
        // paranoia.
        highestTop = frame.origin.y + frame.size.height;
    }

    float yOffset = 0;
    NSMutableArray *terminalsCopy = [NSMutableArray arrayWithArray:terminals];

    // Grab the window that would move the least and move it. This isn't a global
    // optimum, but it is reasonably stable.
    while ([terminalsCopy count] > 0) {
        // Find the leftmost terminal.
        PseudoTerminal* terminal = nil;
        float bestDistance = 0;
        int bestIndex = 0;

        for (int j = 0; j < [terminalsCopy count]; ++j) {
            PseudoTerminal* t = [terminalsCopy objectAtIndex:j];
            if (t) {
                NSRect r = [[t window] frame];
                float y = highestTop - r.size.height + yOffset;
                float dx = x - r.origin.x;
                float dy = y - r.origin.y;
                float distance = dx*dx + dy*dy;
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
        float y = highestTop - [[terminal window] frame].size.height;
        float h = MIN(maxHeight, [[terminal window] frame].size.height);
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
            x = 0;
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
    // Un-full-screen each window. This is done in two steps because
    // toggleFullScreen deallocs self.
    for (PseudoTerminal* t in terminalWindows) {
        if ([t fullScreen]) {
            [t toggleFullScreen:self];
        }
    }

    // For each screen, find the terminals in it and arrange them. This way
    // terminals don't move from screen to screen in this operation.
    for (NSScreen* screen in [NSScreen screens]) {
        [self arrangeTerminals:[self _terminalsInScreen:screen]
                       inFrame:[screen visibleFrame]];
    }
}

- (PseudoTerminal*)currentTerminal
{
    return FRONT;
}

- (void)terminalWillClose:(PseudoTerminal*)theTerminalWindow
{
    if (FRONT == theTerminalWindow) {
        [self setCurrentTerminal: nil];
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
    [tmp sortUsingFunction: _compareEncodingByLocalizedName context:NULL];

    return (tmp);
}

- (void)_addBookmark:(Bookmark*)bookmark toMenu:(NSMenu*)aMenu target:(id)aTarget withShortcuts:(BOOL)withShortcuts
{
    NSMenuItem* aMenuItem = [[[NSMenuItem alloc] initWithTitle:[bookmark objectForKey:KEY_NAME]
                                                        action:@selector(newSessionInTabAtIndex:)
                                                 keyEquivalent:@""] autorelease];
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

    aMenuItem = [[aMenuItem copy] autorelease];
    [aMenuItem setKeyEquivalentModifierMask:modifierMask | NSAlternateKeyMask];
    [aMenuItem setAlternate:YES];
    [aMenuItem setAction:@selector(newSessionInWindowAtIndex:)];
    [aMenuItem setTarget:self];
    [aMenu addItem:aMenuItem];
}

- (void)_addBookmarksForTag:(NSString*)tag toMenu:(NSMenu*)aMenu target:(id)aTarget withShortcuts:(BOOL)withShortcuts
{
    NSMenuItem* aMenuItem = [[[NSMenuItem alloc] initWithTitle:tag action:@selector(noAction:) keyEquivalent:@""] autorelease];
    NSMenu* subMenu = [[[NSMenu alloc] init] autorelease];
    for (int i = 0; i < [[BookmarkModel sharedInstance] numberOfBookmarks]; ++i) {
        Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkAtIndex:i];
        NSArray* tags = [bookmark objectForKey:KEY_TAGS];
        for (int j = 0; j < [tags count]; ++j) {
            if ([tag localizedCaseInsensitiveCompare:[tags objectAtIndex:j]] == NSOrderedSame) {
                [self _addBookmark:bookmark toMenu:subMenu target:aTarget withShortcuts:withShortcuts];
                break;
            }
        }
    }
    [aMenuItem setSubmenu:subMenu];
    [aMenuItem setTarget:self];
    [aMenu addItem:aMenuItem];
}

- (void)addBookmarksToMenu:(NSMenu *)aMenu target:(id)aTarget withShortcuts:(BOOL)withShortcuts
{
    NSArray* tags = [[BookmarkModel sharedInstance] allTags];
    int count = 0;
    for (int i = 0; i < [tags count]; ++i) {
        [self _addBookmarksForTag:[tags objectAtIndex:i]
                           toMenu:aMenu
                           target:aTarget
                    withShortcuts:withShortcuts];
        ++count;
    }
    for (int i = 0; i < [[BookmarkModel sharedInstance] numberOfBookmarks]; ++i) {
        Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkAtIndex:i];
        if ([[bookmark objectForKey:KEY_TAGS] count] == 0) {
            ++count;
            [self _addBookmark:bookmark
                        toMenu:aMenu
                        target:aTarget
                 withShortcuts:withShortcuts];
        }
    }

    if (count > 1) {
        [aMenu addItem:[NSMenuItem separatorItem]];
        NSMenuItem* aMenuItem = [[[NSMenuItem alloc] initWithTitle:
                                  NSLocalizedStringFromTableInBundle(@"Open All",
                                                                     @"iTerm",
                                                                     [NSBundle bundleForClass: [iTermController class]],
                                                                     @"Context Menu")
                                                            action:@selector(newSessionsInWindow:)
                                                     keyEquivalent:@""] autorelease];
        unsigned int modifierMask = NSCommandKeyMask | NSControlKeyMask;
        [aMenuItem setKeyEquivalentModifierMask:modifierMask];
        [aMenuItem setRepresentedObject:@""];
        [aMenuItem setTarget:self];
        [aMenu addItem:aMenuItem];
        aMenuItem = [[aMenuItem copy] autorelease];
        [aMenuItem setKeyEquivalentModifierMask:modifierMask | NSAlternateKeyMask];
        [aMenuItem setAlternate:YES];
        [aMenuItem setAction:@selector(newSessionsInNewWindow:)];
        [aMenuItem setTarget:self];
        [aMenu addItem:aMenuItem];
    }
}

- (void)irAdvance:(int)dir
{
    [FRONT irAdvance:dir];
}

// Executes an addressbook command in new window or tab
- (id)launchBookmark:(NSDictionary *)bookmarkData inTerminal:(PseudoTerminal *)theTerm
{
    PseudoTerminal *term;
    NSDictionary *aDict;

    aDict = bookmarkData;
    if (aDict == nil) {
        aDict = [[BookmarkModel sharedInstance] defaultBookmark];
        if (!aDict) {
            NSMutableDictionary* temp = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:temp];
            [temp setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
            aDict = temp;
        }
    }

    // Where do we execute this command?
    if (theTerm == nil) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES fullScreen:nil] autorelease];
        [self addInTerminals:term];
    } else {
        term = theTerm;
    }

    PTYSession* session = [term addNewSession:aDict];

    // This function is activated from the dock icon's context menu so make sure
    // that the new window is on top of all other apps' windows. For some reason,
    // makeKeyAndOrderFront does nothing.
    if (![[term window] isKeyWindow]) {
        [NSApp arrangeInFront:self];
    }

    return session;
}

- (id)launchBookmark:(NSDictionary *)bookmarkData inTerminal:(PseudoTerminal *)theTerm withCommand:(NSString *)command
{
    PseudoTerminal *term;
    NSDictionary *aDict;

    aDict = bookmarkData;
    if (aDict == nil) {
        aDict = [[BookmarkModel sharedInstance] defaultBookmark];
        if (!aDict) {
            NSMutableDictionary* temp = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:temp];
            [temp setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
            aDict = temp;
        }
    }

    // Where do we execute this command?
    if (theTerm == nil) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES fullScreen:nil] autorelease];
        [self addInTerminals:term];
    } else {
        term = theTerm;
    }

    return [term addNewSession: aDict withCommand: command];
}

- (id)launchBookmark:(NSDictionary *)bookmarkData inTerminal:(PseudoTerminal *)theTerm withURL:(NSString *)url
{
    PseudoTerminal *term;
    NSDictionary *aDict;

    aDict = bookmarkData;
    // $$ is a prefix/suffix of a variabe.
    if (aDict == nil || [[ITAddressBookMgr bookmarkCommand:aDict] isEqualToString:@"$$"]) {
        Bookmark* prototype = aDict;
        if (!prototype) {
            prototype = [[BookmarkModel sharedInstance] defaultBookmark];
        }
        if (!prototype) {
            NSMutableDictionary* temp = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:temp];
            [temp setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
            prototype = temp;
        }

        NSMutableDictionary *tempDict = [NSMutableDictionary dictionaryWithDictionary:prototype];
        NSURL *urlRep = [NSURL URLWithString: url];
        NSString *urlType = [urlRep scheme];

        if ([urlType compare:@"ssh" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithString:@"ssh "];
            if ([urlRep user]) [tempString appendFormat:@"-l %@ ", [urlRep user]];
            if ([urlRep port]) [tempString appendFormat:@"-p %@ ", [urlRep port]];
            if ([urlRep host]) [tempString appendString:[urlRep host]];
            [tempDict setObject:tempString forKey:KEY_COMMAND];
            aDict = tempDict;
        }
        else if ([urlType compare:@"ftp" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithFormat:@"ftp %@", url];
            [tempDict setObject:tempString forKey:KEY_COMMAND];
            aDict = tempDict;
        }
        else if ([urlType compare:@"telnet" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithString:@"telnet "];
            if ([urlRep user]) [tempString appendFormat:@"-l %@ ", [urlRep user]];
            if ([urlRep host]) {
                [tempString appendString:[urlRep host]];
                if ([urlRep port]) [tempString appendFormat:@" %@", [urlRep port]];
            }
            [tempDict setObject:tempString forKey:KEY_COMMAND];
            aDict = tempDict;
        }
    }

    // Where do we execute this command?
    if (theTerm == nil) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES fullScreen:nil] autorelease];
        [self addInTerminals: term];
    } else {
        term = theTerm;
    }

    return [term addNewSession: aDict withURL: url];
}

- (void)launchScript:(id)sender
{
    NSString *fullPath = [NSString stringWithFormat: @"%@/%@", [SCRIPT_DIRECTORY stringByExpandingTildeInPath], [sender title]];

    if ([[[sender title] pathExtension] isEqualToString: @"scpt"]) {
        NSAppleScript *script;
        NSDictionary *errorInfo = [NSDictionary dictionary];
        NSURL *aURL = [NSURL fileURLWithPath: fullPath];

        // Make sure our script suite registry is loaded
        [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

        script = [[NSAppleScript alloc] initWithContentsOfURL: aURL error: &errorInfo];
        [script executeAndReturnError: &errorInfo];
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

void OnHotKeyEvent(void)
{
    if ([NSApp isActive]) {
        PreferencePanel* prefPanel = [PreferencePanel sharedInstance];
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
    return (hotkeyCode_ &&
            ([e modifierFlags] & hotkeyModifiers_) == hotkeyModifiers_ &&
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
        if (cont->machPortRef) {
            CGEventTapEnable(cont->machPortRef, true);
        }
        return NULL;
    } else if (type == kCGEventTapDisabledByUserInput) {
        return NULL;
    }

    NSEvent* e = [NSEvent eventWithCGEvent:event];
    if ([cont eventIsHotkey:e]) {
        OnHotKeyEvent();
        return NULL;
    }

    return event;
}

- (void)unregisterHotkey
{
    hotkeyCode_ = 0;
    hotkeyModifiers_ = 0;
}

- (void)registerHotkey:(int)keyCode modifiers:(int)modifiers
{
    hotkeyCode_ = keyCode;
    hotkeyModifiers_ = modifiers;
    if (!machPortRef) {
        DebugLog(@"Register event tap.");
        machPortRef = CGEventTapCreate(kCGHIDEventTap,
                                       kCGHeadInsertEventTap,
                                       kCGEventTapOptionDefault,
                                       CGEventMaskBit(kCGEventKeyDown),
                                       (CGEventTapCallBack)OnTappedEvent,
                                       self);
        if (machPortRef) {
            CFRunLoopSourceRef eventSrc;

            eventSrc = CFMachPortCreateRunLoopSource(NULL, machPortRef, 0);
            if (eventSrc == NULL) {
                DebugLog(@"CFMachPortCreateRunLoopSource failed.");
            } else {
                DebugLog(@"Adding run loop source.");
                // Get the CFRunLoop primitive for the Carbon Main Event Loop, and add the new event souce
                CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSrc, kCFRunLoopDefaultMode);
                CFRelease(eventSrc);
            }
        } else {
            switch (NSRunAlertPanel(@"Could not enable hotkey.",
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
                    break;
            }
        }
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
    return ([terminalWindows objectAtIndex: theIndex]);
}

- (void)setCurrentTerminal:(PseudoTerminal*)thePseudoTerminal
{
    FRONT = thePseudoTerminal;

    // make sure this window is the key window
    if ([thePseudoTerminal windowInited] && [[thePseudoTerminal window] isKeyWindow] == NO) {
        [[thePseudoTerminal window] makeKeyAndOrderFront: self];
    }

    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:thePseudoTerminal
                                                      userInfo:nil];

}

-(void)replaceInTerminals:(PseudoTerminal *)object atIndex:(unsigned)theIndex
{
    // NSLog(@"iTerm: replaceInTerminals 0x%x atIndex %d", object, theIndex);
    [terminalWindows replaceObjectAtIndex: theIndex withObject: object];
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
    if ([terminalWindows containsObject: object] == YES) {
        return;
    }

    [terminalWindows insertObject:object atIndex:theIndex];
    [self updateWindowTitles];
    if (![object isInitialized]) {
        [object initWithSmartLayout:YES fullScreen:nil];
    }
}

-(void)removeFromTerminalsAtIndex:(unsigned)theIndex
{
    // NSLog(@"iTerm: removeFromTerminalsAtInde %d", theIndex);
    [terminalWindows removeObjectAtIndex: theIndex];
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

