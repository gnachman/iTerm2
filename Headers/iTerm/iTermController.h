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
#import <Carbon/Carbon.h>

@class PseudoTerminal;
@class PTYTextView;
@class ItermGrowlDelegate;
@class PasteboardHistory;

@interface iTermController : NSObject
{
    // PseudoTerminal objects
    NSMutableArray *terminalWindows;
    id FRONT;
    ItermGrowlDelegate *gd;

    // App-wide hotkey
    int hotkeyCode_;
    int hotkeyModifiers_;
    CFMachPortRef machPortRef;
    CFRunLoopSourceRef eventSrc;
    int keyWindowIndexMemo_;
    BOOL itermWasActiveWhenHotkeyOpened;
    BOOL rollingIn_;
}

+ (iTermController*)sharedInstance;
+ (void)sharedInstanceRelease;

+ (void)switchToSpaceInBookmark:(NSDictionary*)aDict;
- (BOOL)rollingInHotkeyTerm;

// actions are forwarded from application
- (IBAction)newWindow:(id)sender;
- (IBAction)newSession:(id)sender;
- (IBAction) previousTerminal:(id)sender;
- (IBAction) nextTerminal:(id)sender;
- (void)arrangeHorizontally;
- (void)newSessionInTabAtIndex:(id)sender;
- (void)newSessionInWindowAtIndex:(id)sender;
- (void)showHideFindBar;

- (void)stopEventTap;

- (int)keyWindowIndexMemo;
- (void)setKeyWindowIndexMemo:(int)i;
- (void)showHotKeyWindow;
- (void)fastHideHotKeyWindow;
- (void)hideHotKeyWindow:(PseudoTerminal*)hotkeyTerm;
- (BOOL)isHotKeyWindowOpen;
- (void)showNonHotKeyWindowsAndSetAlphaTo:(float)a;
- (PseudoTerminal*)hotKeyWindow;

- (PseudoTerminal*)terminalWithNumber:(int)n;
- (int)allocateWindowNumber;

- (BOOL)hasWindowArrangement;
- (void)saveWindowArrangement;
- (void)loadWindowArrangement;

- (PseudoTerminal *)currentTerminal;
- (void)terminalWillClose:(PseudoTerminal*)theTerminalWindow;
- (NSArray*)sortedEncodingList;
- (void)addBookmarksToMenu:(NSMenu *)aMenu target:(id)aTarget withShortcuts:(BOOL)withShortcuts selector:(SEL)selector openAllSelector:(SEL)openAllSelector alternateSelector:(SEL)alternateSeelctor;
- (id)launchBookmark:(NSDictionary*)bookmarkData inTerminal:(PseudoTerminal*)theTerm;
- (id)launchBookmark:(NSDictionary *)bookmarkData inTerminal:(PseudoTerminal *)theTerm withCommand:(NSString *)command;
- (id)launchBookmark:(NSDictionary*)bookmarkData inTerminal:(PseudoTerminal*)theTerm withURL:(NSString*)url;
- (PTYTextView*)frontTextView;
- (int)numberOfTerminals;
- (PseudoTerminal*)terminalAtIndex:(int)i;
- (void)irAdvance:(int)dir;
- (NSUInteger)indexOfTerminal:(PseudoTerminal*)terminal;

- (BOOL)eventIsHotkey:(NSEvent*)e;
- (void)unregisterHotkey;
- (BOOL)haveEventTap;
- (BOOL)registerHotkey:(int)keyCode modifiers:(int)modifiers;
- (void)beginRemappingModifiers;

@end

// Scripting support
@interface iTermController (KeyValueCoding)

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key;

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
- (NSArray*)kvcKeys;

void OnHotKeyEvent(void);

@end

