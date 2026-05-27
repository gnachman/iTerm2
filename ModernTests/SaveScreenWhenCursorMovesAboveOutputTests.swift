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
}
