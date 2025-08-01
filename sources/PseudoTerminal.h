#import <Cocoa/Cocoa.h>

#import "Autocomplete.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTermAPIHelper.h"
#import "iTermBroadcastInputHelper.h"
#import "iTermController.h"
#import "iTermInstantReplayWindowController.h"
#import "iTermPresentationController.h"
#import "iTermPopupWindowController.h"
#import "iTermToolbeltView.h"
#import "iTermWeakReference.h"
#import "PasteboardHistory.h"
#import "ProfileListView.h"
#import "PSMTabBarControl.h"
#import "PTYTabView.h"
#import "PTYWindow.h"
#import "WindowControllerInterface.h"
#import "iTermSessionRestorationStatusProtocol.h"

#include "iTermFileDescriptorClient.h"

@class PTYSession;
@class PSMTabBarControl;
@class iTermPromptOnCloseReason;
@class iTermSessionFactory;
@class iTermToolbeltView;
@protocol iTermWindowScope;
@class iTermController;
@class iTermTerminalWindowSizeHelper;
@class PseudoTerminalState;
@class TmuxController;
@class WKWebViewConfiguration;

// Posted when a new window controller is created. It's not ready to use at this point, though.
extern NSString *const kTerminalWindowControllerWasCreatedNotification;

extern NSString *const kCurrentSessionDidChange;

extern NSString *const iTermDidDecodeWindowRestorableStateNotification;

extern NSString *const iTermTabDidChangePositionInWindowNotification;

extern NSString *const iTermSelectedTabDidChange;
extern NSString *const iTermWindowDidCloseNotification;
extern NSString *const iTermTabDidCloseNotification;
extern NSString *const iTermDidCreateTerminalWindowNotification;

// This class is 1:1 with windows. It controls the tabs, the window's fullscreen
// status, and coordinates resizing of sessions (either session-initiated
// or window-initiated).
@interface PseudoTerminal : NSWindowController <
  iTermInstantReplayDelegate,
  iTermPresentationControllerManagedWindowController,
  iTermSubscribable,
  iTermWeaklyReferenceable,
  iTermWindowController,
  NSWindowDelegate,
  PSMTabBarControlDelegate,
  PSMTabViewDelegate,
  PTYWindowDelegateProtocol,
  WindowControllerInterface>

// Is this window in the process of becoming fullscreen?
// Used to make restoring fullscreen windows work on 10.11.
- (BOOL)togglingLionFullScreen;

// What kind of hotkey window this is, if any.
@property(nonatomic, assign) iTermHotkeyWindowType hotkeyWindowType;

// A unique string for this window. Used for tmux to remember which window
// a tmux window should be opened in as a tab. A window restored from a
// saved arrangement will also restore its guid. Also used for restoring sessions via "Undo" into
// the window they were originally in. Assignable because when you undo closing a window, the guid
// needs to be restored.
@property(nonatomic, copy) NSString *terminalGuid;

// Indicates if the window is fully initialized.
@property(nonatomic, readonly) BOOL windowInitialized;

// If the window is "anchored" to a screen, this returns that screen. Otherwise, it returns the
// current screen. If the window doesn't have a current screen, it returns the
// preferred screen from the profile. If headless, this returns nil. Consider
// this the preferred screen.
@property(nonatomic, readonly) NSScreen *screen;

// Are we in the process of restoring a window with NSWindowRestoration? If so, do not order
// the window as it may be minimized (issue 5258)
@property(nonatomic) BOOL restoringWindow;

// Set to YES when the window has been created but window:didDecodeRestorableState: hasn't been
// called yet.
@property(nonatomic) BOOL restorableStateDecodePending;

// Used only by hotkey windows. Indicate if it should move to the active space when opening.
@property (nonatomic, readonly) iTermProfileSpaceSetting spaceSetting;

@property(nonatomic, readonly) BOOL hasBeenKeySinceActivation;

@property(nonatomic, readonly) iTermSessionFactory *sessionFactory;
@property(nonatomic, readonly) int number;
@property(nonatomic, readonly) Profile *initialProfile;
@property(nonatomic, readonly) iTermVariableScope<iTermWindowScope> *scope;
@property(nonatomic, readonly) NSWindowCollectionBehavior desiredWindowCollectionBehavior;
@property(nonatomic, readonly) BOOL isReplacingWindow;
@property(nonatomic, readonly) BOOL closing;
@property(nonatomic, strong) iTermPromise *fullScreenPromise;
@property(nonatomic, strong) id<iTermPromiseSeal> fullScreenEnteredSeal;
@property(nonatomic) BOOL automaticallySelectNewTabs;
@property(nonatomic, readonly) iTermTerminalWindowSizeHelper *windowSizeHelper;

