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

// Mouse entered the view.
- (void)sessionViewMouseEntered:(NSEvent *)event;

// Mouse exited the view.
- (void)sessionViewMouseExited:(NSEvent *)event;

// Mouse moved within the view.
- (void)sessionViewMouseMoved:(NSEvent *)event;

// Right mouse button depressed.
- (void)sessionViewRightMouseDown:(NSEvent *)event;

// Should [super mouseDown:] be invoked from mouseDown:?
- (BOOL)sessionViewShouldForwardMouseDownToSuper:(NSEvent *)event;

// Informs the delegate of a change to the dimming amount.
- (void)sessionViewDimmingAmountDidChange:(CGFloat)newDimmingAmount;

// Is this this view part of a visible tab?
- (BOOL)sessionViewIsVisible;

// Requests to draw part of the background image/color.
- (void)sessionViewDrawBackgroundImageInView:(NSView *)view
                                    viewRect:(NSRect)rect
                      blendDefaultBackground:(BOOL)blendDefaultBackground;

// Drag entered this view.
- (NSDragOperation)sessionViewDraggingEntered:(id<NSDraggingInfo>)sender;

// Would the current drop target split this view?
- (BOOL)sessionViewShouldSplitSelectionAfterDragUpdate:(id<NSDraggingInfo>)sender;

// Perform a drag into this view.
- (BOOL)sessionViewPerformDragOperation:(id<NSDraggingInfo>)sender;

// Gives the title to show in the per-pane title bar.
- (NSString *)sessionViewTitle;

// Size of one cell of text.
- (NSSize)sessionViewCellSize;

// Rows, columns in session.
- (VT100GridSize)sessionViewGridSize;

// Is this session's text view the first responder?
- (BOOL)sessionViewTerminalIsFirstResponder;

// Gives the tab color for this session.
- (NSColor *)sessionViewTabColor;

// Gives the hamburger menu.
- (NSMenu *)sessionViewContextMenu;

// Close this session, optionally confirming with the user.
- (void)sessionViewConfirmAndClose;

// Start dragging this session.
- (void)sessionViewBeginDrag;

// How tall does the scrollview's document view need to be?
- (CGFloat)sessionViewDesiredHeightOfDocumentView;

// Should we update the sizes of our subviews when we resize?
- (BOOL)sessionViewShouldUpdateSubviewsFramesAutomatically;

// Returns the accepted size.
- (NSSize)sessionViewScrollViewWillResize:(NSSize)proposedSize;

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

// Layout subviews if automatic updates are allowed by the delegate.
- (void)updateLayout;

// The frame excluding the per-pane titlebar.
- (NSRect)contentRect;

- (void)addAnnouncement:(iTermAnnouncementViewController *)announcement;

- (void)createSplitSelectionView;
- (SplitSessionHalf)removeSplitSelectionView;

@end
