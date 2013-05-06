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

// I use a variadic macro here because of an apparent compiler bug in XCode 4.2 that thinks a
// variadaic objc call as an argument is not a single value.
#define DebugLog(args...) DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, args)

//#define GENERAL_VERBOSE_LOGGING
#ifdef GENERAL_VERBOSE_LOGGING
#define DLog NSLog
#else
#define DLog(args...) \
    do { \
        if (gDebugLogging) { \
            DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args]); \
        } \
    } while (0)
#endif

@class PseudoTerminal;
extern BOOL gDebugLogging;
extern NSString *kUseBackgroundPatternIndicatorChangedNotification;
int DebugLogImpl(const char *file, int line, const char *function, NSString* value);

@interface iTermAboutWindow : NSPanel
{
}

- (IBAction)closeCurrentSession:(id)sender;

@end

@interface iTermApplicationDelegate : NSObject
{
    // about window
    NSWindowController *aboutController;
    IBOutlet id ABOUT;
    IBOutlet NSTextView *AUTHORS;

    // Menu items
    IBOutlet NSMenu     *bookmarkMenu;
    IBOutlet NSMenu     *toolbeltMenu;
    IBOutlet NSMenuItem *showToolbeltItem;
    IBOutlet NSMenuItem *selectTab;
    IBOutlet NSMenuItem *previousTerminal;
    IBOutlet NSMenuItem *nextTerminal;
    IBOutlet NSMenuItem *logStart;
    IBOutlet NSMenuItem *logStop;
    IBOutlet NSMenuItem *closeTab;
    IBOutlet NSMenuItem *closeWindow;
    IBOutlet NSMenuItem *sendInputToAllSessions;
    IBOutlet NSMenuItem *sendInputToAllPanes;
    IBOutlet NSMenuItem *sendInputNormally;
    IBOutlet NSMenuItem *toggleBookmarksView;
    IBOutlet NSMenuItem *irNext;
    IBOutlet NSMenuItem *irPrev;
    IBOutlet NSMenuItem *windowArrangements_;

    IBOutlet NSMenuItem *secureInput;
    IBOutlet NSMenuItem *showFullScreenTabs;
    IBOutlet NSMenuItem *useTransparency;
    IBOutlet NSMenuItem *maximizePane;
    BOOL secureInputDesired_;
    BOOL quittingBecauseLastWindowClosed_;

    // If set, skip performing launch actions.
    BOOL quiet_;
    NSDate* launchTime_;

    // Cross app request forgery prevention token. Get this with applescript and then include
    // in a URI request.
    NSString *token_;

    // Set to YES when applicationDidFinishLaunching: is called.
    BOOL finishedLaunching_;

    BOOL userHasInteractedWithAnySession_;  // Disables min 10-second running time
}

- (void)awakeFromNib;

// NSApplication Delegate methods
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification;
- (BOOL)applicationShouldTerminate: (NSNotification *) theNotification;
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename;
- (BOOL)applicationOpenUntitledFile:(NSApplication *)app;
- (NSMenu *)applicationDockMenu:(NSApplication *)sender;
- (NSMenu*)bookmarksMenu;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app;

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag;

- (void)applicationDidBecomeActive:(NSNotification *)aNotification;
- (void)applicationDidResignActive:(NSNotification *)aNotification;

- (IBAction)toggleToolbelt:(id)sender;
- (IBAction)toggleFullScreenTabBar:(id)sender;
- (IBAction)maximizePane:(id)sender;
- (IBAction)toggleUseTransparency:(id)sender;
- (IBAction)toggleSecureInput:(id)sender;

- (IBAction)newWindow:(id)sender;
- (IBAction)newSessionWithSameProfile:(id)sender;
- (IBAction)newSession:(id)sender;
- (IBAction)buildScriptMenu:(id)sender;

- (IBAction)debugLogging:(id)sender;

- (IBAction)toggleSecureInput:(id)sender;
- (void)updateMaximizePaneMenuItem;
- (void)updateUseTransparencyMenuItem;

    // About window
- (IBAction)showAbout:(id)sender;

- (IBAction)makeDefaultTerminal:(id)sender;
- (IBAction)unmakeDefaultTerminal:(id)sender;

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
- (void) reloadSessionMenus: (NSNotification *) aNotification;
- (void) nonTerminalWindowBecameKey: (NSNotification *) aNotification;

// font control
- (IBAction) biggerFont: (id) sender;
- (IBAction) smallerFont: (id) sender;

// Paste speed control
- (IBAction)pasteFaster:(id)sender;
- (IBAction)pasteSlower:(id)sender;
- (IBAction)pasteSlowlyFaster:(id)sender;
- (IBAction)pasteSlowlySlower:(id)sender;

// size
- (IBAction)returnToDefaultSize:(id)sender;
- (IBAction)exposeForTabs:(id)sender;
- (IBAction)editCurrentSession:(id)sender;

- (IBAction)toggleUseBackgroundPatternIndicator:(id)sender;
- (BOOL)useBackgroundPatternIndicator;

- (void)makeHotKeyWindowKeyIfOpen;

// Implements the 10.6 api but is callable in 10.5 and tries to implement
// some subset of the flags.
- (void)setFutureApplicationPresentationOptions:(int)flags unset:(int)antiflags;

- (void)updateBroadcastMenuState;

- (BOOL)showToolbelt;

// Call this when the user has any nontrivial interaction with a session, such as typing in it or closing a window.
- (void)userDidInteractWithASession;

@end

// Scripting support
@interface iTermApplicationDelegate (KeyValueCoding)

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key;

- (PseudoTerminal *)currentTerminal;
- (NSString *)uriToken;

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