// Draws a mock-up of a window arrangement into the current graphics context.
// |frames| gives an array of NSValue's having NSRect values for each screen,
// giving the screens' coordinates in the model.
+ (void)drawArrangementPreview:(NSDictionary*)terminalArrangement
                  screenFrames:(NSArray *)frames
                          dark:(BOOL)dark;

// Returns a new terminal window restored from an arrangement, but with no
// tabs/sessions. May return nil.
// forceOpeningHotKeyWindow means open the window even if there is already a hotkey window with the
// specified profile, or the arrangement is defective in specifying details of the hotkey window.
+ (PseudoTerminal *)bareTerminalWithArrangement:(NSDictionary *)arrangement
                       forceOpeningHotKeyWindow:(BOOL)force;

// Returns a new terminal window restored from an arrangement, with
// tabs/sessions also restored. May return nil.
// forceOpeningHotKeyWindow means open the window even if there is already a hotkey window with the
// specified profile, or the arrangement is defective in specifying details of the hotkey window.
+ (PseudoTerminal *)terminalWithArrangement:(NSDictionary *)arrangement
                                      named:(NSString *)arrangementName
                   forceOpeningHotKeyWindow:(BOOL)force;

+ (instancetype)terminalWithArrangement:(NSDictionary *)arrangement
                                  named:(NSString *)arrangementName
                               sessions:(NSArray *)sessions
               forceOpeningHotKeyWindow:(BOOL)force;

// Register all sessions in the window's arrangement so their contents can be
// rescued later if the window is created from a saved arrangement. Called
// during state restoration.
+ (void)registerSessionsInArrangement:(NSDictionary *)arrangement;

// If the key window is fullscreen (or is becoming fullscreen) then a new
// normal window will automatically become fullscreen. This has to do with Lion
// fullscreen only.
+ (BOOL)willAutoFullScreenNewWindow;

// Is any window toggling or about to toggle lion fullscreen?
+ (BOOL)anyWindowIsEnteringLionFullScreen;

// Will the arrangement open a Lion fullscreen window?
+ (BOOL)arrangementIsLionFullScreen:(NSDictionary *)arrangement;

+ (void)performWhenWindowCreationIsSafeForLionFullScreen:(BOOL)lionFullScreen
                                                   block:(void (^)(void))block;

// Initialize a new PseudoTerminal.
// smartLayout: If true then position windows using the "smart layout"
//   algorithm.
// windowType: Describes constraints on the window's initial frame and border, and more.
// screen: An index into [NSScreen screens], or -1 to let the system pick a
//   screen.
- (instancetype)initWithSmartLayout:(BOOL)smartLayout
                         windowType:(iTermWindowType)windowType
                    savedWindowType:(iTermWindowType)savedWindowType
                             screen:(int)screenIndex
                            profile:(Profile *)profile;

// isHotkey indicates if this is a hotkey window, which receives special
// treatment and must be unique.
- (instancetype)initWithSmartLayout:(BOOL)smartLayout
                         windowType:(iTermWindowType)windowType
                    savedWindowType:(iTermWindowType)savedWindowType
                             screen:(int)screenNumber
                   hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
                            profile:(Profile *)profile;

// If a PseudoTerminal is created with -init (such as happens with AppleScript)
// this must be called before it is used.
- (void)finishInitializationWithSmartLayout:(BOOL)smartLayout
                                 windowType:(iTermWindowType)windowType
                            savedWindowType:(iTermWindowType)savedWindowType
                                     screen:(int)screenNumber
                                   hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
                                    profile:(Profile *)profile;

- (PTYTab *)tabWithUniqueId:(int)uniqueId;

// Sets the window frame. Value should have an NSRect value.
- (void)setFrameValue:(NSValue *)value;

// The PTYWindow for this controller.
- (__kindof iTermTerminalWindow *)ptyWindow;

// Fix the window frame for fullscreen, top, bottom windows.
- (void)canonicalizeWindowFrame;

// Make the tab at [sender tag] the foreground tab.
- (void)selectSessionAtIndexAction:(id)sender;

