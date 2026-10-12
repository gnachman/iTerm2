//
//  PromptMarkRightPromptTests.swift
//  iTerm2
//
//  OSC 133;P handling, in particular right prompts (P;k=r).
//
//  Shells put a right prompt in one of two places:
//
//  powerlevel10k brackets it separately, after the primary prompt's B:
//      A <left prompt> B <typed text> P;k=r <right prompt> B
//
//  reedline (nushell 0.111 and later) nests it inside the primary prompt,
//  drawn with save/restore cursor, and sends a single B for both:
//      A;k=i <left prompt> ESC7 CUP P;k=r <right prompt> ESC8 B <typed text>
//
//  The semantic prompts proposal allows both: P is an "explicit start of
//  prompt, optional after an A or N command", and B is the "end of prompt
//  and start of user input". So a B that closes a right prompt nested in a
//  primary prompt also starts the command, while the second B in the p10k
//  form only closes the right prompt.
//
//  These tests replay the exact byte sequences through the real parser so
//  VT100Terminal's inCommand_ bookkeeping and the cursor save/restore are
//  exercised.
//

import XCTest
@testable import iTerm2SharedARC

final class PromptMarkRightPromptTests: XCTestCase {
    private let width = 80
    private let leftPrompt = "/tmp> "
    private let rightPrompt = " 10/12/2026 10:12:24 AM"

    /// Column where reedline places the right prompt so it ends at the margin.
    private var rightPromptColumn: Int {
        return width - rightPrompt.count
    }

    // MARK: - reedline: right prompt nested before the single B

    /// At an idle prompt, the B that follows the nested right prompt must
    /// start the command. Without that, iTerm2 believes the shell is not at a
    /// prompt (isAtShellPrompt is false): Select Output of Last Command takes
    /// in the next prompt and Auto Composer never engages.
    func test_reedline_idlePrompt_BAfterNestedRightPrompt_startsCommand() {
        let harness = makeHarness()

        harness.send(reedlinePaint(buffer: ""))
        harness.sync()

        let start = commandStartCoord(in: harness)
        XCTAssertEqual(start.x, Int32(leftPrompt.count),
                       "The command should start right after the left prompt, "
                       + "where the cursor was restored before B")
        XCTAssertEqual(start.y, 0)
        XCTAssertGreaterThanOrEqual(harness.screen.commandRange().start.x, 0,
                                    "commandRange (isAtShellPrompt) must be valid at the idle prompt")
    }

    /// reedline repaints the whole prompt, right prompt included, on every
    /// keystroke. The command start must stay put and there must still be a
    /// single prompt mark.
    func test_reedline_keystrokeRepaints_keepCommandStartAndOneMark() {
        let harness = makeHarness()

        for buffer in ["", "e", "ec", "ech", "echo"] {
            harness.send(reedlinePaint(buffer: buffer))
        }
        harness.sync()

        XCTAssertEqual(promptMarks(in: harness).count, 1)
        let start = commandStartCoord(in: harness)
        XCTAssertEqual(start.x, Int32(leftPrompt.count))
        XCTAssertEqual(start.y, 0)
    }

    /// The right prompt is drawn after ESC7 and the cursor is restored with
    /// ESC8 before B, so the cursor at B is to the left of where P;k=r was
    /// seen. The excluded subrange must still cover the right prompt's cells
    /// rather than run backwards from the P column to the B column.
    func test_reedline_rightPromptExcludedSubrange_coversRightPromptCells() {
        let harness = makeHarness()

        harness.send(reedlinePaint(buffer: ""))
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        guard let ranges = mark.excludedSubranges, ranges.count == 1 else {
            XCTFail("Expected one excluded subrange for the right prompt, got "
                    + "\(mark.excludedSubranges?.count ?? 0)")
            return
        }
        let range = ranges[0].absRange
        XCTAssertEqual(range.start.y, range.end.y, "The right prompt is on the prompt row")
        XCTAssertEqual(range.start.x, Int32(rightPromptColumn),
                       "The exclusion starts where P;k=r was received")
        XCTAssertGreaterThanOrEqual(range.end.x, Int32(rightPromptColumn + rightPrompt.count),
                                    "The exclusion must reach the end of the right prompt, "
                                    + "not stop at the restored cursor before it")
    }

    /// Each repaint draws the right prompt again. The exclusions from earlier
    /// repaints describe cells that were just erased and redrawn, so they must
    /// not pile up on the mark.
    func test_reedline_keystrokeRepaints_doNotAccumulateRightPromptExclusions() {
        let harness = makeHarness()

        for buffer in ["", "e", "ec", "ech", "echo"] {
            harness.send(reedlinePaint(buffer: buffer))
        }
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertEqual(mark.excludedSubranges?.count, 1,
                       "Only the most recent paint's right prompt should be excluded")
    }

