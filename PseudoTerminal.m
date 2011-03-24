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

// For beta 1, we're trying to keep the IR bar from mysteriously disappearing
// when live mode is entered.
// #define HIDE_IR_WHEN_LIVE_VIEW_ENTERED
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
#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/iTermApplicationDelegate.h>
#import "FakeWindow.h"
#import <PSMTabBarControl.h>
#import <PSMTabStyle.h>
#import <iTerm/iTermGrowlDelegate.h>
#include <unistd.h>
#import "PasteboardHistory.h"
#import "PTYTab.h"
#import "SessionView.h"
#import "iTerm/iTermApplication.h"
#import "BookmarksWindow.h"
#import "FindViewController.h"

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

// Constants for saved window arrangement key names.
static NSString* TERMINAL_ARRANGEMENT_OLD_X_ORIGIN = @"Old X Origin";
static NSString* TERMINAL_ARRANGEMENT_OLD_Y_ORIGIN = @"Old Y Origin";
static NSString* TERMINAL_ARRANGEMENT_OLD_WIDTH = @"Old Width";
static NSString* TERMINAL_ARRANGEMENT_OLD_HEIGHT = @"Old Height";

static NSString* TERMINAL_ARRANGEMENT_X_ORIGIN = @"X Origin";
static NSString* TERMINAL_ARRANGEMENT_Y_ORIGIN = @"Y Origin";
static NSString* TERMINAL_ARRANGEMENT_WIDTH = @"Width";
static NSString* TERMINAL_ARRANGEMENT_HEIGHT = @"Height";
static NSString* TERMINAL_ARRANGEMENT_TABS = @"Tabs";
static NSString* TERMINAL_ARRANGEMENT_FULLSCREEN = @"Fullscreen";
static NSString* TERMINAL_ARRANGEMENT_WINDOW_TYPE = @"Window Type";
static NSString* TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX = @"Selected Tab Index";
static NSString* TERMINAL_ARRANGEMENT_SCREEN_INDEX = @"Screen";

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

- (id)initWithSmartLayout:(BOOL)smartLayout windowType:(int)windowType screen:(int)screenNumber
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
    if (windowType == WINDOW_TYPE_FULL_SCREEN && screenNumber == -1) {
        NSUInteger n = [[NSScreen screens] indexOfObjectIdenticalTo:[[self window] screen]];
        if (n == NSNotFound) {
            screenNumber = 0;
        } else {
            screenNumber = n;
        }
    }
    if (windowType == WINDOW_TYPE_TOP) {
        smartLayout = NO;
    }
    windowType_ = windowType;
    pbHistoryView = [[PasteboardHistoryView alloc] init];
    autocompleteView = [[AutocompleteView alloc] init];
    // create the window programmatically with appropriate style mask
    styleMask = NSTitledWindowMask |
        NSClosableWindowMask |
        NSMiniaturizableWindowMask |
        NSResizableWindowMask |
        NSTexturedBackgroundWindowMask;

    NSScreen* screen;
    if (screenNumber < 0 || screenNumber >= [[NSScreen screens] count])  {
        screen = [[self window] screen];
        screenNumber_ = 0;
    } else {
        screen = [[NSScreen screens] objectAtIndex:screenNumber];
        screenNumber_ = screenNumber;
    }

    NSRect initialFrame;
    switch (windowType) {
        case WINDOW_TYPE_TOP:
            initialFrame = [screen visibleFrame];
            break;

        case WINDOW_TYPE_FULL_SCREEN:
            oldFrame_ = [[self window] frame];
            initialFrame = [screen frame];
            break;

        default:
            PtyLog(@"Unknown window type: %d", (int)windowType);
            NSLog(@"Unknown window type: %d", (int)windowType);
            // fall through
        case WINDOW_TYPE_NORMAL:
            // Use the system-supplied frame which has a reasonable origin. It may
            // be overridden by smart window placement or a saved window location.
            initialFrame = [[self window] frame];
            break;
    }
    preferredOrigin_ = initialFrame.origin;

    PtyLog(@"initWithSmartLayout - initWithContentRect");
    myWindow = [[PTYWindow alloc] initWithContentRect:initialFrame
                                            styleMask:(windowType == WINDOW_TYPE_TOP || windowType == WINDOW_TYPE_FULL_SCREEN) ? NSBorderlessWindowMask : styleMask
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    if (windowType == WINDOW_TYPE_TOP) {
        [myWindow setHasShadow:YES];
    }

    PtyLog(@"initWithSmartLayout - new window is at %d", myWindow);
    [self setWindow:myWindow];
    [myWindow release];

    _fullScreen = (windowType == WINDOW_TYPE_FULL_SCREEN);
    if (_fullScreen) {
        background_ = [[SolidColorView alloc] initWithFrame:[[[self window] contentView] frame] color:[NSColor blackColor]];
    } else {
        background_ = [[SolidColorView alloc] initWithFrame:[[[self window] contentView] frame] color:[NSColor windowBackgroundColor]];
    }
    [[self window] setAlphaValue:1];
    [[self window] setOpaque:NO];

    normalBackgroundColor = [background_ color];

#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif

    _resizeInProgressFlag = NO;

    if (!smartLayout || windowType == WINDOW_TYPE_FULL_SCREEN) {
        [(PTYWindow*)[self window] setLayoutDone];
    }

    if (windowType == WINDOW_TYPE_NORMAL) {
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
    PreferencePanel* pp = [PreferencePanel sharedInstance];
    [tabBarControl setModifier:[pp modifierTagToMask:[pp switchTabModifier]]];
    [tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    if (!_fullScreen) {
        [[[self window] contentView] addSubview:tabBarControl];
        [tabBarControl release];
    }

    // Set up bottomBar
    NSRect irFrame = [instantReplaySubview frame];
    bottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0,
                                                         0,
                                                         irFrame.size.width,
                                                         irFrame.size.height)];
    [bottomBar addSubview:instantReplaySubview];
    [bottomBar setHidden:YES];
    [instantReplaySubview setHidden:NO];

    // create the tabview
    aRect = [[[self window] contentView] bounds];

    TABVIEW = [[PTYTabView alloc] initWithFrame:aRect];
    [TABVIEW setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    [TABVIEW setAutoresizesSubviews:YES];
    [TABVIEW setAllowsTruncatedLabels:NO];
    [TABVIEW setControlSize:NSSmallControlSize];
    [TABVIEW setTabViewType:NSNoTabsNoBorder];
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
    [self setTabBarStyle];

    [[[self window] contentView] setAutoresizesSubviews: YES];
    [[self window] setDelegate: self];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_refreshTitle:)
                                                 name: @"iTermUpdateLabels"
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_refreshTerminal:)
                                                 name: @"iTermRefreshTerminal"
                                               object: nil];

    [self setWindowInited: YES];
    if (_fullScreen) {
        [self hideMenuBar];
    }
    if (windowType != WINDOW_TYPE_FULL_SCREEN) {
        useTransparency_ = YES;
    } else {
        useTransparency_ = NO;
    }

    number_ = [[iTermController sharedInstance] allocateWindowNumber];

    return self;
}

- (int)number
{
    return number_;
}

- (NSScreen*)screen
{
    NSArray* screens = [NSScreen screens];
    if ([screens count] > screenNumber_) {
        return [screens objectAtIndex:screenNumber_];
    } else {
        return [NSScreen mainScreen];
    }
}

- (void)swipeWithEvent:(NSEvent *)event
{
    if ([event deltaX] < 0) {
        [self nextTab:nil];
    } else if ([event deltaX] > 0) {
        [self previousTab:nil];
    }
    if ([event deltaY] < 0) {
        [[iTermController sharedInstance] nextTerminal:nil];
    } else if ([event deltaY] > 0) {
        [[iTermController sharedInstance] previousTerminal:nil];
    }
}

- (void)setTabBarStyle
{
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
}

- (id)commandField
{
    return commandField;
}

- (void)selectSessionAtIndexAction:(id)sender
{
    [TABVIEW selectTabViewItemAtIndex:[sender tag]];
}

- (NSInteger)indexOfTab:(PTYTab*)aTab
{
    NSArray* items = [TABVIEW tabViewItems];
    for (int i = 0; i < [items count]; i++) {
        if ([[items objectAtIndex:i] identifier] == aTab) {
            return i;
        }
    }
    return NSNotFound;
}

- (void)newSessionInTabAtIndex:(id)sender
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self addNewSession:bookmark];
    }
}

- (void)newSessionsInManyTabsAtIndex:(id)sender
{
    NSMenu* parent = [sender representedObject];
    for (NSMenuItem* item in [parent itemArray]) {
        if (![item isSeparatorItem] && ![item submenu]) {
            NSString* guid = [item representedObject];
            Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
            if (bookmark) {
                [self addNewSession:bookmark];
            }
        }
    }
}

- (void)closeSession:(PTYSession *)aSession
{
    if ([[[aSession tab] sessions] count] == 1) {
        [self closeTab:[aSession tab]];
    } else {
        [aSession terminate];
    }
}

- (int)windowType
{
    return windowType_;
}

- (void)closeTab:(PTYTab*)aTab
{
    NSTabViewItem *aTabViewItem;
    int numberOfTabs;

    if ([TABVIEW indexOfTabViewItemWithIdentifier:aTab] == NSNotFound) {
        return;
    }

    int numClosing = 0;
    for (PTYSession* session in [aTab sessions]) {
        if (![session exited]) {
            ++numClosing;
        }
    }

    BOOL mustAsk = NO;
    if (numClosing > 0 && [[PreferencePanel sharedInstance] promptOnClose]) {
        if (numClosing == 1) {
            if (![[PreferencePanel sharedInstance] onlyWhenMoreTabs]) {
                mustAsk = YES;
            }
        } else {
            mustAsk = YES;
        }
    }

    if (mustAsk) {
        BOOL okToClose;
        if (numClosing == 1) {
            okToClose = NSRunAlertPanel([NSString stringWithFormat:@"%@ #%d",
                                         [[aTab activeSession] name],
                                         [aTab realObjectCount]],
                                        NSLocalizedStringFromTableInBundle(@"This tab will be closed.",
                                                                           @"iTerm",
                                                                           [NSBundle bundleForClass:[self class]],
                                                                           @"Close Session"),
                                        NSLocalizedStringFromTableInBundle(@"OK",
                                                                           @"iTerm",
                                                                           [NSBundle bundleForClass:[self class]],
                                                                           @"OK"),
                                        NSLocalizedStringFromTableInBundle(@"Cancel",
                                                                           @"iTerm",
                                                                           [NSBundle bundleForClass:[self class]],
                                                                           @"Cancel"),
                                        nil) == NSAlertDefaultReturn;
        } else {
            okToClose = NSRunAlertPanel([NSString stringWithFormat:@"Close multiple panes in tab #%d",
                                         [aTab realObjectCount]],
                                        [NSString stringWithFormat:
                                         NSLocalizedStringFromTableInBundle(@"%d sessions will be closed.",
                                                                            @"iTerm",
                                                                            [NSBundle bundleForClass:[self class]],
                                                                            @"Close Session"), numClosing],
                                        NSLocalizedStringFromTableInBundle(@"OK",
                                                                           @"iTerm",
                                                                           [NSBundle bundleForClass:[self class]],
                                                                           @"OK"),
                                        NSLocalizedStringFromTableInBundle(@"Cancel",
                                                                           @"iTerm",
                                                                           [NSBundle bundleForClass:[self class]],
                                                                           @"Cancel"),
                                        nil) == NSAlertDefaultReturn;
        }
        if (!okToClose) {
            return;
        }
    }

    numberOfTabs = [TABVIEW numberOfTabViewItems];
    for (PTYSession* session in [aTab sessions]) {
        [session terminate];
    }
    if (numberOfTabs == 1 && [self windowInited]) {
        [[self window] close];
    } else {
        // now get rid of this tab
        aTabViewItem = [aTab tabViewItem];
        [TABVIEW removeTabViewItem:aTabViewItem];
        PtyLog(@"closeSession - calling fitWindowToTabs");
        [self fitWindowToTabs];
    }
}

