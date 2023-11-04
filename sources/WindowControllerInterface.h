// Defines a protocol shared by PseudoTerminal and FakeWindow.

#import <Cocoa/Cocoa.h>
#import "ITAddressBookMgr.h"
#import "iTermBroadcastInputHelper.h"
#import "ProfileModel.h"
#import "PTYTabDelegate.h"
#import "PTYWindow.h"

@class iTermPopupWindowController;
@class iTermRestorableSession;
@class iTermSwiftyStringGraph;
@class PSMTabBarControl;
@class PTYSession;
@class PTYTab;
@class PTYTabView;
@class TmuxController;
@protocol VT100RemoteHostReading;

@class iTermRestorableSession;

// This is a very basic interface, which is sufficient for simulating a window
// controller for instant replay.
@protocol WindowControllerInterface <NSObject>

// Called by VT100Screen when it wants to resize a window for a
// session-initiated resize. It resizes the session, then the window, then all
// sessions to fit the new window size.
- (BOOL)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height;

// Is the window in traditional fullscreen mode?
- (BOOL)fullScreen;

// Returns true if the window is fullscreen in either Lion-style or
// pre-Lion-style fullscreen.
- (BOOL)anyFullScreen;
- (BOOL)movesWhenDraggedOntoSelf;

// Close a session
- (void)closeSession:(PTYSession*)aSession;

// Close a session but don't kill the underlying window pane if it's a tmux session.
- (void)softCloseSession:(PTYSession *)aSession;

// Select the tab to the right of the foreground tab.
- (void)nextTab:(id)sender;

// Select the tab to the left of the foreground tab.
- (void)previousTab:(id)sender;

// Add a tab with the same panes and profiles.
- (void)createDuplicateOfTab:(PTYTab *)theTab;

// Set background color for tab chrome.
- (void)updateTabColors;

// Set blur radius for window.
- (void)enableBlur:(double)radius;

// Disable blur for window.
- (void)disableBlur;

// Force the window size to change to be just large enough to fit this session.
- (void)fitWindowToTab:(PTYTab*)tab;

// Accessor for window's tab view.
- (PTYTabView *)tabView;

// accessor for foreground session.
- (PTYSession *)currentSession;

// Set the window title to the name of the current session.
- (void)setWindowTitle;

// Return the foreground tab
- (PTYTab*)currentTab;

// Kill tmux window if applicable, or close a tab and resize/close the window if needed.
- (void)closeTab:(PTYTab*)theTab;

// WindowControllerInterface protocol
- (void)windowSetFrameTopLeftPoint:(NSPoint)point;
- (void)windowPerformMiniaturize:(id)sender;
- (void)windowDeminiaturize:(id)sender;
- (void)windowOrderFront:(id)sender;
- (void)windowOrderBack:(id)sender;
- (BOOL)windowIsMiniaturized;
- (NSRect)windowFrame;
- (NSScreen*)windowScreen;

// Indicates if the scroll bar should be shown.
- (BOOL)scrollbarShouldBeVisible;

// Gives the type of scroller to use.
- (NSScrollerStyle)scrollerStyle;

@end

// The full interface for a window controller, as seen by objects that treat it
// like a delegate.
@protocol iTermWindowController <WindowControllerInterface, PTYTabDelegate>

// Is the toolbelt visible for this window?
@property(nonatomic, readonly) BOOL shouldShowToolbelt;
@property(nonatomic, readonly) NSArray *tabs;
@property(nonatomic, readonly) BOOL windowIsResizing;
@property(nonatomic, readonly) BOOL closing;

#pragma mark - Basics

// Get term number
- (int)number;

// Underlying window
- (NSWindow *)window;
- (iTermTerminalWindow *)ptyWindow;

// Unique identifier
- (NSString *)terminalGuid;

// For window restoration, take a new snapshot of the current view hierarchy.
- (void)invalidateRestorableState;

