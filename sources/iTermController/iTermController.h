/*
 **  iTermController.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **          Initial code by Kiichi Kusama
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

#import <Cocoa/Cocoa.h>
#import "ITAddressBookMgr.h"
#import "iTermOpenStyle.h"
#import "iTermRestorableSession.h"
#import "PTYWindow.h"

typedef NS_ENUM(NSUInteger, iTermHotkeyWindowType) {
    iTermHotkeyWindowTypeNone,
    iTermHotkeyWindowTypeRegular,
    iTermHotkeyWindowTypeFloatingPanel,  // joins all spaces and has a higher level than a regular window. Is an NSPanel.
    iTermHotkeyWindowTypeFloatingWindow  // has a higher level than a regular window.
};

extern NSString *const iTermSnippetsTagsDidChange;

@protocol iTermWindowController;
@class iTermRenegablePromise<T>;
@class iTermRestorableSession;
@class iTermSavePanelItem;
@class PasteboardHistory;
@class PseudoTerminal;
@class PTYSession;
@class PTYTab;
@class PTYTextView;
@class TmuxController;
@class WKWebView;
@class WKWebViewConfiguration;

@interface iTermController : NSObject

@property(nonatomic, readonly) iTermRestorableSession *currentRestorableSession;
@property(nonatomic, assign) BOOL selectionRespectsSoftBoundaries;
@property(nonatomic, assign) BOOL startingUp;
@property(nonatomic, assign) BOOL applicationIsQuitting;
@property(nonatomic, readonly) BOOL willRestoreWindowsAtNextLaunch;
@property(nonatomic, readonly) BOOL shouldLeaveSessionsRunningOnQuit;
@property(nonatomic, readonly) BOOL haveTmuxConnection;
@property(nonatomic, nonatomic, assign) PseudoTerminal *currentTerminal;
@property(nonatomic, readonly) int numberOfTerminals;
@property(nonatomic, readonly) BOOL hasRestorableSession;
@property(nonatomic, readonly) BOOL keystrokesBeingStolen;
@property(nonatomic, readonly) BOOL anyWindowIsMain;
@property(nonatomic, readonly) NSArray<iTermTerminalWindow *> *keyTerminalWindows;
@property(nonatomic, readonly) NSInteger numberOfDecodesPending;
@property(nonatomic, strong) iTermRenegablePromise<NSString *> *lastSelectionPromise;

+ (iTermController*)sharedInstance;
+ (void)releaseSharedInstance;

+ (void)switchToSpaceInBookmark:(NSDictionary*)aDict;

// actions are forwarded from application
- (IBAction)newWindow:(id)sender;
- (void)newWindow:(id)sender possiblyTmux:(BOOL)possiblyTmux;
- (void)newSessionWithSameProfile:(id)sender newWindow:(BOOL)newWindow;
- (void)newSession:(id)sender possiblyTmux:(BOOL)possiblyTmux index:(NSNumber *)index;
- (void)previousTerminal;
- (void)nextTerminal;
- (void)newSessionsInWindow:(id)sender;
- (void)newSessionsInNewWindow:(id)sender;

- (void)arrangeHorizontally;
- (void)newSessionInTabAtIndex:(id)sender;
- (void)newSessionInWindowAtIndex:(id)sender;
- (PseudoTerminal*)keyTerminalWindow;
- (PTYSession *)anyTmuxSession;


- (PseudoTerminal*)terminalWithNumber:(int)n;
- (PseudoTerminal *)terminalWithGuid:(NSString *)guid;
- (PTYTab *)tabWithID:(NSString *)tabID;  // short numeric ID
- (PTYTab *)tabWithGUID:(NSString *)guid;  // UUID
- (PseudoTerminal *)windowForSessionWithGUID:(NSString *)guid;
- (PTYTab *)tabForSession:(PTYSession *)session;
- (PseudoTerminal *)windowForTab:(PTYTab *)tab;
- (PseudoTerminal *)windowForSession:(PTYSession *)session;

- (int)allocateWindowNumber;

- (void)saveWindowArrangement:(BOOL)allWindows;
- (void)saveWindowArrangementForAllWindows:(BOOL)allWindows name:(NSString *)name saveItem:(iTermSavePanelItem *)saveItem;
- (void)saveWindowArrangementForWindow:(PseudoTerminal *)currentTerminal name:(NSString *)name saveItem:(iTermSavePanelItem *)saveItem;

- (void)loadWindowArrangementWithName:(NSString *)theName;
- (BOOL)loadWindowArrangementWithName:(NSString *)theName asTabsInTerminal:(PseudoTerminal *)term;

// Load from file, including contents
- (void)importWindowArrangementAtPath:(NSString *)path asTabsInTerminal:(PseudoTerminal *)term;

- (BOOL)arrangementWithName:(NSString *)arrangementName
         hasSessionWithGUID:(NSString *)guid
                        pwd:(NSString *)pwd;

- (void)repairSavedArrangementNamed:(NSString *)savedArrangementName
               replacingMissingGUID:(NSString *)guidToReplace
                           withGUID:(NSString *)replacementGuid;

- (void)repairSavedArrangementNamed:(NSString *)arrangementName
replaceInitialDirectoryForSessionWithGUID:(NSString *)guid
                               with:(NSString *)replacementOldCWD;

- (void)tryOpenArrangement:(NSDictionary *)terminalArrangement
                     named:(NSString *)arrangementName
            asTabsInWindow:(PseudoTerminal *)term;

- (void)terminalWillClose:(PseudoTerminal*)theTerminalWindow;
- (void)addBookmarksToMenu:(NSMenu *)aMenu
                 supermenu:(NSMenu *)supermenu
              withSelector:(SEL)selector
           openAllSelector:(SEL)openAllSelector
                startingAt:(int)startingAt;

// Does not enter fullscreen automatically; that is left to the caller, since tmux has special
// logic around this. Call -didFinishCreatingTmuxWindow: after it is doing being set up.
- (PseudoTerminal *)openTmuxIntegrationWindowUsingProfile:(Profile *)profile
                                         perWindowSetting:(NSString *)perWindowSetting
                                           tmuxController:(TmuxController *)tmuxController;

// This is called when the window created by -openTmuxIntegrationWindowUsingProfile is done being initialized.
- (void)didFinishCreatingTmuxWindow:(PseudoTerminal *)windowController;

- (PseudoTerminal *)windowControllerForNewTabWithProfile:(Profile *)profile
                                               candidate:(PseudoTerminal *)preferredWindowController
                                      respectTabbingMode:(BOOL)respectTabbingMode;

- (PTYTextView*)frontTextView;
- (NSResponder *)frontMainResponder;
- (PseudoTerminal*)terminalAtIndex:(int)i;
- (PseudoTerminal *)terminalForWindow:(NSWindow *)window;
- (void)irAdvance:(int)dir;
- (NSUInteger)indexOfTerminal:(PseudoTerminal*)terminal;

- (void)dumpViewHierarchy;

- (iTermWindowType)windowTypeForBookmark:(Profile*)aDict percentage:(iTermPercentage *)percentage;

- (void)reloadAllBookmarks;
- (Profile *)defaultBookmark;

- (PseudoTerminal *)terminalWithTab:(PTYTab *)tab;
- (PseudoTerminal *)terminalWithSession:(PTYSession *)session;

// Set Software Update (Sparkle) user defaults keys to reflect settings in
// iTerm2's user defaults.
- (void)refreshSoftwareUpdateUserDefaults;

- (void)addRestorableSession:(iTermRestorableSession *)session;
- (void)removeSessionFromRestorableSessions:(PTYSession *)session;
- (iTermRestorableSession *)popRestorableSession;
- (void)commitAndPopCurrentRestorableSession;
- (void)pushCurrentRestorableSession:(iTermRestorableSession *)session;
- (void)killRestorableSessions;

- (NSArray<PTYSession *> *)allSessions;
- (NSArray<PseudoTerminal *> *)terminals;
- (void)addTerminalWindow:(PseudoTerminal *)terminalWindow;
- (PTYSession *)sessionWithGUID:(NSString *)identifier;

// Where -enumerateSessionLookupLocations: found a session. Declared
// in search-precedence order: in-tab sessions win over buried ones,
// which win over sessions reachable only through a peer port; the
// workgroup registry's ports come last because they cover sessions no
// in-tab or buried member can reach (a workgroup whose realized
// members are all windowless and unburied).
typedef NS_ENUM(NSInteger, iTermSessionLookupLocation) {
    iTermSessionLookupLocationTab,
    iTermSessionLookupLocationBuried,
    iTermSessionLookupLocationTabPeerPort,
    iTermSessionLookupLocationBuriedPeerPort,
    iTermSessionLookupLocationWorkgroupRegistryPort,
};

// The single authority on every place a live PTYSession can be found.
// Yields each session (possibly more than once — a peer can be both
// in a tab and in its port) with the location it was found in, in
// precedence order. Consumed by -anySessionWithGUID: (and through it
// -revealSessionWithGUID:) and the unresolvable-session diagnosis
// dump, so the GUID lookup and its diagnosis search the same set of
// places and cannot drift from each other.
- (void)enumerateSessionLookupLocations:(void (^NS_NOESCAPE)(PTYSession *session,
                                                             iTermSessionLookupLocation location,
                                                             BOOL *stop))block;

// Like -sessionWithGUID: but also finds (a) buried sessions and
// (b) workgroup peers reachable through any in-tab or buried
// session's peer port or through the workgroup registry's ports. Use
// this when the caller needs a stable handle on a session regardless
// of whether it's currently visible in a tab — e.g. the Session
// Status toolbelt, which displays rows for buried/non-visible peers
// and needs to resolve them to a PTYSession to render the row or
// activate the peer on click. Peers can be invisible to both
// -sessionWithGUID: and iTermBuriedSessions (the addBuriedSession
// path silently drops sessions when restorableSessionForSession
// returns nil), but their peer port still holds a strong reference,
// which is why the peer-port legs matter.
- (PTYSession *)anySessionWithGUID:(NSString *)identifier;

// sessionID is of the form "w0t0p0:guid"
- (void)revealSessionID:(NSString *)sessionID;
- (void)revealSessionWithGUID:(NSString *)guid;

// Gives a windowless, unburied session a home: a tab of the frontmost
// non-hotkey terminal window, or a fresh window of the user's default
// type when no suitable window exists. Used by -[PTYSession reveal] to
// surface workgroup members reachable only through the workgroup
// registry.
- (void)reviveSessionIntoWindow:(PTYSession *)session;

// The shared create-window-and-revive tail: makes a window with the
// given geometry, registers it, applies `terminalGuid` when non-nil
// (the buried-restore path preserves the saved window's identity),
// adds `session` as a revived tab, and fits the window. Returns the
// new window controller, or nil if creation failed. Callers layer
// their own restorable-state extras (window title, fullscreen) on the
// result.
- (PseudoTerminal *)reviveSession:(PTYSession *)session
              inNewWindowWithType:(iTermWindowType)windowType
                  savedWindowType:(iTermWindowType)savedWindowType
                       percentage:(iTermPercentage)percentage
                           screen:(int)screen
                     terminalGuid:(NSString *)terminalGuid;

void OnHotKeyEvent(void);

// Does a serialized fullscreening of the term's window. Slated for production in 3.1.
- (void)makeTerminalWindowFullScreen:(NSWindowController<iTermWindowController> *)term;

typedef NS_OPTIONS(NSUInteger, iTermSingleUseWindowOptions) {
    iTermSingleUseWindowOptionsNone = 0,
    // Treat the session as short-lived: it will not post a notification when it ends and it can be closed while buried.
    iTermSingleUseWindowOptionsShortLived = (1 << 0),
    // Override the default profile's close on termination  setting to always close on termination.
    iTermSingleUseWindowOptionsCloseOnTermination = (1 << 1),
    // Bury it immediately?
    iTermSingleUseWindowOptionsInitiallyBuried = (1 << 2),
    // Don't escape arguments
    iTermSingleUseWindowOptionsDoNotEscapeArguments = (1 << 3),
    // Command is not a swifty string
    iTermSingleUseWindowOptionsCommandNotSwiftyString = (1 << 4)
};

// Note that `command` is a Swifty string.
- (void)openSingleUseWindowWithCommand:(NSString *)command
                             arguments:(NSArray<NSString *> *)arguments
                                inject:(NSData *)injection
                           environment:(NSDictionary *)environment
                                   pwd:(NSString *)initialPWD
                               options:(iTermSingleUseWindowOptions)options
                        didMakeSession:(void (^)(PTYSession *session))didMakeSession
                            completion:(void (^)(void))completion;

// Note that `rawCommand` is a plain old string, not a Swifty string.
- (void)openSingleUseWindowWithCommand:(NSString *)rawCommand
                                inject:(NSData *)injection
                           environment:(NSDictionary *)environment
                                   pwd:(NSString *)initialPWD
                               options:(iTermSingleUseWindowOptions)options
                        didMakeSession:(void (^)(PTYSession *session))didMakeSession
                            completion:(void (^)(void))completion;
- (NSWindow *)openSingleUseLoginWindowAndWrite:(NSData *)data completion:(void (^)(PTYSession *session))completion;

- (BOOL)openURL:(NSURL *)url
         target:(NSString *)target
      openStyle:(iTermOpenStyle)openStyle
         select:(BOOL)select;
- (WKWebView *)openSingleUserBrowserWindowWithURL:(NSURL *)url
                                    configuration:(WKWebViewConfiguration *)configuration
                                          options:(iTermSingleUseWindowOptions)options
                                       completion:(void (^)(void))completion NS_AVAILABLE_MAC(11);

- (NSWindow *)openWindow:(BOOL)makeWindow
                 command:(NSString *)command
             initialText:(NSString *)initialText
               directory:(NSString *)directory
                hostname:(NSString *)hostname
                username:(NSString *)username;

- (NSArray<NSString *> *)currentSnippetsFilter;

@end

