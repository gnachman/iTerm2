//
//  iTermLayoutCalculatorTest.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/26.
//
//  Tests for iTermLayoutCalculator - the pure layout calculation logic
//  extracted from iTermRootTerminalView for testability.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermLayoutCalculatorTest: XCTestCase {

    // MARK: - Test Fixtures

    /// Creates default inputs with reasonable test values
    func makeDefaultInputs() -> iTermLayoutInputs {
        var inputs = iTermLayoutInputs()
        inputs.contentViewWidth = 800
        inputs.contentViewHeight = 600
        inputs.tabBarHeight = 28
        inputs.leftTabBarWidth = 200
        inputs.toolbeltWidth = 200
        inputs.shouldShowToolbelt = false
        inputs.statusBarHeight = 21
        inputs.hasStatusBar = false
        inputs.statusBarOnTop = true
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = false
        inputs.tabBarFlashing = false
        inputs.tabBarShouldBeAccessory = false
        inputs.tabBarAccessoryOverlapsContent = false
        inputs.enteringFullscreen = false
        inputs.inFullscreen = false
        inputs.tabPosition = kLayoutTabPositionTop
        inputs.divisionViewVisible = false
        inputs.divisionViewHeight = 1
        inputs.notchInset = 0
        inputs.shouldLeaveEmptyAreaAtTop = false
        inputs.drawWindowTitleInPlaceOfTabBar = false
        return inputs
    }

    // MARK: - Tab Bar Overlap Tests

    /// Test: Fullscreen + accessory overlaps content -> frame should shrink
    func testFullscreenWithAccessoryOverlapsContent_ShrinkFrame() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = true
        inputs.tabBarShouldBeAccessory = true  // Tab bar should be visible (even when on loan)
        inputs.tabBarAccessoryOverlapsContent = true
        inputs.inFullscreen = true
        inputs.tabPosition = kLayoutTabPositionTop

        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = iTermLayoutCalculator.tabViewFrame(byShrinkingForFullScreenTabBar: frame, with: inputs)

        // Frame should be shrunk by tab bar height
        XCTAssertEqual(result.size.height, frame.size.height - CGFloat(inputs.tabBarHeight))
        XCTAssertEqual(result.size.width, frame.size.width)
        XCTAssertEqual(result.origin.x, frame.origin.x)
        XCTAssertEqual(result.origin.y, frame.origin.y)
    }

    /// Test: Fullscreen + accessory does NOT overlap -> frame unchanged
    func testFullscreenWithAccessoryNoOverlap_FrameUnchanged() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = true
        inputs.tabBarAccessoryOverlapsContent = false  // Key: no overlap
        inputs.inFullscreen = true
        inputs.tabPosition = kLayoutTabPositionTop

        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = iTermLayoutCalculator.tabViewFrame(byShrinkingForFullScreenTabBar: frame, with: inputs)

        // Frame should be unchanged
        XCTAssertEqual(result, frame)
    }

    /// Test: Not fullscreen -> no frame shrinking
    func testNotFullscreen_NoShrinking() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = true
        inputs.tabBarAccessoryOverlapsContent = true
        inputs.inFullscreen = false
        inputs.enteringFullscreen = false
        inputs.tabPosition = kLayoutTabPositionTop

        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = iTermLayoutCalculator.tabViewFrame(byShrinkingForFullScreenTabBar: frame, with: inputs)

        // Frame should be unchanged when not in fullscreen
        XCTAssertEqual(result, frame)
    }

    /// Test: Entering fullscreen -> frame should shrink (if overlap)
    func testEnteringFullscreen_ShrinkFrame() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = true
        inputs.tabBarShouldBeAccessory = true  // Tab bar should be visible (even when on loan)
        inputs.tabBarAccessoryOverlapsContent = true
        inputs.inFullscreen = false
        inputs.enteringFullscreen = true  // Entering fullscreen
        inputs.tabPosition = kLayoutTabPositionTop

        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = iTermLayoutCalculator.tabViewFrame(byShrinkingForFullScreenTabBar: frame, with: inputs)

        // Frame should be shrunk even when entering fullscreen
        XCTAssertEqual(result.size.height, frame.size.height - CGFloat(inputs.tabBarHeight))
    }

    /// Test: Bottom tab bar position -> no shrinking (only top shrinks)
    func testBottomTabBar_NoShrinking() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = true
        inputs.tabBarAccessoryOverlapsContent = true
        inputs.inFullscreen = true
        inputs.tabPosition = kLayoutTabPositionBottom

        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = iTermLayoutCalculator.tabViewFrame(byShrinkingForFullScreenTabBar: frame, with: inputs)

        // Bottom tab bar never shrinks via this method
        XCTAssertEqual(result, frame)
    }

    /// Test: Left tab bar position -> no shrinking
    func testLeftTabBar_NoShrinking() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = true
        inputs.tabBarAccessoryOverlapsContent = true
        inputs.inFullscreen = true
        inputs.tabPosition = kLayoutTabPositionLeft

        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = iTermLayoutCalculator.tabViewFrame(byShrinkingForFullScreenTabBar: frame, with: inputs)

        // Left tab bar never shrinks via this method
        XCTAssertEqual(result, frame)
    }

    /// Test: Flashing tab bar overlaps content -> no shrinking
    func testFlashingTabBar_NoShrinking() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = true
        inputs.tabBarFlashing = true  // Flashing
        inputs.tabBarAccessoryOverlapsContent = true
        inputs.inFullscreen = true
        inputs.tabPosition = kLayoutTabPositionTop

        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = iTermLayoutCalculator.tabViewFrame(byShrinkingForFullScreenTabBar: frame, with: inputs)

        // Flashing tab bar overlaps content, so no shrinking
        XCTAssertEqual(result, frame)
    }

    /// Test: Tab bar not on loan and not flashing -> already accounted for
    func testTabBarNotOnLoanNotFlashing_AlreadyAccounted() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = false  // Not on loan
        inputs.tabBarFlashing = false
        inputs.tabBarAccessoryOverlapsContent = true
        inputs.inFullscreen = true
        inputs.tabPosition = kLayoutTabPositionTop

        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let result = iTermLayoutCalculator.tabViewFrame(byShrinkingForFullScreenTabBar: frame, with: inputs)

        // Already accounted for when computing decoration heights
        XCTAssertEqual(result, frame)
    }

    // MARK: - Hidden Tab Bar Layout Tests

    /// Test: Hidden tab bar with empty area at top (transitional state)
    func testHiddenTabBarWithEmptyAreaAtTop() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = false
        inputs.tabBarOnLoan = true
        inputs.shouldLeaveEmptyAreaAtTop = true
        inputs.tabBarHeight = 28
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(withHiddenTabBarInputs: inputs)

        // Decoration height at top should include tab bar height
        XCTAssertEqual(outputs.decorationHeightTop, CGFloat(inputs.tabBarHeight))

        // Tab view frame should not extend into the reserved area
        XCTAssertEqual(outputs.tabViewFrame.size.height,
                       CGFloat(inputs.contentViewHeight) - CGFloat(inputs.tabBarHeight))
    }

    /// Test: Hidden tab bar without empty area (normal hidden state)
    func testHiddenTabBarNormalState() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = false
        inputs.tabBarOnLoan = false
        inputs.shouldLeaveEmptyAreaAtTop = false
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(withHiddenTabBarInputs: inputs)

        // No decoration at top (no tab bar, no notch)
        XCTAssertEqual(outputs.decorationHeightTop, 0)

        // Tab view should use full height
        XCTAssertEqual(outputs.tabViewFrame.size.height, CGFloat(inputs.contentViewHeight))
    }

    // MARK: - Visible Top Tab Bar Layout Tests

    /// Test: Visible top tab bar includes height in decoration
    func testVisibleTopTabBarDecoration() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = false
        inputs.tabBarFlashing = false
        inputs.tabPosition = kLayoutTabPositionTop
        inputs.tabBarHeight = 28
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(withVisibleTopTabBarInputs: inputs)

        // Decoration should include tab bar height
        XCTAssertEqual(outputs.decorationHeightTop, CGFloat(inputs.tabBarHeight))

        // Tab view frame height should exclude decoration
        XCTAssertEqual(outputs.tabViewFrame.size.height,
                       CGFloat(inputs.contentViewHeight) - CGFloat(inputs.tabBarHeight))
    }

    /// Test: Tab bar flashing doesn't add to decoration
    func testFlashingTabBarNoDecoration() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = false
        inputs.tabBarFlashing = true  // Flashing
        inputs.tabPosition = kLayoutTabPositionTop
        inputs.tabBarHeight = 28
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(withVisibleTopTabBarInputs: inputs)

        // Flashing tab bar doesn't add to decoration (overlaps content)
        XCTAssertEqual(outputs.decorationHeightTop, 0)
    }

    // MARK: - Status Bar Tests

    /// Test: Top status bar positioning
    func testTopStatusBarPositioning() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = false
        inputs.hasStatusBar = true
        inputs.statusBarOnTop = true
        inputs.statusBarHeight = 21
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(withHiddenTabBarInputs: inputs)

        // Decoration should include status bar height
        XCTAssertEqual(outputs.decorationHeightTop, CGFloat(inputs.statusBarHeight))

        // Status bar frame should be at top of content area
        XCTAssertEqual(outputs.statusBarFrame.size.height, CGFloat(inputs.statusBarHeight))
    }

    /// Test: Bottom status bar positioning
    func testBottomStatusBarPositioning() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = false
        inputs.hasStatusBar = true
        inputs.statusBarOnTop = false
        inputs.statusBarHeight = 21
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(withHiddenTabBarInputs: inputs)

        // Bottom decoration should include status bar height
        XCTAssertEqual(outputs.decorationHeightBottom, CGFloat(inputs.statusBarHeight))

        // Status bar frame should be at bottom
        XCTAssertEqual(outputs.statusBarFrame.origin.y, 0)
        XCTAssertEqual(outputs.statusBarFrame.size.height, CGFloat(inputs.statusBarHeight))
    }

    // MARK: - Toolbelt Tests

    /// Test: Toolbelt frame calculation
    func testToolbeltFrameCalculation() {
        var inputs = makeDefaultInputs()
        inputs.shouldShowToolbelt = true
        inputs.toolbeltWidth = 200
        inputs.contentViewWidth = 800
        inputs.contentViewHeight = 600

        let frame = iTermLayoutCalculator.toolbeltFrame(with: inputs)

        // Toolbelt should be on right side
        XCTAssertEqual(frame.origin.x, CGFloat(inputs.contentViewWidth) - CGFloat(inputs.toolbeltWidth))
        XCTAssertEqual(frame.size.width, CGFloat(inputs.toolbeltWidth))
        XCTAssertEqual(frame.size.height, CGFloat(inputs.contentViewHeight))
    }

    /// Test: Toolbelt with empty area at top
    func testToolbeltWithEmptyAreaAtTop() {
        var inputs = makeDefaultInputs()
        inputs.shouldShowToolbelt = true
        inputs.toolbeltWidth = 200
        inputs.contentViewWidth = 800
        inputs.contentViewHeight = 600
        inputs.shouldLeaveEmptyAreaAtTop = true
        inputs.tabBarHeight = 28

        let frame = iTermLayoutCalculator.toolbeltFrame(with: inputs)

        // Toolbelt height should be reduced by tab bar height
        XCTAssertEqual(frame.size.height,
                       CGFloat(inputs.contentViewHeight) - CGFloat(inputs.tabBarHeight))
    }

    /// Test: Hidden toolbelt returns zero frame
    func testHiddenToolbeltZeroFrame() {
        var inputs = makeDefaultInputs()
        inputs.shouldShowToolbelt = false
        inputs.toolbeltWidth = 200

        let frame = iTermLayoutCalculator.toolbeltFrame(with: inputs)

        XCTAssertEqual(frame, CGRect.zero)
    }

    // MARK: - Edge Case Tests

    /// Test: Division view adds to decoration height
    func testDivisionViewDecoration() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabPosition = kLayoutTabPositionTop
        inputs.divisionViewVisible = true
        inputs.divisionViewHeight = 1

        let outputs = iTermLayoutCalculator.calculateLayout(withVisibleTopTabBarInputs: inputs)

        // Division view should add to top decoration
        XCTAssertGreaterThanOrEqual(outputs.decorationHeightTop,
                                     CGFloat(inputs.tabBarHeight) + CGFloat(inputs.divisionViewHeight))
    }

    /// Test: Notch inset in fullscreen
    func testNotchInset() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = false
        inputs.notchInset = 32  // Notch height
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(withHiddenTabBarInputs: inputs)

        // Notch should add to top decoration
        XCTAssertEqual(outputs.decorationHeightTop, CGFloat(inputs.notchInset))

        // Tab view should not extend into notch area
        XCTAssertEqual(outputs.tabViewFrame.size.height,
                       CGFloat(inputs.contentViewHeight) - CGFloat(inputs.notchInset))
    }

    // MARK: - Full Layout Calculation Tests

    /// Test: Complete layout with all components
    func testCompleteLayoutWithAllComponents() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabPosition = kLayoutTabPositionTop
        inputs.tabBarHeight = 28
        inputs.hasStatusBar = true
        inputs.statusBarOnTop = true
        inputs.statusBarHeight = 21
        inputs.shouldShowToolbelt = true
        inputs.toolbeltWidth = 200
        inputs.divisionViewVisible = true
        inputs.divisionViewHeight = 1
        inputs.contentViewWidth = 800
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(with: inputs)

        // Tab view width should exclude toolbelt
        XCTAssertEqual(outputs.tabViewFrame.size.width,
                       CGFloat(inputs.contentViewWidth) - CGFloat(inputs.toolbeltWidth))

        // Total decorations should make sense
        let totalHeight = outputs.tabViewFrame.size.height +
                          outputs.decorationHeightTop +
                          outputs.decorationHeightBottom
        XCTAssertLessThanOrEqual(totalHeight, CGFloat(inputs.contentViewHeight))
    }

    /// Test: Layout routes to correct method based on tab position
    func testLayoutRoutesCorrectly() {
        // Top tab bar
        var topInputs = makeDefaultInputs()
        topInputs.tabBarVisible = true
        topInputs.tabPosition = kLayoutTabPositionTop
        let topOutputs = iTermLayoutCalculator.calculateLayout(with: topInputs)
        XCTAssertGreaterThan(topOutputs.tabBarFrame.origin.y, topOutputs.tabViewFrame.origin.y)

        // Bottom tab bar
        var bottomInputs = makeDefaultInputs()
        bottomInputs.tabBarVisible = true
        bottomInputs.tabPosition = kLayoutTabPositionBottom
        let bottomOutputs = iTermLayoutCalculator.calculateLayout(with: bottomInputs)
        XCTAssertEqual(bottomOutputs.tabBarFrame.origin.y, 0)

        // Hidden tab bar
        var hiddenInputs = makeDefaultInputs()
        hiddenInputs.tabBarVisible = false
        let hiddenOutputs = iTermLayoutCalculator.calculateLayout(with: hiddenInputs)
        XCTAssertEqual(hiddenOutputs.tabBarFrame, CGRect.zero)
    }

    // MARK: - Unified Mechanism Tests (Phase 4)
    //
    // These tests verify the unified behavior where all tab bar overlap
    // adjustments use frame shrinking, eliminating the dual mechanism of
    // shouldLeaveEmptyAreaAtTop vs tabViewFrameByShrinkingForFullScreenTabBar.

    /// Test: Unified behavior - transitional state uses same approach as fullscreen accessory
    /// When tab bar is on loan and should be accessory, the frame is shrunk consistently
    /// regardless of whether shouldLeaveEmptyAreaAtTop is true.
    func testUnifiedMechanism_TransitionalStateUsesFrameShrinking() {
        // Scenario: Tab bar on loan, should be accessory, accessory overlaps content
        // This is the transitional state during fullscreen entry
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = false  // Tab bar not visible in content area
        inputs.tabBarOnLoan = true
        inputs.tabBarShouldBeAccessory = true
        inputs.tabBarAccessoryOverlapsContent = true
        inputs.inFullscreen = true
        inputs.tabPosition = kLayoutTabPositionTop
        inputs.tabBarHeight = 28
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(with: inputs)

        // The frame should be shrunk by tab bar height
        // The decoration height should NOT include the tab bar - only the frame shrinking
        // happens after decoration calculation
        XCTAssertEqual(outputs.tabViewFrame.size.height,
                       CGFloat(inputs.contentViewHeight) - CGFloat(inputs.tabBarHeight))
    }

    /// Test: When not in fullscreen and tab bar is hidden, no adjustments needed
    func testUnifiedMechanism_NoFullscreenNoAdjustment() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = false
        inputs.tabBarOnLoan = false
        inputs.inFullscreen = false
        inputs.tabPosition = kLayoutTabPositionTop
        inputs.tabBarHeight = 28
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(with: inputs)

        // Full height available when no tab bar and no fullscreen
        XCTAssertEqual(outputs.tabViewFrame.size.height, CGFloat(inputs.contentViewHeight))
        XCTAssertEqual(outputs.decorationHeightTop, 0)
    }

    /// Test: Tab bar visible in fullscreen with accessory overlap - frame shrunk correctly
    func testUnifiedMechanism_VisibleTabBarFullscreenOverlap() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = true
        inputs.tabBarOnLoan = true
        inputs.tabBarShouldBeAccessory = true
        inputs.tabBarAccessoryOverlapsContent = true
        inputs.inFullscreen = true
        inputs.tabPosition = kLayoutTabPositionTop
        inputs.tabBarHeight = 28
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(with: inputs)

        // With visible tab bar on loan as accessory that overlaps,
        // the frame should be shrunk
        XCTAssertEqual(outputs.tabViewFrame.size.height,
                       CGFloat(inputs.contentViewHeight) - CGFloat(inputs.tabBarHeight))
    }

    /// Test: Going from 2 tabs to 1 tab in fullscreen - frame maintained correctly
    /// This simulates closing a tab in fullscreen when hide-tab-bar-when-single-tab is on
    func testUnifiedMechanism_TabCountTransition() {
        // State: Tab bar was visible, now transitioning to hidden
        // Tab bar still on loan but will soon be hidden
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = false  // Will be hidden (going to 1 tab)
        inputs.tabBarOnLoan = true    // Still on loan during transition
        inputs.tabBarShouldBeAccessory = false  // Will no longer be accessory
        inputs.tabBarAccessoryOverlapsContent = true
        inputs.inFullscreen = true
        inputs.tabPosition = kLayoutTabPositionTop
        inputs.tabBarHeight = 28
        inputs.contentViewHeight = 600
        inputs.shouldLeaveEmptyAreaAtTop = true  // Transitional flag

        let outputs = iTermLayoutCalculator.calculateLayout(with: inputs)

        // During transition, frame should still be shrunk to maintain layout stability
        XCTAssertEqual(outputs.tabViewFrame.size.height,
                       CGFloat(inputs.contentViewHeight) - CGFloat(inputs.tabBarHeight))
    }

    // MARK: - Compact Window Title Tests

    /// Test: Compact window with hidden tab bar draws title in place of tab bar
    /// This leaves space at top for the fake title bar even though tab bar is not visible
    func testCompactWindowWithTitleInPlaceOfTabBar() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = false  // Tab bar hidden (single tab)
        inputs.tabBarOnLoan = false   // Not in fullscreen
        inputs.drawWindowTitleInPlaceOfTabBar = true  // Compact window draws fake title
        inputs.tabBarHeight = 28
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(with: inputs)

        // Decoration should include tab bar height for the fake title bar
        XCTAssertEqual(outputs.decorationHeightTop, CGFloat(inputs.tabBarHeight))

        // Tab view should not extend into the title area
        XCTAssertEqual(outputs.tabViewFrame.size.height,
                       CGFloat(inputs.contentViewHeight) - CGFloat(inputs.tabBarHeight))
    }

    /// Test: Non-compact window with hidden tab bar does NOT leave title space
    func testNonCompactWindowHiddenTabBar_NoTitleSpace() {
        var inputs = makeDefaultInputs()
        inputs.tabBarVisible = false
        inputs.tabBarOnLoan = false
        inputs.drawWindowTitleInPlaceOfTabBar = false  // Regular window, no fake title
        inputs.tabBarHeight = 28
        inputs.contentViewHeight = 600

        let outputs = iTermLayoutCalculator.calculateLayout(with: inputs)

        // No decoration at top
        XCTAssertEqual(outputs.decorationHeightTop, 0)

        // Full height available
        XCTAssertEqual(outputs.tabViewFrame.size.height, CGFloat(inputs.contentViewHeight))
    }
}
