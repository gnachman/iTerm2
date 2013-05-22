// -*- mode:objc -*-
// $Id: PTYScrollView.h,v 1.6 2004-03-14 06:05:38 ujwal Exp $
/*
 **  PTYScrollView.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
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
    BOOL hasDarkBackground_;
}

@property (nonatomic, assign) BOOL hasDarkBackground;

+ (BOOL)isCompatibleWithOverlayScrollers;
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
    // If the pattern is set, the backgroundImage is a cached rendered version of it.
    NSColor *backgroundPattern;
    float transparency;

    // Used for working around Lion bug described in setHasVerticalScroller:inInit:
    NSDate *creationDate_;
    NSTimer *timer_;
}

- (void) dealloc;
- (id)initWithFrame:(NSRect)frame hasVerticalScroller:(BOOL)hasVerticalScroller;
- (void)scrollWheel:(NSEvent *)theEvent;
- (void)detectUserScroll;
- (BOOL)isLegacyScroller;

// background image
- (BOOL)hasBackgroundImage;
- (void)setBackgroundImage: (NSImage *) anImage;
- (void)setBackgroundImage: (NSImage *) anImage asPattern:(BOOL)asPattern;
- (void)drawBackgroundImageRect:(NSRect)rect useTransparency:(BOOL)useTransparency;
- (void)drawBackgroundImageRect:(NSRect)rect toPoint:(NSPoint)dest useTransparency:(BOOL)useTransparency;
- (float)transparency;
- (void)setTransparency: (float) theTransparency;

@end
