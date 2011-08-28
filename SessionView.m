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
#import "PseudoTerminal.h"
#import "SplitSelectionView.h"
#import "MovePaneController.h"

static const float kTargetFrameRate = 1.0/60.0;
static int nextViewId;

// Last time any window was resized TODO(georgen):it would be better to track per window.
static NSDate* lastResizeDate_;

@implementation SessionView

+ (void)initialize
{
    lastResizeDate_ = [[NSDate date] retain];
}

+ (void)windowDidResize
{
    [lastResizeDate_ release];
    lastResizeDate_ = [[NSDate date] retain];
}

- (void)_initCommon
{
    [self registerForDraggedTypes:[NSArray arrayWithObjects:@"iTermDragPanePBType", nil]];
    [lastResizeDate_ release];
    lastResizeDate_ = [[NSDate date] retain];
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self _initCommon];
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
        [self _initCommon];
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
    [self unregisterDraggedTypes];
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
    if ([[PreferencePanel sharedInstance] animateDimming]) {
        changePerSecond_ = (targetDimmingAmount_ - currentDimmingAmount_) / kAnimationDuration;
        if (changePerSecond_ == 0) {
            // Nothing to do.
            return;
        }
        if (timer_) {
            [timer_ invalidate];
            timer_ = nil;
        }
        [self fadeAnimation];
    } else {
        [[session_ TEXTVIEW] setDimmingAmount:newDimmingAmount];
    }
}

- (double)dimmedDimmingAmount
{
    return [[PreferencePanel sharedInstance] dimmingAmount];
}

- (void)updateDim
{
    int x = 0;
    if (dim_) {
        x++;
    }
    if (backgroundDimmed_) {
        x++;
    }
    double scale[] = { 0, 1.0, 1.5 };
    double amount = scale[x] * [self dimmedDimmingAmount];
    // Cap amount within reasonable bounds. Before 1.1, dimming amount was only changed by
    // twiddling the prefs file so it could have all kinds of crazy values.
    amount = MIN(0.9, amount);
    amount = MAX(0, amount);

    [self _dimShadeToDimmingAmount:amount];
}

- (void)setDimmed:(BOOL)isDimmed
{
    if (shuttingDown_) {
        return;
    }
    if (isDimmed == dim_) {
        return;
    }
    if ([[[session_ tab] realParentWindow] broadcastInputToSession:session_]) {
        dim_ = NO;
    } else {
        dim_ = isDimmed;
    }
    [self updateDim];
}

- (void)setBackgroundDimmed:(BOOL)backgroundDimmed
{
    BOOL orig = backgroundDimmed_;
    if ([[PreferencePanel sharedInstance] dimBackgroundWindows]) {
        backgroundDimmed_ = backgroundDimmed;
    } else {
        backgroundDimmed_ = NO;
    }
    if (backgroundDimmed_ != orig) {
        [self updateDim];
    }
}

- (BOOL)backgroundDimmed
{
    return backgroundDimmed_;
}

- (void)cancelTimers
{
    shuttingDown_ = YES;
    [timer_ invalidate];
}

- (void)rightMouseDown:(NSEvent*)event
{
    if (!splitSelectionView_) {
        [[[self session] TEXTVIEW] rightMouseDown:event];
    }
}


- (void)mouseDown:(NSEvent*)event
{
    if (splitSelectionView_) {
        [splitSelectionView_ mouseDown:event];
    } else if ([[[self session] TEXTVIEW] mouseDownImpl:event]) {
        [super mouseDown:event];
    }
}

- (FindViewController*)findViewController
{
    return findView_;
}

- (void)setViewId:(int)viewId
{
    viewId_ = viewId;
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

+ (NSDate*)lastResizeDate
{
    return lastResizeDate_;
}

// This is called as part of the live resizing protocol when you let up the mouse button.
- (void)viewDidEndLiveResize
{
    [lastResizeDate_ release];
    lastResizeDate_ = [[NSDate date] retain];
}

- (void)saveFrameSize
{
    savedSize_ = [self frame].size;
}

- (void)restoreFrameSize
{
    [self setFrameSize:savedSize_];
}

- (void)_createSplitSelectionView:(BOOL)cancelOnly
{
    splitSelectionView_ = [[SplitSelectionView alloc] initAsCancelOnly:cancelOnly
                                                             withFrame:NSMakeRect(0,
                                                                                  0,
                                                                                  [self frame].size.width,
                                                                                  [self frame].size.height)
                                                           withSession:session_
                                                              delegate:[MovePaneController sharedInstance]];
    [splitSelectionView_ setFrameOrigin:NSMakePoint(0, 0)];
    [splitSelectionView_ setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    [self addSubview:splitSelectionView_];
    [splitSelectionView_ release];
}

- (void)setSplitSelectionMode:(SplitSelectionMode)mode
{
    switch (mode) {
        case kSplitSelectionModeOn:
            if (splitSelectionView_) {
                return;
            }
            [self _createSplitSelectionView:NO];
            break;

        case kSplitSelectionModeOff:
            [splitSelectionView_ removeFromSuperview];
            splitSelectionView_ = nil;
            break;

        case kSplitSelectionModeCancel:
            [self _createSplitSelectionView:YES];
            break;
    }
}


#pragma mark NSDraggingSource protocol

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
    return (isLocal ? NSDragOperationMove : NSDragOperationNone);
}

- (BOOL)ignoreModifierKeysWhileDragging
{
    return YES;
}

#pragma mark NSDraggingDestination protocol
- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender
{
    if ([[MovePaneController sharedInstance] isMovingSession:[self session]]) {
        return NSDragOperationNone;
    }
    NSRect frame = [self frame];
    splitSelectionView_ = [[SplitSelectionView alloc] initWithFrame:NSMakeRect(0,
                                                                               0,
                                                                               frame.size.width,
                                                                               frame.size.height)];
    [self addSubview:splitSelectionView_];
    [splitSelectionView_ release];
    return NSDragOperationMove;
}

- (void)draggingExited:(id < NSDraggingInfo >)sender
{
    [splitSelectionView_ removeFromSuperview];
    splitSelectionView_ = nil;
}

- (NSDragOperation)draggingUpdated:(id < NSDraggingInfo >)sender
{
    if ([[MovePaneController sharedInstance] isMovingSession:[self session]]) {
        return NSDragOperationNone;
    }
    NSPoint point = [self convertPointFromBase:[sender draggingLocation]];
    [splitSelectionView_ updateAtPoint:point];
    return NSDragOperationMove;
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender
{
    if ([[MovePaneController sharedInstance] isMovingSession:[self session]]) {
        return NO;
    }
    SplitSessionHalf half = [splitSelectionView_ half];
    [splitSelectionView_ removeFromSuperview];
    splitSelectionView_ = nil;
    return [[MovePaneController sharedInstance] dropInSession:[self session] half:half];
}

- (BOOL)prepareForDragOperation:(id < NSDraggingInfo >)sender
{
    if ([[MovePaneController sharedInstance] isMovingSession:[self session]]) {
        return NO;
    }
    return YES;
}

- (BOOL)wantsPeriodicDraggingUpdates
{
    return YES;
}

@end
