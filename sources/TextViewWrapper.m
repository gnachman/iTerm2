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
#import "PTYTextView.h"

@implementation TextViewWrapper {
    PTYTextView *child_;
}

- (void)drawRect:(NSRect)rect
{
    [child_.delegate textViewDrawBackgroundImageInView:self
                                              viewRect:rect
                                blendDefaultBackground:YES];
}

- (void)addSubview:(NSView *)child
{
    [super addSubview:child];
    if ([child isKindOfClass:[PTYTextView class]]) {
      child_ = (PTYTextView *)child;
      [self setFrame:NSMakeRect(0, 0, [child frame].size.width, [child frame].size.height)];
      [child setFrameOrigin:NSMakePoint(0, 0)];
      [self setPostsFrameChangedNotifications:YES];
      [self setPostsBoundsChangedNotifications:YES];
    }
}

- (void)willRemoveSubview:(NSView *)subview
{
  if (subview == child_) {
    child_ = nil;
  }
  [super willRemoveSubview:subview];
}

- (NSRect)adjustScroll:(NSRect)proposedVisibleRect
{
    return [child_ adjustScroll:proposedVisibleRect];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    NSRect rect = self.bounds;
    rect.size.height -= VMARGIN;
    rect.origin.y = VMARGIN;
    if (!NSEqualRects(child_.frame, rect)) {
        child_.frame = rect;
    }
}

@end
