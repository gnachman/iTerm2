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
#import "iTermRestorableSession.h"
#import "PTYWindow.h"

typedef NS_ENUM(NSUInteger, iTermHotkeyWindowType) {
    iTermHotkeyWindowTypeNone,
    iTermHotkeyWindowTypeRegular,
    iTermHotkeyWindowTypeFloatingPanel,  // joins all spaces and has a higher level than a regular window. Is an NSPanel.
    iTermHotkeyWindowTypeFloatingWindow  // has a higher level than a regular window.
};

#define kApplicationDidFinishLaunchingNotification @"kApplicationDidFinishLaunchingNotification"

@protocol iTermWindowController;
@class iTermRestorableSession;
@class PasteboardHistory;
@class PseudoTerminal;
@class PTYSession;
@class PTYTab;
@class PTYTextView;

@interface iTermController : NSObject

@property(nonatomic, readonly) iTermRestorableSession *currentRestorableSession;
@property(nonatomic, assign) BOOL selectionRespectsSoftBoundaries;
@property(nonatomic, assign) BOOL startingUp;
@property(nonatomic, assign) BOOL applicationIsQuitting;
@property(nonatomic, readonly) BOOL willRestoreWindowsAtNextLaunch;
@property(nonatomic, readonly) BOOL shouldLeaveSessionsRunningOnQuit;
@property(nonatomic, readonly) BOOL haveTmuxConnection;
@property(nonatomic, readonly, strong) PTYSession *sessionWithMostRecentSelection;
@property(nonatomic, nonatomic, assign) PseudoTerminal *currentTerminal;
@property(nonatomic, readonly) int numberOfTerminals;
@property(nonatomic, readonly) BOOL hasRestorableSession;
@property(nonatomic, readonly) BOOL keystrokesBeingStolen;
@property(nonatomic, readonly) BOOL anyWindowIsMain;
@property(nonatomic, readonly) NSArray<iTermTerminalWindow *> *keyTerminalWindows;

+ (iTermController*)sharedInstance;
+ (void)releaseSharedInstance;

+ (void)switchToSpaceInBookmark:(NSDictionary*)aDict;

// actions are forwarded from application
- (IBAction)newWindow:(id)sender;
- (void)newWindow:(id)sender possiblyTmux:(BOOL)possiblyTmux;
- (void)newSessionWithSameProfile:(id)sender;
- (void)newSession:(id)sender possiblyTmux:(BOOL)possiblyTmux;
- (void)previousTerminal;
- (void)nextTerminal;
- (void)newSessionsInWindow:(id)sender;
- (void)newSessionsInNewWindow:(id)sender;
- (void)launchScript:(id)sender;

- (void)arrangeHorizontally;
- (void)newSessionInTabAtIndex:(id)sender;
- (void)newSessionInWindowAtIndex:(id)sender;
- (PseudoTerminal*)keyTerminalWindow;
- (PTYSession *)anyTmuxSession;


- (PseudoTerminal*)terminalWithNumber:(int)n;
- (PseudoTerminal *)terminalWithGuid:(NSString *)guid;
- (int)allocateWindowNumber;

- (void)saveWindowArrangement:(BOOL)allWindows;
- (void)loadWindowArrangementWithName:(NSString *)theName;

- (void)terminalWillClose:(PseudoTerminal*)theTerminalWindow;
- (void)addBookmarksToMenu:(NSMenu *)aMenu
              withSelector:(SEL)selector
           openAllSelector:(SEL)openAllSelector
                startingAt:(int)startingAt;

// Does not enter fullscreen automatically; that is left to the caller, since tmux has special
// logic around this. Call -didFinishCreatingTmuxWindow: after it is doing being set up.
- (PseudoTerminal *)openTmuxIntegrationWindowUsingProfile:(Profile *)profile;

// This is called when the window created by -openTmuxIntegrationWindowUsingProfile is done being initialized.
- (void)didFinishCreatingTmuxWindow:(PseudoTerminal *)windowController;

// Super-flexible way to create a new window or tab. If |block| is given then it is used to add a
// new session/tab to the window; otherwise the bookmark is used in conjunction with the optional
// URL.
- (PTYSession *)launchBookmark:(Profile *)bookmarkData
                    inTerminal:(PseudoTerminal *)theTerm
                       withURL:(NSString *)url
              hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
                       makeKey:(BOOL)makeKey
                   canActivate:(BOOL)canActivate
                       command:(NSString *)command
                         block:(PTYSession *(^)(PseudoTerminal *))block;
- (PTYSession *)launchBookmark:(Profile *)profile inTerminal:(PseudoTerminal *)theTerm;
- (PTYTextView*)frontTextView;
- (PseudoTerminal*)terminalAtIndex:(int)i;
- (PseudoTerminal *)terminalForWindow:(NSWindow *)window;
- (void)irAdvance:(int)dir;
- (NSUInteger)indexOfTerminal:(PseudoTerminal*)terminal;

- (void)dumpViewHierarchy;

- (iTermWindowType)windowTypeForBookmark:(Profile*)aDict;

- (void)reloadAllBookmarks;
- (Profile *)defaultBookmark;

- (PseudoTerminal *)terminalWithTab:(PTYTab *)tab;
- (PseudoTerminal *)terminalWithSession:(PTYSession *)session;

// Indicates a rough guess as to whether a terminal window is substantially visible.
// Being on another space will count as being obscured.
// On OS 10.9+, if the window is completely covered by another app's window, it's obscured.
// If other iTerm windows cover more than ~40% of |terminal| then it's obscured.
- (BOOL)terminalIsObscured:(id<iTermWindowController>)terminal;

// Set Software Update (Sparkle) user defaults keys to reflect settings in
// iTerm2's user defaults.
- (void)refreshSoftwareUpdateUserDefaults;

- (void)addRestorableSession:(iTermRestorableSession *)session;
- (void)removeSessionFromRestorableSessions:(PTYSession *)session;
- (iTermRestorableSession *)popRestorableSession;
- (void)commitAndPopCurrentRestorableSession;
- (void)pushCurrentRestorableSession:(iTermRestorableSession *)session;
- (void)killRestorableSessions;

- (NSArray<PseudoTerminal *> *)terminals;
- (void)addTerminalWindow:(PseudoTerminal *)terminalWindow;

void OnHotKeyEvent(void);

// Does a serialized fullscreening of the term's window. Slated for production in 3.1.
- (void)makeTerminalWindowFullScreen:(NSWindowController<iTermWindowController> *)term;

@end

