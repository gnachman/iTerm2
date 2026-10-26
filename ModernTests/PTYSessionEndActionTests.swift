//
//  PTYSessionEndActionTests.swift
//  iTerm2 ModernTests
//
//  PTYSession.forceDefaultEndAction is the durable pin that keeps a
//  workgroup-spawned member (peer, split, or tab) from ever reporting a
//  Close end action, no matter what the profile's "Close Sessions On End"
//  (KEY_SESSION_END_ACTION) setting is or how a later profile sync
//  reconciles it. Without the pin, a member could quietly flip to Close and
//  auto-close when its program exits (e.g. a Diff pane whose difftool
//  finishes), which tears the whole workgroup down.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionEndActionTests: XCTestCase {
    func testDefaultSessionReportsItsAppliedEndAction() {
        let s = PTYSession(synthetic: false)!
        XCTAssertFalse(s.forceDefaultEndAction,
                       "A plain session must not pin the end action")
        s.endAction = .close
        XCTAssertEqual(s.endAction, .close,
                       "Baseline: endAction reflects the applied Close setting")
    }

    func testForceDefaultEndActionOverridesCloseSetting() {
        let s = PTYSession(synthetic: false)!
        s.endAction = .close
        s.forceDefaultEndAction = true
        XCTAssertEqual(s.endAction, .default,
                       "forceDefaultEndAction must override a Close end action")
    }

    func testPinSurvivesALaterProfileSyncToClose() {
        let s = PTYSession(synthetic: false)!
        s.forceDefaultEndAction = true
        // setPreferencesFromAddressBookEntry drives self.endAction = <profile
        // value> on a profile sync; simulate that reconciling the key back to
        // Close. The pin must win.
        s.endAction = .close
        XCTAssertEqual(s.endAction, .default,
                       "The pin must survive a later setEndAction(.close)")
    }
}

/// F-609: when a session's program ends, the “Session ended. Restart it?”
/// announcement slides over the top rows of the session. Short output (for
/// example a custom command that just echoes something) lives in those rows,
/// so it must be moved down out from under the announcement, not left hidden.
final class PTYSessionEndedMessageTests: XCTestCase {
    private let width: Int32 = 40
    private let height: Int32 = 10

