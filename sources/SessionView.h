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
#import "iTermBackgroundColorView.h"
#import "iTermFindDriver.h"
#import "iTermLegacyView.h"
#import "iTermMetalDriver.h"
#import "PTYScrollView.h"
#import "PTYSession.h"
#import "SessionTitleView.h"
#import "SplitSelectionView.h"

@class iTermAnnouncementViewController;
@class iTermFindDriver;
@class iTermImageWrapper;
@class iTermIncrementalMinimapView;
@class iTermLegacyView;
@class iTermMetalDriver;
@protocol iTermSearchResultsMinimapViewDelegate;
@class iTermSearchResultsMinimapView;
@class PTYSession;
@class SplitSelectionView;
@class SessionTitleView;

extern NSString *const SessionViewWasSelectedForInspectionNotification;

@protocol iTermSessionViewDelegate<iTermFindDriverDelegate, iTermLegacyViewDelegate, NSObject>

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

// Drag entered this view.
- (NSDragOperation)sessionViewDraggingEntered:(id<NSDraggingInfo>)sender;
- (void)sessionViewDraggingExited:(id<NSDraggingInfo>)sender;

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
- (BOOL)sessionViewShouldDimOnlyText;
- (NSColor *)sessionViewBackgroundColor;

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
- (void)sessionViewScrollViewDidResize;

// User double clicked on title view.
- (void)sessionViewDoubleClickOnTitleBar;

// Make the textview the first responder
- (void)sessionViewBecomeFirstResponder;

// Current window changed.
- (void)sessionViewDidChangeWindow;

// Announcement shown, changed, or removed.
- (void)sessionViewAnnouncementDidChange:(SessionView *)sessionView;

- (void)sessionViewUserScrollDidChange:(BOOL)userScroll;

- (void)sessionViewDidChangeHoverURLVisible:(BOOL)visible;
- (void)sessionViewNeedsMetalFrameUpdate;

// Please stop using metal and then start again.
- (void)sessionViewRecreateMetalView;

- (iTermStatusBarViewController *)sessionViewStatusBarViewController;

- (iTermVariableScope *)sessionViewScope;

- (BOOL)sessionViewUseSeparateStatusBarsPerPane;
- (CGFloat)sessionViewTransparencyAlpha;
- (NSRect)sessionViewFrameForLegacyView;
- (void)sessionViewDidChangeEffectiveAppearance;
- (BOOL)sessionViewCaresAboutMouseMovement;

- (NSRect)sessionViewOffscreenCommandLineFrameForView:(NSView *)view;
- (void)sessionViewUpdateComposerFrame;

@end

typedef NS_ENUM(NSUInteger, iTermSessionViewFindDriver) {
    iTermSessionViewFindDriverDropDown,  // There is no status bar
    iTermSessionViewFindDriverTemporaryStatusBar,  // The find component will be added to the status bar while it's in use
    iTermSessionViewFindDriverPermanentStatusBar  // The find component is always in the status bar
};

@interface SessionView : NSView <SessionTitleViewDelegate>
// Unique per-process id of view, used for ordering them in PTYTab.
@property(nonatomic, assign) int viewId;

// If a modifier+digit switches panes, this is the value of digit. Used to show in title bar.
@property(nonatomic, assign) int ordinal;
@property(nonatomic, readonly) iTermAnnouncementViewController *currentAnnouncement;
@property(nonatomic, weak) id<iTermSessionViewDelegate> delegate;
@property(nonatomic, readonly) iTermSearchResultsMinimapView *searchResultsMinimap NS_AVAILABLE_MAC(10_14);
@property(nonatomic, readonly) iTermIncrementalMinimapView *marksMinimap NS_AVAILABLE_MAC(10_14);
@property(nonatomic, readonly) PTYScrollView *scrollview;
@property(nonatomic, readonly) PTYScroller *verticalScroller;
@property(nonatomic, readonly) iTermMetalDriver *driver NS_AVAILABLE_MAC(10_11);
@property(nonatomic, readonly) MTKView *metalView NS_AVAILABLE_MAC(10_11);
@property(nonatomic, readonly) BOOL useMetal NS_AVAILABLE_MAC(10_11);

