/*
 **  BookmarksWindow.h
 **  iTerm
 **
 **  Created by George Nachman on 8/29/10.
 **  Project: iTerm
 **
 **  Description: Display a window with searchable bookmarks. You can use this
 **    to open bookmarks in a new window or tab.
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
 */

#import <Cocoa/Cocoa.h>
#import "BookmarkTableView.h"

@interface BookmarksWindow : NSWindowController <BookmarkTableDelegate> {
    IBOutlet BookmarkTableView* tableView_;
    IBOutlet NSSegmentedControl* actions_;
}

+ (BookmarksWindow*)sharedInstance;
- (id)init;
- (id)initWithWindowNibName:(NSString *)windowNibName;
- (IBAction)openBookmark:(id)sender;
- (void)bookmarkTableSelectionDidChange:(id)bookmarkTable;
- (void)bookmarkTableSelectionWillChange:(id)bookmarkTable;
- (void)bookmarkTableRowSelected:(id)bookmarkTable;
- (IBAction)editBookmarks:(id)sender;

@end
