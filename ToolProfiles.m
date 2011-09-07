//
//  ToolProfiles.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolProfiles.h"
#import "PseudoTerminal.h"
#import "iTermController.h"
#import "BookmarkModel.h"

@implementation ToolProfiles

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        const int kVerticalMargin = 5;
        const int kMargin = 0;
        const int kPopupHeight = 26;

        listView_ = [[BookmarkListView alloc] initWithFrame:NSMakeRect(kMargin, 0, frame.size.width - kMargin * 2, frame.size.height - kPopupHeight - kVerticalMargin)];
        [listView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [listView_ setDelegate:self];
        [listView_ setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [self addSubview:listView_];
        [listView_ release];

        popup_ = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kPopupHeight, frame.size.width, kPopupHeight)];
        [[popup_ cell] setControlSize:NSSmallControlSize];
        [[popup_ cell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [[popup_ menu] addItemWithTitle:@"New Tab"
                                 action:@selector(toolProfilesNewTab:)
                          keyEquivalent:@""];
        [[popup_ menu] addItemWithTitle:@"New Window"
                                 action:@selector(toolProfilesNewWindow:)
                          keyEquivalent:@""];
        [[popup_ menu] addItemWithTitle:@"New Horizontal Split"
                                 action:@selector(toolProfilesNewHorizontalSplit:)
                          keyEquivalent:@""];
        [[popup_ menu] addItemWithTitle:@"New Vertical Split"
                                 action:@selector(toolProfilesNewVerticalSplit:)
                          keyEquivalent:@""];
        for (NSMenuItem *i in [[popup_ menu] itemArray]) {
            [i setTarget:self];
        }
        [self addSubview:popup_];
        [popup_ release];
        [popup_ setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];

        [popup_ bind:@"enabled" toObject:listView_ withKeyPath:@"hasSelection" options:nil];
    }
    return self;
}

- (void)dealloc
{
    [popup_ unbind:@"enabled"];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)toolProfilesNewTab:(id)sender
{
    PseudoTerminal* terminal = [[iTermController sharedInstance] currentTerminal];
    for (NSString* guid in [listView_ selectedGuids]) {
        Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
        [[iTermController sharedInstance] launchBookmark:bookmark
                                              inTerminal:terminal];
    }    
}

- (void)toolProfilesNewWindow:(id)sender
{
    for (NSString* guid in [listView_ selectedGuids]) {
        Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
        [[iTermController sharedInstance] launchBookmark:bookmark
                                              inTerminal:nil];
    }    
}

- (void)toolProfilesNewHorizontalSplit:(id)sender
{
    PseudoTerminal* terminal = [[iTermController sharedInstance] currentTerminal];
    for (NSString* guid in [listView_ selectedGuids]) {
        [terminal splitVertically:NO withBookmarkGuid:guid];
    }    
}

- (void)toolProfilesNewVerticalSplit:(id)sender
{
    PseudoTerminal* terminal = [[iTermController sharedInstance] currentTerminal];
    for (NSString* guid in [listView_ selectedGuids]) {
        [terminal splitVertically:YES withBookmarkGuid:guid];
    }
}

- (void)bookmarkTableRowSelected:(id)bookmarkTable
{
    NSEvent *event = [[NSApplication sharedApplication] currentEvent];
    if ([event modifierFlags] & (NSControlKeyMask)) {
        [self toolProfilesNewHorizontalSplit:nil];
    } else if ([event modifierFlags] & (NSAlternateKeyMask)) {
        [self toolProfilesNewVerticalSplit:nil];
    } else if ([event modifierFlags] & (NSShiftKeyMask)) {
        [self toolProfilesNewWindow:nil];
    } else {
        [self toolProfilesNewTab:nil];
    }
}

@end