@property(nonatomic, readonly) BOOL isDropDownSearchVisible;
@property(nonatomic, weak) id<iTermFindDriverDelegate> findDriverDelegate;
@property(nonatomic, readonly) BOOL findViewIsHidden;
@property(nonatomic, readonly) BOOL findViewHasKeyboardFocus;
@property(nonatomic, readonly) iTermFindDriver *findDriver;
@property(nonatomic, readonly) iTermFindDriver *findDriverCreatingIfNeeded;
@property(nonatomic, readonly) NSSize internalDecorationSize;
@property(nonatomic, readonly) iTermSessionViewFindDriver findDriverType;
@property(nonatomic, weak) id<iTermSearchResultsMinimapViewDelegate> searchResultsMinimapViewDelegate NS_AVAILABLE_MAC(10_14);
@property(nonatomic, strong) iTermImageWrapper *image;
@property(nonatomic) iTermBackgroundImageMode imageMode;
@property(nonatomic, readonly) BOOL statusBarIsInPaneTitleBar;
@property(nonatomic, readonly) double adjustedDimmingAmount;
@property(nonatomic, readonly) iTermLegacyView *legacyView;

@property(nonatomic) CGFloat composerHeight;

// For macOS 10.14+ when subpixel AA is OFF, this draws the default background color. When there's
// a background image it will be translucent to effect blending. When subpixel AA is ON or the OS
// is 10.13 or earlier then this is hidden. It can't be used with subpixel AA because macOS isn't
// able to take the color it's drawing over into account when choosing the subpixel colors and it
// looks horrible.
@property(nonatomic, strong) iTermSessionBackgroundColorView *backgroundColorView;

// How far the metal view extends beyond the visible part of the viewport, such as under the title
// bar or bottom per-pane status bar.
@property(nonatomic, readonly) NSEdgeInsets extraMargins;

- (void)setTerminalBackgroundColor:(NSColor *)color;

- (void)showFindUI;
- (void)createFindDriverIfNeeded;
- (void)showFilter;

- (void)findViewDidHide;
- (void)findDriverInvalidateFrame;
- (void)setUseMetal:(BOOL)useMetal dataSource:(id<iTermMetalDriverDataSource>)dataSource NS_AVAILABLE_MAC(10_11);;
- (void)didChangeMetalViewAlpha;
- (void)setTransparencyAlpha:(CGFloat)transparencyAlpha
                       blend:(CGFloat)blend;

+ (double)titleHeight;
+ (NSDate*)lastResizeDate;
+ (void)windowDidResize;

- (void)setMetalViewNeedsDisplayInTextViewRect:(NSRect)textViewRect NS_AVAILABLE_MAC(10_11);

- (void)setDimmed:(BOOL)isDimmed;
- (void)setBackgroundDimmed:(BOOL)backgroundDimmed;
- (void)updateDim;
- (void)updateColors;
- (void)saveFrameSize;
- (void)restoreFrameSize;
- (void)setSplitSelectionMode:(SplitSelectionMode)mode move:(BOOL)move session:(id)session;
- (BOOL)setShowTitle:(BOOL)value adjustScrollView:(BOOL)adjustScrollView;
- (BOOL)showTitle;

- (BOOL)setShowBottomStatusBar:(BOOL)value adjustScrollView:(BOOL)adjustScrollView;
- (BOOL)showBottomStatusBar;

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
- (void)updateAnnouncementFrame;

// The frame excluding the per-pane titlebar.
- (NSRect)contentRect;

// Insets the rect by the titlebar and status bar if they are present.
- (NSRect)insetRect:(NSRect)rect flipped:(BOOL)flipped includeBottomStatusBar:(BOOL)includeBottomStatusBar;

- (void)addAnnouncement:(iTermAnnouncementViewController *)announcement;

- (void)createSplitSelectionView;
- (SplitSessionHalf)removeSplitSelectionView;

- (BOOL)setHoverURL:(NSString *)url anchorFrame:(NSRect)anchorFrame;
- (BOOL)hasHoverURL;
- (void)reallyUpdateMetalViewFrame;
- (void)invalidateStatusBar;
- (void)updateFindDriver;

- (void)addSubviewBelowFindView:(NSView *)aView;

// This keeps you from adding views over the find view.
- (void)addSubview:(NSView *)view NS_UNAVAILABLE;
- (void)removeMetalView;

- (void)tabColorDidChange;
- (void)didBecomeVisible;
- (void)showUnobtrusiveMessage:(NSString *)message;
- (void)showUnobtrusiveMessage:(NSString *)message duration:(NSTimeInterval)duration;
- (void)setSuppressLegacyDrawing:(BOOL)suppressLegacyDrawing;
- (void)takeFindDriverFrom:(SessionView *)donorView delegate:(id<iTermFindDriverDelegate>)delegate;

// Sets the next responder for the dropdown find view controller so you can still use menu items
// vended by PTYTextView when it is focused.
- (void)setMainResponder:(NSResponder *)responder;
- (void)updateForAppearanceChange;

@end
