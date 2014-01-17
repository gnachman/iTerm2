#import <Cocoa/Cocoa.h>
#import "PSMTabBarControl.h"
#import "PTYTabView.h"
#import "PTYWindow.h"
#import "ProfileListView.h"
#import "WindowControllerInterface.h"
#import "PasteboardHistory.h"
#import "Popup.h"
#import "Autocomplete.h"
#import "ToolbeltView.h"
#import "SolidColorView.h"
#import "FutureMethods.h"

@class BottomBarView;
@class PTYSession;
@class PSMTabBarControl;
@class PTToolbarController;
@class ToolbeltView;
@class iTermController;

@class TmuxController;

// This class is 1:1 with windows. It controls the tabs, bottombar, toolbar,
// fullscreen, and coordinates resizing of sessions (either session-initiated
// or window-initiated).
// OS 10.5 doesn't support window delegates
@interface PseudoTerminal : NSWindowController <
  iTermWindowController,
  NSWindowDelegate,
  PSMTabBarControlDelegate,
  PTYTabViewDelegateProtocol,
  PTYWindowDelegateProtocol,
  WindowControllerInterface>

// Draws a mock-up of a window arrangement into the current graphics context.
// |frames| gives an array of NSValue's having NSRect values for each screen,
// giving the screens' coordinates in the model.
+ (void)drawArrangementPreview:(NSDictionary*)terminalArrangement
                  screenFrames:(NSArray *)frames;

// Returns a new terminal window restored from an arrangement, but with no
// tabs/sessions.
+ (PseudoTerminal*)bareTerminalWithArrangement:(NSDictionary*)arrangement;

// Returns a new terminal window restored from an arrangement, with
// tabs/sessions also restored..
+ (PseudoTerminal*)terminalWithArrangement:(NSDictionary*)arrangement;

// Initialize a new PseudoTerminal.
// smartLayout: If true then position windows using the "smart layout"
//   algorithm.
// windowType: WINDOW_TYPE_NORMAL, WINDOW_TYPE_FULL_SCREEN, WINDOW_TYPE_TOP, or
//   WINDOW_TYPE_LION_FULL_SCREEN, or WINDOW_TYPE_BOTTOM or WINDOW_TYPE_LEFT or
//   WINDOW_TYPE_RIGHT
// screen: An index into [NSScreen screens], or -1 to let the system pick a
//   screen.
- (id)initWithSmartLayout:(BOOL)smartLayout
               windowType:(int)windowType
                   screen:(int)screenIndex;

// isHotkey indicates if this is a hotkey window, which recieves special
// treatment and must be unique.
- (id)initWithSmartLayout:(BOOL)smartLayout
               windowType:(int)windowType
                   screen:(int)screenNumber
                 isHotkey:(BOOL)isHotkey;

// If a PseudoTerminal is created with -init (such as happens with AppleScript)
// this must be called before it is used.
- (void)finishInitializationWithSmartLayout:(BOOL)smartLayout
                                 windowType:(int)windowType
                                     screen:(int)screenNumber
                                   isHotkey:(BOOL)isHotkey;

// The window's original screen.
- (NSScreen*)screen;

// Sets the window frame. Value should have an NSRect value.
- (void)setFrameValue:(NSValue *)value;

// The PTYWindow for this controller.
- (PTYWindow*)ptyWindow;

// Called on object deallocation.
- (void)dealloc;

// accessor for commandField.
- (id)commandField;

// Set the tab bar's look & feel
- (void)setTabBarStyle;

// Fix the window frame for fullscreen, top, bottom windows.
- (void)canonicalizeWindowFrame;

// Make the tab at [sender tag] the foreground tab.
- (void)selectSessionAtIndexAction:(id)sender;

// A unique number for this window assigned by finishInitializationWithSmartLayout.
- (NSString *)terminalGuid;

// Miniaturizes the window and marks it as a hide-after-opening window (which
// will be saved in window arrangements).
- (void)hideAfterOpening;

// Open a new tab with the bookmark given by the guid in
// [sender representedObject]. Used by menu items in the Bookmarks menu.
- (void)newSessionInTabAtIndex:(id)sender;

// Toggles visibility of fullscreen tab bar.
- (void)toggleFullScreenTabBar;

// Is there a saved scroll position?
- (BOOL)hasSavedScrollPosition;

// Set the window title to 'title'.
- (void)setWindowTitle:(NSString *)title;

// Sessions in the broadcast group.
- (NSArray *)broadcastSessions;

// Enter full screen mode in the next mainloop.
- (void)delayedEnterFullscreen;

