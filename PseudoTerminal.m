
// -*- mode:objc -*-
// $Id: PseudoTerminal.m,v 1.437 2009-02-06 15:07:23 delx Exp $
//
/*
 **  PseudoTerminal.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **         Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Session and window controller for iTerm.
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

#define WINDOW_NAME @"iTerm Window %d"

#import <iTerm/iTerm.h>
#import <iTerm/PseudoTerminal.h>
#import <iTerm/PTYScrollView.h>
#import <iTerm/NSStringITerm.h>
#import <iTerm/PTYSession.h>
#import <iTerm/VT100Screen.h>
#import <iTerm/PTYTabView.h>
#import <iTerm/PreferencePanel.h>
#import <iTerm/iTermController.h>
#import <iTerm/PTYTask.h>
#import <iTerm/PTYTextView.h>
#import <iTerm/PseudoTerminal.h>
#import <iTerm/VT100Terminal.h>
#import <iTerm/VT100Screen.h>
#import <iTerm/PTYSession.h>
#import <iTerm/PTToolbarController.h>
#import <iTerm/FindCommandHandler.h>
#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/iTermApplicationDelegate.h>
#import "FakeWindow.h"
#import <PSMTabBarControl.h>
#import <PSMTabStyle.h>
#import <iTerm/iTermGrowlDelegate.h>
#include <unistd.h>
#import "PasteboardHistory.h"

#define CACHED_WINDOW_POSITIONS 100

#define ITLocalizedString(key) NSLocalizedStringFromTableInBundle(key, @"iTerm", [NSBundle bundleForClass:[self class]], @"Context menu")

// #define PSEUDOTERMINAL_VERBOSE_LOGGING
#ifdef PSEUDOTERMINAL_VERBOSE_LOGGING
#define PtyLog NSLog
#else
#define PtyLog(args...) \
    do { \
        if (gDebugLogging) { \
          DebugLog([NSString stringWithFormat:args]); \
        } \
    } while (0)
#endif

static BOOL windowPositions[CACHED_WINDOW_POSITIONS];

@interface PSMTabBarControl (Private)
- (void)update;
@end

@interface NSWindow (private)
- (void)setBottomCornerRounded:(BOOL)rounded;
@end

// keys for attributes:
NSString *columnsKey = @"columns";
NSString *rowsKey = @"rows";
// keys for to-many relationships:
NSString *sessionsKey = @"sessions";

#define TABVIEW_TOP_OFFSET                29
#define TABVIEW_BOTTOM_OFFSET            27
#define TABVIEW_LEFT_RIGHT_OFFSET        29
#define TOOLBAR_OFFSET                    0

@class PTYSession, iTermController, PTToolbarController, PSMTabBarControl;

@implementation SolidColorView
- (id)initWithFrame:(NSRect)frame color:(NSColor*)color
{
    self = [super initWithFrame:frame];
    if (self) {
        color_ = [color retain];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [color_ setFill];
    NSRectFill(dirtyRect);
}

- (void)setColor:(NSColor*)color
{
    [color_ autorelease];
    color_ = [color retain];
}

- (NSColor*)color
{
    return color_;
}

@end
@implementation BottomBarView
- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor controlColor] setFill];
    NSRectFill(dirtyRect);

    // Draw a black line at the top of the view.
    [[NSColor blackColor] setFill];
    NSRect r = [self frame];
    NSRectFill(NSMakeRect(0, r.size.height - 1, r.size.width, 1));
}

@end

@implementation PseudoTerminal

- (id)initWithSmartLayout:(BOOL)smartLayout fullScreen:(NSScreen*)fullScreen
{
    unsigned int styleMask;
    PTYWindow *myWindow;

    self = [super initWithWindowNibName:@"PseudoTerminal"];
    NSAssert(self, @"initWithWindowNibName returned nil");

    // Force the nib to load
    [self window];
    [commandField retain];
    [commandField setDelegate:self];
    [bottomBar retain];

    pbHistoryView = [[PasteboardHistoryView alloc] init];

    autocompleteView = [[AutocompleteView alloc] init];

    // create the window programmatically with appropriate style mask
    styleMask = NSTitledWindowMask |
        NSClosableWindowMask |
        NSMiniaturizableWindowMask |
        NSResizableWindowMask;

    // set the window style according to preference
    if ([[PreferencePanel sharedInstance] windowStyle] == 0) {
        styleMask |= NSTexturedBackgroundWindowMask;
    } else if ([[PreferencePanel sharedInstance] windowStyle] == 2) {
        styleMask |= NSUnifiedTitleAndToolbarWindowMask;
    }
    NSScreen* screen = fullScreen ? fullScreen : [NSScreen mainScreen];
    PtyLog(@"initWithSmartLayout - initWithContentRect:%fx%f", [screen frame].size.width, [screen frame].size.height);
    myWindow = [[PTYWindow alloc] initWithContentRect:[screen frame]
                                            styleMask:fullScreen ? NSBorderlessWindowMask : styleMask
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    PtyLog(@"initWithSmartLayout - new window is at %d", myWindow);
    [self setWindow:myWindow];
    [myWindow release];

    _fullScreen = (fullScreen != nil);
    previousFindString = [[NSMutableString alloc] init];
    if (fullScreen) {
        background_ = [[SolidColorView alloc] initWithFrame:[[[self window] contentView] frame] color:[NSColor blackColor]];
        [[self window] setAlphaValue:1];
    } else {
        background_ = [[SolidColorView alloc] initWithFrame:[[[self window] contentView] frame] color:[NSColor windowBackgroundColor]];
        [[self window] setAlphaValue:0.9999];  // Why is this not 1.0?
    }
    normalBackgroundColor = [background_ color];

#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif

    _resizeInProgressFlag = NO;

    if (!smartLayout) {
        [(PTYWindow*)[self window] setLayoutDone];
    }

    if (!_fullScreen) {
        _toolbarController = [[PTToolbarController alloc] initWithPseudoTerminal:self];
        if ([[self window] respondsToSelector:@selector(setBottomCornerRounded:)])
            [[self window] setBottomCornerRounded:NO];
    }

    // create the tab bar control
    [[self window] setContentView:background_];
    [background_ release];

    NSRect aRect = [[[self window] contentView] bounds];
    aRect.size.height = 22;
    tabBarControl = [[PSMTabBarControl alloc] initWithFrame:aRect];
    [tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    if (!_fullScreen) {
        [[[self window] contentView] addSubview:tabBarControl];
        [tabBarControl release];
    }

    // Set up bottomBar
    NSRect fbFrame = [findBarSubview frame];
    NSRect irFrame = [instantReplaySubview frame];
    bottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0,
                                                         0,
                                                         fbFrame.size.width,
                                                         fbFrame.size.height + irFrame.size.height)];
    [bottomBar addSubview:findBarSubview];
    [bottomBar addSubview:instantReplaySubview];
    fbFrame.origin.y = 0;
    [findBarSubview setFrame:fbFrame];
    irFrame.origin.y = fbFrame.size.height;
    [instantReplaySubview setFrame:irFrame];
    [bottomBar setHidden:YES];
    [instantReplaySubview setHidden:YES];
    [findBarSubview setHidden:YES];

    [findBarTextField setDelegate:self];

    // create the tabview
    aRect = [[[self window] contentView] bounds];

    TABVIEW = [[PTYTabView alloc] initWithFrame: aRect];
    [TABVIEW setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable];
    [TABVIEW setAutoresizesSubviews: YES];
    [TABVIEW setAllowsTruncatedLabels: NO];
    [TABVIEW setControlSize: NSSmallControlSize];
    [TABVIEW setTabViewType: NSNoTabsNoBorder];
    // Add to the window
    [[[self window] contentView] addSubview:TABVIEW];
    [TABVIEW release];

    [[[self window] contentView] addSubview:bottomBar];

    if (_fullScreen) {
        // Put tab bar control inside of a solid-colored background for fullscreen mode and hide it
        // just above the top of the screen.
        tabBarBackground = [[SolidColorView alloc] initWithFrame:NSMakeRect(0, -[tabBarControl frame].size.height, [TABVIEW frame].size.width, [tabBarControl frame].size.height) color:[NSColor windowBackgroundColor]];
        [tabBarBackground addSubview:tabBarControl];
        [tabBarControl setFrameOrigin:NSMakePoint(0, 0)];
        [tabBarBackground setHidden:YES];
        [tabBarControl release];
    }

    // assign tabview and delegates
    [tabBarControl setTabView: TABVIEW];
    [TABVIEW setDelegate: tabBarControl];
    [tabBarControl setDelegate: self];
    [tabBarControl setHideForSingleTab: NO];
    [tabBarControl setHidden:_fullScreen];

    // set the style of tabs to match window style
    switch ([[PreferencePanel sharedInstance] windowStyle]) {
        case 0:
            [tabBarControl setStyleNamed:@"Metal"];
            break;
        case 1:
            [tabBarControl setStyleNamed:@"Aqua"];
            break;
        case 2:
            [tabBarControl setStyleNamed:@"Unified"];
            break;
        default:
            [tabBarControl setStyleNamed:@"Adium"];
            break;
    }

    [[[self window] contentView] setAutoresizesSubviews: YES];
    [[self window] setDelegate: self];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_refreshTerminal:)
                                                 name: @"iTermRefreshTerminal"
                                               object: nil];

    [self setWindowInited: YES];
    if (fullScreen) {
        [self hideMenuBar];
    }

    return self;
}

- (id)commandField
{
    return commandField;
}

- (void)selectSessionAtIndexAction:(id)sender
{
    [TABVIEW selectTabViewItemAtIndex:[sender tag]];
}

- (void)newSessionInTabAtIndex:(id)sender
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self addNewSession:bookmark];
    }
}

- (void)closeSession:(PTYSession*)aSession
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, aSession);
#endif

    NSTabViewItem *aTabViewItem;
    int numberOfSessions;

    if ([TABVIEW indexOfTabViewItemWithIdentifier:aSession] == NSNotFound) {
        return;
    }

    numberOfSessions = [TABVIEW numberOfTabViewItems];
    if (numberOfSessions == 1 && [self windowInited]) {
        [[self window] close];
    } else {
        // now get rid of this session
        aTabViewItem = [aSession tabViewItem];
        [aSession terminate];
        [TABVIEW removeTabViewItem:aTabViewItem];
        PtyLog(@"closeSession - calling fitWindowToSessions");
        [self fitWindowToSessions];
    }
}

- (IBAction)closeCurrentSession:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal closeCurrentSession]",
          __FILE__, __LINE__);
#endif
    PTYSession *aSession = [[TABVIEW selectedTabViewItem] identifier];

    if ([aSession exited] ||
        ![[PreferencePanel sharedInstance] promptOnClose] || [[PreferencePanel sharedInstance] onlyWhenMoreTabs] ||
        (NSRunAlertPanel([NSString stringWithFormat:@"%@ #%d", [aSession name], [aSession realObjectCount]],
                     NSLocalizedStringFromTableInBundle(@"This session will be closed.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Close Session"),
                     NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"OK"),
                     NSLocalizedStringFromTableInBundle(@"Cancel",@"iTerm", [NSBundle bundleForClass: [self class]], @"Cancel")
                         ,nil) == NSAlertDefaultReturn)) {
        [self closeSession:[[TABVIEW selectedTabViewItem] identifier]];
    }
}

- (IBAction)previousSession:(id)sender
{
    NSTabViewItem *tvi = [TABVIEW selectedTabViewItem];
    [TABVIEW selectPreviousTabViewItem:sender];
    if (tvi == [TABVIEW selectedTabViewItem]) {
        [TABVIEW selectTabViewItemAtIndex:[TABVIEW numberOfTabViewItems]-1];
    }
}

- (IBAction)nextSession:(id)sender
{
    NSTabViewItem *tvi = [TABVIEW selectedTabViewItem];
    [TABVIEW selectNextTabViewItem: sender];
    if (tvi == [TABVIEW selectedTabViewItem]) {
        [TABVIEW selectTabViewItemAtIndex: 0];
    }
}

- (int)numberOfSessions
{
    return [TABVIEW numberOfTabViewItems];
}

- (PTYSession*)sessionAtIndex:(int)i
{
    NSTabViewItem* tvi = [TABVIEW tabViewItemAtIndex:i];
    return [tvi identifier];
}


- (PTYSession *)currentSession
{
    return [[TABVIEW selectedTabViewItem] identifier];
}

- (int)currentSessionIndex
{
    return ([TABVIEW indexOfTabViewItem:[TABVIEW selectedTabViewItem]]);
}

- (void)dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // Release all our sessions
    NSTabViewItem *aTabViewItem;
    for (; [TABVIEW numberOfTabViewItems]; )  {
        aTabViewItem = [TABVIEW tabViewItemAtIndex:0];
        [[aTabViewItem identifier] terminate];
        [TABVIEW removeTabViewItem: aTabViewItem];
    }

    [commandField release];
    [bottomBar release];
    [_toolbarController release];
    if (_timer) {
        [_timer invalidate];
        [findProgressIndicator setHidden:YES];
        _timer = nil;
    }
    [pbHistoryView release];
    [autocompleteView release];

    if (fullScreenTabviewTimer_) {
        [fullScreenTabviewTimer_ invalidate];
    }
    [super dealloc];
}

- (void)setWindowTitle
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal setWindowTitle]",
          __FILE__, __LINE__);
#endif
    [self setWindowTitle:[self currentSessionName]];
}

- (void)setWindowTitle:(NSString *)title
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal setWindowTitle:%@]",
          __FILE__, __LINE__, title);
#endif
    NSParameterAssert([title length] > 0);

    if ([self sendInputToAllSessions]) {
        title = [NSString stringWithFormat:@"☛%@", title];
    }

    NSUInteger number = [[iTermController sharedInstance] indexOfTerminal:self];
    if (number >= 0 && number < 9) {
        [[self window] setTitle:[NSString stringWithFormat:@"%d. %@", number+1, title]];
    } else {
        [[self window] setTitle:title];
    }
}

- (BOOL)tempTitle
{
    return tempTitle;
}

- (void)resetTempTitle
{
    tempTitle = NO;
}

- (void)sendInputToAllSessions:(NSData *)data
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal sendDataToAllSessions:]",
          __FILE__, __LINE__);
#endif
    PTYSession *aSession;
    int i;

    int n = [TABVIEW numberOfTabViewItems];
    for (i = 0; i < n; ++i) {
        aSession = [[TABVIEW tabViewItemAtIndex: i] identifier];

        if (![aSession exited]) {
            [[aSession SHELL] writeTask:data];
        }
    }
}

// NSWindow delegate methods
- (void)windowDidDeminiaturize:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidDeminiaturize:%@]",
          __FILE__, __LINE__, aNotification);
#endif
    if ([[[[self currentSession] addressBookEntry] objectForKey:KEY_BLUR] boolValue]) {
        [self enableBlur];
    } else {
        [self disableBlur];
    }
}

- (BOOL)windowShouldClose:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowShouldClose:%@]",
          __FILE__, __LINE__, aNotification);
#endif

    if ([[PreferencePanel sharedInstance] promptOnClose] &&
        (![[PreferencePanel sharedInstance] onlyWhenMoreTabs] ||
         [TABVIEW numberOfTabViewItems] > 1)) {
        return [self showCloseWindow];
    } else {
        return YES;
    }
}

- (void)windowWillClose:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowWillClose:%@]",
          __FILE__, __LINE__, aNotification);
#endif

    // tabBarControl is holding on to us, so we have to tell it to let go
    [tabBarControl setDelegate:nil];

    [self disableBlur];
    if (_fullScreen) {
        [NSMenu setMenuBarVisible:YES];
    }

    // Save frame position for last window
    if ([[[iTermController sharedInstance] terminals] count] == 1) {
        // Close the bottomBar because otherwise the wrong size
        // frame is saved.  You wouldn't want the bottomBar to
        // open automatically anyway.
        // TODO(georgen): There's a tiny bug here. If you're in instant replay
        // then the window size for the IR window is saved instead of the live
        // window.
        if (![bottomBar isHidden]) {
            [self showHideBottomBar];
        }
        if ([[PreferencePanel sharedInstance] smartPlacement]) {
            [[self window] saveFrameUsingName: [NSString stringWithFormat: WINDOW_NAME, 0]];
        } else {
            // Save frame position for window
            [[self window] saveFrameUsingName: [NSString stringWithFormat: WINDOW_NAME, framePos]];
            windowPositions[framePos] = NO;
        }
    } else {
        if (![[PreferencePanel sharedInstance] smartPlacement]) {
            // Save frame position for window
            [[self window] saveFrameUsingName: [NSString stringWithFormat: WINDOW_NAME, framePos]];
            windowPositions[framePos] = NO;
        }
    }

    [[iTermController sharedInstance] terminalWillClose:self];
}

- (void)windowWillMiniaturize:(NSNotification *)aNotification
{
    [self disableBlur];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidBecomeKey:%@]",
          __FILE__, __LINE__, aNotification);
#endif
    PtyLog(@"%s(%d):-[PseudoTerminal windowDidBecomeKey:%@]",
          __FILE__, __LINE__, aNotification);

    //[self selectSessionAtIndex: [self currentSessionIndex]];
    [[iTermController sharedInstance] setCurrentTerminal: self];

    if (_fullScreen) {
        [self hideMenuBar];
    }

    // Note: there was a bug in the old iterm that setting fonts didn't work
    // properly if the font panel was left open in focus-follows-mouse mode.
    // There was code here to close the font panel. I couldn't reproduce the old
    // bug and it was reported as bug 51 in iTerm2 so it was removed. See the
    // svn history for the old impl.

    // update the cursor
    [[[self currentSession] TEXTVIEW] refresh];
    [[[self currentSession] TEXTVIEW] setNeedsDisplay:YES];
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
    if (togglingFullScreen_) {
        PtyLog(@"windowDidResignKey returning because togglingFullScreen.");
        return;
    }
    if (fullScreenTabviewTimer_) {
        // If the window has been closed then it's possible that the
        // timer is the only object left that is holding a reference to
        // self. Retain and autorelease so that invalidating the timer
        // doesn't free self while there's still stuff going on in this
        // function.
        [self retain];
        [self autorelease];
        [fullScreenTabviewTimer_ invalidate];
        fullScreenTabviewTimer_ = nil;
    } else {
        [self hideFullScreenTabControl];
    }
    if ([[pbHistoryView window] isVisible] ||
        [[autocompleteView window] isVisible]) {
        return;
    }

    PtyLog(@"%s(%d):-[PseudoTerminal windowDidResignKey:%@]",
          __FILE__, __LINE__, aNotification);

    //[self windowDidResignMain: aNotification];

    if (_fullScreen) {
        [self hideFullScreenTabControl];
        [NSMenu setMenuBarVisible:YES];
    }
    // update the cursor
    [[[self currentSession] TEXTVIEW] refresh];
    [[[self currentSession] TEXTVIEW] setNeedsDisplay:YES];
}

- (void)windowDidResignMain:(NSNotification *)aNotification
{
    PtyLog(@"%s(%d):-[PseudoTerminal windowDidResignMain:%@]",
          __FILE__, __LINE__, aNotification);
    if (_fullScreen && !togglingFullScreen_) {
        [self toggleFullScreen:nil];
    }
    // update the cursor
    [[[self currentSession] TEXTVIEW] refresh];
    [[[self currentSession] TEXTVIEW] setNeedsDisplay:YES];
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize
{

    PtyLog(@"%s(%d):-[PseudoTerminal windowWillResize: obj=%d, proposedFrameSize width = %f; height = %f]",
          __FILE__, __LINE__, [self window], proposedFrameSize.width, proposedFrameSize.height);

    float charHeight = [self maxCharHeight:nil];
    float charWidth = [self maxCharWidth:nil];
    //NSLog(@"charSize=%fx%f", charHeight, charWidth);
    PtyLog(@"Proposed size: %fx%f", proposedFrameSize.width, proposedFrameSize.height);
    if (sender != [self window]) {
        if (!(proposedFrameSize.width > 20*charWidth + MARGIN*2)) {
            proposedFrameSize.width = 20*charWidth + MARGIN * 2;
        }
        if (!(proposedFrameSize.height > 20*charHeight)) {
            proposedFrameSize.height = 20*charHeight + MARGIN * 2;
        }
        PtyLog(@"(via sender!=self) Allowed size: %fx%f", proposedFrameSize.height, proposedFrameSize.width);
        return proposedFrameSize;
    }

    float northChange = [sender frame].size.height -
        [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.height;
    float westChange = [sender frame].size.width -
        [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.width;
    //NSLog(@"Change change: %f,%f", northChange, westChange);
    int old_height = (proposedFrameSize.height - northChange - VMARGIN*2) / charHeight + 0.5;
    int old_width = (proposedFrameSize.width - westChange - MARGIN*2) / charWidth + 0.5;
    if (old_height < 2) {
        old_height = 2;
    }
    if (old_width < 20) {
        old_width = 20;
    }
    proposedFrameSize.height = charHeight * old_height + northChange + VMARGIN*2;
    proposedFrameSize.width = charWidth * old_width + westChange + MARGIN * 2;
    //int h = proposedFrameSize.height / charHeight;
    //int w = proposedFrameSize.width / charWidth;
    //NSLog(@"New height x width is %dx%d", h, w);
    PtyLog(@"Accepted size: %fx%f", proposedFrameSize.width, proposedFrameSize.height);

    return proposedFrameSize;
}

- (void)windowDidResize:(NSNotification *)aNotification
{
    if (togglingFullScreen_) {
        PtyLog(@"windowDidResize returning because togglingFullScreen.");
        return;
    }
    NSRect frame;


#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidResize: width = %f, height = %f]",
          __FILE__, __LINE__, [[self window] frame].size.width, [[self window] frame].size.height);
#endif

    frame = [[[self currentSession] SCROLLVIEW] documentVisibleRect];

    PtyLog(@"windowDidResize - window frame is %fx%f, scrollview's visible rect frame is (%.1f, %.1f) %.1f x %.1f",
          [[self window] frame].size.width, [[self window] frame].size.height,
          frame.origin.x, frame.origin.y,
          frame.size.width, frame.size.height);

    if (frame.size.width <= 0 || frame.size.height <= 0) {
        PtyLog(@"Tried to resize to way too small.");
        return;
    }
    if (isnan(frame.size.width) || isnan(frame.size.height)) {
        PtyLog(@"Tried to resize to nan");
        return;
    }

    // Adjust the size of all the sessions.
    PtyLog(@"windowDidResize - call fitSessionsToWindow");
    [self fitSessionsToWindow];

    // Move window widgets around.
    int width, height;
    float charWidth = [self widestSessionWidth:&width];
    float charHeight = [self tallestSessionHeight:&height];
    PtyLog(@"windowDidResize: calling fitWindowtoSessionsWithWidth");
    [self fitWindowToSessionsWithWidth:width
                                       height:height
                                    charWidth:charWidth
                                   charHeight:charHeight];

    PTYSession* session = [self currentSession];
    NSString *aTitle = [NSString stringWithFormat:@"%@ (%d,%d)",
                        [self currentSessionName],
                        [session columns],
                        [session rows]];
    [self setWindowTitle: aTitle];
    tempTitle = YES;

    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermWindowDidResize" object: self userInfo: nil];
}

// PTYWindowDelegateProtocol
- (void)windowWillToggleToolbarVisibility:(id)sender
{
}

- (void)windowDidToggleToolbarVisibility:(id)sender
{
    PtyLog(@"windowDidToggleToolbarVisibility - calling fitWindowToSessions");
    [self fitWindowToSessions];
}

// Bookmarks
- (IBAction)toggleFullScreen:(id)sender
{
    PtyLog(@"toggleFullScreen called");
    PseudoTerminal *newTerminal;
    if (!_fullScreen) {
        NSScreen *currentScreen = [[[[iTermController sharedInstance] currentTerminal] window]screen];
        newTerminal = [[PseudoTerminal alloc] initWithSmartLayout:NO fullScreen:currentScreen];
        newTerminal->oldFrame_ = [[self window] frame];
    } else {
        // If a window is created while the menu bar is hidden then its
        // miniaturize button will be disabled, even if the menu bar is later
        // shown. Thus, we must show the menu bar before creating the new window.
        // It is not hidden in the other clause of this if statement because
        // hiding the menu bar must be done after setting the window's frame.
        [NSMenu setMenuBarVisible:YES];
        PtyLog(@"toggleFullScreen - allocate new terminal");
        newTerminal = [[PseudoTerminal alloc] initWithSmartLayout:NO fullScreen:nil];
    }

    _fullScreen = !_fullScreen;
    togglingFullScreen_ = true;
    newTerminal->togglingFullScreen_ = YES;

    // Save the current session so it can be made current after moving
    // tabs over to the new window.
    PTYSession *currentSession = [self currentSession];
    NSAssert(currentSession, @"No current session");
    if (_fullScreen) {
        [newTerminal _drawFullScreenBlackBackground];
    }
    PtyLog(@"toggleFullScreen - copy settings");
    [newTerminal copySettingsFrom:self];

    PtyLog(@"toggleFullScreen - calling addInTerminals");
    [[iTermController sharedInstance] addInTerminals:newTerminal];
    [newTerminal release];

    int n = [TABVIEW numberOfTabViewItems];
    int i;
    NSTabViewItem *aTabViewItem;
    PTYSession *aSession;

    newTerminal->_resizeInProgressFlag = YES;
    for (i = 0; i < n; ++i) {
        aTabViewItem = [[TABVIEW tabViewItemAtIndex:0] retain];
        aSession = [aTabViewItem identifier];
        if (_fullScreen) {
            [aSession setTransparency:0];
        } else {
            [aSession setTransparency:[[[aSession addressBookEntry] objectForKey:KEY_TRANSPARENCY] floatValue]];
        }
        // remove from our window
        PtyLog(@"toggleFullScreen - remove tab %d from old window", i);
        [TABVIEW removeTabViewItem:aTabViewItem];

        // add the session to the new terminal
        PtyLog(@"toggleFullScreen - add tab %d from old window", i);
        [newTerminal insertSession:aSession atIndex:i];
        PtyLog(@"toggleFullScreen - done inserting session", i);

        // release the tabViewItem
        [aTabViewItem release];
    }
    newTerminal->_resizeInProgressFlag = NO;
    [[newTerminal tabView] selectTabViewItemWithIdentifier:currentSession];
    BOOL fs = _fullScreen;
    PtyLog(@"toggleFullScreen - close old window", i);
    // The window close call below also releases the window controller (self).
    // This causes havoc because we keep running for a while, so we'll retain a
    // copy of ourselves and release it when we're all done.
    [self retain];
    [[self window] close];
    if (!fs) {
        PtyLog(@"toggleFullScreen - set new frame to old frame: %fx%f", oldFrame_.size.width, oldFrame_.size.height);
        [[newTerminal window] setFrame:oldFrame_ display:YES];
    } else {
        PtyLog(@"toggleFullScreen - call adjustFullScreenWindowForBottomBarChange");
        [newTerminal adjustFullScreenWindowForBottomBarChange];
        [newTerminal hideMenuBar];
    }

    if (!fs) {
        // Find the largest possible session size for the existing window frame
        // and fit the window to an imaginary session of that size.
        float charWidth = [newTerminal maxCharWidth:NULL];
        float charHeight = [newTerminal maxCharHeight:NULL];
        NSRect visibleFrame = [[newTerminal window] frame];
        PtyLog(@"toggleFullScreen - new window's frame is %fx%f", visibleFrame.size.width, visibleFrame.size.height);
        NSRect contentRect = [[newTerminal window] contentRectForFrameRect:visibleFrame];
        if (![newTerminal->bottomBar isHidden]) {
            contentRect.size.height -= [newTerminal->bottomBar frame].size.height;
        }
        if (n > 1 || ![[PreferencePanel sharedInstance] hideTab]) {
            contentRect.size.height -= [newTerminal->tabBarControl frame].size.height;
        }
        NSSize scrollContentSize = [PTYScrollView contentSizeForFrameSize:contentRect.size
                                                    hasHorizontalScroller:NO
                                                      hasVerticalScroller:(![[PreferencePanel sharedInstance] hideScrollbar])
                                                               borderType:NSNoBorder];
        NSSize textSize = scrollContentSize;
        textSize.width -= MARGIN * 2;
        int width = textSize.width / charWidth;
        int height = textSize.height / charHeight;
        PtyLog(@"toggleFullScreen: calling fitWindowToSessionsWithWidth");
        [newTerminal fitWindowToSessionsWithWidth:width height:height charWidth:charWidth charHeight:charHeight];
    }
    newTerminal->togglingFullScreen_ = NO;
    PtyLog(@"toggleFullScreen - calling fitSessionsToWindow");
    [newTerminal fitSessionsToWindow];
    PtyLog(@"toggleFullScreen - calling fitWindowToSessions");
    [newTerminal fitWindowToSessions];
    PtyLog(@"toggleFullScreen - calling setWindowTitle");
    [newTerminal setWindowTitle];
    PtyLog(@"toggleFullScreen - calling window update");
    [[newTerminal window] update];
    PtyLog(@"toggleFullScreen returning");
    togglingFullScreen_ = false;
    [self release];
}

- (BOOL)fullScreen
{
    return _fullScreen;
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender defaultFrame:(NSRect)defaultFrame
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowWillUseStandardFrame:defaultFramewidth = %f, height = %f]",
          __FILE__, __LINE__, defaultFrame.size.width, defaultFrame.size.height);
#endif
    float decorationHeight = [sender frame].size.height -
        [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.height;
    float decorationWidth = [sender frame].size.width -
        [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.width;

    float charHeight = [self maxCharHeight:nil];
    float charWidth = [self maxCharWidth:nil];

    NSRect proposedFrame;
    proposedFrame.origin.x = [sender frame].origin.x;
    proposedFrame.origin.y = [sender frame].size.height;;
    BOOL verticalOnly = NO;

    if ([[PreferencePanel sharedInstance] maxVertically] &&
        !([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask)) {
        verticalOnly = YES;
    }
    if (verticalOnly) {
        proposedFrame.size.width = [sender frame].size.width;
    } else {
        proposedFrame.size.width = decorationWidth + floor(defaultFrame.size.width / charWidth) * charWidth;
    }
    proposedFrame.size.height = decorationHeight + floor(defaultFrame.size.height / charHeight) * charHeight;

    PtyLog(@"For zoom, default frame is %fx%f, proposed frame is %f,%f %fx%f",
           defaultFrame.size.width, defaultFrame.size.height,
           proposedFrame.origin.x, proposedFrame.origin.y,
           proposedFrame.size.width, proposedFrame.size.height);
    return proposedFrame;
}

- (void)windowWillShowInitial
{
    PTYWindow* window = (PTYWindow*)[self window];
    if (([[[iTermController sharedInstance] terminals] count] == 1) ||
        (![[PreferencePanel sharedInstance] smartPlacement])) {
        NSRect frame = [window frame];
        [self setFramePos];
        [window setFrameUsingName:[NSString stringWithFormat:WINDOW_NAME, framePos]];
        frame.origin = [window frame].origin;
        frame.origin.y += [window frame].size.height - frame.size.height;
        [window setFrame:frame display:NO];
    } else {
        [window smartLayout];
    }
}

- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height
{
    PtyLog(@"sessionInitiatedResize");
    // ignore resize request when we are in full screen mode.
    if (_fullScreen) {
        PtyLog(@"sessionInitiatedResize - in full screen mode");
        return;
    }

    [self safelySetSessionSize:session rows:height columns:width];
    PtyLog(@"sessionInitiatedResize - calling fitWindowToSession");
    [self fitWindowToSession:session];
    PtyLog(@"sessionInitiatedResize - calling fitSessionsToWindow");
    [self fitSessionsToWindow];
}

// Contextual menu
- (void)editCurrentSession:(id)sender
{
    PTYSession* session = [self currentSession];
    if (!session) {
        return;
    }
    Bookmark* bookmark = [session addressBookEntry];
    if (!bookmark) {
        return;
    }
    NSString* newGuid = [session divorceAddressBookEntryFromPreferences];
    [[PreferencePanel sessionsInstance] openToBookmark:newGuid];
}

- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu
{
    // Constructs the context menu for right-clicking on a terminal when
    // right click does not paste.
    int nextIndex;
    NSMenuItem *aMenuItem;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal menuForEvent]", __FILE__, __LINE__);
#endif

    if (theMenu == nil) {
        return;
    }

    // Bookmarks
    [theMenu insertItemWithTitle:NSLocalizedStringFromTableInBundle(@"New",
                                                                    @"iTerm",
                                                                    [NSBundle bundleForClass:[self class]],
                                                                    @"Context menu")
                          action:nil
                   keyEquivalent:@""
                         atIndex:0];
    nextIndex = 1;

    // Create a menu with a submenu to navigate between tabs if there are more than one
    if ([TABVIEW numberOfTabViewItems] > 1) {
        [theMenu insertItemWithTitle:NSLocalizedStringFromTableInBundle(@"Select",
                                                                        @"iTerm",
                                                                        [NSBundle bundleForClass:[self class]],
                                                                        @"Context menu")
                              action:nil
                       keyEquivalent:@""
                             atIndex:nextIndex];

        NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@""];
        int i;

        for (i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
            aMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ #%d",
                                                           [[TABVIEW tabViewItemAtIndex: i] label],
                                                           i+1]
                                                   action:@selector(selectTab:)
                                            keyEquivalent:@""];
            [aMenuItem setRepresentedObject:[[TABVIEW tabViewItemAtIndex:i] identifier]];
            [aMenuItem setTarget:TABVIEW];
            [tabMenu addItem:aMenuItem];
            [aMenuItem release];
        }
        [theMenu setSubmenu:tabMenu forItem:[theMenu itemAtIndex:nextIndex]];
        [tabMenu release];
        ++nextIndex;
    }

    // Separator
    [theMenu insertItem:[NSMenuItem separatorItem] atIndex: nextIndex];

    // Build the bookmarks menu
    NSMenu *aMenu = [[[NSMenu alloc] init] autorelease];

    [[iTermController sharedInstance] addBookmarksToMenu:aMenu
                                                  target:self
                                           withShortcuts:NO];
    [aMenu addItem: [NSMenuItem separatorItem]];
    NSMenuItem *tip = [[[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Press Option for New Window",
                                                                                            @"iTerm",
                                                                                            [NSBundle bundleForClass: [self class]],
                                                                                            @"Toolbar Item: New")
                                                  action:@selector(bogusSelector)
                                           keyEquivalent: @""]
                       autorelease];
    [tip setKeyEquivalentModifierMask: NSCommandKeyMask];
    [aMenu addItem: tip];
    tip = [[tip copy] autorelease];
    [tip setTitle:NSLocalizedStringFromTableInBundle(@"Open In New Window",
                                                     @"iTerm",
                                                     [NSBundle bundleForClass: [self class]],
                                                     @"Toolbar Item: New")];
    [tip setKeyEquivalentModifierMask: NSCommandKeyMask | NSAlternateKeyMask];
    [tip setAlternate:YES];
    [aMenu addItem: tip];

    [theMenu setSubmenu: aMenu forItem: [theMenu itemAtIndex: 0]];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Info
    aMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Info...",
                                                                                     @"iTerm",
                                                                                     [NSBundle bundleForClass: [self class]],
                                                                                     @"Context menu")
                                           action:@selector(editCurrentSession:)
                                    keyEquivalent:@""];
    [aMenuItem setTarget: self];
    [theMenu addItem: aMenuItem];
    [aMenuItem release];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Close current session
    aMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Close",
                                                                                     @"iTerm",
                                                                                     [NSBundle bundleForClass:[self class]],
                                                                                     @"Context menu")
                                           action:@selector(closeCurrentSession:)
                                    keyEquivalent:@""];
    [aMenuItem setTarget: self];
    [theMenu addItem: aMenuItem];
    [aMenuItem release];

}

// NSTabView
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView: willSelectTabViewItem]", __FILE__, __LINE__);
#endif
    if (![[self currentSession] exited]) {
        [[self currentSession] resetStatus];
    }
    // If the user is currently select-dragging the text view, stop it so it
    // doesn't keep going in the background.
    [[[self currentSession] TEXTVIEW] aboutToHide];

    if ([[autocompleteView window] isVisible]) {
        [autocompleteView close];
    }
}

- (void)enableBlur
{
    id window = [self window];
    if (!_fullScreen &&
        nil != window &&
        [window respondsToSelector:@selector(enableBlur)]) {
        [window enableBlur];
    }
}

- (void)disableBlur
{
    id window = [self window];
    if (!_fullScreen &&
        nil != window &&
        [window respondsToSelector:@selector(disableBlur)]) {
        [window disableBlur];
    }
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView: didSelectTabViewItem]", __FILE__, __LINE__);
#endif

    [[tabViewItem identifier] resetStatus];

    // Background tabs' timers run infrequently so make sure the display is
    // up to date to avoid a jump when it's shown.
    [[[tabViewItem identifier] TEXTVIEW] setNeedsDisplay:YES];
    [[tabViewItem identifier] updateDisplay];
    [[tabViewItem identifier] scheduleUpdateIn:kFastTimerIntervalSec];

    if (_fullScreen) {
        [self _drawFullScreenBlackBackground];
    } else {
        [[tabViewItem identifier] setLabelAttribute];
        [self setWindowTitle];
    }

    [[self window] makeFirstResponder:[[tabViewItem identifier] TEXTVIEW]];
    if ([[[[tabViewItem identifier] addressBookEntry] objectForKey:KEY_BLUR] boolValue]) {
        [self enableBlur];
    } else {
        [self disableBlur];
    }

    if (![instantReplaySubview isHidden]) {
        [self updateInstantReplay];
    }
    // Post notifications
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermSessionBecameKey" object: [tabViewItem identifier]];
    [self showOrHideInstantReplayBar];
}

- (void)showOrHideInstantReplayBar
{
    PTYSession* aSession = [self currentSession];
    if ([aSession liveSession]) {
        [self setInstantReplayBarVisible:YES];
    } else {
        [self setInstantReplayBarVisible:NO];
    }
}

- (void)tabView:(NSTabView *)tabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView:willRemoveTabViewItem]", __FILE__, __LINE__);
#endif
}

- (void)tabView:(NSTabView *)tabView willAddTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView:willAddTabViewItem]", __FILE__, __LINE__);
#endif

    [self tabView:tabView willInsertTabViewItem:tabViewItem atIndex:[tabView numberOfTabViewItems]];
}

- (void)tabView:(NSTabView *)tabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)anIndex
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView:willInsertTabViewItem:atIndex:%d]", __FILE__, __LINE__, anIndex);
#endif
    [[tabViewItem identifier] setParent:self];
}

- (BOOL)tabView:(NSTabView*)tabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem
{
    PTYSession *aSession = [tabViewItem identifier];

    return [aSession exited] ||
        ![[PreferencePanel sharedInstance] promptOnClose] || [[PreferencePanel sharedInstance] onlyWhenMoreTabs] ||
        (NSRunAlertPanel([NSString stringWithFormat:@"%@ #%d", [aSession name], [aSession realObjectCount]],
                        NSLocalizedStringFromTableInBundle(@"This session will be closed.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Close Session"),
                        NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"OK"),
                        NSLocalizedStringFromTableInBundle(@"Cancel",@"iTerm", [NSBundle bundleForClass: [self class]], @"Cancel")
                        ,nil) == NSAlertDefaultReturn);

}

- (BOOL)tabView:(NSTabView*)aTabView shouldDragTabViewItem:(NSTabViewItem *)tabViewItem fromTabBar:(PSMTabBarControl *)tabBarControl
{
    return YES;
}

- (BOOL)tabView:(NSTabView*)aTabView shouldDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl
{
    //NSLog(@"shouldDropTabViewItem: %@ inTabBar: %@", [tabViewItem label], tabBarControl);
    return YES;
}

- (void)tabView:(NSTabView*)aTabView didDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)aTabBarControl
{
    //NSLog(@"didDropTabViewItem: %@ inTabBar: %@", [tabViewItem label], aTabBarControl);
    PTYSession *aSession = [tabViewItem identifier];
    PseudoTerminal *term = [aTabBarControl delegate];

    [[aSession SCREEN] resizeWidth:[aSession columns] height:[aSession rows]];
    PtyLog(@"tabView:didDropTabViewItem - calling shell setWidth:%d height:%d", [aSession columns], [aSession rows]);
    [[aSession SHELL] setWidth:[aSession columns]  height:[aSession rows]];
    if ([[term tabView] numberOfTabViewItems] == 1) {
        PtyLog(@"didDropTabViewItem - calling fitWindowToSessions");
        [term fitWindowToSessions];
    }

    int i;
    for (i=0; i < [aTabView numberOfTabViewItems]; ++i) {
        PTYSession *currentSession = [[aTabView tabViewItemAtIndex:i] identifier];
        [currentSession setObjectCount:i+1];
    }
    if ([aSession liveSession] && [term->instantReplaySubview isHidden]) {
        [term showHideInstantReplay];
    }
    [self showOrHideInstantReplayBar];
}

- (void)tabView:(NSTabView *)aTabView closeWindowForLastTabViewItem:(NSTabViewItem *)tabViewItem
{
    //NSLog(@"closeWindowForLastTabViewItem: %@", [tabViewItem label]);
    [[self window] close];
}

- (NSImage *)tabView:(NSTabView *)aTabView imageForTabViewItem:(NSTabViewItem *)tabViewItem offset:(NSSize *)offset styleMask:(unsigned int *)styleMask
{
    NSImage *viewImage;

    if (tabViewItem == [aTabView selectedTabViewItem]) {
        NSView *textview = [tabViewItem view];
        NSRect tabFrame = [tabBarControl frame];
        int tabHeight = tabFrame.size.height;

        NSRect contentFrame, viewRect;
        contentFrame = viewRect = [textview frame];
        contentFrame.size.height += tabHeight;

        // grabs whole tabview image
        viewImage = [[[NSImage alloc] initWithSize:contentFrame.size] autorelease];
        NSImage *tabViewImage = [[[NSImage alloc] init] autorelease];

        [textview lockFocus];
        NSBitmapImageRep *tabviewRep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:viewRect] autorelease];
        [tabViewImage addRepresentation:tabviewRep];
        [textview unlockFocus];

        [viewImage lockFocus];
        //viewRect.origin.x += 10;
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) {
            viewRect.origin.y += tabHeight;
        }
        [tabViewImage compositeToPoint:viewRect.origin operation:NSCompositeSourceOver];
        [viewImage unlockFocus];

        //draw over where the tab bar would usually be
        [viewImage lockFocus];
        [[NSColor windowBackgroundColor] set];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            tabFrame.origin.y += viewRect.size.height;
        }
        NSRectFill(tabFrame);
        //draw the background flipped, which is actually the right way up
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
        tabFrame.origin.y = -tabFrame.origin.y - tabFrame.size.height;
        [(id <PSMTabStyle>)[[aTabView delegate] style] drawBackgroundInRect:tabFrame];
        [transform invert];
        [transform concat];

        [viewImage unlockFocus];

        offset->width = [(id <PSMTabStyle>)[tabBarControl style] leftMarginForTabBarControl];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            offset->height = 22;
        } else {
            offset->height = viewRect.size.height + 22;
        }
        *styleMask = NSBorderlessWindowMask;
    } else {
        NSView *textview = [tabViewItem view];
        NSRect tabFrame = [tabBarControl frame];
        int tabHeight = tabFrame.size.height;

        NSRect contentFrame, viewRect;
        contentFrame = viewRect = [textview frame];
        contentFrame.size.height += tabHeight;

        // grabs whole tabview image
        viewImage = [[[NSImage alloc] initWithSize:contentFrame.size] autorelease];
        NSImage *textviewImage = [[[NSImage alloc] initWithSize:viewRect.size] autorelease];

        [textviewImage setFlipped: YES];
        [textviewImage lockFocus];
        //draw the background flipped, which is actually the right way up
        [[[tabViewItem identifier] TEXTVIEW] drawRect:viewRect];
        [textviewImage unlockFocus];

        [viewImage lockFocus];
        //viewRect.origin.x += 10;
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) {
            viewRect.origin.y += tabHeight;
        }
        [textviewImage compositeToPoint:viewRect.origin operation:NSCompositeSourceOver];
        [viewImage unlockFocus];

        //draw over where the tab bar would usually be
        [viewImage lockFocus];
        [[NSColor windowBackgroundColor] set];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            tabFrame.origin.y += viewRect.size.height;
        }
        NSRectFill(tabFrame);
        //draw the background flipped, which is actually the right way up
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
        tabFrame.origin.y = -tabFrame.origin.y - tabFrame.size.height;
        [(id <PSMTabStyle>)[[aTabView delegate] style] drawBackgroundInRect:tabFrame];
        [transform invert];
        [transform concat];

        [viewImage unlockFocus];

        offset->width = [(id <PSMTabStyle>)[tabBarControl style] leftMarginForTabBarControl];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            offset->height = 22;
        }
        else {
            offset->height = viewRect.size.height + 22;
        }
        *styleMask = NSBorderlessWindowMask;
    }

    return viewImage;
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView
{
    PtyLog(@"%s(%d):-[PseudoTerminal tabViewDidChangeNumberOfTabViewItems]", __FILE__, __LINE__);

    // check window size in case tabs have to be hidden or shown
    if (([TABVIEW numberOfTabViewItems] == 1) || ([[PreferencePanel sharedInstance] hideTab] &&
        ([TABVIEW numberOfTabViewItems] > 1 && [tabBarControl isHidden]))) {
        PtyLog(@"tabViewDidChangeNumberOfTabViewItems - calling fitWindowToSessions");
        [self fitWindowToSessions];
    }

    int i;
    for (i=0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYSession *aSession = [[TABVIEW tabViewItemAtIndex: i] identifier];
        [aSession setObjectCount:i+1];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermNumberOfSessionsDidChange" object: self userInfo: nil];
}

- (NSMenu *)tabView:(NSTabView *)tabView menuForTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabViewContextualMenu]", __FILE__, __LINE__);
#endif
    NSMenuItem *item;
    NSMenu *rootMenu = [[[NSMenu alloc] init] autorelease];

    // Create a menu with a submenu to navigate between tabs if there are more than one
    if ([TABVIEW numberOfTabViewItems] > 1) {
        NSMenu *tabMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
        NSUInteger count = 1;
        for (NSTabViewItem *tab in [TABVIEW tabViewItems]) {
            NSString *title = [NSString stringWithFormat:@"%@ #%d", [tab label], count++];
            item = [[[NSMenuItem alloc] initWithTitle:title
                                               action:@selector(selectTab:)
                                        keyEquivalent:@""] autorelease];
            [item setRepresentedObject:[tab identifier]];
            [item setTarget:TABVIEW];
            [tabMenu addItem: item];
        }

        [rootMenu addItemWithTitle:ITLocalizedString(@"Select")
                            action:nil
                     keyEquivalent:@""];
        [rootMenu setSubmenu:tabMenu forItem:[rootMenu itemAtIndex:0]];
        [rootMenu addItem: [NSMenuItem separatorItem]];
   }

    // add tasks
    item = [[[NSMenuItem alloc] initWithTitle:ITLocalizedString(@"Close Tab")
                                       action:@selector(closeTabContextualMenuAction:)
                                keyEquivalent:@""] autorelease];
    [item setRepresentedObject:tabViewItem];
    [rootMenu addItem:item];

    if ([TABVIEW numberOfTabViewItems] > 1) {
        item = [[[NSMenuItem alloc] initWithTitle:ITLocalizedString(@"Move to new window")
                                           action:@selector(moveTabToNewWindowContextualMenuAction:)
                                    keyEquivalent:@""] autorelease];
        [item setRepresentedObject:tabViewItem];
        [rootMenu addItem:item];
    }

    return rootMenu;
}

- (PSMTabBarControl *)tabView:(NSTabView *)aTabView newTabBarForDraggedTabViewItem:(NSTabViewItem *)tabViewItem atPoint:(NSPoint)point
{
    PseudoTerminal *term;
    PTYSession *aSession = [tabViewItem identifier];

    if (aSession == nil) {
        return nil;
    }

    // create a new terminal window
    term = [[[PseudoTerminal alloc] initWithSmartLayout:NO fullScreen:nil] autorelease];
    if (term == nil) {
        return nil;
    }

    [term copySettingsFrom:self];

    [[iTermController sharedInstance] addInTerminals: term];

    if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
        [[term window] setFrameTopLeftPoint:point];
    } else {
        [[term window] setFrameOrigin:point];
    }

    return [term tabBarControl];
}

- (NSString *)tabView:(NSTabView *)aTabView toolTipForTabViewItem:(NSTabViewItem *)aTabViewItem
{
    NSDictionary *ade = [[aTabViewItem identifier] addressBookEntry];

    NSString *temp = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Name: %@\nCommand: %@",
                                                                                   @"iTerm",
                                                                                   [NSBundle bundleForClass:[self class]],
                                                                                   @"Tab Tooltips"),
                      [ade objectForKey:KEY_NAME],
                      [ITAddressBookMgr bookmarkCommand:ade]];

    return temp;

}

- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem
{
    [tabView selectTabViewItem:tabViewItem];
    [self editCurrentSession:self];
}

- (void)tabViewDoubleClickTabBar:(NSTabView *)tabView
{
    Bookmark* prototype = [[BookmarkModel sharedInstance] defaultBookmark];
    if (!prototype) {
        NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
        [aDict setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
        prototype = aDict;
    }
    [self addNewSession:prototype];
}

- (void)setLabelColor:(NSColor *)color forTabViewItem:tabViewItem
{
    if ([[PreferencePanel sharedInstance] highlightTabLabels]) {
        [tabBarControl setLabelColor:color forTabViewItem:tabViewItem];
    } else {
        [tabBarControl setLabelColor:[NSColor blackColor] forTabViewItem:tabViewItem];
    }

}

- (PTYTabView *)tabView
{
    return TABVIEW;
}

- (IBAction)searchPrevious:(id)sender
{
    [[FindCommandHandler sharedInstance] setSearchString:[findBarTextField stringValue]];
    [[FindCommandHandler sharedInstance] setIgnoresCase: [ignoreCase state]];
    [self _newSearch:[[FindCommandHandler sharedInstance] findPreviousWithOffset:1]];
}

- (IBAction)searchNext:(id)sender
{
    [[FindCommandHandler sharedInstance] setSearchString:[findBarTextField stringValue]];
    [[FindCommandHandler sharedInstance] setIgnoresCase: [ignoreCase state]];
    [self _newSearch:[[FindCommandHandler sharedInstance] findNext]];
}

- (IBAction)searchNextPrev:(id)sender
{
    if ([sender selectedSegment] == 0) {
        [self searchPrevious:sender];
    } else {
        [self searchNext:sender];
    }
    [sender setSelected:NO forSegment:[sender selectedSegment]];
}

- (void)findWithSelection
{
    FindCommandHandler* fch = [FindCommandHandler sharedInstance];
    [self _newSearch:[fch findWithSelection]];
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    NSTextField *field = [aNotification object];
    if (field != findBarTextField) {
        return;
    }

    if ([previousFindString length] == 0) {
        [[[self currentSession] TEXTVIEW] resetFindCursor];
    } else {
        NSRange range =  [[findBarTextField stringValue] rangeOfString:previousFindString];
        if (range.location != 0) {
            [[[self currentSession] TEXTVIEW] resetFindCursor];
        }
    }
    [previousFindString setString:[findBarTextField stringValue]];
    [[FindCommandHandler sharedInstance] setSearchString:[findBarTextField stringValue]];
    [[FindCommandHandler sharedInstance] setIgnoresCase: [ignoreCase state]];
    [self _newSearch:[[FindCommandHandler sharedInstance] findPreviousWithOffset:0]];
};

- (void)deselectFindBarTextField
{
    NSText* fieldEditor = [[self window] fieldEditor:YES forObject:findBarTextField];
    [fieldEditor setSelectedRange:NSMakeRange([[fieldEditor string] length], 0)];
    [fieldEditor setNeedsDisplay:YES];
}

- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector
{
    if (control == findBarTextField && commandSelector == @selector(cancelOperation:)) {
        // Have the esc key close the find bar instead of erasing its contents.
        [self closeFindBar:self];
        return YES;
    } else if (control == findBarTextField && commandSelector == @selector(insertBacktab:)) {
        if ([[[self currentSession] TEXTVIEW] growSelectionLeft]) {
            NSString* text = [[[self currentSession] TEXTVIEW] selectedText];
            if (text) {
                [[[self currentSession] TEXTVIEW] copy:self];
                [findBarTextField setStringValue:text];
                [self deselectFindBarTextField];
                [self searchPrevious:self];
            }
        }
        return YES;
    } else if (control == findBarTextField && commandSelector == @selector(insertTab:)) {
        [[[self currentSession] TEXTVIEW] growSelectionRight];
        NSString* text = [[[self currentSession] TEXTVIEW] selectedText];
        if (text) {
            [[[self currentSession] TEXTVIEW] copy:self];
            [findBarTextField setStringValue:text];
            [self deselectFindBarTextField];
        }
        return YES;
    } else if (control == findBarTextField && commandSelector == @selector(insertNewlineIgnoringFieldEditor:)) {
        // Alt-enter
        PTYTextView* textview = [[self currentSession] TEXTVIEW];
        [textview copy:nil];
        NSString* text = [textview selectedTextWithPad:NO];
        [[self currentSession] pasteString:text];
        [[self window] makeFirstResponder:[[self currentSession] TEXTVIEW]];
        return YES;
    } else {
        return NO;
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    int move = [[[aNotification userInfo] objectForKey:@"NSTextMovement"] intValue];
    NSControl *postingObject = [aNotification object];
    if (postingObject == findBarTextField) {
        [previousFindString setString:@""];
        switch (move) {
            case NSReturnTextMovement:
                // Return key
                if ([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) {
                    [self searchNext:self];
                } else {
                    [self searchPrevious:self];
                }
                break;
        }
        return;
    }

    switch (move) {
        case NSReturnTextMovement:
            [self sendCommand: nil];
            break;
        case NSTabTextMovement:
        {
            Bookmark* prototype = [[BookmarkModel sharedInstance] defaultBookmark];
            if (!prototype) {
                NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
                [ITAddressBookMgr setDefaultsInBookmark:aDict];
                [aDict setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
                prototype = aDict;
            }

            [self addNewSession:prototype
                    withCommand:[commandField stringValue]];
            break;
        }
        default:
            break;
    }
}

- (BOOL)isInitialized
{
    return TABVIEW != nil;
}

// Toggle bottom bar.
- (void)showHideBottomBar
{
    BOOL hide = ![bottomBar isHidden];
    [bottomBar setHidden:hide];
    [self arrangeBottomBarSubviews];
    if (_fullScreen) {
        [self adjustFullScreenWindowForBottomBarChange];
    } else {
        PtyLog(@"showHideFindBar - calling fitWindowToSessions");
        [self fitWindowToSessions];
    }

    // On OS X 10.5.8, the scroll bar and resize indicator are messed up at this point. Resizing the tabview fixes it. This seems to be fixed in 10.6.
    NSRect tvframe = [TABVIEW frame];
    tvframe.size.height += 1;
    [TABVIEW setFrame: tvframe];
    tvframe.size.height -= 1;
    [TABVIEW setFrame: tvframe];

    if (hide) {
        [[self window] makeFirstResponder:[[self currentSession] TEXTVIEW]];
    }
}

// Arrange find, instant replay subviews within bottom bar.
- (void)arrangeBottomBarSubviews
{
    NSRect frame = NSMakeRect(0, 0, [[self window] frame].size.width, 0);
    NSRect irFrame = [instantReplaySubview frame];
    NSRect fbFrame = [findBarSubview frame];
    if (![instantReplaySubview isHidden]) {
        irFrame.origin.y = frame.size.height;
        frame.size.height += irFrame.size.height;
    }
    if (![findBarSubview isHidden]) {
        fbFrame.origin.y = frame.size.height;
        frame.size.height += [findBarSubview frame].size.height;
    }
    [bottomBar setFrame:frame];
    [instantReplaySubview setFrame:irFrame];
    [findBarSubview setFrame:fbFrame];
}

- (NSString*)stringForTimestamp:(long long)timestamp
{
    time_t startTime = timestamp / 1000000;
    time_t now = time(NULL);
    struct tm startTimeParts;
    struct tm nowParts;
    localtime_r(&startTime, &startTimeParts);
    localtime_r(&now, &nowParts);
    NSDateFormatter* fmt = [[[NSDateFormatter alloc] init] autorelease];
    [fmt setDateStyle:NSDateFormatterShortStyle];
    if (startTimeParts.tm_year != nowParts.tm_year ||
        startTimeParts.tm_yday != nowParts.tm_yday) {
        [fmt setDateStyle:NSDateFormatterShortStyle];
    } else {
        [fmt setDateStyle:NSDateFormatterNoStyle];
    }
    [fmt setTimeStyle:NSDateFormatterMediumStyle];
    NSDate* date = [NSDate dateWithTimeIntervalSince1970:startTime];
    NSString* result = [fmt stringFromDate:date];
    return result;
}

// Refresh the widgets in the instant replay bar.
- (void)updateInstantReplay
{
    DVR* dvr = [[self currentSession] dvr];
    DVRDecoder* decoder = nil;

    if (dvr) {
        decoder = [[self currentSession] dvrDecoder];
    }
    if (dvr && [decoder timestamp] != [dvr lastTimeStamp]) {
        [currentTime setStringValue:[self stringForTimestamp:[decoder timestamp]]];
        [currentTime sizeToFit];
        float range = ((float)([dvr lastTimeStamp] - [dvr firstTimeStamp])) / 1000000.0;
        if (range > 0) {
            float offset = ((float)([decoder timestamp] - [dvr firstTimeStamp])) / 1000000.0;
            float frac = offset / range;
            [irSlider setFloatValue:frac];
        }
    } else {
        // Live view
        dvr = [[[self currentSession] SCREEN] dvr];
        [irSlider setFloatValue:1.0];
        [currentTime setStringValue:@"Live View"];
        [currentTime sizeToFit];
    }
    [earliestTime setStringValue:[self stringForTimestamp:[dvr firstTimeStamp]]];
    [earliestTime sizeToFit];
    [latestTime setStringValue:@"Now"];

    // Align the currentTime with the slider
    NSRect f = [currentTime frame];
    NSRect sf = [irSlider frame];
    NSRect etf = [earliestTime frame];
    float newSliderX = etf.origin.x + etf.size.width + 10;
    float dx = newSliderX - sf.origin.x;
    sf.origin.x = newSliderX;
    sf.size.width -= dx;
    [irSlider setFrame:sf];
    float newX = [irSlider floatValue] * sf.size.width + sf.origin.x - f.size.width / 2;
    if (newX + f.size.width > sf.origin.x + sf.size.width) {
        newX = sf.origin.x + sf.size.width - f.size.width;
    }
    if (newX < sf.origin.x) {
        newX = sf.origin.x;
    }
    [currentTime setFrameOrigin:NSMakePoint(newX, f.origin.y)];
}

- (IBAction)irButton:(id)sender
{
    switch ([sender selectedSegment]) {
        case 0:
            [self irAdvance:-1];
            break;

        case 1:
            [self irAdvance:1];
            break;

    }
    [[self window] makeFirstResponder:[[self currentSession] TEXTVIEW]];
    [sender setSelected:NO forSegment:[sender selectedSegment]];
}

- (void)irAdvance:(int)dir
{
    if (![[self currentSession] liveSession]) {
        if (dir > 0) {
            // Can't go forward in time from live view (though that would be nice!)
            NSBeep();
            return;
        }
        [self replaySession:[self currentSession]];
    }
    [[self currentSession] irAdvance:dir];
    if (![instantReplaySubview isHidden]) {
        [self updateInstantReplay];
    }
}

// Toggle instant replay bar.
- (void)showHideInstantReplay
{
    BOOL hide = ![instantReplaySubview isHidden];
    if (!hide) {
        [self updateInstantReplay];
    }
    [instantReplaySubview setHidden:hide];
    [self arrangeBottomBarSubviews];
    if (_fullScreen) {
        [self adjustFullScreenWindowForBottomBarChange];
    } else {
        PtyLog(@"showHideFindBar - calling fitWindowToSessions");
        [self fitWindowToSessions];
    }

    // On OS X 10.5.8, the scroll bar and resize indicator are messed up at this point. Resizing the tabview fixes it. This seems to be fixed in 10.6.
    NSRect tvframe = [TABVIEW frame];
    tvframe.size.height += 1;
    [TABVIEW setFrame: tvframe];
    tvframe.size.height -= 1;
    [TABVIEW setFrame: tvframe];

    if (([findBarSubview isHidden] && [instantReplaySubview isHidden] && ![bottomBar isHidden]) ||
        ((![findBarSubview isHidden] || ![instantReplaySubview isHidden]) && [bottomBar isHidden])) {
        [self showHideBottomBar];
    }
    if (!hide) {
        [[self window] makeFirstResponder:[[self currentSession] TEXTVIEW]];
    }
}

- (void)showHideFindBar
{
    BOOL hide = ![findBarSubview isHidden];
    NSObject* firstResponder = [[self window] firstResponder];
    NSText* currentEditor = [findBarTextField currentEditor];
    if (hide && (!currentEditor || currentEditor != firstResponder)) {
        // The bar is visible but doesn't have focus. Just set the focus.
        [[self window] makeFirstResponder:findBarTextField];
        return;
    }
    if (hide && _timer) {
        [_timer invalidate];
        _timer = nil;
        [findProgressIndicator setHidden:YES];
    }
    [findBarSubview setHidden:hide];
    [self arrangeBottomBarSubviews];
    if (_fullScreen) {
        [self adjustFullScreenWindowForBottomBarChange];
    } else {
        PtyLog(@"showHideFindBar - calling fitWindowToSessions");
        [self fitWindowToSessions];
    }

    // On OS X 10.5.8, the scroll bar and resize indicator are messed up at this point. Resizing the tabview fixes it. This seems to be fixed in 10.6.
    NSRect tvframe = [TABVIEW frame];
    tvframe.size.height += 1;
    [TABVIEW setFrame: tvframe];
    tvframe.size.height -= 1;
    [TABVIEW setFrame: tvframe];

    if (!hide) {
        [[self window] makeFirstResponder:findBarTextField];
    } else {
        [[self window] makeFirstResponder:[[self currentSession] TEXTVIEW]];
    }
    if (([findBarSubview isHidden] &&
         [instantReplaySubview isHidden] &&
         ![bottomBar isHidden]) ||            // subviews hidden but parent view open.
        ((![findBarSubview isHidden] ||
          ![instantReplaySubview isHidden]) &&
         [bottomBar isHidden])) {             // subview visible but parent view hidden.
        [self showHideBottomBar];
    }
}

- (IBAction)closeFindBar:(id)sender
{
    if (![findBarSubview isHidden]) {
        [self showHideFindBar];
    }
}

- (IBAction)closeInstantReplay:(id)sender
{
    if (![instantReplaySubview isHidden]) {
        if ([[self currentSession] liveSession]) {
            [self showLiveSession:[[self currentSession] liveSession] inPlaceOf:[self currentSession]];
        }
        [self showOrHideInstantReplayBar];
    }
}

- (void)fitWindowToSession:(PTYSession*)session
{
    PtyLog(@"fitWindowToSession");
    if (inSetup) {
        PtyLog(@"fitWindowToSession - in setup");
        return;
    }

    // Pick a new window size that is a multiple of the widest/tallest character in any tab but is
    // just large enough to fit this session.
    float myCharHeight = [[session TEXTVIEW] lineHeight];
    float myCharWidth = [[session TEXTVIEW] charWidth];
    int myHeight = [session rows];
    int myWidth = [session columns];

    int biggestWidth;
    int biggestHeight;
    float biggestCharHeight = [self tallestSessionHeight:&biggestHeight];
    float biggestCharWidth = [self widestSessionWidth:&biggestWidth];

    // Pick a new width and height. Quite posibly no session is this size.
    int width = (myWidth * myCharWidth) / biggestCharWidth;
    int height = ceil(((float)myHeight * myCharHeight) / biggestCharHeight);

    PtyLog(@"fitWindowToSession calling fitWindowToSessionsWithWidth");
    [self fitWindowToSessionsWithWidth:width
                                height:height
                             charWidth:biggestCharWidth
                            charHeight:biggestCharHeight];
}

- (BOOL)sendInputToAllSessions
{
    return (sendInputToAllSessions);
}

-(void)replaySession:(PTYSession *)oldSession
{
    // NSLog(@"Enter instant replay. Live session is %@", oldSession);
    NSTabViewItem* oldTabViewItem = [TABVIEW selectedTabViewItem];
    if (!oldTabViewItem) {
        return;
    }

    PTYSession *newSession;

    // Initialize a new session
    newSession = [[PTYSession alloc] init];
    // NSLog(@"New session for IR view is at %p", newSession);

    // set our preferences
    [newSession setAddressBookEntry:[oldSession addressBookEntry]];
    [[newSession SCREEN] setScrollback:0];

    // Replace the contents of the tab view item.
    int oldIndex = [TABVIEW indexOfTabViewItem:oldTabViewItem];

    // Add this session to our term and make it current
    PTYSession* liveSession = [oldTabViewItem identifier];
    [liveSession retain];
    [self replaceInSessions:newSession atIndex:oldIndex];

    [newSession setName:[oldSession name]];
    [newSession setDefaultName:[oldSession defaultName]];
    [newSession release];

    // Put the new session in DVR mode and pass it the old session, which it
    // keeps a reference to.
    [newSession setDvr:[[oldSession SCREEN] dvr] liveSession:liveSession];
    [liveSession release];

    // TODO(georgen): the hidden window can resize itself and the FakeWindow
    // needs to pass that on to the SCREEN. Otherwise the DVR playback into the
    // time after cmd-d was pressed (but before the present) has the wrong
    // window size.
    [oldSession setFakeParent:[[FakeWindow alloc] initFromRealWindow:self session:oldSession]];

    // This starts the new session's update timer
    [newSession updateDisplay];
    if ([instantReplaySubview isHidden]) {
        [self showHideInstantReplay];
    }
}

- (void)showLiveSession:(PTYSession*)liveSession inPlaceOf:(PTYSession*)replaySession
{
    // NSLog(@"Go live. IR session is %@, live is %@", replaySession, liveSession);

    [replaySession cancelTimers];
    int oldIndex = [TABVIEW indexOfTabViewItemWithIdentifier:replaySession];
    assert(oldIndex >= 0);
    NSTabViewItem* oldTabViewItem = [TABVIEW tabViewItemAtIndex:oldIndex];
    assert(oldTabViewItem);
    [liveSession setAddressBookEntry:[replaySession addressBookEntry]];
    FakeWindow* fakeWindow = [liveSession fakeWindow];

    [self replaceSession:liveSession atIndex:oldIndex];
    [fakeWindow rejoin:self];
    [self updateInstantReplay];
    [self showHideInstantReplay];
    [liveSession setParent:self];
}

- (void)windowSetFrameTopLeftPoint:(NSPoint)point
{
    [[self window] setFrameTopLeftPoint:point];
}

- (void)windowPerformMiniaturize:(id)sender
{
    [[self window] performMiniaturize:sender];
}

- (void)windowDeminiaturize:(id)sender
{
    [[self window] deminiaturize:sender];
}

- (void)windowOrderFront:(id)sender
{
    [[self window] orderFront:sender];
}

- (void)windowOrderBack:(id)sender
{
    [[self window] orderBack:sender];
}

- (BOOL)windowIsMiniaturized
{
    return [[self window] isMiniaturized];
}

- (NSRect)windowFrame
{
    return [[self window] frame];
}

- (NSScreen*)windowScreen
{
    return [[self window] screen];
}

- (IBAction)irSliderMoved:(id)sender
{
    if ([irSlider floatValue] == 1.0) {
        if ([[self currentSession] liveSession]) {
            [self showLiveSession:[[self currentSession] liveSession] inPlaceOf:[self currentSession]];
        }
    } else {
        if (![[self currentSession] liveSession]) {
            [self replaySession:[self currentSession]];
        }
        [[self currentSession] irSeekToAtLeast:[self timestampForFraction:[irSlider floatValue]]];
    }
    [self updateInstantReplay];
}

- (IBAction)irPrev:(id)sender
{
    if (![[PreferencePanel sharedInstance] instantReplay]) {
        NSRunAlertPanel(@"Feature Disabled",
                        @"Instant Replay is disabled. Please turn it on in Preferences under the General tab.",
                        @"OK",
                        nil,
                        nil);
        return;
    }
    [self irAdvance:-1];
    [[self window] makeFirstResponder:[[self currentSession] TEXTVIEW]];
}

- (IBAction)irNext:(id)sender
{
    [self irAdvance:1];
    [[self window] makeFirstResponder:[[self currentSession] TEXTVIEW]];
}

- (IBAction)openPasteHistory:(id)sender
{
    [pbHistoryView popInSession:[self currentSession]];
}

- (IBAction)openAutocomplete:(id)sender
{
    [autocompleteView popInSession:[self currentSession]];
}

@end

@implementation PseudoTerminal (Private)

- (void)_drawFullScreenBlackBackground
{
    [[[self window] contentView] lockFocus];
    [[NSColor blackColor] set];
    NSRect frame = [[self window] frame];
    if (![bottomBar isHidden]) {
        int h = [bottomBar frame].size.height;
        frame.origin.y += h;
        frame.size.height -= h;
    }
    NSRectFill(frame);
    [[[self window] contentView] unlockFocus];
}

- (void)_refreshTerminal:(NSNotification *)aNotification
{
    PtyLog(@"_refreshTerminal - calling fitWindowToSessions");
    [self fitWindowToSessions];

    // Assign counts to each session. This causes tabs to show their tab number,
    // called an objectCount. When the "compact tab" pref is toggled, this makes
    // formerly countless tabs show their counts.
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYSession *aSession = [[TABVIEW tabViewItemAtIndex:i] identifier];
        [aSession setObjectCount:i+1];
    }
}

- (void)_getSessionParameters:(NSMutableString *)command withName:(NSMutableString *)name
{
    NSRange r1, r2, currentRange;

    while (1) {
        currentRange = NSMakeRange(0,[command length]);
        r1 = [command rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r1.location == NSNotFound) break;
        currentRange.location = r1.location + 2;
        currentRange.length -= r1.location + 2;
        r2 = [command rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r2.location == NSNotFound) break;

        [parameterName setStringValue: [command substringWithRange:NSMakeRange(r1.location+2, r2.location - r1.location-2)]];
        [parameterValue setStringValue:@""];
        [NSApp beginSheet: parameterPanel
           modalForWindow: [self window]
            modalDelegate: self
           didEndSelector: nil
              contextInfo: nil];

        [NSApp runModalForWindow:parameterPanel];

        [NSApp endSheet:parameterPanel];
        [parameterPanel orderOut:self];

        [name replaceOccurrencesOfString:[command  substringWithRange:NSMakeRange(r1.location, r2.location - r1.location+2)] withString:[parameterValue stringValue] options:NSLiteralSearch range:NSMakeRange(0,[name length])];
        [command replaceOccurrencesOfString:[command  substringWithRange:NSMakeRange(r1.location, r2.location - r1.location+2)] withString:[parameterValue stringValue] options:NSLiteralSearch range:NSMakeRange(0,[command length])];
    }

    while (1) {
        currentRange = NSMakeRange(0,[name length]);
        r1 = [name rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r1.location == NSNotFound) break;
        currentRange.location = r1.location + 2;
        currentRange.length -= r1.location + 2;
        r2 = [name rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r2.location == NSNotFound) break;

        [parameterName setStringValue: [name substringWithRange:NSMakeRange(r1.location+2, r2.location - r1.location-2)]];
        [parameterValue setStringValue:@""];
        [NSApp beginSheet: parameterPanel
           modalForWindow: [self window]
            modalDelegate: self
           didEndSelector: nil
              contextInfo: nil];

        [NSApp runModalForWindow:parameterPanel];

        [NSApp endSheet:parameterPanel];
        [parameterPanel orderOut:self];

        [name replaceOccurrencesOfString:[name  substringWithRange:NSMakeRange(r1.location, r2.location - r1.location+2)] withString:[parameterValue stringValue] options:NSLiteralSearch range:NSMakeRange(0,[name length])];
    }

}

- (void)hideMenuBar
{
    NSScreen* menubarScreen = nil;
    NSScreen* currentScreen = nil;

    if ([[NSScreen screens] count] == 0) {
        return;
    }

    menubarScreen = [[NSScreen screens] objectAtIndex:0];
    currentScreen = [NSScreen mainScreen];

    if (currentScreen == menubarScreen) {
        [NSMenu setMenuBarVisible: NO];
    }
}

// Utility
+ (void)breakDown:(NSString *)cmdl cmdPath:(NSString **)cmd cmdArgs:(NSArray **)path
{
    NSMutableArray *mutableCmdArgs;
    char *cmdLine; // The temporary UTF-8 version of the command line
    char *nextChar; // The character we will process next
    char *argStart; // The start of the current argument we are processing
    char *copyPos; // The position where we are currently writing characters
    int inQuotes = 0; // Are we inside double quotes?

    mutableCmdArgs = [[NSMutableArray alloc] init];

    // The value returned by [cmdl UTF8String] is automatically freed (when the
    // autorelease context containing this is destroyed). We need to copy the
    // string, as the tokenisation is easier when we can modify string we are
    // working with.
    cmdLine = strdup([cmdl UTF8String]);
    nextChar = cmdLine;
    copyPos = cmdLine;
    argStart = cmdLine;

    if (!cmdLine) {
        // We could not allocate enough memory for the cmdLine... bailing
        *path = [[NSArray alloc] init];
        [mutableCmdArgs release];
        return;
    }

    char c;
    while ((c = *nextChar++)) {
        switch (c) {
            case '\\':
                if (*nextChar == '\0') {
                    // This is the last character, thus this is a malformed
                    // command line, we will just leave the "\" character as a
                    // literal.
                }

                // We need to copy the next character verbatim.
                *copyPos++ = *nextChar++;
                break;
            case '\"':
                // Time to toggle the quotation mode
                inQuotes = !inQuotes;
                // Note: Since we don't copy to/increment copyPos, this
                // character will be dropped from the output string.
                break;
            case ' ':
            case '\t':
            case '\n':
                if (inQuotes) {
                    // We need to copy the current character verbatim.
                    *copyPos++ = c;
                } else {
                    // Time to split the command
                    *copyPos = '\0';
                    [mutableCmdArgs addObject:[NSString stringWithUTF8String: argStart]];
                    argStart = nextChar;
                    copyPos = nextChar;
                }
                break;
            default:
                // Just copy the current character.
                // Note: This could be made more efficient for the 'normal
                // case' where copyPos is not offset from the current place we
                // are reading from. Since this function is called rarely, and
                // it isn't that slow, we will just ignore the optimisation.
                *copyPos++ = c;
                break;
        }
    }

    if (copyPos != argStart) {
        // We have data that we have not copied into mutableCmdArgs.
        *copyPos = '\0';
        [mutableCmdArgs addObject:[NSString stringWithUTF8String: argStart]];
    }

    if ([mutableCmdArgs count] > 0) {
        *cmd = [mutableCmdArgs objectAtIndex:0];
        [mutableCmdArgs removeObjectAtIndex:0];
    } else {
        // This will only occur if the input string is empty.
        // Note: The old code did nothing in this case, so neither will we.
    }

    free(cmdLine);
    *path = [NSArray arrayWithArray:mutableCmdArgs];
    [mutableCmdArgs release];
}

// Assumes all sessions are reasonable sizes.
- (void)fitWindowToSessions
{
    if (togglingFullScreen_) {
        PtyLog(@"fitWindowToSessions returning because togglingFullScreen.");
        return;
    }
    int width;
    int height;
    float charHeight = [self tallestSessionHeight:&height];
    float charWidth = [self widestSessionWidth:&width];

    PtyLog(@"fitWindowToSessions: calling fitWindowToSessionsWithWidth");
    [self fitWindowToSessionsWithWidth:width height:height charWidth:charWidth charHeight:charHeight];
    PtyLog(@"fitWindowToSessions returning.");
}

- (void)adjustFullScreenWindowForBottomBarChange
{
    if (!_fullScreen) {
        return;
    }
    PtyLog(@"adjustFullScreenWindowForBottomBarChange");

    int width;
    int height;
    float charHeight = [self maxCharHeight:&height];
    float charWidth = [self maxCharWidth:&width];

    NSRect aRect = [[self window] frame];
    height = aRect.size.height / charHeight;
    width = (aRect.size.width - MARGIN * 2) / charWidth;
    int yoffset=0;
    if (![bottomBar isHidden]) {
        int dh = [bottomBar frame].size.height / charHeight + 1;
        height -= dh;
        yoffset = [bottomBar frame].size.height;
    } else {
        yoffset = floor(aRect.size.height - charHeight * height)/2; // screen height minus one half character
    }
    aRect = NSMakeRect(floor((aRect.size.width - width * charWidth - MARGIN * 2)/2),  // screen width minus one half character and a margin
                       yoffset,
                       width * charWidth + MARGIN * 2,                        // enough width for width col plus two margins
                       charHeight * height);                                  // enough height for width rows
    [TABVIEW setFrame:aRect];
    PtyLog(@"adjustFullScreenWindowForBottomBarChange - call fitSessionsToWindow");
    [self fitSessionsToWindow];
    [self fitBottomBarToWindow];
}

- (void)fitBottomBarToWindow
{
    // Adjust the position of the bottom bar to fit properly below the tabview.
    NSRect bottomBarFrame = [bottomBar frame];
    bottomBarFrame.size.width = [TABVIEW frame].size.width;
    bottomBarFrame.origin.x = [TABVIEW frame].origin.x;
    [bottomBar setFrame: bottomBarFrame];

    NSRect findBarFrame = [findBarSubview frame];
    findBarFrame.size.width = bottomBarFrame.size.width;
    findBarFrame.origin.x = 0;
    [findBarSubview setFrame: findBarFrame];

    NSRect instantReplayFrame = [instantReplaySubview frame];
    float dWidth = instantReplayFrame.size.width - bottomBarFrame.size.width;
    NSRect sliderFrame = [irSlider frame];
    sliderFrame.size.width -= dWidth;
    instantReplayFrame.size.width = bottomBarFrame.size.width;
    [instantReplaySubview setFrame:instantReplayFrame];
    [irSlider setFrame:sliderFrame];

    [self updateInstantReplay];
}

- (void)setInstantReplayBarVisible:(BOOL)visible
{
    BOOL hide = !visible;
    if ([instantReplaySubview isHidden] != hide) {
        [self showHideInstantReplay];
    }
}

- (NSSize)getWindowDecorationSize:(int)width height:(int)height charWidth:(float)charWidth charHeight:(float)charHeight
{
    assert(!_fullScreen);

    NSSize result;
    result.height = 0;
    result.width = 0;

    if ([TABVIEW numberOfTabViewItems] + tabViewItemsBeingAdded > 1 ||
        ![[PreferencePanel sharedInstance] hideTab]) {
        result.height += [tabBarControl frame].size.height;
    }
    if (![bottomBar isHidden]) {
        result.height += [bottomBar frame].size.height;
    }

    NSSize textViewSize;
    // set desired size of textview to enough pixels to fit WIDTH*HEIGHT
    textViewSize.width = (int)ceil(charWidth * width + MARGIN * 2);
    textViewSize.height = (int)ceil(charHeight * height);

    // figure out how big the scrollview should be to achieve the desired textview size of vsize.
    NSSize scrollViewSize;
    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
    scrollViewSize = [PTYScrollView frameSizeForContentSize:textViewSize
                                      hasHorizontalScroller:NO
                                        hasVerticalScroller:hasScrollbar
                                                 borderType:NSNoBorder];

    // figure out how big the tabview should be to fit the scrollview.
    NSSize tabViewSize;
    tabViewSize = [PTYTabView frameSizeForContentSize:scrollViewSize
                                      tabViewType:[TABVIEW tabViewType]
                                      controlSize:[TABVIEW controlSize]];

    NSSize winSizeForTabViewSize;
    NSRect rect;
    rect.origin.x = 0;
    rect.origin.y = 0;
    rect.size = tabViewSize;
    winSizeForTabViewSize = [PTYWindow frameRectForContentRect:rect styleMask:[[self window] styleMask]].size;

    result.height += winSizeForTabViewSize.height - textViewSize.height;
    result.width += winSizeForTabViewSize.width - textViewSize.width;

    return result;
}

- (void)showFullScreenTabControl
{
    [tabBarBackground setHidden:NO];
    [tabBarControl setHidden:NO];

    // Ensure the tab bar is on top of all other views.
    if ([tabBarBackground superview] != nil) {
        [tabBarBackground removeFromSuperview];
    }
    [[[self window] contentView] addSubview:tabBarBackground];

    if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
        [tabBarBackground setFrameOrigin:NSMakePoint(0, [[[self window] contentView] frame].size.height -  [tabBarBackground frame].size.height)];
        [tabBarBackground setAlphaValue:0];
        [[tabBarBackground animator] setAlphaValue:1];
    } else {
        [tabBarBackground setFrameOrigin:NSMakePoint(0, 0)];
        [tabBarBackground setAlphaValue:0];
        [[tabBarBackground animator] setAlphaValue:1];
    }
}

- (void)immediatelyHideFullScreenTabControl
{
    [tabBarBackground setHidden:YES];
}

- (void)hideFullScreenTabControl
{
    if ([tabBarBackground isHidden]) {
        return;
    }
    // Fade out and then hide the tab control.
    [[tabBarBackground animator] setAlphaValue:0];
    [self performSelector:@selector(immediatelyHideFullScreenTabControl) 
               withObject:nil 
               afterDelay:[[NSAnimationContext currentContext] duration]];
}

- (void)flagsChanged:(NSEvent *)theEvent
{
    if (!_fullScreen) {
        return;
    }
    const float kCmdHoldTime = 1;
    NSUInteger modifierFlags = [theEvent modifierFlags];
    if ((modifierFlags & NSCommandKeyMask) && fullScreenTabviewTimer_ == nil) {
        fullScreenTabviewTimer_ = [[NSTimer scheduledTimerWithTimeInterval:kCmdHoldTime
                                                                    target:self
                                                                  selector:@selector(cmdHeld:)
                                                                  userInfo:nil
                                                                    repeats:NO] retain];
    } else if (!(modifierFlags & NSCommandKeyMask) && fullScreenTabviewTimer_ != nil) {
        [fullScreenTabviewTimer_ invalidate];
        fullScreenTabviewTimer_ = nil;
    }
    if (!(modifierFlags & NSCommandKeyMask)) {
        [self hideFullScreenTabControl];
    }
}

- (void)cmdHeld:(id)sender
{
    [fullScreenTabviewTimer_ release];
    fullScreenTabviewTimer_ = nil;
    if (_fullScreen) {
        [self showFullScreenTabControl];
    }
}


- (void)fitWindowToSessionsWithWidth:(int)width height:(int)height charWidth:(float)charWidth charHeight:(float)charHeight
{
    PtyLog(@"fitWindowToSessionsWithWidth:%d height:%d charWidth:%f charHeight:%f", width, height, charWidth, charHeight);
    // position the tabview and control
    NSRect aRect;
    if (_fullScreen) {
        [self adjustFullScreenWindowForBottomBarChange];
        PtyLog(@"fitWindowToSessionsWithWidth returning because in full screen mode");
        return;
    }

    NSSize decorationSize = [self getWindowDecorationSize:width height:height charWidth:charWidth charHeight:charHeight];
    PtyLog(@"Window decoration takes %1.0fx%1.0f", decorationSize.width, decorationSize.height);

    NSRect visibleFrame = [[[self window] screen] visibleFrame];

    NSSize size, vsize, winSize, tabViewSize;
    NSWindow *thisWindow = [self window];
    NSPoint topLeft;
    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];

    // This code sets up aRect to be the new size of the window.
    if (!_resizeInProgressFlag) {
        PtyLog(@"fitWindowToSessionsWithWidth - no resize in progress.");
        _resizeInProgressFlag = YES;
        // Get size of window
        aRect = [thisWindow contentRectForFrameRect:visibleFrame];
        if ([TABVIEW numberOfTabViewItems] > 1 || ![[PreferencePanel sharedInstance] hideTab]) {
            // reduce window size by hight of tabview
            aRect.size.height -= [tabBarControl frame].size.height;
        }
        // compute the max number of rows that fits in the remaining space
        if (![bottomBar isHidden]) {
            // reduce window height by size of bottomBar
            aRect.size.height -= [bottomBar frame].size.height;
        }

        // set desired size of textview to enough pixels to fit WIDTH*HEIGHT
        vsize.width = (int)ceil(charWidth * width + MARGIN * 2);
        vsize.height = (int)ceil(charHeight * height + VMARGIN*2);

        PtyLog(@"Existing session would take %1.0fx%1.0f", vsize.width, vsize.height);

        NSSize maxFrameSize = [self maxFrame].size;
        PtyLog(@"Max frame size is %1.0fx%1.0f", maxFrameSize.width, maxFrameSize.height);

        if (vsize.width + decorationSize.width > maxFrameSize.width) {
            vsize.width = (int)((maxFrameSize.width - decorationSize.width) / charWidth) * (int)charWidth;
        }
        if (vsize.height + decorationSize.height > maxFrameSize.height) {
            vsize.height = (int)((maxFrameSize.height - decorationSize.height - VMARGIN*2) / charHeight) * (int)charHeight + VMARGIN*2;
        }

        PtyLog(@"After constraining window to max content size, vsize is %1.0fx%1.0f", vsize.width, vsize.height);

        // NSLog(@"width=%d,height=%d",[[[_sessionMgr currentSession] SCREEN] width],[[[_sessionMgr currentSession] SCREEN] height]);
        PtyLog(@"fitWindowToSessionsWithWidth - want content size of %fx%f", vsize.width, vsize.height);

        // figure out how big the scrollview should be to achieve the desired textview size of vsize.
        size = [PTYScrollView frameSizeForContentSize:vsize
                                hasHorizontalScroller:NO
                                  hasVerticalScroller:hasScrollbar
                                           borderType:NSNoBorder];
        PtyLog(@"fitWindowToSessionsWithWidth - scrollview size will be %fx%f", size.width, size.height);

        [thisWindow setShowsResizeIndicator: hasScrollbar];
        PtyLog(@"Scrollview size for this text view is %fx%f", size.width, size.height);

        // figure out how big the tabview should be to fit the scrollview.
        tabViewSize = [PTYTabView frameSizeForContentSize:size
                                              tabViewType:[TABVIEW tabViewType]
                                              controlSize:[TABVIEW controlSize]];
        PtyLog(@"fitWindowToSessionsWithWidth - Tabview size for this scrollview is %fx%f", tabViewSize.width, tabViewSize.height);

        // desired size of window content
        winSize = tabViewSize;
        PtyLog(@"fitWindowToSessionsWithWidth - Baseline window size is %fx%f", winSize.width, winSize.height);
        if (![bottomBar isHidden]) {
            winSize.height += [bottomBar frame].size.height;
            PtyLog(@"fitWindowToSessionsWithWidth - Add bottomBar height to window. New window size is %fx%f", winSize.width, winSize.height);
        }
        if ([TABVIEW numberOfTabViewItems] == 1 &&
            [[PreferencePanel sharedInstance] hideTab]) {
            // The tabs are not visible at the top of the window. Set aRect appropriately.
            [tabBarControl setHidden: YES];
            aRect.origin.x = 0;
            aRect.origin.y = 0;
            if (![bottomBar isHidden]) {
                aRect.origin.y += [bottomBar frame].size.height;
            }
            aRect.size = tabViewSize;
            PtyLog(@"fitWindwoToSessionWithWidth - Set tab view size to %fx%f", aRect.size.width, aRect.size.height);
            [TABVIEW setFrame: aRect];
        } else {
            // The tabBar control is visible.
            PtyLog(@"fitWindowToSessionsWithWidth - tabs are visible. Adjusting window size...");
            [tabBarControl setHidden:NO];
            [tabBarControl setTabLocation:[[PreferencePanel sharedInstance] tabViewType]];
            winSize.height += [tabBarControl frame].size.height;
            PtyLog(@"fitWindowToSessionsWithWidth - Add tab bar control height to window height. Window size is now %fx%f",
                  winSize.width, winSize.height);
            if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
                // setup aRect to make room for the tabs at the top.
                aRect.origin.x = 0;
                aRect.origin.y = 0;
                aRect.size = tabViewSize;
                if (![bottomBar isHidden]) {
                    aRect.origin.y += [bottomBar frame].size.height;
                }
                PtyLog(@"fitWindowToSessionsWithWidth - Set tab view size to %fx%f", aRect.size.width, aRect.size.height);
                [TABVIEW setFrame: aRect];
                aRect.origin.y += aRect.size.height;
                aRect.size.height = [tabBarControl frame].size.height;
                [tabBarControl setFrame: aRect];
            } else {
                PtyLog(@"fitWindowToSessionsWithWidth - putting tabs at bottom");
                // setup aRect to make room for the tabs at the bottom.
                aRect.origin.x = 0;
                aRect.origin.y = 0;
                aRect.size.width = tabViewSize.width;
                aRect.size.height = [tabBarControl frame].size.height;
                if (![bottomBar isHidden]) {
                    aRect.origin.y += [bottomBar frame].size.height;
                }
                [tabBarControl setFrame: aRect];
                aRect.origin.y = [tabBarControl frame].size.height;
                if (![bottomBar isHidden]) {
                    aRect.origin.y += [bottomBar frame].size.height;
                }
                aRect.size.height = tabViewSize.height;
                PtyLog(@"fitWindowToSessionsWithWidth - Set tab view size to %fx%f", aRect.size.width, aRect.size.height);
                [TABVIEW setFrame: aRect];
            }
        }

        // set the style of tabs to match window style
        switch ([[PreferencePanel sharedInstance] windowStyle]) {
            case 0:
                [tabBarControl setStyleNamed:@"Metal"];
                break;
            case 1:
                [tabBarControl setStyleNamed:@"Aqua"];
                break;
            case 2:
                [tabBarControl setStyleNamed:@"Unified"];
                break;
            default:
                [tabBarControl setStyleNamed:@"Adium"];
                break;
        }

        [tabBarControl setDisableTabClose:[[PreferencePanel sharedInstance] useCompactLabel]];
        [tabBarControl setCellMinWidth: [[PreferencePanel sharedInstance] useCompactLabel]?
        [[PreferencePanel sharedInstance] minCompactTabWidth]:
        [[PreferencePanel sharedInstance] minTabWidth]];
        [tabBarControl setSizeCellsToFit: [[PreferencePanel sharedInstance] useUnevenTabs]];
        [tabBarControl setCellOptimumWidth:  [[PreferencePanel sharedInstance] optimumTabWidth]];

        // Preserve the top-left corner of the frame.
        aRect = [thisWindow frame];
        topLeft.x = aRect.origin.x;
        topLeft.y = aRect.origin.y + aRect.size.height;

        aRect.size.width = winSize.width;
        aRect.size.height = winSize.height;
        NSRect frame = [thisWindow frameRectForContentRect: aRect];
        PtyLog(@"fitWindowToSessionsWithWidth - Setting window size. For window content size %fx%f, set frame to %fx%f", aRect.size.width,
              aRect.size.height, frame.size.width, frame.size.height);
        frame.origin.x = topLeft.x;
        frame.origin.y = topLeft.y - frame.size.height;

        [[thisWindow contentView] setAutoresizesSubviews: NO];
        // This triggers a call to fitSessionsToWindow (via windowDidResize)
        PtyLog(@"fitWindowToSessionsWithWidth - Set window frame size to %fx%f", frame.size.width, frame.size.height);
        PtyLog(@"Set window to %1.0fx%1.0f", frame.size.width, frame.size.height);
        [thisWindow setFrame: frame display:YES];
        PtyLog(@"Window size is now %1.0fx%1.0f", [thisWindow frame].size.width, [thisWindow frame].size.height);
        PtyLog(@"fitWindowToSessionsWithWidth - [NSWindow setFrame] returned");
        [[thisWindow contentView] setAutoresizesSubviews: YES];

        _resizeInProgressFlag = NO;
    } else {
        PtyLog(@"fitWindowToSessionsWithWidth - there was a resize in progress.");
    }

    PtyLog(@"fitWindowToSessionsWithWidth - call fitBottomBarToWindow");
    [self fitBottomBarToWindow];

    PtyLog(@"fitWindowToSessionsWithWidth - refresh textview");
    [[[self currentSession] TEXTVIEW] setNeedsDisplay:YES];
    PtyLog(@"fitWindowToSessionsWithWidth - update tab bar");
    [tabBarControl update];
    PtyLog(@"fitWindowToSessionsWithWidth - set resize increments");
    [[self window] setResizeIncrements:NSMakeSize([self maxCharWidth:nil], [self maxCharHeight:nil])];
    PtyLog(@"fitWindowToSessionsWithWidth - return.");
}

- (float)maxCharWidth:(int*)numChars
{
    float max=0;
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYSession* session = [[TABVIEW tabViewItemAtIndex:i] identifier];
        float w =[[session TEXTVIEW] charWidth];
        PtyLog(@"maxCharWidth - session %d has %dx%d, chars are %fx%f", i, [session columns], [session rows], [[session TEXTVIEW] charWidth], [[session TEXTVIEW] lineHeight]);
        if (w > max) {
            max = w;
            if (numChars) {
                *numChars = [session columns];
            }
        }
    }
    return max;
}

- (float)maxCharHeight:(int*)numChars
{
    float max=0;
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYSession* session = [[TABVIEW tabViewItemAtIndex:i] identifier];
        float h =[[session TEXTVIEW] lineHeight];
        PtyLog(@"maxCharHeight - session %d has %dx%d, chars are %fx%f", i, [session columns], [session rows], [[session TEXTVIEW] charWidth], [[session TEXTVIEW] lineHeight]);
        if (h > max) {
            max = h;
            if (numChars) {
                *numChars = [session rows];
            }
        }
    }
    return max;
}

- (float)widestSessionWidth:(int*)numChars
{
    float max=0;
    float ch=0;
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYSession* session = [[TABVIEW tabViewItemAtIndex:i] identifier];
        float w = [[session TEXTVIEW] charWidth];
        PtyLog(@"widestSessionWidth - session %d has %dx%d, chars are %fx%f", i, [session columns], [session rows], [[session TEXTVIEW] charWidth], [[session TEXTVIEW] lineHeight]);
        if (w * [session columns] > max) {
            max = w;
            ch = [[session TEXTVIEW] charWidth];
            *numChars = [session columns];
        }
    }
    return ch;
}

- (float)tallestSessionHeight:(int*)numChars
{
    float max=0;
    float ch=0;
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYSession* session = [[TABVIEW tabViewItemAtIndex:i] identifier];
        float h = [[session TEXTVIEW] lineHeight];
        PtyLog(@"tallestSessionheight - session %d has %dx%d, chars are %fx%f", i, [session columns], [session rows], [[session TEXTVIEW] charWidth], [[session TEXTVIEW] lineHeight]);
        if (h * [session rows] > max) {
            max = h * [session rows];
            ch = [[session TEXTVIEW] lineHeight];
            *numChars = [session rows];
        }
    }
    return ch;
}

- (void)copySettingsFrom:(PseudoTerminal*)other
{
    [findBarSubview setHidden:YES];
    [instantReplaySubview setHidden:YES];
    if (![other->findBarSubview isHidden]) {
        [self showHideFindBar];
    }
    if (![other->instantReplaySubview isHidden]) {
        [self showHideInstantReplay];
    }
    [bottomBar setHidden:[other->bottomBar isHidden]];
}

- (void)setupSession:(PTYSession *)aSession
               title:(NSString *)title
{
    NSDictionary *tempPrefs;

    PtyLog(@"%s(%d):-[PseudoTerminal setupSession]",
          __FILE__, __LINE__);

    NSParameterAssert(aSession != nil);

    // Init the rest of the session
    [aSession setParent:self];

    // set some default parameters
    if ([aSession addressBookEntry] == nil) {
        tempPrefs = [[BookmarkModel sharedInstance] defaultBookmark];
        if (tempPrefs != nil) {
            // Use the default bookmark. This path is taken with applescript's
            // "make new session at the end of sessions" command.
            [aSession setAddressBookEntry:tempPrefs];
        } else {
            // get the hardcoded defaults
            NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
            [ITAddressBookMgr setDefaultsInBookmark:dict];
            [dict setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
            [aSession setAddressBookEntry:dict];
            tempPrefs = dict;
        }
    } else {
        tempPrefs = [aSession addressBookEntry];
    }
    int rows = [[tempPrefs objectForKey:KEY_ROWS] intValue];
    int columns = [[tempPrefs objectForKey:KEY_COLUMNS] intValue];
    // rows, columns are set to the bookmark defaults. Make sure they'll fit.

    NSSize charSize = [PTYTextView charSizeForFont:[ITAddressBookMgr fontWithDesc:[tempPrefs objectForKey:KEY_NORMAL_FONT]]
                                 horizontalSpacing:[[tempPrefs objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                   verticalSpacing:[[tempPrefs objectForKey:KEY_VERTICAL_SPACING] floatValue]];

    if ([TABVIEW numberOfTabViewItems] != 0) {
        NSSize contentSize = [[[self currentSession] SCROLLVIEW] documentVisibleRect].size;
        rows = (contentSize.height - VMARGIN*2) / charSize.height;
        columns = (contentSize.width - MARGIN*2) / charSize.width;
    }

    NSRect marginlessRect = NSMakeRect(0, 0, columns * charSize.width, rows * charSize.height);

    if ([aSession initScreen:marginlessRect]) {
        PtyLog(@"setupSession - call safelySetSessionSize");
        [self safelySetSessionSize:aSession rows:rows columns:columns];
        inSetup = YES;
        PtyLog(@"setupSession - call setPreferencesFromAddressBookEntry");
        [aSession setPreferencesFromAddressBookEntry:tempPrefs];
        inSetup = NO;
        [[aSession SCREEN] setDisplay:[aSession TEXTVIEW]];
        [[aSession TERMINAL] setTrace:YES];    // debug vt100 escape sequence decode

        if (title) {
            [aSession setName:title];
            [aSession setDefaultName:title];
            [self setWindowTitle];
        }
    }
}

- (NSRect)maxFrame
{
    NSRect visibleFrame = NSZeroRect;
    for (NSScreen* screen in [NSScreen screens]) {
        visibleFrame = NSUnionRect(visibleFrame, [screen visibleFrame]);
    }
    return visibleFrame;
}

- (NSSize)maxTextViewSize
{
    NSRect frame = [self maxFrame];
    NSSize decorationSize = [self getWindowDecorationSize:1 height:1 charWidth:1 charHeight:1];
    NSSize result;
    result.width = frame.size.width - decorationSize.width;
    result.height = frame.size.height - decorationSize.height;
    return result;
}

// Set the session to a size that fits on the screen.
- (void)safelySetSessionSize:(PTYSession*)aSession rows:(int)rows columns:(int)columns
{
    PtyLog(@"safelySetSessionSize");
    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
    if (!_fullScreen) {
        int width = columns;
        int height = rows;
        if (width < 20) {
            width = 20;
        }
        if (height < 2) {
            height = 2;
        }

        int max_height = ([self maxTextViewSize].height - VMARGIN*2) / [[aSession TEXTVIEW] lineHeight];

        if (height > max_height) {
            height = max_height;
        }
        PtyLog(@"safelySetSessionSize - set to %dx%d", width, height);
        [[aSession SCREEN] resizeWidth:width height:height];
        PtyLog(@"safelySetSessionSize -  calling shell setWidth:%d height:%d", width, height);
        [[aSession SHELL] setWidth:width  height:height];
        [[aSession SCROLLVIEW] setHasVerticalScroller:hasScrollbar];
        [[aSession SCROLLVIEW] setLineScroll:[[aSession TEXTVIEW] lineHeight]];
        [[aSession SCROLLVIEW] setPageScroll:2*[[aSession TEXTVIEW] lineHeight]];
        if ([aSession backgroundImagePath]) {
            [aSession setBackgroundImagePath:[aSession backgroundImagePath]];
        }
    }
}

- (void)fitSessionToWindow:(PTYSession*)aSession
{
    if (togglingFullScreen_) {
        PtyLog(@"fitSessionToWindow returning because togglingFullScreen.");
        return;
    }
    PtyLog(@"fitSessionToWindow begins");
    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
    [[aSession SCROLLVIEW] setHasVerticalScroller:hasScrollbar];
    NSSize size = [[[self currentSession] SCROLLVIEW] documentVisibleRect].size;
    int width = (size.width - MARGIN*2) / [[aSession TEXTVIEW] charWidth];
    int height = (size.height - VMARGIN*2) / [[aSession TEXTVIEW] lineHeight];
    if (width <= 0 || height <= 0) {
        // We can be called before the window is initialized, but we'll fail spectacularly
        // if we keep going.
        return;
    }
    PtyLog(@"fitSessionToWindow: given a height of %1.0f can fit %d rows", size.height, height);
    if (width == [aSession columns] && height == [aSession rows]) {
        PtyLog(@"fitSessionToWindow - terminating early because session size doesn't change");
        return;
    }
    PtyLog(@"fitSessionToWindow - Given a scrollview size of %fx%f, can fit %dx%d chars", size.width, size.height, width, height);

    [[aSession SCREEN] resizeWidth:width height:height];
    PtyLog(@"fitSessionToWindow -  calling shell setWidth:%d height:%d", width, height);
    [[aSession SHELL] setWidth:width  height:height];
    [[aSession SCROLLVIEW] setLineScroll:[[aSession TEXTVIEW] lineHeight]];
    [[aSession SCROLLVIEW] setPageScroll:2*[[aSession TEXTVIEW] lineHeight]];
    if ([aSession backgroundImagePath]) {
        [aSession setBackgroundImagePath:[aSession backgroundImagePath]];
    }
    PtyLog(@"fitSessionToWindow returns");
}

- (void)insertSession:(PTYSession *)aSession atIndex:(int)anIndex
{
    NSTabViewItem *aTabViewItem;


    PtyLog(@"%s(%d):-[PseudoTerminal insertSession: 0x%x atIndex: %d]",
           __FILE__, __LINE__, aSession, index);

    if (aSession == nil) {
        return;
    }

    if ([TABVIEW indexOfTabViewItemWithIdentifier:aSession] == NSNotFound) {
        // create a new tab
        aTabViewItem = [[NSTabViewItem alloc] initWithIdentifier: aSession];
        [aSession setTabViewItem:aTabViewItem];
        NSParameterAssert(aTabViewItem != nil);
        [aTabViewItem setLabel:[aSession name]];
        [aTabViewItem setView:[aSession view]];
        // This triggers a call to fitWindowToSessions
        PtyLog(@"insertSession - calling insertTabViewItem");
        [TABVIEW insertTabViewItem: aTabViewItem atIndex: anIndex];

        [aTabViewItem release];
        [TABVIEW selectTabViewItemAtIndex:anIndex];

        if ([self windowInited] && !_fullScreen) {
            [[self window] makeKeyAndOrderFront: self];
        }
        [[iTermController sharedInstance] setCurrentTerminal: self];
    }
}

- (void)replaceSession:(PTYSession *)aSession atIndex:(int)anIndex
{
    PtyLog(@"%s(%d):-[PseudoTerminal insertSession: 0x%x atIndex: %d]",
           __FILE__, __LINE__, aSession, index);

    if (aSession == nil) {
        return;
    }

    assert([TABVIEW indexOfTabViewItemWithIdentifier:aSession] == NSNotFound);
    NSTabViewItem *aTabViewItem = [TABVIEW tabViewItemAtIndex:anIndex];
    assert(aTabViewItem);

    // Tell the session at this index that it is no longer associated with this tab.
    PTYSession* oldSession = [aTabViewItem identifier];
    [oldSession setTabViewItem:nil];

    // Replace the session for the tab view item.
    [tabBarControl changeIdentifier:aSession atIndex:anIndex];

    [aSession setTabViewItem:aTabViewItem];

    // Set other tabviewitem attributes to match the new session.
    [aTabViewItem setLabel:[aSession name]];
    [aTabViewItem setView:[aSession view]];
    [TABVIEW selectTabViewItemAtIndex:anIndex];

    // Bring the window to the fore.
    [self fitWindowToSessions];
    if ([self windowInited] && !_fullScreen) {
        [[self window] makeKeyAndOrderFront:self];
    }
    [[iTermController sharedInstance] setCurrentTerminal:self];
}

- (NSString *)currentSessionName
{
    PTYSession* session = [self currentSession];
    return [session windowTitle] ? [session windowTitle] : [session defaultName];
}

- (void)setCurrentSessionName:(NSString *)theSessionName
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal setCurrentSessionName]",
          __FILE__, __LINE__);
#endif
    PTYSession *aSession = [[TABVIEW selectedTabViewItem] identifier];

    if (theSessionName != nil) {
        [aSession setName:theSessionName];
        [aSession setDefaultName:theSessionName];
    } else {
        NSMutableString *title = [NSMutableString string];
        NSString *progpath = [NSString stringWithFormat: @"%@ #%d",
                              [[[[aSession SHELL] path] pathComponents] lastObject],
                              [TABVIEW indexOfTabViewItem:[TABVIEW selectedTabViewItem]]];

        if ([aSession exited]) {
            [title appendString:@"Finish"];
        } else {
            [title appendString:progpath];
        }

        [aSession setName: title];
        [aSession setDefaultName: title];
    }
}

- (void)setFramePos
{
    // Set framePos to the next unused window position.
    for (int i = 0; i < CACHED_WINDOW_POSITIONS; ++i) {
        if (!windowPositions[i]) {
            windowPositions[i] = YES;
            framePos = i;
            return;
        }
    }
    framePos = CACHED_WINDOW_POSITIONS - 1;
}

- (void)startProgram:(NSString *)program
           arguments:(NSArray *)prog_argv
         environment:(NSDictionary *)prog_env
              isUTF8:(BOOL)isUTF8
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal startProgram:%@ arguments:%@]",
          __FILE__, __LINE__, program, prog_argv );
#endif
    [[self currentSession] startProgram:program
                              arguments:prog_argv
                            environment:prog_env
                                 isUTF8:isUTF8];

    if ([[[self window] title] compare:@"Window"] == NSOrderedSame) {
        [self setWindowTitle];
    }
}

- (void)reset:(id)sender
{
    [[[self currentSession] TERMINAL] reset];
}

- (void)clearBuffer:(id)sender
{
    [[self currentSession] clearBuffer];
}

- (void)clearScrollbackBuffer:(id)sender
{
    [[self currentSession] clearScrollbackBuffer];
}

- (IBAction)logStart:(id)sender
{
    if (![[self currentSession] logging]) {
        [[self currentSession] logStart];
    }
    // send a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermSessionBecameKey" object: [self currentSession]];
}

- (IBAction)logStop:(id)sender
{
    if ([[self currentSession] logging]) {
        [[self currentSession] logStop];
    }
    // send a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermSessionBecameKey" object: [self currentSession]];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    BOOL logging = [[self currentSession] logging];
    BOOL result = YES;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal validateMenuItem:%@]",
          __FILE__, __LINE__, item );
#endif

    if ([item action] == @selector(logStart:)) {
        result = logging == YES ? NO : YES;
    } else if ([item action] == @selector(logStop:)) {
        result = logging == NO ? NO : YES;
    } else if ([item action] == @selector(irPrev:)) {
        result = [[self currentSession] canInstantReplayPrev];
    } else if ([item action] == @selector(irNext:)) {
        result = [[self currentSession] canInstantReplayNext];
    }
    return result;
}

- (void)setSendInputToAllSessions:(BOOL)flag
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif

    sendInputToAllSessions = flag;
    if (flag) {
        sendInputToAllSessions = (NSRunAlertPanel(NSLocalizedStringFromTableInBundle(@"Warning!",@"iTerm", [NSBundle bundleForClass: [self class]], @"Warning"),
                                                  NSLocalizedStringFromTableInBundle(@"Keyboard input will be sent to all sessions in this terminal.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Keyboard Input"),
                                                  NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"Profile"),
                                                  NSLocalizedStringFromTableInBundle(@"Cancel",@"iTerm", [NSBundle bundleForClass: [self class]], @"Cancel"), nil) == NSAlertDefaultReturn);
    }
    if (sendInputToAllSessions) {
        [[self window] setBackgroundColor: [NSColor highlightColor]];
        [background_ setColor:[NSColor highlightColor]];
    } else {
        [[self window] setBackgroundColor: normalBackgroundColor];
        [background_ setColor:normalBackgroundColor];
    }
}

- (IBAction)toggleInputToAllSessions:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal toggleInputToAllSessions:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self setSendInputToAllSessions: ![self sendInputToAllSessions]];

    // Post a notification to reload menus
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:self
                                                      userInfo:nil];
    [self setWindowTitle];
}

- (void)fitSessionsToWindow
{
    PtyLog(@"fitSessionsToWindow begins");
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYSession* session = (PTYSession*) [[TABVIEW tabViewItemAtIndex:i] identifier];
        [self fitSessionToWindow:session];
    }
    PtyLog(@"fitSessionsToWindow returns");
}

// Close Window
- (BOOL)showCloseWindow
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal showCloseWindow]", __FILE__, __LINE__);
#endif

    return (NSRunAlertPanel(NSLocalizedStringFromTableInBundle(@"Close Window?",@"iTerm", [NSBundle bundleForClass: [self class]], @"Close window"),
                            NSLocalizedStringFromTableInBundle(@"All sessions will be closed",@"iTerm", [NSBundle bundleForClass: [self class]], @"Close window"),
                            NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"OK"),
                            NSLocalizedStringFromTableInBundle(@"Cancel",@"iTerm", [NSBundle bundleForClass: [self class]], @"Cancel")
                            ,nil) == NSAlertDefaultReturn);
}

- (PSMTabBarControl*)tabBarControl
{
    return tabBarControl;
}

// closes a tab
- (void) closeTabContextualMenuAction: (id) sender
{
    [self closeSession:[[sender representedObject] identifier]];
}

// moves a tab with its session to a new window
- (void)moveTabToNewWindowContextualMenuAction:(id)sender
{
    PseudoTerminal *term;
    NSTabViewItem *aTabViewItem = [sender representedObject];
    PTYSession *aSession = [aTabViewItem identifier];

    if (aSession == nil) {
        return;
    }

    // create a new terminal window
    term = [[[PseudoTerminal alloc] initWithSmartLayout:NO fullScreen:nil] autorelease];
    if (term == nil) {
        return;
    }

    [[iTermController sharedInstance] addInTerminals: term];


    // temporarily retain the tabViewItem
    [aTabViewItem retain];

    // remove from our window
    [TABVIEW removeTabViewItem: aTabViewItem];

    // add the session to the new terminal
    [term insertSession: aSession atIndex: 0];
    PtyLog(@"mvoeTabToNewWindowContextMenuAction - call fitSessionsToWindow");
    [term fitSessionsToWindow];

    // release the tabViewItem
    [aTabViewItem release];
}

- (IBAction)closeWindow:(id)sender
{
    [[self window] performClose:sender];
}

- (IBAction)sendCommand:(id)sender
{
    NSString *command = [commandField stringValue];

    if (command == nil ||
        [[command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isEqualToString:@""]) {
        return;
    }

    NSRange range = [command rangeOfString:@"://"];
    if (range.location != NSNotFound) {
        range = [[command substringToIndex:range.location] rangeOfString:@" "];
        if (range.location == NSNotFound) {
            NSURL *url = [NSURL URLWithString: command];
            NSString *urlType = [url scheme];
            id bm = [[PreferencePanel sharedInstance] handlerBookmarkForURL:urlType];

            if (bm) {
                [[iTermController sharedInstance] launchBookmark:bm
                                                      inTerminal:[[iTermController sharedInstance] currentTerminal]
                                                         withURL:command];
            } else {
                [[NSWorkspace sharedWorkspace] openURL:url];
            }
            return;
        }
    }
    [[self currentSession] sendCommand: command];
    [commandField setStringValue:@""];
}

- (void)reloadBookmarks
{
    for (int j = 0; j < [self numberOfSessions]; ++j) {
        PTYSession* session = [self sessionAtIndex:j];
        Bookmark *oldBookmark = [session addressBookEntry];
        NSString* oldName = [oldBookmark objectForKey:KEY_NAME];
        [oldName retain];
        NSString* guid = [oldBookmark objectForKey:KEY_GUID];
        Bookmark* newBookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
        if (!newBookmark) {
            newBookmark = [[BookmarkModel sessionsInstance] bookmarkWithGuid:guid];
        }
        if (newBookmark && newBookmark != oldBookmark) {
            // Same guid but different pointer means it has changed.
            // The test can have false negatives but it should be harmless.
            [session setPreferencesFromAddressBookEntry:newBookmark];
            [session setAddressBookEntry:newBookmark];
            if (![[newBookmark objectForKey:KEY_NAME] isEqualToString:oldName]) {
                [session setName:[newBookmark objectForKey:KEY_NAME]];
            }
        }
        [oldName release];
    }
}

- (IBAction)parameterPanelEnd:(id)sender
{
    [NSApp stopModal];
}

- (void)_continueSearch
{
    // NSLog(@"PseudoTerminal continueSearch");
    BOOL more = NO;
    if ([[[self currentSession] TEXTVIEW] findInProgress]) {
        more = [[[self currentSession] TEXTVIEW] continueFind];
    }
    if (!more) {
        // NSLog(@"invalidating timer");
        [_timer invalidate];
        [findProgressIndicator setHidden:YES];
        _timer = nil;
    }
}

- (void)_newSearch:(BOOL)needTimer
{
    if (needTimer && !_timer) {
        // NSLog(@"creating timer");
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                  target:self
                                                selector:@selector(_continueSearch)
                                                userInfo:nil
                                                 repeats:YES];
        [findProgressIndicator setHidden:NO];
        [findProgressIndicator startAnimation:self];
    } else if (!needTimer && _timer) {
        // NSLog(@"destroying timer");
        // did a search while one was in progress
        [_timer invalidate];
        _timer = nil;
        [findProgressIndicator setHidden:YES];
    }
}

- (long long)timestampForFraction:(float)f
{
    DVR* dvr = [[self currentSession] dvr];
    long long range = [dvr lastTimeStamp] - [dvr firstTimeStamp];
    long long offset = range * f;
    return [dvr firstTimeStamp] + offset;
}

@end


@implementation PseudoTerminal (KeyValueCoding)

-(int)columns
{
    return [[self currentSession] columns];
}

-(void)setColumns:(int)columns
{
    [self sessionInitiatedResize:[self currentSession] width:columns height:[[self currentSession] rows]];
}

-(int)rows
{
    return [[self currentSession] rows];
}

-(void)setRows:(int)rows
{
    [self sessionInitiatedResize:[self currentSession] width:[[self currentSession] columns] height:rows];
}

-(id)addNewSession:(NSDictionary *)addressbookEntry
{
    NSAssert(addressbookEntry, @"Null address book entry");
    // NSLog(@"PseudoTerminal: -addInSessions: 0x%x", object);
    PTYSession *aSession;
    NSString *oldCWD = nil;

    /* Get currently selected tabviewitem */
    if ([self currentSession]) {
        oldCWD = [[[self currentSession] SHELL] getWorkingDirectory];
    }

    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession SCREEN] setScrollback:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    // set our preferences
    [aSession setAddressBookEntry: addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession: aSession];
    if ([aSession SCREEN]) {
        NSMutableString *cmd, *name;
        NSArray *arg;
        NSString *pwd;
        BOOL isUTF8;

        // Grab the addressbook command
        cmd = [[[NSMutableString alloc] initWithString:[ITAddressBookMgr bookmarkCommand:addressbookEntry]] autorelease];
        name = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey:KEY_NAME]] autorelease];
        // Get session parameters
        [self _getSessionParameters:cmd withName:name];

        [PseudoTerminal breakDown:cmd cmdPath:&cmd cmdArgs:&arg];

        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry];
        if ([pwd length] == 0) {
            if (oldCWD) {
                pwd = oldCWD;
            } else {
                pwd = NSHomeDirectory();
            }
        }
        NSDictionary *env = [NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        isUTF8 = ([[addressbookEntry objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue] == NSUTF8StringEncoding);

        [self setCurrentSessionName:name];

        // Start the command
        [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8];
    }

    [aSession release];
    return aSession;
}