// A unique number for this window assigned by finishInitializationWithSmartLayout.
- (NSString *)terminalGuid;

// Miniaturizes the window and marks it as a hide-after-opening window (which
// will be saved in window arrangements).
- (void)hideAfterOpening;

// Is there a saved scroll position?
- (BOOL)hasSavedScrollPosition;

// Set the window title to 'title'.
- (void)setWindowTitle:(NSString *)title subtitle:(NSString *)subtitle;

// Sessions in the broadcast group.
- (NSArray *)broadcastSessions;

// Enter full screen mode in the next mainloop.
- (void)delayedEnterFullscreen;

// Toggle non-Lion fullscreen mode.
- (void)toggleTraditionalFullScreenMode;

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
- (iTermPromptOnCloseReason *)promptOnCloseReason;

// Accessor for toolbelt view.
- (iTermToolbeltView *)toolbelt;

// Tries to grow (or shrink, for negative values) the toolbelt. Returns the amount it was actually
// grown by, in case it hits a limit.
- (CGFloat)growToolbeltBy:(CGFloat)diff;

- (void)refreshTools;

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

// Show or hide as needed for current session.
- (void)showOrHideInstantReplayBar;

// Maximize or unmaximize the active pane
- (void)toggleMaximizeActivePane;

// Return the smallest allowable width for this terminal.
- (float)minWidth;

+ (BOOL)arrangement:(NSDictionary *)arrangement
         passesTest:(BOOL (^NS_NOESCAPE)(NSDictionary *candidate))closure;
+ (NSDictionary *)modifiedArrangement:(NSDictionary *)arrangement
                              mutator:(NSDictionary *(^)(NSDictionary *))mutator;
+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
             replacingProfileWithGUID:(NSString *)badGuid
                          withProfile:(Profile *)goodProfile;
+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
     replacingOldCWDOfSessionWithGUID:(NSString *)guid
                           withOldCWD:(NSString *)replacementOldCWD;
+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
                  settingCustomLocale:(NSString *)lang;
+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
                       profileMutator:(Profile *(^)(Profile *))profileMutator;

+ (NSDictionary *)arrangementForSessionWithGUID:(NSString *)sessionGUID
                            inWindowArrangement:(NSDictionary *)arrangement;

// Load an arrangement into an empty window.
- (BOOL)loadArrangement:(NSDictionary *)arrangement named:(NSString *)arrangementName;

// Load just the tabs into this window.
- (BOOL)restoreTabsFromArrangement:(NSDictionary *)arrangement
                             named:(NSString *)arrangementName
                          sessions:(NSArray<PTYSession *> *)sessions
                partialAttachments:(NSDictionary *)partialAttachments;

// Returns the arrangement for this window.
- (NSDictionary*)arrangement;

// Returns the arrangement for this window, optionally excluding tmux tabs.
- (NSDictionary *)arrangementExcludingTmuxTabs:(BOOL)excludeTmux
                             includingContents:(BOOL)includeContents;

// All tabs in this window.
- (NSArray<PTYTab *> *)tabs;

// Updates the window when screen parameters (number of screens, resolutions,
// etc.) change.
- (void)screenParametersDidChange;

// Changes how input is broadcast.
- (void)setBroadcastMode:(BroadcastMode)mode;
- (void)setBroadcastingSessions:(NSArray<NSArray<PTYSession *> *> *)domains;

// Change split selection mode for all sessions in this window.
- (void)setSplitSelectionMode:(BOOL)mode excludingSession:(PTYSession *)session move:(BOOL)move;

// Use this if it might be a tmux window. The completion block will always be called eventually.
// The ready block is called after the session has started, much like the completion block in
// other session creation calls.
- (void)asyncSplitVertically:(BOOL)isVertical
                      before:(BOOL)before
                     profile:(Profile *)theBookmark
               targetSession:(PTYSession *)targetSession
                  completion:(void (^)(PTYSession *, BOOL ok))completion
                       ready:(void (^)(PTYSession *newSession, BOOL ok))ready;

// Cause every session in this window to reload its bookmark.
- (void)reloadBookmarks;

// Return all sessions in all tabs.
- (NSArray*)allSessions;

