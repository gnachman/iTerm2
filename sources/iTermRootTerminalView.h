//
//  iTermRootTerminalView.h
//  iTerm2
//
//  Created by George Nachman on 7/3/15.
//
//

#import <Cocoa/Cocoa.h>
#import "SolidColorView.h"

extern const CGFloat kHorizontalTabBarHeight;

@class iTermTabBarControlView;
@protocol iTermTabBarControlViewDelegate;
@class iTermToolbeltView;
@protocol iTermToolbeltViewDelegate;
@protocol PSMTabBarControlDelegate;
@class PTYTabView;

@protocol iTermRootTerminalViewDelegate<iTermTabBarControlViewDelegate>
- (void)repositionWidgets;
- (void)rootTerminalViewDidResizeContentArea;
- (BOOL)haveTopBorder;
- (BOOL)haveBottomBorder;
- (BOOL)haveLeftBorder;
- (BOOL)haveRightBorder;
- (BOOL)anyFullScreen;
- (BOOL)exitingLionFullscreen;
- (BOOL)divisionViewShouldBeVisible;
- (NSWindow *)window;
@end

@interface iTermRootTerminalView : SolidColorView

// TODO: Get rid of this
@property(nonatomic, assign) id<iTermRootTerminalViewDelegate> delegate;

// The tabview occupies almost the entire window. Each tab has an identifier
// which is a PTYTab.
@property(nonatomic, readonly) PTYTabView *tabView;

// This is a sometimes-visible control that shows the tabs and lets the user
// change which is visible.
@property(nonatomic, readonly) iTermTabBarControlView *tabBarControl;

// Gray line dividing tab/title bar from content. Will be nil if a division
// view isn't needed such as for fullscreen windows or windows without a
// title bar (e.g., top-of-screen).
@property(nonatomic, readonly) SolidColorView *divisionView;

// Toolbelt view. Goes on the right side of the terminal window, if visible.
@property(nonatomic, readonly) iTermToolbeltView *toolbelt;

// Should the toolbelt be visible?
@property(nonatomic, assign) BOOL shouldShowToolbelt;

// How wide the toolbelt should be. User may drag it to change.
// ALWAYS USE THE FLOOR OF THIS VALUE!
@property(nonatomic, assign) CGFloat toolbeltWidth;

// TODO: Remove this
@property(nonatomic, readonly) NSRect toolbeltFrame;

@property(nonatomic, readonly) BOOL scrollbarShouldBeVisible;

@property(nonatomic, readonly) BOOL tabBarShouldBeVisible;

@property(nonatomic, readonly) CGFloat tabviewWidth;

@property(nonatomic, readonly) CGFloat leftTabBarWidth;

- (instancetype)initWithFrame:(NSRect)frame
                        color:(NSColor *)color
               tabBarDelegate:(id<iTermTabBarControlViewDelegate, PSMTabBarControlDelegate>)tabBarDelegate
                     delegate:(id<iTermRootTerminalViewDelegate, iTermToolbeltViewDelegate>)delegate;  // TODO: This should hopefully go away

// Update the division view's frame and set it visible/hidden per |shouldBeVisible|.
- (void)updateDivisionView;

// Perform a layout pass on the toolbelt, and hide/show it as needed.
- (void)updateToolbelt;

// TODO: Don't expose this
- (void)constrainToolbeltWidth;

// TODO: Get rid of this
- (void)updateToolbeltFrame;

- (void)shutdown;

- (void)layoutSubviews;

- (BOOL)tabBarShouldBeVisibleWithAdditionalTabs:(int)numberOfAdditionalTabs;

@end
