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

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        fixture = TerminalWindowTestFixture()
        var frame = fixture.window.frame
        frame.size = NSSize(width: 900, height: 650)
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

    /// Undo close of a tab: the window removes the tab, then adds one made from its arrangement with
    /// its sessions revived. Every float comes back with its frame and grid.
    func testUndoCloseOfATabRestoresEveryFloatsFrame() {
        let back = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        let front = fixture.addFloat(frame: NSRect(x: 300, y: 200, width: 300, height: 200))
        let closing = tab
        let frames = [back, front].map { closing.floatingPane(for: $0)?.outlineFrame }
        let grids = [back, front].map { ($0.columns, $0.rows) }
        guard let arrangement = closing.arrangement(), let sessions = closing.sessions() else {
            XCTFail("No arrangement")
            return
        }
        let uniqueId = closing.uniqueId
        _ = fixture.addTab()
        fixture.terminal.perform(NSSelectorFromString("removeTab:"), with: closing)
        fixture.terminal.addTab(withArrangement: arrangement,
                                uniqueId: uniqueId,
                                sessions: sessions,
                                archives: nil,
                                predecessors: [])
        guard let restored = fixture.terminal.tabs().first(where: { $0.floatingSessions()?.contains(back) ?? false }) else {
            XCTFail("No restored tab")
            return
        }
        fixture.terminal.tabView()?.selectTabViewItem(restored.tabViewItem)
        XCTAssertEqual(restored.floatingSessions(), [back, front])
        XCTAssertEqual([back, front].map { restored.floatingPane(for: $0)?.outlineFrame }, frames)
        XCTAssertEqual(back.columns, grids[0].0)
        XCTAssertEqual(back.rows, grids[0].1)
        XCTAssertEqual(front.columns, grids[1].0)
        XCTAssertEqual(front.rows, grids[1].1)
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

    // MARK: - Undo close from an archive

    // Writes the archive Archive On Closure writes for `session`, which has already left its tab,
    // and returns its path.
    private func writeArchive(of session: PTYSession) throws -> String {
        let archive = try XCTUnwrap(fixture.terminal.arrangement(with: session) as NSDictionary?)
        let path = NSTemporaryDirectory() + UUID().uuidString + ".itermarchive"
        XCTAssertTrue(archive.write(toFile: path, atomically: true))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    // Closes `float` and lets its undo window run out: only its archive is left.
    private func closeAndArchive(_ float: PTYSession, in tab: PTYTab) throws -> iTermUndoCloseArchives {
        tab.remove(float)
        return iTermUndoCloseArchives(pathsBySessionGUID: [float.guid: try writeArchive(of: float)])
    }

    /// QA finding F-004: a float closed with Archive On Closure on, whose undo window ran out, is
    /// restored from its archive as a float in its tab, where it was.
    func testUndoClosingAnArchivedFloatPutsItBackAsAFloat() throws {
        let target = tab
        let tiled = try XCTUnwrap(target.tiledSessions()?.first)
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        let frame = target.floatingPane(for: float)?.outlineFrame
        let arrangement = try XCTUnwrap(target.arrangement())
        let archives = try closeAndArchive(float, in: target)
        let numberOfTabs = fixture.terminal.numberOfTabs()

        fixture.terminal.recreateTab(target, withArrangement: arrangement, sessions: [], archives: archives, revive: true)

        XCTAssertEqual(fixture.terminal.numberOfTabs(), numberOfTabs, "no tab is added for the archive")
        XCTAssertEqual(target.tiledSessions(), [tiled], "the tiled layout is untouched")
        XCTAssertEqual(target.floatingSessions()?.count, 1, "the archive comes back as a float")
        let restored = try XCTUnwrap(target.floatingSessions()?.first)
        XCTAssertTrue(restored.isArchive)
        XCTAssertEqual(target.floatingPane(for: restored)?.outlineFrame, frame)
        XCTAssertTrue(target.activeSession === restored)
    }

    /// Tiled panes added after the float closed are left alone, and the archive is not also given a
    /// tab of its own.
    func testUndoClosingAnArchivedFloatLeavesTiledPanesAddedSinceAlone() throws {
        let target = tab
        let tiled = try XCTUnwrap(target.tiledSessions()?.first)
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        let arrangement = try XCTUnwrap(target.arrangement())
        let archives = try closeAndArchive(float, in: target)
        let added = fixture.split(tiled, vertically: true)
        let numberOfTabs = fixture.terminal.numberOfTabs()

        fixture.terminal.recreateTab(target, withArrangement: arrangement, sessions: [], archives: archives, revive: true)

        XCTAssertEqual(target.tiledSessions(), [tiled, added])
        XCTAssertEqual(target.floatingSessions()?.count, 1, "the archive comes back as a float")
        XCTAssertEqual(fixture.terminal.numberOfTabs(), numberOfTabs, "no tab is added for the archive")
    }

    /// An archived float that can't be put back as a float gets a tab of its own rather than being
    /// lost.
    func testAnArchivedFloatThatCannotBeRestoredAsAFloatGetsItsOwnTab() throws {
        let target = tab
        let tiled = target.tiledSessions()
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        var arrangement = try XCTUnwrap(target.arrangement())
        // A float record whose node is not a session view can't be restored as a float. The record
        // still matches the float's GUID because its session arrangement is kept.
        var records = try XCTUnwrap(arrangement["Floating Panes"] as? [[AnyHashable: Any]])
        var node = try XCTUnwrap(records[0]["Node"] as? [AnyHashable: Any])
        node[TAB_ARRANGEMENT_VIEW_TYPE] = VIEW_TYPE_SPLITTER
        records[0]["Node"] = node
        arrangement["Floating Panes"] = records
        let archives = try closeAndArchive(float, in: target)
        let numberOfTabs = fixture.terminal.numberOfTabs()

        fixture.terminal.recreateTab(target, withArrangement: arrangement, sessions: [], archives: archives, revive: true)

        XCTAssertEqual(target.floatingSessions()?.count, 0)
        XCTAssertEqual(target.tiledSessions(), tiled, "the tiled layout is untouched")
        XCTAssertEqual(fixture.terminal.numberOfTabs(), numberOfTabs + 1)
        let added = try XCTUnwrap(fixture.terminal.tabs().last)
        XCTAssertEqual(added.sessions()?.count, 1)
        XCTAssertTrue(added.sessions()?.first?.isArchive ?? false)
    }

    /// When the float's tab is gone, the archive gets a tab of its own, as a tiled pane's does.
    func testAnArchivedFloatWhoseTabIsGoneGetsItsOwnTab() throws {
        let float = fixture.addFloat(frame: NSRect(x: 40, y: 40, width: 300, height: 200))
        let closing = tab
        let arrangement = try XCTUnwrap(closing.arrangement())
        let archives = try closeAndArchive(float, in: closing)
        _ = fixture.addTab()
        fixture.terminal.perform(NSSelectorFromString("removeTab:"), with: closing)
        let numberOfTabs = fixture.terminal.numberOfTabs()

        fixture.terminal.recreateTab(closing, withArrangement: arrangement, sessions: [], archives: archives, revive: true)

        XCTAssertEqual(fixture.terminal.numberOfTabs(), numberOfTabs + 1)
        let added = try XCTUnwrap(fixture.terminal.tabs().last)
        XCTAssertEqual(added.sessions()?.count, 1)
        XCTAssertTrue(added.sessions()?.first?.isArchive ?? false)
    }
}