    private func makeSession() -> PTYSession {
        let session = PTYSession(synthetic: false)!
        let screen = session.screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { [width, height] _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
            mutableState.maxScrollbackLines = 1000
        })
        return session
    }

    private func append(_ lines: [String], to session: PTYSession) {
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for line in lines {
                mutableState.appendString(atCursor: line)
                mutableState.appendCarriageReturnLineFeed()
            }
        })
    }

    // What -brokenPipeWithError: does for a session that offers to restart.
    private func endSession(_ session: PTYSession) {
        session.perform(NSSelectorFromString("appendBrokenPipeMessage:"), with: "Session Ended")
        session.perform(NSSelectorFromString("queueRestartSessionAnnouncement"))
    }

    private func screenLines(_ session: PTYSession) -> [String] {
        return session.screen.compactLineDump().components(separatedBy: "\n")
    }

    func testShortOutputMovesToTheBottomOfTheScreen() {
        let session = makeSession()
        append(["hello-there"], to: session)
        endSession(session)

        let lines = screenLines(session)
        XCTAssertEqual(lines.count, Int(height))
        XCTAssertTrue(lines[Int(height) - 3].hasPrefix("hello-there"),
                      "Output should sit just above the message: \(lines)")
        XCTAssertTrue(lines[Int(height) - 2].contains("Session Ended"),
                      "Message should be on the second-to-last row: \(lines)")
        XCTAssertTrue(lines.prefix(Int(height) - 3).allSatisfy { $0.allSatisfy { $0 == "." } },
                      "Rows above the output should be blank: \(lines)")
        XCTAssertEqual(session.screen.numberOfScrollbackLines(), 0,
                       "Nothing should be pushed into scrollback")
    }

    func testMarksMoveWithTheirLines() {
        let session = makeSession()
        append(["first", "second"], to: session)
        var mark: iTermMark?
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            // A mark on “second”, the second row.
            let line = Int64(mutableState.cumulativeScrollbackOverflow) + Int64(mutableState.numberOfScrollbackLines) + 1
            mark = mutableState.addMarkStarting(atAbsoluteLine: line, oneLine: true, of: VT100ScreenMark.self) as? iTermMark
        })
        XCTAssertNotNil(mark)
        endSession(session)

        let lines = screenLines(session)
        let secondRow = lines.firstIndex { $0.hasPrefix("second") }
        XCTAssertEqual(secondRow, Int(height) - 3, "\(lines)")
        var markRow: Int64 = -1
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            let range = mutableState.absCoordRange(for: mark?.entry?.interval)
            markRow = range.start.y - Int64(mutableState.cumulativeScrollbackOverflow) - Int64(mutableState.numberOfScrollbackLines)
        })
        XCTAssertEqual(markRow, Int64(height) - 3,
                       "The mark should still be on the line with “second”")
    }

    // After a clear, which moves the screen into scrollback, the cleared
    // lines stay in scrollback and marks there stay put.
    func testScrollbackIsUntouched() {
        let session = makeSession()
        let history = (0..<Int(height) * 2).map { "old \($0)" }
        append(history, to: session)
        var mark: iTermMark?
        var scrollbackBefore: Int32 = 0
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mark = mutableState.addMarkStarting(atAbsoluteLine: Int64(mutableState.cumulativeScrollbackOverflow) + 3,
                                                oneLine: true,
                                                of: VT100ScreenMark.self) as? iTermMark
            mutableState.eraseInDisplay(beforeCursor: true, afterCursor: true, decProtect: false)
            mutableState.cursorTo(x: 1)
            mutableState.cursorTo(y: 1)
            scrollbackBefore = mutableState.numberOfScrollbackLines
        })
        append(["hello-there"], to: session)
        endSession(session)

        let lines = screenLines(session)
        XCTAssertTrue(lines[Int(height) - 3].hasPrefix("hello-there"), "\(lines)")
        XCTAssertFalse(lines.contains { $0.hasPrefix("old") }, "Cleared lines must not come back: \(lines)")
        var markLine: Int64 = -1
        var scrollbackAfter: Int32 = 0
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            markLine = mutableState.absCoordRange(for: mark?.entry?.interval).start.y - Int64(mutableState.cumulativeScrollbackOverflow)
            scrollbackAfter = mutableState.numberOfScrollbackLines
        })
        XCTAssertEqual(scrollbackAfter, scrollbackBefore)
        XCTAssertEqual(markLine, 3, "A mark in scrollback must not move")
    }

    // Text a program left below the cursor is kept.
    func testTextBelowTheCursorIsKept() {
        let session = makeSession()
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "output")
            mutableState.cursorTo(y: 5)
            mutableState.cursorTo(x: 1)
            mutableState.appendString(atCursor: "status")
            mutableState.cursorTo(y: 2)
            mutableState.cursorTo(x: 1)
        })
        endSession(session)

        let lines = screenLines(session)
        XCTAssertNotNil(lines.firstIndex { $0.hasPrefix("output") }, "\(lines)")
        XCTAssertNotNil(lines.firstIndex { $0.hasPrefix("status") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("Session Ended") }, "\(lines)")
        XCTAssertEqual(session.screen.numberOfScrollbackLines(), 0)
    }

    func testFullScreenIsNotRearranged() {
        let session = makeSession()
        let lines = (0..<Int(height) * 2).map { "line \($0)" }
        append(lines, to: session)
        endSession(session)

        let dump = session.screen.compactLineDumpWithHistory().components(separatedBy: "\n")
        let expected = lines.map { $0 + String(repeating: ".", count: Int(width) - $0.count) }
        XCTAssertEqual(Array(dump.prefix(lines.count)), expected,
                       "Existing output is kept in order")
    }
}