// Save the current scroll position
- (IBAction)saveScrollPosition:(id)sender
{
    [[self currentSession] saveScrollPosition];
}

// Jump to the saved scroll position
- (IBAction)jumpToSavedScrollPosition:(id)sender
{
    [[self currentSession] jumpToSavedScrollPosition];
}

// Is there a saved scroll position?
- (BOOL)hasSavedScrollPosition
{
    return [[self currentSession] hasSavedScrollPosition];
}


- (IBAction)closeCurrentTab:(id)sender
{
    [self closeTab:[self currentTab]];
}

- (IBAction)closeCurrentSession:(id)sender
{
    if ([[self window] isKeyWindow]) {
        PTYSession *aSession = [[[TABVIEW selectedTabViewItem] identifier] activeSession];
        [self closeSessionWithConfirmation:aSession];
    }
}

- (void)closeSessionWithConfirmation:(PTYSession *)aSession
{
    if ([[[aSession tab] sessions] count] == 1) {
        [self closeCurrentTab:self];
        return;
    }
    if ([aSession exited] ||
        ![[PreferencePanel sharedInstance] promptOnClose] ||
        [[PreferencePanel sharedInstance] onlyWhenMoreTabs] ||
        (NSRunAlertPanel([NSString stringWithFormat:@"%@ #%d",
                            [aSession name],
                            [[aSession tab] realObjectCount]],
                         NSLocalizedStringFromTableInBundle(@"This session will be closed.",
                                                            @"iTerm",
                                                            [NSBundle bundleForClass:[self class]],
                                                            @"Close Session"),
                         NSLocalizedStringFromTableInBundle(@"OK",
                                                            @"iTerm",
                                                            [NSBundle bundleForClass:[self class]],
                                                            @"OK"),
                         NSLocalizedStringFromTableInBundle(@"Cancel",
                                                            @"iTerm",
                                                            [NSBundle bundleForClass:[self class]],
                                                            @"Cancel"),
                         nil) == NSAlertDefaultReturn)) {
        // Just in case IR is open, close it first.
        [self closeInstantReplay:self];
        [self closeSession:aSession];
    }
}

- (IBAction)previousTab:(id)sender
{
    NSTabViewItem *tvi = [TABVIEW selectedTabViewItem];
    [TABVIEW selectPreviousTabViewItem:sender];
    if (tvi == [TABVIEW selectedTabViewItem]) {
        [TABVIEW selectTabViewItemAtIndex:[TABVIEW numberOfTabViewItems]-1];
    }
}

- (IBAction)nextTab:(id)sender
{
    NSTabViewItem *tvi = [TABVIEW selectedTabViewItem];
    [TABVIEW selectNextTabViewItem: sender];
    if (tvi == [TABVIEW selectedTabViewItem]) {
        [TABVIEW selectTabViewItemAtIndex:0];
    }
}

- (IBAction)previousPane:(id)sender
{
    [[self currentTab] previousSession];
}

- (IBAction)nextPane:(id)sender
{
    [[self currentTab] nextSession];
}

- (int)numberOfTabs
{
    return [TABVIEW numberOfTabViewItems];
}

- (PTYTab*)currentTab
{
    return [[TABVIEW selectedTabViewItem] identifier];
}

- (PTYSession *)currentSession
{
    return [[[TABVIEW selectedTabViewItem] identifier] activeSession];
}

- (void)dealloc
{
    // Do not assume that [self window] is valid here. It may have been freed.
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // Cancel any SessionView timers.
    for (PTYSession* aSession in [self sessions]) {
        [[aSession view] cancelTimers];
    }

    // Release all our sessions
    NSTabViewItem *aTabViewItem;
    for (; [TABVIEW numberOfTabViewItems]; )  {
        aTabViewItem = [TABVIEW tabViewItemAtIndex:0];
        [[aTabViewItem identifier] terminateAllSessions];
        PTYTab* theTab = [aTabViewItem identifier];
        [theTab setParentWindow:nil];
        [TABVIEW removeTabViewItem:aTabViewItem];
    }

    [commandField release];
    [bottomBar release];
    [_toolbarController release];
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
    if (title == nil) {
        // title can be nil during loadWindowArrangement
        title = @"";
    }

    if ([self sendInputToAllSessions]) {
        title = [NSString stringWithFormat:@"☛%@", title];
    }

    NSUInteger number = [[iTermController sharedInstance] indexOfTerminal:self];
    if ([[PreferencePanel sharedInstance] windowNumber] && number >= 0 && number < 9) {
        [[self window] setTitle:[NSString stringWithFormat:@"%d. %@", number_+1, title]];
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
    int i;

    int n = [TABVIEW numberOfTabViewItems];
    for (i = 0; i < n; ++i) {
        for (PTYSession* aSession in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
            if (![aSession exited]) {
                [[aSession SHELL] writeTask:data];
            }
        }
    }
}

+ (PseudoTerminal*)terminalWithArrangement:(NSDictionary*)arrangement
{
    PseudoTerminal* term;
    int windowType;
    if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_WINDOW_TYPE]) {
        windowType = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_WINDOW_TYPE] intValue];
    } else {
        if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_FULLSCREEN] &&
            [[arrangement objectForKey:TERMINAL_ARRANGEMENT_FULLSCREEN] boolValue]) {
            windowType = WINDOW_TYPE_FULL_SCREEN;
        } else {
            windowType = WINDOW_TYPE_NORMAL;
        }
    }
    int screenIndex;
    if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_SCREEN_INDEX]) {
        screenIndex = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_SCREEN_INDEX] intValue];
    } else {
        screenIndex = 0;
    }
    if (screenIndex < 0 || screenIndex >= [[NSScreen screens] count]) {
        screenIndex = 0;
    }

    if (windowType == WINDOW_TYPE_FULL_SCREEN) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                                 windowType:windowType
                                                     screen:screenIndex] autorelease];

        NSRect rect;
        rect.origin.x = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_X_ORIGIN] doubleValue];
        rect.origin.y = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_Y_ORIGIN] doubleValue];
        rect.size.width = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_WIDTH] doubleValue];
        rect.size.height = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_HEIGHT] doubleValue];
        term->oldFrame_ = rect;
    } else {
        if (windowType == WINDOW_TYPE_NORMAL) {
            screenIndex = -1;
        }
        term = [[[PseudoTerminal alloc] initWithSmartLayout:NO windowType:windowType screen:-1] autorelease];

        NSRect rect;
        rect.origin.x = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_X_ORIGIN] doubleValue];
        rect.origin.y = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_Y_ORIGIN] doubleValue];
        // TODO: for window type top, set width to screen width.
        rect.size.width = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
        rect.size.height = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
        [[term window] setFrame:rect display:NO];
    }
    for (NSDictionary* tabArrangement in [arrangement objectForKey:TERMINAL_ARRANGEMENT_TABS]) {
        [PTYTab openTabWithArrangement:tabArrangement inTerminal:term];
    }
    [term->TABVIEW selectTabViewItemAtIndex:[[arrangement objectForKey:TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX] intValue]];

    return term;
}

- (NSDictionary*)arrangement
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:7];
    NSRect rect = [[self window] frame];
    int screenNumber = 0;
    for (NSScreen* screen in [NSScreen screens]) {
        if (screen == [[self window] deepestScreen]) {
            break;
        }
        ++screenNumber;
    }

    // Save window frame
    [result setObject:[NSNumber numberWithDouble:rect.origin.x]
               forKey:TERMINAL_ARRANGEMENT_X_ORIGIN];
    [result setObject:[NSNumber numberWithDouble:rect.origin.y]
               forKey:TERMINAL_ARRANGEMENT_Y_ORIGIN];
    [result setObject:[NSNumber numberWithDouble:rect.size.width]
               forKey:TERMINAL_ARRANGEMENT_WIDTH];
    [result setObject:[NSNumber numberWithDouble:rect.size.height]
               forKey:TERMINAL_ARRANGEMENT_HEIGHT];

    if (_fullScreen) {
        // Save old window frame
        [result setObject:[NSNumber numberWithDouble:oldFrame_.origin.x]
                   forKey:TERMINAL_ARRANGEMENT_OLD_X_ORIGIN];
        [result setObject:[NSNumber numberWithDouble:oldFrame_.origin.y]
                   forKey:TERMINAL_ARRANGEMENT_OLD_Y_ORIGIN];
        [result setObject:[NSNumber numberWithDouble:oldFrame_.size.width]
                   forKey:TERMINAL_ARRANGEMENT_OLD_WIDTH];
        [result setObject:[NSNumber numberWithDouble:oldFrame_.size.height]
                   forKey:TERMINAL_ARRANGEMENT_OLD_HEIGHT];
    }

    [result setObject:[NSNumber numberWithInt:windowType_]
               forKey:TERMINAL_ARRANGEMENT_WINDOW_TYPE];
    [result setObject:[NSNumber numberWithInt:[[NSScreen screens] indexOfObjectIdenticalTo:[[self window] screen]]]
                                       forKey:TERMINAL_ARRANGEMENT_SCREEN_INDEX];
    // Save tabs.
    NSMutableArray* tabs = [NSMutableArray arrayWithCapacity:[self numberOfTabs]];
    for (NSTabViewItem* tabViewItem in [TABVIEW tabViewItems]) {
        [tabs addObject:[[tabViewItem identifier] arrangement]];
    }
    [result setObject:tabs forKey:TERMINAL_ARRANGEMENT_TABS];

    // Save index of selected tab.
    [result setObject:[NSNumber numberWithInt:[TABVIEW indexOfTabViewItem:[TABVIEW selectedTabViewItem]]]
               forKey:TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX];

    return result;
}

// NSWindow delegate methods
- (void)windowDidDeminiaturize:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidDeminiaturize:%@]",
          __FILE__, __LINE__, aNotification);
#endif
    if ([[self currentTab] blur]) {
        [self enableBlur];
    } else {
        [self disableBlur];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowDidDeminiaturize"
                                                        object:self
                                                      userInfo:nil];
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

    // Close popups.
    [pbHistoryView close];
    [autocompleteView close];

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
            [self showHideInstantReplay];
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

    // Kill sessions so their timers stop and they are freed.
    for (PTYSession* session in [self sessions]) {
        if (![session exited]) {
            [session terminate];
        }
    }

    // This releases the last reference to self.
    [[iTermController sharedInstance] terminalWillClose:self];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowDidClose"
                                                        object:nil
                                                      userInfo:nil];
}

- (void)windowWillMiniaturize:(NSNotification *)aNotification
{
    [self disableBlur];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowWillMiniaturize"
                                                        object:self
                                                      userInfo:nil];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    isOrderedOut_ = NO;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidBecomeKey:%@]",
          __FILE__, __LINE__, aNotification);
#endif
    PtyLog(@"%s(%d):-[PseudoTerminal windowDidBecomeKey:%@]",
          __FILE__, __LINE__, aNotification);

    [[iTermController sharedInstance] setCurrentTerminal:self];
    [[[NSApplication sharedApplication] delegate] updateMaximizePaneMenuItem];
    [[[NSApplication sharedApplication] delegate] updateUseTransparencyMenuItem];
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
    [self _loadFindStringFromSharedPasteboard];
}

