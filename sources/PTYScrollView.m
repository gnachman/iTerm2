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

#import "iTerm.h"
#import "FutureMethods.h"
#import "PreferencePanel.h"
#import "PTYScrollView.h"
#import "PTYTextView.h"

#import <Cocoa/Cocoa.h>

@implementation PTYScroller

+ (BOOL)isCompatibleWithOverlayScrollers {
    return YES;
}

- (void)mouseDown:(NSEvent *)theEvent {
    [super mouseDown:theEvent];

    if ([self floatValue] != 1) {
        _userScroll = YES;
    } else {
        _userScroll = NO;
    }
}

- (void)trackScrollButtons:(NSEvent *)theEvent {
    [super trackScrollButtons:theEvent];

    if ([self floatValue] != 1) {
        _userScroll = YES;
    } else {
        _userScroll = NO;
    }
}

- (void)trackKnob:(NSEvent *)theEvent {
    [super trackKnob:theEvent];

    if ([self floatValue] != 1) {
        _userScroll = YES;
    } else {
        _userScroll = NO;
    }
}

- (BOOL)isLegacyScroller
{
    return [self scrollerStyle] == NSScrollerStyleLegacy;
}

@end

@implementation PTYScrollView {
    // Used for working around Lion bug described in setHasVerticalScroller:inInit:
    NSDate *creationDate_;
    NSTimer *timer_;
}

- (id)initWithFrame:(NSRect)frame hasVerticalScroller:(BOOL)hasVerticalScroller {
    self = [super initWithFrame:frame];
    if (self) {
        [self setHasVerticalScroller:hasVerticalScroller inInit:YES];

        assert([self contentView] != nil);

        PTYScroller *aScroller;

        aScroller = [[PTYScroller alloc] init];
        [self setVerticalScroller:aScroller];
        [aScroller release];

        creationDate_ = [[NSDate date] retain];
    }
    
    return self;
}

- (void)dealloc {
    [creationDate_ release];
    [timer_ invalidate];
    timer_ = nil;

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ visibleRect:%@", [super description],
               [NSValue valueWithRect:[self documentVisibleRect]]];
}

- (void)scrollWheel:(NSEvent *)theEvent {
    NSRect scrollRect;

    scrollRect = [self documentVisibleRect];

    CGFloat delta = [theEvent deltaY];
    // Make sure that a very small scroll event moves by at least one line.
    if (fabs(delta) < 1) {
        if (delta > 0) {
            delta = 1;
        } else if (delta < 0) {
            delta = -1;
        } else {
            // The delta could be 0 in case of touchpad scrolling.
            delta = 0;
        }
    }

    scrollRect.origin.y -= delta * [self verticalLineScroll];
    [[self documentView] scrollRectToVisible:scrollRect];

    [self detectUserScroll];
}

- (void)detectUserScroll {
    NSRect scrollRect;
    PTYScroller *verticalScroller = (PTYScroller *)[self verticalScroller];

    scrollRect = [self documentVisibleRect];
    verticalScroller.userScroll =
        scrollRect.origin.y + scrollRect.size.height < [[self documentView] frame].size.height;
}

- (void)reallyShowScroller {
    [super setHasVerticalScroller:YES];
    timer_ = nil;
}

- (BOOL)isLegacyScroller {
    return [(NSScrollView*)self scrollerStyle] == NSScrollerStyleLegacy;
}

- (void)setHasVerticalScroller:(BOOL)flag {
    [self setHasVerticalScroller:flag inInit:NO];
}

#pragma mark - Private

- (void)setHasVerticalScroller:(BOOL)flag inInit:(BOOL)inInit {
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
