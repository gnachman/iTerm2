//
//  PTYTabFloatingPaneModelTests.swift
//  ModernTests
//
//  How a tab holds floating panes: enumeration, removal, active-session hand-off and maximize.
//  These use a real terminal window.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTabFloatingPaneModelTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private let floatFrame = NSRect(x: 40, y: 30, width: 300, height: 200)

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        super.tearDown()
    }

    private var tab: PTYTab {
        guard let tab = fixture.terminal.currentTab() else {
            it_fatalError("No tab")
        }
        return tab
    }

    private var tiled: PTYSession {
        guard let session = tab.tiledSessions()?.first else {
            it_fatalError("No tiled session")
        }
        return session
    }

    // MARK: - Enumeration

    func testSessionsListTiledThenFloating() {
        let tiled = self.tiled
        let second = fixture.split(tiled, vertically: true)
        let back = fixture.addFloat(frame: floatFrame)
        let front = fixture.addFloat(frame: floatFrame.offsetBy(dx: 20, dy: 20))

        XCTAssertEqual(tab.tiledSessions(), [tiled, second])
        XCTAssertEqual(tab.floatingSessions(), [back, front], "floats are back to front")
        XCTAssertEqual(tab.sessions(), [tiled, second, back, front], "tiled first, then floats")
        XCTAssertEqual(tab.sessionViews()?.count, 4)
        XCTAssertTrue(tab.sessionIsFloating(back))
        XCTAssertFalse(tab.sessionIsFloating(tiled))
    }

    func testFloatIsAboveTheRootInTheContainer() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let container = tab.realRootView, let pane = tab.floatingPane(for: float) else {
            XCTFail("Missing views")
            return
        }
        XCTAssertTrue(pane.superview === container)
        XCTAssertTrue(container.subviews.first === tab.rootView, "the root is at the back")
        XCTAssertTrue(container.subviews.last === pane, "the float is at the front")
        XCTAssertEqual(pane.outlineFrame.minX, floatFrame.minX)
        XCTAssertEqual(pane.outlineFrame.maxY, floatFrame.maxY, "the top left is kept; this container is not flipped")
        XCTAssertLessThanOrEqual(pane.outlineFrame.width, floatFrame.width, "snapped down to whole cells")
        XCTAssertLessThanOrEqual(pane.outlineFrame.height, floatFrame.height)
        XCTAssertTrue(float.view?.superview === pane.splitView)
        XCTAssertEqual(pane.splitView.subviews.count, 1)
        XCTAssertEqual(tab.rootView?.frame, container.bounds, "a float does not change the tiled layout")
    }

    func testFindsFloatByViewID() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let viewID = float.view?.viewId else {
            XCTFail("No view")
            return
        }
        XCTAssertTrue(tab.session(withViewId: viewID) === float)
    }

    // MARK: - Removal

    func testRemovingAFloatRemovesItsPaneAndLeavesTheLayoutAlone() {
        let tiled = self.tiled
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        let pane = tab.floatingPane(for: float)
        let rootFrame = tab.rootView?.frame

        tab.remove(float)

        XCTAssertEqual(tab.sessions(), [tiled, second])
        XCTAssertTrue(tab.floatingPanes.isEmpty)
        XCTAssertNil(pane?.superview, "the float's pane leaves the container")
        XCTAssertEqual(tab.rootView?.subviews.count, 2, "the tiled layout is untouched")
        XCTAssertEqual(tab.rootView?.frame, rootFrame)
    }

    func testRemovingATiledSessionLeavesFloatsAlone() {
        let tiled = self.tiled
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        let frame = tab.floatingPane(for: float)?.outlineFrame

        tab.remove(second)

        XCTAssertEqual(tab.tiledSessions(), [tiled])
        XCTAssertEqual(tab.floatingSessions(), [float])
        XCTAssertEqual(tab.floatingPane(for: float)?.outlineFrame, frame)
    }

    func testRemovingTheActiveFloatActivatesTheFrontmostRemainingFloat() {
        let back = fixture.addFloat(frame: floatFrame)
        let middle = fixture.addFloat(frame: floatFrame)
        let front = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(front)

        tab.remove(front)
        XCTAssertTrue(tab.activeSession === middle)

        tab.remove(middle)
        XCTAssertTrue(tab.activeSession === back)
    }

    func testRemovingTheLastActiveFloatActivatesTheMostRecentTiledSession() {
        let tiled = self.tiled
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(tiled)
        tab.setActiveSession(second)
        tab.setActiveSession(tiled)
        tab.setActiveSession(float)

        tab.remove(float)
        XCTAssertTrue(tab.activeSession === tiled, "the tiled session used most recently takes over")
    }

    // MARK: - Maximize

    func testFloatsSurviveMaximizeAndAreStillEnumerated() {
        let tiled = self.tiled
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        guard let container = tab.realRootView, let pane = tab.floatingPane(for: float) else {
            XCTFail("Missing views")
            return
        }
        let frame = pane.outlineFrame
        tab.setActiveSession(second)

        tab.maximize()
        XCTAssertTrue(tab.isMaximized)
        XCTAssertTrue(pane.superview === container, "maximize keeps floats")
        XCTAssertTrue(container.subviews.last === pane, "floats stay above the maximized pane")
        XCTAssertEqual(Set(tab.tiledSessions() ?? []), Set([tiled, second]))
        XCTAssertEqual(tab.floatingSessions(), [float])
        XCTAssertTrue(tab.sessions()?.last === float, "floats come after tiled sessions while maximized too")

        tab.perform(NSSelectorFromString("unmaximize"))
        XCTAssertFalse(tab.isMaximized)
        XCTAssertTrue(pane.superview === container)
        XCTAssertEqual(tab.sessions(), [tiled, second, float])
        XCTAssertEqual(pane.outlineFrame, frame)
    }

    func testActivatingAFloatWhileMaximizedLeavesItFloating() {
        let tiled = self.tiled
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        guard let pane = tab.floatingPane(for: float) else {
            XCTFail("No pane")
            return
        }
        tab.setActiveSession(second)
        tab.maximize()

        tab.setActiveSessionPreservingMaximization(float)
        XCTAssertTrue(tab.activeSession === float)
        XCTAssertTrue(tab.isMaximized)
        XCTAssertTrue(float.view?.superview === pane.splitView, "the float's view stays in the float")
        XCTAssertTrue(tab.rootView?.subviews.first === second.view, "the maximized pane stays")

        tab.unmaximizeTemporarilyAndActivate { tiled }
        XCTAssertTrue(tab.activeSession === tiled)
        XCTAssertTrue(tab.rootView?.subviews.first === tiled.view)
        XCTAssertTrue(float.view?.superview === pane.splitView)

        tab.unmaximizeTemporarilyAndActivate { float }
        XCTAssertTrue(tab.activeSession === float)
        XCTAssertTrue(tab.rootView?.subviews.first === tiled.view)
        XCTAssertTrue(float.view?.superview === pane.splitView)

        tab.perform(NSSelectorFromString("unmaximize"))
        XCTAssertEqual(tab.sessions(), [tiled, second, float])
    }

    // MARK: - Splits

    func testASplitAimedAtAFloatGoesToTheMostRecentTiledPane() {
        let tiled = self.tiled
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(tiled)
        tab.setActiveSession(float)
        XCTAssertTrue(tab.splitTarget(for: float) === tiled)

        let added = fixture.split(float, vertically: true)
        XCTAssertEqual(tab.floatingSessions(), [float], "a float holds exactly one session")
        XCTAssertEqual(tab.tiledSessions(), [tiled, added], "the split went to the tiled layout")
        XCTAssertEqual(tab.floatingPane(for: float)?.splitView.subviews.count, 1)
    }

    // MARK: - Promotion

    func testRemovingTheLastTiledPanePromotesTheFrontFloat() {
        let tiled = self.tiled
        let back = fixture.addFloat(frame: floatFrame)
        let front = fixture.addFloat(frame: floatFrame.offsetBy(dx: 20, dy: 20))
        tab.setActiveSession(tiled)

        tab.remove(tiled)

        XCTAssertEqual(tab.tiledSessions(), [front], "the front float becomes the tiled pane")
        XCTAssertEqual(tab.floatingSessions(), [back], "other floats stay floating")
        XCTAssertTrue(front.view?.superview === tab.rootView)
        XCTAssertEqual(front.view?.frame.size, tab.rootView?.bounds.size, "the promoted pane fills the tab")
        XCTAssertNil(tab.floatingPane(for: front))
        XCTAssertTrue(tab.activeSession === front)
    }

    func testRemovingATiledPaneThatIsNotTheLastDoesNotPromote() {
        let tiled = self.tiled
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        tab.remove(second)
        XCTAssertEqual(tab.tiledSessions(), [tiled])
        XCTAssertEqual(tab.floatingSessions(), [float])
    }

    func testPromotionGrowsTheGridToFillTheTab() {
        let float = fixture.addFloat(frame: floatFrame)
        let floatColumns = float.columns
        tab.remove(tiled)
        XCTAssertGreaterThan(float.columns, floatColumns)
    }

    // MARK: - Refitting

    func testFittingAFloatKeepsItsGrid() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let pane = tab.floatingPane(for: float) else {
            XCTFail("No pane")
            return
        }
        let columns = float.columns
        let rows = float.rows
        // Something changes the frame behind the float's back; fitting restores it from the grid.
        pane.outlineFrame = pane.outlineFrame.insetBy(dx: 30, dy: 20)
        tab.fitSession(toCurrentViewSize: float)
        XCTAssertEqual(float.columns, columns)
        XCTAssertEqual(float.rows, rows)
        guard let metrics = FloatingPaneLayout.metrics(for: float) else {
            XCTFail("No metrics")
            return
        }
        XCTAssertEqual(pane.outlineFrame.size,
                       metrics.frameSize(for: FloatingPaneGrid(columns: Int(columns), rows: Int(rows))))
    }

    // MARK: - Minimum size

    func testFloatsContributeTheirMinimumSizeNotTheirCurrentSize() {
        let float = fixture.addFloat(frame: floatFrame)
        let floatMinimum = FloatingPaneLayout.minimumSize(session: float)
        let minSize = tab.minSize()
        XCTAssertGreaterThanOrEqual(minSize.width, floatMinimum.width)
        XCTAssertGreaterThanOrEqual(minSize.height, floatMinimum.height)
        XCTAssertLessThan(floatMinimum.width, floatFrame.width, "the minimum is the 2x2 grid, not the current one")
    }
}
