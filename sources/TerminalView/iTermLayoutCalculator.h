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

    /// Requested width of the opt-in harness navigator. Zero disables it.
    CGFloat harnessSidebarWidth;

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

    /// Tab position (PSMTab_TopTab, PSMTab_BottomTab, PSMTab_LeftTab, PSMTab_RightTab)
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
    /// Frame for the harness navigator
    CGRect harnessSidebarFrame;

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

/// Calculate layout for visible right tab bar.
+ (iTermLayoutOutputs)calculateLayoutWithVisibleRightTabBarInputs:(iTermLayoutInputs)inputs;

/// Tabs the tab bar shows while a harness project is selected. Nil means no filter: a window
/// with no tab in the project keeps showing everything. The selected tab is always included so
/// the bar never hides the terminal on screen. Only an explicit project change (reselect) moves
/// the selection, to the first project tab in orderedItems; periodic refreshes never do.
+ (nullable NSSet *)harnessProjectVisibleItemsForOrderedItems:(NSArray *)orderedItems
                                                matchingItems:(NSSet *)matchingItems
                                                 selectedItem:(nullable id)selectedItem
                                                     reselect:(BOOL)reselect
                                                 itemToSelect:(id _Nullable * _Nullable)itemToSelect
    NS_SWIFT_NAME(harnessProjectVisibleItems(orderedItems:matchingItems:selectedItem:reselect:itemToSelect:));

@end

// Tab position constants (matching PSMTabBarControl)
extern const int kLayoutTabPositionTop;
extern const int kLayoutTabPositionBottom;
extern const int kLayoutTabPositionLeft;
extern const int kLayoutTabPositionRight;

NS_ASSUME_NONNULL_END
