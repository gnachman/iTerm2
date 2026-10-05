//
//  PTYTabArchivedSessionMapTests.swift
//  ModernTests
//
//  Undo Close restores a tab whose panes are partly live and partly archived
//  (their undo window ran out). Each archived session's arrangement takes the
//  place of the session it replaces, marked as an archive. A marked pane needs
//  no live session in the session map; any other pane does.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTabArchivedSessionMapTests: XCTestCase {
    // Mirrors the file-static key in PTYSession.m.
    private let kSessionGUID = "Session GUID"

    private func leaf(guid: String, archived: Bool) -> [String: Any] {
        var session: [AnyHashable: Any] = [kSessionGUID: guid]
        if archived {
            session = PTYSession.arrangement(session, markedAsArchiveAtPath: "/archive")
        }
        return [
            TAB_ARRANGEMENT_VIEW_TYPE: VIEW_TYPE_SESSIONVIEW,
            TAB_ARRANGEMENT_SESSION: session,
        ]
    }

    private func tab(_ leaves: [[String: Any]]) -> [String: Any] {
        return [
            TAB_ARRANGEMENT_ROOT: [
                TAB_ARRANGEMENT_VIEW_TYPE: VIEW_TYPE_SPLITTER,
                SUBVIEWS: leaves,
            ] as [String: Any]
        ]
    }

    func testAllArchivedNeedsNoSessions() {
        let arrangement = tab([leaf(guid: "a", archived: true),
                               leaf(guid: "b", archived: true)])
        let map = PTYTab.sessionMap(withArrangement: arrangement, sessions: [])
        XCTAssertNotNil(map)
        XCTAssertEqual(map?.count, 0)
    }

    func testUnarchivedPaneWithoutSessionFails() {
        let arrangement = tab([leaf(guid: "a", archived: true),
                               leaf(guid: "b", archived: false)])
        XCTAssertNil(PTYTab.sessionMap(withArrangement: arrangement, sessions: []))
    }

    private func session(at index: Int, in tabArrangement: [AnyHashable: Any]) -> [AnyHashable: Any]? {
        let root = tabArrangement[TAB_ARRANGEMENT_ROOT] as? [AnyHashable: Any]
        let leaves = root?[SUBVIEWS] as? [[AnyHashable: Any]]
        return leaves?[index][TAB_ARRANGEMENT_SESSION] as? [AnyHashable: Any]
    }

    private func writeArchive(sessionGUID: String) throws -> String {
        let archivedSession: [AnyHashable: Any] = [kSessionGUID: sessionGUID, "Contents": "archived"]
        let window: [AnyHashable: Any] = [
            TERMINAL_ARRANGEMENT_TABS: [tab([[
                TAB_ARRANGEMENT_VIEW_TYPE: VIEW_TYPE_SESSIONVIEW,
                TAB_ARRANGEMENT_SESSION: archivedSession,
            ]])]
        ]
        let path = NSTemporaryDirectory() + UUID().uuidString + ".itermarchive"
        XCTAssertTrue((window as NSDictionary).write(toFile: path, atomically: true))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    func testArchiveTakesTheExpiredSessionsPlace() throws {
        let path = try writeArchive(sessionGUID: "a")
        let archives = iTermUndoCloseArchives(pathsBySessionGUID: ["a": path])
        let original = tab([leaf(guid: "a", archived: false),
                            leaf(guid: "b", archived: false)])
        let result = archives.tabArrangementBySubstitutingArchives(in: original)

        let a = try XCTUnwrap(session(at: 0, in: result))
        XCTAssertEqual(a["Contents"] as? String, "archived")
        XCTAssertTrue(PTYSession.arrangementIsMarked(asArchive: a))

        let b = try XCTUnwrap(session(at: 1, in: result))
        XCTAssertFalse(PTYSession.arrangementIsMarked(asArchive: b))
        XCTAssertNil(b["Contents"])

        XCTAssertEqual(archives.standaloneTabArrangements.count, 1)
    }

    func testUnreadableArchiveRestoresEmptyInPlace() throws {
        let archives = iTermUndoCloseArchives(pathsBySessionGUID: ["a": "/nonexistent/x.itermarchive"])
        let result = archives.tabArrangementBySubstitutingArchives(in: tab([leaf(guid: "a", archived: false)]))
        let a = try XCTUnwrap(session(at: 0, in: result))
        XCTAssertTrue(PTYSession.arrangementIsMarked(asArchive: a))
        XCTAssertNotNil(PTYTab.sessionMap(withArrangement: result, sessions: []))
        XCTAssertEqual(archives.standaloneTabArrangements.count, 0)
    }

    func testMarkIsDetected() {
        let marked = PTYSession.arrangement([kSessionGUID: "a"], markedAsArchiveAtPath: "/archive")
        XCTAssertTrue(PTYSession.arrangementIsMarked(asArchive: marked))
        XCTAssertFalse(PTYSession.arrangementIsMarked(asArchive: [kSessionGUID: "a"]))
        XCTAssertEqual(PTYSession.guid(inArrangement: marked), "a")
    }
}
