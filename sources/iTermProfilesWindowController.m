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

#import "DebugLogging.h"
#import "NSEvent+iTerm.h"
#import "PTYTab.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermSessionLauncher.h"
#import "iTermUserDefaults.h"

static NSString *const kCloseBookmarksWindowAfterOpeningKey = @"CloseBookmarksWindowAfterOpening";
static NSString *const iTermProfilesWindowTagsOpen = @"NoSyncProfilesWindowTagsOpen";

@interface iTermProfilesWindowController()
@property (nonatomic, strong) IBOutlet NSButton* tabButton;
@property (nonatomic, strong) IBOutlet NSButton* windowButton;
@end

@interface iTermProfileWindowContentView : NSView
@property (nonatomic, weak) iTermProfilesWindowController *windowController;
@end

@implementation iTermProfileWindowContentView

// In issue 6770 some people saw the key equivalent stop working. My guess is that view-based
// table views are responsible. This function cuts the gordian knot.
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    DLog(@"iTermProfileWindowContentView: Perform key equivalent: %@", event);
    if ([event.characters isEqualToString:@"\r"]) {
        if (event.it_modifierFlags & NSEventModifierFlagShift) {
            if (self.windowController.windowButton.isEnabled) {
                [self.windowController openBookmarkInWindow:nil];
                return YES;
            }
        } else {
            if (self.windowController.tabButton.isEnabled) {
                [self.windowController openBookmarkInTab:nil];
                return YES;
            }
        }
    }
    BOOL result = [super performKeyEquivalent:event];
    DLog(@"iTermProfileWindowContentView: Perform key equivalent returns %@", @(result));
    return result;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)flagsChanged:(NSEvent *)event {
    [super flagsChanged:event];
    [self.windowController flagsChanged:event];
}

@end

typedef enum {
    HORIZONTAL_PANE,
    VERTICAL_PANE,
    NO_PANE // no gane
} PaneMode;

@interface iTermProfilesWindowRestorer : NSObject<NSWindowRestoration>
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

@interface iTermOpenProfileInTabButton : NSButton
@end

@implementation iTermOpenProfileInTabButton

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    DLog(@"iTermOpenProfileInTabButton: performKeyEquivalent: %@", event);
    BOOL result = [super performKeyEquivalent:event];
    DLog(@"iTermOpenProfileInTabButton: performKeyEquivalent result is %@", @(result));
    return result;
}

@end

@implementation iTermProfilesWindowController {
    IBOutlet ProfileListView* tableView_;
    IBOutlet NSSegmentedControl* actions_;
    IBOutlet NSButton* horizontalPaneButton_;
    IBOutlet NSButton* verticalPaneButton_;
    IBOutlet NSButton* closeAfterOpeningBookmark_;
    IBOutlet NSButton* newTabsInNewWindowButton_;
    IBOutlet NSButton* toggleTagsButton_;
    IBOutlet NSTextField* optionHintLabel_;
    NSImage *_newWindowIcon;
    id _flagsChangedMonitor;
}

@synthesize tabButton = tabButton_;
@synthesize windowButton = windowButton_;

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
        } else {
            [[self window] setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
        }
        [tableView_ setDelegate:self];
        [tableView_ allowMultipleSelections];
        [tableView_ multiColumns];

        NSUserDefaults* prefs = [iTermUserDefaults userDefaults];
        NSNumber* n = [prefs objectForKey:kCloseBookmarksWindowAfterOpeningKey];
        [closeAfterOpeningBookmark_ setState:[n boolValue] ? NSControlStateValueOn : NSControlStateValueOff];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updatePaneButtons:)
                                                     name:@"iTermWindowBecameKey"
                                                   object:nil];
        [[self window] setRestorable:YES];
        [[self window] setRestorationClass:[iTermProfilesWindowRestorer class]];
    }
    return self;
}

