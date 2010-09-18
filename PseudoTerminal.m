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
#import <iTerm/VT100Terminal.h>
#import <iTerm/VT100Screen.h>
#import <iTerm/PTYSession.h>
#import <iTerm/PTToolbarController.h>
#import <iTerm/FindCommandHandler.h>
#import <iTerm/ITAddressBookMgr.h>
#import <PSMTabBarControl.h>
#import <PSMTabStyle.h>
#import <iTerm/iTermGrowlDelegate.h>
#include <unistd.h>

#define CACHED_WINDOW_POSITIONS 100
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

@implementation FindBarView
- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor controlColor] setFill];
    NSRectFill(dirtyRect);
}

@end

@implementation PseudoTerminal

- (id)initWithSmartLayout:(BOOL)smartLayout fullScreen:(NSScreen*)fullScreen
{
    unsigned int styleMask;
    PTYWindow *myWindow;

    self = [super initWithWindowNibName:@"PseudoTerminal"];
    if (self == nil) {
        return nil;
    }

    // Force the nib to load
    [self window];
    [commandField retain];
    [commandField setDelegate:self];
    [findBar retain];

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
    myWindow = [[PTYWindow alloc] initWithContentRect:[screen frame]
                                            styleMask:fullScreen ? NSBorderlessWindowMask : styleMask 
                                              backing:NSBackingStoreBuffered 
                                                defer:NO];
    [self setWindow:myWindow];
    [myWindow release];

    _fullScreen = (fullScreen != nil);
    previousFindString = [[NSMutableString alloc] init];
    if (fullScreen) {
        [[self window] setBackgroundColor:[NSColor blackColor]];
        [[self window] setAlphaValue:1];
    } else {
        [[self window] setAlphaValue:0.9999];
    }
    normalBackgroundColor = [[self window] backgroundColor];

#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif

    _resizeInProgressFlag = NO;

    if (smartLayout) {
        [(PTYWindow*)[self window] setLayoutDone];
    }

    if (!_fullScreen) {
        _toolbarController = [[PTToolbarController alloc] initWithPseudoTerminal:self];
        if ([[self window] respondsToSelector:@selector(setBottomCornerRounded:)])
            [[self window] setBottomCornerRounded:NO];
    }

    // create the tab bar control
    NSRect aRect = [[[self window] contentView] bounds];
    aRect.size.height = 22;
    tabBarControl = [[PSMTabBarControl alloc] initWithFrame:aRect];
    [tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [[[self window] contentView] addSubview:tabBarControl];
    [tabBarControl release];    

    // Set up findbar    
    NSRect fbFrame = [findBarSubview frame];
    findBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, fbFrame.size.width, fbFrame.size.height)];
    [findBar addSubview:findBarSubview];
    [findBar setHidden:YES];

    [findBarTextField setDelegate:self];

    // create the tabview
    aRect = [[[self window] contentView] bounds];
    if (![findBar isHidden]) {
        aRect.size.height -= [findBar frame].size.height;
    }
    TABVIEW = [[PTYTabView alloc] initWithFrame: aRect];
    [TABVIEW setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable];
    [TABVIEW setAutoresizesSubviews: YES];
    [TABVIEW setAllowsTruncatedLabels: NO];
    [TABVIEW setControlSize: NSSmallControlSize];
    [TABVIEW setTabViewType: NSNoTabsNoBorder];
    // Add to the window
    [[[self window] contentView] addSubview: TABVIEW];
    [TABVIEW release];

    [[[self window] contentView] addSubview: findBar];

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
    [findBar release];
    [_toolbarController release];
    if (_timer) {
        [_timer invalidate];
        [findProgressIndicator setHidden:YES];
        _timer = nil;
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

    [[self window] setTitle: title];
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
        // Close the findbar because otherwise the wrong size
        // frame is saved.  You wouldn't want the findbar to
        // open automatically anyway.
        if (![findBar isHidden]) {
            [self showHideFindBar];
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
    [[[self currentSession] TEXTVIEW] updateDirtyRects];
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidResignKey:%@]",
          __FILE__, __LINE__, aNotification);
#endif

    //[self windowDidResignMain: aNotification];

    if (_fullScreen) { 
        [NSMenu setMenuBarVisible:YES];
    } else {
        // update the cursor
        [[[self currentSession] TEXTVIEW] updateDirtyRects];
    }
}

- (void)windowDidResignMain:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidResignMain:%@]",
          __FILE__, __LINE__, aNotification);
#endif
    if (_fullScreen) {
        [self toggleFullScreen:nil];
    }
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowWillResize: proposedFrameSize width = %f; height = %f]",
          __FILE__, __LINE__, proposedFrameSize.width, proposedFrameSize.height);
