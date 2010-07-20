// -*- mode:objc -*-
// $Id: iTermController.h,v 1.29 2008-10-08 05:54:50 yfabian Exp $
/*
 **  iTermController.h
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
@class PTYTextView;
@class TreeNode;
@class ItermGrowlDelegate;

@interface iTermController : NSObject
{
    // PseudoTerminal objects
    NSMutableArray *terminalWindows;
    id FRONT;
	ItermGrowlDelegate *gd;
}

+ (iTermController*)sharedInstance;
+ (void)sharedInstanceRelease;

// actions are forwarded form application
- (IBAction)newWindow:(id)sender;
- (IBAction)newSession:(id)sender;
- (IBAction) previousTerminal: (id) sender;
- (IBAction) nextTerminal: (id) sender;
- (void)newSessionInTabAtIndex: (id) sender;
- (void)newSessionInWindowAtIndex: (id) sender;

- (PseudoTerminal *) currentTerminal;
- (void) terminalWillClose: (PseudoTerminal *) theTerminalWindow;
- (NSArray *) sortedEncodingList;
- (void) alternativeMenu: (NSMenu *)aMenu forNode: (TreeNode *) theNode target: (id) aTarget withShortcuts: (BOOL) withShortcuts;
- (void) launchBookmark: (NSDictionary *) bookmarkData inTerminal: (PseudoTerminal *) theTerm;
- (void) launchBookmark: (NSDictionary *) bookmarkData inTerminal: (PseudoTerminal *) theTerm withCommand: (NSString *)command;
- (void) launchBookmark: (NSDictionary *) bookmarkData inTerminal: (PseudoTerminal *) theTerm withURL: (NSString *)url;
- (PTYTextView *) frontTextView;

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

@end