// Forbid FFM from changing key window if is hotkey window.
- (BOOL)disableFocusFollowsMouse
{
    return isHotKeyWindow_;
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
    PtyLog(@"PseudoTerminal windowDidResignKey");
    if ([self isHotKeyWindow] && ![[iTermController sharedInstance] rollingInHotkeyTerm]) {
        PtyLog(@"windowDidResignKey: is hotkey");
        // We want to dismiss the hotkey window when some other window
        // becomes key. Note that if a popup closes this function shouldn't
        // be called at all because it makes us key before closing itself.
        // If a popup is opening, though, we shouldn't close ourselves.
        if (![[NSApp keyWindow] isKindOfClass:[PopupWindow class]]) {
            PtyLog(@"windowDidResignKey: new key window isn't popup so hide myself");
            [[iTermController sharedInstance] hideHotKeyWindow:self];
        }
    }
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

    // Find the session for the current pane of the current tab.
    PTYTab* tab = [self currentTab];
    PTYSession* session = [tab activeSession];

    // Get the width and height of characters in this session.
    float charWidth = [[session TEXTVIEW] charWidth];
    float charHeight = [[session TEXTVIEW] lineHeight];

    // Decide when to snap.  (We snap unless shift is held down.)
    BOOL shiftDown = (([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) != 0);
    BOOL snapWidth = !shiftDown;
    BOOL snapHeight = !shiftDown;
    if (sender != [self window]) {
      snapWidth = snapHeight = false;
    }

    // Compute proposed tab size (window minus decorations).
    NSSize decorationSize = [self windowDecorationSize];
    NSSize tabSize = NSMakeSize(proposedFrameSize.width - decorationSize.width,
                                proposedFrameSize.height - decorationSize.height);

    // Snap proposed tab size to grid.  The snapping uses a grid spaced to
    // match the current pane's character size and aligned so margins are
    // correct if all we have is a single pane.
    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
    NSSize contentSize = [PTYScrollView contentSizeForFrameSize:tabSize
                                        hasHorizontalScroller:NO
                                        hasVerticalScroller:hasScrollbar
                                        borderType:NSNoBorder];

    int screenWidth = (contentSize.width - MARGIN * 2) / charWidth;
    int screenHeight = (contentSize.height - VMARGIN * 2) / charHeight;

    if (snapWidth) {
      contentSize.width = screenWidth * charWidth + MARGIN * 2;
    }
    if (snapHeight) {
      contentSize.height = screenHeight * charHeight + VMARGIN * 2;
    }
    tabSize = [PTYScrollView frameSizeForContentSize:contentSize
                             hasHorizontalScroller:NO
                             hasVerticalScroller:hasScrollbar
                             borderType:NSNoBorder];

    // Respect minimum tab sizes.
    for (NSTabViewItem* tabViewItem in [TABVIEW tabViewItems]) {
        PTYTab* theTab = [tabViewItem identifier];
        NSSize minTabSize = [theTab minSize];
        tabSize.width = MAX(tabSize.width, minTabSize.width);
        tabSize.height = MAX(tabSize.height, minTabSize.height);
    }

    // Compute new window size from tab size.
    proposedFrameSize.width = tabSize.width + decorationSize.width;
    proposedFrameSize.height = tabSize.height + decorationSize.height;

    // Apply maximum window size.
    NSSize maxFrameSize = [self maxFrame].size;
    proposedFrameSize.width = MIN(maxFrameSize.width, proposedFrameSize.width);
    proposedFrameSize.height = MIN(maxFrameSize.height, proposedFrameSize.height);

    // If snapping, reject the new size if the mouse has not moved at least
    // half the current grid size in a given direction.  This is really
    // important to the feel of the snapping, especially when the window is
    // not aligned to the grid (e.g. after switching to a tab with a
    // different font size).
    NSSize senderSize = [sender frame].size;
    if (snapWidth) {
      int deltaX = abs(senderSize.width - proposedFrameSize.width);
      if (deltaX < (int)(charWidth / 2)) {
        proposedFrameSize.width = senderSize.width;
      }
    }
    if (snapHeight) {
      int deltaY = abs(senderSize.height - proposedFrameSize.height);
      if (deltaY < (int)(charHeight / 2)) {
        proposedFrameSize.height = senderSize.height;
      }
    }

    PtyLog(@"Accepted size: %fx%f", proposedFrameSize.width, proposedFrameSize.height);

    return proposedFrameSize;
}

- (void)windowDidResize:(NSNotification *)aNotification
{
    PtyLog(@"windowDidResize to: %fx%f", [[self window] frame].size.width, [[self window] frame].size.height);
    if (togglingFullScreen_) {
        PtyLog(@"windowDidResize returning because togglingFullScreen.");
        return;
    }

    // Adjust the size of all the sessions.
    PtyLog(@"windowDidResize - call repositionWidgets");
    [self repositionWidgets];

    PTYSession* session = [self currentSession];
    NSString *aTitle = [NSString stringWithFormat:@"%@ (%d,%d)",
                        [self currentSessionName],
                        [session columns],
                        [session rows]];
    [self setWindowTitle:aTitle];
    tempTitle = YES;
    [self fitTabsToWindow];

    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowDidResize"
                                                        object:self
                                                      userInfo:nil];
}

// PTYWindowDelegateProtocol
- (void)windowWillToggleToolbarVisibility:(id)sender
{
}

- (void)windowDidToggleToolbarVisibility:(id)sender
{
    PtyLog(@"windowDidToggleToolbarVisibility - calling fitWindowToTabs");
    [self fitWindowToTabs];
}

- (IBAction)toggleUseTransparency:(id)sender
{
    useTransparency_ = !useTransparency_;
    [[[NSApplication sharedApplication] delegate] updateUseTransparencyMenuItem];
    for (PTYSession* aSession in [self sessions]) {
        [[aSession view] setNeedsDisplay:YES];
    }
}

- (BOOL)useTransparency
{
    return useTransparency_;
}

- (IBAction)toggleFullScreen:(id)sender
{
    if (windowType_ == WINDOW_TYPE_TOP) {
        // TODO: would be nice if you could toggle top windows to fullscreen
        return;
    }
    PtyLog(@"toggleFullScreen called");
    PseudoTerminal *newTerminal;
    if (!_fullScreen) {
        NSScreen *currentScreen = [[[[iTermController sharedInstance] currentTerminal] window] screen];
        newTerminal = [[PseudoTerminal alloc] initWithSmartLayout:NO
                                                       windowType:WINDOW_TYPE_FULL_SCREEN
                                                           screen:[[NSScreen screens] indexOfObjectIdenticalTo:currentScreen]];
        newTerminal->oldFrame_ = [[self window] frame];
        newTerminal->useTransparency_ = NO;
        [[newTerminal window] setOpaque:NO];
    } else {
        // If a window is created while the menu bar is hidden then its
        // miniaturize button will be disabled, even if the menu bar is later
        // shown. Thus, we must show the menu bar before creating the new window.
        // It is not hidden in the other clause of this if statement because
        // hiding the menu bar must be done after setting the window's frame.
        [NSMenu setMenuBarVisible:YES];
        PtyLog(@"toggleFullScreen - allocate new terminal");
        // TODO: restore previous window type
        NSScreen *currentScreen = [[[[iTermController sharedInstance] currentTerminal] window] screen];
        newTerminal = [[PseudoTerminal alloc] initWithSmartLayout:NO
                                                       windowType:WINDOW_TYPE_NORMAL
                                                       screen:[[NSScreen screens] indexOfObjectIdenticalTo:currentScreen]];
        PtyLog(@"toggleFullScreen - set new frame to old frame: %fx%f", oldFrame_.size.width, oldFrame_.size.height);
        [[newTerminal window] setFrame:oldFrame_ display:YES];
    }
    [newTerminal setIsHotKeyWindow:isHotKeyWindow_];

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

    newTerminal->_resizeInProgressFlag = YES;
    for (i = 0; i < n; ++i) {
        aTabViewItem = [[TABVIEW tabViewItemAtIndex:0] retain];
        PTYTab* theTab = [aTabViewItem identifier];
        for (PTYSession* aSession in [theTab sessions]) {
            [aSession setTransparency:[[[aSession addressBookEntry] objectForKey:KEY_TRANSPARENCY] floatValue]];
        }
        // remove from our window
        PtyLog(@"toggleFullScreen - remove tab %d from old window", i);
        [TABVIEW removeTabViewItem:aTabViewItem];

        // add the session to the new terminal
        PtyLog(@"toggleFullScreen - add tab %d from old window", i);
        [newTerminal insertTab:theTab atIndex:i];
        PtyLog(@"toggleFullScreen - done inserting session", i);

        // release the tabViewItem
        [aTabViewItem release];
    }
    newTerminal->_resizeInProgressFlag = NO;
    [[newTerminal tabView] selectTabViewItemWithIdentifier:[currentSession tab]];
    BOOL fs = _fullScreen;
    PtyLog(@"toggleFullScreen - close old window", i);
    // The window close call below also releases the window controller (self).
    // This causes havoc because we keep running for a while, so we'll retain a
    // copy of ourselves and release it when we're all done.
    [self retain];
    [[self window] close];
    if (fs) {
        PtyLog(@"toggleFullScreen - call adjustFullScreenWindowForBottomBarChange");
        [newTerminal adjustFullScreenWindowForBottomBarChange];
        [newTerminal hideMenuBar];
    }

    if (!fs) {
        // Find the largest possible session size for the existing window frame
        // and fit the window to an imaginary session of that size.
        NSSize contentSize = [[[newTerminal window] contentView] frame].size;
        if (![newTerminal->bottomBar isHidden]) {
            contentSize.height -= [newTerminal->bottomBar frame].size.height;
        }
        if ([newTerminal->TABVIEW numberOfTabViewItems] > 1 ||
            ![[PreferencePanel sharedInstance] hideTab]) {
            contentSize.height -= [newTerminal->tabBarControl frame].size.height;
        }
        [newTerminal fitWindowToTabSize:contentSize];
    }
    newTerminal->togglingFullScreen_ = NO;
    PtyLog(@"toggleFullScreen - calling fitTabsToWindow");
    [newTerminal repositionWidgets];
    [newTerminal fitTabsToWindow];
    if (fs) {
        PtyLog(@"toggleFullScreen - calling adjustFullScreenWindowForBottomBarChange");
        [newTerminal adjustFullScreenWindowForBottomBarChange];
    } else {
        PtyLog(@"toggleFullScreen - calling fitWindowToTabs");
        [newTerminal fitWindowToTabs];
    }
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

    if ([[PreferencePanel sharedInstance] maxVertically] ^
        (([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) != 0)) {
        verticalOnly = YES;
    }
    if (verticalOnly) {
        proposedFrame.size.width = [sender frame].size.width;
    } else {
        proposedFrame.size.width = decorationWidth + floor(defaultFrame.size.width / charWidth) * charWidth;
    }
    // TODO: This doesn't make any sense with horizontal split panes.
    proposedFrame.size.height = floor((defaultFrame.size.height - decorationHeight - VMARGIN * 2) / charHeight) * charHeight + decorationHeight + VMARGIN*2;

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
        if ([window setFrameUsingName:[NSString stringWithFormat:WINDOW_NAME, framePos]]) {
            frame.origin = [window frame].origin;
            frame.origin.y += [window frame].size.height - frame.size.height;
        } else {
            frame.origin = preferredOrigin_;
        }
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

    [[session tab] setLockedSession:session];
    [self safelySetSessionSize:session rows:height columns:width];
    PtyLog(@"sessionInitiatedResize - calling fitWindowToTab");
    [self fitWindowToTab:[session tab]];
    PtyLog(@"sessionInitiatedResize - calling fitTabsToWindow");
    [self fitTabsToWindow];
    [[session tab] setLockedSession:nil];
}

// Contextual menu
- (void)editCurrentSession:(id)sender
{
    PTYSession* session = [self currentSession];
    if (!session) {
        return;
    }
    [self editSession:session];
}

- (void)editSession:(PTYSession*)session
{
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
    int nextIndex = 0;
    NSMenuItem *aMenuItem;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal menuForEvent]", __FILE__, __LINE__);
#endif

    if (theMenu == nil) {
        return;
    }

    // Bookmarks
    [theMenu insertItemWithTitle:NSLocalizedStringFromTableInBundle(@"New Window",
                                                                    @"iTerm",
                                                                    [NSBundle bundleForClass:[self class]],
                                                                    @"Context menu")
                          action:nil
                   keyEquivalent:@""
                         atIndex:nextIndex++];
    [theMenu insertItemWithTitle:NSLocalizedStringFromTableInBundle(@"New Tab",
                                                                    @"iTerm",
                                                                    [NSBundle bundleForClass:[self class]],
                                                                    @"Context menu")
                          action:nil
                   keyEquivalent:@""
                         atIndex:nextIndex++];

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

    // TODO: test this
    [[iTermController sharedInstance] addBookmarksToMenu:aMenu
                                                  target:[iTermController sharedInstance]
                                           withShortcuts:NO
                                                selector:@selector(newSessionInWindowAtIndex:)
                                         openAllSelector:@selector(newSessionsInManyWindows:)
                                       alternateSelector:nil];
    [aMenu addItem: [NSMenuItem separatorItem]];

    [theMenu setSubmenu:aMenu forItem:[theMenu itemAtIndex:0]];

    aMenu = [[[NSMenu alloc] init] autorelease];
    [[iTermController sharedInstance] addBookmarksToMenu:aMenu
                                                  target:self
                                           withShortcuts:NO
                                                selector:@selector(newSessionInTabAtIndex:)
                                         openAllSelector:@selector(newSessionsInManyTabsAtIndex:)
                                       alternateSelector:nil];
    [aMenu addItem: [NSMenuItem separatorItem]];

    [theMenu setSubmenu:aMenu forItem:[theMenu itemAtIndex:1]];
}

