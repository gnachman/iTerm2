//
//  iTermLayoutCalculator.m
//  iTerm2
//
//  Created by George Nachman on 2/25/26.
//
//  IMPORTANT: Tab bar overlap handling has two mutually exclusive mechanisms:
//
//  1. shouldLeaveEmptyAreaAtTop (decoration heights approach):
//     - Used during transitional states when tab bar is on loan but not yet an accessory
//     - Adds tab bar height to decorationHeightTop
//     - Applied in calculateLayoutWithHiddenTabBarInputs
//
//  2. tabViewFrameByShrinkingForFullScreenTabBar (frame shrinking approach):
//     - Used when tab bar IS a titlebar accessory that overlaps content
//     - Shrinks the frame directly by tab bar height
//     - Called after decoration calculation
//
//  These mechanisms are mutually exclusive to avoid double-deduction.
//  When shouldLeaveEmptyAreaAtTop is true, frame shrinking is skipped.
//

#import "iTermLayoutCalculator.h"

// These match the PSMTabBarControl constants
const int kLayoutTabPositionTop = 0;
const int kLayoutTabPositionBottom = 1;
const int kLayoutTabPositionLeft = 2;

@implementation iTermLayoutCalculator

#pragma mark - Main Entry Point

+ (iTermLayoutOutputs)calculateLayoutWithInputs:(iTermLayoutInputs)inputs {
    if (!inputs.tabBarVisible) {
        return [self calculateLayoutWithHiddenTabBarInputs:inputs];
    }

    switch (inputs.tabPosition) {
        case kLayoutTabPositionTop:
            return [self calculateLayoutWithVisibleTopTabBarInputs:inputs];
        case kLayoutTabPositionBottom:
            return [self calculateLayoutWithVisibleBottomTabBarInputs:inputs];
        case kLayoutTabPositionLeft:
            return [self calculateLayoutWithVisibleLeftTabBarInputs:inputs];
        default:
            return [self calculateLayoutWithVisibleTopTabBarInputs:inputs];
    }
}

#pragma mark - Hidden Tab Bar Layout

+ (iTermLayoutOutputs)calculateLayoutWithHiddenTabBarInputs:(iTermLayoutInputs)inputs {
    iTermLayoutOutputs outputs = {0};

    // Calculate decoration heights
    outputs.decorationHeightBottom = 0;
    outputs.decorationHeightTop = inputs.notchInset;

    if (inputs.divisionViewVisible) {
        outputs.decorationHeightTop += inputs.divisionViewHeight;
    }

    // Handle transitional state: tab bar on loan but not yet positioned as accessory
    if (inputs.shouldLeaveEmptyAreaAtTop) {
        outputs.decorationHeightTop += inputs.tabBarHeight;
    } else if (inputs.drawWindowTitleInPlaceOfTabBar) {
        // Compact window with hidden tab bar: leave space for fake title bar
        outputs.decorationHeightTop += inputs.tabBarHeight;
    }

    // Calculate tabview width (excluding toolbelt)
    CGFloat tabViewWidth = inputs.contentViewWidth;
    if (inputs.shouldShowToolbelt) {
        tabViewWidth -= inputs.toolbeltWidth;
    }

    // Initial tab view frame
    CGRect tabViewFrame = CGRectMake(
        0,
        outputs.decorationHeightBottom,
        tabViewWidth,
        inputs.contentViewHeight - outputs.decorationHeightTop - outputs.decorationHeightBottom
    );

    // Apply fullscreen tab bar shrinking if needed
    tabViewFrame = [self tabViewFrameByShrinkingForFullScreenTabBar:tabViewFrame
                                                         withInputs:inputs];

    // Layout status bar and adjust decoration heights
    [self layoutStatusBarWithInputs:inputs
                   decorationTop:&outputs.decorationHeightTop
                decorationBottom:&outputs.decorationHeightBottom
                  statusBarFrame:&outputs.statusBarFrame
                   tabViewFrame:tabViewFrame];

    // Recalculate tab view frame with status bar adjustments
    outputs.tabViewFrame = CGRectMake(
        0,
        outputs.decorationHeightBottom,
        tabViewWidth,
        inputs.contentViewHeight - outputs.decorationHeightTop - outputs.decorationHeightBottom
    );

    // Apply fullscreen tab bar shrinking again after status bar adjustment
    outputs.tabViewFrame = [self tabViewFrameByShrinkingForFullScreenTabBar:outputs.tabViewFrame
                                                                 withInputs:inputs];

    // Tab bar frame is zero when hidden
    outputs.tabBarFrame = CGRectZero;

    // Calculate toolbelt frame
    outputs.toolbeltFrame = [self toolbeltFrameWithInputs:inputs];

    return outputs;
}

