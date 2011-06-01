// -*- mode:objc -*-
/*
 **  TextViewWrapper.m
 **
 **  Copyright (c) 2010
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: This wraps a textview and adds a border at the top of
 **  the visible area.
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


#import "TextViewWrapper.h"
#import "iTerm/PTYTextView.h"

@implementation TextViewWrapper

- (void)drawRect:(NSRect)rect
{
    [child_ drawFlippedBackground:NSMakeRect(0,
                                      [[child_ enclosingScrollView] documentVisibleRect].origin.y - VMARGIN,
                                      [self frame].size.width,
                                      VMARGIN)
                   toPoint:NSMakePoint(0, VMARGIN)];
}

- (void)addSubview:(PTYTextView*)child
{
    [super addSubview:child];
    child_ = child;
    [self setFrame:NSMakeRect(0, 0, [child frame].size.width, [child frame].size.height)];
    [child setFrameOrigin:NSMakePoint(0, 0)];
    [self setPostsFrameChangedNotifications:YES];
    [self setPostsBoundsChangedNotifications:YES];
}

- (NSRect)adjustScroll:(NSRect)proposedVisibleRect
{
    return [child_ adjustScroll:proposedVisibleRect];
}

- (BOOL)isFlipped
{
    return YES;
}

@end