#endif
    if (sender!=[self window]) {
        NSLog(@"Aha!");
        return proposedFrameSize;
    }

    //NSLog(@"Proposed size: %fx%f", proposedFrameSize.height, proposedFrameSize.width);
    float northChange = [sender frame].size.height - 
        [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.height;
    float westChange = [sender frame].size.width - 
        [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.width;
    //NSLog(@"Change change: %f,%f", northChange, westChange);
    float charHeight = [self maxCharHeight:nil];
    float charWidth = [self maxCharWidth:nil];
    //NSLog(@"charSize=%fx%f", charHeight, charWidth);
    int old_height = (proposedFrameSize.height - northChange) / charHeight + 0.5;
    int old_width = (proposedFrameSize.width - westChange - MARGIN*2) / charWidth + 0.5;
    if (old_height < 2) {
        old_height = 2;
    }
    if (old_width < 20) {
        old_width = 20;
    }
    proposedFrameSize.height = charHeight * old_height + northChange;
    proposedFrameSize.width = charWidth * old_width + westChange + MARGIN * 2;
    //int h = proposedFrameSize.height / charHeight;
    //int w = proposedFrameSize.width / charWidth;
    //NSLog(@"New height x width is %dx%d", h, w);
    //NSLog(@"Accepted size: %fx%f", proposedFrameSize.height, proposedFrameSize.width);

    return proposedFrameSize;
}

- (void)windowDidResize:(NSNotification *)aNotification
{
    NSRect frame;


#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidResize: width = %f, height = %f]",
          __FILE__, __LINE__, [[self window] frame].size.width, [[self window] frame].size.height);
#endif

    frame = [[[self currentSession] SCROLLVIEW] documentVisibleRect];
#if 0
    NSLog(@"scrollview content size %.1f, %.1f, %.1f, %.1f",
          frame.origin.x, frame.origin.y,
          frame.size.width, frame.size.height);
#endif

    // Display the new size in the window title.
    // TODO(georgen): Maybe do this only if the size actually changed
    PTYSession* session = [self currentSession];
    NSString *aTitle = [NSString stringWithFormat:@"%@ (%d,%d)", 
                        [self currentSessionName], 
                        [session columns], 
                        [session rows]];
    [self setWindowTitle: aTitle];
    tempTitle = YES;
    [self fitSessionsToWindow];

    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermWindowDidResize" object: self userInfo: nil];    
}

// PTYWindowDelegateProtocol
- (void)windowWillToggleToolbarVisibility:(id)sender
{
}

- (void)windowDidToggleToolbarVisibility:(id)sender
{
    [self fitWindowToSessions];
}

