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

#define kApplicationDidFinishLaunchingNotification @"kApplicationDidFinishLaunchingNotification"

@class PseudoTerminal;
@class PTYTextView;
@class ItermGrowlDelegate;
@class PasteboardHistory;
@class GTMCarbonHotKey;
@class PTYSession;

@interface iTermController : NSObject
{
    // PseudoTerminal objects
    NSMutableArray *terminalWindows;
    id FRONT;
    ItermGrowlDelegate *gd;

    int keyWindowIndexMemo_;

    // For restoring previously active app when exiting hotkey window
    NSNumber *previouslyActiveAppPID_;
    id runningApplicationClass_;
}

+ (iTermController*)sharedInstance;
+ (void)sharedInstanceRelease;
+ (BOOL)getSystemVersionMajor:(unsigned *)major
                        minor:(unsigned *)minor
                       bugFix:(unsigned *)bugFix;

+ (void)switchToSpaceInBookmark:(NSDictionary*)aDict;

// actions are forwarded from application
- (IBAction)newWindow:(id)sender;
- (void)newWindow:(id)sender possiblyTmux:(BOOL)possiblyTmux;
- (IBAction)newSessionWithSameProfile:(id)sender;
- (IBAction)newSession:(id)sender;
- (void)newSession:(id)sender possiblyTmux:(BOOL)possiblyTmux;
- (IBAction) previousTerminal:(id)sender;
- (IBAction) nextTerminal:(id)sender;
- (void)newSessionsInWindow:(id)sender;
- (void)newSessionsInNewWindow:(id)sender;
- (void)launchScript:(id)sender;

- (void)arrangeHorizontally;
- (void)newSessionInTabAtIndex:(id)sender;
- (void)newSessionInWindowAtIndex:(id)sender;
- (void)showHideFindBar;
- (PseudoTerminal*)keyTerminalWindow;
- (BOOL)haveTmuxConnection;
- (PTYSession *)anyTmuxSession;

- (int)keyWindowIndexMemo;
- (void)setKeyWindowIndexMemo:(int)i;

- (PseudoTerminal*)terminalWithNumber:(int)n;
- (int)allocateWindowNumber;

- (void)saveWindowArrangement;
- (void)loadWindowArrangementWithName:(NSString *)theName;

- (PTYSession *)sessionWithMostRecentSelection;

- (PseudoTerminal *)currentTerminal;
- (void)terminalWillClose:(PseudoTerminal*)theTerminalWindow;
- (NSArray*)sortedEncodingList;
- (void)addBookmarksToMenu:(NSMenu *)aMenu startingAt:(int)startingAt;
- (void)addBookmarksToMenu:(NSMenu *)aMenu withSelector:(SEL)selector openAllSelector:(SEL)openAllSelector startingAt:(int)startingAt;
- (PseudoTerminal *)openWindow;
- (id)launchBookmark:(NSDictionary *)bookmarkData
          inTerminal:(PseudoTerminal *)theTerm
             withURL:(NSString *)url
            isHotkey:(BOOL)isHotkey
             makeKey:(BOOL)makeKey;
- (id)launchBookmark:(NSDictionary*)bookmarkData inTerminal:(PseudoTerminal*)theTerm;
- (PTYTextView*)frontTextView;
- (int)numberOfTerminals;
- (PseudoTerminal*)terminalAtIndex:(int)i;
- (void)irAdvance:(int)dir;
- (NSUInteger)indexOfTerminal:(PseudoTerminal*)terminal;

- (void)dumpViewHierarchy;

- (void)storePreviouslyActiveApp;
- (void)restorePreviouslyActiveApp;
- (int)windowTypeForBookmark:(Profile*)aDict;

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