#pragma mark - Visible Top Tab Bar Layout

+ (iTermLayoutOutputs)calculateLayoutWithVisibleTopTabBarInputs:(iTermLayoutInputs)inputs {
    iTermLayoutOutputs outputs = {0};

    outputs.decorationHeightBottom = 0;
    outputs.decorationHeightTop = inputs.notchInset;

    // Add tab bar height if not on loan and not flashing
    if (!inputs.tabBarOnLoan && !inputs.tabBarFlashing) {
        outputs.decorationHeightTop += inputs.tabBarHeight;
    }

    if (inputs.divisionViewVisible) {
        outputs.decorationHeightTop += inputs.divisionViewHeight;
    }

    // Calculate tabview width
    CGFloat tabViewWidth = inputs.contentViewWidth;
    if (inputs.shouldShowToolbelt) {
        tabViewWidth -= inputs.toolbeltWidth;
    }

    CGRect frame = CGRectMake(
        0,
        outputs.decorationHeightBottom,
        tabViewWidth,
        inputs.contentViewHeight - outputs.decorationHeightBottom - outputs.decorationHeightTop
    );

    // Layout status bar
    CGFloat tempTop = outputs.decorationHeightTop;
    CGFloat tempBottom = outputs.decorationHeightBottom;
    [self layoutStatusBarWithInputs:inputs
                   decorationTop:&tempTop
                decorationBottom:&tempBottom
                  statusBarFrame:&outputs.statusBarFrame
                   tabViewFrame:frame];

    // Calculate final tab view frame
    outputs.tabViewFrame = CGRectMake(
        0,
        tempBottom,
        tabViewWidth,
        inputs.contentViewHeight - tempBottom - tempTop
    );

    outputs.tabViewFrame = [self tabViewFrameByShrinkingForFullScreenTabBar:outputs.tabViewFrame
                                                                 withInputs:inputs];

    outputs.decorationHeightTop = tempTop;
    outputs.decorationHeightBottom = tempBottom;

    // Tab bar frame at top
    CGFloat tabBarOffset = 0;
    if (!inputs.tabBarOnLoan && inputs.tabBarFlashing) {
        tabBarOffset = inputs.tabBarHeight;
    }
    outputs.tabBarFrame = CGRectMake(
        CGRectGetMinX(outputs.tabViewFrame),
        CGRectGetMaxY(frame) - tabBarOffset,
        CGRectGetWidth(outputs.tabViewFrame),
        inputs.tabBarHeight
    );

    outputs.toolbeltFrame = [self toolbeltFrameWithInputs:inputs];

    return outputs;
}

#pragma mark - Visible Bottom Tab Bar Layout

