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

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermScrollAccumulator.h"
#import "NSView+iTerm.h"
#import "PTYScrollView.h"
#import "PTYTextView.h"

#import <Cocoa/Cocoa.h>

@interface PTYScroller()
@property (nonatomic, retain) iTermScrollAccumulator *accumulator;
@end

@implementation PTYScroller

+ (BOOL)isCompatibleWithOverlayScrollers {
    return YES;
}

- (void)dealloc {
    [_accumulator release];
    [super dealloc];
}

// rdar://45295749/
- (void)setScrollerStyle:(NSScrollerStyle)scrollerStyle {
    if (@available(macOS 10.14, *)) {
        NSView *reparent = nil;
        NSInteger index = NSNotFound;

        // To work around awful performance issues introduced in Mojave caused
        // by putting a scrollview over the MTKView making the window server do
        // an offscreen render (in iOS parlance) we reparent the scroller to be
        // a subview of SessionView. That fixes the performance problem, but
        // introduces a new issue: when the scroller style changes from legacy
        // to overlay, it becomes invisible. Why? Because I'm doing things I
        // shouldn't be doing. But we can fool NSScrollView by briefly
        // reparenting it during setScrollerStyle:.
        if (self.scrollerStyle != scrollerStyle && scrollerStyle == NSScrollerStyleOverlay) {
            NSView *preferredSuperview = [self superview];
            if (preferredSuperview) {
                index = [preferredSuperview.subviews indexOfObject:self];
                NSScrollView *scrollview = [self.ptyScrollerDelegate ptyScrollerScrollView];
                if (preferredSuperview != scrollview && scrollview != nil) {
                    DLog(@"Scroller style changing to overlay. Remove self from %@, add to %@", preferredSuperview, scrollview);
                    reparent = preferredSuperview;
                    [scrollview addSubview:self];
                }
            }
        }

        [super setScrollerStyle:scrollerStyle];

        if (reparent && index != NSNotFound) {
            DLog(@"Return to being child of %@", reparent);
            [reparent insertSubview:self atIndex:index];
        }
    } else {
        [super setScrollerStyle:scrollerStyle];
    }
}

- (iTermScrollAccumulator *)accumulator {
    if (!_accumulator) {
        _accumulator = [[iTermScrollAccumulator alloc] init];
    }
    return _accumulator;
}

- (void)setUserScroll:(BOOL)userScroll {
    if (!userScroll && _userScroll) {
        [_accumulator reset];
    }
    if (userScroll != _userScroll) {
        _userScroll = userScroll;
        [_ptyScrollerDelegate userScrollDidChange:userScroll];
    }
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
    // Sadly the superclass's -scroller property may return a dealloc'ed instance.
    NSScroller *_scroller;
}

+ (BOOL)isCompatibleWithResponsiveScrolling {
    return NO;
}

- (instancetype)initWithFrame:(NSRect)frame hasVerticalScroller:(BOOL)hasVerticalScroller {
    self = [super initWithFrame:frame];
    if (self) {
        [self setHasVerticalScroller:YES];
        assert([self contentView] != nil);

        PTYScroller *aScroller;

        aScroller = [[PTYScroller alloc] init];
        [self setVerticalScroller:aScroller];
        [aScroller release];
        self.verticalScrollElasticity = NSScrollElasticityNone;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(it_scrollViewDidScroll:) name:NSScrollViewDidLiveScrollNotification object:self];
    }

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_scroller release];

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ visibleRect:%@", [super description],
               [NSValue valueWithRect:[self documentVisibleRect]]];
}

- (PTYScroller *)ptyVerticalScroller {
    return (PTYScroller *)[super verticalScroller];
}

- (void)it_scrollViewDidScroll:(id)sender {
    [self detectUserScroll];
}

- (CGFloat)accumulateVerticalScrollFromEvent:(NSEvent *)theEvent {
    const CGFloat lineHeight = self.verticalLineScroll;
    if ([iTermAdvancedSettingsModel useModernScrollWheelAccumulator]) {
        return [self.ptyVerticalScroller.accumulator deltaYForEvent:theEvent lineHeight:lineHeight];
    } else {
        return [self.ptyVerticalScroller.accumulator legacyDeltaYForEvent:theEvent lineHeight:lineHeight];
    }
}

// The scroll wheel handling code is like Mr. Burns: it has every possible
// disease and they are in perfect balance.
//
// Overriding scrollWheel: is a horror show of undocumented crazytimes. This is
// hinted at in various places in the documentation, release notes from a
// decade ago, stack overflow, and my nightmares. But it must be done.
//
// If you turn on the "hide scrollbars" setting then PTYTextView's scrollWheel:
// does not get momentum scrolling. The only way to get momentum scrolling in
// that case is to do what is done in the else branch here.
//
// Note that -[PTYTextView scrollWheel:] can elect not to call [super
// scrollWheel] when reporting mouse events, in which case this does not get
// called.
//
// We HAVE to call super when the scroll bars are not hidden because otherwise
// you get issue 6637.
- (void)scrollWheel:(NSEvent *)theEvent {
    if (self.hasVerticalScroller) {
        [super scrollWheel:theEvent];
    } else {
        NSRect scrollRect;

        scrollRect = [self documentVisibleRect];

        CGFloat amount = [self accumulateVerticalScrollFromEvent:theEvent];
        scrollRect.origin.y -= amount * self.verticalLineScroll;
        [[self documentView] scrollRectToVisible:scrollRect];

        [self detectUserScroll];
    }
}

- (void)detectUserScroll {
    NSRect scrollRect;
    PTYScroller *verticalScroller = (PTYScroller *)[self verticalScroller];

    scrollRect = [self documentVisibleRect];
    verticalScroller.userScroll =
        scrollRect.origin.y + scrollRect.size.height < [[self documentView] frame].size.height;
}

- (BOOL)isLegacyScroller {
    return [(NSScrollView*)self scrollerStyle] == NSScrollerStyleLegacy;
}

- (void)setVerticalScroller:(NSScroller *)verticalScroller {
    [_scroller autorelease];
    _scroller = [verticalScroller retain];
    [super setVerticalScroller:verticalScroller];
}

@end
