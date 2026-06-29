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

// Handle cycle forwards/cycle backwards actions, often bound to ctrl-tab and ctrl-shift-tab.
- (void)cycleKeyDownWithModifiers:(NSUInteger)modifierFlags forwards:(BOOL)forwards;
- (void)cycleFlagsChanged:(NSUInteger)modifierFlags;
- (void)cycleForwards:(BOOL)forwards;

@end
