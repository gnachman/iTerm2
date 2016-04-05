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
#import "PTYSession.h"
#import "SessionTitleView.h"

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
- (NSDragOperation)sessionViewDraggingEntered:(id<NSDraggingInfo>)sender; /*
    PTYSession *movingSession = [[MovePaneController sharedInstance] session];
    if ([[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] != NSNotFound) {
        // Dragging a tab handle. Source is a PSMTabBarControl.
        PTYTab *theTab = (PTYTab *)[[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject] identifier];
        if (_session.tab == theTab || [[theTab sessions] count] > 1) {
            return NSDragOperationNone;
        }
        if (![[theTab activeSession] isCompatibleWith:[self session]]) {
            // Can't have heterogeneous tmux controllers in one tab.
            return NSDragOperationNone;
        }
    } else if ([[MovePaneController sharedInstance] isMovingSession:[self session]]) {
        // Moving me onto myself
        return NSDragOperationMove;
    } else if (![movingSession isCompatibleWith:[self session]]) {
        // We must both be non-tmux or belong to the same session.
        return NSDragOperationNone;
    }
    NSRect frame = [self frame];
    _splitSelectionView = [[SplitSelectionView alloc] initWithFrame:NSMakeRect(0,
                                                                               0,
                                                                               frame.size.width,
                                                                               frame.size.height)];
    [self addSubview:_splitSelectionView];
    [_splitSelectionView release];
    [[self window] orderFront:nil];
    return NSDragOperationMove;
*/
- (NSDragOperation)sessionViewDraggingUpdated:(id<NSDraggingInfo>)sender; /*
    if ([[[sender draggingPasteboard] types] indexOfObject:iTermMovePaneDragType] != NSNotFound &&
        [[MovePaneController sharedInstance] isMovingSession:[self session]]) {
        return NSDragOperationMove;
    }
    NSPoint point = [self convertPoint:[sender draggingLocation] fromView:nil];
    [_splitSelectionView updateAtPoint:point];
    return NSDragOperationMove;
*/
- (BOOL)sessionViewPerformDragOperation:(id<NSDraggingInfo>)sender; /*
    if ([[[sender draggingPasteboard] types] indexOfObject:iTermMovePaneDragType] != NSNotFound) {
        if ([[MovePaneController sharedInstance] isMovingSession:[self session]]) {
            if (![_delegate sessionViewHasSiblings] && ![_delegate sessionViewBelongsToFullScreenWindow]) {
                // If you dragged a session from a tab with split panes onto itself then do nothing.
                // But if you drag a session onto itself in a tab WITHOUT split panes, then move the
                // whole window.
                [[MovePaneController sharedInstance] moveWindowBy:[sender draggedImageLocation]];
            }
            // Regardless, we must say the drag failed because otherwise
            // draggedImage:endedAt:operation: will try to move the session to its own window.
            [[MovePaneController sharedInstance] setDragFailed:YES];
            return NO;
        }
        SplitSessionHalf half = [_splitSelectionView half];
        [_splitSelectionView removeFromSuperview];
        _splitSelectionView = nil;
        return [[MovePaneController sharedInstance] dropInSession:[self session]
                                                             half:half
                                                          atPoint:[sender draggingLocation]];
    } else {
        // Drag a tab into a split
        SplitSessionHalf half = [_splitSelectionView half];
        [_splitSelectionView removeFromSuperview];
        _splitSelectionView = nil;
        PTYTab *theTab = (PTYTab *)[[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject] identifier];
        return [[MovePaneController sharedInstance] dropTab:theTab
                                                  inSession:[self session]
                                                       half:half
                                                    atPoint:[sender draggingLocation]];
    }
*/
- (BOOL)sessionViewHasSiblings;  // _session.delegate.sessions.count == 1
- (BOOL)sessionViewBelongsToFullScreenWindow;  // !_session.delegate.realParentWindow.anyFullScreen
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

+ (double)titleHeight;
+ (NSDate*)lastResizeDate;
+ (void)windowDidResize;

- (void)setDimmed:(BOOL)isDimmed;
- (FindViewController*)findViewController;
- (void)setBackgroundDimmed:(BOOL)backgroundDimmed;
- (void)updateDim;
- (void)saveFrameSize;
- (void)restoreFrameSize;
- (void)setSplitSelectionMode:(SplitSelectionMode)mode move:(BOOL)move;
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

@end
