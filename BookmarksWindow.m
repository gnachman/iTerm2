/*
**  BookmarksWindow.m
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

#import "BookmarksWindow.h"
#import <iTerm/BookmarkModel.h>
#import <iTerm/iTermController.h>
#import <iTerm/PreferencePanel.h>

@implementation BookmarksWindow

+ (BookmarksWindow*)sharedInstance
{
    static BookmarksWindow* instance;
    if (!instance) {
        instance = [[BookmarksWindow alloc] init];
    }
    return instance;
}

- (id)init
{
    self = [self initWithWindowNibName:@"BookmarksWindow"];
    return self;
}

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    self = [super initWithWindowNibName:windowNibName];
    if (!self) {
        return nil;
    }

    // Force the window to load
    [self window];
    [tableView_ setDelegate:self];
    [tableView_ multiColumns];
    return self;
}

- (IBAction)openBookmark:(id)sender
{
    NSString* guid = [tableView_ selectedGuid];
    if (!guid) {
        NSBeep();
        return;
    }
    PseudoTerminal* terminal = nil;
    if ([sender selectedSegment] == 0) {
        terminal = [[iTermController sharedInstance] currentTerminal];
    }
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
    [[iTermController sharedInstance] launchBookmark:bookmark 
                                          inTerminal:terminal];
}

- (void)bookmarkTableSelectionDidChange:(id)bookmarkTable
{
    NSString* guid = [tableView_ selectedGuid];
    for (int i = 0; i < 2; ++i) {
        [actions_ setEnabled:(guid != nil) forSegment:i];
    }
}

- (void)bookmarkTableSelectionWillChange:(id)bookmarkTable
{
}

- (void)bookmarkTableRowSelected:(id)bookmarkTable
{
    NSString* guid = [tableView_ selectedGuid];
    PseudoTerminal* terminal = [[iTermController sharedInstance] currentTerminal];
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
    [[iTermController sharedInstance] launchBookmark:bookmark 
                                          inTerminal:terminal];    
}

- (IBAction)editBookmarks:(id)sender
{
    [[PreferencePanel sharedInstance] run];
    [[PreferencePanel sharedInstance] showBookmarks];
}

@end
