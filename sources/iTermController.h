// -*- mode:objc -*-
// $Id: iTermController.h,v 1.29 2008-10-08 05:54:50 yfabian Exp $
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

#define kApplicationDidFinishLaunchingNotification @"kApplicationDidFinishLaunchingNotification"

@class GTMCarbonHotKey;
@class ItermGrowlDelegate;
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

+ (iTermController*)sharedInstance;
+ (void)sharedInstanceRelease;
+ (BOOL)getSystemVersionMajor:(unsigned *)major
                        minor:(unsigned *)minor
                       bugFix:(unsigned *)bugFix;

+ (void)switchToSpaceInBookmark:(NSDictionary*)aDict;

// actions are forwarded from application
- (IBAction)newWindow:(id)sender;
- (void)newWindow:(id)sender possiblyTmux:(BOOL)possiblyTmux;
- (void)newSessionWithSameProfile:(id)sender;
- (void)newSession:(id)sender possiblyTmux:(BOOL)possiblyTmux;
- (IBAction) previousTerminal:(id)sender;
- (IBAction) nextTerminal:(id)sender;
- (void)newSessionsInWindow:(id)sender;
- (void)newSessionsInNewWindow:(id)sender;
- (void)launchScript:(id)sender;

- (void)arrangeHorizontally;
- (void)newSessionInTabAtIndex:(id)sender;
- (void)newSessionInWindowAtIndex:(id)sender;
- (PseudoTerminal*)keyTerminalWindow;
- (BOOL)haveTmuxConnection;
- (PTYSession *)anyTmuxSession;

- (int)keyWindowIndexMemo;
- (void)setKeyWindowIndexMemo:(int)i;

- (PseudoTerminal*)terminalWithNumber:(int)n;
- (PseudoTerminal *)terminalWithGuid:(NSString *)guid;
- (int)allocateWindowNumber;

- (void)saveWindowArrangement:(BOOL)allWindows;
- (void)loadWindowArrangementWithName:(NSString *)theName;

- (PTYSession *)sessionWithMostRecentSelection;

- (PseudoTerminal *)currentTerminal;
- (void)terminalWillClose:(PseudoTerminal*)theTerminalWindow;
- (void)addBookmarksToMenu:(NSMenu *)aMenu
              withSelector:(SEL)selector
           openAllSelector:(SEL)openAllSelector
                startingAt:(int)startingAt;
- (PseudoTerminal *)openWindow;

// Super-flexible way to create a new window or tab. If |block| is given then it is used to add a
// new session/tab to the window; otherwise the bookmark is used in conjunction with the optional
// URL.
- (PTYSession *)launchBookmark:(Profile *)bookmarkData
                    inTerminal:(PseudoTerminal *)theTerm
                       withURL:(NSString *)url
                      isHotkey:(BOOL)isHotkey
                       makeKey:(BOOL)makeKey
                       command:(NSString *)command
                         block:(PTYSession *(^)(PseudoTerminal *))block;
- (PTYSession *)launchBookmark:(Profile *)profile inTerminal:(PseudoTerminal *)theTerm;
- (PTYTextView*)frontTextView;
- (int)numberOfTerminals;
- (PseudoTerminal*)terminalAtIndex:(int)i;
- (void)irAdvance:(int)dir;
- (NSUInteger)indexOfTerminal:(PseudoTerminal*)terminal;

- (void)dumpViewHierarchy;

- (void)storePreviouslyActiveApp;
- (void)restorePreviouslyActiveApp;
- (int)windowTypeForBookmark:(Profile*)aDict;

- (void)reloadAllBookmarks;

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
- (BOOL)hasRestorableSession;
- (void)killRestorableSessions;

- (NSArray*)terminals;
- (void)addTerminalWindow:(PseudoTerminal *)terminalWindow;

- (void)setCurrentTerminal:(PseudoTerminal *)aTerminal;

void OnHotKeyEvent(void);

@end

