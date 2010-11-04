// -*- mode:objc -*-
/*
 **  Autocomplete.h
 **
 **  Copyright (c) 2010
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Implements the Autocomplete UI. It grabs the word behind the
 **      cursor and opens a popup window with likely suffixes. Selecting one
 **      appends it, and you can search the list Quicksilver-style.
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
#import "iTerm/PTYSession.h"

@interface AutocompleteWindow : NSWindow {
}
- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)aStyle
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)flag;

- (BOOL)canBecomeKeyWindow;
- (void)keyDown:(NSEvent *)event;

@end

@interface AutocompleteView : NSWindowController
{
    IBOutlet NSTableView* table_;
    NSMutableString* prefix_;
    NSMutableString* substring_;
    NSMutableArray* model_;
    PTYSession* dataSource_;
    NSTimer* timer_;
    BOOL clearFilterOnNextKeyDown_;
    BOOL onTop_;
    int startX_;
    int startY_;
}

- (id)init;
- (void)dealloc;
- (void)updatePrefix;
- (void)setDataSource:(PTYSession*)dataSource;
- (void)windowDidResignKey:(NSNotification *)aNotification;
- (void)windowDidBecomeKey:(NSNotification *)aNotification;
- (void)refresh;
- (void)setOnTop:(BOOL)onTop;

- (void)_setClearFilterOnNextKeyDownFlag:(id)sender;
- (void)_populateModel;

// DataSource methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView;
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;

- (void)rowSelected:(id)sender;
- (void)keyDown:(NSEvent*)event;

@end