    /// Full cycle as nushell 0.116 sends it: the right prompt is drawn while
    /// typing and dropped from the final repaint on Return (transient right
    /// prompt). The command and exit code are recorded.
    func test_reedline_fullCycle_transientRightPrompt_recordsCommand() {
        let harness = makeHarness()

        for buffer in ["", "e", "echo", "echo hi"] {
            harness.send(reedlinePaint(buffer: buffer))
        }
        harness.send(reedlineSubmit(buffer: "echo hi", keepRightPrompt: false))
        harness.send(Array("hi\r\n".utf8))
        harness.send(osc133("D;0"))
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertEqual(mark.fullCommand, "echo hi")
        XCTAssertEqual(mark.firstLineOfCommand, "echo hi")
        XCTAssertTrue(mark.hasCode)
        XCTAssertEqual(mark.code, 0)
    }

    /// Full cycle when the right prompt stays on screen after Return (a
    /// configuration without transient prompts, and reedline's final repaint
    /// in some modes). The only B before C follows the nested right prompt, so
    /// the command is recorded only if that B starts it, and the right prompt
    /// text must not leak into the recorded command.
    func test_reedline_fullCycle_rightPromptKeptOnSubmit_recordsCommandWithoutRightPrompt() {
        let harness = makeHarness()

        harness.send(reedlinePaint(buffer: ""))
        harness.send(reedlineSubmit(buffer: "echo hi", keepRightPrompt: true))
        harness.send(Array("hi\r\n".utf8))
        harness.send(osc133("D;1"))
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertEqual(mark.fullCommand, "echo hi",
                       "The right prompt's cells must be subtracted from the command")
        XCTAssertEqual(mark.firstLineOfCommand, "echo hi")
        XCTAssertTrue(mark.hasCode)
        XCTAssertEqual(mark.code, 1)
    }

    /// The shell's history in the Command History tool comes from C. With the
    /// right prompt nested before B at an idle prompt, pressing Return on an
    /// empty line must not record a command.
    func test_reedline_emptySubmit_recordsNoCommand() {
        let harness = makeHarness()

        harness.send(reedlinePaint(buffer: ""))
        harness.send(reedlineSubmit(buffer: "", keepRightPrompt: true))
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertNil(mark.fullCommand)
        XCTAssertNil(mark.firstLineOfCommand)
    }

    // MARK: - powerlevel10k: right prompt bracketed separately after B

    /// p10k sends the primary B before its right prompt, then a second B after
    /// the right prompt. That second B must only close the right prompt: the
    /// command start stays after the left prompt instead of moving to where the
    /// right prompt ended.
    func test_p10k_secondBAfterRightPrompt_doesNotMoveCommandStart() {
        let harness = makeHarness()

        harness.send(p10kPaint(buffer: "echo hi"))
        harness.sync()

        let start = commandStartCoord(in: harness)
        XCTAssertEqual(start.x, 2, "Command starts after \"$ \"")
        XCTAssertEqual(start.y, 0)

        let mark = onlyPromptMark(in: harness)
        XCTAssertEqual(mark.excludedSubranges?.count, 1)
        let range = mark.excludedSubranges!.first!.absRange
        XCTAssertEqual(range.start.x, Int32(rightPromptColumn))
        XCTAssertEqual(range.end.x, Int32(rightPromptColumn + rightPrompt.count))
    }

    /// Full p10k cycle: the right prompt is subtracted from the command.
    func test_p10k_fullCycle_recordsCommandWithoutRightPrompt() {
        let harness = makeHarness()

        harness.send(p10kPaint(buffer: "echo hi"))
        harness.send(Array("\r\n".utf8))
        harness.send(osc133("C"))
        harness.send(Array("hi\r\n".utf8))
        harness.send(osc133("D;0"))
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertEqual(mark.fullCommand, "echo hi")
        XCTAssertEqual(mark.firstLineOfCommand, "echo hi")
        XCTAssertEqual(mark.code, 0)
    }

    // MARK: - P;k=i (Ghostty and WezTerm bash/zsh)

    /// Ghostty's and WezTerm's bash integrations send A once, then wrap PS1 in
    /// P;k=i … B so that a prompt redraw doesn't trigger A's fresh-line. That
    /// must produce one prompt mark and a command start after the prompt.
    func test_PkEqualsI_afterA_isOnePromptWithCommandStart() {
        let harness = makeHarness()

        var bytes = osc133("A;cl=line;aid=123")
        bytes += osc133("P;k=i")
        bytes += Array("$ ".utf8)
        bytes += osc133("B")
        harness.send(bytes)
        harness.sync()

        XCTAssertEqual(promptMarks(in: harness).count, 1)
        let start = commandStartCoord(in: harness)
        XCTAssertEqual(start.x, 2)
        XCTAssertEqual(start.y, 0)
    }