// accessors for to-many relationships:
// (See NSScriptKeyValueCoding.h)
-(id)valueInSessionsAtIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -valueInSessionsAtIndex: %d", anIndex);
    return ([[TABVIEW tabViewItemAtIndex:anIndex] identifier]);
}

-(NSArray*)sessions
{
    int n = [TABVIEW numberOfTabViewItems];
    NSMutableArray *sessions = [NSMutableArray arrayWithCapacity: n];
    int i;

    for (i = 0; i < n; ++i) {
        [sessions addObject: [[TABVIEW tabViewItemAtIndex:i] identifier]];
    }

    return sessions;
}

-(void)setSessions: (NSArray*)sessions {}

-(id)valueWithName: (NSString *)uniqueName inPropertyWithKey: (NSString*)propertyKey
{
    id result = nil;
    int i;

    // TODO: if (... == YES) => if (...)
    if ([propertyKey isEqualToString: sessionsKey] == YES) {
        PTYSession *aSession;

        for (i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
            aSession = [[TABVIEW tabViewItemAtIndex:i] identifier];
            if ([[aSession name] isEqualToString: uniqueName] == YES) {
                return (aSession);
            }
        }
    }

    return result;
}

// The 'uniqueID' argument might be an NSString or an NSNumber.
-(id)valueWithID: (NSString *)uniqueID inPropertyWithKey: (NSString*)propertyKey
{
    id result = nil;
    int i;

    if ([propertyKey isEqualToString: sessionsKey] == YES) {
        PTYSession *aSession;

        for (i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
            aSession = [[TABVIEW tabViewItemAtIndex:i] identifier];
            if ([[aSession tty] isEqualToString: uniqueID] == YES) {
                return (aSession);
            }
        }
    }

    return result;
}

