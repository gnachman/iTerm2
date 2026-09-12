//
//  ReportSyncCoalescingTests.swift
//  iTerm2
//
//  Regression tests for issues 13013 and 13035: a burst of OSC 4 color queries
//  (herdr queries all 256 palette colors on every focus event) used to pause+join
//  once per query, freezing the UI; a pipelined run of CSI 6 n cursor-position
//  queries was paced the same way. OSC 4 queries and device status reports now use
//  the coalescible report gate, which arms a skip-sync flag that stays set across a
//  run of such queries and is invalidated by any state side effect, so a pure burst
//  pays a single joined sync. Both read mutation-thread-owned state (colorMap; the
//  grid cursor), so skipping the extra syncs cannot return stale values.
//
//  These tests exercise the REAL token executor (via screen.inject) so the
//  rollback/pause/joined-sync gate actually runs. Crucially they observe the
//  mechanism, not just the output: VT100ScreenMutableState.reportSyncCount counts
//  how many reports took the pause+sync path, so a burst that coalesces advances
//  it by 1 while a run of un-coalesced reports advances it by N. Reverting the
//  skip-sync arming flips those counts and fails these tests (verified).
//
//  Determinism: waits pump the run loop until the expected number of reports have
//  actually been delivered (report sends are asynchronous), never on a wall-clock
//  timeout, so they can't return early under load. A bound turns a real hang
//  (e.g. the non-coalescible livelock) into a failure instead of an infinite spin.
//

import XCTest
@testable import iTerm2SharedARC

private final class ReportRecordingSession: FakeSession {
    // Report bytes as strings, in delivery order.
    private(set) var reports: [String] = []

    override func screenSendReport(_ data: Data) {
        reports.append(String(data: data, encoding: .utf8) ?? "")
    }

    func resetReports() {
        reports.removeAll()
    }
}

final class ReportSyncCoalescingTests: XCTestCase {
    private let session = ReportRecordingSession()