// Open a new window with a profile with the specified GUID.
- (void)newWindowWithBookmarkGuid:(NSString*)guid;

// Open a new tab with a profile with the specified GUID.
- (void)newTabWithBookmarkGuid:(NSString*)guid;

// Construct the right-click context menu.
- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu;

// Resize the window to a given pixel size. A nearby size will be used if
// possible, but minimum size constraints will be respected.
- (void)setFrameSize:(NSSize)newSize;

// Is transparency being used?
- (BOOL)useTransparency;

// Increment the badge count, or set it to 1 if there is none.
- (void)incrementBadge;

// For scripting.
- (NSScriptObjectSpecifier *)objectSpecifier;

// Last time the window was resized.
- (NSDate *)lastResizeTime;

// The current mode for broadcasting of input.
- (BroadcastMode)broadcastMode;
- (void)setBroadcastMode:(BroadcastMode)mode;
- (NSArray<PTYSession *> *)broadcastSessions;

// Returns true if the window is in 10.7-style fullscreen.
- (BOOL)lionFullScreen;

// Get the window type
- (iTermWindowType)windowType;

// Returns a new terminal at the given screen coordinate. The
// "wasDraggedFromAnotherWindow_" flag is set on the returned window.
- (NSWindowController<iTermWindowController> *)terminalDraggedFromAnotherWindowAtPoint:(NSPoint)point;

// Session terminated. Remove any weak refs to it.
- (void)sessionDidTerminate:(PTYSession *)session;

// Pop the current session out and move it into its own window.
- (void)moveSessionToWindow:(id)sender;
- (void)moveSessionToTab:(id)sender;

// Show or hide this window's toolbelt.
- (IBAction)toggleToolbeltVisibility:(id)sender;

- (void)popupWillClose:(iTermPopupWindowController *)popup;

- (void)toggleFullScreenMode:(id)sender;

- (void)toggleFullScreenMode:(id)sender
                  completion:(void (^)(BOOL))completion;

// Is the window title transient?
- (void)clearTransientTitle;
- (BOOL)isShowingTransientTitle;

- (void)currentSessionWordAtCursorDidBecome:(NSString *)word;

- (void)storeWindowStateInRestorableSession:(iTermRestorableSession *)restorableSession;

- (PTYSession *)syntheticSessionForSession:(PTYSession *)oldSession;

#pragma mark - Tabs

// Close a tab and resize/close the window if needed.
- (void)removeTab:(PTYTab *)aTab;

// Move tabs within ordering.
- (void)moveTabLeft:(id)sender;
- (void)moveTabRight:(id)sender;

// Increase and Decrease
- (void)increaseHeight:(id)sender;
- (void)decreaseHeight:(id)sender;
- (void)increaseWidth:(id)sender;
- (void)decreaseWidth:(id)sender;

- (void)increaseHeightOfSession:(PTYSession *)session;
- (void)decreaseHeightOfSession:(PTYSession *)session;
- (void)increaseWidthOfSession:(PTYSession *)session;
- (void)decreaseWidthOfSession:(PTYSession *)session;

// If soft is true, don't kill tmux session. Otherwise is just like closeTab.
- (void)closeTab:(PTYTab *)aTab soft:(BOOL)soft;

// Accessor for tab bar.
- (PSMTabBarControl*)tabBarControl;

// Return the number of tabs in this window.
- (int)numberOfTabs;

// Adds a tab to the end.
- (void)appendTab:(PTYTab*)aTab;

// Adds tab at end or next to current tab depending on settings.
- (void)addTabAtAutomaticallyDeterminedLocation:(PTYTab *)tab;

// Fit the window to exactly fit a tab of the given size. Returns true if the
// window was resized.
- (BOOL)fitWindowToTabSize:(NSSize)tabSize;

// Return the index of a tab or NSNotFound.
- (NSInteger)indexOfTab:(PTYTab*)aTab;

