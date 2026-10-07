//
//  FloatingPanePersistenceTests.swift
//  ModernTests
//
//  Floats in tab arrangements: what is encoded, and a round trip through tabWithArrangement that
//  revives the existing sessions (the path undo close takes) so no processes are launched.
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPanePersistenceTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
        var frame = fixture.window.frame
        frame.size = NSSize(width: 900, height: 650)
        fixture.window.setFrame(frame, display: true)
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

    private func floatRecords(_ arrangement: [AnyHashable: Any]) -> [[String: Any]] {
        return arrangement["Floating Panes"] as? [[String: Any]] ?? []
    }

    private func sessionGUID(inRecord record: [String: Any]) -> String? {
        guard let node = record["Node"] as? [String: Any],
              let session = node["Session"] as? [AnyHashable: Any] else {
            return nil
        }
        return PTYSession.guid(inArrangement: session)
    }

    // MARK: - Encoding

    func testArrangementRecordsFloatsBackToFront() {
        let back = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        let front = fixture.addFloat(frame: NSRect(x: 200, y: 150, width: 300, height: 200))
        guard let arrangement = tab.arrangement() else {
            XCTFail("No arrangement")
            return
        }
        let records = floatRecords(arrangement)
        XCTAssertEqual(records.map { sessionGUID(inRecord: $0) }, [back.guid, front.guid])
        XCTAssertNotNil(records.first?["Frame"])
        XCTAssertNotNil(records.first?["Container Size"])
        XCTAssertNil(records.first?["Saved Frame"], "only a maximized float has one")
        XCTAssertEqual(arrangement["Floating Panes Hidden"] as? Bool, false)

        // The tiled tree is unchanged: one session.
        guard let root = arrangement["Root"] as? [String: Any],
              let subviews = root["Subviews"] as? [[String: Any]] else {
            XCTFail("No root")
            return
        }
        XCTAssertEqual(subviews.count, 1)
    }

    func testArrangementWithoutFloatsHasNoFloatKeys() {
        guard let arrangement = tab.arrangement() else {
            XCTFail("No arrangement")
            return
        }
        XCTAssertNil(arrangement["Floating Panes"], "older builds see exactly what they saw before")
        XCTAssertNil(arrangement["Floating Panes Hidden"])
    }

    func testFloatsAreRecordedWhileTheTabIsMaximized() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        tab.setActiveSession(second)
        tab.maximize()
        let records = floatRecords(tab.arrangement() ?? [:])
        XCTAssertEqual(records.map { sessionGUID(inRecord: $0) }, [float.guid])
        tab.perform(NSSelectorFromString("unmaximize"))
    }

    // MARK: - Round trip

    /// Builds a new tab from this tab's arrangement and puts it in the window. With `revive`, the
    /// tab's own sessions are matched up as undo close does; without, new sessions are made from the
    /// arrangement as Duplicate Tab and restoring an arrangement do.
    private func roundTrip(revive: Bool = true) -> PTYTab {
        guard let arrangement = tab.arrangement(), let sessions = tab.sessions() else {
            it_fatalError("No arrangement")
        }
        let sessionMap: [String: PTYSession]?
        if revive {
            guard let map = PTYTab.sessionMap(withArrangement: arrangement, sessions: sessions) else {
                it_fatalError("No session map")
            }
            sessionMap = map
        } else {
            sessionMap = nil
        }
        guard let restored = PTYTab(arrangement: arrangement,
                                    named: nil,
                                    inTerminal: fixture.terminal,
                                    hasFlexibleView: false,
                                    viewMap: nil,
                                    sessionMap: sessionMap,
                                    tmuxController: nil,
                                    partialAttachments: nil,
                                    reservedTabGUIDs: Set(),
                                    options: nil) else {
            it_fatalError("No restored tab")
        }
        fixture.terminal.insert(restored, at: Int32(fixture.terminal.numberOfTabs()))
        fixture.terminal.tabView()?.selectTabViewItem(restored.tabViewItem)
        return restored
    }

    func testRoundTripRestoresFloatsWithTheirPlacementAndOrder() {
        let back = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        let front = fixture.addFloat(frame: NSRect(x: 200, y: 150, width: 320, height: 220))
        guard let backPane = tab.floatingPane(for: back), let frontPane = tab.floatingPane(for: front) else {
            XCTFail("No panes")
            return
        }
        let backFrame = backPane.outlineFrame
        let frontFrame = frontPane.outlineFrame
        let backGrid = (back.columns, back.rows)
        tab.setActiveSession(back)

        let restored = roundTrip()

        XCTAssertEqual(restored.floatingSessions(), [back, front], "same sessions, same z-order")
        XCTAssertEqual(restored.tiledSessions()?.count, 1)
        XCTAssertEqual(restored.floatingPane(for: back)?.outlineFrame, backFrame)
        XCTAssertEqual(restored.floatingPane(for: front)?.outlineFrame, frontFrame)
        XCTAssertEqual(back.columns, backGrid.0)
        XCTAssertEqual(back.rows, backGrid.1)
        XCTAssertTrue(restored.activeSession === back, "the active float is restored as active")
        XCTAssertTrue(back.view?.showTitle() ?? false)
    }

    /// Undo close matches the closed tab's sessions to its arrangement. Floats must be matched too,
    /// or they come back as new sessions and the old ones keep running.
    func testTheSessionMapIncludesFloats() {
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        guard let arrangement = tab.arrangement(), let sessions = tab.sessions() else {
            XCTFail("No arrangement")
            return
        }
        let map = PTYTab.sessionMap(withArrangement: arrangement, sessions: sessions)
        XCTAssertTrue(map?[float.guid] === float)
        XCTAssertEqual(map?.count, 2)
    }

    /// Duplicate Tab and restoring an arrangement make new sessions, which must get the float's
    /// saved grid, not one more row.
    func testNewSessionsFromAnArrangementKeepTheFloatsGrid() {
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        guard let pane = tab.floatingPane(for: float), let metrics = FloatingPaneLayout.metrics(for: float) else {
            XCTFail("No pane")
            return
        }
        let grid = FloatingPaneGrid(columns: 30, rows: 8)
        FloatingPaneLayout.apply(FloatingPanePlacement(frame: CGRect(origin: CGPoint(x: 40, y: 40),
                                                                     size: metrics.frameSize(for: grid)),
                                                       grid: grid),
                                 to: pane,
                                 session: float)
        let frame = pane.outlineFrame

        let restored = roundTrip(revive: false)
        guard let copy = restored.floatingSessions()?.first, let copyPane = restored.floatingPane(for: copy) else {
            XCTFail("No restored float")
            return
        }
        XCTAssertFalse(copy === float)
        XCTAssertEqual(copy.columns, 30)
        XCTAssertEqual(copy.rows, 8)
        XCTAssertEqual(copyPane.outlineFrame, frame)
    }

    func testRoundTripRestoresHiddenState() {
        fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        tab.setActiveSession(tiled)
        tab.floatingPanesHidden = true
        let restored = roundTrip()
        XCTAssertTrue(restored.floatingPanesHidden)
        XCTAssertTrue(restored.floatingPanes.allSatisfy { $0.isHidden })
    }

    func testRoundTripRestoresAMaximizedFloat() {
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        guard let pane = tab.floatingPane(for: float) else {
            XCTFail("No pane")
            return
        }
        let frame = pane.outlineFrame
        tab.setActiveSession(float)
        fixture.terminal.toggleMaximizeActivePane()

        let restored = roundTrip()
        guard let restoredPane = restored.floatingPane(for: float) else {
            XCTFail("No restored pane")
            return
        }
        XCTAssertTrue(restoredPane.isMaximized)
        restored.toggleMaximizeSession(float)
        XCTAssertEqual(restoredPane.outlineFrame, frame, "unmaximizing goes back to the saved frame")
    }

    // MARK: - Walkers

    func testWalkersVisitFloatingPanes() {
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        guard let arrangement = tab.arrangement(), let tiled = tab.tiledSessions()?.first else {
            XCTFail("No arrangement")
            return
        }

        XCTAssertNotNil(PTYTab.arrangementForSession(withGUID: float.guid, inArrangement: arrangement))
        XCTAssertNotNil(PTYTab.arrangementForSession(withGUID: tiled.guid, inArrangement: arrangement))
        XCTAssertNotNil(PTYTab.floatingPaneRecordForSession(withGUID: float.guid, inArrangement: arrangement))
        XCTAssertNil(PTYTab.floatingPaneRecordForSession(withGUID: tiled.guid, inArrangement: arrangement))

        XCTAssertTrue(PTYTab.arrangement(arrangement, passesTest: { candidate in
            candidate.flatMap { PTYSession.guid(inArrangement: $0) } == float.guid
        }), "a test that only the float passes is found")

        let modified = PTYTab.modifiedArrangement(arrangement) { sessionArrangement in
            var copy = sessionArrangement ?? [:]
            copy["Floating Pane Test Mark"] = true
            return copy
        }
        var marks = 0
        _ = PTYTab.arrangement(modified, passesTest: { candidate in
            if candidate?["Floating Pane Test Mark"] as? Bool == true {
                marks += 1
            }
            return false
        })
        XCTAssertEqual(marks, 2, "the tiled session and the float are both modified")
        XCTAssertEqual(floatRecords(modified ?? [:]).count, 1)

        let stripped = PTYTab.arrangementWithoutFloatingPanes(arrangement)
        XCTAssertNil(stripped?["Floating Panes"])
        XCTAssertNotNil(stripped?["Root"])
    }

    // MARK: - Undo close

    func testUndoClosingAFloatPutsItBackAsAFloat() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        let frame = tab.floatingPane(for: float)?.outlineFrame
        guard let arrangement = tab.arrangement() else {
            XCTFail("No arrangement")
            return
        }
        tab.remove(float)
        XCTAssertEqual(tab.sessions(), [tiled])

        fixture.terminal.recreateTab(tab, withArrangement: arrangement, sessions: [float], archives: nil, revive: false)

        XCTAssertEqual(tab.tiledSessions(), [tiled], "the tiled layout is untouched")
        XCTAssertEqual(tab.floatingSessions(), [float], "the float comes back as a float")
        XCTAssertEqual(tab.floatingPane(for: float)?.outlineFrame, frame)
        XCTAssertTrue(tab.activeSession === float)
    }

    func testUndoClosingATiledPaneLeavesLiveFloatsAlone() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        guard let pane = tab.floatingPane(for: float), let arrangement = tab.arrangement() else {
            XCTFail("No arrangement")
            return
        }
        tab.remove(second)

        fixture.terminal.recreateTab(tab, withArrangement: arrangement, sessions: [second], archives: nil, revive: false)

        XCTAssertEqual(tab.tiledSessions(), [tiled, second])
        XCTAssertEqual(tab.floatingSessions(), [float])
        XCTAssertTrue(tab.floatingPane(for: float) === pane, "the live float was not rebuilt")
    }
}
