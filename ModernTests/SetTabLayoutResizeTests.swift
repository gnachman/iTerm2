//
//  SetTabLayoutResizeTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

/// F-343: a real Tab.async_update_layout() change lost a cell per pane and shrank the window.
/// The pane frames were laid out without the dividers between them, so fitting the root to the
/// panes took a point from the last one. And when only the split between panes moved, nothing fit
/// the sessions to their new frames. (SetTabLayoutNoOpTests covers an unchanged layout.)
final class SetTabLayoutResizeTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        fixture = TerminalWindowTestFixture()
        var frame = fixture.window.frame
        frame.size = NSSize(width: 1200, height: 500)
        fixture.window.setFrame(frame, display: true)
    }

    override func tearDown() {
        fixture?.close()
        fixture = nil
        super.tearDown()
    }

    private var tab: PTYTab {
        guard let tab = fixture.terminal.currentTab() else {
            it_fatalError("No tab")
        }
        return tab
    }

    private var firstSession: PTYSession {
        guard let session = tab.tiledSessions()?.first as? PTYSession else {
            it_fatalError("No session")
        }
        return session
    }

    private func sessionLinks(_ node: ITMSplitTreeNode) -> [ITMSplitTreeNode_SplitTreeLink] {
        var result = [ITMSplitTreeNode_SplitTreeLink]()
        for case let link as ITMSplitTreeNode_SplitTreeLink in node.linksArray {
            if link.childOneOfCase == .session {
                result.append(link)
            } else {
                result.append(contentsOf: sessionLinks(link.node))
            }
        }
        return result
    }

    private struct Grid: Equatable, CustomStringConvertible {
        var width: Int32
        var height: Int32
        var description: String { "\(width)x\(height)" }
    }

    private var tree: ITMSplitTreeNode {
        guard let tree = tab.rootSplitTreeNode() else {
            it_fatalError("No split tree")
        }
        return tree
    }

    /// The tab's panes, in the order the API lists them.
    private var grids: [Grid] {
        return sessionLinks(tree).map {
            Grid(width: $0.session.gridSize.width, height: $0.session.gridSize.height)
        }
    }

    /// Asks for `requested` the way apiServerSetTabLayout:handler: does.
    private func apply(_ requested: [Grid]) {
        let tree = self.tree
        let links = sessionLinks(tree)
        XCTAssertEqual(links.count, requested.count)
        for (link, grid) in zip(links, requested) {
            link.session.gridSize.width = grid.width
            link.session.gridSize.height = grid.height
        }
        tab.setSizesFrom(tree)
    }

    func testMovingTheSplitGivesEachPaneTheRequestedColumns() {
        fixture.split(firstSession, vertically: true)
        let before = grids
        let rows = before[0].height
        let total = before[0].width + before[1].width

        let narrowLeft = [Grid(width: total / 2 - 20, height: rows),
                          Grid(width: total - (total / 2 - 20), height: rows)]
        apply(narrowLeft)
        XCTAssertEqual(grids, narrowLeft)
        let windowSize = fixture.window.frame.size

        // The total is the same, so only the split moves and the root keeps its size.
        let wideLeft = [Grid(width: total / 2 + 20, height: rows),
                        Grid(width: total - (total / 2 + 20), height: rows)]
        apply(wideLeft)
        XCTAssertEqual(grids, wideLeft)
        XCTAssertEqual(fixture.window.frame.size, windowSize)

        // Repeating it changes nothing.
        apply(wideLeft)
        XCTAssertEqual(grids, wideLeft)
        XCTAssertEqual(fixture.window.frame.size, windowSize)
    }

    func testNestedSplitsKeepTheRequestedSizes() {
        let right = fixture.split(firstSession, vertically: true)
        fixture.split(right, vertically: false)
        let before = grids
        XCTAssertEqual(before.count, 3)
        let totalWidth = before[0].width + before[1].width
        let leftRows = before[0].height
        let rightRows = before[1].height + before[2].height

        let first = [Grid(width: totalWidth / 2 - 10, height: leftRows),
                     Grid(width: totalWidth - (totalWidth / 2 - 10), height: rightRows / 2 - 3),
                     Grid(width: totalWidth - (totalWidth / 2 - 10), height: rightRows - (rightRows / 2 - 3))]
        apply(first)
        XCTAssertEqual(grids, first)
        let windowSize = fixture.window.frame.size

        let second = [Grid(width: totalWidth / 2 + 10, height: leftRows),
                      Grid(width: totalWidth - (totalWidth / 2 + 10), height: rightRows / 2 + 3),
                      Grid(width: totalWidth - (totalWidth / 2 + 10), height: rightRows - (rightRows / 2 + 3))]
        apply(second)
        XCTAssertEqual(grids, second)
        XCTAssertEqual(fixture.window.frame.size, windowSize)
    }

    func testGrowingAPaneGrowsTheWindowByWholeCells() throws {
        fixture.split(firstSession, vertically: true)
        let before = grids
        apply(before)
        let charWidth = try XCTUnwrap(firstSession.textview?.charWidth)
        let windowSize = fixture.window.frame.size
        let visibleWidth = try XCTUnwrap(fixture.window.screen?.visibleFrame.width)
        try XCTSkipIf(windowSize.width + 10 * charWidth > visibleWidth, "The screen is too narrow")

        let wider = [before[0], Grid(width: before[1].width + 10, height: before[1].height)]
        apply(wider)
        XCTAssertEqual(grids, wider)
        XCTAssertEqual(fixture.window.frame.width,
                       windowSize.width + 10 * charWidth,
                       accuracy: 0.5)
    }
}
