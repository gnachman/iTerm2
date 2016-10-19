/*
**  iTermProfilesWindowController.m
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

#import "iTermProfilesWindowController.h"
#import "ProfileModel.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"

static NSString *const kCloseBookmarksWindowAfterOpeningKey = @"CloseBookmarksWindowAfterOpening";

typedef enum {
    HORIZONTAL_PANE,
    VERTICAL_PANE,
    NO_PANE // no gane
} PaneMode;

@interface iTermProfilesWindowRestorer : NSObject
@end

@implementation iTermProfilesWindowRestorer

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    iTermProfilesWindowController *windowController = [iTermProfilesWindowController sharedInstance];
    [windowController.window restoreStateWithCoder:state];
    completionHandler(windowController.window, NULL);
}

@end


@implementation iTermProfilesWindowController {
    IBOutlet ProfileListView* tableView_;
    IBOutlet NSSegmentedControl* actions_;
    IBOutlet NSButton* horizontalPaneButton_;
    IBOutlet NSButton* verticalPaneButton_;
    IBOutlet NSButton* tabButton_;
    IBOutlet NSButton* windowButton_;
    IBOutlet NSButton* closeAfterOpeningBookmark_;
    IBOutlet NSButton* newTabsInNewWindowButton_;
    IBOutlet NSButton* toggleTagsButton_;
}

+ (iTermProfilesWindowController*)sharedInstance {
    static iTermProfilesWindowController* instance;
    if (!instance) {
        instance = [[iTermProfilesWindowController alloc] init];
    }
    return instance;
}

- (instancetype)init {
    self = [self initWithWindowNibName:@"ProfilesWindow"];
    return self;
}

- (instancetype)initWithWindowNibName:(NSString *)windowNibName {
    self = [super initWithWindowNibName:windowNibName];

    if (self) {
        [[self window] setDelegate:self];
        if ([iTermAdvancedSettingsModel profilesWindowJoinsActiveSpace]) {
            [[self window] setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
        }
        [tableView_ setDelegate:self];
        [tableView_ allowMultipleSelections];
        [tableView_ multiColumns];

        NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
        NSNumber* n = [prefs objectForKey:kCloseBookmarksWindowAfterOpeningKey];
        [closeAfterOpeningBookmark_ setState:[n boolValue] ? NSOnState : NSOffState];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updatePaneButtons:)
                                                     name:@"iTermWindowBecameKey"
                                                   object:nil];
        [[self window] setRestorable:YES];
        [[self window] setRestorationClass:[iTermProfilesWindowRestorer class]];
    }
    return self;
}

- (IBAction)closeCurrentSession:(id)sender
{
    if ([[self window] isKeyWindow]) {
        [self close];
    }
}

- (void)_openBookmarkInTab:(BOOL)inTab firstInWindow:(BOOL)firstInWindow inPane:(PaneMode)inPane
{
    NSArray* guids = [tableView_ orderedSelectedGuids];
    if (![guids count]) {
        NSBeep();
        return;
    }
    BOOL isFirst = YES;
    for (NSString* guid in guids) {
        PseudoTerminal* terminal = nil;
        BOOL openInTab = inTab && !(isFirst && firstInWindow);
        if (openInTab) {
            terminal = [[iTermController sharedInstance] currentTerminal];
        }
        Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        if (inPane != NO_PANE && terminal != nil) {
            [terminal splitVertically:(inPane == VERTICAL_PANE)
                         withBookmark:bookmark
                        targetSession:[[terminal currentTab] activeSession]];
        } else {
            [[iTermController sharedInstance] launchBookmark:bookmark
                                                  inTerminal:terminal];
        }
        isFirst = NO;
    }
}

- (IBAction)openBookmarkInVerticalPane:(id)sender
{
    BOOL windowExists = [[iTermController sharedInstance] currentTerminal] != nil;
    [self _openBookmarkInTab:YES firstInWindow:!windowExists inPane:VERTICAL_PANE];
    if ([closeAfterOpeningBookmark_ state] == NSOnState) {
        [[self window] close];
    }
}

- (IBAction)openBookmarkInHorizontalPane:(id)sender
{
    BOOL windowExists = [[iTermController sharedInstance] currentTerminal] != nil;
    [self _openBookmarkInTab:YES firstInWindow:!windowExists inPane:HORIZONTAL_PANE];
    if ([closeAfterOpeningBookmark_ state] == NSOnState) {
        [[self window] close];
    }
}

- (IBAction)openBookmarkInTab:(id)sender
{
    [self _openBookmarkInTab:YES firstInWindow:NO inPane:NO_PANE];
    if ([closeAfterOpeningBookmark_ state] == NSOnState) {
        [[self window] close];
    }
}

- (IBAction)openBookmarkInWindow:(id)sender
{
    [self _openBookmarkInTab:NO firstInWindow:NO inPane:NO_PANE];
    if ([closeAfterOpeningBookmark_ state] == NSOnState) {
        [[self window] close];
    }
}

- (IBAction)toggleTags:(id)sender {
    [tableView_ toggleTags];
    [[self window] invalidateRestorableState];
}

- (void)updatePaneButtons:(id)sender
{
    [self profileTableSelectionDidChange:tableView_];
}

- (void)updateKeyEquivalents
{
    if (!tabButton_.isEnabled && windowButton_.isEnabled) {
        windowButton_.keyEquivalentModifierMask = 0;
    } else {
        windowButton_.keyEquivalentModifierMask = NSShiftKeyMask;
    }
}

- (void)profileTableTagsVisibilityDidChange:(ProfileListView *)profileListView {
    [toggleTagsButton_ setTitle:profileListView.tagsVisible ? @"< Tags" : @"Tags >"];
}

- (void)profileTableSelectionDidChange:(id)profileTable
{
    NSSet* guids = [tableView_ selectedGuids];
    BOOL anySelectionDisablesTabs = NO;
    for (NSString *guid in guids) {
        Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        if ([[profile objectForKey:KEY_PREVENT_TAB] boolValue]) {
            anySelectionDisablesTabs = YES;
        }
    }

    if ([guids count]) {
        BOOL windowExists = [[iTermController sharedInstance] currentTerminal] != nil;
        // tabButton is enabled even if windowExists==false because its shortcut is enter and we
        // don't want to break that.
        [tabButton_ setEnabled:!anySelectionDisablesTabs];
        [windowButton_ setEnabled:YES];
        if ([guids count] > 1) {
            [newTabsInNewWindowButton_ setEnabled:!anySelectionDisablesTabs];
            [horizontalPaneButton_ setEnabled:YES];
            [verticalPaneButton_ setEnabled:YES];
        } else {
            [newTabsInNewWindowButton_ setEnabled:NO];
            [horizontalPaneButton_ setEnabled:windowExists];
            [verticalPaneButton_ setEnabled:windowExists];
        }
    } else {
        [horizontalPaneButton_ setEnabled:NO];
        [verticalPaneButton_ setEnabled:NO];
        [tabButton_ setEnabled:NO];
        [windowButton_ setEnabled:NO];
        [newTabsInNewWindowButton_ setEnabled:NO];
    }
    for (int i = 0; i < 2; ++i) {
        [actions_ setEnabled:([guids count] > 0) forSegment:i];
    }
    [self updateKeyEquivalents];
}

- (void)profileTableSelectionWillChange:(id)profileTable
{
}

- (void)profileTableRowSelected:(id)profileTable
{
    NSSet* guids = [tableView_ selectedGuids];
    for (NSString* guid in guids) {
        PseudoTerminal* terminal = [[iTermController sharedInstance] currentTerminal];
        Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        [[iTermController sharedInstance] launchBookmark:bookmark
                                              inTerminal:terminal];
    }
    if ([closeAfterOpeningBookmark_ state] == NSOnState) {
        [[self window] close];
    }
}

- (IBAction)editBookmarks:(id)sender {
    if ([tableView_ selectedGuid]) {
        [self editSelectedBookmark:nil];
    } else {
        [[PreferencePanel sharedInstance] run];
        [[[PreferencePanel sharedInstance] window] makeKeyAndOrderFront:nil];
        [[PreferencePanel sharedInstance] selectProfilesTab];
    }
}

- (void)editSelectedBookmark:(id)sender
{
    NSString* guid = [tableView_ selectedGuid];
    if (guid) {
        [[PreferencePanel sharedInstance] openToProfileWithGuid:guid selectGeneralTab:YES];
        [[[PreferencePanel sharedInstance] window] makeKeyAndOrderFront:nil];
    }
}

- (NSMenu*)profileTable:(id)profileTable menuForEvent:(NSEvent*)theEvent
{
    NSMenu* menu =[[[NSMenu alloc] initWithTitle:@"Contextual Menu"] autorelease];

    int count = [[profileTable selectedGuids] count];
    if (count == 1) {
        [menu addItemWithTitle:@"Edit Profile..."
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

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kNonTerminalWindowBecameKeyNotification
                                                        object:nil
                                                      userInfo:nil];
    [tableView_ focusSearchField];
}

- (IBAction)closeAfterOpeningChanged:(id)sender
{
    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:[NSNumber numberWithBool:[closeAfterOpeningBookmark_ state] == NSOnState]
              forKey:kCloseBookmarksWindowAfterOpeningKey];
}

- (IBAction)newTabsInNewWindow:(id)sender
{
    [self _openBookmarkInTab:YES firstInWindow:YES inPane:NO_PANE];
    if ([closeAfterOpeningBookmark_ state] == NSOnState) {
        [[self window] close];
    }
}

- (void)windowDidMove:(NSNotification *)notification {
    [[self window] invalidateRestorableState];
}

- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

@end
