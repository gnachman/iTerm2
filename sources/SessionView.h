// -*- mode:objc -*-
/*
 **  SessionView.h
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

#import <Cocoa/Cocoa.h>
#import "FindViewController.h"
#import "PTYScrollView.h"
#import "PTYSession.h"
#import "SessionTitleView.h"
#import "SplitSelectionView.h"

@class iTermAnnouncementViewController;
@class PTYSession;
@class SplitSelectionView;
@class SessionTitleView;

@protocol iTermSessionViewDelegate<NSObject>
- (void)sessionViewMouseEntered:(NSEvent *)event;  // forward to textview
- (void)sessionViewMouseExited:(NSEvent *)event;  // forward to textview
- (void)sessionViewMouseMoved:(NSEvent *)event;  // forward to textview
- (void)sessionViewRightMouseDown:(NSEvent *)event;  // forward to textview
- (BOOL)sessionViewShouldForwardMouseDownToSuper:(NSEvent *)event;  // forward to textview **mouseDownImpl**
- (void)sessionViewDimmingAmountDidChange:(CGFloat)newDimmingAmount;  // set colorMap.dimmingAmount
- (BOOL)sessionViewIsVisible;  // Just return YES, delegate will be nil otherwise
- (void)sessionViewDrawBackgroundImageInView:(NSView *)view
                                    viewRect:(NSRect)rect
                      blendDefaultBackground:(BOOL)blendDefaultBackground;  // Forward to textViewDrawBackgroundImageInView:viewRect:blendDefaultBackground:
- (NSDragOperation)sessionViewDraggingEntered:(id<NSDraggingInfo>)sender;
- (BOOL)sessionViewShouldSplitSelectionAfterDragUpdate:(id<NSDraggingInfo>)sender;
- (BOOL)sessionViewPerformDragOperation:(id<NSDraggingInfo>)sender;
- (NSString *)sessionViewTitle;  // _session.name
- (NSSize)sessionViewCellSize;  // NSMakeSize([[_session textview] charWidth], [[_session textview] lineHeight]);
- (VT100GridSize)sessionViewGridSize;  // VT100GridSizeMake([_session columns], [_session rows]);
- (BOOL)sessionViewTerminalIsFirstResponder;  // _session.textview.window.firstResponder == _session.textview
- (NSColor *)sessionViewTabColor;  // _session.tabColor
- (NSMenu *)sessionViewContextMenu;  // [[_session textview] titleBarMenu]
- (void)sessionViewConfirmAndClose;  // [[[_session delegate] realParentWindow] closeSessionWithConfirmation:_session]
- (void)sessionViewBeginDrag; /*
    if (![[MovePaneController sharedInstance] session]) {
        [[MovePaneController sharedInstance] beginDrag:_session];
    }
*/

@end

@interface SessionView : NSView <SessionTitleViewDelegate>
// Unique per-process id of view, used for ordering them in PTYTab.
@property(nonatomic, assign) int viewId;

// If a modifier+digit switches panes, this is the value of digit. Used to show in title bar.
@property(nonatomic, assign) int ordinal;
@property(nonatomic, readonly) iTermAnnouncementViewController *currentAnnouncement;
@property(nonatomic, assign) id<iTermSessionViewDelegate> delegate;
@property(nonatomic, readonly) PTYScrollView *scrollview;

+ (double)titleHeight;
+ (NSDate*)lastResizeDate;
+ (void)windowDidResize;

- (void)setDimmed:(BOOL)isDimmed;
- (FindViewController*)findViewController;
- (void)setBackgroundDimmed:(BOOL)backgroundDimmed;
- (void)updateDim;
- (void)saveFrameSize;
- (void)restoreFrameSize;
- (void)setSplitSelectionMode:(SplitSelectionMode)mode move:(BOOL)move session:(id)session;
- (BOOL)setShowTitle:(BOOL)value adjustScrollView:(BOOL)adjustScrollView;
- (BOOL)showTitle;
- (void)setTitle:(NSString *)title;
// For tmux sessions, autoresizing is turned off so the title must be moved
// manually. This repositions the title view and the find view.
- (void)updateTitleFrame;

// Returns the largest possible scrollview frame size that can fit in
// this SessionView.
// It only differs from the scrollview's size for tmux tabs, for which
// autoresizing is off.
- (NSSize)maximumPossibleScrollViewContentSize;

// Smallest SessionView frame that contains our contents based on the session's
// rows and columns.
- (NSSize)compactFrame;

- (void)updateScrollViewFrame;

// The frame excluding the per-pane titlebar.
- (NSRect)contentRect;

- (void)addAnnouncement:(iTermAnnouncementViewController *)announcement;

- (void)createSplitSelectionView;
- (SplitSessionHalf)removeSplitSelectionView;

@end
