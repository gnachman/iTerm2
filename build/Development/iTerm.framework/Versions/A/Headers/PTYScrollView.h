// -*- mode:objc -*-
// $Id: PTYScrollView.h,v 1.6 2004-03-14 06:05:38 ujwal Exp $
/*
 **  PTYScrollView.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: NSScrollView subclass. Currently does not do anything special.
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

@interface PTYScroller : NSScroller
{
    BOOL userScroll;
}

- (id)init;
- (void) mouseDown: (NSEvent *)theEvent;
- (void)trackScrollButtons:(NSEvent *)theEvent;
- (void)trackKnob:(NSEvent *)theEvent;
- (BOOL)userScroll;
- (void)setUserScroll: (BOOL) scroll;

@end

@interface PTYScrollView : NSScrollView
{
	NSImage *backgroundImage;
	float transparency;
}

- (void) dealloc;
- (id)initWithFrame:(NSRect)frame;
- (void)scrollWheel:(NSEvent *)theEvent;
- (void)detectUserScroll;

// background image
- (NSImage *) backgroundImage;
- (void) setBackgroundImage: (NSImage *) anImage;
- (void) drawBackgroundImageRect: (NSRect) rect;
- (float) transparency;
- (void) setTransparency: (float) theTransparency;

@end