// Create a tab. Is async so it can fetch the current working directory without blocking the main
// thread.
- (void)asyncCreateTabWithProfile:(Profile *)profile
                      withCommand:(NSString *)command
                      environment:(NSDictionary *)environment
                         tabIndex:(NSNumber *)tabIndex
                   didMakeSession:(void (^)(PTYSession *session))didMakeSession
                       completion:(void (^)(PTYSession *newSession, BOOL ok))completion;

- (PTYSession *)createTabWithProfile:(Profile *)profile
                         withCommand:(NSString *)command
                         environment:(NSDictionary *)environment
                            tabIndex:(NSNumber *)tabIndex
                   previousDirectory:(NSString *)previousDirectory
                              parent:(PTYSession *)parent
                          completion:(void (^)(PTYSession *, BOOL ok))completion;
- (void)addSession:(PTYSession *)session inTabAtIndex:(NSNumber *)tabIndex;
- (void)customizeCollectionBehaviorForProfile:(Profile *)profile;

- (IBAction)newTmuxWindow:(id)sender;
- (IBAction)newTmuxTab:(id)sender;
- (void)newTmuxTabAtIndex:(NSNumber *)index;
- (NSString *)tmuxPerWindowSetting;
- (void)setTmuxPerWindowSetting:(NSString *)setting
                 tmuxController:(TmuxController *)tmuxController;

// Turn full-screen mode on or off. Creates a new PseudoTerminal and moves this
// one's state into it.
- (IBAction)closeCurrentTab:(id)sender;
- (BOOL)closeTabIfConfirmed:(PTYTab *)tab;
- (BOOL)closeSessionWithConfirmation:(PTYSession *)aSession;
- (void)closeSessionWithoutConfirmation:(PTYSession *)aSession;

- (void)changeTabColorToMenuAction:(id)sender;
- (void)moveSessionToWindow:(id)sender;

- (void)addRevivedSession:(PTYSession *)session;
- (void)addTabWithArrangement:(NSDictionary *)arrangement
                     uniqueId:(int)tabUniqueId
                     sessions:(NSArray *)sessions
                 predecessors:(NSArray *)predecessors;  // NSInteger of tab uniqueId's that come before this tab.
- (void)recreateTab:(PTYTab *)tab
    withArrangement:(NSDictionary *)arrangement
           sessions:(NSArray *)sessions
             revive:(BOOL)revive;

- (IBAction)toggleToolbeltVisibility:(id)sender;

- (void)setupSession:(PTYSession *)aSession
            withSize:(NSSize *)size;

- (NSColor *)accessoryTextColorForMini:(BOOL)mini;

// Update self.screen to reflect the currently preferred screen. In practice,
// this changes self.screen to the screen with the cursor if the window is
// configured to follow it.
- (void)moveToPreferredScreen;

// Returns the preferred frame for the window if it were on a given screen.
- (NSRect)canonicalFrameForScreen:(NSScreen *)screen;

// Swap pane with another in that direction
- (void)swapPaneLeft;
- (void)swapPaneRight;
- (void)swapPaneUp;
- (void)swapPaneDown;


// Returns a restorable session that will restore the split pane, tab, or window, as needed.
- (iTermRestorableSession *)restorableSessionForSession:(PTYSession *)session;

- (void)addSessionInNewTab:(PTYSession *)object;
- (void)didDonateTab:(PTYTab *)aTab toWindowController:(PseudoTerminal *)term;
- (void)moveTabAtIndex:(NSInteger)selectedIndex toIndex:(NSInteger)destinationIndex;

- (PseudoTerminal *)it_moveTabToNewWindow:(PTYTab *)aTab;
- (BOOL)getAndResetRestorableState;
- (void)restoreState:(PseudoTerminalState *)state;
- (void)asyncRestoreState:(PseudoTerminalState *)state
                  timeout:(void (^)(NSArray *))timeout
               completion:(void (^)(void))completion;
- (void)ensureSaneFrame;

- (NSArray<NSString *> *)currentSnippetTags;
- (PTYTextView *)checkFirstResponder;

#pragma mark - Web

- (WKWebView *)openTabWithURL:(NSURL *)url
                  baseProfile:(Profile *)base
              nearSessionGuid:(NSString *)sessionGuid
                configuration:(WKWebViewConfiguration *)configuration NS_AVAILABLE_MAC(11_0);

- (void)openSplitPaneWithURL:(NSURL *)url
                 baseProfile:(Profile *)base
             nearSessionGuid:(NSString *)sessionGuid
                    vertical:(BOOL)vertical;

@end

