// -*- mode:objc -*-
// $Id: iTermApplicationDelegate.h,v 1.21 2006-11-21 19:24:29 yfabian Exp $
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

//#define GENERAL_VERBOSE_LOGGING
#ifdef GENERAL_VERBOSE_LOGGING
#define DLog NSLog
#else
#define DLog(args...) \
do { \
if (gDebugLogging) { \
DebugLog([NSString stringWithFormat:args]); \
} \
} while (0)
#endif

@class PseudoTerminal;
extern BOOL gDebugLogging;
void DebugLog(NSString* value);

@interface iTermApplicationDelegate : NSObject
{
    // about window
    NSWindowController *aboutController;
    IBOutlet id ABOUT;
    IBOutlet NSTextView *AUTHORS;
    
    // Menu items
    IBOutlet NSMenu     *bookmarkMenu;
    IBOutlet NSMenuItem *selectTab;
    IBOutlet NSMenuItem *previousTerminal;
    IBOutlet NSMenuItem *nextTerminal;
    IBOutlet NSMenuItem *logStart;
    IBOutlet NSMenuItem *logStop;
    IBOutlet NSMenuItem *closeTab;
    IBOutlet NSMenuItem *closeWindow;
    IBOutlet NSMenuItem *sendInputToAllSessions;
    IBOutlet NSMenuItem *toggleBookmarksView;
    IBOutlet NSMenuItem *irNext;
    IBOutlet NSMenuItem *irPrev;

    IBOutlet NSMenuItem *secureInput;
    IBOutlet NSMenuItem *useTransparency;
    IBOutlet NSMenuItem *maximizePane;
    BOOL secureInputDesired_;
    BOOL quittingBecauseLastWindowClosed_;
}

- (void)awakeFromNib;

// NSApplication Delegate methods
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification;
- (BOOL)applicationShouldTerminate: (NSNotification *) theNotification;
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename;
- (BOOL)applicationOpenUntitledFile:(NSApplication *)app;
- (NSMenu *)applicationDockMenu:(NSApplication *)sender;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app;
- (void)applicationDidBecomeActive:(NSNotification *)aNotification;
- (void)applicationDidResignActive:(NSNotification *)aNotification;

- (IBAction)maximizePane:(id)sender;
- (IBAction)toggleUseTransparency:(id)sender;
- (IBAction)toggleSecureInput:(id)sender;

- (IBAction)newWindow:(id)sender;
- (IBAction)newSession:(id)sender;
- (IBAction)buildScriptMenu:(id)sender;

- (IBAction)debugLogging:(id)sender;

- (IBAction)toggleSecureInput:(id)sender;
- (void)updateMaximizePaneMenuItem;
- (void)updateUseTransparencyMenuItem;

    // About window
- (IBAction)showAbout:(id)sender;

- (IBAction)saveWindowArrangement:(id)sender;
- (IBAction)loadWindowArrangement:(id)sender;

- (IBAction)showPrefWindow:(id)sender;
- (IBAction)showBookmarkWindow:(id)sender;
- (IBAction)instantReplayPrev:(id)sender;
- (IBAction)instantReplayNext:(id)sender;

    // navigation
- (IBAction)previousTerminal: (id) sender;
- (IBAction)nextTerminal: (id) sender;
- (IBAction)arrangeHorizontally:(id)sender;

// Notifications
- (void) reloadMenus: (NSNotification *) aNotification;
- (void) buildSessionSubmenu: (NSNotification *) aNotification;
- (void) buildAddressBookMenu: (NSNotification *) aNotification;
- (void) reloadSessionMenus: (NSNotification *) aNotification;
- (void) nonTerminalWindowBecameKey: (NSNotification *) aNotification;

// font control
- (IBAction) biggerFont: (id) sender;
- (IBAction) smallerFont: (id) sender;

// size
- (IBAction)returnToDefaultSize:(id)sender;
- (IBAction)exposeForTabs:(id)sender;
- (IBAction)editCurrentSession:(id)sender;

- (void)makeHotKeyWindowKeyIfOpen;

@end

// Scripting support
@interface iTermApplicationDelegate (KeyValueCoding)

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key;

- (PseudoTerminal *)currentTerminal;

// accessors for to-many relationships:
-(NSArray*)terminals;
-(void)setTerminals: (NSArray*)terminals;
- (void) setCurrentTerminal: (PseudoTerminal *) aTerminal;

-(id)valueInTerminalsAtIndex:(unsigned)index;
-(void)replaceInTerminals:(PseudoTerminal *)object atIndex:(unsigned)index;
- (void) addInTerminals: (PseudoTerminal *) object;
- (void) insertInTerminals: (PseudoTerminal *) object;
-(void)insertInTerminals:(PseudoTerminal *)object atIndex:(unsigned)index;
-(void)removeFromTerminalsAtIndex:(unsigned)index;

// a class method to provide the keys for KVC:
+(NSArray*)kvcKeys;

@end
