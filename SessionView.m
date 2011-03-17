// -*- mode:objc -*-
/*
 **  SessionView.m
 **
 **  Copyright (c) 2010
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: This view contains a session's scrollview.
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

#import "SessionView.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"

static const float kTargetFrameRate = 1.0/60.0;
static int nextViewId;

@implementation SessionView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        findView_ = [[FindViewController alloc] initWithNibName:@"FindView" bundle:nil];
        [[findView_ view] setHidden:YES];
        [self addSubview:[findView_ view]];
        NSRect aRect = [self frame];
        [findView_ setFrameOrigin:NSMakePoint(aRect.size.width - [[findView_ view] frame].size.width - 30,
                                                     aRect.size.height - [[findView_ view] frame].size.height)];
        viewId_ = nextViewId++;
    }
    return self;
}

- (id)initWithFrame:(NSRect)frame session:(PTYSession*)session
{
    self = [self initWithFrame:frame];
    if (self) {
        session_ = [session retain];
    }
    return self;
}

- (void)addSubview:(NSView *)aView
{
    static BOOL running;
    BOOL wasRunning = running;
    running = YES;
    if (!wasRunning && findView_ && aView != [findView_ view]) {
        [super addSubview:aView positioned:NSWindowBelow relativeTo:[findView_ view]];
    } else {
        [super addSubview:aView];
    }
    running = NO;
}

- (void)dealloc
{
    [session_ release];
    [super dealloc];
}

- (PTYSession*)session
{
    return session_;
}

- (void)setSession:(PTYSession*)session
{
    [session_ autorelease];
    session_ = [session retain];
}

- (void)fadeAnimation
{
    timer_ = nil;
    float elapsed = [[NSDate date] timeIntervalSinceDate:previousUpdate_];
    float newDimmingAmount = currentDimmingAmount_ + elapsed * changePerSecond_;
    [previousUpdate_ release];
    if ((changePerSecond_ > 0 && newDimmingAmount > targetDimmingAmount_) ||
        (changePerSecond_ < 0 && newDimmingAmount < targetDimmingAmount_)) {
        currentDimmingAmount_ = targetDimmingAmount_;
        [[session_ TEXTVIEW] setDimmingAmount:targetDimmingAmount_];
    } else {
        [[session_ TEXTVIEW] setDimmingAmount:newDimmingAmount];
        currentDimmingAmount_ = newDimmingAmount;
        previousUpdate_ = [[NSDate date] retain];
        timer_ = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                  target:self
                                                selector:@selector(fadeAnimation)
                                                userInfo:nil
                                                 repeats:NO];
    }
}

- (void)_dimShadeToDimmingAmount:(float)newDimmingAmount
{
    targetDimmingAmount_ = newDimmingAmount;
    previousUpdate_ = [[NSDate date] retain];
    const double kAnimationDuration = 0.1;
    changePerSecond_ = (targetDimmingAmount_ - currentDimmingAmount_) / kAnimationDuration;
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
    [self fadeAnimation];
}

- (double)dimmedDimmingAmount
{
    return 0.2;
}

- (void)setDimmed:(BOOL)isDimmed
{
    if (shuttingDown_) {
        return;
    }
    if (isDimmed == dim_) {
        return;
    }
    dim_ = isDimmed;
    if (isDimmed) {
        currentDimmingAmount_ = 0;
        [[session_ TEXTVIEW] setDimmingAmount:0];
        [self _dimShadeToDimmingAmount:[self dimmedDimmingAmount]];
    } else {
        [self _dimShadeToDimmingAmount:0];
    }
}

- (void)cancelTimers
{
    shuttingDown_ = YES;
    [timer_ invalidate];
}

- (void)rightMouseDown:(NSEvent*)event
{
    [[[self session] TEXTVIEW] rightMouseDown:event];
}


- (void)mouseDown:(NSEvent*)event
{
    if ([[[self session] TEXTVIEW] mouseDownImpl:event]) {
        [super mouseDown:event];
    }
}

- (FindViewController*)findViewController
{
    return findView_;
}

- (int)viewId
{
    return viewId_;
}

- (void)setFrameSize:(NSSize)frameSize
{
    [super setFrameSize:frameSize];
    if (frameSize.width < 340) {
        [[findView_ view] setFrameSize:NSMakeSize(MAX(150, frameSize.width - 50),
                                                  [[findView_ view] frame].size.height)];
        [findView_ setFrameOrigin:NSMakePoint(frameSize.width - [[findView_ view] frame].size.width - 30,
                                              frameSize.height - [[findView_ view] frame].size.height)];
    } else {
        [[findView_ view] setFrameSize:NSMakeSize(290,
                                                  [[findView_ view] frame].size.height)];
        [findView_ setFrameOrigin:NSMakePoint(frameSize.width - [[findView_ view] frame].size.width - 30,
                                              frameSize.height - [[findView_ view] frame].size.height)];
    }
}

@end
