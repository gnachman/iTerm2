//
//  TitleFloodTests.swift
//  iTerm2
//
//  QA finding F-327: a program setting the window title as fast as it can
//  write must not cost the main thread a title update, and a working
//  directory fetch, per escape sequence.
//

import XCTest
@testable import iTerm2SharedARC

final class TitleFloodTests: XCTestCase {
    private func titles(_ count: Int) -> [String] {
        return (0..<count).flatMap { ["t\($0)", "u\($0)"] }
    }

    /// Sets each title inside one joined block, the way the parser would
    /// with nothing else in between, then lets the side effects run.
    private func setWindowTitles(_ harness: TerminalTestHarness, _ titles: [String]) {
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for title in titles {
                mutableState.terminalSetWindowTitle(title)
            }
        })
        harness.sync()
    }

    func testWindowTitleFloodIsAppliedOnce() {
        let harness = TerminalTestHarness()
        setWindowTitles(harness, titles(5000))
        XCTAssertEqual(harness.delegate.titleEvents, ["window u4999", "pwd"])
    }

    func testIconTitleFloodIsAppliedOnce() {
        let harness = TerminalTestHarness()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for title in self.titles(5000) {
                mutableState.terminalSetIconTitle(title)
            }
        })
        harness.sync()
        XCTAssertEqual(harness.delegate.titleEvents, ["icon u4999"])
    }

    // OSC 0 sets both titles. Each kind keeps its own latest value.
    func testMixedFloodKeepsLatestOfEachKind() {
        let harness = TerminalTestHarness()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<5000 {
                mutableState.terminalSetWindowTitle("w\(i)")
                mutableState.terminalSetIconTitle("i\(i)")
            }
        })
        harness.sync()
        XCTAssertEqual(harness.delegate.windowTitleCount, 1)
        XCTAssertEqual(harness.delegate.iconNameCount, 1)
        XCTAssertTrue(harness.delegate.titleEvents.contains("window w4999"), "\(harness.delegate.titleEvents)")
        XCTAssertTrue(harness.delegate.titleEvents.contains("icon i4999"), "\(harness.delegate.titleEvents)")
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 1)
    }

    // End to end through the parser, as in the QA repro.
    func testFloodThroughParserIsCoalesced() {
        let harness = TerminalTestHarness()
        let flood = (0..<5000).map { "\u{1b}]2;t\($0)\u{07}\u{1b}]2;u\($0)\u{07}" }.joined()
        harness.feedEscapeSequence(Array(flood.utf8))
        harness.sync()
        XCTAssertEqual(harness.delegate.titleEvents, ["window u4999", "pwd"])
    }

    // Coalescing must not move a title past a side effect that came after
    // it, such as a bell.
    func testTitlesKeepTheirPlaceAroundOtherSideEffects() {
        let harness = TerminalTestHarness()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetWindowTitle("a")
            mutableState.terminalSetWindowTitle("b")
            mutableState.terminalRingBell()
            mutableState.terminalSetWindowTitle("c")
            mutableState.terminalSetWindowTitle("d")
        })
        harness.sync()
        XCTAssertEqual(harness.delegate.titleEvents,
                       ["window b", "pwd", "bell", "window d", "pwd"])
    }

    // A title that arrives after its batch went to the main thread starts a
    // new one rather than being lost.
    func testTitleAfterBatchWasTakenStartsANewBatch() {
        let harness = TerminalTestHarness()
        setWindowTitles(harness, ["a"])
        setWindowTitles(harness, ["b"])
        XCTAssertEqual(harness.delegate.titleEvents, ["window a", "pwd", "window b", "pwd"])
    }

    // With shell integration reporting the directory, a title only polls the
    // local directory, and a flood polls it once.
    func testFloodWithShellIntegrationPollsLocalDirectoryOnce() {
        let harness = TerminalTestHarness()
        harness.sendCurrentDirectory(path: "/tmp")
        harness.resetCalls()
        setWindowTitles(harness, titles(5000))
        XCTAssertEqual(harness.delegate.titleEvents, ["window u4999", "poll local"])
    }

    // A flood spread over many lines still asks for the directory once, and
    // logs it for the first line and the last, so the working directory mark
    // spans them just as it would have had each title fetched.
    func testFloodOverManyLinesFetchesDirectoryOnceForFirstAndLastLine() {
        let harness = TerminalTestHarness()
        harness.delegate.polledWorkingDirectory = "/tmp"
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for i in 0..<1000 {
                mutableState.terminalSetWindowTitle("t\(i)")
                mutableState.appendCarriageReturnLineFeed()
            }
        })
        harness.sync()
        XCTAssertEqual(harness.delegate.windowTitleCount, 1)
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 1)
        XCTAssertEqual(harness.delegate.logWorkingDirectoryCalls.map(\.line), [0, 999])
        var overflow: Int64 = 0
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            overflow = mutableState.cumulativeScrollbackOverflow
        })
        for absLine: Int64 in [0, 500, 999] {
            let line = Int32(absLine - overflow)
            XCTAssertEqual(harness.screen.workingDirectory(onLine: line), "/tmp", "line \(absLine)")
        }
    }

    // When the cursor goes back up between titles, the last title's line is
    // logged after the first's, as each title would have been in turn.
    func testFloodThatMovesBackUpLogsFirstThenLastLine() {
        let harness = TerminalTestHarness()
        harness.delegate.polledWorkingDirectory = "/tmp"
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for line: Int32 in [10, 20, 5] {
                mutableState.terminalMoveCursorTo(x: 1, y: line + 1)
                mutableState.terminalSetWindowTitle("t\(line)")
            }
        })
        harness.sync()
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 1)
        XCTAssertEqual(harness.delegate.logWorkingDirectoryCalls.map(\.line), [10, 5])
    }

    // With a remote host known, a title does not touch the working directory,
    // and a flood is still applied once.
    func testFloodWithRemoteHostAppliesTitleOnceWithoutDirectoryWork() {
        let harness = TerminalTestHarness()
        harness.sendRemoteHost(user: "user", host: "example.com")
        harness.resetCalls()
        setWindowTitles(harness, titles(5000))
        XCTAssertEqual(harness.delegate.titleEvents, ["window u4999"])
    }

    // An icon title waits for a deferred pass, but a window title that needs
    // the directory does not, so it starts a batch of its own rather than
    // joining the deferred one.
    func testWindowTitleDoesNotJoinDeferredIconBatch() {
        let harness = TerminalTestHarness()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetIconTitle("i")
            mutableState.terminalSetWindowTitle("w")
            mutableState.terminalSetIconTitle("j")
        })
        harness.sync()
        XCTAssertEqual(harness.delegate.titleEvents, ["icon i", "window w", "icon j", "pwd"])
    }

    // OSC 1 with a newline sets the icon title and the subtitle. A flood of
    // them keeps the latest of each.
    func testIconAndSubtitleFloodThroughParserIsCoalesced() {
        let harness = TerminalTestHarness()
        let flood = (0..<1000).map { "\u{1b}]1;a\($0)\nb\($0)\u{07}" }.joined()
        harness.feedEscapeSequence(Array(flood.utf8))
        harness.sync()
        XCTAssertEqual(harness.delegate.titleEvents, ["icon a999", "subtitle b999"])
    }

    // A title the profile does not allow is not applied, but the directory is
    // still fetched, as before.
    func testDisallowedTitleIsNotApplied() {
        let harness = TerminalTestHarness()
        harness.delegate.allowTitleSetting = false
        setWindowTitles(harness, titles(10))
        XCTAssertEqual(harness.delegate.titleEvents, ["pwd"])
    }
}
