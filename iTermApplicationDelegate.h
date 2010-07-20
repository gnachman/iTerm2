// -*- mode:objc -*-
// $Id: iTermApplicationDelegate.h,v 1.21 2006-11-21 19:24:29 yfabian Exp $
/*
 **  iTermApplicationDelegate.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
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

@class PseudoTerminal;

@interface iTermApplicationDelegate : NSObject
{
    // about window
	NSWindowController *aboutController;
    IBOutlet id ABOUT;
	IBOutlet id scrollingInfo;
    IBOutlet NSTextView *AUTHORS;

	//Scrolling
    NSTimer	*scrollTimer;
	NSTimer	*eventLoopScrollTimer;
    float	scrollLocation;
    int		maxScroll;
    float   scrollRate;
	
    
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
	IBOutlet NSMenuItem *fontSizeFollowWindowResize;
	IBOutlet NSMenuItem *toggleBookmarksView;
    IBOutlet NSMenuItem *toggleTransparency;

}

// NSApplication Delegate methods
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification;
- (BOOL) applicationShouldTerminate: (NSNotification *) theNotification;
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename;
- (BOOL)applicationOpenUntitledFile:(NSApplication *)app;
- (NSMenu *)applicationDockMenu:(NSApplication *)sender;
- (void)applicationDidUnhide:(NSNotification *)aNotification;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app;

- (IBAction)newWindow:(id)sender;
- (IBAction)newSession:(id)sender;
- (IBAction)buildScriptMenu:(id)sender;

    // About window
- (IBAction)showAbout:(id)sender;
- (IBAction)aboutOK:(id)sender;

- (IBAction)showPrefWindow:(id)sender;
- (IBAction)showBookmarkWindow:(id)sender;

    // navigation
- (IBAction) previousTerminal: (id) sender;
- (IBAction) nextTerminal: (id) sender;

// Notifications
- (void) reloadMenus: (NSNotification *) aNotification;
- (void) buildSessionSubmenu: (NSNotification *) aNotification;
- (void) buildAddressBookMenu: (NSNotification *) aNotification;
- (void) reloadSessionMenus: (NSNotification *) aNotification;
- (void) nonTerminalWindowBecameKey: (NSNotification *) aNotification;

// font control
- (IBAction) biggerFont: (id) sender;
- (IBAction) smallerFont: (id) sender;

// transparency
- (IBAction) useTransparency: (id) sender;

// size
- (IBAction) returnToDefaultSize: (id) sender;

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