- (void)windowDidLoad {
    ((iTermProfileWindowContentView *)self.window.contentView).windowController = self;
    __weak typeof(self) weakSelf = self;
    _flagsChangedMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged handler:^NSEvent *(NSEvent *event) {
        iTermProfilesWindowController *strongSelf = weakSelf;
        if (strongSelf.window.isKeyWindow) {
            [strongSelf flagsChanged:event];
        }
        return event;
    }];
    [self.window makeFirstResponder:self.window.contentView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidResize:)
                                                 name:NSWindowDidResizeNotification
                                               object:self.window];
}

- (void)updateHintPosition {
    if (optionHintLabel_) {
        NSRect frame = optionHintLabel_.frame;
        frame.origin.y = self.window.contentView.frame.size.height - frame.size.height - 5;
        [optionHintLabel_ setFrame:frame];
    }
}

- (void)windowDidResize:(NSNotification *)notification {
    [self updateHintPosition];
}

- (void)awakeFromNib {
    NSNumber *n = [NSNumber castFrom:[[iTermUserDefaults userDefaults] objectForKey:iTermProfilesWindowTagsOpen]];
    if (n.boolValue) {
        [tableView_ setTagsOpen:NO animated:NO];
        [tableView_ setTagsOpen:YES animated:NO];
    }
    // Load the new window icon for split buttons
    _newWindowIcon = [NSImage imageNamed:@"open_in_new_window 2"];
    [horizontalPaneButton_ setImagePosition:NSImageLeft];
    [verticalPaneButton_ setImagePosition:NSImageLeft];
    // Position the hint label at the bottom of the window
    [self updateHintPosition];
}

- (void)flagsChanged:(NSEvent *)event {
    [self updateButtonImagesForModifiers:event.modifierFlags];
}

- (void)updateButtonImagesForModifiers:(NSEventModifierFlags)modifiers {
    BOOL optionPressed = (modifiers & NSEventModifierFlagOption) != 0;
    NSImage *image = optionPressed ? _newWindowIcon : nil;
    [horizontalPaneButton_ setImage:image];
    [verticalPaneButton_ setImage:image];
    
    // Adjust button widths to accommodate the icon
    CGFloat extraWidth = optionPressed ? 20.0 : 0.0;
    NSRect hFrame = horizontalPaneButton_.frame;
    hFrame.size.width = 127.0 + extraWidth;
    [horizontalPaneButton_ setFrame:hFrame];
    
    NSRect vFrame = verticalPaneButton_.frame;
    vFrame.size.width = 111.0 + extraWidth;
    [verticalPaneButton_ setFrame:vFrame];
    
    // Update window button title based on option and selection count
    NSSet *guids = [tableView_ selectedGuids];
    if ([guids count] > 1) {
        [windowButton_ setTitle:optionPressed ? @"New Window" : @"New Windows"];
    } else {
        [windowButton_ setTitle:@"New Window"];
    }
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
        DLog(@"Beep: no guids");
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
            [terminal asyncSplitVertically:(inPane == VERTICAL_PANE)
                                    before:NO
                                   profile:bookmark
                             targetSession:[[terminal currentTab] activeSession]
                                completion:nil
                                     ready:nil];
        } else {
            [iTermSessionLauncher launchBookmark:bookmark
                                      inTerminal:terminal
                              respectTabbingMode:NO
                                      completion:nil];
        }
        isFirst = NO;
    }
}

