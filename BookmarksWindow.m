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
    [[self window] setDelegate:self];
    [[self window] setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    [tableView_ setDelegate:self];
    [tableView_ allowMultipleSelections];
    [tableView_ multiColumns];

    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
    NSNumber* n = [prefs objectForKey:@"CloseBookmarksWindowAfterOpening"];
    [closeAfterOpeningBookmark_ setState:[n boolValue] ? NSOnState : NSOffState];

    return self;
}

- (void)_openBookmarkInTab:(BOOL)inTab firstInWindow:(BOOL)firstInWindow
{
    NSSet* guids = [tableView_ selectedGuids];
    if (![guids count]) {
        NSBeep();
        return;
    }
    BOOL isFirst = YES;
    for (NSString* guid in guids) {
        PseudoTerminal* terminal = nil;
        BOOL openInTab = inTab & !(isFirst && firstInWindow);
        if (openInTab) {
            terminal = [[iTermController sharedInstance] currentTerminal];
        }
        Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
        [[iTermController sharedInstance] launchBookmark:bookmark
                                              inTerminal:terminal];
        isFirst = NO;
    }
}

- (IBAction)openBookmarkInTab:(id)sender
{
    [self _openBookmarkInTab:YES firstInWindow:NO];
    if ([closeAfterOpeningBookmark_ state] == NSOnState) {
        [[self window] close];
    }
}

- (IBAction)openBookmarkInWindow:(id)sender
{
    [self _openBookmarkInTab:NO firstInWindow:NO];
    if ([closeAfterOpeningBookmark_ state] == NSOnState) {
        [[self window] close];
    }
}

- (void)bookmarkTableSelectionDidChange:(id)bookmarkTable
{
    NSSet* guids = [tableView_ selectedGuids];
    if ([guids count]) {
        [tabButton_ setEnabled:YES];
        [windowButton_ setEnabled:YES];
        if ([guids count] > 1) {
            [newTabsInNewWindowButton_ setHidden:NO];
        } else {
            [newTabsInNewWindowButton_ setHidden:YES];
        }
    } else {
        [tabButton_ setEnabled:NO];
        [windowButton_ setEnabled:NO];
    }
    for (int i = 0; i < 2; ++i) {
        [actions_ setEnabled:([guids count] > 0) forSegment:i];
    }
}

- (void)bookmarkTableSelectionWillChange:(id)bookmarkTable
{
}

- (void)bookmarkTableRowSelected:(id)bookmarkTable
{
    NSSet* guids = [tableView_ selectedGuids];
    for (NSString* guid in guids) {
        PseudoTerminal* terminal = [[iTermController sharedInstance] currentTerminal];
        Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
        [[iTermController sharedInstance] launchBookmark:bookmark
                                              inTerminal:terminal];
    }
    if ([closeAfterOpeningBookmark_ state] == NSOnState) {
        [[self window] close];
    }
}

- (IBAction)editBookmarks:(id)sender
{
    [[PreferencePanel sharedInstance] run];
    [[PreferencePanel sharedInstance] showBookmarks];
}

- (IBAction)editSelectedBookmark:(id)sender
{
    NSString* guid = [tableView_ selectedGuid];
    if (guid) {
        [[PreferencePanel sharedInstance] openToBookmark:guid];
    }
}

- (NSMenu*)bookmarkTable:(id)bookmarkTable menuForEvent:(NSEvent*)theEvent
{
    NSMenu* menu =[[[NSMenu alloc] initWithTitle:@"Contextual Menu"] autorelease];

    int count = [[bookmarkTable selectedGuids] count];
    if (count == 1) {
        [menu addItemWithTitle:@"Edit Bookmark..."
                        action:@selector(editSelectedBookmark:)
                 keyEquivalent:@""];
        [menu addItemWithTitle:@"Open in New Tab"
                        action:@selector(openBookmarkInTab:)
                 keyEquivalent:@""];
        [menu addItemWithTitle:@"Open in New Window"
                        action:@selector(openBookmarkInWindow:)
                 keyEquivalent:@""];
    } else if (count > 1) {
        [menu addItemWithTitle:@"Open in New Tabs"
                        action:@selector(openBookmarkInTab:)
                 keyEquivalent:@""];
        [menu addItemWithTitle:@"Open in New Windows"
                        action:@selector(openBookmarkInWindow:)
                 keyEquivalent:@""];
    }
    return menu;
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"nonTerminalWindowBecameKey"
                                                        object:nil
                                                      userInfo:nil];
}

- (IBAction)closeAfterOpeningChanged:(id)sender
{
    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:[NSNumber numberWithBool:[closeAfterOpeningBookmark_ state] == NSOnState]
              forKey:@"CloseBookmarksWindowAfterOpening"];
}

- (IBAction)newTabsInNewWindow:(id)sender
{
    [self _openBookmarkInTab:YES firstInWindow:YES];
    if ([closeAfterOpeningBookmark_ state] == NSOnState) {
        [[self window] close];
    }
}

@end
