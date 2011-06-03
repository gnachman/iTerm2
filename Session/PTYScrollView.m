// -*- mode:objc -*-
// $Id: PTYScrollView.m,v 1.23 2008-09-09 22:10:05 yfabian Exp $
/*
 **  PTYScrollView.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: NSScrollView subclass. Handles scroll detection and background images.
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

// Debug option
#define DEBUG_ALLOC           0
#define DEBUG_METHOD_TRACE    0

#import "iTerm/iTerm.h"
#import "Session/PTYScrollView.h"
#import "Session/PTYTextView.h"
#import "Prefs/PreferencePanel.h"

@implementation PTYScroller

- (id)init
{
    userScroll=NO;
    return [super init];
}

+ (BOOL)isCompatibleWithOverlayScrollers
{
    return YES;
}

- (void) mouseDown: (NSEvent *)theEvent
{
    [super mouseDown:theEvent];

    if ([self floatValue] != 1) {
        userScroll = YES;
    } else {
        userScroll = NO;
    }
}

- (void)trackScrollButtons:(NSEvent *)theEvent
{
    [super trackScrollButtons:theEvent];

    if ([self floatValue] != 1) {
        userScroll = YES;
    } else {
        userScroll = NO;
    }
}

- (void)trackKnob:(NSEvent *)theEvent
{
    [super trackKnob:theEvent];

    if ([self floatValue] != 1) {
        userScroll = YES;
    } else {
        userScroll = NO;
    }
}

- (BOOL)userScroll
{
    return userScroll;
}

- (void)setUserScroll:(BOOL)scroll
{
    userScroll = scroll;
}

- (NSScrollerPart)hitPart
{
    return [super hitPart];
}

@end

@implementation PTYScrollView

- (void) dealloc
{
    [backgroundImage release];

    [super dealloc];
}

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]) == nil) {
        return nil;
    }
    
    assert([self contentView] != nil);

    PTYScroller *aScroller;

    aScroller = [[PTYScroller alloc] init];
    [self setVerticalScroller:aScroller];
    [aScroller release];

    return self;
}

- (void)drawBackgroundImageRect:(NSRect)rect useTransparency:(BOOL)useTransparency
{
    [self drawBackgroundImageRect:rect
                          toPoint:NSMakePoint(rect.origin.x,
                                              rect.origin.y + rect.size.height)
                  useTransparency:useTransparency];
}

- (void)drawBackgroundImageRect:(NSRect)rect toPoint:(NSPoint)dest useTransparency:(BOOL)useTransparency
{
    NSRect srcRect;

    // resize image if we need to
    if ([backgroundImage size].width != [self documentVisibleRect].size.width ||
        [backgroundImage size].height != [self documentVisibleRect].size.height) {
        [backgroundImage setSize: [self documentVisibleRect].size];
    }

    srcRect = rect;
    // normalize to origin of visible rectangle
    srcRect.origin.y -= [self documentVisibleRect].origin.y;
    // do a vertical flip of coordinates
    srcRect.origin.y = [backgroundImage size].height - srcRect.origin.y - srcRect.size.height - VMARGIN;

    // draw the image rect
    [[self backgroundImage] compositeToPoint:dest
                                    fromRect:srcRect
                                   operation:NSCompositeCopy
                                    fraction:useTransparency ? (1.0 - [self transparency]) : 1];
}

- (void)scrollWheel:(NSEvent *)theEvent
{
    PTYScroller *verticalScroller = (PTYScroller *)[self verticalScroller];
    NSRect scrollRect;

    scrollRect = [self documentVisibleRect];
    scrollRect.origin.y -= [theEvent deltaY] * [self verticalLineScroll];
    [[self documentView] scrollRectToVisible: scrollRect];

    scrollRect = [self documentVisibleRect];
    if(scrollRect.origin.y+scrollRect.size.height < [[self documentView] frame].size.height)
        [verticalScroller setUserScroll: YES];
    else
        [verticalScroller setUserScroll: NO];
}

- (void)detectUserScroll
{
    NSRect scrollRect;
    PTYScroller *verticalScroller = (PTYScroller *)[self verticalScroller];

    scrollRect= [self documentVisibleRect];
    if(scrollRect.origin.y+scrollRect.size.height < [[self documentView] frame].size.height)
        [verticalScroller setUserScroll: YES];
    else
        [verticalScroller setUserScroll: NO];
}

// background image
- (NSImage *) backgroundImage
{
    return (backgroundImage);
}

- (void) setBackgroundImage: (NSImage *) anImage
{
    [backgroundImage release];
    [anImage retain];
    backgroundImage = anImage;
    [backgroundImage setScalesWhenResized: YES];
    [backgroundImage setSize: [self documentVisibleRect].size];
}

- (float) transparency
{
    return (transparency);
}

- (void)setTransparency:(float)theTransparency
{
    if (theTransparency >= 0 && theTransparency <= 1) {
        transparency = theTransparency;
        [self setNeedsDisplay:YES];
    }
}

@end
