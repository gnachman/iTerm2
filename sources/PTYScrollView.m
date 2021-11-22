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
#import "NSEvent+iTerm.h"
#import "NSView+iTerm.h"
#import "PreferencePanel.h"
#import "PTYScrollView.h"
#import "PTYTextView.h"

#import <Cocoa/Cocoa.h>

@interface NSScroller(Private)
- (void)_setOverlayScrollerState:(unsigned long long)arg1 forceImmediately:(BOOL)arg2;
@end

@interface PTYScroller()
@property (nonatomic, retain) iTermScrollAccumulator *accumulator;
@end

@implementation PTYScroller

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        if (self.scrollerStyle != NSScrollerStyleOverlay) {
            _ptyScrollerState = PTYScrollerStateLegacy;
        } else {
            _ptyScrollerState = PTYScrollerStateOverlayHidden;
        }
    }
    return self;
}

- (void)_setOverlayScrollerState:(unsigned long long)arg1 forceImmediately:(BOOL)arg2 {
    if (self.scrollerStyle != NSScrollerStyleOverlay) {
        _ptyScrollerState = PTYScrollerStateLegacy;
    } else {
        switch (arg1) {
            case 0:
                _ptyScrollerState = PTYScrollerStateOverlayHidden;
                break;
            case 1:
                _ptyScrollerState = PTYScrollerStateOverlayVisibleNarrow;
                break;
            case 2:
                _ptyScrollerState = PTYScrollerStateOverlayVisibleWide;
                break;
        }
    }
    [self.ptyScrollerDelegate ptyScrollerDidTransitionToState:_ptyScrollerState];
    [super _setOverlayScrollerState:arg1 forceImmediately:arg2];
}

+ (BOOL)isCompatibleWithOverlayScrollers {
    return YES;
}

- (void)dealloc {
    [_accumulator release];
    [super dealloc];
}

// rdar://45295749/
- (void)dismemberForScrollerStyle:(NSScrollerStyle)scrollerStyle NS_AVAILABLE_MAC(10_14) {
    DLog(@"Begin dismembering the scroll bar");
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
    // See note in PTYTextView.m for a perhaps better fix.
    if (self.scrollerStyle != scrollerStyle && scrollerStyle == NSScrollerStyleOverlay) {
        DLog(@"PERFORMING DISMEMBERMENT");
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
}

- (void)setScrollerStyle:(NSScrollerStyle)scrollerStyle {
    DLog(@"%@: set scroller style to %@ from\n%@", self, @(scrollerStyle), [NSThread callStackSymbols]);

    if (scrollerStyle != NSScrollerStyleOverlay) {
        _ptyScrollerState = PTYScrollerStateLegacy;
    } else {
        _ptyScrollerState = PTYScrollerStateOverlayHidden;
    }
    [self.ptyScrollerDelegate ptyScrollerDidTransitionToState:_ptyScrollerState];

    if (PTYScrollView.shouldDismember) {
        [self dismemberForScrollerStyle:scrollerStyle];
        return;
    }
    [super setScrollerStyle:scrollerStyle];
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
        DLog(@"setUserScroll:%@\n%@", @(userScroll), [NSThread callStackSymbols]);
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

+ (BOOL)shouldDismember NS_AVAILABLE_MAC(10_14) {
    return [iTermAdvancedSettingsModel dismemberScrollView];
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
        DLog(@"Set new scroller's style  %@ -> %@", @(aScroller.scrollerStyle), @([NSScroller preferredScrollerStyle]));
        aScroller.scrollerStyle = [NSScroller preferredScrollerStyle];
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
- (void)scrollWheel:(NSEvent *)event {
    if (self.hasVerticalScroller && ![iTermAdvancedSettingsModel fastTrackpad]) {
        if ([iTermAdvancedSettingsModel fixMouseWheel]) {
            NSEvent *fixed = [event eventByRoundingScrollWheelClicksAwayFromZero];
            DLog(@"Fix mouse wheel. %@", fixed);
            [super scrollWheel:fixed];
        } else {
            DLog(@"Use default mouse wheel behavior %@", event);
            [super scrollWheel:event];
        }
    } else {
        DLog(@"Scroll bar invisible or fast trackpad enabled, so use accumulator %@", event);
        NSRect scrollRect;

        scrollRect = [self documentVisibleRect];

        CGFloat amount = [self accumulateVerticalScrollFromEvent:event];
        scrollRect.origin.y -= amount * self.verticalLineScroll;
        DLog(@"Scroll by %@ lines, each with height %@, to scroll from %@ to %@",
             @(amount), @(self.verticalLineScroll), NSStringFromRect(self.documentVisibleRect),
             NSStringFromRect(scrollRect));
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
