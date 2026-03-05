//
//  iTermLayoutCalculator.h
//  iTerm2
//
//  Created by George Nachman on 2/25/26.
//
//  Pure layout calculation logic extracted from iTermRootTerminalView for testability.
//  This class takes layout inputs (dimensions, flags) and returns frame rects
//  with no direct AppKit dependencies.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Input parameters for layout calculation.
/// All dimensions are in points.
typedef struct {
    /// Size of the window's content view
    CGFloat contentViewWidth;
    CGFloat contentViewHeight;

    /// Tab bar dimensions
    CGFloat tabBarHeight;
    CGFloat leftTabBarWidth;

    /// Toolbelt dimensions
    CGFloat toolbeltWidth;
    BOOL shouldShowToolbelt;

    /// Status bar
    CGFloat statusBarHeight;
    BOOL hasStatusBar;
    BOOL statusBarOnTop;  // YES for top, NO for bottom

    /// Tab bar state flags
    BOOL tabBarVisible;
    BOOL tabBarOnLoan;
    BOOL tabBarFlashing;
    BOOL tabBarShouldBeAccessory;
    BOOL tabBarAccessoryOverlapsContent;

    /// Fullscreen state
    BOOL enteringFullscreen;
    BOOL inFullscreen;

    /// Tab position (PSMTab_TopTab, PSMTab_BottomTab, PSMTab_LeftTab)
    int tabPosition;

    /// Division view
    BOOL divisionViewVisible;
    CGFloat divisionViewHeight;

    /// Notch inset (for MacBooks with notch in fullscreen)
    CGFloat notchInset;

    /// Whether to leave empty area at top for transitional tab bar state
    BOOL shouldLeaveEmptyAreaAtTop;

    /// Whether to draw window title in place of tab bar
    BOOL drawWindowTitleInPlaceOfTabBar;
} iTermLayoutInputs;

/// Output frame rects from layout calculation.
typedef struct {
    /// Frame for the tab view (main content area)
    CGRect tabViewFrame;

    /// Frame for the status bar container
    CGRect statusBarFrame;

    /// Frame for the toolbelt
    CGRect toolbeltFrame;

    /// Frame for the tab bar
    CGRect tabBarFrame;

    /// Decoration heights (space consumed by decorations at top/bottom)
    CGFloat decorationHeightTop;
    CGFloat decorationHeightBottom;
} iTermLayoutOutputs;

/// Pure layout calculator with no AppKit dependencies.
/// All layout logic is encapsulated here for easy unit testing.
@interface iTermLayoutCalculator : NSObject

/// Calculate layout frames given input parameters.
/// This is a pure function with no side effects.
+ (iTermLayoutOutputs)calculateLayoutWithInputs:(iTermLayoutInputs)inputs;

/// Calculate the tab view frame, optionally shrinking for fullscreen tab bar.
/// This handles the case when the tab bar is a titlebar accessory that overlaps content.
+ (CGRect)tabViewFrameByShrinkingForFullScreenTabBar:(CGRect)frame
                                          withInputs:(iTermLayoutInputs)inputs
    NS_SWIFT_NAME(tabViewFrame(byShrinkingForFullScreenTabBar:with:));

/// Calculate the toolbelt frame.
+ (CGRect)toolbeltFrameWithInputs:(iTermLayoutInputs)inputs;

/// Calculate layout for hidden tab bar case.
+ (iTermLayoutOutputs)calculateLayoutWithHiddenTabBarInputs:(iTermLayoutInputs)inputs;

/// Calculate layout for visible top tab bar.
+ (iTermLayoutOutputs)calculateLayoutWithVisibleTopTabBarInputs:(iTermLayoutInputs)inputs;

/// Calculate layout for visible bottom tab bar.
+ (iTermLayoutOutputs)calculateLayoutWithVisibleBottomTabBarInputs:(iTermLayoutInputs)inputs;

/// Calculate layout for visible left tab bar.
+ (iTermLayoutOutputs)calculateLayoutWithVisibleLeftTabBarInputs:(iTermLayoutInputs)inputs;

@end

// Tab position constants (matching PSMTabBarControl)
extern const int kLayoutTabPositionTop;
extern const int kLayoutTabPositionBottom;
extern const int kLayoutTabPositionLeft;

NS_ASSUME_NONNULL_END
