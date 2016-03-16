// -*- mode:objc -*-
/*
 **  FakeWindow.m
 **
 **  Copyright 20101
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Shell window that takes over for a session during instant
 **  replay.
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

#import "FakeWindow.h"
#import "PTYSession.h"
#import "PTYTab.h"

@implementation FakeWindow {
    // FakeWindow always has exactly one session.
    PTYSession* session;

    // Saved state from old window.
    BOOL isFullScreen;
    BOOL isLionFullScreen;
    BOOL isMiniaturized;
    NSRect frame;
    NSScreen* screen;
    NSWindowController<iTermWindowController> * realWindow;

    // Changes the session has initiated that will be delayed and performed
    // in -[rejoin:].
    BOOL hasPendingBlurChange;
    double pendingBlurRadius;
    BOOL pendingBlur;
    BOOL hasPendingClose;
    BOOL hasPendingFitWindowToTab;
    BOOL hasPendingSizeChange;
    int pendingW;
    int pendingH;
    BOOL hasPendingSetWindowTitle;

    BOOL scrollbarShouldBeVisible;
}

- (instancetype)initFromRealWindow:(NSWindowController<iTermWindowController> *)aTerm
                           session:(PTYSession*)aSession {
    self = [super init];
    if (!self) {
        return nil;
    }

    isFullScreen = [aTerm fullScreen];
    isLionFullScreen = [aTerm lionFullScreen];
    isMiniaturized = [[aTerm window] isMiniaturized];
    frame = [[aTerm window] frame];
    screen = [[aTerm window] screen];
    session = [aSession retain];
    realWindow = aTerm;
    scrollbarShouldBeVisible = [aTerm scrollbarShouldBeVisible];
    return self;
}

- (void)dealloc {
    [session release];
    [super dealloc];
}

- (void)rejoin:(NSWindowController<iTermWindowController> *)aTerm
{
    if (hasPendingClose) {
        // TODO(georgen): We don't honor pending closes. It's not safe to close right now because
        // this may release aTerm, but aTerm may exist in the calling stack (in many places!).
        // It might work to start a timer to close it, but that would have some serious unexpected
        // side effects.
        // [aTerm closeSession:session];
        return;
    }

    if (hasPendingBlurChange) {
        if (pendingBlur) {
            [aTerm enableBlur:pendingBlurRadius];
        } else {
            [aTerm disableBlur];
        }
    }
    if (hasPendingSizeChange) {
        [aTerm sessionInitiatedResize:session width:pendingW height:pendingH];
    }
    if (hasPendingFitWindowToTab) {
        [aTerm fitWindowToTab:[aTerm tabForSession:session]];
    }
    if (hasPendingSetWindowTitle) {
        [aTerm setWindowTitle];
    }
    [aTerm updateTabColors];
}

- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height
{
    hasPendingSizeChange = YES;
    pendingW = width;
    pendingH = height;
}

- (BOOL)fullScreen
{
    return isFullScreen;
}

- (BOOL)anyFullScreen
{
    return isLionFullScreen || isFullScreen;
}

- (PTYSession *)currentSession
{
    return session;
}

- (void)closeSession:(PTYSession*)aSession
{
    hasPendingClose = YES;  // TODO: This isn't right with panes.
}

- (void)closeTab:(PTYTab*)theTab
{
    hasPendingClose = YES;
}

- (void)nextTab:(id)sender
{
}

- (void)previousTab:(id)sender
{
}

- (void)enableBlur:(double)radius
{
    hasPendingBlurChange = YES;
    pendingBlurRadius = radius;
    pendingBlur = YES;
}

- (void)disableBlur
{
    hasPendingBlurChange = YES;
    pendingBlur = NO;
}

- (void)fitWindowToTab:(PTYTab*)tab
{
    hasPendingFitWindowToTab = YES;
}

- (PTYTabView *)tabView
{
    return nil;
}

- (void)setWindowTitle
{
    hasPendingSetWindowTitle = YES;
}

- (PTYTab*)currentTab
{
    return nil;
}


- (void)windowSetFrameTopLeftPoint:(NSPoint)point
{
}

- (void)windowPerformMiniaturize:(id)sender
{
}

- (void)windowDeminiaturize:(id)sender
{
}

- (void)windowOrderFront:(id)sender
{
}

- (void)windowOrderBack:(id)sender
{
}

- (BOOL)windowIsMiniaturized
{
    return isMiniaturized;
}

- (NSRect)windowFrame
{
    return frame;
}

- (NSScreen*)windowScreen
{
    return screen;
}

- (BOOL)scrollbarShouldBeVisible
{
    return scrollbarShouldBeVisible;
}

- (NSScrollerStyle)scrollerStyle
{
    return [self anyFullScreen] ? NSScrollerStyleOverlay : [NSScroller preferredScrollerStyle];
}

- (void)updateTabColors
{
}

@end