-(id)addNewSession:(NSDictionary *)addressbookEntry withURL:(NSString *)url
{
    PtyLog(@"PseudoTerminal: -addNewSession");
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession SCREEN] setScrollback:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    // set our preferences
    [aSession setAddressBookEntry: addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession: aSession];
    if ([aSession SCREEN]) {
        // We process the cmd to insert URL parts
        NSMutableString *cmd = [[[NSMutableString alloc] initWithString:[ITAddressBookMgr bookmarkCommand:addressbookEntry]] autorelease];
        NSMutableString *name = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey: KEY_NAME]] autorelease];
        NSURL *urlRep = [NSURL URLWithString: url];


        // Grab the addressbook command
        [cmd replaceOccurrencesOfString:@"$$URL$$" withString:url options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$HOST$$" withString:[urlRep host]?[urlRep host]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$USER$$" withString:[urlRep user]?[urlRep user]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$PASSWORD$$" withString:[urlRep password]?[urlRep password]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$PORT$$" withString:[urlRep port]?[[urlRep port] stringValue]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$PATH$$" withString:[urlRep path]?[urlRep path]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];

        // Update the addressbook title
        [name replaceOccurrencesOfString:@"$$URL$$" withString:url options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$HOST$$" withString:[urlRep host]?[urlRep host]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$USER$$" withString:[urlRep user]?[urlRep user]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$PASSWORD$$" withString:[urlRep password]?[urlRep password]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$PORT$$" withString:[urlRep port]?[[urlRep port] stringValue]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$PATH$$" withString:[urlRep path]?[urlRep path]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];

        // Get remaining session parameters
        [self _getSessionParameters: cmd withName:name];

        NSArray *arg;
        NSString *pwd;
        BOOL isUTF8;
        [PseudoTerminal breakDown:cmd cmdPath:&cmd cmdArgs:&arg];

        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry];
        if ([pwd length] == 0) {
            pwd = NSHomeDirectory();
        }
        NSDictionary *env = [NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        isUTF8 = ([[addressbookEntry objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue] == NSUTF8StringEncoding);

        [self setCurrentSessionName: name];

        // Start the command
        [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8];
    }
    [aSession release];
    return aSession;
}

-(id)addNewSession:(NSDictionary *)addressbookEntry withCommand:(NSString *)command
{
    PtyLog(@"PseudoTerminal: addNewSession 2");
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession SCREEN] setScrollback:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    // set our preferences
    [aSession setAddressBookEntry: addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession: aSession];
    if ([aSession SCREEN]) {
        NSMutableString *cmd, *name;
        NSArray *arg;
        NSString *pwd;
        BOOL isUTF8;

        // Grab the addressbook command
        cmd = [[[NSMutableString alloc] initWithString:command] autorelease];
        name = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey: KEY_NAME]] autorelease];
        // Get session parameters
        [self _getSessionParameters: cmd withName:name];

        [PseudoTerminal breakDown:cmd cmdPath:&cmd cmdArgs:&arg];

        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry];
        if ([pwd length] == 0) {
            pwd = NSHomeDirectory();
        }
        NSDictionary *env =[NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        isUTF8 = ([[addressbookEntry objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue] == NSUTF8StringEncoding);

        [self setCurrentSessionName:name];

        // Start the command
        [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8];
    }

    [aSession release];
    return aSession;
}