+ (iTermLayoutOutputs)calculateLayoutWithVisibleBottomTabBarInputs:(iTermLayoutInputs)inputs {
    iTermLayoutOutputs outputs = {0};

    // Tab bar at bottom
    outputs.tabBarFrame = CGRectMake(
        0,
        0,
        inputs.contentViewWidth - (inputs.shouldShowToolbelt ? inputs.toolbeltWidth : 0),
        inputs.tabBarHeight
    );

    outputs.decorationHeightTop = inputs.notchInset;
    outputs.decorationHeightBottom = 0;

    if (inputs.divisionViewVisible) {
        outputs.decorationHeightTop += inputs.divisionViewHeight;
    }

    if (!inputs.tabBarFlashing) {
        outputs.decorationHeightBottom += inputs.tabBarHeight;
    }

    CGRect frame = CGRectMake(
        CGRectGetMinX(outputs.tabBarFrame),
        outputs.decorationHeightBottom,
        CGRectGetWidth(outputs.tabBarFrame),
        inputs.contentViewHeight - outputs.decorationHeightTop - outputs.decorationHeightBottom
    );

    // Layout status bar
    [self layoutStatusBarWithInputs:inputs
                   decorationTop:&outputs.decorationHeightTop
                decorationBottom:&outputs.decorationHeightBottom
                  statusBarFrame:&outputs.statusBarFrame
                   tabViewFrame:frame];

    outputs.tabViewFrame = CGRectMake(
        CGRectGetMinX(outputs.tabBarFrame),
        outputs.decorationHeightBottom,
        CGRectGetWidth(outputs.tabBarFrame),
        inputs.contentViewHeight - outputs.decorationHeightTop - outputs.decorationHeightBottom
    );

    outputs.tabViewFrame = [self tabViewFrameByShrinkingForFullScreenTabBar:outputs.tabViewFrame
                                                                 withInputs:inputs];

    outputs.toolbeltFrame = [self toolbeltFrameWithInputs:inputs];

    return outputs;
}

#pragma mark - Visible Left Tab Bar Layout

+ (iTermLayoutOutputs)calculateLayoutWithVisibleLeftTabBarInputs:(iTermLayoutInputs)inputs {
    iTermLayoutOutputs outputs = {0};

    outputs.decorationHeightTop = inputs.notchInset;
    outputs.decorationHeightBottom = 0;

    if (inputs.divisionViewVisible) {
        outputs.decorationHeightTop += inputs.divisionViewHeight;
    }

    // Tab bar on left side
    outputs.tabBarFrame = CGRectMake(
        0,
        outputs.decorationHeightBottom,
        inputs.leftTabBarWidth,
        inputs.contentViewHeight - outputs.decorationHeightBottom - outputs.decorationHeightTop
    );

    CGFloat widthAdjustment = 0;
    CGFloat xOffset = 0;
    if (inputs.tabBarFlashing) {
        xOffset = -CGRectGetMaxX(outputs.tabBarFrame);
        widthAdjustment -= CGRectGetWidth(outputs.tabBarFrame);
    }
    if (inputs.shouldShowToolbelt) {
        widthAdjustment += inputs.toolbeltWidth;
    }

    CGRect frame = CGRectMake(
        CGRectGetMaxX(outputs.tabBarFrame) + xOffset,
        outputs.decorationHeightBottom,
        inputs.contentViewWidth - CGRectGetWidth(outputs.tabBarFrame) - widthAdjustment,
        inputs.contentViewHeight - outputs.decorationHeightBottom - outputs.decorationHeightTop
    );

    // Layout status bar
    [self layoutStatusBarWithInputs:inputs
                   decorationTop:&outputs.decorationHeightTop
                decorationBottom:&outputs.decorationHeightBottom
                  statusBarFrame:&outputs.statusBarFrame
                   tabViewFrame:frame];

    outputs.tabViewFrame = CGRectMake(
        CGRectGetMaxX(outputs.tabBarFrame) + xOffset,
        outputs.decorationHeightBottom,
        inputs.contentViewWidth - CGRectGetWidth(outputs.tabBarFrame) - widthAdjustment,
        inputs.contentViewHeight - outputs.decorationHeightBottom - outputs.decorationHeightTop
    );

    outputs.tabViewFrame = [self tabViewFrameByShrinkingForFullScreenTabBar:outputs.tabViewFrame
                                                                 withInputs:inputs];

    outputs.toolbeltFrame = [self toolbeltFrameWithInputs:inputs];

    return outputs;
}