// NSTabView
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView: willSelectTabViewItem]", __FILE__, __LINE__);
#endif
    if (![[self currentSession] exited]) {
        [[self currentSession] setNewOutput:NO];
    }
    // If the user is currently select-dragging the text view, stop it so it
    // doesn't keep going in the background.
    [[[self currentSession] TEXTVIEW] aboutToHide];

    if ([[autocompleteView window] isVisible]) {
        [autocompleteView close];
    }
    NSColor* newTabColor = [tabBarControl tabColorForTabViewItem:tabViewItem];
    if (newTabColor && !sendInputToAllSessions) {
        [[self window] setBackgroundColor:newTabColor];
        [background_ setColor:newTabColor];
    } else if (sendInputToAllSessions) {
        [[self window] setBackgroundColor: [NSColor highlightColor]];
        [background_ setColor:[NSColor highlightColor]];
    } else {
        [[self window] setBackgroundColor:nil];
        [background_ setColor:normalBackgroundColor];
    }
}

- (void)enableBlur
{
    id window = [self window];
    if (nil != window &&
        [window respondsToSelector:@selector(enableBlur)]) {
        [window enableBlur];
    }
}

- (void)disableBlur
{
    id window = [self window];
    if (nil != window &&
        [window respondsToSelector:@selector(disableBlur)]) {
        [window disableBlur];
    }
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    for (PTYSession* aSession in [[tabViewItem identifier] sessions]) {
        [aSession setNewOutput:NO];

        // Background tabs' timers run infrequently so make sure the display is
        // up to date to avoid a jump when it's shown.
        [[aSession TEXTVIEW] setNeedsDisplay:YES];
        [aSession updateDisplay];
        [aSession scheduleUpdateIn:kFastTimerIntervalSec];
    }

    PTYSession* aSession = [[tabViewItem identifier] activeSession];
    if (_fullScreen) {
        [self _drawFullScreenBlackBackground];
    } else {
        [[aSession tab] setLabelAttributes];
        [self setWindowTitle];
    }

    [[self window] makeFirstResponder:[[[tabViewItem identifier] activeSession] TEXTVIEW]];
    if ([[aSession tab] blur]) {
        [self enableBlur];
    } else {
        [self disableBlur];
    }

    if (![bottomBar isHidden]) {
        [self updateInstantReplay];
    }
    // Post notifications
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                        object:[[tabViewItem identifier] activeSession]];
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
    PTYTab* theTab = [tabViewItem identifier];
    [theTab setParentWindow:self];
}

- (BOOL)tabView:(NSTabView*)tabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem
{
    PTYTab *aTab = [tabViewItem identifier];

    return ([aTab allSessionsExited] ||
            ![[PreferencePanel sharedInstance] promptOnClose] ||
            [[PreferencePanel sharedInstance] onlyWhenMoreTabs] ||
            (NSRunAlertPanel([NSString stringWithFormat:@"%@ #%d",
                              [[aTab activeSession] name],
                              [[[aTab activeSession] tab] realObjectCount]],
                             NSLocalizedStringFromTableInBundle(@"This session will be closed.",
                                                                @"iTerm",
                                                                [NSBundle bundleForClass:[self class]],
                                                                @"Close Session"),
                        NSLocalizedStringFromTableInBundle(@"OK",
                                                           @"iTerm",
                                                           [NSBundle bundleForClass:[self class]],
                                                           @"OK"),
                        NSLocalizedStringFromTableInBundle(@"Cancel",
                                                           @"iTerm",
                                                           [NSBundle bundleForClass:[self class]],
                                                           @"Cancel"),
                        nil) == NSAlertDefaultReturn));

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

- (void)tabView:(NSTabView*)aTabView willDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)aTabBarControl
{
    PTYTab *aTab = [tabViewItem identifier];
    for (PTYSession* aSession in [aTab sessions]) {
        [aSession setIgnoreResizeNotifications:YES];
    }
}

- (void)tabView:(NSTabView*)aTabView didDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)aTabBarControl
{
    PTYTab *aTab = [tabViewItem identifier];
    PseudoTerminal *term = [aTabBarControl delegate];

    if ([term numberOfTabs] == 1) {
        [term fitWindowToTabs];
    } else {
        [term fitTabToWindow:aTab];
    }
    int i;
    for (i=0; i < [aTabView numberOfTabViewItems]; ++i) {
        PTYTab *theTab = [[aTabView tabViewItemAtIndex:i] identifier];
        [theTab setObjectCount:i+1];
    }

    // In fullscreen mode reordering the tabs causes the tabview not to be displayed properly.
    // This seems to fix it.
    [TABVIEW display];
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

        // Grabs whole tabview image.
        viewImage = [[[NSImage alloc] initWithSize:contentFrame.size] autorelease];
        NSImage *tabViewImage = [[[NSImage alloc] init] autorelease];

        [textview lockFocus];
        NSBitmapImageRep *tabviewRep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:viewRect] autorelease];
        [tabViewImage addRepresentation:tabviewRep];
        [textview unlockFocus];

        [viewImage lockFocus];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) {
            viewRect.origin.y += tabHeight;
        }
        [tabViewImage compositeToPoint:viewRect.origin operation:NSCompositeSourceOver];
        [viewImage unlockFocus];

        // Draw over where the tab bar would usually be.
        [viewImage lockFocus];
        [[NSColor windowBackgroundColor] set];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            tabFrame.origin.y += viewRect.size.height;
        }
        NSRectFill(tabFrame);
        // Draw the background flipped, which is actually the right way up
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
        tabFrame.origin.y = -tabFrame.origin.y - tabFrame.size.height;
        [(id <PSMTabStyle>)[[aTabView delegate] style] drawBackgroundInRect:tabFrame color:nil];
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
        // grabs whole tabview image
        viewImage = [[tabViewItem identifier] image:YES];

        offset->width = [(id <PSMTabStyle>)[tabBarControl style] leftMarginForTabBarControl];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            offset->height = 22;
        }
        else {
            offset->height = [viewImage size].height;
        }
        *styleMask = NSBorderlessWindowMask;
    }

    return viewImage;
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView
{
    PtyLog(@"%s(%d):-[PseudoTerminal tabViewDidChangeNumberOfTabViewItems]", __FILE__, __LINE__);
    for (PTYSession* session in [self allSessions]) {
        [session setIgnoreResizeNotifications:NO];
    }

    // check window size in case tabs have to be hidden or shown
    if (([TABVIEW numberOfTabViewItems] == 1) || ([[PreferencePanel sharedInstance] hideTab] &&
        ([TABVIEW numberOfTabViewItems] > 1 && [tabBarControl isHidden]))) {
        PtyLog(@"tabViewDidChangeNumberOfTabViewItems - calling fitWindowToTab");
        [self fitWindowToTabs];
    }

    int i;
    for (i=0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYTab *aTab = [[TABVIEW tabViewItemAtIndex: i] identifier];
        [aTab setObjectCount:i+1];
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
        for (NSTabViewItem *aTabViewItem in [TABVIEW tabViewItems]) {
            NSString *title = [NSString stringWithFormat:@"%@ #%d", [aTabViewItem label], count++];
            item = [[[NSMenuItem alloc] initWithTitle:title
                                               action:@selector(selectTab:)
                                        keyEquivalent:@""] autorelease];
            [item setRepresentedObject:[aTabViewItem identifier]];
            [item setTarget:TABVIEW];
            [tabMenu addItem:item];
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
    PTYTab *aTab = [tabViewItem identifier];

    if (aTab == nil) {
        return nil;
    }

    // create a new terminal window
    term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                             windowType:WINDOW_TYPE_NORMAL
                                                 screen:-1] autorelease];
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
    NSDictionary *ade = [[[aTabViewItem identifier] activeSession] addressBookEntry];
    BOOL ignore;
    NSString *temp = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Name: %@\nCommand: %@",
                                                                                   @"iTerm",
                                                                                   [NSBundle bundleForClass:[self class]],
                                                                                   @"Tab Tooltips"),
                      [ade objectForKey:KEY_NAME],
                      [ITAddressBookMgr bookmarkCommand:ade isLoginSession:&ignore]];

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

- (void)setTabColor:(NSColor*)color forTabViewItem:(NSTabViewItem*)tabViewItem
{
    [tabBarControl setTabColor:color forTabViewItem:tabViewItem];
    if ([TABVIEW selectedTabViewItem] == tabViewItem) {
        NSColor* newTabColor = [tabBarControl tabColorForTabViewItem:tabViewItem];
        if (newTabColor && !sendInputToAllSessions) {
            [[self window] setBackgroundColor:newTabColor];
            [background_ setColor:newTabColor];
        }
    }
}

- (NSColor*)tabColorForTabViewItem:(NSTabViewItem*)tabViewItem
{
    return [tabBarControl tabColorForTabViewItem:tabViewItem];
}

- (PTYTabView *)tabView
{
    return TABVIEW;
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    int move = [[[aNotification userInfo] objectForKey:@"NSTextMovement"] intValue];

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
                    withCommand:[commandField stringValue]
                 asLoginSession:NO];
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

- (void)fillPath:(NSBezierPath*)path
{
    if ([tabBarControl isHidden]) {
        [[NSColor windowBackgroundColor] set];
        [path fill];
        [[NSColor darkGrayColor] set];
        [path stroke];
    } else {
      [tabBarControl fillPath:path];
    }
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
    if (![bottomBar isHidden]) {
        [self updateInstantReplay];
    }
}

- (BOOL)inInstantReplay
{
    return ![bottomBar isHidden];
}

// Toggle instant replay bar.
- (void)showHideInstantReplay
{
    BOOL hide = ![bottomBar isHidden];
    if (!hide) {
        [self updateInstantReplay];
    }
    [bottomBar setHidden:hide];
    if (_fullScreen) {
        [self adjustFullScreenWindowForBottomBarChange];
    } else {
        [[[self window] contentView] setAutoresizesSubviews:NO];
        if (hide) {
            NSRect frame = [[self window] frame];
            NSPoint topLeft;
            topLeft.x = frame.origin.x;
            topLeft.y = frame.origin.y + frame.size.height;
            [[self window] setFrame:preBottomBarFrame display:NO];
            [[self window] setFrameTopLeftPoint:topLeft];
        } else {
            preBottomBarFrame = [[self window] frame];
            NSRect newFrame = preBottomBarFrame;
            float h = [instantReplaySubview frame].size.height;
            newFrame.size.height += h;
            newFrame.origin.y -= h;
            [[self window] setFrame:newFrame display:YES];
        }
    }

    // On OS X 10.5.8, the scroll bar and resize indicator are messed up at this point. Resizing the tabview fixes it. This seems to be fixed in 10.6.
    NSRect tvframe = [TABVIEW frame];
    tvframe.size.height += 1;
    [TABVIEW setFrame: tvframe];
    tvframe.size.height -= 1;
    [TABVIEW setFrame: tvframe];
    [[[self window] contentView] setAutoresizesSubviews:YES];

    [[self window] makeFirstResponder:[[self currentSession] TEXTVIEW]];
}

