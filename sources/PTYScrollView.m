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

@interface PTYScroller()
// Total number of rows scrolled by. Will always be in (-1, 1).
@property(nonatomic) CGFloat accumulatedDeltaY;
@end

@implementation PTYScroller

+ (BOOL)isCompatibleWithOverlayScrollers {
    return YES;
}

- (void)setUserScroll:(BOOL)userScroll {
    if (!userScroll && _userScroll) {
        _accumulatedDeltaY = 0;
    }
    _userScroll = userScroll;
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

@interface PTYClipView : NSClipView
@property (nonatomic) NSRect previousDocumentVisibleRect;
@end

@implementation PTYClipView
@end


@implementation PTYScrollView {
    // Used for working around Lion bug described in setHasVerticalScroller:inInit:
    NSDate *creationDate_;
    NSTimer *timer_;
    NSMutableArray<NSView *> *_floatingSubviews;
}

- (instancetype)initWithFrame:(NSRect)frame hasVerticalScroller:(BOOL)hasVerticalScroller {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView = [[[PTYClipView alloc] init] autorelease];
        self.contentView.postsBoundsChangedNotifications = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(boundsDidChangeNotification:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:[self contentView]];

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
    [_floatingSubviews release];
    timer_ = nil;

    [super dealloc];
}

- (void)redrawSubviewsInRect:(NSRect)rect {
    NSLog(@"Redraw %@", NSStringFromRect(rect));
    [self.documentView setNeedsDisplayInRect:rect];
    for (NSView *view in self.documentView.subviews) {
        NSRect viewRect = [view convertRect:rect fromView:self.documentView];
        [view setNeedsDisplayInRect:viewRect];
    }
}

- (void)boundsDidChangeNotification:(NSNotification *)notification {
    if (!self.contentView.copiesOnScroll) {
        [self redrawSubviewsInRect:self.documentVisibleRect];
        [self redrawFloatingSubviews];
        return;
    }
    NSRect newDocumentVisibleRect = self.documentVisibleRect;
    PTYClipView *clipView = (PTYClipView *)self.contentView;
    NSRect lastDocumentVisibleRect = clipView.previousDocumentVisibleRect;
    NSLog(@"Bounds changed (%f-%f) -> (%f-%f)",
          lastDocumentVisibleRect.origin.y,
          lastDocumentVisibleRect.origin.y + lastDocumentVisibleRect.size.height,
          newDocumentVisibleRect.origin.y,
          newDocumentVisibleRect.origin.y + newDocumentVisibleRect.size.height);
    if (newDocumentVisibleRect.size.width == lastDocumentVisibleRect.size.width) {
        CGFloat newMin = newDocumentVisibleRect.origin.y;
        CGFloat newMax = CGRectGetMaxY(newDocumentVisibleRect);
        CGFloat cleanMin = lastDocumentVisibleRect.origin.y;
        CGFloat cleanMax = CGRectGetMaxY(lastDocumentVisibleRect);
        NSArray *points = @[ @(newMin), @(cleanMin), @(newMax), @(cleanMax) ];
        points = [points sortedArrayUsingSelector:@selector(compare:)];
        __block CGFloat lastValue;
        [points enumerateObjectsUsingBlock:^(id  _Nonnull number, NSUInteger idx, BOOL * _Nonnull stop) {
            CGFloat value = [number doubleValue];
            if (idx > 0) {
                if (lastValue < cleanMin) {
                    // Found a region above cleanMin that needs redrawing
                    [self redrawSubviewsInRect:NSMakeRect(0, lastValue, newDocumentVisibleRect.size.width, value - lastValue)];
                } else if (value > cleanMax) {
                    // Found a region below cleanMax that needs redrawing
                    CGFloat dirtyMin = MAX(cleanMax, lastValue);
                    [self redrawSubviewsInRect:NSMakeRect(0, dirtyMin, newDocumentVisibleRect.size.width, value - dirtyMin)];
                };
            }
            lastValue = value;
        }];
    }

    clipView.previousDocumentVisibleRect = newDocumentVisibleRect;
    [self redrawFloatingSubviews];
}

- (void)redrawFloatingSubviews {
    for (NSView *view in _floatingSubviews) {
        [view setNeedsDisplay:YES];
    }
}

- (void)addFloatingSubview:(NSView *)view forAxis:(NSEventGestureAxis)axis {
    [super addFloatingSubview:view forAxis:axis];
    if (!_floatingSubviews) {
        _floatingSubviews = [[NSMutableArray alloc] init];
    }
    [_floatingSubviews addObject:view];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ visibleRect:%@", [super description],
               [NSValue valueWithRect:[self documentVisibleRect]]];
}

- (PTYScroller *)verticalScroller {
    return (PTYScroller *)[super verticalScroller];
}

static CGFloat RoundTowardZero(CGFloat value) {
    if (value > 0) {
        return floor(value);
    } else {
        return ceil(value);
    }
}

- (CGFloat)accumulateVerticalScrollFromEvent:(NSEvent *)theEvent {
    CGFloat delta = theEvent.scrollingDeltaY;
    if (theEvent.hasPreciseScrollingDeltas) {
        delta /= self.verticalLineScroll;
    }

    PTYScroller *verticalScroller = (PTYScroller *)[self verticalScroller];
    verticalScroller.accumulatedDeltaY += delta;
    CGFloat amount = 0;
    if (fabs(verticalScroller.accumulatedDeltaY) >= 1) {
        amount = RoundTowardZero(verticalScroller.accumulatedDeltaY);
        verticalScroller.accumulatedDeltaY = verticalScroller.accumulatedDeltaY - amount;
    }
    return amount;
}

- (void)scrollWheel:(NSEvent *)theEvent {
    NSRect scrollRect;

    scrollRect = [self documentVisibleRect];

    CGFloat amount = [self accumulateVerticalScrollFromEvent:theEvent];
    scrollRect.origin.y -= amount * [self verticalLineScroll];
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
