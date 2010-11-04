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
#import "LineBuffer.h"


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
    // Table view that displays choices.
    IBOutlet NSTableView* table_;

    // Word before cursor.
    NSMutableString* prefix_;

    // What the user has typed so far to filter result set.
    NSMutableString* substring_;

    // First 20 results beginning with prefix_, including those not matching
    // substring_.
    NSMutableArray* unfilteredModel_;

    // Results currently being displayed.
    NSMutableArray* model_;

    // Backing session.
    PTYSession* dataSource_;

    // Timer to set clearFilterOnNextKeyDown_.
    NSTimer* timer_;

    // If set, then next time a key is pressed erase substring_ before appending.
    BOOL clearFilterOnNextKeyDown_;

    // If true then window is above cursor.
    BOOL onTop_;

    // x,y coords where prefix occured.
    int startX_;
    long long startY_;  // absolute coord

    // Context for searches while populating unfilteredModel.
    FindContext context_;

    // Timer for doing asynch seraches for prefix.
    NSTimer* populateTimer_;

    // Cursor location to begin next search.
    int x_;
    long long y_;  // absolute coord
}

- (id)init;
- (void)dealloc;
- (void)updatePrefix;
- (void)setDataSource:(PTYSession*)dataSource;
- (void)windowDidResignKey:(NSNotification *)aNotification;
- (void)windowDidBecomeKey:(NSNotification *)aNotification;
- (void)refresh;
- (void)setOnTop:(BOOL)onTop;
- (void)setPosition;

- (void)_setClearFilterOnNextKeyDownFlag:(id)sender;
- (void)_populateUnfilteredModel;
- (void)_updateFilter;
- (BOOL)_word:(NSString*)temp matchesFilter:(NSString*)filter;
- (void)_populateMore:(id)sender;
- (void)_doPopulateMore;

// DataSource methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView;
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;

- (void)rowSelected:(id)sender;
- (void)keyDown:(NSEvent*)event;

@end