- (IBAction)closeInstantReplay:(id)sender
{
    if (![bottomBar isHidden]) {
        if ([[self currentSession] liveSession]) {
            [self showLiveSession:[[self currentSession] liveSession] inPlaceOf:[self currentSession]];
        }
        [self showOrHideInstantReplayBar];
    }
}

- (void)fitWindowToTab:(PTYTab*)tab
{
    [self fitWindowToTabSize:[tab size]];
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
    if ([[[oldSession SCREEN] dvr] lastTimeStamp] == 0) {
        // Nothing recorded (not enough memory for one frame, perhaps?).
        return;
    }
    PTYSession *newSession;

    // Initialize a new session
    newSession = [[PTYSession alloc] init];
    // NSLog(@"New session for IR view is at %p", newSession);

    // set our preferences
    [newSession setAddressBookEntry:[oldSession addressBookEntry]];
    [[newSession SCREEN] setScrollback:0];
    [self setupSession:newSession title:nil withSize:nil];

    // Add this session to our term and make it current
    PTYTab* theTab = [oldTabViewItem identifier];
    [newSession setTab:theTab];
    [theTab setDvrInSession:newSession];
    [newSession release];
    if ([bottomBar isHidden]) {
        [self showHideInstantReplay];
    }
}

- (void)showLiveSession:(PTYSession*)liveSession inPlaceOf:(PTYSession*)replaySession
{
    PTYTab* theTab = [replaySession tab];
    [self updateInstantReplay];
#ifdef HIDE_IR_WHEN_LIVE_VIEW_ENTERED
    [self showHideInstantReplay];
#endif
    [theTab showLiveSession:liveSession inPlaceOf:replaySession];
    [theTab setParentWindow:self];
    [[self window] makeFirstResponder:[[theTab activeSession] TEXTVIEW]];
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
#ifdef HIDE_IR_WHEN_LIVE_VIEW_ENTERED
    if ([irSlider floatValue] == 1.0) {
        if ([[self currentSession] liveSession]) {
            [self showLiveSession:[[self currentSession] liveSession] inPlaceOf:[self currentSession]];
        }
    } else {
#endif
        if (![[self currentSession] liveSession]) {
            [self replaySession:[self currentSession]];
        }
        [[self currentSession] irSeekToAtLeast:[self timestampForFraction:[irSlider floatValue]]];
#ifdef HIDE_IR_WHEN_LIVE_VIEW_ENTERED
    }
#endif
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
    if ([[autocompleteView window] isVisible]) {
        [autocompleteView more];
    } else {
        [autocompleteView popInSession:[self currentSession]];
    }
}

- (BOOL)canSplitPaneVertically:(BOOL)isVertical withBookmark:(Bookmark*)theBookmark
{
    NSFont* asciiFont = [ITAddressBookMgr fontWithDesc:[theBookmark objectForKey:KEY_NORMAL_FONT]];
    NSFont* nonAsciiFont = [ITAddressBookMgr fontWithDesc:[theBookmark objectForKey:KEY_NON_ASCII_FONT]];
    NSSize asciiCharSize = [PTYTextView charSizeForFont:asciiFont
                                      horizontalSpacing:[[theBookmark objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                        verticalSpacing:[[theBookmark objectForKey:KEY_VERTICAL_SPACING] floatValue]];
    NSSize nonAsciiCharSize = [PTYTextView charSizeForFont:nonAsciiFont
                                         horizontalSpacing:[[theBookmark objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                           verticalSpacing:[[theBookmark objectForKey:KEY_VERTICAL_SPACING] floatValue]];
    NSSize charSize = NSMakeSize(MAX(asciiCharSize.width, nonAsciiCharSize.width),
                                 MAX(asciiCharSize.height, nonAsciiCharSize.height));
    NSSize newSessionSize = NSMakeSize(charSize.width * MIN_SESSION_COLUMNS + MARGIN * 2,
                                       charSize.height * MIN_SESSION_ROWS + VMARGIN * 2);

    if (![[self currentTab] canSplitVertically:isVertical withSize:newSessionSize]) {
        // Test if the window can afford to grow. First, compute the minimum growth possible based on
        // the font size of the new pane.
        BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
        NSSize growth = NSMakeSize(isVertical ? newSessionSize.width : 0,
                                   isVertical ? 0 : newSessionSize.height);
        growth = [PTYScrollView frameSizeForContentSize:growth
                                  hasHorizontalScroller:NO
                                    hasVerticalScroller:hasScrollbar
                                             borderType:NSNoBorder];

        // Now compute the minimum window size that can support this new pane.
        NSSize windowSize = NSZeroSize;
        for (NSTabViewItem* theItem in [TABVIEW tabViewItems]) {
            PTYTab* theTab = [theItem identifier];
            NSSize minTabSize = [theTab minSize];
            windowSize.width = MAX(windowSize.width, minTabSize.width);
            windowSize.height = MAX(windowSize.height, minTabSize.height);
        }
        NSSize decoration = [self windowDecorationSize];
        windowSize.width += decoration.width;
        windowSize.height += decoration.height;
        windowSize.width += growth.width;
        windowSize.height += growth.height;

        // Finally, check if the new window size would fit on the screen.
        NSSize maxFrameSize = [self maxFrame].size;
        if (windowSize.width > maxFrameSize.width || windowSize.height > maxFrameSize.height) {
            return NO;
        }
    }
    return YES;
}

- (void)toggleMaximizeActivePane
{
    if ([[self currentTab] hasMaximizedPane]) {
        [[self currentTab] unmaximize];
    } else {
        [[self currentTab] maximize];
    }
}

- (void)newWindowWithBookmarkGuid:(NSString*)guid
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
    if (bookmark) {
        [[iTermController sharedInstance] launchBookmark:bookmark inTerminal:nil];
    }
}

- (void)newTabWithBookmarkGuid:(NSString*)guid
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
    if (bookmark) {
        [[iTermController sharedInstance] launchBookmark:bookmark inTerminal:self];
    }
}

- (void)splitVertically:(BOOL)isVertical withBookmarkGuid:(NSString*)guid
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
    if (bookmark) {
        [self splitVertically:isVertical withBookmark:bookmark targetSession:[self currentSession]];
    }
}

- (void)splitVertically:(BOOL)isVertical withBookmark:(Bookmark*)theBookmark targetSession:(PTYSession*)targetSession
{
    PtyLog(@"--------- splitVertically -----------");
    if (![self canSplitPaneVertically:isVertical withBookmark:theBookmark]) {
        NSBeep();
        return;
    }
    NSString *oldCWD = nil;

    /* Get currently selected tabviewitem */
    if ([self currentSession]) {
        oldCWD = [[[self currentSession] SHELL] getWorkingDirectory];
    }

    PTYSession* newSession = [self newSessionWithBookmark:theBookmark];
    SessionView* sessionView = [[self currentTab] splitVertically:isVertical targetSession:targetSession];
    [sessionView setSession:newSession];
    [newSession setTab:[self currentTab]];
    [newSession setView:sessionView];
    NSSize size = [sessionView frame].size;
    [self setupSession:newSession title:nil withSize:&size];

    // Move the scrollView into sessionView.
    NSView* scrollView = [[[newSession view] subviews] objectAtIndex:0];
    [scrollView retain];
    [scrollView removeFromSuperview];
    [sessionView addSubview:scrollView];
    [scrollView release];

    [self fitTabsToWindow];

    [self runCommandInSession:newSession inCwd:oldCWD];
    if (targetSession == [[self currentTab] activeSession]) {
        [[self currentTab] setActiveSessionPreservingViewOrder:newSession];
    }
    [[self currentTab] recheckBlur];
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermNumberOfSessionsDidChange" object: self userInfo: nil];
}

- (IBAction)splitVertically:(id)sender
{
    Bookmark* theBookmark = [[BookmarkModel sharedInstance] defaultBookmark];
    [self splitVertically:YES withBookmark:theBookmark targetSession:[[self currentTab] activeSession]];
}

- (IBAction)splitHorizontally:(id)sender
{
    Bookmark* theBookmark = [[BookmarkModel sharedInstance] defaultBookmark];
    [self splitVertically:NO withBookmark:theBookmark targetSession:[[self currentTab] activeSession]];
}

- (void)fitWindowToTabs
{
    if (togglingFullScreen_) {
        return;
    }

    // Determine the size of the largest tab.
    NSSize maxTabSize = NSZeroSize;
    PtyLog(@"fitWindowToTabs.......");
    for (NSTabViewItem* item in [TABVIEW tabViewItems]) {
        PTYTab* tab = [item identifier];
        NSSize tabSize = [tab size];
        PtyLog(@"The natrual size of this tab is %lf", tabSize.height);
        if (tabSize.width > maxTabSize.width) {
            maxTabSize.width = tabSize.width;
        }
        if (tabSize.height > maxTabSize.height) {
            maxTabSize.height = tabSize.height;
        }

        tabSize = [tab minSize];
        if (tabSize.width > maxTabSize.width) {
            maxTabSize.width = tabSize.width;
        }
        if (tabSize.height > maxTabSize.height) {
            maxTabSize.height = tabSize.height;
        }
    }
    PtyLog(@"fitWindowToTabs - calling repositionWidgets");
    [self repositionWidgets];
    PtyLog(@"fitWindowToTabs - calling fitWindowToTabSize");
    [self fitWindowToTabSize:maxTabSize];
}

- (void)fitWindowToTabSize:(NSSize)tabSize
{
    if (_fullScreen) {
        [self fitTabsToWindow];
        return;
    }
    // Set the window size to be large enough to encompass that tab plus its decorations.
    NSSize decorationSize = [self windowDecorationSize];
    NSSize winSize = tabSize;
    winSize.width += decorationSize.width;
    winSize.height += decorationSize.height;
    NSRect frame = [[self window] frame];

    BOOL mustResizeTabs = NO;
    NSSize maxFrameSize = [self maxFrame].size;
    if (winSize.width > maxFrameSize.width ||
        winSize.height > maxFrameSize.height) {
        mustResizeTabs = YES;
    }
    winSize.width = MIN(winSize.width, maxFrameSize.width);
    winSize.height = MIN(winSize.height, maxFrameSize.height);

    CGFloat heightChange = winSize.height - [[self window] frame].size.height;
    frame.size = winSize;
    frame.origin.y -= heightChange;

    [[[self window] contentView] setAutoresizesSubviews:NO];
    if (windowType_ == WINDOW_TYPE_TOP) {
        frame.size.width = [[self window] frame].size.width;
        frame.origin.x = [[self window] frame].origin.x;
    }
    [[self window] setFrame:frame display:YES];
    [[[self window] contentView] setAutoresizesSubviews:YES];

    [self fitBottomBarToWindow];

    PtyLog(@"fitWindowToTabs - refresh textview");
    for (PTYSession* session in [[self currentTab] sessions]) {
        [[session TEXTVIEW] setNeedsDisplay:YES];
    }
    PtyLog(@"fitWindowToTabs - update tab bar");
    [tabBarControl update];
    PtyLog(@"fitWindowToTabs - return.");

    if (mustResizeTabs) {
        [self fitTabsToWindow];
    }
}

- (void)selectPaneLeft:(id)sender
{
    PTYSession* session = [[self currentTab] sessionLeftOf:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] setActiveSession:session];
    }
}

- (void)selectPaneRight:(id)sender
{
    PTYSession* session = [[self currentTab] sessionRightOf:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] setActiveSession:session];
    }
}

- (void)selectPaneUp:(id)sender
{
    PTYSession* session = [[self currentTab] sessionAbove:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] setActiveSession:session];
    }
}

