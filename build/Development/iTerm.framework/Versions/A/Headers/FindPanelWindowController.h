/*
 **  FindPanelWindowController.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Implements the find functions.
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class PTYTextView;

@interface FindPanelWindowController : NSWindowController
{
    IBOutlet NSTextField *searchStringField;
    IBOutlet NSButton *caseCheckBox;

    id delegate;
}

// init
+ (id)sharedInstance;

// NSWindow delegate methods
- (void)windowWillClose:(NSNotification *)aNotification;
- (void)windowDidLoad;

// action methods
- (IBAction) findNext: (id) sender;
- (IBAction) findPrevious: (id) sender;

// get/set methods
- (id) delegate;
- (void) setDelegate: (id) theDelegate;
- (NSString *) searchString;
- (void) setSearchString: (NSString *) aString;

@end

@interface FindCommandHandler : NSObject
{
    NSString* _searchString;
    BOOL _ignoresCase;
    
}

+ (id)sharedInstance;

- (IBAction) findNext;
- (IBAction) findPrevious;
- (IBAction) findWithSelection;
- (IBAction) jumpToSelection;
- (void) findSubString:(NSString *) subString forwardDirection: (BOOL) direction ignoringCase: (BOOL) caseCheck;
- (void)setSearchString:(NSString*)searchString;
- (NSString*)searchString;
- (BOOL)ignoresCase;
- (void)setIgnoresCase:(BOOL)set;

@end

