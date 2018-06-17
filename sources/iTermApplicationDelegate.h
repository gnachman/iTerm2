/*
 **  iTermApplicationDelegate.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
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
#import <Carbon/Carbon.h>
#import "DebugLogging.h"
#import "iTermApplication.h"

@class iTermScriptsMenuController;
@class ITMNotification;
@class PseudoTerminal;
@class PTYSession;

extern NSString *kUseBackgroundPatternIndicatorChangedNotification;
extern NSString *const kSavedArrangementDidChangeNotification;
extern NSString *const kNonTerminalWindowBecameKeyNotification;

extern NSString *const kMarkAlertActionModalAlert;
extern NSString *const kMarkAlertActionPostNotification;
extern NSString *const kShowFullscreenTabsSettingDidChange;
extern NSString *const iTermApplicationWillTerminate;

@interface iTermApplicationDelegate : NSObject<iTermApplicationDelegate>

@property(nonatomic, readonly) BOOL workspaceSessionActive;
@property(nonatomic, readonly) BOOL isApplescriptTestApp;
@property(nonatomic, readonly) BOOL isRunningOnTravis;

// Returns one of the kMarkAlertAction strings defined above.
@property(nonatomic, readonly) NSString *markAlertAction;

// Is Sparkle in the process of restarting us?
@property(nonatomic, readonly) BOOL sparkleRestarting;

@property(nonatomic, readonly) BOOL useBackgroundPatternIndicator;
@property(nonatomic, readonly) BOOL warnBeforeMultiLinePaste;
@property(nonatomic, readonly) NSMenu *downloadsMenu;
@property(nonatomic, readonly) NSMenu *uploadsMenu;
@property(nonatomic, readonly) iTermScriptsMenuController *scriptsMenuController;

- (void)updateMaximizePaneMenuItem;
- (void)updateUseTransparencyMenuItem;
- (void)updateBroadcastMenuState;

- (void)makeHotKeyWindowKeyIfOpen;

// Call this when the user has any nontrivial interaction with a session, such as typing in it or closing a window.
- (void)userDidInteractWithASession;

- (void)openPasswordManagerToAccountName:(NSString *)name inSession:(PTYSession *)session;
- (void)updateBuriedSessionsMenu;

#pragma mark - Actions

- (void)toggleToolbeltTool:(id)sender;
- (void)newSession:(id)sender;
- (void)undo:(id)sender;
- (void)showPrefWindow:(id)sender;

@end