- (void)selectPaneDown:(id)sender
{
    PTYSession* session = [[self currentTab] sessionBelow:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] setActiveSession:session];
    }
}

- (void)sessionWasRemoved
{
    // This works around an apparent bug in NSSplitView that causes dividers'
    // cursor rects to survive after the divider is gone.
    [[self window] resetCursorRects];
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermNumberOfSessionsDidChange" object: self userInfo: nil];
}

- (float)minWidth
{
    // Pick 400 as an absolute minimum just to be safe. This is rather arbitrary and hacky.
    float minWidth = 400;
    for (NSTabViewItem* tabViewItem in [TABVIEW tabViewItems]) {
        PTYTab* theTab = [tabViewItem identifier];
        minWidth = MAX(minWidth, [theTab minSize].width);
    }
    return minWidth;
}

- (BOOL)disableProgressIndicators
{
    return tempDisableProgressIndicators_;
}

- (void)appendTab:(PTYTab*)aTab
{
    [self insertTab:aTab atIndex:[TABVIEW numberOfTabViewItems]];
}

- (void)getSessionParameters:(NSMutableString *)command withName:(NSMutableString *)name
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

- (NSArray*)tabs
{
    int n = [TABVIEW numberOfTabViewItems];
    NSMutableArray *tabs = [NSMutableArray arrayWithCapacity:n];
    for (int i = 0; i < n; ++i) {
        NSTabViewItem* theItem = [TABVIEW tabViewItemAtIndex:i];
        [tabs addObject:[theItem identifier]];
    }
    return tabs;
}

- (BOOL)isHotKeyWindow
{
    return isHotKeyWindow_;
}

- (void)setIsHotKeyWindow:(BOOL)value
{
    isHotKeyWindow_ = value;
}

- (BOOL)isOrderedOut
{
    return isOrderedOut_;
}

- (void)setIsOrderedOut:(BOOL)value
{
    isOrderedOut_ = value;
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

- (void)_refreshTitle:(NSNotification*)aNotification
{
    // This is if displaying of window number was toggled in prefs.
    [self setWindowTitle];
}

- (void)_refreshTerminal:(NSNotification *)aNotification
{
    PtyLog(@"_refreshTerminal - calling fitWindowToTabs");
    [self fitWindowToTabs];

    BOOL canDim = [[PreferencePanel sharedInstance] dimInactiveSplitPanes];
    // Assign counts to each session. This causes tabs to show their tab number,
    // called an objectCount. When the "compact tab" pref is toggled, this makes
    // formerly countless tabs show their counts.
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYTab *aTab = [[TABVIEW tabViewItemAtIndex:i] identifier];
        [aTab setObjectCount:i+1];

        // Update dimmed status of inactive sessions in split panes in case the preference changed.
        for (PTYSession* aSession in [aTab sessions]) {
            if (canDim) {
                if (aSession != [aTab activeSession]) {
                    [[aSession view] setDimmed:YES];
                }
            } else {
                [[aSession view] setDimmed:NO];
            }
        }
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
    height = (aRect.size.height - VMARGIN * 2) / charHeight;
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
                       charHeight * height + VMARGIN * 2);                    // enough height for width rows
    [TABVIEW setFrame:aRect];
    PtyLog(@"adjustFullScreenWindowForBottomBarChange - call fitTabsToWindow");
    [self fitTabsToWindow];
    [self fitBottomBarToWindow];
}

- (void)fitBottomBarToWindow
{
    // Adjust the position of the bottom bar to fit properly below the tabview.
    NSRect bottomBarFrame = [bottomBar frame];
    bottomBarFrame.size.width = [TABVIEW frame].size.width;
    bottomBarFrame.origin.x = [TABVIEW frame].origin.x;
    [bottomBar setFrame: bottomBarFrame];

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
    if ([bottomBar isHidden] != hide) {
        [self showHideInstantReplay];
    }
}

- (BOOL)_haveLeftBorder
{
    if (![[PreferencePanel sharedInstance] showWindowBorder]) {
        return NO;
    } else if (_fullScreen || windowType_ == WINDOW_TYPE_TOP) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)_haveBottomBorder
{
    BOOL tabBarVisible = ([TABVIEW numberOfTabViewItems] > 1 ||
                          ![[PreferencePanel sharedInstance] hideTab]);
    BOOL topTabBar = ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab);
    if (![[PreferencePanel sharedInstance] showWindowBorder]) {
        return NO;
    } else if (_fullScreen || windowType_ == WINDOW_TYPE_TOP) {
        // Only normal windows can have a left border
        return NO;
    } else if (![bottomBar isHidden]) {
        // Bottom bar visible so no need for a lower border
        return NO;
    } else if (topTabBar) {
        // Nothing on the bottom, so need a border.
        return YES;
    } else if (!tabBarVisible) {
        // Invisible bottom tab bar
        return YES;
    } else {
        // Visible bottom tab bar
        return NO;
    }
}

- (BOOL)_haveRightBorder
{
    if (![[PreferencePanel sharedInstance] showWindowBorder]) {
        return NO;
    } else if (_fullScreen || windowType_ == WINDOW_TYPE_TOP) {
        return NO;
    } else if ([[PreferencePanel sharedInstance] hideScrollbar]) {
        // hidden scrollbar
        return YES;
    } else {
        // visible scrollbar
        return NO;
    }
}

- (NSSize)windowDecorationSize
{
    NSSize contentSize = NSZeroSize;

    if ([TABVIEW numberOfTabViewItems] + tabViewItemsBeingAdded > 1 ||
        ![[PreferencePanel sharedInstance] hideTab]) {
        contentSize.height += [tabBarControl frame].size.height;
    }
    if (![bottomBar isHidden]) {
        contentSize.height += [bottomBar frame].size.height;
    }

    // Add 1px border
    if ([self _haveLeftBorder]) {
        ++contentSize.width;
    }
    if ([self _haveRightBorder]) {
        ++contentSize.width;
    }
    if ([self _haveBottomBorder]) {
        ++contentSize.height;
    }

    return [[self window] frameRectForContentRect:NSMakeRect(0, 0, contentSize.width, contentSize.height)].size;
}

- (void)_setDisableProgressIndicators:(BOOL)value
{
    tempDisableProgressIndicators_ = value;
    for (NSTabViewItem* anItem in [TABVIEW tabViewItems]) {
        PTYTab* theTab = [anItem identifier];
        [theTab setIsProcessing:[theTab realIsProcessing]];
    }
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

    // This is a little hack because the progress indicators in the tabbar control crash if they
    // try to draw while fading.
    [self _setDisableProgressIndicators:YES];
    [self performSelector:@selector(enableProgressIndicators)
               withObject:nil
               afterDelay:[[NSAnimationContext currentContext] duration]];
}

- (void)enableProgressIndicators
{
    [self _setDisableProgressIndicators:NO];
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
    NSUInteger modifierFlags = [theEvent modifierFlags];
    if ((modifierFlags & NSDeviceIndependentModifierFlagsMask) == NSCommandKeyMask &&  // you pressed exactly cmd
        ([tabBarBackground isHidden] || [tabBarBackground alphaValue] == 0) &&  // the tab bar is not visible
        fullScreenTabviewTimer_ == nil) {  // not in the middle of doing this already
        fullScreenTabviewTimer_ = [[NSTimer scheduledTimerWithTimeInterval:[[PreferencePanel sharedInstance] fsTabDelay]
                                                                    target:self
                                                                  selector:@selector(cmdHeld:)
                                                                  userInfo:nil
                                                                    repeats:NO] retain];
    } else if ((modifierFlags & NSDeviceIndependentModifierFlagsMask) != NSCommandKeyMask &&
               fullScreenTabviewTimer_ != nil) {
        [fullScreenTabviewTimer_ invalidate];
        fullScreenTabviewTimer_ = nil;
    }

     // This hides the tabbar if you press any other key while it's already showing.
     // This breaks certain popular ways of switching tabs like cmd-shift-arrow or
     // cmd-shift-[ or ].
     // I can't remember why I added this. Let's take it out and if nobody complains
     // remove it for good. gn 2/12/2011.
     // if ((modifierFlags & NSDeviceIndependentModifierFlagsMask) != NSCommandKeyMask) {
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

- (void)repositionWidgets
{
    PtyLog(@"repositionWidgets");
    if (_fullScreen) {
        [self adjustFullScreenWindowForBottomBarChange];
        PtyLog(@"repositionWidgets returning because in full screen mode");
        return;
    }

    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
    NSWindow *thisWindow = [self window];
    [thisWindow setShowsResizeIndicator:hasScrollbar];
    if ([TABVIEW numberOfTabViewItems] == 1 &&
        [[PreferencePanel sharedInstance] hideTab]) {
        // The tabBarControl should not be visible.
        [tabBarControl setHidden:YES];
        NSRect aRect;
        aRect.origin.x = [self _haveLeftBorder] ? 1 : 0;
        aRect.origin.y = [self _haveBottomBorder] ? 1 : 0;
        if (![bottomBar isHidden]) {
            aRect.origin.y += [bottomBar frame].size.height;
        }
        aRect.size = [[thisWindow contentView] frame].size;
        aRect.size.height -= aRect.origin.y;
        aRect.size.width -= aRect.origin.x;
        aRect.size.width -= [self _haveRightBorder] ? 1 : 0;
        PtyLog(@"repositionWidgets - Set tab view size to %fx%f", aRect.size.width, aRect.size.height);
        [TABVIEW setFrame:aRect];
    } else {
        // The tabBar control is visible.
        PtyLog(@"repositionWidgets - tabs are visible. Adjusting window size...");
        [tabBarControl setHidden:NO];
        [tabBarControl setTabLocation:[[PreferencePanel sharedInstance] tabViewType]];
        NSRect aRect;
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            // Place tabs at the top.
            // Add 1px border
            aRect.origin.x = [self _haveLeftBorder] ? 1 : 0;
            aRect.origin.y = [self _haveBottomBorder] ? 1 : 0;
            aRect.size = [[thisWindow contentView] frame].size;
            if (![bottomBar isHidden]) {
                aRect.origin.y += [bottomBar frame].size.height;
            }
            aRect.size.height -= aRect.origin.y;
            aRect.size.height -= [tabBarControl frame].size.height;
            aRect.size.width -= aRect.origin.x;
            aRect.size.width -= [self _haveRightBorder] ? 1 : 0;
            PtyLog(@"repositionWidgets - Set tab view size to %fx%f", aRect.size.width, aRect.size.height);
            [TABVIEW setFrame:aRect];
            aRect.origin.y += aRect.size.height;
            aRect.size.height = [tabBarControl frame].size.height;
            [tabBarControl setFrame:aRect];
        } else {
            PtyLog(@"repositionWidgets - putting tabs at bottom");
            // setup aRect to make room for the tabs at the bottom.
            aRect.origin.x = [self _haveLeftBorder] ? 1 : 0;
            aRect.origin.y = [self _haveBottomBorder] ? 1 : 0;
            aRect.size = [[thisWindow contentView] frame].size;
            aRect.size.height = [tabBarControl frame].size.height;
            aRect.size.width -= aRect.origin.x;
            aRect.size.width -= [self _haveRightBorder] ? 1 : 0;
            if (![bottomBar isHidden]) {
                aRect.origin.y += [bottomBar frame].size.height;
            }
            [tabBarControl setFrame:aRect];
            aRect.origin.y += [tabBarControl frame].size.height;
            aRect.size.height = [[thisWindow contentView] frame].size.height - aRect.origin.y;
            PtyLog(@"repositionWidgets - Set tab view size to %fx%f", aRect.size.width, aRect.size.height);
            [TABVIEW setFrame:aRect];
        }
    }

    // Update the tab style.
    [self setTabBarStyle];

    [tabBarControl setDisableTabClose:[[PreferencePanel sharedInstance] useCompactLabel]];
    if ([[PreferencePanel sharedInstance] useCompactLabel]) {
        [tabBarControl setCellMinWidth:[[PreferencePanel sharedInstance] minCompactTabWidth]];
    } else {
        [tabBarControl setCellMinWidth:[[PreferencePanel sharedInstance] minTabWidth]];
    }
    [tabBarControl setSizeCellsToFit:[[PreferencePanel sharedInstance] useUnevenTabs]];
    [tabBarControl setCellOptimumWidth:[[PreferencePanel sharedInstance] optimumTabWidth]];

    PtyLog(@"repositionWidgets - call fitBottomBarToWindow");
    [self fitBottomBarToWindow];

    PtyLog(@"repositionWidgets - refresh textviews in this tab");
    for (PTYSession* session in [[self currentTab] sessions]) {
        [[session TEXTVIEW] setNeedsDisplay:YES];
    }

    PtyLog(@"repositionWidgets - update tab bar");
    [tabBarControl update];
    PtyLog(@"repositionWidgets - return.");
}