// Bookmarks
- (IBAction)toggleFullScreen:(id)sender
{
    PseudoTerminal *newTerminal;
    if (!_fullScreen) {
        NSScreen *currentScreen = [[[[iTermController sharedInstance] currentTerminal] window]screen];
        newTerminal = [[PseudoTerminal alloc] initWithSmartLayout:NO fullScreen:currentScreen];
        newTerminal->oldFrame_ = [[self window] frame];
    } else {
        newTerminal = [[PseudoTerminal alloc] initWithSmartLayout:NO fullScreen:nil];
    }

    _fullScreen = !_fullScreen;

    // Save the current session so it can be made current after moving
    // tabs over to the new window.
    PTYSession *currentSession = [self currentSession];

    [newTerminal copySettingsFrom:self];
    [[[newTerminal window] contentView] lockFocus];
    [[NSColor blackColor] set];
    NSRectFill([[newTerminal window] frame]);
    [[[newTerminal window] contentView] unlockFocus];

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
        [TABVIEW removeTabViewItem:aTabViewItem];

        // add the session to the new terminal
        [newTerminal insertSession:aSession atIndex:i];

        // release the tabViewItem
        [aTabViewItem release];
    }
    newTerminal->_resizeInProgressFlag = NO;
    [[newTerminal tabView] selectTabViewItemWithIdentifier:currentSession];
    BOOL fs = _fullScreen;
    [[self window] close];
    if (!fs) {
        [[newTerminal window] setFrame:oldFrame_ display:YES];
        [NSMenu setMenuBarVisible:YES];
    } else {
        [newTerminal adjustFullScreenWindowForFindBarChange];
        [newTerminal hideMenuBar];
    }
    [newTerminal fitSessionsToWindow];
    [newTerminal fitWindowToSessions];
    [newTerminal setWindowTitle];
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
    float nch = [sender frame].size.height - 
        [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.height;
    float wch = [sender frame].size.width - 
        [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.width;

    defaultFrame.origin.x = [sender frame].origin.x;
    float charHeight = [self maxCharHeight:nil];
    float charWidth = [self maxCharWidth:nil];
    int new_height = (defaultFrame.size.height - nch) / charHeight;
    int new_width = (defaultFrame.size.width - wch - MARGIN * 2) /charWidth;

    defaultFrame.size.height = charHeight * new_height + nch;
    defaultFrame.origin.y = [sender frame].size.height;
    BOOL verticalOnly = NO;

    if ([[PreferencePanel sharedInstance] maxVertically] &&
        !([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask)) {
        verticalOnly = YES;
    }

    defaultFrame.size.width = (verticalOnly ? [sender frame].size.width : new_width*charWidth+wch+MARGIN*2);
    //NSLog(@"actual width: %f, height: %f",defaultFrame.size.width,defaultFrame.size.height);

    return defaultFrame;
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
    // ignore resize request when we are in full screen mode.
    if (_fullScreen) {
        return;
    }

    [self safelySetSessionSize:session rows:height columns:width];
    [self fitWindowToSession:session];
    [self fitSessionsToWindow];
}

- (void)resizeWindowToPixelsWidth:(int)w height:(int)h
{
    // ignore resize request when we are in full screen mode.
    if (_fullScreen) {
        return;
    }

    NSRect frm = [[self window] frame];
    float rh = frm.size.height - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.height;
    float rw = frm.size.width - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.width;

    frm.origin.y += frm.size.height;
    if (!h) {
        h = [[[self window] screen] frame].size.height - rh;
    }

    float charHeight = [self maxCharHeight:nil];
    float charWidth = [self maxCharWidth:nil];

    int n = (h) / charHeight + 0.5;
    frm.size.height = n*charHeight + rh;

    if (!w) {
        w = [[[self window] screen] frame].size.width - rw;
    }
    n = (w - MARGIN*2) / charWidth + 0.5;
    frm.size.width = n*charWidth + rw + MARGIN*2;

    frm.origin.y -= frm.size.height; //keep the top left point the same

    [[self window] setFrame:frm display:NO];
    [self windowDidResize:nil];
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
    NSString* guid = [bookmark objectForKey:KEY_GUID];
    [[BookmarkModel sessionsInstance] removeBookmarkWithGuid:guid];
    [[BookmarkModel sessionsInstance] addBookmark:bookmark];

    // Change the GUID so that this session can follow a different path in life
    // than its bookmark. Changes to the bookmark will no longer affect this
    // session, and changes to this session won't affect its originating bookmark
    // (which may not evene exist any longer).
    guid = [BookmarkModel newGuid];
    [[BookmarkModel sessionsInstance] setObject:guid
                                         forKey:KEY_GUID 
                                     inBookmark:bookmark];
    [session setAddressBookEntry:[[BookmarkModel sessionsInstance] bookmarkWithGuid:guid]];
    [[PreferencePanel sessionsInstance] openToBookmark:guid];
}

- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu
{
    // Constructs the context menu for right-clicking on a terminal when
    // right click does not paste.
    unsigned int modflag = 0;
    int nextIndex;
    NSMenuItem *aMenuItem;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal menuForEvent]", __FILE__, __LINE__);
#endif

    if (theMenu == nil) {
        return;
    }

    modflag = [theEvent modifierFlags];

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
    [[[tabViewItem identifier] TEXTVIEW] setNeedsDisplay: YES];
    if (_fullScreen) {
        [[[self window] contentView] lockFocus];
        [[NSColor blackColor] set];
        NSRectFill([[self window] frame]);
        [[[self window] contentView] unlockFocus];
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

    // Post notifications
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermSessionBecameKey" object: [tabViewItem identifier]];    
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
    [[aSession SHELL] setWidth:[aSession columns]  height:[aSession rows]];
    if ([[term tabView] numberOfTabViewItems] == 1) {
        [term fitWindowToSessions];
    }

    int i;
    for (i=0; i < [aTabView numberOfTabViewItems]; ++i) {
        PTYSession *currentSession = [[aTabView tabViewItemAtIndex:i] identifier];
        [currentSession setObjectCount:i+1];
    }        
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
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabViewDidChangeNumberOfTabViewItems]", __FILE__, __LINE__);
#endif

    // check window size in case tabs have to be hidden or shown
    if (([TABVIEW numberOfTabViewItems] == 1) || ([[PreferencePanel sharedInstance] hideTab] && 
        ([TABVIEW numberOfTabViewItems] > 1 && [tabBarControl isHidden]))) {
        [self fitWindowToSessions];      
    }

    int i;
    for (i=0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYSession *aSession = [[TABVIEW tabViewItemAtIndex: i] identifier];
        [aSession setObjectCount:i+1];
    }        

    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermNumberOfSessionsDidChange" object: self userInfo: nil];        
}

- (NSMenu *)tabView:(NSTabView *)aTabView menuForTabViewItem:(NSTabViewItem *)tabViewItem
{
    NSMenuItem *aMenuItem;
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabViewContextualMenu]", __FILE__, __LINE__);
#endif    

    NSMenu *theMenu = [[[NSMenu alloc] init] autorelease];

    // Create a menu with a submenu to navigate between tabs if there are more than one
    if ([TABVIEW numberOfTabViewItems] > 1) {    
        int nextIndex = 0;
        int i;

        [theMenu insertItemWithTitle: NSLocalizedStringFromTableInBundle(@"Select",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu") action:nil keyEquivalent:@"" atIndex: nextIndex];
        NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@""];

        for (i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
            aMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ #%d", [[TABVIEW tabViewItemAtIndex: i] label], i+1]
                                                   action:@selector(selectTab:) keyEquivalent:@""];
            [aMenuItem setRepresentedObject: [[TABVIEW tabViewItemAtIndex: i] identifier]];
            [aMenuItem setTarget: TABVIEW];
            [tabMenu addItem: aMenuItem];
            [aMenuItem release];
        }
        [theMenu setSubmenu: tabMenu forItem: [theMenu itemAtIndex: nextIndex]];
        [tabMenu release];
        ++nextIndex;
        [theMenu addItem: [NSMenuItem separatorItem]];
   }

    // add tasks
    aMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Close Tab",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context Menu") action:@selector(closeTabContextualMenuAction:) keyEquivalent:@""];
    [aMenuItem setRepresentedObject: tabViewItem];
    [theMenu addItem: aMenuItem];
    [aMenuItem release];
    if ([TABVIEW numberOfTabViewItems] > 1) {
        aMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Move to new window",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context Menu") action:@selector(moveTabToNewWindowContextualMenuAction:) keyEquivalent:@""];
        [aMenuItem setRepresentedObject: tabViewItem];
        [theMenu addItem: aMenuItem];
        [aMenuItem release];
    }

    return theMenu;
}

