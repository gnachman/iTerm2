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

static const float kTargetFrameRate = 1.0/60.0;

@implementation ShadeView

- (void)setAlpha:(float)newAlpha
{
    alpha = newAlpha;
}

- (void)drawRect:(NSRect)rect
{
    [[NSColor blackColor] set];
    NSRectFill(rect);
}

- (void)rightMouseDown:(NSEvent*)event
{
    [[self superview] rightMouseDown:event];
}

@end

@implementation SessionView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        shade_ = [[[ShadeView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)] autorelease];
        [shade_ setAlphaValue:0];
        [shade_ setHidden:YES];
        [self addSubview:shade_];
    }
    return self;
}

- (id)retain
{
    return [super retain];
}

- (oneway void)release
{
    [super release];
}

- (id)autorelease
{
    return [super autorelease];
}

- (id)initWithFrame:(NSRect)frame session:(PTYSession*)session
{
    self = [self initWithFrame:frame];
    if (self) {
        session_ = [session retain];
    }
    return self;
}

- (void)dealloc
{
    [session_ release];
    [super dealloc];
}

- (void)addSubview:(NSView *)aView
{
    // Keep shade on top of any subview.
    [super addSubview:aView];
    [shade_ removeFromSuperview];
    [super addSubview:shade_];
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [shade_ setFrameSize:newSize];
    [shade_ setFrameOrigin:NSMakePoint(0, 0)];
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

- (void)hideShade
{
    [shade_ setHidden:YES];
}

- (void)fadeAnimation
{
    timer_ = nil;
    float elapsed = [[NSDate date] timeIntervalSinceDate:previousUpdate_];
    float newAlpha = currentAlpha_ + elapsed * changePerSecond_;
    [previousUpdate_ release];
    if ((changePerSecond_ > 0 && newAlpha > targetAlpha_) ||
        (changePerSecond_ < 0 && newAlpha < targetAlpha_)) {
        currentAlpha_ = targetAlpha_;
        [shade_ setAlphaValue:targetAlpha_];
        if (targetAlpha_ == 0) {
            [shade_ setHidden:YES];
        }
    } else {
        [shade_ setAlphaValue:newAlpha];
        currentAlpha_ = newAlpha;
        previousUpdate_ = [[NSDate date] retain];
        timer_ = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                  target:self
                                                selector:@selector(fadeAnimation)
                                                userInfo:nil
                                                 repeats:NO];
    }
}

- (void)_dimShadeToAlpha:(float)newAlpha
{
    targetAlpha_ = newAlpha;
    previousUpdate_ = [[NSDate date] retain];
    if (currentAlpha_ == 0 && [shade_ isHidden]) {
        [shade_ setHidden:NO];
    }
    const double kAnimationDuration = 0.250;
    changePerSecond_ = (targetAlpha_ - currentAlpha_) / kAnimationDuration;
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
    [self fadeAnimation];
}

- (double)dimmedAlpha
{
    NSColor* backgroundColor = [session_ backgroundColor];
    NSColor* rgb = [backgroundColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    double brightness = [rgb brightnessComponent];
    // Map brightness onto alpha.
    const double kMaxAlpha = 0.35;
    const double kMinAlpha = 0.1;
    const double kSpan = kMaxAlpha - kMinAlpha;
    return kSpan * (1 - brightness) + kMinAlpha;
}

+ (BOOL)dimmingSupported
{
    static enum { DIMMING_OK, DIMMING_BROKEN, DIMMING_UNKNOWN } cachedResult = DIMMING_UNKNOWN;
    if (cachedResult == DIMMING_UNKNOWN) {
        SInt32 macVersion;

        if (Gestalt(gestaltSystemVersion, &macVersion) == noErr) {
            if (macVersion < 0x1060) {
                cachedResult = DIMMING_BROKEN;
            } else {
                cachedResult = DIMMING_OK;
            }
        } else {
            NSLog(@"Gestalt(gestaltSystemVersion) failed. Assuming 10.6 or greater.");
            cachedResult = DIMMING_OK;
        }
    }
    return cachedResult == DIMMING_OK;
}

- (void)setDimmed:(BOOL)isDimmed
{
    if (![SessionView dimmingSupported]) {
        return;
    }
    if (shuttingDown_) {
        return;
    }
    if (isDimmed == dim_) {
        return;
    }
    dim_ = isDimmed;
    if (isDimmed) {
        currentAlpha_ = 0;
        [shade_ setAlphaValue:0];
        [shade_ setHidden:NO];
        [self _dimShadeToAlpha:[self dimmedAlpha]];
    } else {
        [self _dimShadeToAlpha:0];
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

@end