-(void)appendSession:(PTYSession *)object
{
    PtyLog(@"PseudoTerminal: -appendSession: 0x%x", object);
    // Increment tabViewItemsBeingAdded so that the maximum content size will
    // be calculated with the tab bar if it's about to open.
    ++tabViewItemsBeingAdded;
    [self setupSession: object title: nil];
    tabViewItemsBeingAdded--;
    if ([object SCREEN]) {  // screen initialized ok
        [self insertSession: object atIndex:[TABVIEW numberOfTabViewItems]];
    }
}

-(void)replaceInSessions:(PTYSession *)object atIndex:(unsigned)anIndex
{
    PtyLog(@"PseudoTerminal: -replaceInSessions: 0x%x atIndex: %d", object, anIndex);
    [self setupSession:object title:nil];
    if ([object SCREEN]) {  // screen initialized ok
        [self replaceSession:object atIndex:anIndex];
    }
}

-(void)addInSessions:(PTYSession *)object
{
    PtyLog(@"PseudoTerminal: -addInSessions: 0x%x", object);
    [self insertInSessions: object];
}

-(void)insertInSessions:(PTYSession *)object
{
    PtyLog(@"PseudoTerminal: -insertInSessions: 0x%x", object);
    [self insertInSessions: object atIndex:[TABVIEW numberOfTabViewItems]];
}