// Insert a tab at a specified location.
- (void)insertTab:(PTYTab*)aTab atIndex:(int)anIndex;

// Add a session to the tab view.
- (PTYTab *)insertSession:(PTYSession *)aSession atIndex:(int)anIndex;

// Resize window to be just large enough to fit the largest tab without
// changing session sizes.
- (void)fitWindowToTabs;

- (void)tabActiveSessionDidChange;

// Returns the tab associated with a session.
- (PTYTab *)tabForSession:(PTYSession *)session;

- (void)tabTitleDidChange:(PTYTab *)tab;

- (void)tabAddSwiftyStringsToGraph:(iTermSwiftyStringGraph *)graph;

- (void)tabSessionDidChangeTransparency:(PTYTab *)tab;

#pragma mark - Sessions

// Set the session name. If theSessionName is nil then set it to the pathname
// or "Finish" if it's closed.
- (void)setName:(NSString *)theSessionName forSession:(PTYSession*)aSession;

// Return the window title, minus it number, bell, etc.
- (NSString *)undecoratedWindowTitle;

// Show the pref panel for the current session, divorcing it from its profile.
- (void)editSession:(PTYSession*)session makeKey:(BOOL)makeKey;

// Close a session if the user agrees to a modal alert.
- (void)closeSessionWithConfirmation:(PTYSession *)aSession;

// Restart a session if the user agrees to a modal alert.
- (void)restartSessionWithConfirmation:(PTYSession *)aSession;

// Update sessions' dimming status.
- (void)setDimmingForSessions;

// All sessions in this window.
- (NSArray*)allSessions;

// Do some cleanup after a session is removed.
- (void)sessionWasRemoved;

// Make the window fore (opening the hotkey window if needed), select the right tab, and activate the
// session. Does nothing if the session does not belong to this window.
- (void)makeSessionActive:(PTYSession *)session;

// Pane navigation
- (void)selectPaneLeft:(id)sender;
- (void)selectPaneRight:(id)sender;
- (void)selectPaneUp:(id)sender;
- (void)selectPaneDown:(id)sender;

- (void)swapPaneLeft;
- (void)swapPaneRight;
- (void)swapPaneUp;
- (void)swapPaneDown;

// Enable or disable transparency support for a window.
- (void)toggleUseTransparency:(id)sender;

- (void)openPasswordManagerToAccountName:(NSString *)name inSession:(PTYSession *)session;

- (void)tabDidClearScrollbackBufferInSession:(PTYSession *)session;

#pragma mark - Instant replay

// Begin instant replay on a session.
- (void)replaySession:(PTYSession *)oldSession;

// End instant replay, subbing in a live session for the fake IR session.
- (void)showLiveSession:(PTYSession*)liveSession
              inPlaceOf:(PTYSession*)replaySession;

// Is the window currently in IR mode?
- (BOOL)inInstantReplay;

// Hide the IR bar and end instant replay.
- (BOOL)closeInstantReplay:(id)sender orTerminateSession:(BOOL)orTerminateSession;

// Step forward/back in IR.
- (void)irPrev:(id)sender;
- (void)irNext:(id)sender;

// Toggle the visibility of IR.
- (void)showHideInstantReplay;

// Exit a synthetic view (a generalized version of an IR session).
- (void)replaceSyntheticActiveSessionWithLiveSessionIfNeeded;

#pragma mark - Broadcast

// Indicates if a session participates in input broadcasting.
- (BOOL)broadcastInputToSession:(PTYSession *)session;

// Toggles broadcasting to a single session.
- (void)toggleBroadcastingInputToSession:(PTYSession *)session;

// Call writeTask: for each session's shell with the given data.
- (void)sendInputToAllSessions:(NSString *)string
                      encoding:(NSStringEncoding)optionalEncoding
                 forceEncoding:(BOOL)forceEncoding;

- (iTermRestorableSession *)restorableSessionForSession:(PTYSession *)session;

#pragma mark - Tmux

