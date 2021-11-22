//
//  ToolProfiles.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolProfiles.h"

#import "DebugLogging.h"
#import "iTermController.h"
#import "iTermSessionLauncher.h"
#import "NSEvent+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"

static const int kVerticalMargin = 5;
static const int kMargin = 0;
static const int kPopupHeight = 26;
static const CGFloat kButtonHeight = 23;
static const CGFloat kInnerMargin = 5;
static NSString *const iTermToolProfilesProfileListViewState = @"iTermToolProfilesProfileListViewState";

@implementation ToolProfiles {
    ProfileListView *listView_;
    NSPopUpButton *popup_;
    NSButton *_openButton;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        listView_ = [[ProfileListView alloc] initWithFrame:NSMakeRect(kMargin, 0, frame.size.width - kMargin * 2, frame.size.height - kPopupHeight - kVerticalMargin)
                                                     model:[ProfileModel sharedInstance]
                                                      font:[NSFont it_toolbeltFont]];
        [listView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [listView_ setDelegate:self];
        [listView_ disableArrowHandler];
        [listView_ allowMultipleSelections];
        [listView_.tableView setHeaderView:nil];
        listView_.tableView.enclosingScrollView.drawsBackground = NO;
        if (@available(macOS 10.16, *)) {
            [listView_ forceOverlayScroller];
        }
        listView_.tableView.backgroundColor = [NSColor clearColor];

        [self addSubview:listView_];

        _openButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
        if (@available(macOS 10.16, *)) {
            _openButton.bezelStyle = NSBezelStyleRegularSquare;
            _openButton.bordered = NO;
            _openButton.image = [NSImage it_imageForSymbolName:@"play" accessibilityDescription:@"Open Profile"];
            _openButton.imageScaling = NSImageScaleProportionallyUpOrDown;
            _openButton.imagePosition = NSImageOnly;
        } else {
            [_openButton setButtonType:NSButtonTypeMomentaryPushIn];
            [_openButton setTitle:@"Open"];
            [_openButton setBezelStyle:NSBezelStyleSmallSquare];
        }
        [_openButton setTarget:self];
        [_openButton setAction:@selector(open:)];
        [_openButton sizeToFit];
        [_openButton setAutoresizingMask:NSViewMinYMargin];
        [self addSubview:_openButton];
        [_openButton bind:@"enabled" toObject:listView_ withKeyPath:@"hasSelection" options:nil];

        popup_ = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kPopupHeight, frame.size.width - _openButton.frame.size.width - kInnerMargin, kPopupHeight)];
        [[popup_ cell] setControlSize:NSControlSizeSmall];
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(refreshTerminal:)
                                                     name:kRefreshTerminalNotification
                                                   object:nil];

        [popup_ bind:@"enabled" toObject:listView_ withKeyPath:@"hasSelection" options:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [popup_ unbind:@"enabled"];
    [_openButton unbind:@"enabled"];
}

- (void)refreshTerminal:(NSNotification *)notification {
    [listView_ reloadData];
}

- (void)windowBackgroundColorDidChange {
    [listView_ reloadData];
}

- (void)relayout {
    NSRect frame = self.frame;
    listView_.frame = NSMakeRect(kMargin, 0, frame.size.width - kMargin * 2, frame.size.height - kPopupHeight - kVerticalMargin);
    if (@available(macOS 10.16, *)) {
        const CGFloat margin = 0;
        popup_.frame = NSMakeRect(0,
                                  frame.size.height - kPopupHeight,
                                  frame.size.width - NSWidth(_openButton.frame) - margin,
                                  kPopupHeight);
        NSRect rect = _openButton.frame;
        const CGFloat inset = (NSHeight(popup_.frame) - NSHeight(rect)) / 2.0;
        rect.origin.x = NSMaxX(popup_.frame) + margin;
        const CGFloat fudgeFactor = 1;
        rect.origin.y = inset + NSMinY(popup_.frame) - fudgeFactor;
        _openButton.frame = rect;
    } else {
        popup_.frame = NSMakeRect(0,
                                  frame.size.height - kPopupHeight,
                                  frame.size.width - _openButton.frame.size.width - kInnerMargin,
                                  kPopupHeight);
        _openButton.frame = NSMakeRect(frame.size.width - _openButton.frame.size.width,
                                       frame.size.height - kPopupHeight,
                                       _openButton.frame.size.width,
                                       _openButton.frame.size.height);
    }
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
        [iTermSessionLauncher launchBookmark:bookmark
                                  inTerminal:terminal
                          respectTabbingMode:NO
                                  completion:nil];
    }
}

- (void)toolProfilesNewWindow:(id)sender
{
    for (NSString* guid in [listView_ selectedGuids]) {
        Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        [iTermSessionLauncher launchBookmark:bookmark
                                  inTerminal:nil
                          respectTabbingMode:NO
                                  completion:nil];
    }
}

- (void)toolProfilesNewHorizontalSplit:(id)sender
{
    PseudoTerminal* terminal = [[iTermController sharedInstance] currentTerminal];
    for (NSString* guid in [listView_ selectedGuids]) {
        Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        if (!profile) {
            continue;
        }
        [terminal asyncSplitVertically:NO
                                before:NO
                               profile:profile
                         targetSession:[terminal currentSession]
                            completion:nil
                                 ready:nil];
    }
}

- (void)toolProfilesNewVerticalSplit:(id)sender
{
    PseudoTerminal* terminal = [[iTermController sharedInstance] currentTerminal];
    for (NSString* guid in [listView_ selectedGuids]) {
        Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        if (!profile) {
            continue;
        }
        [terminal asyncSplitVertically:YES
                                before:NO
                               profile:profile
                         targetSession:[terminal currentSession]
                            completion:nil
                                 ready:nil];
    }
}

- (void)profileTableRowSelected:(id)profileTable
{
    NSEvent *event = [[NSApplication sharedApplication] currentEvent];
    if ([event it_modifierFlags] & (NSEventModifierFlagControl)) {
        [self toolProfilesNewHorizontalSplit:nil];
    } else if ([event it_modifierFlags] & (NSEventModifierFlagOption)) {
        [self toolProfilesNewVerticalSplit:nil];
    } else if ([event it_modifierFlags] & (NSEventModifierFlagShift)) {
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
    [self it_performNonObjectReturningSelector:[[popup_ selectedItem] action]
                                    withObject:nil];
}

- (NSDictionary *)restorableState {
    return @{ iTermToolProfilesProfileListViewState: listView_.restorableState };
}

- (void)restoreFromState:(NSDictionary *)state {
    [listView_ restoreFromState:state[iTermToolProfilesProfileListViewState]];
}

@end