    private func makeScreen(width: Int32 = 80, height: Int32 = 25) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
        })
        return screen
    }

    /// Feed bytes through the real read/execute pipeline and deterministically
    /// wait until `expected` more reports have been delivered. Returns as soon as
    /// they arrive; fails (rather than spinning forever) if they never do.
    private func feed(_ screen: VT100Screen, _ string: String, expecting expected: Int,
                      file: StaticString = #filePath, line: UInt = #line) {
        let target = session.reports.count + expected
        screen.inject(string.data(using: .utf8)!)
        for _ in 0..<20000 {
            if session.reports.count >= target { return }
            screen.performBlock(joinedThreads: { _, _, _ in })
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
        XCTFail("Timed out waiting for \(expected) reports; got \(session.reports.count - (target - expected))",
                file: file, line: line)
    }

    /// How many reports have taken the pause+sync path so far.
    private func syncCount(_ screen: VT100Screen) -> Int {
        var n = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in n = mutableState.reportSyncCount })
        return n
    }

    // ESC ] 4 ; index ; ? BEL
    private func query(_ index: Int) -> String { "\u{1b}]4;\(index);?\u{07}" }
    // ESC ] 4 ; index ; rgb:RRRR/GGGG/BBBB BEL
    private func setColor(_ index: Int, _ hex: String) -> String { "\u{1b}]4;\(index);rgb:\(hex)\u{07}" }

    /// herdr's burst: all 256 palette queries at once must produce 256 correct
    /// reports AND coalesce to a single pause+sync. The sync-count assertion is
    /// the actual 13013 guard: without skip-sync it would be 256.
    func testFullPaletteQueryBurstCoalescesToOneSync() {
        let screen = makeScreen()
        session.resetReports()
        let syncsBefore = syncCount(screen)

        var burst = ""
        for i in 0..<256 { burst += query(i) }
        feed(screen, burst, expecting: 256)

        XCTAssertEqual(session.reports.count, 256, "Every OSC 4 query must produce exactly one report")
        for (i, report) in session.reports.enumerated() {
            XCTAssertTrue(report.hasPrefix("\u{1b}]4;\(i);"),
                          "Report \(i) should be for index \(i): \(report.debugDescription)")
        }
        XCTAssertEqual(syncCount(screen) - syncsBefore, 1,
                       "A pure color-query burst must coalesce to a single pause+sync")
    }

    /// Output between queries disarms skip-sync, so each query after output takes
    /// a fresh sync. This asserts the disarm actually happens (sync count == N),
    /// exercising the arm/disarm cycle repeatedly, and that nothing is dropped.
    func testOutputBetweenQueriesForcesResync() {
        let screen = makeScreen()
        session.resetReports()
        let syncsBefore = syncCount(screen)

        let indices = Array(0..<40)
        var stream = ""
        for i in indices {
            stream += "x"          // output -> setNeedsRedraw -> disarms skip-sync
            stream += query(i)     // must re-sync and report the right index
        }
        feed(screen, stream, expecting: indices.count)

        XCTAssertEqual(session.reports.count, indices.count)
        for (i, report) in session.reports.enumerated() {
            XCTAssertTrue(report.hasPrefix("\u{1b}]4;\(indices[i]);"),
                          "Report \(i) should be for index \(indices[i]): \(report.debugDescription)")
        }
        XCTAssertEqual(syncCount(screen) - syncsBefore, indices.count,
                       "Every query preceded by output must re-sync (disarm works)")
    }

    /// Regression for the livelock: a single DSR cursor position (ESC[6n) must be
    /// delivered exactly once and take exactly one sync. DSR is coalescible (issue
    /// 13035), but a lone query with the skip-sync flag disarmed still syncs once;
    /// the point here is that allowNextReport applies to every report, so the
    /// rolled-back token delivers on re-execution instead of looping forever.
    func testCursorPositionReportProducesExactlyOneReport() {
        let screen = makeScreen()
        session.resetReports()
        let syncsBefore = syncCount(screen)

        feed(screen, "\u{1b}[6n", expecting: 1)   // DSR 6 -> CPR

        XCTAssertEqual(session.reports.count, 1)
        XCTAssertTrue((session.reports.first ?? "").hasSuffix("R"),
                      "CPR should end in R: \((session.reports.first ?? "").debugDescription)")
        XCTAssertEqual(syncCount(screen) - syncsBefore, 1)
    }

    /// herdr/notcurses-style burst: many CSI 6 n cursor-position queries in one
    /// write must produce one report each AND coalesce to a single pause+sync,
    /// because the cursor is mutation-thread-owned and no state changes between
    /// them. Without DSR coalescing this would be one sync per query (issue 13035).
    func testCursorPositionBurstCoalescesToOneSync() {
        let screen = makeScreen()
        session.resetReports()
        let syncsBefore = syncCount(screen)

        let count = 200
        var burst = ""
        for _ in 0..<count { burst += "\u{1b}[6n" }
        feed(screen, burst, expecting: count)

        XCTAssertEqual(session.reports.count, count, "Every CSI 6n must produce one report")
        for report in session.reports {
            XCTAssertTrue(report.hasSuffix("R"), "Each report should be a CPR ending in R: \(report.debugDescription)")
        }
        XCTAssertEqual(syncCount(screen) - syncsBefore, 1,
                       "A pure cursor-position burst must coalesce to a single pause+sync")
    }

    /// Cross-type coalescing: a CSI 6 n right after a color-query burst shares the
    /// armed skip-sync flag (both read mutation-owned state, nothing mutates
    /// between them), so the whole run is a single sync and all reports deliver.
    func testCursorPositionAfterColorBurstCoalesces() {
        let screen = makeScreen()
        session.resetReports()
        let syncsBefore = syncCount(screen)

        var burst = ""
        for i in 0..<8 { burst += query(i) }
        burst += "\u{1b}[6n"   // DSR after the armed color run
        feed(screen, burst, expecting: 9)

        XCTAssertEqual(session.reports.count, 9, "8 color reports + 1 CPR")
        XCTAssertTrue((session.reports.last ?? "").hasSuffix("R"),
                      "Last report should be the CPR: \((session.reports.last ?? "").debugDescription)")
        XCTAssertEqual(syncCount(screen) - syncsBefore, 1,
                       "A color burst followed by a cursor query coalesces to one sync")
    }

    /// Primary Device Attributes (ESC[c) is also non-coalescible and must deliver.
    func testDeviceAttributesReportProducesExactlyOneReport() {
        let screen = makeScreen()
        session.resetReports()

        feed(screen, "\u{1b}[c", expecting: 1)

        XCTAssertEqual(session.reports.count, 1)
    }

    /// A genuinely non-coalescible report right after a coalescible color burst
    /// must still take its own sync: the burst arms skip-sync, but a non-coalescible
    /// report must not ride that flag. Secondary Device Attributes (ESC[>c) stays
    /// non-coalescible, so expect 2 syncs total: one for the burst, one for the DA.
    func testNonCoalescibleReportAfterColorBurstStillSyncs() {
        let screen = makeScreen()
        session.resetReports()
        let syncsBefore = syncCount(screen)

        var burst = ""
        for i in 0..<8 { burst += query(i) }
        burst += "\u{1b}[>c"   // secondary DA (non-coalescible) after the armed run
        feed(screen, burst, expecting: 9)

        XCTAssertEqual(session.reports.count, 9, "8 color reports + 1 secondary DA")
        XCTAssertTrue((session.reports.last ?? "").hasSuffix("c"),
                      "Last report should be the DA reply ending in c: \((session.reports.last ?? "").debugDescription)")
        XCTAssertEqual(syncCount(screen) - syncsBefore, 2,
                       "One sync for the coalesced burst, one for the non-coalescible DA")
    }

    /// A color set is visible to a later query. This is guaranteed by the OSC 4
    /// set being a pause barrier (it updates the mutation colorMap before the next
    /// token), independent of skip-sync; it guards that coalescing does not break
    /// that round-trip. (It does NOT exercise the skip-sync disarm - see the file
    /// header - so it is deliberately not named as such.)
    func testColorSetIsVisibleToLaterQuery() {
        let screen = makeScreen()
        feed(screen, query(15), expecting: 1)   // prime: arm skip-sync
        session.resetReports()

        feed(screen, setColor(15, "0000/0000/0000") + query(15), expecting: 1)

        XCTAssertTrue((session.reports.first ?? "").contains("0000/0000/0000"),
                      "Query after set must report the new color, got \((session.reports.first ?? "").debugDescription)")
    }
}
