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

@class PTYSession;
@class PseudoTerminal;

extern NSString *kUseBackgroundPatternIndicatorChangedNotification;
extern NSString *const kMultiLinePasteWarningUserDefaultsKey;
extern NSString *const kPasteOneLineWithNewlineAtShellWarningUserDefaultsKey;
extern NSString *const kSavedArrangementDidChangeNotification;
extern NSString *const kNonTerminalWindowBecameKeyNotification;

extern NSString *const kMarkAlertActionModalAlert;
extern NSString *const kMarkAlertActionPostNotification;
extern NSString *const kShowFullscreenTabsSettingDidChange;

int DebugLogImpl(const char *file, int line, const char *function, NSString* value);

@interface iTermApplicationDelegate : NSObject<NSApplicationDelegate>

@property(nonatomic, readonly) BOOL workspaceSessionActive;
@property(nonatomic, readonly) BOOL isApplescriptTestApp;
@property(nonatomic, readonly) BOOL isRunningOnTravis;

// Returns one of the kMarkAlertAction strings defined above.
@property(nonatomic, readonly) NSString *markAlertAction;

// Is Sparkle in the process of restarting us?
@property(nonatomic, readonly) BOOL sparkleRestarting;

@property(nonatomic, readonly) BOOL useBackgroundPatternIndicator;
@property(nonatomic, readonly) BOOL warnBeforeMultiLinePaste;

- (void)awakeFromNib;

// NSApplication Delegate methods
- (NSMenu*)bookmarksMenu;

- (IBAction)undo:(id)sender;
- (IBAction)toggleToolbeltTool:(NSMenuItem *)menuItem;
- (IBAction)toggleFullScreenTabBar:(id)sender;
- (IBAction)maximizePane:(id)sender;
- (IBAction)toggleUseTransparency:(id)sender;
- (IBAction)toggleSecureInput:(id)sender;

- (IBAction)newWindow:(id)sender;
- (IBAction)newSessionWithSameProfile:(id)sender;
- (IBAction)newSession:(id)sender;
- (IBAction)buildScriptMenu:(id)sender;

- (IBAction)debugLogging:(id)sender;
- (IBAction)openQuickly:(id)sender;

- (void)updateMaximizePaneMenuItem;
- (void)updateUseTransparencyMenuItem;

    // About window
- (IBAction)showAbout:(id)sender;

- (IBAction)makeDefaultTerminal:(id)sender;
- (IBAction)unmakeDefaultTerminal:(id)sender;

- (IBAction)saveWindowArrangement:(id)sender;

- (IBAction)showPrefWindow:(id)sender;
- (IBAction)showBookmarkWindow:(id)sender;

    // navigation
- (IBAction)arrangeHorizontally:(id)sender;

// Notifications
- (void)reloadMenus: (NSNotification *) aNotification;
- (void)buildSessionSubmenu: (NSNotification *) aNotification;
- (void)reloadSessionMenus: (NSNotification *) aNotification;
- (void)nonTerminalWindowBecameKey: (NSNotification *) aNotification;

// font control
- (IBAction) biggerFont: (id) sender;
- (IBAction) smallerFont: (id) sender;

// Paste speed control
- (IBAction)pasteFaster:(id)sender;
- (IBAction)pasteSlower:(id)sender;
- (IBAction)pasteSlowlyFaster:(id)sender;
- (IBAction)pasteSlowlySlower:(id)sender;

- (IBAction)toggleMultiLinePasteWarning:(id)sender;

// size
- (IBAction)returnToDefaultSize:(id)sender;
- (IBAction)exposeForTabs:(id)sender;
- (IBAction)editCurrentSession:(id)sender;

- (IBAction)toggleUseBackgroundPatternIndicator:(id)sender;

- (void)makeHotKeyWindowKeyIfOpen;

- (void)updateBroadcastMenuState;

// Call this when the user has any nontrivial interaction with a session, such as typing in it or closing a window.
- (void)userDidInteractWithASession;

- (NSMenu *)downloadsMenu;
- (NSMenu *)uploadsMenu;

- (void)openPasswordManagerToAccountName:(NSString *)name inSession:(PTYSession *)session;

- (PseudoTerminal *)currentTerminal;
- (NSArray*)terminals;

@end
