/*
 **  ColorsMenuItemView.h
 **
 **  Copyright (c) 2012
 **
 **  Author: Andrea Bonomi
 **
 **  Project: iTerm
 **
 **  Description: Colored Tabs.
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

#import <Cocoa/Cocoa.h>

@interface ColorsMenuItemView : NSView
@property(nonatomic, strong) NSColor *currentColor;
@property(nonatomic, readonly) NSColor *color;

// Returns the preferred size for the menu item view based on the current
// advanced setting for tab colors. Width is fixed to match existing layout;
// height grows to accommodate multiple rows of color chips.
+ (NSSize)preferredSize;

- (void)drawRect:(NSRect)rect;
- (void)mouseUp:(NSEvent*) event;

@end

@interface iTermTabColorMenuItem: NSMenuItem
@property (nonatomic, readonly) ColorsMenuItemView *colorsView;
@end