-(void)insertInSessions:(PTYSession *)object atIndex:(unsigned)anIndex
{
    PtyLog(@"PseudoTerminal: -insertInSessions: 0x%x atIndex: %d", object, anIndex);
    [self setupSession: object title: nil];
    if ([object SCREEN]) {  // screen initialized ok
        [self insertSession:object atIndex:anIndex];
    }
}

-(void)removeFromSessionsAtIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -removeFromSessionsAtIndex: %d", anIndex);
    if (anIndex < [TABVIEW numberOfTabViewItems]) {
        PTYSession *aSession = [[TABVIEW tabViewItemAtIndex:anIndex] identifier];
        [self closeSession: aSession];
    }
}

- (BOOL)windowInited
{
    return (windowInited);
}

- (void) setWindowInited: (BOOL) flag
{
    windowInited = flag;
}


// a class method to provide the keys for KVC:
+(NSArray*)kvcKeys
{
    static NSArray *_kvcKeys = nil;
    if (nil == _kvcKeys ){
        _kvcKeys = [[NSArray alloc] initWithObjects:
            columnsKey, rowsKey, sessionsKey,  nil ];
    }
    return _kvcKeys;
}

@end

@implementation PseudoTerminal (ScriptingSupport)

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier
{
    NSUInteger anIndex = 0;
    id classDescription = nil;

    NSScriptObjectSpecifier *containerRef;

    NSArray *terminals = [[iTermController sharedInstance] terminals];
    anIndex = [terminals indexOfObjectIdenticalTo:self];
    if (anIndex != NSNotFound) {
        containerRef     = [NSApp objectSpecifier];
        classDescription = [NSClassDescription classDescriptionForClass:[NSApp class]];
        //create and return the specifier
        return [[[NSIndexSpecifier allocWithZone:[self zone]]
               initWithContainerClassDescription: classDescription
                              containerSpecifier: containerRef
                                             key: @ "terminals"
                                           index: anIndex] autorelease];
    } else {
        return nil;
    }
}

// Handlers for supported commands:

-(void)handleSelectScriptCommand: (NSScriptCommand *)command
{
    [[iTermController sharedInstance] setCurrentTerminal: self];
}

-(id)handleLaunchScriptCommand: (NSScriptCommand *)command
{
    // Get the command's arguments:
    NSDictionary *args = [command evaluatedArguments];
    NSString *session = [args objectForKey:@"session"];
    NSDictionary *abEntry;

    abEntry = [[BookmarkModel sharedInstance] bookmarkWithName:session];
    if (abEntry == nil) {
        abEntry = [[BookmarkModel sharedInstance] defaultBookmark];
    }
    if (abEntry == nil) {
        NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
        [aDict setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
        abEntry = aDict;
    }

    // If we have not set up a window, do it now
    if ([self windowInited] == NO) {
        [self initWithSmartLayout:NO fullScreen:nil];
    }

    // TODO(georgen): test this
    // launch the session!
    id rv = [[iTermController sharedInstance] launchBookmark:abEntry 
                                                 inTerminal:self];
    return rv;
}

@end


