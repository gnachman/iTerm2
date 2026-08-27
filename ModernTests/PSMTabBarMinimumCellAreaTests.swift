//
//  PSMTabBarMinimumCellAreaTests.swift
//  iTerm2XCTests
//
//  -maximumLeftInsetFittingAllCellsMinimallyForWidth: answers "how much of the
//  bar can something else take before a tab stops fitting". It mirrors the
//  branch structure of -cellWidthsForHorizontalArrangementWithOverflow: rather
//  than calling it, which is the one real cost of routing the window name's
//  reservation through the tab bar: two expressions that must agree.
//
//  These tests pin them together: at the predicted inset every cell is still
//  laid out at its promised minimum width, and a point past it the tabs are
//  squeezed under that minimum. They assert the two rules against each other
//  rather than against fixed point values, so they stay true if the metrics
//  change and fail only if the two rules diverge.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabBarMinimumCellAreaTests: XCTestCase {
    private let barWidth: CGFloat = 900
    private var control: PSMTabBarControl!

    override func setUp() {
        super.setUp()
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: barWidth, height: 24))
        // -initWithFrame: assigns _style directly rather than through -setStyle:,
        // which is the only thing that wires the style's back-reference. Without
        // this the style reads `tabBar?.insets.left ?? 0`, the bar's insets never
        // reach the width calculation at all, and every assertion below passes
        // vacuously against a bar that thinks it has the whole 900pt.
        control.style.tabBar = control
        control.cellMinWidth = 60
        // Uneven and optimum sizing are deliberately unrepresented in the
        // minimum, because neither can overflow a bar that fits minimally.
        // Turning them off exercises the expression under test directly.
        control.sizeCellsToFit = false
        control.stretchCellsToFit = false
    }

    override func tearDown() {
        control = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func addTabCells(_ count: Int, pinned: Int = 0) {
        for i in 0..<count {
            let cell = PSMTabBarCell(controlView: control)!
            cell.isPinned = (i < pinned)
            control.cells().add(cell)
        }
    }

    private func addChip(_ groupID: String) {
        let cell = PSMTabBarCell(controlView: control)!
        cell.isTabGroupChip = true
        cell.tabGroupIdentifier = groupID
        control.cells().add(cell)
    }

    private func addGroupedTabCell(_ groupID: String, collapsedHidden: Bool) {
        let cell = PSMTabBarCell(controlView: control)!
        cell.tabGroupIdentifier = groupID
        cell.isCollapsedHidden = collapsedHidden
        control.cells().add(cell)
    }

    private func laidOutWidths(leftInset: CGFloat) -> [CGFloat] {
        control.insets = NSEdgeInsets(top: 0, left: leftInset, bottom: 0, right: 0)
        return (control.cellWidths(forHorizontalArrangementWithOverflow: false) ?? []).map { CGFloat($0.doubleValue) }
    }

    /// The safe direction, and the one the window name's reservation depends on:
    /// at the predicted inset every cell is still laid out, at no less than the
    /// minimum width the bar promises it.
    ///
    /// Note this is a bound on *squeezing*, not on dropping. Past the limit the
    /// bar does not drop a cell -- -computeCellFramesInContainerOfWidth: divides
    /// whatever is left evenly among the cells it has, so they shrink below
    /// cellMinWidth first and are only dropped much later. cellMinWidth is a soft
    /// floor on that path, so "every cell fits" is the wrong thing to assert
    /// against; "every cell fits at its promised width" is the real contract.
    private func assertEveryCellFitsAtItsMinimum(_ what: String,
                                                 file: StaticString = #filePath,
                                                 line: UInt = #line) {
        let expected = control.cells().count
        let maxInset = control.maximumLeftInsetFittingAllCellsMinimally(forWidth: barWidth)
        XCTAssertGreaterThan(maxInset, 0,
                             "\(what): expected some room to give away",
                             file: file, line: line)

        let widths = laidOutWidths(leftInset: floor(maxInset))
        XCTAssertEqual(widths.count, expected,
                       "\(what): a cell was dropped at the inset we predicted would fit",
                       file: file, line: line)
        // Pinned cells and group chips are laid out at their own fixed widths,
        // so only the ordinary tab cells are held to cellMinWidth.
        let plainWidths = zip(widths, control.cells() as! [PSMTabBarCell])
            .filter { !$0.1.isPinned && !$0.1.isTabGroupChip && !$0.1.isCollapsedHidden }
            .map { $0.0 }
        for width in plainWidths {
            XCTAssertGreaterThanOrEqual(width, CGFloat(control.cellMinWidth) - 0.5,
                                        "\(what): a tab was squeezed under cellMinWidth at the inset we predicted would fit",
                                        file: file, line: line)
        }
    }

    // MARK: - Plain cells

    func testPlainCellsSingle() {
        addTabCells(1)
        assertEveryCellFitsAtItsMinimum("one tab")
    }

    func testPlainCellsSeveral() {
        addTabCells(6)
        assertEveryCellFitsAtItsMinimum("six tabs")
    }

    // The other side of the bound: the prediction should not be leaving usable
    // space on the table. One point past it, the tabs no longer get their
    // minimum. Asserted only for plain cells, where every cell is held to
    // cellMinWidth -- pinned cells and chips have fixed widths of their own and
    // absorb the squeeze differently.
    func testPlainCellsAreSqueezedJustPastTheLimit() {
        addTabCells(6)
        let maxInset = control.maximumLeftInsetFittingAllCellsMinimally(forWidth: barWidth)
        let widths = laidOutWidths(leftInset: ceil(maxInset) + 1)
        let narrowest = widths.min() ?? 0
        XCTAssertLessThan(narrowest, CGFloat(control.cellMinWidth),
                          "every tab still got its minimum past the predicted limit, so the prediction is too conservative")
    }

    // Intercell spacing is charged per gap, not per cell; a prediction that got
    // that wrong would be off by one gap and drift further with every tab.
    func testPlainCellsSpacingScalesWithCount() {
        addTabCells(2)
        let twoTabs = control.maximumLeftInsetFittingAllCellsMinimally(forWidth: barWidth)
        addTabCells(1)
        let threeTabs = control.maximumLeftInsetFittingAllCellsMinimally(forWidth: barWidth)

        let perTabCost = twoTabs - threeTabs
        let expected = CGFloat(control.cellMinWidth) + control.style.intercellSpacing
        XCTAssertEqual(perTabCost, expected, accuracy: 0.01,
                       "each additional tab should cost one cell plus one gap")
    }

    // MARK: - Pinned cells

    func testPinnedAndUnpinnedMix() {
        addTabCells(5, pinned: 2)
        assertEveryCellFitsAtItsMinimum("two pinned, three unpinned")
    }

    func testAllPinned() {
        addTabCells(3, pinned: 3)
        assertEveryCellFitsAtItsMinimum("three pinned")
    }

    // MARK: - Group chips

    func testChipWithExpandedMembers() {
        addChip("group")
        addGroupedTabCell("group", collapsedHidden: false)
        addGroupedTabCell("group", collapsedHidden: false)
        addTabCells(2)
        assertEveryCellFitsAtItsMinimum("chip with two visible members")
    }

    // The case a raw tab count gets wrong: collapsed members occupy no width and
    // no spacing, so counting them overstates what the tabs need and the name
    // gives up space it could have had.
    func testCollapsedMembersDoNotInflateTheMinimum() {
        addChip("group")
        addGroupedTabCell("group", collapsedHidden: true)
        addGroupedTabCell("group", collapsedHidden: true)
        addTabCells(2)
        let withCollapsed = control.maximumLeftInsetFittingAllCellsMinimally(forWidth: barWidth)

        addGroupedTabCell("group", collapsedHidden: true)
        let withOneMoreCollapsed = control.maximumLeftInsetFittingAllCellsMinimally(forWidth: barWidth)

        XCTAssertEqual(withCollapsed, withOneMoreCollapsed, accuracy: 0.01,
                       "a hidden collapsed member should cost the bar nothing")
    }
}