- (float)maxCharWidth:(int*)numChars
{
    float max=0;
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
            float w =[[session TEXTVIEW] charWidth];
            PtyLog(@"maxCharWidth - session %d has %dx%d, chars are %fx%f",
                   i, [session columns], [session rows], [[session TEXTVIEW] charWidth],
                   [[session TEXTVIEW] lineHeight]);
            if (w > max) {
                max = w;
                if (numChars) {
                    *numChars = [session columns];
                }
            }
        }
    }
    return max;
}

- (float)maxCharHeight:(int*)numChars
{
    float max=0;
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
            float h =[[session TEXTVIEW] lineHeight];
            PtyLog(@"maxCharHeight - session %d has %dx%d, chars are %fx%f", i, [session columns],
                   [session rows], [[session TEXTVIEW] charWidth], [[session TEXTVIEW] lineHeight]);
            if (h > max) {
                max = h;
                if (numChars) {
                    *numChars = [session rows];
                }
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
        for (PTYSession* session in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
            float w = [[session TEXTVIEW] charWidth];
            PtyLog(@"widestSessionWidth - session %d has %dx%d, chars are %fx%f", i,
                   [session columns], [session rows], [[session TEXTVIEW] charWidth],
                   [[session TEXTVIEW] lineHeight]);
            if (w * [session columns] > max) {
                max = w;
                ch = [[session TEXTVIEW] charWidth];
                *numChars = [session columns];
            }
        }
    }
    return ch;
}

- (float)tallestSessionHeight:(int*)numChars
{
    float max=0;
    float ch=0;
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
            float h = [[session TEXTVIEW] lineHeight];
            PtyLog(@"tallestSessionheight - session %d has %dx%d, chars are %fx%f", i, [session columns], [session rows], [[session TEXTVIEW] charWidth], [[session TEXTVIEW] lineHeight]);
            if (h * [session rows] > max) {
                max = h * [session rows];
                ch = [[session TEXTVIEW] lineHeight];
                *numChars = [session rows];
            }
        }
    }
    return ch;
}

- (void)copySettingsFrom:(PseudoTerminal*)other
{
    [bottomBar setHidden:YES];
    if (![other->bottomBar isHidden]) {
        [self showHideInstantReplay];
    }
    [bottomBar setHidden:[other->bottomBar isHidden]];
}

- (void)setupSession:(PTYSession *)aSession
               title:(NSString *)title
            withSize:(NSSize*)size
{
    NSDictionary *tempPrefs;

    PtyLog(@"%s(%d):-[PseudoTerminal setupSession]",
          __FILE__, __LINE__);

    NSParameterAssert(aSession != nil);

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
    if (nextSessionRows_) {
        rows = nextSessionRows_;
        nextSessionRows_ = 0;
    }
    if (nextSessionColumns_) {
        columns = nextSessionColumns_;
        nextSessionColumns_ = 0;
    }
    // rows, columns are set to the bookmark defaults. Make sure they'll fit.

    NSSize charSize = [PTYTextView charSizeForFont:[ITAddressBookMgr fontWithDesc:[tempPrefs objectForKey:KEY_NORMAL_FONT]]
                                 horizontalSpacing:[[tempPrefs objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                   verticalSpacing:[[tempPrefs objectForKey:KEY_VERTICAL_SPACING] floatValue]];

    if (windowType_ == WINDOW_TYPE_TOP) {
        NSRect windowFrame = [[self window] frame];
        BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
        NSSize contentSize = [PTYScrollView contentSizeForFrameSize:windowFrame.size
                                              hasHorizontalScroller:NO
                                                hasVerticalScroller:hasScrollbar
                                                         borderType:NSNoBorder];
        
        columns = (contentSize.width - MARGIN*2) / charSize.width;
    }
    if (size == nil && [TABVIEW numberOfTabViewItems] != 0) {
        NSSize contentSize = [[[self currentSession] SCROLLVIEW] documentVisibleRect].size;
        rows = (contentSize.height - VMARGIN*2) / charSize.height;
        columns = (contentSize.width - MARGIN*2) / charSize.width;
    }
    NSRect sessionRect;
    if (size != nil) {
        BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
        NSSize contentSize = [PTYScrollView contentSizeForFrameSize:*size
                                              hasHorizontalScroller:NO
                                                hasVerticalScroller:hasScrollbar
                                                         borderType:NSNoBorder];
        rows = (contentSize.height - VMARGIN*2) / charSize.height;
        columns = (contentSize.width - MARGIN*2) / charSize.width;
        sessionRect.origin = NSZeroPoint;
        sessionRect.size = *size;
    } else {
        sessionRect = NSMakeRect(0, 0, columns * charSize.width + MARGIN * 2, rows * charSize.height + VMARGIN * 2);
    }

    if ([aSession setScreenSize:sessionRect parent:self]) {
        PtyLog(@"setupSession - call safelySetSessionSize");
        [self safelySetSessionSize:aSession rows:rows columns:columns];
        PtyLog(@"setupSession - call setPreferencesFromAddressBookEntry");
        [aSession setPreferencesFromAddressBookEntry:tempPrefs];
        [aSession setBookmarkName:[tempPrefs objectForKey:KEY_NAME]];
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

// Set the session to a size that fits on the screen.
- (void)safelySetSessionSize:(PTYSession*)aSession rows:(int)rows columns:(int)columns
{
    PtyLog(@"safelySetSessionSize");
    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
    if (windowType_ == WINDOW_TYPE_NORMAL) {
        int width = columns;
        int height = rows;
        if (width < 20) {
            width = 20;
        }
        if (height < 2) {
            height = 2;
        }

        // With split panes it is very difficult to directly compute the maximum size of any
        // given pane. However, any growth in a pane can be taken up by the window as a whole.
        // We compute the maximum amount the window can grow and ensure that the rows and columns
        // won't cause the window to exceed the max size.

        // 1. Figure out how big the tabview can get assuming window decoration remains unchanged.
        NSSize maxFrame = [self maxFrame].size;
        NSSize decoration = [self windowDecorationSize];
        NSSize maxTabSize;
        maxTabSize.width = maxFrame.width - decoration.width;
        maxTabSize.height = maxFrame.height - decoration.height;

        // 2. Figure out how much the window could grow by in rows and columns.
        NSSize currentSize = [TABVIEW frame].size;
        if ([TABVIEW numberOfTabViewItems] == 0) {
            currentSize = NSZeroSize;
        }
        NSSize maxGrowth;
        maxGrowth.width = maxTabSize.width - currentSize.width;
        maxGrowth.height = maxTabSize.height - currentSize.height;
        int maxNewCols = maxGrowth.width / [[aSession TEXTVIEW] charWidth];
        int maxNewRows = maxGrowth.height / [[aSession TEXTVIEW] lineHeight];

        // 3. Compute the number of rows and columns we're trying to grow by.
        int newRows = rows - [aSession rows];
        int newCols = columns - [aSession columns];

        // 4. Cap growth if it exceeds the maximum. Do nothing if it's shrinking.
        if (newRows > maxNewRows) {
            int error = newRows - maxNewRows;
            height -= error;
        }
        if (newCols > maxNewCols) {
            int error = newCols - maxNewCols;
            width -= error;
        }

        PtyLog(@"safelySetSessionSize - set to %dx%d", width, height);
        [aSession setWidth:width height:height];
        [[aSession SCROLLVIEW] setHasVerticalScroller:hasScrollbar];
        [[aSession SCROLLVIEW] setLineScroll:[[aSession TEXTVIEW] lineHeight]];
        [[aSession SCROLLVIEW] setPageScroll:2*[[aSession TEXTVIEW] lineHeight]];
        if ([aSession backgroundImagePath]) {
            [aSession setBackgroundImagePath:[aSession backgroundImagePath]];
        }
    }
}

- (void)fitTabToWindow:(PTYTab*)aTab
{
    NSSize size = [TABVIEW contentRect].size;
    PtyLog(@"fitTabToWindow calling setSize for content size of height %lf", size.height);
    [aTab setSize:size];
}

- (void)insertTab:(PTYTab*)aTab atIndex:(int)anIndex
{
    PtyLog(@"insertTab:atIndex:%d", anIndex);
    assert(aTab);
    if ([TABVIEW indexOfTabViewItemWithIdentifier:aTab] == NSNotFound) {
        for (PTYSession* aSession in [aTab sessions]) {
            [aSession setIgnoreResizeNotifications:YES];
        }
        NSTabViewItem* aTabViewItem = [[NSTabViewItem alloc] initWithIdentifier:aTab];
        [aTabViewItem setLabel:@""];
        assert(aTabViewItem);
        [aTab setTabViewItem:aTabViewItem];
        PtyLog(@"insertTab:atIndex - calling [TABVIEW insertTabViewItem:atIndex]");
        [TABVIEW insertTabViewItem:aTabViewItem atIndex:anIndex];
        [aTabViewItem release];
        [TABVIEW selectTabViewItemAtIndex:anIndex];
        if ([self windowInited] && !_fullScreen) {
            [[self window] makeKeyAndOrderFront:self];
        }
        [[iTermController sharedInstance] setCurrentTerminal:self];
    }
}

- (void)insertSession:(PTYSession *)aSession atIndex:(int)anIndex
{
    PtyLog(@"%s(%d):-[PseudoTerminal insertSession: 0x%x atIndex: %d]",
           __FILE__, __LINE__, aSession, index);

    if (aSession == nil) {
        return;
    }

    if ([[self allSessions] indexOfObject:aSession] == NSNotFound) {
        // create a new tab
        PTYTab* aTab = [[PTYTab alloc] initWithSession:aSession];
        [aSession setIgnoreResizeNotifications:YES];
        [self insertTab:aTab atIndex:anIndex];
        [aTab release];
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
    PTYTab* oldTab = [aTabViewItem identifier];
    [oldTab setTabViewItem:nil];

    // Replace the session for the tab view item.
    PTYTab* newTab = [[PTYTab alloc] initWithSession:aSession];
    [tabBarControl changeIdentifier:newTab atIndex:anIndex];
    [newTab setTabViewItem:aTabViewItem];

    // Set other tabviewitem attributes to match the new session.
    [TABVIEW selectTabViewItemAtIndex:anIndex];

    // Bring the window to the fore.
    [self fitWindowToTabs];
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

- (void)setName:(NSString *)theSessionName forSession:(PTYSession*)aSession
{
    if (theSessionName != nil) {
        [aSession setDefaultName:theSessionName];
        [aSession setName:theSessionName];
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

        [aSession setName:title];
        [aSession setDefaultName:title];
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
           inSession:(PTYSession*)theSession
      asLoginSession:(BOOL)asLoginSession
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal startProgram:%@ arguments:%@]",
          __FILE__, __LINE__, program, prog_argv );
#endif
    [theSession startProgram:program
                   arguments:prog_argv
                 environment:prog_env
                      isUTF8:isUTF8
              asLoginSession:asLoginSession];

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
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                        object:[self currentSession]];
}

- (IBAction)logStop:(id)sender
{
    if ([[self currentSession] logging]) {
        [[self currentSession] logStop];
    }
    // send a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                        object:[self currentSession]];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    BOOL logging = [[self currentSession] logging];
    BOOL result = YES;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal validateMenuItem:%@]",
          __FILE__, __LINE__, item );
#endif

    if ([item action] == @selector(jumpToSavedScrollPosition:)) {
        result = [self hasSavedScrollPosition];
    } else if ([item action] == @selector(logStart:)) {
        result = logging == YES ? NO : YES;
    } else if ([item action] == @selector(logStop:)) {
        result = logging == NO ? NO : YES;
    } else if ([item action] == @selector(irPrev:)) {
        result = [[self currentSession] canInstantReplayPrev];
    } else if ([item action] == @selector(irNext:)) {
        result = [[self currentSession] canInstantReplayNext];
    } else if ([item action] == @selector(selectPaneUp:) ||
               [item action] == @selector(selectPaneDown:) ||
               [item action] == @selector(selectPaneLeft:) ||
               [item action] == @selector(selectPaneRight:)) {
        result = ([[[self currentTab] sessions] count] > 1);
    } else if ([item action] == @selector(closecurrentsession:)) {
        NSWindowController* controller = [[NSApp keyWindow] windowController];
        if (controller) {
            // Any object whose window controller implements this selector is closed by
            // cmd-w: pseudoterminal (closes a pane), preferences, bookmarks
            // window. Notably, not expose, various modal windows, etc.
            result = [controller respondsToSelector:@selector(closecurrentsession:)];
        } else {
            result = NO;
        }
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
        NSColor* tabColor = [tabBarControl tabColorForTabViewItem:[TABVIEW selectedTabViewItem]];
        if (tabColor) {
            [[self window] setBackgroundColor:tabColor];
            [background_ setColor:tabColor];
        } else {
            [[self window] setBackgroundColor:nil];
            [background_ setColor:normalBackgroundColor];
        }
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

- (void)fitTabsToWindow
{
    PtyLog(@"fitTabsToWindow begins");
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        [self fitTabToWindow:[[TABVIEW tabViewItemAtIndex:i] identifier]];
    }
    PtyLog(@"fitTabsToWindow returns");
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
    [self closeTab:[[sender representedObject] identifier]];
}

// moves a tab with its session to a new window
- (void)moveTabToNewWindowContextualMenuAction:(id)sender
{
    PseudoTerminal *term;
    NSTabViewItem *aTabViewItem = [sender representedObject];
    PTYTab *aTab = [aTabViewItem identifier];

    if (aTab == nil) {
        return;
    }

    // create a new terminal window
    term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                             windowType:WINDOW_TYPE_NORMAL
                                                 screen:-1] autorelease];
    if (term == nil) {
        return;
    }

    [[iTermController sharedInstance] addInTerminals: term];


    // temporarily retain the tabViewItem
    [aTabViewItem retain];

    // remove from our window
    [TABVIEW removeTabViewItem:aTabViewItem];

    // add the session to the new terminal
    [term insertTab:aTab atIndex: 0];
    PtyLog(@"moveTabToNewWindowContextMenuAction - call fitWindowToTabs");
    [term fitWindowToTabs];

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
    for (PTYSession* session in [self allSessions]) {
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
            // The test can have false positives but it should be harmless.
            [session setPreferencesFromAddressBookEntry:newBookmark];
            [session setAddressBookEntry:newBookmark];
            [[session tab] recheckBlur];
            if (![[newBookmark objectForKey:KEY_NAME] isEqualToString:oldName]) {
                // Set name, which overrides any session-set icon name.
                [session setName:[newBookmark objectForKey:KEY_NAME]];
                // set default name, which will appear as a prefix if the session changes the name.
                [session setDefaultName:[newBookmark objectForKey:KEY_NAME]];
            }
        }
        [oldName release];
    }
}

