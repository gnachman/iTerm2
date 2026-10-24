/*
 **  PTYTabView.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: NSTabView subclass.
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

#import "PTYTabView.h"
#import <Carbon/Carbon.h>

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermKeyBindingAction.h"
#import "iTermKeyMappings.h"
#import "iTermKeystroke.h"
#import "iTermPreferences.h"
#import "iTermSwipeTracker.h"
#import "ITAddressBookMgr.h"
#import "NSEvent+iTerm.h"
#import "NSObject+iTerm.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "iTerm2SharedARC-Swift.h"

const NSUInteger kAllModifiers = (NSEventModifierFlagControl |
                                  NSEventModifierFlagCommand |
                                  NSEventModifierFlagOption |
                                  NSEventModifierFlagShift);

@interface PTYTabView()<iTermSwipeTrackerDelegate>
@end

@implementation PTYTabView {
    // Holds references to tabs with the most recently used one at index 0 and least recently used
    // in the last position.
    NSMutableArray *_tabViewItemsInMRUOrder;

    // If set, then the user has cycled at least once and has not yet let up the modifier keys used
    // to cycle. If the shortcut for cycling doesn't have modifiers, then this will always be NO.
    BOOL _isCyclingWithModifierPressed;

    // Modifiers that are being used for cycling tabs. Only valid if _isCyclingWithModifierPressed
    // is YES.
    NSUInteger _cycleModifierFlags;

    // YES while the tab switcher overlay is open. Implies _isCyclingWithModifierPressed.
    BOOL _switcherActive;

    // Index into _tabViewItemsInMRUOrder of the tab that will be selected when the modifiers are
    // released. Only valid while _switcherActive.
    NSUInteger _switcherIndex;

    // Overlay listing tabs while cycling with a modifier held, if enabled.
    iTermTabSwitcher *_switcher;

    // Handles the arrow, return, and escape keys while the switcher is open.
    id _switcherKeyMonitor;

    // YES while removing a tab, when selecting its neighbor should not close the switcher.
    BOOL _removingTabViewItem;

    // When each tab was last the selected tab, for the switcher’s “last seen” times.
    NSMapTable<NSTabViewItem *, NSDate *> *_lastSelectedDates;

    // For handling swipe outside PTYTextView, such as on pane title bar.
    iTermSwipeTracker *_swipeTracker;
}

@dynamic delegate;

- (instancetype)initWithFrame:(NSRect)aRect {
    self = [super initWithFrame:aRect];
    if (self) {
        _tabViewItemsInMRUOrder = [[NSMutableArray alloc] init];
        _lastSelectedDates = [NSMapTable weakToStrongObjectsMapTable];
        _swipeTracker = [[iTermSwipeTracker alloc] init];
        _swipeTracker.delegate = self;
    }

    return self;
}

- (void)dealloc {
    // Normally removed by -endSwitcherSelecting:. If the tab view goes away with the switcher
    // open, don't leave an app-wide key monitor or an orphaned overlay behind.
    if (_switcherKeyMonitor) {
        [NSEvent removeMonitor:_switcherKeyMonitor];
        _switcherKeyMonitor = nil;
    }
    [_switcher end];
}

#pragma mark - NSView

- (BOOL)acceptsFirstResponder {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.drawsBackground) {
        if ([self.window.appearance.name isEqual:NSAppearanceNameVibrantDark]) {
            [[NSColor blackColor] set];
            dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
            NSRectFill(dirtyRect);
        } else {
            [super drawRect:dirtyRect];
        }
    }
}

#pragma mark - NSTabView

- (void)addTabViewItem:(NSTabViewItem *) aTabViewItem {
    // Let our delegate know
    id<PSMTabViewDelegate> delegate = self.delegate;

    if ([delegate conformsToProtocol:@protocol(PSMTabViewDelegate)]) {
        [delegate tabView:self willAddTabViewItem:aTabViewItem];
    }

    NSTabViewItem *highlighted = [self switcherHighlightedItem];
    [_tabViewItemsInMRUOrder addObject:aTabViewItem];
    [self reloadSwitcherKeepingHighlighted:highlighted];
    [super addTabViewItem:aTabViewItem];
}

- (void)removeTabViewItem:(NSTabViewItem *)tabViewItemToRemove {
    // Let our delegate know.
    id<PSMTabViewDelegate> delegate = self.delegate;
    if ([delegate conformsToProtocol:@protocol(PSMTabViewDelegate)]) {
        [delegate tabView:self willRemoveTabViewItem:tabViewItemToRemove];
    }

    NSTabViewItem *highlighted = [self switcherHighlightedItem];
    [_tabViewItemsInMRUOrder removeObject:tabViewItemToRemove];
    // Selecting a neighbor of a closing tab is not the user choosing a tab, so it leaves the
    // switcher open. The switcher is reloaded below once the tab is gone.
    _removingTabViewItem = YES;

    if (self.selectedTabViewItem == tabViewItemToRemove) {
        NSArray<NSTabViewItem *> *items = self.tabViewItems;
        NSInteger index = [items indexOfObject:tabViewItemToRemove];
        if (index != NSNotFound) {
            if (![iTermAdvancedSettingsModel moveLeftAfterClosingTab]) {
                // Select the next tab to the right if possible
                if (index + 1 < items.count) {
                    [self selectTabViewItem:items[index + 1]];
                }
            } else {
                // Select the next tab to the left if possible
                if (index == 0 && items.count > 1) {
                    [self selectTabViewItem:items[1]];
                } else if (index > 0) {
                    [self selectTabViewItem:items[index - 1]];
                }
            }
        }
    }

    // Remove the item.
    [super removeTabViewItem:tabViewItemToRemove];
    _removingTabViewItem = NO;
    [self reloadSwitcherKeepingHighlighted:highlighted];
}

- (void)insertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(NSInteger)theIndex {
    // Let our delegate know
    id<PSMTabViewDelegate> delegate = self.delegate;

    // Check the boundary
    if (theIndex > [self numberOfTabViewItems]) {
        theIndex = [self numberOfTabViewItems];
    }

    if ([delegate conformsToProtocol:@protocol(PSMTabViewDelegate)]) {
        [delegate tabView:self willInsertTabViewItem:tabViewItem atIndex:theIndex];
    }
    NSTabViewItem *highlighted = [self switcherHighlightedItem];
    [_tabViewItemsInMRUOrder addObject:tabViewItem];
    [self reloadSwitcherKeepingHighlighted:highlighted];

    [super insertTabViewItem:tabViewItem atIndex:theIndex];
}

- (void)selectTabViewItem:(NSTabViewItem *)tabViewItem {
    if (_switcherActive && !_removingTabViewItem) {
        // Chosen some other way, such as by clicking the tab bar. That wins over the switcher.
        DLog(@"Tab selected while the tab switcher is open; closing it");
        [self cancelSwitcher];
    }
    NSTabViewItem *previous = self.selectedTabViewItem;
    if (previous && previous != tabViewItem) {
        [_lastSelectedDates setObject:[NSDate date] forKey:previous];
    }
    [super selectTabViewItem:tabViewItem];

    if (!_isCyclingWithModifierPressed) {
        [_tabViewItemsInMRUOrder removeObject:tabViewItem];
        [_tabViewItemsInMRUOrder insertObject:tabViewItem atIndex:0];
    }
}

- (void)selectTab:(id)sender {
    [self selectTabViewItemWithIdentifier:[sender representedObject]];
}

- (void)previousTab:(id)sender {
    NSTabViewItem *tabViewItem = [self selectedTabViewItem];
    [self selectPreviousTabViewItem:sender];
    if (tabViewItem == [self selectedTabViewItem]) {
        [self selectTabViewItemAtIndex:[self numberOfTabViewItems] - 1];
    }
}

- (void)nextTab:(id)sender {
    NSTabViewItem *tabViewItem = [self selectedTabViewItem];
    [self selectNextTabViewItem:sender];
    if (tabViewItem == [self selectedTabViewItem]) {
        [self selectTabViewItemAtIndex:0];
    }
}

- (NSUInteger)MRUIndexAfter:(NSUInteger)theIndex forwards:(BOOL)forwards {
    if (forwards) {
        theIndex++;
        if (theIndex >= [_tabViewItemsInMRUOrder count]) {
            theIndex = 0;
        }
    } else {
        NSInteger temp = theIndex;
        temp--;
        if (temp < 0) {
            temp = [_tabViewItemsInMRUOrder count] - 1;
        }
        theIndex = temp;
    }
    return theIndex;
}

- (void)cycleForwards:(BOOL)forwards {
    if ([_tabViewItemsInMRUOrder count] == 0) {
        return;
    }
    NSTabViewItem* tabViewItem = [self selectedTabViewItem];
    NSUInteger theIndex = [_tabViewItemsInMRUOrder indexOfObject:tabViewItem];
    if (theIndex == NSNotFound) {
        theIndex = 0;
    }
    NSTabViewItem* next = _tabViewItemsInMRUOrder[[self MRUIndexAfter:theIndex forwards:forwards]];
    // The MRU order won't be changed by cycling until you let up the modifier key in
    // cycleFlagsChanged:.
    [self selectTabViewItem:next];
}

- (void)cycleKeyDownWithModifiers:(NSUInteger)modifierFlags forwards:(BOOL)forwards {
    if (!_isCyclingWithModifierPressed) {
        // Initial press; set modifier mask from current modifiers
        _cycleModifierFlags = (modifierFlags & kAllModifiers);
        _isCyclingWithModifierPressed = (_cycleModifierFlags != 0);
        if (_isCyclingWithModifierPressed &&
            // With one tab there is nothing to switch to.
            _tabViewItemsInMRUOrder.count > 1 &&
            self.window != nil &&
            [iTermPreferences boolForKey:kPreferenceKeyShowTabSwitcherWhenCyclingTabs]) {
            [self beginSwitcher];
        }
    }
    if (_switcherActive) {
        // The tab isn't selected, and the MRU order doesn't change, until the modifiers are
        // released in cycleFlagsChanged:.
        [self moveSwitcherSelectionForwards:forwards];
    } else {
        [self cycleForwards:forwards];
    }
}

- (void)cycleFlagsChanged:(NSUInteger)modifierFlags {
    if (_isCyclingWithModifierPressed && ((modifierFlags & _cycleModifierFlags) == 0)) {
        // Modifiers released while cycling.
        DLog(@"Cycle modifiers released. switcherActive=%@", @(_switcherActive));
        if (_switcherActive) {
            [self commitSwitcherSelection];
            return;
        }
        _isCyclingWithModifierPressed = NO;
        // While this looks like a no-op, it has the effect of re-ordering the MRU list.
        [self selectTabViewItem:[self selectedTabViewItem]];
    }
}

#pragma mark - Tab Switcher

- (NSArray<iTermTabSwitcherItem *> *)switcherItems {
    NSTabViewItem *selected = self.selectedTabViewItem;
    NSMutableArray<iTermTabSwitcherItem *> *items = [NSMutableArray array];
    for (NSTabViewItem *tabViewItem in _tabViewItemsInMRUOrder) {
        NSDate *lastSeen = (tabViewItem == selected) ? nil : [_lastSelectedDates objectForKey:tabViewItem];
        [items addObject:[[iTermTabSwitcherItem alloc] initWithTabViewItem:tabViewItem lastSeen:lastSeen]];
    }
    return items;
}

- (void)beginSwitcher {
    NSUInteger index = [_tabViewItemsInMRUOrder indexOfObject:[self selectedTabViewItem]];
    _switcherIndex = (index == NSNotFound) ? 0 : index;
    _switcherActive = YES;
    DLog(@"Begin tab switcher with %@ tabs, modifiers=%@", @(_tabViewItemsInMRUOrder.count), @(_cycleModifierFlags));
    if (!_switcher) {
        _switcher = [[iTermTabSwitcher alloc] init];
    }
    __weak __typeof(self) weakSelf = self;
    _switcher.hoverHandler = ^(NSInteger index) {
        [weakSelf setSwitcherIndex:index];
    };
    _switcher.clickHandler = ^(NSInteger index) {
        [weakSelf setSwitcherIndex:index];
        [weakSelf commitSwitcherSelection];
    };
    _switcher.scrollHandler = ^(BOOL forwards) {
        [weakSelf moveSwitcherSelectionForwards:forwards];
    };
    _switcher.didShowHandler = ^{
        [weakSelf updatePreviewedTabInTabBar];
    };
    _switcher.avoidedScreenFrame = [self tabBarScreenFrame];
    [_switcher beginWithItems:[self switcherItems]
                selectedIndex:_switcherIndex
                   overWindow:self.window];
    [self updatePreviewedTabInTabBar];
    _switcherKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                handler:^NSEvent * _Nullable(NSEvent *event) {
        // A nil return would swallow the key, so if the tab view is gone, let everything through.
        __strong __typeof(self) strongSelf = weakSelf;
        return strongSelf ? [strongSelf switcherHandleKeyDown:event] : event;
    }];
    // The release of the modifiers arrives as flagsChanged: in the key window. If this window
    // stops being key, or the app stops being active, mid-cycle, it never arrives.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(cancelSwitcher)
                                                 name:NSApplicationDidResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(cancelSwitcher)
                                                 name:NSWindowDidResignKeyNotification
                                               object:self.window];
}

- (void)moveSwitcherSelectionForwards:(BOOL)forwards {
    [self setSwitcherIndex:[self MRUIndexAfter:_switcherIndex forwards:forwards]];
}

- (void)setSwitcherIndex:(NSInteger)index {
    if (!_switcherActive || index < 0 || index >= (NSInteger)_tabViewItemsInMRUOrder.count) {
        return;
    }
    _switcherIndex = index;
    [_switcher selectIndex:_switcherIndex];
    [self updatePreviewedTabInTabBar];
}

- (NSRect)tabBarScreenFrame {
    id<PSMTabViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabBarScreenFrameForTabView:)]) {
        return [delegate tabBarScreenFrameForTabView:self];
    }
    return NSZeroRect;
}

// Outlines the highlighted tab in the tab bar, but only once the overlay is on screen, so a quick
// tap of Cycle Tabs doesn't flash it. Clears the outline once the switcher has ended.
- (void)updatePreviewedTabInTabBar {
    id<PSMTabViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabView:setPreviewedTabViewItem:)]) {
        NSTabViewItem *item = _switcher.isVisible ? [self switcherHighlightedItem] : nil;
        [delegate tabView:self setPreviewedTabViewItem:item];
    }
}

- (void)cancelSwitcher {
    [self endSwitcherSelecting:nil];
}

- (void)commitSwitcherSelection {
    if (!_switcherActive || _switcherIndex >= _tabViewItemsInMRUOrder.count) {
        [self cancelSwitcher];
        return;
    }
    [self endSwitcherSelecting:_tabViewItemsInMRUOrder[_switcherIndex]];
}

// The one way out of the switcher. Selects `tabViewItem` afterwards if it is not nil.
- (void)endSwitcherSelecting:(NSTabViewItem *)tabViewItem {
    if (!_switcherActive) {
        return;
    }
    DLog(@"End tab switcher selecting %@", tabViewItem);
    _switcherActive = NO;
    _isCyclingWithModifierPressed = NO;
    if (_switcherKeyMonitor) {
        [NSEvent removeMonitor:_switcherKeyMonitor];
        _switcherKeyMonitor = nil;
    }
    [_switcher end];
    // _switcherActive is NO, so this removes the outline.
    [self updatePreviewedTabInTabBar];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSApplicationDidResignActiveNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSWindowDidResignKeyNotification
                                                  object:nil];
    // With no tab chosen, reselect the current one. That is not a no-op: it moves the tab to the
    // front of the MRU list, as -cycleFlagsChanged: does without the switcher. The selection can
    // change while the switcher is open without updating the MRU list, such as when the selected
    // tab is closed from the switcher and its neighbor takes over.
    NSTabViewItem *itemToSelect = tabViewItem ?: self.selectedTabViewItem;
    if (itemToSelect) {
        [self selectTabViewItem:itemToSelect];
    }
}

// Call after _tabViewItemsInMRUOrder changes while the switcher is open. Keeps `highlighted`
// highlighted if it is still there, or else the row now in its place.
- (void)reloadSwitcherKeepingHighlighted:(NSTabViewItem *)highlighted {
    if (!_switcherActive) {
        return;
    }
    if (_tabViewItemsInMRUOrder.count < 2) {
        // Nothing left to switch to, such as after closing tabs from the switcher.
        [self cancelSwitcher];
        return;
    }
    const NSUInteger index = [_tabViewItemsInMRUOrder indexOfObject:highlighted];
    _switcherIndex = (index == NSNotFound) ? MIN(_switcherIndex, _tabViewItemsInMRUOrder.count - 1) : index;
    DLog(@"Reload tab switcher with %@ tabs", @(_tabViewItemsInMRUOrder.count));
    _switcher.avoidedScreenFrame = [self tabBarScreenFrame];
    [_switcher updateWithItems:[self switcherItems] selectedIndex:_switcherIndex];
    [self updatePreviewedTabInTabBar];
}

- (NSTabViewItem *)switcherHighlightedItem {
    if (!_switcherActive || _switcherIndex >= _tabViewItemsInMRUOrder.count) {
        return nil;
    }
    return _tabViewItemsInMRUOrder[_switcherIndex];
}

// Closes the highlighted tab the way its close button would. If no confirmation is needed, the
// switcher stays open and reloads without it. A confirmation takes key focus from the window,
// which closes the switcher.
- (void)closeSwitcherHighlightedTab {
    NSTabViewItem *item = [self switcherHighlightedItem];
    if (!item) {
        return;
    }
    DLog(@"Tab switcher closing %@", item);
    __weak __typeof(self) weakSelf = self;
    // Not from inside the event monitor: a confirmation would run a modal loop there.
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.tabViewItems containsObject:item]) {
            return;
        }
        id<PSMTabViewDelegate> delegate = strongSelf.delegate;
        if ([delegate respondsToSelector:@selector(tabView:closeTabViewItemWithConfirmation:)]) {
            [delegate tabView:strongSelf closeTabViewItemWithConfirmation:item];
        }
    });
}

// The user's binding for this keystroke in `tabViewItem`'s active session, or nil if there is none.
- (iTermKeyBindingAction *)keyBindingActionForEvent:(NSEvent *)event inTabViewItem:(NSTabViewItem *)tabViewItem {
    PTYTab *tab = [PTYTab castFrom:tabViewItem.identifier];
    iTermKeyBindingAction *action =
        [iTermKeyMappings actionForKeystroke:[iTermKeystroke withEvent:event]
                                 keyMappings:tab.activeSession.profile[KEY_KEYBOARD_MAP]];
    return action.isActionable ? action : nil;
}

// Selects the highlighted tab and lets `event` through to it. Selecting a tab makes its session
// first responder right away (see -[PseudoTerminal tabView:didSelectTabViewItem:]), and a local
// monitor runs before the event is dispatched, so the key reaches the new tab. Without the
// switcher, cycling selects each tab as it goes, so this is where the key went before too.
- (NSEvent *)commitSwitcherSelectionPassingEvent:(NSEvent *)event {
    [self commitSwitcherSelection];
    DLog(@"Committed tab switcher before key %@. First responder is now %@",
         event, self.window.firstResponder);
    return event;
}

// Returns nil if the event was consumed.
- (NSEvent *)switcherHandleKeyDown:(NSEvent *)event {
    if (!_switcherActive || event.window != self.window) {
        return event;
    }
    if ((event.it_modifierFlags & _cycleModifierFlags) == 0) {
        // The modifiers are up but flagsChanged: never said so. Finish as if it had, then let
        // this key through.
        DLog(@"Key down with cycle modifiers released; committing tab switcher");
        return [self commitSwitcherSelectionPassingEvent:event];
    }
    // The selected tab's session is still first responder, so it is the one that sees Cycle Tabs.
    iTermKeyBindingAction *currentAction = [self keyBindingActionForEvent:event
                                                            inTabViewItem:self.selectedTabViewItem];
    if (currentAction.keyAction == KEY_ACTION_NEXT_MRU_TAB ||
        currentAction.keyAction == KEY_ACTION_PREVIOUS_MRU_TAB) {
        // Pressing Cycle Tabs again. The session sends it back to -cycleKeyDownWithModifiers:.
        return event;
    }
    // Any other key is passed through to the highlighted tab, whose profile decides what it does.
    iTermKeyBindingAction *destinationAction = [self keyBindingActionForEvent:event
                                                                inTabViewItem:[self switcherHighlightedItem]];
    if (destinationAction) {
        // A binding for something else. It acts on the tab being switched to.
        DLog(@"Tab switcher passing bound key %@ through", event);
        return [self commitSwitcherSelectionPassingEvent:event];
    }
    // W is matched by character so it follows the keyboard layout, like Command-W.
    if ([event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"w"] ||
        event.keyCode == kVK_Delete ||
        event.keyCode == kVK_ForwardDelete) {
        [self closeSwitcherHighlightedTab];
        return nil;
    }
    switch (event.keyCode) {
        case kVK_Escape:
            [self cancelSwitcher];
            return nil;
        case kVK_Return:
        case kVK_ANSI_KeypadEnter:
            [self commitSwitcherSelection];
            return nil;
        case kVK_DownArrow:
            [self moveSwitcherSelectionForwards:YES];
            return nil;
        case kVK_UpArrow:
            [self moveSwitcherSelectionForwards:NO];
            return nil;
    }
    // Any other key, such as Control-C, is meant for the tab being switched to, not the one
    // being left.
    return [self commitSwitcherSelectionPassingEvent:event];
}

- (void)scrollWheel:(NSEvent *)event {
    DLog(@"%@", event);
    if (![_swipeTracker handleEvent:event]) {
        [super scrollWheel:event];
    }
}

#pragma mark - iTermSwipeTrackerDelegate

- (iTermSwipeState *)swipeTrackerWillBeginNewSwipe:(iTermSwipeTracker *)tracker {
    if (!self.swipeHandler) {
        return nil;
    }
    return [[iTermSwipeState alloc] initWithSwipeHandler:self.swipeHandler];
}

- (BOOL)swipeTrackerShouldBeginNewSwipe:(iTermSwipeTracker *)tracker {
    return [self.swipeHandler swipeHandlerShouldBeginNewSwipe];
}

@end
