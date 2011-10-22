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
#import "PSMTabDragAssistant.h"
#import "SessionTitleView.h"

static const float kTargetFrameRate = 1.0/60.0;
static int nextViewId;
static const double kTitleHeight = 22;

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

- (void)markUpdateTime
{
    [previousUpdate_ release];
    previousUpdate_ = [[NSDate date] retain];
}

- (void)clearUpdateTime
{
    [previousUpdate_ release];
    previousUpdate_ = nil;
}

- (void)_initCommon
{
    [self registerForDraggedTypes:[NSArray arrayWithObjects:@"iTermDragPanePBType", @"PSMTabBarControlItemPBType", nil]];
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
        [self setSession:session];
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
    [previousUpdate_ release];
    [title_ removeFromSuperview];
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
    [[session_ TEXTVIEW] setDimmingAmount:currentDimmingAmount_];
}

- (void)fadeAnimation
{
    timer_ = nil;
    float elapsed = [[NSDate date] timeIntervalSinceDate:previousUpdate_];
    float newDimmingAmount = currentDimmingAmount_ + elapsed * changePerSecond_;
    [self clearUpdateTime];
    if ((changePerSecond_ > 0 && newDimmingAmount > targetDimmingAmount_) ||
        (changePerSecond_ < 0 && newDimmingAmount < targetDimmingAmount_)) {
        currentDimmingAmount_ = targetDimmingAmount_;
        [[session_ TEXTVIEW] setDimmingAmount:targetDimmingAmount_];
    } else {
        [[session_ TEXTVIEW] setDimmingAmount:newDimmingAmount];
        currentDimmingAmount_ = newDimmingAmount;
        [self markUpdateTime];
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
    [self markUpdateTime];
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

- (double)adjustedDimmingAmount
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

    return amount;
}

- (void)updateDim
{
    double amount = [self adjustedDimmingAmount];

    [self _dimShadeToDimmingAmount:amount];
    [title_ setDimmingAmount:amount];
}

- (void)setDimmed:(BOOL)isDimmed
{
    if (shuttingDown_) {
        return;
    }
    if (isDimmed == dim_) {
        return;
    }
    if (session_) {
        dim_ = isDimmed;
        [self updateDim];
    } else {
        dim_ = isDimmed;
        currentDimmingAmount_ = [self adjustedDimmingAmount];
    }
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
    static int inme;
    if (inme) {
        // Avoid infinite recursion. Not quite sure why this happens, but a call
        // to [title_ mouseDown:] or [super mouseDown:] will sometimes (after a
        // few steps through the OS) bring you back here. It only happens
        // consistently when dragging the pane title bar, but it happens inconsitently
        // with clicks in the title bar too.
        return;
    }
    ++inme;
    // A click on the very top of the screen while in full screen mode may not be
    // in any subview!
    NSPoint p = [NSEvent mouseLocation];
    NSPoint basePoint = [[self window] convertScreenToBase:p];
    NSPoint relativePoint = [self convertPointFromBase:basePoint];
    if (title_ && NSPointInRect(relativePoint, [title_ frame])) {
        [title_ mouseDown:event];
        --inme;
        return;
    }
    if (splitSelectionView_) {
        [splitSelectionView_ mouseDown:event];
    } else if (NSPointInRect(relativePoint, [[[self session] SCROLLVIEW] frame]) &&
               [[[self session] TEXTVIEW] mouseDownImpl:event]) {
        [super mouseDown:event];
    }
    --inme;
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

- (void)draggedImage:(NSImage *)draggedImage movedTo:(NSPoint)screenPoint
{
    [[NSCursor closedHandCursor] set];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
    return (isLocal ? NSDragOperationMove : NSDragOperationNone);
}

- (BOOL)ignoreModifierKeysWhileDragging
{
    return YES;
}

- (void)draggedImage:(NSImage *)anImage endedAt:(NSPoint)aPoint operation:(NSDragOperation)operation
{
    if (![[MovePaneController sharedInstance] dragFailed]) {
        [[MovePaneController sharedInstance] dropInSession:nil half:kNoHalf atPoint:aPoint];
    }
}

#pragma mark NSDraggingDestination protocol
- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender
{
    if ([[[sender draggingPasteboard] types] indexOfObject:@"PSMTabBarControlItemPBType"] != NSNotFound) {
        // Dragging a tab handle. Source is a PSMTabBarControl.
        PTYTab *theTab = [[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject] identifier];
        if (theTab == [session_ tab] || [[theTab sessions] count] > 1) {
            return NSDragOperationNone;
        }
    } else if ([[MovePaneController sharedInstance] isMovingSession:[self session]]) {
        return NSDragOperationMove;
    }
    NSRect frame = [self frame];
    splitSelectionView_ = [[SplitSelectionView alloc] initWithFrame:NSMakeRect(0,
                                                                               0,
                                                                               frame.size.width,
                                                                               frame.size.height)];
    [self addSubview:splitSelectionView_];
    [splitSelectionView_ release];
    [[self window] orderFront:nil];
    return NSDragOperationMove;
}

- (void)draggingExited:(id < NSDraggingInfo >)sender
{
    [splitSelectionView_ removeFromSuperview];
    splitSelectionView_ = nil;
}

- (NSDragOperation)draggingUpdated:(id < NSDraggingInfo >)sender
{
    if ([[[sender draggingPasteboard] types] indexOfObject:@"iTermDragPanePBType"] != NSNotFound &&
        [[MovePaneController sharedInstance] isMovingSession:[self session]]) {
        return NSDragOperationMove;
    }
    NSPoint point = [self convertPointFromBase:[sender draggingLocation]];
    [splitSelectionView_ updateAtPoint:point];
    return NSDragOperationMove;
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender
{
    if ([[[sender draggingPasteboard] types] indexOfObject:@"iTermDragPanePBType"] != NSNotFound) {
        if ([[MovePaneController sharedInstance] isMovingSession:[self session]]) {
            [[MovePaneController sharedInstance] setDragFailed:YES];
        }
        SplitSessionHalf half = [splitSelectionView_ half];
        [splitSelectionView_ removeFromSuperview];
        splitSelectionView_ = nil;
        return [[MovePaneController sharedInstance] dropInSession:[self session]
                                                             half:half
                                                          atPoint:[sender draggingLocation]];
    } else {
        // Drag a tab into a split
        SplitSessionHalf half = [splitSelectionView_ half];
        [splitSelectionView_ removeFromSuperview];
        splitSelectionView_ = nil;
        PTYTab *theTab = [[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject] identifier];
        return [[MovePaneController sharedInstance] dropTab:theTab
                                                  inSession:[self session]
                                                       half:half
                                                    atPoint:[sender draggingLocation]];
    }
}

- (BOOL)prepareForDragOperation:(id < NSDraggingInfo >)sender
{
    return YES;
}

- (BOOL)wantsPeriodicDraggingUpdates
{
    return YES;
}

- (BOOL)setShowTitle:(BOOL)value
{
    if (value == showTitle_) {
        return NO;
    }
    showTitle_ = value;
    PTYScrollView *scrollView = [session_ SCROLLVIEW];
    NSRect frame = [scrollView frame];
    if (showTitle_) {
        frame.size.height -= kTitleHeight;
        title_ = [[[SessionTitleView alloc] initWithFrame:NSMakeRect(0,
                                                                     self.frame.size.height - kTitleHeight,
                                                                     self.frame.size.width,
                                                                     kTitleHeight)] autorelease];
        [title_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        title_.delegate = self;
        [self addSubview:title_];
    } else {
        frame.size.height += kTitleHeight;
        [title_ removeFromSuperview];
        title_ = nil;
    }
    [scrollView setFrame:frame];
    [self setTitle:[session_ name]];
    return YES;
}

- (void)setTitle:(NSString *)title
{
    if (!title) {
        title = @"";
    }
    title_.title = title;
    [title_ setNeedsDisplay:YES];
}

#pragma mark SessionTitleViewDelegate

- (NSMenu *)menu
{
    return [[session_ TEXTVIEW] menuForEvent:nil];
}

- (void)close
{
    [[[session_ tab] realParentWindow] closeSessionWithConfirmation:session_];
}

- (void)beginDrag
{
    if (![[MovePaneController sharedInstance] session]) {
        [[MovePaneController sharedInstance] beginDrag:session_];
    }
}

@end