    /// A P;k=i that arrives mid-line must not insert a newline (that is the
    /// difference between P and A).
    func test_PkEqualsI_midLine_doesNotFreshLine() {
        let harness = makeHarness()

        var bytes = Array("partial".utf8)
        bytes += osc133("P;k=i")
        bytes += Array("$ ".utf8)
        bytes += osc133("B")
        harness.send(bytes)
        harness.sync()

        let start = commandStartCoord(in: harness)
        XCTAssertEqual(start.y, 0, "P must not move to a fresh line")
        XCTAssertEqual(start.x, Int32("partial$ ".count))
    }

    // MARK: - Byte builders

    /// OSC 133 terminated with ST, as reedline sends it.
    private func osc133(_ body: String) -> [UInt8] {
        return Array("\u{1B}]133;\(body)\u{1B}\\".utf8)
    }

    private func csi(_ body: String) -> [UInt8] {
        return Array("\u{1B}[\(body)".utf8)
    }

    /// One reedline paint of the primary prompt on row 0, as captured from
    /// nushell 0.116.1 (colors removed): hide the cursor, home to the prompt
    /// row, erase below, A, left prompt, then the right prompt inside a cursor
    /// save/restore, then B and the buffer.
    private func reedlinePaint(buffer: String) -> [UInt8] {
        var bytes = csi("?25l")
        bytes += csi("1;1H")
        bytes += csi("J")
        bytes += osc133("A;k=i;click_events=1")
        bytes += Array(leftPrompt.utf8)
        bytes += Array("\u{1B}7".utf8)
        bytes += csi("1;\(rightPromptColumn + 1)H")
        bytes += osc133("P;k=r")
        bytes += Array(rightPrompt.utf8)
        bytes += Array("\u{1B}8".utf8)
        bytes += osc133("B")
        bytes += Array(buffer.utf8)
        bytes += csi("?25h")
        return bytes
    }

    /// reedline's final paint on Return followed by the newline and C.
    /// nushell's default transient right prompt drops the right prompt here.
    private func reedlineSubmit(buffer: String, keepRightPrompt: Bool) -> [UInt8] {
        var bytes: [UInt8]
        if keepRightPrompt {
            bytes = reedlinePaint(buffer: buffer)
        } else {
            bytes = csi("?25l")
            bytes += csi("1;1H")
            bytes += csi("J")
            bytes += osc133("A;k=i;click_events=1")
            bytes += Array(leftPrompt.utf8)
            bytes += osc133("B")
            bytes += Array(buffer.utf8)
            bytes += csi("?25h")
        }
        bytes += csi("J")
        bytes += Array("\r\n".utf8)
        bytes += osc133("C")
        return bytes
    }

    /// powerlevel10k's order: PS1 is wrapped in A … B, and RPROMPT in
    /// P;k=r … B. zsh draws the left prompt and the buffer, then moves right
    /// to draw RPROMPT, then moves the cursor back to the end of the buffer.
    private func p10kPaint(buffer: String) -> [UInt8] {
        var bytes = osc133("A")
        bytes += Array("$ ".utf8)
        bytes += osc133("B")
        bytes += Array(buffer.utf8)
        bytes += csi("1;\(rightPromptColumn + 1)H")
        bytes += osc133("P;k=r")
        bytes += Array(rightPrompt.utf8)
        bytes += osc133("B")
        bytes += csi("1;\(2 + buffer.count + 1)H")
        return bytes
    }

    // MARK: - Helpers

    private func makeHarness() -> TerminalTestHarness {
        return TerminalTestHarness(width: width, height: 24)
    }

    private func commandStartCoord(in harness: TerminalTestHarness) -> VT100GridAbsCoord {
        var coord = VT100GridAbsCoordMake(-1, -1)
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            coord = mutableState.commandStartCoord
        })
        return coord
    }

    private func promptMarks(in harness: TerminalTestHarness) -> [VT100ScreenMark] {
        return harness.allScreenMarks().filter { $0.isPrompt }
    }

    private func onlyPromptMark(in harness: TerminalTestHarness,
                                file: StaticString = #file,
                                line: UInt = #line) -> any VT100ScreenMarkReading {
        let marks = promptMarks(in: harness)
        XCTAssertEqual(marks.count, 1, "Expected exactly one prompt mark", file: file, line: line)
        return marks.first!
    }
}