// Toggle non-Lion fullscreen mode.
- (void)toggleTraditionalFullScreenMode;

// accessor
- (BOOL)fullScreenTabControl;

// Should the tab bar be shown?
- (BOOL)tabBarShouldBeVisible;

// If n tabs were added, should the tab bar then be shown?
- (BOOL)tabBarShouldBeVisibleWithAdditionalTabs:(int)n;

// Open the session preference panel.
- (void)editCurrentSession:(id)sender;

// Are we in in IR?
- (BOOL)inInstantReplay;

// Move backward/forward in time by one frame.
- (void)irAdvance:(int)dir;

// Does any session want to be prompted for closing?
- (BOOL)promptOnClose;

// Accessor for toolbelt view.
- (ToolbeltView *)toolbelt;

- (void)refreshTools;

#pragma mark - NSTextField Delegate Methods

// Called when return or tab is pressed in the bottombar text field or the command
// field.
- (void)controlTextDidEndEditing:(NSNotification *)aNotification;

#pragma mark - NSWindowController Delegate Methods

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

#pragma mark - PTYWindow Delegate Methods

// Set the window's initial frame. Unofficial protocol.
- (void)windowWillShowInitial;


#pragma mark - Tab View Delegate Methods

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

// Called after dropping a tab in this window.
- (void)tabView:(NSTabView*)aTabView
    didDropTabViewItem:(NSTabViewItem *)tabViewItem
       inTabBar:(PSMTabBarControl *)aTabBarControl;

// Called just before dropping a tab in this window.
- (void)tabView:(NSTabView*)aTabView
    willDropTabViewItem:(NSTabViewItem *)tabViewItem
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

// Fill in a path with the tabbar color.
- (void)fillPath:(NSBezierPath*)path;

// If excludeTmux is NO, then this is just like fitWindowToTabs. Otherwise, we
// resize the window to be just large enough to fit the largest tab without
// changing session sizes, but ignore tmux tabs when looking for the largest
// tab (assuming that a pending resize has been sent to the server, this lets
// you anticipate its response). Does nothing if all tabs are tmux tabs.
- (void)fitWindowToTabsExcludingTmuxTabs:(BOOL)excludeTmux;

// Update irBar.
- (void)updateInstantReplay;

// Show or hide as needed for current session.
- (void)showOrHideInstantReplayBar;

// Maximize or unmaximize the active pane
- (void)toggleMaximizeActivePane;

// Return the smallest allowable width for this terminal.
- (float)minWidth;

// Load an arrangement into an empty window.
- (void)loadArrangement:(NSDictionary *)arrangement;

// Returns the arrangement for this window.
- (NSDictionary*)arrangement;

// Update a window's tmux layout, such as when fonts or scrollbar sizes change.
- (void)refreshTmuxLayoutsAndWindow;

// All tabs in this window.
- (NSArray*)tabs;

// Up to one window may be the hotkey window, which is toggled with the system-wide
// hotkey.
- (void)setIsHotKeyWindow:(BOOL)value;

// Updates the window when screen parameters (number of screens, resolutions,
// etc.) change.
- (void)screenParametersDidChange;

// Changes how input is broadcast.
- (void)setBroadcastMode:(BroadcastMode)mode;

// Change split selection mode for all sessions in this window.
- (void)setSplitSelectionMode:(BOOL)mode excludingSession:(PTYSession *)session;

// Change visibility of menu bar (but only if it should be changed--may do
// nothing if the menu bar is on a different screen, for example).
- (void)hideMenuBar;
- (void)showMenuBar;

// Cause every session in this window to reload its bookmark.
- (void)reloadBookmarks;

// Return all sessions in all tabs.
- (NSArray*)allSessions;

#pragma mark - IBActions

