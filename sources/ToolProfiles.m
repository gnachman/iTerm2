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
#import "ProfileModel.h"

static const int kVerticalMargin = 5;
static const int kMargin = 0;
static const int kPopupHeight = 26;
static const CGFloat kButtonHeight = 23;
static const CGFloat kInnerMargin = 5;

@implementation ToolProfiles {
    ProfileListView *listView_;
    NSPopUpButton *popup_;
    NSButton *_openButton;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        listView_ = [[ProfileListView alloc] initWithFrame:NSMakeRect(kMargin, 0, frame.size.width - kMargin * 2, frame.size.height - kPopupHeight - kVerticalMargin)];
        [listView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [listView_ setDelegate:self];
        [listView_ setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [listView_ disableArrowHandler];
        [listView_ allowMultipleSelections];
        [listView_.tableView setHeaderView:nil];

        [self addSubview:listView_];
        [listView_ release];

        _openButton = [[[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)] autorelease];
        [_openButton setButtonType:NSMomentaryPushInButton];
        [_openButton setTitle:@"Open"];
        [_openButton setTarget:self];
        [_openButton setAction:@selector(open:)];
        [_openButton setBezelStyle:NSSmallSquareBezelStyle];
        [_openButton sizeToFit];
        [_openButton setAutoresizingMask:NSViewMinYMargin];
        [self addSubview:_openButton];
        [_openButton bind:@"enabled" toObject:listView_ withKeyPath:@"hasSelection" options:nil];

        popup_ = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kPopupHeight, frame.size.width - _openButton.frame.size.width - kInnerMargin, kPopupHeight)] autorelease];
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
        [popup_ setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];

        [popup_ bind:@"enabled" toObject:listView_ withKeyPath:@"hasSelection" options:nil];

    }
    return self;
}

- (void)dealloc
{
    [popup_ unbind:@"enabled"];
    [_openButton unbind:@"enabled"];
    [super dealloc];
}

- (void)relayout {
    NSRect frame = self.frame;
    listView_.frame = NSMakeRect(kMargin, 0, frame.size.width - kMargin * 2, frame.size.height - kPopupHeight - kVerticalMargin);
    popup_.frame = NSMakeRect(0, frame.size.height - kPopupHeight, frame.size.width - _openButton.frame.size.width - kInnerMargin, kPopupHeight);
    _openButton.frame = NSMakeRect(frame.size.width - _openButton.frame.size.width,
                                   frame.size.height - kPopupHeight,
                                   _openButton.frame.size.width,
                                   _openButton.frame.size.height);
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)toolProfilesNewTab:(id)sender
{
    PseudoTerminal* terminal = [[iTermController sharedInstance] currentTerminal];
    for (NSString* guid in [listView_ selectedGuids]) {
        Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        [[iTermController sharedInstance] launchBookmark:bookmark
                                              inTerminal:terminal];
    }    
}

- (void)toolProfilesNewWindow:(id)sender
{
    for (NSString* guid in [listView_ selectedGuids]) {
        Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
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

- (void)profileTableRowSelected:(id)profileTable
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

- (void)shutdown
{
}

- (CGFloat)minimumHeight
{
    return 88;
}

- (void)open:(id)sender {
    [self performSelector:[[popup_ selectedItem] action]];
}

@end
