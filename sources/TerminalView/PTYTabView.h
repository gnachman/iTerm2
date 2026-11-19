/*
 **  PTYTabView.h
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "PSMTabBarControl.h"

@protocol iTermSwipeHandler;
@class PTYTabView;

// Implemented by the window controller of a window with a PTYTabView.
@protocol iTermTabViewReplacementProviding<NSObject>
// The tab to select when the selected one is removed, or nil for the usual
// neighbor. towardTheLeft is the direction the user prefers.
- (NSTabViewItem *)tabView:(PTYTabView *)tabView
            replacementForRemovedTabViewItem:(NSTabViewItem *)tabViewItem
                               towardTheLeft:(BOOL)towardTheLeft;
// A removal that asked for a replacement is done.
- (void)tabViewDidFinishRemovingTabViewItem:(PTYTabView *)tabView;
// The tabs Ctrl-Tab cycling may go to, or nil for all of them. A tab bar
// search limits it to the tabs shown.
- (NSSet<NSTabViewItem *> *)tabViewItemsToCycleAmongInTabView:(PTYTabView *)tabView;
@end

// An NSTabView offers the tab bar control and a view in which one of several NSTabViewItem objects
// (each of which has an associated NSView) is displayed. This subclass doesn't draw the control;
// that's expected to be a subview of its container. That tab bar control is PTYTabView's delegate.
// This implementation adds delegate callbacks as needed by PSMTabBarControl and keeps track of the
// MRU order of tabs, as well as providing methods for cycling among them.
@interface PTYTabView : NSTabView

// Override setDelegate so that it accepts PSMTabBarControl without warning
@property(atomic, weak) id<PSMTabViewDelegate> delegate;
@property(nonatomic, weak) id<iTermSwipeHandler> swipeHandler;

// Selects a tab where sender's -representedObject is a NSTabViewItem. Used from a window's
// context menu.
- (void)selectTab:(id)sender;

// Select tab relative to current one.
- (void)nextTab:(id)sender;
- (void)previousTab:(id)sender;
// Select the adjacent tab, wrapping around at the ends.
- (void)selectNextTabWrapping;
- (void)selectPreviousTabWrapping;

// Handle cycle forwards/cycle backwards actions, often bound to ctrl-tab and ctrl-shift-tab.
- (void)cycleKeyDownWithModifiers:(NSUInteger)modifierFlags forwards:(BOOL)forwards;
// Whether Ctrl-Tab (or the like) is held, stepping through tabs.
@property(nonatomic, readonly) BOOL isCyclingWithModifierPressed;
// Whether the tab switcher overlay is open for the current cycle.
@property(nonatomic, readonly) BOOL isShowingSwitcher;
- (void)cycleFlagsChanged:(NSUInteger)modifierFlags;
- (void)cycleForwards:(BOOL)forwards;
// Call when the tabs the controller lets cycling go to may have changed, such
// as when a tab bar search changes, so an open switcher lists the right tabs.
- (void)tabViewItemsToCycleAmongDidChange;

@end
