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
#import "Popup.h"

@interface AutocompleteView : Popup
{
    // Table view that displays choices.
    IBOutlet NSTableView* table_;

    // Word before cursor.
    NSMutableString* prefix_;

    // Is there whitespace before the cursor? If so, strip whitespace from before candidates.
    BOOL whitespaceBeforeCursor_;

    // Words before the word at the cursor.
    NSMutableArray* context_;

    // x,y coords where prefix occured.
    int startX_;
    long long startY_;  // absolute coord

    // Context for searches while populating unfilteredModel.
    FindContext findContext_;

    // Timer for doing asynch seraches for prefix.
    NSTimer* populateTimer_;

    // Cursor location to begin next search.
    int x_;
    long long y_;  // absolute coord
    
    // Number of matches found so far
    int matchCount_;
}

- (id)init;
- (void)dealloc;

- (void)onOpen;
- (void)refresh;
- (void)onClose;
- (void)rowSelected:(id)sender;
- (void)_populateMore:(id)sender;
- (void)_doPopulateMore;

@end

