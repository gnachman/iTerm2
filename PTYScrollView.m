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

#import "iTerm.h"
#import "PTYScrollView.h"
#import "FutureMethods.h"
#import "PTYTextView.h"
#import "PreferencePanel.h"
#import "FutureMethods.h"
#import <Cocoa/Cocoa.h>

@interface PTYScrollView (Private)

- (void)setHasVerticalScroller:(BOOL)flag inInit:(BOOL)inInit;

@end

@implementation PTYScroller

@synthesize hasDarkBackground = hasDarkBackground_;

- (id)init
{
    userScroll=NO;
    return [super init];
}

+ (BOOL)isCompatibleWithOverlayScrollers
{
    return YES;
}

- (void)setHasDarkBackground:(BOOL)value {
    if (IsLionOrLater()) {
        // Values copied from NSScroller.h to avoid 10.7 SDK dependency.
        const int defaultStyle = 0;  // NSScrollerKnobStyleDefault
        const int lightStyle = 2;  // NSScrollerKnobStyleLight
        [self futureSetKnobStyle:value ? lightStyle : defaultStyle];
    }
    hasDarkBackground_ = value;
}

- (void)mouseDown: (NSEvent *)theEvent
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

- (BOOL)isLegacyScroller
{
    return [(NSScroller*)self futureScrollerStyle] == FutureNSScrollerStyleLegacy;
}

@end

@implementation PTYScrollView

- (id)initWithFrame:(NSRect)frame hasVerticalScroller:(BOOL)hasVerticalScroller
{
    if ((self = [super initWithFrame:frame]) == nil) {
        return nil;
    }

    [self setHasVerticalScroller:hasVerticalScroller inInit:YES];

    assert([self contentView] != nil);

    PTYScroller *aScroller;

    aScroller = [[PTYScroller alloc] init];
    [self setVerticalScroller:aScroller];
    [aScroller release];

    creationDate_ = [[NSDate date] retain];

    return self;
}

- (void)dealloc
{
    [backgroundImage release];
    [backgroundPattern release];
    [creationDate_ release];
    [timer_ invalidate];
    timer_ = nil;

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ visibleRect:%@", [super description], [NSValue valueWithRect:[self visibleRect]]];
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

    float alpha = useTransparency ? (1.0 - [self transparency]) : 1;
    // resize/create image if we need to
    if ((!backgroundImage && backgroundPattern) ||
        !NSEqualSizes(backgroundImage.size, self.documentVisibleRect.size)) {
        if (backgroundPattern) {
            [backgroundImage release];
            backgroundImage = [[NSImage alloc] initWithSize:self.documentVisibleRect.size];
            [backgroundImage lockFocus];
            [[backgroundPattern colorWithAlphaComponent:alpha] set];
            [backgroundPattern drawSwatchInRect:NSMakeRect(0,
                                                           0,
                                                           self.documentVisibleRect.size.width,
                                                           self.documentVisibleRect.size.height)];
            [backgroundImage unlockFocus];
        } else {
            [backgroundImage setSize:[self documentVisibleRect].size];
        }
    }

    srcRect = rect;
    // normalize to origin of visible rectangle
    srcRect.origin.y -= [self documentVisibleRect].origin.y;
    // do a vertical flip of coordinates
    srcRect.origin.y = [backgroundImage size].height - srcRect.origin.y - srcRect.size.height - VMARGIN;

    // draw the image rect
    [backgroundImage compositeToPoint:dest
                             fromRect:srcRect
                            operation:NSCompositeCopy
                             fraction:alpha];
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

    scrollRect = [self documentVisibleRect];
    if (scrollRect.origin.y + scrollRect.size.height < [[self documentView] frame].size.height)
        [verticalScroller setUserScroll:YES];
    else
        [verticalScroller setUserScroll:NO];
}

- (BOOL)hasBackgroundImage {
    return backgroundImage != nil || backgroundPattern != nil;
}

- (void)setBackgroundImage:(NSImage *)anImage
{
    [self setBackgroundImage:anImage asPattern:NO];
}

- (void)setBackgroundImage:(NSImage *)anImage asPattern:(BOOL)asPattern
{
    [backgroundPattern release];
    backgroundPattern = nil;
    [backgroundImage autorelease];
    backgroundImage = nil;
    if (asPattern) {
        if (anImage) {
            backgroundPattern = [[NSColor colorWithPatternImage:anImage] retain];
        }
    } else {
        backgroundImage = [anImage retain];
        [backgroundImage setScalesWhenResized:YES];
        [backgroundImage setSize:[self documentVisibleRect].size];
    }
}

- (float)transparency
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

- (void)reallyShowScroller
{
    [super setHasVerticalScroller:YES];
    timer_ = nil;
}

- (BOOL)isLegacyScroller
{
    return [(NSScrollView*)self futureScrollerStyle] == FutureNSScrollerStyleLegacy;
}

- (void)setHasVerticalScroller:(BOOL)flag
{
    [self setHasVerticalScroller:flag inInit:NO];
}
@end


@implementation PTYScrollView (Private)

- (void)setHasVerticalScroller:(BOOL)flag inInit:(BOOL)inInit
{
    if ([self isLegacyScroller]) {
        [super setHasVerticalScroller:flag];
        return;
    }

    // Work around a bug in 10.7.0. When using an overlay scroller and a
    // non-white background, a white rectangle is briefly visible on the right
    // side of the window. In that case, delay the initial show of the scroller
    // for a few seconds.
    // This isn't related to PTYScroller or the call to setVerticalScroller: as far
    // as I can tell.
    const NSTimeInterval kScrollerTimeDelay = 0.5;
    if (flag &&
        !timer_ &&
        (inInit || [[NSDate date] timeIntervalSinceDate:creationDate_] < kScrollerTimeDelay)) {
        timer_ = [NSTimer scheduledTimerWithTimeInterval:kScrollerTimeDelay
                                                  target:self
                                                selector:@selector(reallyShowScroller)
                                                userInfo:nil
                                                 repeats:NO];
        return;
    } else if (flag && timer_) {
        return;
    } else if (!flag && timer_) {
        [timer_ invalidate];
        timer_ = nil;
        return;
    } else {
        [super setHasVerticalScroller:flag];
    }
}


@end