- (PSMTabBarControl *)tabView:(NSTabView *)aTabView newTabBarForDraggedTabViewItem:(NSTabViewItem *)tabViewItem atPoint:(NSPoint)point
{
    PseudoTerminal *term;
    PTYSession *aSession = [tabViewItem identifier];

    if (aSession == nil) {
        return nil;
    }

    // create a new terminal window
    term = [[PseudoTerminal alloc] init];
    if (term == nil) {
        return nil;
    }

    [term initWithSmartLayout:NO fullScreen:nil];
    [term copySettingsFrom:self];

    [[iTermController sharedInstance] addInTerminals: term];
    [term release];

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
        prototype = aDict;
    }
    [self addNewSession:prototype];
}

- (void)setLabelColor:(NSColor *)color forTabViewItem:tabViewItem
{
    [tabBarControl setLabelColor:color forTabViewItem:tabViewItem];
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

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    int move = [[[aNotification userInfo] objectForKey:@"NSTextMovement"] intValue];
    NSControl *postingObject = [aNotification object]; 
    if (postingObject == findBarTextField) {
        // This is handled elsewhere.
        [previousFindString setString:@""];
        return;
    }

    switch (move) {
        case 16: // Return key
            [self sendCommand: nil];
            break;
        case 17: // Tab key
        {
            Bookmark* prototype = [[BookmarkModel sharedInstance] defaultBookmark];
            if (!prototype) {
                NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
                [ITAddressBookMgr setDefaultsInBookmark:aDict];
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

- (void)showHideFindBar
{
    BOOL hide = ![findBar isHidden];
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
    [findBar setHidden:hide];
    if (_fullScreen) {
        [self adjustFullScreenWindowForFindBarChange];
    } else {
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
}


@end

@implementation PseudoTerminal (Private)

- (void)_refreshTerminal:(NSNotification *)aNotification
{
    [self fitWindowToSessions];
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
    int i;  // Position in s that we're reading from.
    int j;  // Position in currentWord that we're writing to.
    int currentArgNumber;  // -1 for command, >=0 for arguments.
    int inQuotes;  // Are we inside double quotes?
    const char *s = [cmdl UTF8String];  // UTF-8 input string
    int slen = strlen(s);  // length of input command line.
    char* currentWord = malloc(slen + 1);  // buffer for the word being read.
    NSMutableArray *arguments;  // will store argv[1, ...]

    arguments = [[NSMutableArray alloc] init];

    i = 0;
    j = 0;
    inQuotes = 0;
    currentArgNumber = -1;
    while (i <= slen) {
        if (inQuotes) {
            if (s[i] == '\"') {
                inQuotes = 0;
            } else {
                currentWord[j++] = s[i];
            }
        } else {
            if (s[i] == '\"') {
                inQuotes = 1;
            } else if (s[i] == ' ' || 
                       s[i] == '\t' || 
                       s[i] == '\n' || 
                       s[i] == 0) {
                currentWord[j] = 0;
                if (currentArgNumber == -1) {
                    *cmd = [NSString stringWithCString:currentWord];
                } else
                    [arguments addObject:[NSString stringWithCString:currentWord]];
                j = 0;
                ++currentArgNumber;
                while (i < slen && (s[i+1] == ' ' || 
                                    s[i+1] == '\t' || 
                                    s[i+1] == '\n' || 
                                    s[i+1] == 0)) {
                    ++i;
                }
            } else {
                currentWord[j++] = s[i];
            }
        }
        ++i;
    }

    *path = [NSArray arrayWithArray:arguments];
    [arguments release];
    free(currentWord);
}

// Assumes all sessions are reasonable sizes.
- (void)fitWindowToSessions
{
    int width;
    int height;
    float charHeight = [self tallestSessionHeight:&height];
    float charWidth = [self widestSessionWidth:&width];

    [self fitWindowToSessionsWithWidth:width height:height charWidth:charWidth charHeight:charHeight];
}

- (void)adjustFullScreenWindowForFindBarChange
{
    if (!_fullScreen) {
        return;
    }

    int width;
    int height;
    float charHeight = [self maxCharHeight:&height];
    float charWidth = [self maxCharWidth:&width];

    NSRect aRect = [[self window] frame];
    height = aRect.size.height / charHeight;
    width = aRect.size.width / charWidth;
    int yoffset=0;
    if (![findBar isHidden]) {
        int dh = [findBar frame].size.height / charHeight + 1;
        height -= dh;
        yoffset = [findBar frame].size.height;
    } else {
        yoffset = floor(aRect.size.height - charHeight * height)/2; // screen height minus one half character
    }
    aRect = NSMakeRect(floor((aRect.size.width - width * charWidth - MARGIN * 2)/2),  // screen width minus one half character and a margin
                       yoffset,        
                       width * charWidth + MARGIN * 2,                        // enough width for width col plus two margins
                       charHeight * height);                                  // enough height for width rows
    [TABVIEW setFrame:aRect];
    [self fitSessionsToWindow];
    [self fitFindBarToWindow];
}

- (void)fitFindBarToWindow
{
    // Adjust the position of the findbar to fit properly below the tabview.
    NSRect findBarFrame = [findBar frame];
    findBarFrame.size.width = [TABVIEW frame].size.width;
    findBarFrame.origin.x = [TABVIEW frame].origin.x;
    [findBar setFrame: findBarFrame];
    findBarFrame.size.width += findBarFrame.origin.x;
    findBarFrame.origin.x = 0;
    [findBarSubview setFrame: findBarFrame];
}

- (void)fitWindowToSessionsWithWidth:(int)width height:(int)height charWidth:(float)charWidth charHeight:(float)charHeight
{
    // position the tabview and control
    NSRect aRect;
    if (_fullScreen) {
        [self adjustFullScreenWindowForFindBarChange];
        return;
    }

    aRect = [tabBarControl frame];
    aRect.origin.x = 0;
    aRect.origin.y = [TABVIEW frame].size.height;
    aRect.size.width = [[[self window] contentView] bounds].size.width;
    [tabBarControl setFrame: aRect];    
    [tabBarControl setSizeCellsToFit:NO];
    [tabBarControl setCellMinWidth:75];
    [tabBarControl setCellOptimumWidth:175];

    NSRect visibleFrame = [[[self window] screen] visibleFrame];

    NSSize size, vsize, winSize, tabViewSize;
    NSWindow *thisWindow = [self window];
    NSPoint topLeft;
    BOOL vmargin_added = NO;
    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];

    // This code sets up aRect to be the new size of the window.
    if (!_resizeInProgressFlag) {
        _resizeInProgressFlag = YES;
        // Get size of window
        aRect = [thisWindow contentRectForFrameRect:visibleFrame];
        if ([TABVIEW numberOfTabViewItems] > 1 || ![[PreferencePanel sharedInstance] hideTab]) {
            // reduce window size by hight of tabview
            aRect.size.height -= [tabBarControl frame].size.height;
        }
        // compute the max number of rows that fits in the remaining space
        if (![findBar isHidden]) {
            // reduce window height by size of findbar
            aRect.size.height -= [findBar frame].size.height;
        }

        // set desired size of textview to enough pixels to fit WIDTH*HEIGHT
        vsize.width = (int)ceil(charWidth * width + MARGIN * 2);
        vsize.height = (int)ceil(charHeight * height);
        NSLog(@"Setting window to content width of %d pixels for %d columns at charwidth of ", (int)vsize.width, width, charWidth);

        NSSize maxContentSize = [self maxContentRect].size;
        if (vsize.width > maxContentSize.width) {
            vsize.width = (int)(maxContentSize.width / charWidth) * (int)charWidth;
        }
        if (vsize.height > maxContentSize.height) {
            vsize.height = (int)(maxContentSize.height / charHeight) * (int)charHeight;
        }
        // NSLog(@"width=%d,height=%d",[[[_sessionMgr currentSession] SCREEN] width],[[[_sessionMgr currentSession] SCREEN] height]);

        // figure out how big the scrollview should be to achieve the desired textview size of vsize.
        size = [PTYScrollView frameSizeForContentSize:vsize
                                hasHorizontalScroller:NO
                                  hasVerticalScroller:hasScrollbar
                                           borderType:NSNoBorder];
        [thisWindow setShowsResizeIndicator: hasScrollbar];
        NSLog(@"%s: scrollview content size %.1f, %.1f", __PRETTY_FUNCTION__,
              size.width, size.height);            

        // figure out how big the tabview should be to fit the scrollview.
        tabViewSize = [PTYTabView frameSizeForContentSize:size 
                                              tabViewType:[TABVIEW tabViewType] 
                                              controlSize:[TABVIEW controlSize]];
        NSLog(@"%s: tabview content size %.1f, %.1f", __PRETTY_FUNCTION__,
              tabViewSize.width, tabViewSize.height);

        // desired size of window content
        winSize = tabViewSize;
        if (![findBar isHidden]) {
            winSize.height += [findBar frame].size.height;
        }
        if ([TABVIEW numberOfTabViewItems] == 1 && 
            [[PreferencePanel sharedInstance] hideTab]) {
            // The tabs are not visible at the top of the window. Set aRect appropriately.
            [tabBarControl setHidden: YES];
            aRect.origin.x = 0;
            aRect.origin.y = ([findBar isHidden] && [[PreferencePanel sharedInstance] useBorder]) ? VMARGIN : 0;
            if (![findBar isHidden]) {
                aRect.origin.y += [findBar frame].size.height;
            }
            aRect.size = tabViewSize;
            [TABVIEW setFrame: aRect];        
            if ([findBar isHidden] && [[PreferencePanel sharedInstance] useBorder]) {
                winSize.height += VMARGIN;
                vmargin_added = YES;
            }
        } else {
            // The tabs are visible at the top of the window.
            [tabBarControl setHidden: NO];
            [tabBarControl setTabLocation: [[PreferencePanel sharedInstance] tabViewType]];
            winSize.height += [tabBarControl frame].size.height;
            if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
                // setup aRect to make room for the tabs at the top.
                aRect.origin.x = 0;
                aRect.origin.y = ([findBar isHidden] && [[PreferencePanel sharedInstance] useBorder]) ? VMARGIN : 0;
                aRect.size = tabViewSize;
                if (![findBar isHidden]) {
                    aRect.origin.y += [findBar frame].size.height;
                }
                [TABVIEW setFrame: aRect];
                aRect.origin.y += aRect.size.height;
                aRect.size.height = [tabBarControl frame].size.height;
                [tabBarControl setFrame: aRect];
                if ([findBar isHidden] && [[PreferencePanel sharedInstance] useBorder]) {
                    winSize.height += VMARGIN;
                    vmargin_added = YES;
                }
            } else {
                // setup aRect to make room for the tabs at the bottom.
                aRect.origin.x = 0;
                aRect.origin.y = 0;
                aRect.size.width = tabViewSize.width;
                aRect.size.height = [tabBarControl frame].size.height;
                if (![findBar isHidden]) {
                    aRect.origin.y += [findBar frame].size.height;
                }
                [tabBarControl setFrame: aRect];
                aRect.origin.y = [tabBarControl frame].size.height;
                if (![findBar isHidden]) {
                    aRect.origin.y += [findBar frame].size.height;
                }
                aRect.size.height = tabViewSize.height;
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
        NSLog(@"%s: window content size %.1f, %.1f", __PRETTY_FUNCTION__,
              winSize.width, winSize.height);

        // Preserve the top-left corner of the frame.
        aRect = [thisWindow frame];
        topLeft.x = aRect.origin.x;
        topLeft.y = aRect.origin.y + aRect.size.height;

        aRect.size.width = winSize.width;
        aRect.size.height = winSize.height;
        NSRect frame = [thisWindow frameRectForContentRect: aRect];
        frame.origin.x = topLeft.x;
        frame.origin.y = topLeft.y - frame.size.height;

        [[thisWindow contentView] setAutoresizesSubviews: NO];
        // This triggers a call to fitSessionsToWindow (via windowDidResize)
        [thisWindow setFrame: frame display:YES];
        NSLog(@"Set frame size to %fx%f", frame.size.height, frame.size.width);
        [[thisWindow contentView] setAutoresizesSubviews: YES]; 

        if (vmargin_added) {
            [[thisWindow contentView] lockFocus];
            [[NSColor windowFrameColor] set];
            NSRectFill(NSMakeRect(0,0,vsize.width,VMARGIN));
            [[thisWindow contentView] unlockFocus];
        }

        _resizeInProgressFlag = NO;
    }

    [self fitFindBarToWindow];

    [[[self currentSession] TEXTVIEW] setNeedsDisplay:YES];
    [tabBarControl update];
    [[self window] setResizeIncrements:NSMakeSize([self maxCharWidth:nil], [self maxCharHeight:nil])];
}    

- (float)maxCharWidth:(int*)numChars
{
    float max=0;
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYSession* session = [[TABVIEW tabViewItemAtIndex:i] identifier];
        float w =[[session TEXTVIEW] charWidth];
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
    [findBar setHidden:[other->findBar isHidden]];
}

- (void)setupSession:(PTYSession *)aSession
               title:(NSString *)title
{
    NSDictionary *tempPrefs;
    ITAddressBookMgr *bookmarkManager;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal setupSession]",
          __FILE__, __LINE__);
#endif

    NSParameterAssert(aSession != nil);    

    // get our shared managers
    bookmarkManager = [ITAddressBookMgr sharedInstance];    

    // Init the rest of the session
    [aSession setParent:self];

    // set some default parameters
    if ([aSession addressBookEntry] == nil) {
        // get the default entry
        NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
        [ITAddressBookMgr setDefaultsInBookmark:dict];
        [aSession setAddressBookEntry:dict];
        tempPrefs = dict;
    } else {
        tempPrefs = [aSession addressBookEntry];
    }
    int rows = [[tempPrefs objectForKey:KEY_ROWS] intValue];
    int columns = [[tempPrefs objectForKey:KEY_COLUMNS] intValue];
    // rows, columns are set to the bookmark defaults. Make sure they'll fit.

    NSSize charSize = [PTYTextView charSizeForFont:[ITAddressBookMgr fontWithDesc:[tempPrefs objectForKey:KEY_NORMAL_FONT]] 
                                 horizontalSpacing:[[tempPrefs objectForKey:KEY_HORIZONTAL_SPACING] floatValue] 
                                   verticalSpacing:[[tempPrefs objectForKey:KEY_VERTICAL_SPACING] floatValue]];

    if ([TABVIEW numberOfTabViewItems] == 0) {
        rows = [aSession rows];
        columns = [aSession columns];
    } else {
        NSSize contentSize = [self visibleContentRect].size;
        rows = contentSize.height / charSize.height;
        columns = (contentSize.width - MARGIN*2) / charSize.width;
    }

    NSRect marginlessRect = NSMakeRect(0, 0, columns * charSize.width, rows * charSize.height);

    if ([aSession initScreen:marginlessRect vmargin:0]) {
        [self safelySetSessionSize:aSession rows:rows columns:columns];
        [aSession setPreferencesFromAddressBookEntry:tempPrefs];
        [[aSession SCREEN] setDisplay:[aSession TEXTVIEW]];
        [[aSession TERMINAL] setTrace:YES];    // debug vt100 escape sequence decode

        if (title) {
            [aSession setName:title];
            [aSession setDefaultName:title];
            [self setWindowTitle];
        }
    }
}

- (NSRect)maxContentRect
{
    NSRect visibleFrame = [[[self window] screen] visibleFrame];
    NSRect maxContentRect = [[self window] contentRectForFrameRect:visibleFrame];
    if (([TABVIEW numberOfTabViewItems] + tabViewItemsBeingAdded) > 1 || ![[PreferencePanel sharedInstance] hideTab]) {
        // reduce window size by hight of tabview
        maxContentRect.size.height -= [tabBarControl frame].size.height;
    }   

    // compute the max number of rows that fits in the remaining space
    if (![findBar isHidden]) {
        // reduce window height by size of findbar
        maxContentRect.size.height -= [findBar frame].size.height;
    }   
    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
    if (hasScrollbar) {
        maxContentRect.size.width -= [NSScroller scrollerWidth];
    }
    return maxContentRect;
}

- (NSRect)visibleContentRect
{
    NSRect current = [[[self currentSession] SCROLLVIEW] documentVisibleRect];
    if (([TABVIEW numberOfTabViewItems] + tabViewItemsBeingAdded) > 1 && 
        [tabBarControl isHidden] &&
        [[PreferencePanel sharedInstance] hideTab]) {
        // A tab bar control is about to be shown.
        current.size.height -= [tabBarControl frame].size.height;
    }
    return current;
}

// Set the session to a size that fits on the screen.
- (void)safelySetSessionSize:(PTYSession*)aSession rows:(int)rows columns:(int)columns
{
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

        int max_height = [self maxContentRect].size.height / [[aSession TEXTVIEW] lineHeight];

        if (height > max_height) {
            height = max_height;
        }
        [[aSession SCREEN] resizeWidth:width height:height];
        [[aSession SHELL] setWidth:width  height:height];
        [[aSession SCROLLVIEW] setHasVerticalScroller:hasScrollbar];
        [[aSession SCROLLVIEW] setLineScroll:[[aSession TEXTVIEW] lineHeight]];
        [[aSession SCROLLVIEW] setPageScroll:height*[[aSession TEXTVIEW] lineHeight]];
        if ([aSession backgroundImagePath]) {
            [aSession setBackgroundImagePath:[aSession backgroundImagePath]]; 
        }
    }        
}

- (void)fitSessionToWindow:(PTYSession*)aSession
{
    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
    NSSize size = [self visibleContentRect].size;
    int width = (size.width - MARGIN*2) / [[aSession TEXTVIEW] charWidth];
    NSLog(@"There are %d pixels avilable for %d columns at charwidth of %f", (int)size.width, width, [[aSession TEXTVIEW] charWidth]);
    int height = size.height / [[aSession TEXTVIEW] lineHeight];

    [[aSession SCREEN] resizeWidth:width height:height];
    [[aSession SHELL] setWidth:width  height:height];
    [[aSession SCROLLVIEW] setHasVerticalScroller:hasScrollbar];
    [[aSession SCROLLVIEW] setLineScroll:[[aSession TEXTVIEW] lineHeight]];
    [[aSession SCROLLVIEW] setPageScroll:height*[[aSession TEXTVIEW] lineHeight]];
    if ([aSession backgroundImagePath]) {
        [aSession setBackgroundImagePath:[aSession backgroundImagePath]]; 
    }
}

- (void)insertSession:(PTYSession *)aSession atIndex:(int)anIndex
{
    NSTabViewItem *aTabViewItem;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal insertSession: 0x%x atIndex: %d]",
          __FILE__, __LINE__, aSession, index);
#endif    

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
        [TABVIEW insertTabViewItem: aTabViewItem atIndex: anIndex];

        [aTabViewItem release];
        [TABVIEW selectTabViewItemAtIndex:anIndex];

        if ([self windowInited] && !_fullScreen) {
            [[self window] makeKeyAndOrderFront: self];
        }
        [[iTermController sharedInstance] setCurrentTerminal: self];
    }
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
    } else {
        [[self window] setBackgroundColor: normalBackgroundColor];
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

- (BOOL)sendInputToAllSessions
{
    return (sendInputToAllSessions);
}

- (void)fitSessionsToWindow
{
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYSession* session = (PTYSession*) [[TABVIEW tabViewItemAtIndex:i] identifier];
        [self fitSessionToWindow:session];
    }
}