- (IBAction)openBookmarkInVerticalPane:(id)sender
{
    BOOL windowExists;
    if (([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption) != 0) {
        // Force open in new window when Option key pressed
        windowExists = NO;
    }
    else {
        windowExists = [[iTermController sharedInstance] currentTerminal] != nil;
    }
    [self _openBookmarkInTab:YES firstInWindow:!windowExists inPane:VERTICAL_PANE];
    if ([closeAfterOpeningBookmark_ state] == NSControlStateValueOn) {
        [[self window] close];
    }
}

- (IBAction)openBookmarkInHorizontalPane:(id)sender
{
    BOOL windowExists;
    if (([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption) != 0) {
        // Force open in new window when Option key pressed
        windowExists = NO;
    }
    else {
        windowExists = [[iTermController sharedInstance] currentTerminal] != nil;
    }
    [self _openBookmarkInTab:YES firstInWindow:!windowExists inPane:HORIZONTAL_PANE];
    if ([closeAfterOpeningBookmark_ state] == NSControlStateValueOn) {
        [[self window] close];
    }
}

- (IBAction)openBookmarkInTab:(id)sender{
    // Move "new tabs in new window" functionality to Opt+new tab
    BOOL firstInWindow = !(([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption) != 0);
    [self _openBookmarkInTab:YES firstInWindow:firstInWindow inPane:NO_PANE];
    if ([closeAfterOpeningBookmark_ state] == NSControlStateValueOn) {
        [[self window] close];
    }
}

- (IBAction)openBookmarkInWindow:(id)sender
{
    [self _openBookmarkInTab:NO firstInWindow:NO inPane:NO_PANE];
    if ([closeAfterOpeningBookmark_ state] == NSControlStateValueOn) {
        [[self window] close];
    }
}

- (IBAction)toggleTags:(id)sender {
    [[iTermUserDefaults userDefaults] setBool:!tableView_.tagsVisible
                                              forKey:iTermProfilesWindowTagsOpen];
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
        windowButton_.keyEquivalentModifierMask = NSEventModifierFlagShift;
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
        [windowButton_ setTitle:([guids count] > 1 ? @"New Windows" : @"New Window")];
        if ([guids count] > 1) {
            [newTabsInNewWindowButton_ setEnabled:NO];  // Eliminated per owner suggestion
            [horizontalPaneButton_ setEnabled:YES];
            [verticalPaneButton_ setEnabled:YES];
            // Show option hint label when multiple profiles selected
            if (optionHintLabel_) {
                [optionHintLabel_ setHidden:NO];
                [optionHintLabel_ setStringValue:@"Press option to open profiles in a new window"];
            }
        } else {
            [newTabsInNewWindowButton_ setEnabled:NO];
            [horizontalPaneButton_ setEnabled:windowExists];
            [verticalPaneButton_ setEnabled:windowExists];
            // Hide option hint label when single profile
            if (optionHintLabel_) {
                [optionHintLabel_ setHidden:YES];
            }
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
    [self updateButtonImagesForModifiers:[NSEvent modifierFlags]];
}

- (void)profileTableSelectionWillChange:(id)profileTable
{
}

- (void)profileTableRowSelected:(id)profileTable {
    NSSet *guids = [tableView_ selectedGuids];
    for (NSString *guid in guids) {
        PseudoTerminal* terminal = [[iTermController sharedInstance] currentTerminal];
        Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        if ([[iTermApplication sharedApplication] it_modifierFlags] & NSEventModifierFlagShift) {
            [self _openBookmarkInTab:NO firstInWindow:NO inPane:NO_PANE];
        } else {
            [iTermSessionLauncher launchBookmark:profile
                                      inTerminal:terminal
                              respectTabbingMode:NO
                                      completion:nil];
        }
    }
    if ([closeAfterOpeningBookmark_ state] == NSControlStateValueOn) {
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

- (void)editSelectedBookmark:(id)sender {
    NSString *guid = [tableView_ selectedGuid];
    if (guid) {
        [[PreferencePanel sharedInstance] openToProfileWithGuid:guid
                                               selectGeneralTab:YES
                                                           tmux:NO
                                                          scope:nil
                                                     showWindow:YES];
        [[[PreferencePanel sharedInstance] window] makeKeyAndOrderFront:nil];
    }
}

- (NSMenu *)profileTable:(id)profileTable menuForEvent:(NSEvent *)theEvent {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];

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
    NSUserDefaults* prefs = [iTermUserDefaults userDefaults];
    [prefs setObject:[NSNumber numberWithBool:[closeAfterOpeningBookmark_ state] == NSControlStateValueOn]
              forKey:kCloseBookmarksWindowAfterOpeningKey];
}

- (IBAction)newTabsInNewWindow:(id)sender
{
    [self _openBookmarkInTab:YES firstInWindow:YES inPane:NO_PANE];
    if ([closeAfterOpeningBookmark_ state] == NSControlStateValueOn) {
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