- (IBAction)parameterPanelEnd:(id)sender
{
    [NSApp stopModal];
}

- (long long)timestampForFraction:(float)f
{
    DVR* dvr = [[self currentSession] dvr];
    long long range = [dvr lastTimeStamp] - [dvr firstTimeStamp];
    long long offset = range * f;
    return [dvr firstTimeStamp] + offset;
}

- (NSArray*)allSessions
{
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:[TABVIEW numberOfTabViewItems]];
    for (NSTabViewItem* item in [TABVIEW tabViewItems]) {
        [result addObjectsFromArray:[[item identifier] sessions]];
    }
    return result;
}

- (PTYSession*)newSessionWithBookmark:(Bookmark*)bookmark
{
    assert(bookmark);
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] init];

    [[aSession SCREEN] setUnlimitedScrollback:[[bookmark objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession SCREEN] setScrollback:[[bookmark objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    // set our preferences
    [aSession setAddressBookEntry:bookmark];
    return [aSession autorelease];
}

// Used when adding a split pane.
- (void)runCommandInSession:(PTYSession*)aSession inCwd:(NSString*)oldCWD;
{
    if ([aSession SCREEN]) {
        NSMutableString *cmd, *name;
        NSArray *arg;
        NSString *pwd;
        BOOL isUTF8;
        // Grab the addressbook command
        Bookmark* addressbookEntry = [aSession addressBookEntry];
        BOOL loginSession;
        cmd = [[[NSMutableString alloc] initWithString:[ITAddressBookMgr bookmarkCommand:addressbookEntry isLoginSession:&loginSession]] autorelease];
        name = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey:KEY_NAME]] autorelease];
        // Get session parameters
        [self getSessionParameters:cmd withName:name];

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
        [self setName:name forSession:aSession];
        // Start the command
        [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8 inSession:aSession asLoginSession:loginSession];
    }
}

- (void)_loadFindStringFromSharedPasteboard
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermLoadFindStringFromSharedPasteboard"
                                                        object:nil
                                                      userInfo:nil];    
}

@end


@implementation PseudoTerminal (KeyValueCoding)

-(int)columns
{
    return [[self currentSession] columns];
}

-(void)setColumns:(int)columns
{
    if (![self currentSession]) {
        nextSessionColumns_ = columns;
    } else {
        [self sessionInitiatedResize:[self currentSession]
                               width:columns
                              height:[[self currentSession] rows]];
    }
}

-(int)rows
{
    return [[self currentSession] rows];
}

-(void)setRows:(int)rows
{
    if (![self currentSession]) {
        nextSessionRows_ = rows;
    } else {
        [self sessionInitiatedResize:[self currentSession]
                              width:[[self currentSession] columns]
                              height:rows];
    }
}

-(id)addNewSession:(NSDictionary *)addressbookEntry
{
    NSAssert(addressbookEntry, @"Null address book entry");
    // NSLog(@"PseudoTerminal: -addInSessions: 0x%x", object);
    PTYSession *aSession;
    NSString *oldCWD = nil;

    /* Get active session's directory */
    if ([self currentSession]) {
        oldCWD = [[[self currentSession] SHELL] getWorkingDirectory];
    }

    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession SCREEN] setUnlimitedScrollback:[[addressbookEntry objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession SCREEN] setScrollback:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    // set our preferences
    [aSession setAddressBookEntry:addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession:aSession];
    if ([aSession SCREEN]) {
        [aSession runCommandWithOldCwd:oldCWD];
        if ([[[self window] title] compare:@"Window"] == NSOrderedSame) {
            [self setWindowTitle];
        }
    }

    if ([self numberOfTabs] == 1 &&
        [addressbookEntry objectForKey:KEY_SPACE] &&
        [[addressbookEntry objectForKey:KEY_SPACE] intValue] == -1) {
        [[self window] setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
    }

    [aSession release];
    return aSession;
}


// accessors for to-many relationships:
// (See NSScriptKeyValueCoding.h)
-(id)valueInSessionsAtIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -valueInSessionsAtIndex: %d", anIndex);
    return [[self sessions] objectAtIndex:anIndex];
}

-(NSArray*)sessions
{
    int n = [TABVIEW numberOfTabViewItems];
    NSMutableArray *sessions = [NSMutableArray arrayWithCapacity:n];
    int i;

    for (i = 0; i < n; ++i) {
        for (PTYSession* aSession in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
            [sessions addObject:aSession];
        }
    }

    return sessions;
}

-(void)setSessions: (NSArray*)sessions
{
}

-(id)valueWithName: (NSString *)uniqueName inPropertyWithKey: (NSString*)propertyKey
{
    id result = nil;
    int i;

    // TODO: if (... == YES) => if (...)
    if ([propertyKey isEqualToString: sessionsKey] == YES) {
        PTYSession *aSession;

        for (i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
            aSession = [[[TABVIEW tabViewItemAtIndex:i] identifier] activeSession];
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
            aSession = [[[TABVIEW tabViewItemAtIndex:i] identifier] activeSession];
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
    [[aSession SCREEN] setUnlimitedScrollback:[[addressbookEntry objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession SCREEN] setScrollback:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    // set our preferences
    [aSession setAddressBookEntry: addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession: aSession];
    if ([aSession SCREEN]) {
        // We process the cmd to insert URL parts
        BOOL loginSession;
        NSMutableString *cmd = [[[NSMutableString alloc] initWithString:[ITAddressBookMgr bookmarkCommand:addressbookEntry
                                                                                           isLoginSession:&loginSession]] autorelease];
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
        [self getSessionParameters:cmd withName:name];

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

        [self setName:name forSession:aSession];

        // Start the command
        [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8 inSession:aSession asLoginSession:loginSession];
    }
    [aSession release];
    return aSession;
}

-(id)addNewSession:(NSDictionary *)addressbookEntry withCommand:(NSString *)command asLoginSession:(BOOL)loginSession
{
    PtyLog(@"PseudoTerminal: addNewSession 2");
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession SCREEN] setUnlimitedScrollback:[[addressbookEntry objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
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
        [self getSessionParameters:cmd withName:name];

        [PseudoTerminal breakDown:cmd cmdPath:&cmd cmdArgs:&arg];

        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry];
        if ([pwd length] == 0) {
            pwd = NSHomeDirectory();
        }
        NSDictionary *env =[NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        isUTF8 = ([[addressbookEntry objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue] == NSUTF8StringEncoding);

        [self setName:name forSession:aSession];

        // Start the command
        [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8 inSession:aSession asLoginSession:loginSession];
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
    [self setupSession:object title:nil withSize:nil];
    tabViewItemsBeingAdded--;
    if ([object SCREEN]) {  // screen initialized ok
        [self insertSession:object atIndex:[TABVIEW numberOfTabViewItems]];
    }
}

-(void)replaceInSessions:(PTYSession *)object atIndex:(unsigned)anIndex
{
    PtyLog(@"PseudoTerminal: -replaceInSessions: 0x%x atIndex: %d", object, anIndex);
    // TODO: Test this
    [self setupSession:object title:nil withSize:nil];
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
    // TODO: test this
    [self setupSession:object title:nil withSize:nil];
    if ([object SCREEN]) {  // screen initialized ok
        [self insertSession:object atIndex:anIndex];
    }
}

-(void)removeFromSessionsAtIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -removeFromSessionsAtIndex: %d", anIndex);
    if (anIndex < [TABVIEW numberOfTabViewItems]) {
        PTYSession *aSession = [[[TABVIEW tabViewItemAtIndex:anIndex] identifier] activeSession];
        [self closeSession:aSession];
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
        int windowType = [abEntry objectForKey:KEY_WINDOW_TYPE] ? [[abEntry objectForKey:KEY_WINDOW_TYPE] intValue] : WINDOW_TYPE_NORMAL;
        if (windowType == WINDOW_TYPE_FULL_SCREEN) {
            windowType = WINDOW_TYPE_NORMAL;
            // TODO: this should work with fullscreen
        }
        [iTermController switchToSpaceInBookmark:abEntry];
        [self initWithSmartLayout:NO 
                       windowType:windowType
                           screen:-1];
    }

    // launch the session!
    id rv = [[iTermController sharedInstance] launchBookmark:abEntry
                                                 inTerminal:self];
    return rv;
}

@end