// Returns the size of the window (in characters) that is the smallest width of
// any tab and smallest height of any tab.
- (NSSize)tmuxCompatibleSize;

// Increment the count of tmux originated resizes in progress.
- (void)beginTmuxOriginatedResize;

// Decrement the count of tmux originated resizes in progress.
- (void)endTmuxOriginatedResize;

// Fit the window to the tabs after a tmux layout change. A change is trivial
// if views are resized but the view hierarchy is not changed.
- (void)tmuxTabLayoutDidChange:(BOOL)nontrivialChange
                           tab:(PTYTab *)tab
            variableWindowSize:(BOOL)variableWindowSize;

// Returns an array of unique tmux controllers present in this window.
- (NSArray *)uniqueTmuxControllers;

// Opens a new tmux tab. window gives the tmux window id. name gives the new
// window title.
- (void)loadTmuxLayout:(NSMutableDictionary *)parseTree
         visibleLayout:(NSMutableDictionary *)visibleParseTree
                window:(int)window
        tmuxController:(TmuxController *)tmuxController
                  name:(NSString *)name;

#pragma mark - Splits

// Create a new split with a specified bookmark. `targetSession` is the session
// to split.
- (void)asyncSplitVertically:(BOOL)isVertical
                      before:(BOOL)before
                     profile:(Profile *)theBookmark
               targetSession:(PTYSession *)targetSession
                  completion:(void (^)(PTYSession *, BOOL ok))completion
                       ready:(void (^)(PTYSession *, BOOL ok))ready;

// Create a new split with the specified bookmark. The passed-in session is
// inserted either before (left/above) or after (right/below) the target
// session. If performSetup is set, then setupSession:withSize: is
// called.
- (void)splitVertically:(BOOL)isVertical
                 before:(BOOL)before
          addingSession:(PTYSession*)newSession
          targetSession:(PTYSession*)targetSession
           performSetup:(BOOL)performSetup;
// Indicates if the current session can be split.
- (BOOL)canSplitPaneVertically:(BOOL)isVertical withBookmark:(Profile*)theBookmark;

// Indicates if this a hotkey window.
- (BOOL)isHotKeyWindow;

// Is this a "floating" hotkey window? These sit in nonactivating panels with a high window level.
- (BOOL)isFloatingHotKeyWindow;

- (void)sessionHostDidChange:(PTYSession *)session to:(id<VT100RemoteHostReading>)host;

#pragma mark - Command history

// Remove the ACH window. It won't come back until showAutoCommandHistoryForSession is called.
- (void)hideAutoCommandHistoryForSession:(PTYSession *)session;

// Should updateAutoCommandHistoryForPrefix:inSession:popIfNeeded: be called?
- (BOOL)wantsCommandHistoryUpdatesFromSession:(PTYSession *)session;

// Set the current command prefix for a given session, updating the ACH window
// if open. If it was shown with showAutoCommandHistoryForSession but then
// taken offscreen because there were no entries, this may cause it to return
// to visibility. It won't return to visibility if
// hideAutoCommandHistoryForSession was called.
- (void)updateAutoCommandHistoryForPrefix:(NSString *)prefix inSession:(PTYSession *)session popIfNeeded:(BOOL)popIfNeeded;

// Show the ACH window. Follow up with a call to updateAutoCommandHistoryForPrefix.
- (void)showAutoCommandHistoryForSession:(PTYSession *)session;

// Indicates if the ACH window is shown and visible for |session|.
- (BOOL)autoCommandHistoryIsOpenForSession:(PTYSession *)session;
- (BOOL)commandHistoryIsOpenForSession:(PTYSession *)session;
- (void)closeCommandHistory;

- (void)openCommandHistory:(id)sender;
- (void)openCommandHistoryWithPrefix:(NSString *)prefix sortChronologically:(BOOL)sortChronologically;
- (void)nextMark:(id)sender;
- (void)previousMark:(id)sender;

@end
