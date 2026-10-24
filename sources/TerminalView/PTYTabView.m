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
#import "iTermSwipeTracker.h"
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

    // Index into _tabViewItemsInMRUOrder of the tab that will be selected when the modifiers are
    // released. Only valid if _isCyclingWithModifierPressed is YES.
    NSUInteger _cycleIndex;

    // Overlay listing tabs while cycling with a modifier held.
    iTermTabSwitcher *_switcher;

    // Handles the arrow and escape keys while the switcher is up. Only valid while cycling.
    id _cycleKeyMonitor;

    // For handling swipe outside PTYTextView, such as on pane title bar.
    iTermSwipeTracker *_swipeTracker;
}

@dynamic delegate;

- (instancetype)initWithFrame:(NSRect)aRect {
    self = [super initWithFrame:aRect];
    if (self) {
        _tabViewItemsInMRUOrder = [[NSMutableArray alloc] init];
        _swipeTracker = [[iTermSwipeTracker alloc] init];
        _swipeTracker.delegate = self;
    }

    return self;
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

    [_tabViewItemsInMRUOrder addObject:aTabViewItem];
    [super addTabViewItem:aTabViewItem];
}

- (void)removeTabViewItem:(NSTabViewItem *)tabViewItemToRemove {
    // Let our delegate know.
    id<PSMTabViewDelegate> delegate = self.delegate;
    if ([delegate conformsToProtocol:@protocol(PSMTabViewDelegate)]) {
        [delegate tabView:self willRemoveTabViewItem:tabViewItemToRemove];
    }

    [_tabViewItemsInMRUOrder removeObject:tabViewItemToRemove];
    [self cancelCycling];

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
    [_tabViewItemsInMRUOrder addObject:tabViewItem];

    [super insertTabViewItem:tabViewItem atIndex:theIndex];
}

- (void)selectTabViewItem:(NSTabViewItem *)tabViewItem {
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
    [self selectTabViewItem:next];
}

- (void)cycleKeyDownWithModifiers:(NSUInteger)modifierFlags forwards:(BOOL)forwards {
    if ([_tabViewItemsInMRUOrder count] == 0) {
        return;
    }
    if (!_isCyclingWithModifierPressed) {
        // Initial press; set modifier mask from current modifiers
        _cycleModifierFlags = (modifierFlags & kAllModifiers);
        _isCyclingWithModifierPressed = (_cycleModifierFlags != 0);
        if (_isCyclingWithModifierPressed) {
            [self beginCycling];
        }
    }
    if (!_isCyclingWithModifierPressed) {
        // No modifier to hold, so there's nothing to preview: switch immediately.
        [self cycleForwards:forwards];
        return;
    }
    // The tab isn't selected, and the MRU order doesn't change, until the modifiers are released
    // in cycleFlagsChanged:.
    [self moveCycleSelectionForwards:forwards];
}

- (void)moveCycleSelectionForwards:(BOOL)forwards {
    _cycleIndex = [self MRUIndexAfter:_cycleIndex forwards:forwards];
    [_switcher selectIndex:_cycleIndex];
}

- (void)beginCycling {
    NSUInteger index = [_tabViewItemsInMRUOrder indexOfObject:[self selectedTabViewItem]];
    _cycleIndex = (index == NSNotFound) ? 0 : index;
    if (!_switcher) {
        _switcher = [[iTermTabSwitcher alloc] init];
    }
    __weak __typeof(self) weakSelf = self;
    _switcher.hoverHandler = ^(NSInteger index) {
        [weakSelf selectCycleIndex:index];
    };
    _switcher.clickHandler = ^(NSInteger index) {
        [weakSelf commitCycleIndex:index];
    };
    [_switcher beginWithTabViewItems:_tabViewItemsInMRUOrder
                       selectedIndex:_cycleIndex
                          overWindow:self.window];
    _cycleKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                             handler:^NSEvent * _Nullable(NSEvent *event) {
        return [weakSelf handleCycleKeyDown:event];
    }];
    // If the app is deactivated mid-cycle we never see the modifiers come up.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(cancelCycling)
                                                 name:NSApplicationDidResignActiveNotification
                                               object:nil];
}

- (void)cancelCycling {
    if (!_isCyclingWithModifierPressed) {
        return;
    }
    _isCyclingWithModifierPressed = NO;
    [self endCycling];
}

- (void)selectCycleIndex:(NSInteger)index {
    if (!_isCyclingWithModifierPressed || index < 0 || index >= (NSInteger)_tabViewItemsInMRUOrder.count) {
        return;
    }
    _cycleIndex = index;
    [_switcher selectIndex:_cycleIndex];
}

// Selects the tab at the given index right away and ends cycling, as if the modifiers had been
// released with that tab highlighted.
- (void)commitCycleIndex:(NSInteger)index {
    if (!_isCyclingWithModifierPressed) {
        return;
    }
    [self selectCycleIndex:index];
    _isCyclingWithModifierPressed = NO;
    [self endCycling];
    if (_cycleIndex < [_tabViewItemsInMRUOrder count]) {
        [self selectTabViewItem:_tabViewItemsInMRUOrder[_cycleIndex]];
    }
}

// Returns nil if the event was consumed.
- (NSEvent *)handleCycleKeyDown:(NSEvent *)event {
    if (!_isCyclingWithModifierPressed || event.window != self.window) {
        return event;
    }
    switch (event.keyCode) {
        case kVK_Escape:
            [self cancelCycling];
            return nil;
        case kVK_Return:
        case kVK_ANSI_KeypadEnter:
            [self commitCycleIndex:_cycleIndex];
            return nil;
        case kVK_DownArrow:
            [self moveCycleSelectionForwards:YES];
            return nil;
        case kVK_UpArrow:
            [self moveCycleSelectionForwards:NO];
            return nil;
    }
    return event;
}

- (void)endCycling {
    if (_cycleKeyMonitor) {
        [NSEvent removeMonitor:_cycleKeyMonitor];
        _cycleKeyMonitor = nil;
    }
    [_switcher end];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSApplicationDidResignActiveNotification
                                                  object:nil];
}

- (void)cycleFlagsChanged:(NSUInteger)modifierFlags {
    if (_isCyclingWithModifierPressed && ((modifierFlags & _cycleModifierFlags) == 0)) {
        // Modifiers released while cycling.
        [self commitCycleIndex:_cycleIndex];
    }
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
