//
//  SaveScreenWhenCursorMovesAboveOutputTests.swift
//  iTerm2
//
//  Tests for preserving on-screen content when a full-screen program that doesn't use the
//  alternate screen buffer (e.g. Claude Code) repaints from the top of the screen on launch.
//

import XCTest
@testable import iTerm2SharedARC

class SaveScreenWhenCursorMovesAboveOutputTests: XCTestCase {
    private var session = FakeSession()

    /// Feed raw bytes through the real parser (so CSI sequences dispatch through the normal
    /// terminal handlers), then flush the token executor so the effects are visible synchronously.
    private func feed(_ screen: VT100Screen, _ string: String) {
        screen.inject(string.data(using: .utf8)!)
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    /// Builds a screen, appends `priorLines` (the content already on screen), then simulates shell
    /// integration establishing a running command whose output begins at `outputStartRow`
    /// (FTCS C). Going through FTCS C is important: the setup appends set the
    /// "appended text since command executed" flag, and FTCS C is what resets it, mirroring the
    /// real sequence where the echoed command text precedes the marker and the program's output
    /// follows it.
    private func makeRunningCommandScreen(width: Int,
                                          height: Int,
                                          priorLines: [String],
                                          outputStartRow: Int) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.terminalEnabled = true
            ms.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(Int32(width), height: Int32(height), mutableState: ms)
            for line in priorLines {
                ms.appendString(atCursor: line)
                ms.appendCarriageReturnLineFeed()
            }
        })
        // Put the cursor where the command's output begins (1-based row). This is a real CSI H, but
        // the feature can't fire yet because no running command's output start has been established.
        feed(screen, "\u{1b}[\(outputStartRow + 1);1H")
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.setCoordinateOfCommandStart(VT100GridAbsCoord(x: 0, y: Int64(outputStartRow)))
            ms.terminalCommandDidEnd()
        })
        return screen
    }

    /// The program moves the cursor to the top of the screen before writing any output of its own.
    /// The visible content should be scrolled into history and the grid cleared.
    func testScrollsScreenIntoHistoryWhenProgramMovesAboveOutputBeforeWriting() {
        let screen = makeRunningCommandScreen(width: 5, height: 6,
                                              priorLines: ["AAAA", "BBBB"],
                                              outputStartRow: 2)
        XCTAssertGreaterThanOrEqual(screen.startOfRunningCommandOutput.x, 0,
                                    "setup should have established a running command")

        feed(screen, "\u{1b}[H")   // CSI H: move cursor to top-left

        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       ["AAAA.",
                        "BBBB.",
                        ".....",
                        ".....",
                        ".....",
                        ".....",
                        ".....",
                        "....."].joined(separator: "\n"))
    }

    /// If the program has already drawn its own output, moving the cursor up to repaint must not
    /// scroll that output into history.
    func testDoesNotScrollWhenProgramAlreadyProducedOutput() {
        let screen = makeRunningCommandScreen(width: 5, height: 6,
                                              priorLines: ["AAAA", "BBBB"],
                                              outputStartRow: 2)
        feed(screen, "CCCC")        // program writes output
        feed(screen, "\u{1b}[H")    // then repaints from the top

        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       ["AAAA.",
                        "BBBB.",
                        "CCCC.",
                        ".....",
                        ".....",
                        "....."].joined(separator: "\n"))
    }

    /// Relaunch case: the previous session left content on screen below where the new command's
    /// output begins (CCCC, DDDD). Because this command hasn't produced output yet, that leftover
    /// content must still be preserved, even though it sits at/below the output-start row. (A
    /// grid-contents check would wrongly see that content and refuse to scroll.)
    func testPreservesLeftoverContentBelowOutputStartOnRelaunch() {
        let screen = makeRunningCommandScreen(width: 5, height: 6,
                                              priorLines: ["AAAA", "BBBB", "CCCC", "DDDD"],
                                              outputStartRow: 2)
        feed(screen, "\u{1b}[H")

        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       ["AAAA.",
                        "BBBB.",
                        "CCCC.",
                        "DDDD.",
                        ".....",
                        ".....",
                        ".....",
                        ".....",
                        ".....",
                        "....."].joined(separator: "\n"))
    }

    /// Without shell integration there is no known output-start, so the screen is left alone.
    func testDoesNotScrollWithoutShellIntegration() {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.terminalEnabled = true
            ms.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(5, height: 6, mutableState: ms)
            ms.appendString(atCursor: "AAAA")
            ms.appendCarriageReturnLineFeed()
            ms.appendString(atCursor: "BBBB")
            ms.appendCarriageReturnLineFeed()
        })
        feed(screen, "\u{1b}[H")

        XCTAssertEqual(screen.compactLineDumpWithHistory(),
                       ["AAAA.",
                        "BBBB.",
                        ".....",
                        ".....",
                        ".....",
                        "....."].joined(separator: "\n"))
    }

    // MARK: - Folds (no shell integration required)

    private func foldCount(_ screen: VT100Screen) -> Int {
        var n = 0
        screen.performBlock(joinedThreads: { _, ms, _ in
            n = ms.intervalTree.allObjects().compactMap { $0 as? FoldMark }.count
        })
        return n
    }

    private func scrollbackLines(_ screen: VT100Screen) -> Int {
        var n = 0
        screen.performBlock(joinedThreads: { _, ms, _ in n = Int(ms.numberOfScrollbackLines) })
        return n
    }

    /// Number of fold marks whose line currently lives in the addressable grid (at or below the top
    /// of the visible screen): the ones at risk of being overwritten and orphaned by a repaint.
    private func foldsInGrid(_ screen: VT100Screen) -> Int {
        var n = 0
        screen.performBlock(joinedThreads: { _, ms, _ in
            let gridTopAbs = ms.cumulativeScrollbackOverflow + Int64(ms.numberOfScrollbackLines)
            n = ms.intervalTree.allObjects().filter { obj in
                guard let fold = obj as? FoldMark, let interval = fold.entry?.interval else { return false }
                return ms.absCoordRange(for: interval).start.y >= gridTopAbs
            }.count
        })
        return n
    }

    private func makeScreenWithFold() -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.terminalEnabled = true
            ms.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(5, height: 6, mutableState: ms)
            for line in ["AAAA", "BBBB", "CCCC", "DDDD"] {
                ms.appendString(atCursor: line)
                ms.appendCarriageReturnLineFeed()
            }
        })
        // Fold BBBB and CCCC (abs lines 1...2) into one placeholder. No FTCS was sent, so there is
        // no shell integration: the command-output path cannot fire and the fold is the only anchor.
        screen.foldAbsLineRange(NSRange(location: 1, length: 1))
        screen.performBlock(joinedThreads: { _, _, _ in })
        return screen
    }

    /// A program that doesn't use the alternate screen homes the cursor above an in-grid fold and
    /// repaints. Even with no shell integration, the fold must be scrolled into history (preserving
    /// its mark) instead of being overwritten in place and leaving an orphaned unfold icon.
    func testScrollsFoldIntoHistoryWithoutShellIntegration() {
        let screen = makeScreenWithFold()

        XCTAssertLessThan(screen.startOfRunningCommandOutput.x, 0,
                          "setup: no shell integration, so the command-output path cannot fire")
        XCTAssertEqual(foldCount(screen), 1, "setup: one fold")
        XCTAssertEqual(scrollbackLines(screen), 0, "setup: nothing in history yet")
        XCTAssertEqual(foldsInGrid(screen), 1, "setup: the fold is in the grid")

        feed(screen, "\u{1b}[H")   // CSI H: move cursor to top-left, above the fold

        XCTAssertEqual(foldCount(screen), 1, "the fold must be preserved, not destroyed")
        XCTAssertGreaterThan(scrollbackLines(screen), 0, "the fold and content above it scrolled into history")
        XCTAssertEqual(foldsInGrid(screen), 0, "no fold left in the grid to be orphaned")
    }

    /// Control: while the cursor stays below the bottommost fold they coexist, so a repaint below the
    /// fold must not scroll anything into history.
    func testDoesNotScrollWhenCursorStaysBelowFold() {
        let screen = makeScreenWithFold()
        let before = scrollbackLines(screen)

        feed(screen, "\u{1b}[4;1H")   // move the cursor to a row below the fold

        XCTAssertEqual(scrollbackLines(screen), before, "must not scroll when the cursor is below the fold")
        XCTAssertEqual(foldsInGrid(screen), 1, "the fold remains in the grid, coexisting with the cursor")
    }

    /// The actual reported scenario: shell integration IS installed, but the program (Claude Code)
    /// emits FTCS C, draws its banner, and only THEN homes the cursor to repaint. The banner draw sets
    /// appendedTextSinceCommandExecuted, so saveScreenToScrollbackIfCursorMovedAboveCommandOutput bails
    /// at its mid-run-repaint guard. The fold path doesn't consult that flag, so it must still preserve
    /// the fold.
    func testScrollsFoldIntoHistoryWhenProgramDrawsThenHomesWithShellIntegration() {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.terminalEnabled = true
            ms.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(5, height: 8, mutableState: ms)
            for line in ["TOP0", "TOP1", "TOP2", "PMPT"] {
                ms.appendString(atCursor: line)
                ms.appendCarriageReturnLineFeed()
            }
        })
        // Fold the top prior content (TOP0, TOP1) into one placeholder at the top of the grid.
        screen.foldAbsLineRange(NSRange(location: 0, length: 1))
        screen.performBlock(joinedThreads: { _, _, _ in })

        // Shell integration: establish a running command (FTCS C), which sets the output start and
        // resets appendedTextSinceCommandExecuted, mirroring a real shell launching `claude`.
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.setCoordinateOfCommandStart(VT100GridAbsCoord(x: 0, y: 2))
            ms.terminalCommandDidEnd()
        })
        XCTAssertGreaterThanOrEqual(screen.startOfRunningCommandOutput.x, 0,
                                    "setup: shell integration established an output start")
        XCTAssertEqual(foldsInGrid(screen), 1, "setup: the fold is in the grid")

        // The program draws its banner BEFORE homing the cursor. This sets the appended-text flag, which
        // is exactly what makes the command-output preservation path bail.
        feed(screen, "BANNER")

        // Now it homes the cursor above the fold and repaints.
        feed(screen, "\u{1b}[H")

        XCTAssertEqual(foldCount(screen), 1, "fold preserved")
        XCTAssertEqual(foldsInGrid(screen), 0,
                       "fold scrolled into history even though the command-output path bailed on appendedText")
    }

}
