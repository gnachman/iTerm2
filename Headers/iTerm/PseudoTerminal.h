// -*- mode:objc -*-
// $Id: PseudoTerminal.h,v 1.62 2009-02-06 15:07:24 delx Exp $
/*
 **  PseudoTerminal.h
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

#import <Cocoa/Cocoa.h>
#import <iTerm/PTYTabView.h>
#import <iTerm/PTYWindow.h>
#import <BookmarkListView.h>

@class PTYSession, iTermController, PTToolbarController, PSMTabBarControl;

// The FindBar's view is of this class. It overrides drawing the background.
@interface FindBarView : NSView
{
}
- (void)drawRect:(NSRect)dirtyRect;

@end

// This class is 1:1 with windows. It controls the tabs, findbar, toolbar,
// fullscreen, and coordinates resizing of sessions (either session-initiated
// or window-initiated).
@interface PseudoTerminal : NSWindowController <PTYTabViewDelegateProtocol, PTYWindowDelegateProtocol>
{
    ////////////////////////////////////////////////////////////////////////////
    // Parameter Panel
    // A bookmark may have metasyntactic variables like $$FOO$$ in the command.
    // When opening such a bookmark, pop up a sheet and ask the user to fill in
    // the value. These fields belong to that sheet.
    IBOutlet NSTextField *parameterName;
    IBOutlet NSPanel     *parameterPanel;
    IBOutlet NSTextField *parameterValue;
    IBOutlet NSTextField *parameterPrompt;

    ////////////////////////////////////////////////////////////////////////////
    // FindBar
    // UI elements for searching the current session.

    // This contains all the other elements.
    IBOutlet FindBarView* findBarSubview;

    // The text that is being searched for.
    IBOutlet NSTextField* findBarTextField;

    // Buttons to advance search forward or backwards.
    IBOutlet NSButton*    findBarNextButton;
    IBOutlet NSButton*    findBarPreviousButton;

    // Checkbox: ignore case?
    IBOutlet NSButton*    ignoreCase;

    // Spins as asynchronous searching is in progress.
    IBOutlet NSProgressIndicator* findProgressIndicator;

    // Find happens incrementally. This remembers the string to search for.
    NSMutableString* previousFindString;

    // Contains only findBarSubview. For whatever reason, adding the FindBarView
    // directly to the window doesn't work.
    NSView* findBar;

    // Find runs out of a timer so that if you have a huge buffer then it
    // doesn't lock up. This timer runs the show.
    NSTimer* _timer;

    ////////////////////////////////////////////////////////////////////////////
    // Tab View
    // The tabview occupies almost the entire window. Each tab has an identifier
    // which is a PTYSession.
    PTYTabView *TABVIEW;

    // This is a sometimes-visible control that shows the tabs and lets the user
    // change which is visible.
    PSMTabBarControl *tabBarControl;

    // This is either 0 or 1. If 1, then a tab item is in the process of being
    // added and the tabBarControl will be shown if it is added successfully
    // if it's not currently shown.
    int tabViewItemsBeingAdded;

    ////////////////////////////////////////////////////////////////////////////
    // Toolbar
    // A toolbar may be shown at the top of the window.

    // This does the dirty work of running the toolbar.
    PTToolbarController* _toolbarController;

    // A text field into which you may type a command. When you press enter in it
    // then the text is sent to the terminal.
    IBOutlet id commandField;

    ////////////////////////////////////////////////////////////////////////////
    // Miscellaneous

    // Is this a full screenw indow?
    BOOL _fullScreen;

    // When you enter full-screen mode the old frame size is saved here. When
    // full-screen mode is exited that frame is restored.
    NSRect oldFrame_;

    // True if an [init...] method was called.
    BOOL windowInited;

    // True if input is being redirected to all sessions.
    BOOL sendInputToAllSessions;

    // True if the window title is showing transient information (such as the
    // size during resizing).
    BOOL tempTitle;

    // When sending input to all sessions we temporarily change the background
    // color. This stores the normal background color so we can restore to it.
    NSColor *normalBackgroundColor;

    // This prevents recursive resizing.
    BOOL _resizeInProgressFlag;

    // There is a scheme for saving window positions. Each window is assigned
    // a number, and the positions are stored by window name. The window name
    // includes its unique number. framePos gives this window's number.
    int framePos;
}

// Initialize a new PseudoTerminal.
// smartLayout: If true then position windows using the "smart layout" 
//   algorithm.
// fullScreen: If nil, then a normal window is opened. If not nil, it gives the
//   size of the screen and a full screen window is opened with those
//   dimensions.
- (id)initWithSmartLayout:(BOOL)smartLayout 
               fullScreen:(NSScreen*)fullScreen;

// Called on object deallocation.
- (void)dealloc;

// accessor for commandField.
- (id)commandField;

// Make the tab at [sender tag] the foreground tab.
- (void)selectSessionAtIndexAction:(id)sender;

// Open a new tab with the bookmark given by the guid in
// [sender representedObject]. Used by menu items in the Bookmarks menu.
- (void)newSessionInTabAtIndex:(id)sender;

// Close a tab and resize/close the window if needed.
- (void)closeSession:(PTYSession*)aSession;

// Close the foreground session.
- (IBAction)closeCurrentSession:(id)sender;

// Select the tab to the left of the foreground tab.
- (IBAction)previousSession:(id)sender;

// Select the tab to the right of the foreground tab.
- (IBAction)nextSession:(id)sender;

// Return the number of sessions in this window.
- (int)numberOfSessions;

// Accessor for a session.
- (PTYSession*)sessionAtIndex:(int)i;

// accessor for foreground session.
- (PTYSession *)currentSession;

// tab number of current session.
- (int)currentSessionIndex;

// Set the window title to the name of the current session.
- (void)setWindowTitle;

// Set the window title to 'title'.
- (void)setWindowTitle:(NSString *)title;

// Is the window title transient?
- (BOOL)tempTitle;

// Set the window title to non-transient.
- (void)resetTempTitle;

// Call writeTask: for each session's shell with the given data.
- (void)sendInputToAllSessions:(NSData *)data;

// Turn full-screen mode on or off. Creates a new PseudoTerminal and moves this
// one's state into it.
- (IBAction)toggleFullScreen:(id)sender;

// accessor
- (BOOL)fullScreen;

// Called by VT100Screen when it wants to resize a window for a 
// session-initiated resize. It resizes the session, then the window, then all
// sessions to fit the new window size.
- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height;

// Open the session preference panel.
- (void)editCurrentSession:(id)sender;

// Construct the right-click context menu.
- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu;

// setters
- (void)enableBlur;
- (void)disableBlur;

// Set the text color for a tab control's name.
- (void)setLabelColor:(NSColor *)color forTabViewItem:tabViewItem;

// accessor
- (PTYTabView *)tabView;

// Search for the previous occurrence of a string.
- (IBAction)searchPrevious:(id)sender;

// Search for the next occurrence of a string.
- (IBAction)searchNext:(id)sender;

// Search for the currently selected text.
- (void)findWithSelection;

// Called when the findbar or the command text field changes.
- (void)controlTextDidChange:(NSNotification *)aNotification;

// Toggle findbar.
- (void)showHideFindBar;


////////////////////////////////////////////////////////////////////////////////
// NSTextField Delegate Methods

// Called when return or tab is pressed in the findbar text field or the command
// field.
- (void)controlTextDidEndEditing:(NSNotification *)aNotification;


////////////////////////////////////////////////////////////////////////////////
// NSWindowController Delegate Methods
// Called when a window is unhidden.
- (void)windowDidDeminiaturize:(NSNotification *)aNotification;

// The window is trying to close. Pop a dialog if necessary and return the
// disposition.
- (BOOL)windowShouldClose:(NSNotification *)aNotification;

// Called when the window closes. Gets our affairs in order.
- (void)windowWillClose:(NSNotification *)aNotification;

// Called when the window is hiding (cmd-h).
- (void)windowWillMiniaturize:(NSNotification *)aNotification;

// Called when this window becomes key.
// "A key window is the current focus for keyboard events (for example, it 
// contains a text field the user is typing in)"
- (void)windowDidBecomeKey:(NSNotification *)aNotification;

// Called when this window ceases to be the key window.
- (void)windowDidResignKey:(NSNotification *)aNotification;

// Called when this window ceases to be the main window.
// "A main window is the primary focus of user actions for the application"
- (void)windowDidResignMain:(NSNotification *)aNotification;

// Called when a resize is inevitable. Wants to resize to proposedFrameSize.
// Returns an acceptable size which has a content size that is a multiple of the
// widest/tallest character.
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize;

// Called after a window resizes. Make sessions resize to fit.
- (void)windowDidResize:(NSNotification *)aNotification;

// Called when the toolbar is shown/hidden.
- (void)windowWillToggleToolbarVisibility:(id)sender;

// Called after the toolbar is shown/hidden. Adjusts window size.
- (void)windowDidToggleToolbarVisibility:(id)sender;

// Called when the green 'zoom' button in the top left of the window is pressed.
- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender 
                        defaultFrame:(NSRect)defaultFrame;


////////////////////////////////////////////////////////////////////////////////
// PTYWindow Delegate Methods

// Set the window's initial frame. Unofficial protocol.
- (void)windowWillShowInitial;


////////////////////////////////////////////////////////////////////////////////
// Tab View Delegate Methods

// Called before a tab view item is selected.
- (void)tabView:(NSTabView *)tabView 
    willSelectTabViewItem:(NSTabViewItem *)tabViewItem;

// Called afer a tab is selected.
- (void)tabView:(NSTabView *)tabView 
    didSelectTabViewItem:(NSTabViewItem *)tabViewItem;

// Called before removing a tab.
- (void)tabView:(NSTabView *)tabView 
    willRemoveTabViewItem:(NSTabViewItem *)tabViewItem;

// Called before adding a tab.
- (void)tabView:(NSTabView *)tabView 
    willAddTabViewItem:(NSTabViewItem *)tabViewItem;

// Called before inserting a tab at a specific location.
- (void)tabView:(NSTabView *)tabView 
    willInsertTabViewItem:(NSTabViewItem *)tabViewItem 
        atIndex:(int)anIndex;

// Called to see if a tab can be closed. May open a confirmation dialog.
- (BOOL)tabView:(NSTabView*)tabView 
     shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem;

// Called to see if a tab can be dragged.
- (BOOL)tabView:(NSTabView*)aTabView 
    shouldDragTabViewItem:(NSTabViewItem *)tabViewItem 
     fromTabBar:(PSMTabBarControl *)tabBarControl;

// Called to see if a tab can be dropped in this window.
- (BOOL)tabView:(NSTabView*)aTabView 
    shouldDropTabViewItem:(NSTabViewItem *)tabViewItem 
       inTabBar:(PSMTabBarControl *)tabBarControl;

// Called after droping a tab in this window.
- (void)tabView:(NSTabView*)aTabView 
    didDropTabViewItem:(NSTabViewItem *)tabViewItem 
       inTabBar:(PSMTabBarControl *)aTabBarControl;

// Called after the last tab in a window is closed.
- (void)tabView:(NSTabView *)aTabView 
    closeWindowForLastTabViewItem:(NSTabViewItem *)tabViewItem;

// Compose the image for a tab control.
- (NSImage *)tabView:(NSTabView *)aTabView 
 imageForTabViewItem:(NSTabViewItem *)tabViewItem
              offset:(NSSize *)offset
           styleMask:(unsigned int *)styleMask;

// Called after a tab is added or removed.
- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView;

// Creates a context menu for a tab control.
- (NSMenu *)tabView:(NSTabView *)aTabView 
 menuForTabViewItem:(NSTabViewItem *)tabViewItem;

// Called when a tab is dragged and dropped into an area not in an existing
// window. A new window is created having only this tab.
- (PSMTabBarControl *)tabView:(NSTabView *)aTabView 
    newTabBarForDraggedTabViewItem:(NSTabViewItem *)tabViewItem 
                      atPoint:(NSPoint)point;

// Returns a tooltip for a tab control.
- (NSString *)tabView:(NSTabView *)aTabView 
    toolTipForTabViewItem:(NSTabViewItem *)aTabViewItem;

// Called when a tab is double clicked.
- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem;

// Called when the empty area in the tab bar is double clicked.
- (void)tabViewDoubleClickTabBar:(NSTabView *)tabView;

// Returns true if an init... method was already called.
- (BOOL)isInitialized;

@end

@interface PseudoTerminal (KeyValueCoding)
// IMPORTANT:
// Never remove methods from here because it will break existing Applescript.
// Be careful making any changes that might not be backward-compatible.

// accessors for to-many relationships:
// accessors for attributes:
// IMPORTANT: These accessors are here for backward compatibility with existing
// applescript. These methods don't make sense since each tab may have a
// different number of rows and columns.
-(int)columns;
-(void)setColumns: (int)columns;
-(int)rows;
-(void)setRows: (int)rows;

// (See NSScriptKeyValueCoding.h)
-(id)valueInSessionsAtIndex:(unsigned)index;
-(id)valueWithName: (NSString *)uniqueName inPropertyWithKey: (NSString*)propertyKey;
-(id)valueWithID: (NSString *)uniqueID inPropertyWithKey: (NSString*)propertyKey;
-(void)addNewSession:(NSDictionary *)addressbookEntry withURL: (NSString *)url;
-(void)addNewSession:(NSDictionary *) addressbookEntry withCommand: (NSString *)command;
-(void)appendSession:(PTYSession *)object;
-(void)removeFromSessionsAtIndex:(unsigned)index;
-(NSArray*)sessions;
-(void)setSessions: (NSArray*)sessions;
-(void)replaceInSessions:(PTYSession *)object atIndex:(unsigned)index;
-(void)addInSessions:(PTYSession *)object;
-(void)insertInSessions:(PTYSession *)object;
-(void)insertInSessions:(PTYSession *)object atIndex:(unsigned)index;
// Add a new session to this window with the given addressbook entry.
- (void)addNewSession:(NSDictionary *)addressbookEntry;


- (BOOL)windowInited;
- (void) setWindowInited: (BOOL) flag;

// a class method to provide the keys for KVC:
+(NSArray*)kvcKeys;

@end

@interface PseudoTerminal (Private)

- (void)hideMenuBar;

// This is a half-baked function that tries to parse a command line into a 
// command (returned in *cmd) and an array of arguments (returned in *path).
+ (void)breakDown:(NSString *)cmdl 
          cmdPath:(NSString **)cmd 
          cmdArgs:(NSArray **)path;

// Force the window size to change to be just large enough to fit this session.
- (void)fitWindowToSession:(PTYSession*)session;

// Force the window size to change to be just large enough to fit the widest and
// tallest sessions.
- (void)fitWindowToSessions;

// Returns the width of characters in pixels in the session with the widest
// characters. Fills in *numChars with the number of columns in that session.
- (float)maxCharWidth:(int*)numChars;

// Returns the height of characters in pixels in the session with the tallest
// characters. Fills in *numChars with the number of rows in that session.
- (float)maxCharHeight:(int*)numChars;

// Returns the width of characters in pixels in the overall widest session.
// Fills in *numChars with the number of columns in that session.
- (float)widestSessionWidth:(int*)numChars;

// Returns the height of characters in pixels in the overall tallest session.
// Fills in *numChars with the number of rows in that session.
- (float)tallestSessionHeight:(int*)numChars;

// Force the window to fit a hypothetical session with a given number of rows,
// columns, character width, and line height.
- (void)fitWindowToSessionsWithWidth:(int)width 
                              height:(int)height 
                           charWidth:(float)charWidth 
                          charHeight:(float)charHeight;

// Copy state from 'other' to this terminal.
- (void)copySettingsFrom:(PseudoTerminal*)other;


// Set the session's address book and initialize its screen and name. Sets the
// window title to the session's name.
- (void)setupSession:(PTYSession *)aSession
               title:(NSString *)title;

// Returns the largest possible content rectangle that can fit on the screen
// while leaving space for the toolbar, findbar, window decorations, etc.
- (NSRect)maxContentRect;

// Returns the size of the area where text is shown. Does not include the
// scrollbar, findbar, toolbar, or window decorations, but does include any
// margins within the PTYTextView.
- (NSRect)visibleContentRect;

// Push a size change to a session (and on to its shell) but clamps the size to
// reasonable minimum and maximum limits. 
- (void)safelySetSessionSize:(PTYSession*)aSession 
                        rows:(int)rows 
                     columns:(int)columns;

// Push a size change to a session so that it is as large as possible while
// still fitting in the window.
- (void)fitSessionToWindow:(PTYSession*)aSession;

// Push size changes to all sessions so they are all as large as possible while
// still fitting in the window.
- (void)fitSessionsToWindow;

// Add a session to the tab view.
- (void)insertSession:(PTYSession *)aSession atIndex:(int)anIndex;

// Reutrn the name of the foreground session.
- (NSString *)currentSessionName;

// Set the session name. If theSessionName is nil then set it to the pathname
// or "Finish" if it's closed.
- (void)setCurrentSessionName:(NSString *)theSessionName;

// Assign a value to the 'framePos' member variable which is used for storing
// window frame positions between invocations of iTerm.
- (void)setFramePos;

// Execute the given program and set the window title if it is uninitialized.
- (void)startProgram:(NSString *)program
           arguments:(NSArray *)prog_argv
         environment:(NSDictionary *)prog_env 
              isUTF8:(BOOL)isUTF8;

// Send a reset to the current session's terminal.
- (void)reset:(id)sender;

// Clear the buffer of the current session.
- (void)clearBuffer:(id)sender;

// Erase the scrollback buffer of the current session.
- (void)clearScrollbackBuffer:(id)sender;

// Turn on session logging in the current session.
- (IBAction)logStart:(id)sender;

// Turn off session logging in the current session.
- (IBAction)logStop:(id)sender;

// Returns true if the given menu item is selectable.
- (BOOL)validateMenuItem:(NSMenuItem *)item;

// accessor
- (BOOL)sendInputToAllSessions;

// setter
- (void)setSendInputToAllSessions:(BOOL)flag;

// Turn on/off sending of input to all sessions. This causes a bunch of UI
// to update in addition to flipping the flag.
- (IBAction)toggleInputToAllSessions:(id)sender;

// Show a dialog confirming close. Returns YES if the window should be closed.
- (BOOL)showCloseWindow;

// accessor
- (PSMTabBarControl*)tabBarControl;

// Called when the tab control's context menu is closed.
- (void)closeTabContextualMenuAction:(id)sender;

// Move a tab to a new window due to a context menu selection.
- (void)moveTabToNewWindowContextualMenuAction:(id)sender;

// Close this window.
- (IBAction)closeWindow:(id)sender;

// Sends text to the current session. Also interprets URLs and opens them.
- (IBAction)sendCommand:(id)sender;

// Cause every session in this window to reload its bookmark.
- (void)reloadBookmarks;

// Called when the parameter panel should close.
- (IBAction)parameterPanelEnd:(id)sender;

// Called by the timer to search more text.
- (void)_continueSearch;

// Begin searching for a string.
- (void)_newSearch:(BOOL)needTimer;

// Called when the close button in the find bar is pressed.
- (IBAction)closeFindBar:(id)sender;

// Grow or shrink the tabview to make room for the find bar in fullscreen mode
// and then fit sessions to new window size.
- (void)adjustFullScreenWindowForFindBarChange;

// Adjust the find bar's width to match the window's.
- (void)fitFindBarToWindow;

@end

@interface PseudoTerminal (ScriptingSupport)

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier;

-(void)handleSelectScriptCommand: (NSScriptCommand *)command;

-(void)handleLaunchScriptCommand: (NSScriptCommand *)command;

@end