#pragma mark - Tab View Frame Shrinking

+ (CGRect)tabViewFrameByShrinkingForFullScreenTabBar:(CGRect)frame
                                          withInputs:(iTermLayoutInputs)inputs {
    // Check if tab bar accessory overlaps content
    if (!inputs.tabBarAccessoryOverlapsContent) {
        return frame;
    }

    // Tab bar must be visible (even when on loan) for shrinking to apply.
    // This handles the case when tab bar shouldn't be visible (e.g., single tab
    // with hide-single-tab enabled) but is still on loan during a transition.
    if (!inputs.tabBarShouldBeAccessory) {
        return frame;
    }

    // Must be in fullscreen or entering fullscreen
    if (!inputs.enteringFullscreen && !inputs.inFullscreen) {
        return frame;
    }

    // Only applies to top tab bar
    if (inputs.tabPosition != kLayoutTabPositionTop) {
        return frame;
    }

    // Flashing tab bar overlaps content
    if (inputs.tabBarFlashing) {
        return frame;
    }

    // If tab bar is not on loan and not flashing, it was already accounted for
    if (!inputs.tabBarOnLoan && !inputs.tabBarFlashing) {
        return frame;
    }

    // IMPORTANT: If shouldLeaveEmptyAreaAtTop is true, the shrinking was already
    // applied via decorationHeightTop in the layout calculation. Don't double-apply.
    // This ensures the two mechanisms are mutually exclusive.
    if (inputs.shouldLeaveEmptyAreaAtTop) {
        return frame;
    }

    CGRect tabViewFrame = frame;
    tabViewFrame.size.height -= inputs.tabBarHeight;
    return tabViewFrame;
}

#pragma mark - Toolbelt Frame

+ (CGRect)toolbeltFrameWithInputs:(iTermLayoutInputs)inputs {
    if (!inputs.shouldShowToolbelt) {
        return CGRectZero;
    }

    CGFloat top = inputs.notchInset;
    CGFloat bottom = 0;

    CGRect toolbeltFrame = CGRectMake(
        inputs.contentViewWidth - inputs.toolbeltWidth,
        bottom,
        inputs.toolbeltWidth,
        inputs.contentViewHeight - top - bottom
    );

    // Shrink the toolbelt to account for the tab bar.
    // Use shouldLeaveEmptyAreaAtTop OR frame shrinking, but not both.
    // These mechanisms are mutually exclusive.
    if (inputs.shouldLeaveEmptyAreaAtTop) {
        toolbeltFrame.size.height -= inputs.tabBarHeight;
    } else {
        toolbeltFrame = [self tabViewFrameByShrinkingForFullScreenTabBar:toolbeltFrame
                                                              withInputs:inputs];
    }

    return toolbeltFrame;
}

#pragma mark - Status Bar Layout

+ (void)layoutStatusBarWithInputs:(iTermLayoutInputs)inputs
                   decorationTop:(CGFloat *)decorationTop
                decorationBottom:(CGFloat *)decorationBottom
                  statusBarFrame:(CGRect *)statusBarFrame
                   tabViewFrame:(CGRect)containingFrame {
    if (!inputs.hasStatusBar) {
        *statusBarFrame = CGRectZero;
        return;
    }

    if (inputs.statusBarOnTop) {
        *statusBarFrame = CGRectMake(
            CGRectGetMinX(containingFrame),
            CGRectGetMaxY(containingFrame) - inputs.statusBarHeight,
            CGRectGetWidth(containingFrame),
            inputs.statusBarHeight
        );
        *decorationTop += inputs.statusBarHeight;
    } else {
        *statusBarFrame = CGRectMake(
            CGRectGetMinX(containingFrame),
            CGRectGetMinY(containingFrame),
            CGRectGetWidth(containingFrame),
            inputs.statusBarHeight
        );
        *decorationBottom += inputs.statusBarHeight;
    }
}

@end