- (IBAction)toggleShowTimestamps:(id)sender;
- (IBAction)openDashboard:(id)sender;
- (IBAction)findCursor:(id)sender;
// Save the current scroll position
- (IBAction)saveScrollPosition:(id)sender;
// Jump to the saved scroll position
- (IBAction)jumpToSavedScrollPosition:(id)sender;
// Close foreground tab.
- (IBAction)closeCurrentTab:(id)sender;
// Close the active session.
- (IBAction)closeCurrentSession:(id)sender;
// Select the tab to the left of the foreground tab.
- (IBAction)previousTab:(id)sender;
// Select the tab to the right of the foreground tab.
- (IBAction)nextTab:(id)sender;
// Select the most recent pane
- (IBAction)previousPane:(id)sender;
// Select the least recently used pane
- (IBAction)nextPane:(id)sender;
- (IBAction)detachTmux:(id)sender;
- (IBAction)newTmuxWindow:(id)sender;
- (IBAction)newTmuxTab:(id)sender;
// Toggle whether transparency is allowed in this terminal.
- (IBAction)toggleUseTransparency:(id)sender;
// Turn full-screen mode on or off. Creates a new PseudoTerminal and moves this
// one's state into it.
- (IBAction)toggleFullScreenMode:(id)sender;
// Called when next/prev frame button is clicked.
- (IBAction)irButton:(id)sender;
// Called when the close button in the find bar is pressed.
- (IBAction)closeInstantReplay:(id)sender;
- (IBAction)irSliderMoved:(id)sender;
// Advance to next or previous time step
- (IBAction)irPrev:(id)sender;
- (IBAction)irNext:(id)sender;
- (IBAction)stopCoprocess:(id)sender;
- (IBAction)runCoprocess:(id)sender;
- (IBAction)coprocessPanelEnd:(id)sender;
- (IBAction)coprocessHelp:(id)sender;
- (IBAction)openSplitHorizontallySheet:(id)sender;
- (IBAction)openSplitVerticallySheet:(id)sender;
// Show paste history window.
- (IBAction)openPasteHistory:(id)sender;
- (IBAction)openCommandHistory:(id)sender;
// Show autocomplete window.
- (IBAction)openAutocomplete:(id)sender;
// selector for menu item to split current session vertically.
- (IBAction)splitVertically:(id)sender;
- (IBAction)splitHorizontally:(id)sender;
- (IBAction)moveTabLeft:(id)sender;
- (IBAction)moveTabRight:(id)sender;
- (IBAction)resetCharset:(id)sender;
- (IBAction)logStart:(id)sender;
- (IBAction)logStop:(id)sender;
- (IBAction)wrapToggleToolbarShown:(id)sender;
- (IBAction)enableSendInputToAllPanes:(id)sender;
- (IBAction)disableBroadcasting:(id)sender;
- (IBAction)enableSendInputToAllTabs:(id)sender;
- (IBAction)closeWindow:(id)sender;
- (IBAction)sendCommand:(id)sender;
- (IBAction)parameterPanelEnd:(id)sender;
// Change active pane.
- (IBAction)selectPaneLeft:(id)sender;
- (IBAction)selectPaneRight:(id)sender;
- (IBAction)selectPaneUp:(id)sender;
- (IBAction)selectPaneDown:(id)sender;
- (IBAction)movePaneDividerRight:(id)sender;
- (IBAction)movePaneDividerLeft:(id)sender;
- (IBAction)movePaneDividerDown:(id)sender;
- (IBAction)movePaneDividerUp:(id)sender;
- (IBAction)addNoteAtCursor:(id)sender;
- (IBAction)showHideNotes:(id)sender;
- (IBAction)nextMarkOrNote:(id)sender;
- (IBAction)previousMarkOrNote:(id)sender;
- (IBAction)toggleAlertOnNextMark:(id)sender;
- (void)changeTabColorToMenuAction:(id)sender;
- (void)moveSessionToWindow:(id)sender;

#pragma mark - Key Value Coding

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
-(id)addNewSession:(NSDictionary *)addressbookEntry withURL: (NSString *)url;
-(id)addNewSession:(NSDictionary *)addressbookEntry
           withURL:(NSString *)url
     forObjectType:(iTermObjectType)objectType;
-(id)addNewSession:(NSDictionary *) addressbookEntry
       withCommand:(NSString *)command
     forObjectType:(iTermObjectType)objectType;
-(void)appendSession:(PTYSession *)object;
-(void)removeFromSessionsAtIndex:(unsigned)index;
-(void)setSessions: (NSArray*)sessions;
-(void)replaceInSessions:(PTYSession *)object atIndex:(unsigned)index;
-(void)addInSessions:(PTYSession *)object;
-(void)insertInSessions:(PTYSession *)object;
-(void)insertInSessions:(PTYSession *)object atIndex:(unsigned)index;
// Add a new session to this window with the given addressbook entry.
- (id)addNewSession:(NSDictionary *)addressbookEntry;


- (BOOL)windowInited;
- (void) setWindowInited: (BOOL) flag;

// a class method to provide the keys for KVC:
+(NSArray*)kvcKeys;

#pragma mark - Scripting support

-(void)handleSelectScriptCommand: (NSScriptCommand *)command;

-(id)handleLaunchScriptCommand: (NSScriptCommand *)command;

@end