- (void)fitWindowToSession:(PTYSession*)session
{
    float charHeight = [[session TEXTVIEW] lineHeight];
    float charWidth = [[session TEXTVIEW] charWidth];
    int height = [session rows];
    int width = [session columns];
    [self fitWindowToSessionsWithWidth:width height:height charWidth:charWidth charHeight:charHeight];
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
    term = [[PseudoTerminal alloc] init];
    if (term == nil) {
        return;
    }

    [term initWithSmartLayout:NO fullScreen:nil];

    [[iTermController sharedInstance] addInTerminals: term];
    [term release];


    // temporarily retain the tabViewItem
    [aTabViewItem retain];

    // remove from our window
    [TABVIEW removeTabViewItem: aTabViewItem];

    // add the session to the new terminal
    [term insertSession: aSession atIndex: 0];
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

- (IBAction)closeFindBar:(id)sender
{
    if (![findBar isHidden]) {
        [self showHideFindBar];
    }
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

-(void)addNewSession:(NSDictionary *)addressbookEntry
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

-(void)addNewSession:(NSDictionary *)addressbookEntry withURL:(NSString *)url
{
    // NSLog(@"PseudoTerminal: -addInSessions: 0x%x", object);
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
}

-(void)addNewSession:(NSDictionary *)addressbookEntry withCommand:(NSString *)command
{
    // NSLog(@"PseudoTerminal: -addInSessions: 0x%x", object);
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
}

-(void)appendSession:(PTYSession *)object
{
    // NSLog(@"PseudoTerminal: -appendSession: 0x%x", object);
    ++tabViewItemsBeingAdded;
    [self setupSession: object title: nil];
    tabViewItemsBeingAdded--;
    if ([object SCREEN]) {  // screen initialized ok
        [self insertSession: object atIndex:[TABVIEW numberOfTabViewItems]];
    }
}

-(void)replaceInSessions:(PTYSession *)object atIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -replaceInSessions: 0x%x atIndex: %d", object, anIndex);
    NSLog(@"Replace Sessions: not implemented.");
}

-(void)addInSessions:(PTYSession *)object
{
    // NSLog(@"PseudoTerminal: -addInSessions: 0x%x", object);
    [self insertInSessions: object];
}

-(void)insertInSessions:(PTYSession *)object
{
    // NSLog(@"PseudoTerminal: -insertInSessions: 0x%x", object);
    [self insertInSessions: object atIndex:[TABVIEW numberOfTabViewItems]];
}

-(void)insertInSessions:(PTYSession *)object atIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -insertInSessions: 0x%x atIndex: %d", object, anIndex);
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

-(void)handleLaunchScriptCommand: (NSScriptCommand *)command
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
        abEntry = aDict;
    }

    // If we have not set up a window, do it now
    if ([self windowInited] == NO) {
        [self initWithSmartLayout:NO fullScreen:nil];
    }

    // TODO(georgen): test this
    // launch the session!
    [[iTermController sharedInstance] launchBookmark: abEntry inTerminal: self];

    return;
}

@end

