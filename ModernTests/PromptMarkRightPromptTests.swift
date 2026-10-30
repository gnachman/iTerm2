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
//  exercised. They use feedEscapeSequence, which parses and executes on the
//  joined thread, so assertions never race the mutation thread. The prompt is
//  drawn on the second row, below a "Last login" line, as in a new session,
//  except in the bottom-row tests, where an idle prompt usually sits.
//

import XCTest
@testable import iTerm2SharedARC

final class PromptMarkRightPromptTests: XCTestCase {
    private let width = 80
    private let leftPrompt = "/tmp> "
    private let rightPrompt = " 10/12/2026 10:12:24 AM"

    private let height = 24

    /// Zero-based row the prompt is drawn on. Bottom-row tests change it
    /// before calling makeHarness().
    private var promptRow = 1

    /// reedline right-aligns the right prompt so it ends exactly at the margin
    /// (start_col = screen width - prompt width).
    private var reedlineRightPromptColumn: Int {
        return width - rightPrompt.count
    }

    /// zsh leaves ZLE_RPROMPT_INDENT columns (1 by default) after RPROMPT.
    private func zshRightPromptColumn(indent: Int) -> Int {
        return width - rightPrompt.count - indent
    }

    // MARK: - reedline: right prompt nested before the single B

    /// At an idle prompt, the B that follows the nested right prompt must
    /// start the command. Without that, iTerm2 believes the shell is not at a
    /// prompt (isAtShellPrompt is false): Select Output of Last Command takes
    /// in the next prompt and Auto Composer never engages.
    func test_reedline_idlePrompt_BAfterNestedRightPrompt_startsCommand() {
        let harness = makeHarness()

        harness.feedEscapeSequence(reedlinePaint(buffer: ""))
        harness.sync()

        let start = commandStartCoord(in: harness)
        XCTAssertEqual(start.x, Int32(leftPrompt.count),
                       "The command should start right after the left prompt, "
                       + "where the cursor was restored before B")
        XCTAssertEqual(start.y, Int64(promptRow))
        XCTAssertGreaterThanOrEqual(harness.screen.commandRange().start.x, 0,
                                    "commandRange (isAtShellPrompt) must be valid at the idle prompt")
    }

    /// reedline repaints the whole prompt, right prompt included, on every
    /// keystroke. The command start must stay put and there must still be a
    /// single prompt mark.
    func test_reedline_keystrokeRepaints_keepCommandStartAndOneMark() {
        let harness = makeHarness()

        for buffer in ["", "e", "ec", "ech", "echo"] {
            harness.feedEscapeSequence(reedlinePaint(buffer: buffer))
        }
        harness.sync()

        XCTAssertEqual(promptMarks(in: harness).count, 1)
        let start = commandStartCoord(in: harness)
        XCTAssertEqual(start.x, Int32(leftPrompt.count))
        XCTAssertEqual(start.y, Int64(promptRow))
    }

    /// The right prompt is drawn after ESC7 and the cursor is restored with
    /// ESC8 before B, so the cursor at B is to the left of where P;k=r was
    /// seen. The excluded subrange must still cover the right prompt's cells
    /// rather than run backwards from the P column to the B column. The right
    /// prompt ends exactly at the margin, so the end must also be valid there.
    func test_reedline_rightPromptExcludedSubrange_coversRightPromptCells() {
        let harness = makeHarness()

        harness.feedEscapeSequence(reedlinePaint(buffer: ""))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        guard let ranges = mark.excludedSubranges, ranges.count == 1 else {
            XCTFail("Expected one excluded subrange for the right prompt, got "
                    + "\(mark.excludedSubranges?.count ?? 0)")
            return
        }
        let range = ranges[0].absRange
        XCTAssertEqual(range.start.y, Int64(promptRow))
        XCTAssertEqual(range.start.x, Int32(reedlineRightPromptColumn),
                       "The exclusion starts where P;k=r was received")
        XCTAssertGreaterThanOrEqual(linearPosition(range.end),
                                    linearPosition(VT100GridAbsCoordMake(Int32(width),
                                                                         Int64(promptRow))),
                                    "The exclusion must reach the end of the right prompt at the "
                                    + "margin, not stop at the restored cursor before it")
    }

    /// Each repaint draws the right prompt again. The exclusions from earlier
    /// repaints describe cells that were just erased and redrawn, so they must
    /// not pile up on the mark.
    func test_reedline_keystrokeRepaints_doNotAccumulateRightPromptExclusions() {
        let harness = makeHarness()

        for buffer in ["", "e", "ec", "ech", "echo"] {
            harness.feedEscapeSequence(reedlinePaint(buffer: buffer))
        }
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.excludedSubranges?.count, 1,
                       "Only the most recent paint's right prompt should be excluded")
    }

    /// Full cycle as nushell 0.116 sends it: the right prompt is drawn while
    /// typing and dropped from the final repaint on Return (transient right
    /// prompt). The command and exit code are recorded.
    func test_reedline_fullCycle_transientRightPrompt_recordsCommand() {
        let harness = makeHarness()

        for buffer in ["", "e", "echo", "echo hi"] {
            harness.feedEscapeSequence(reedlinePaint(buffer: buffer))
        }
        harness.feedEscapeSequence(reedlineSubmit(buffer: "echo hi", keepRightPrompt: false))
        harness.feedEscapeSequence(Array("hi\r\n".utf8))
        harness.feedEscapeSequence(osc133("D;0"))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.fullCommand, "echo hi")
        XCTAssertEqual(mark.firstLineOfCommand, "echo hi")
        XCTAssertTrue(mark.hasCode)
        XCTAssertEqual(mark.code, 0)
    }

    /// Full cycle when the right prompt stays on screen after Return (no
    /// transient right prompt). The only B before C follows the nested right
    /// prompt, so the command is recorded only if that B starts it, and the
    /// right prompt text must not leak into the recorded command.
    func test_reedline_fullCycle_rightPromptKeptOnSubmit_recordsCommandWithoutRightPrompt() {
        let harness = makeHarness()

        harness.feedEscapeSequence(reedlinePaint(buffer: ""))
        harness.feedEscapeSequence(reedlineSubmit(buffer: "echo hi", keepRightPrompt: true))
        harness.feedEscapeSequence(Array("hi\r\n".utf8))
        harness.feedEscapeSequence(osc133("D;1"))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.fullCommand, "echo hi",
                       "The right prompt's cells must be subtracted from the command")
        XCTAssertEqual(mark.firstLineOfCommand, "echo hi")
        XCTAssertTrue(mark.hasCode)
        XCTAssertEqual(mark.code, 1)
    }

    /// Pressing Return on an empty line must not record a command, even though
    /// the B before C now starts one.
    func test_reedline_emptySubmit_recordsNoCommand() {
        let harness = makeHarness()

        harness.feedEscapeSequence(reedlinePaint(buffer: ""))
        harness.feedEscapeSequence(reedlineSubmit(buffer: "", keepRightPrompt: true))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertNil(mark.fullCommand)
        XCTAssertNil(mark.firstLineOfCommand)
    }

    /// While typing a multi-line command, reedline draws a "::: " indicator
    /// between A;k=s and B on each continuation line. The final repaint on
    /// Return draws those lines without it. Exclusions from the typing repaints
    /// must not survive, or the first four characters of each continuation line
    /// are cut from the recorded command.
    func test_reedline_multiLine_continuationIndicatorDroppedOnSubmit_keepsFullCommand() {
        let harness = makeHarness()
        let lines = ["let y = [", "\"AAAAAAA\" \"BBBBBBB\"", "] | length"]

        harness.feedEscapeSequence(reedlinePaint(buffer: ""))
        for count in 1...lines.count {
            harness.feedEscapeSequence(reedlineMultiLinePaint(lines: Array(lines.prefix(count)),
                                                continuationIndicator: "::: "))
        }
        var submit = reedlineMultiLinePaint(lines: lines, continuationIndicator: "")
        submit += csi("J")
        submit += Array("\r\n".utf8)
        submit += osc133("C")
        harness.feedEscapeSequence(submit)
        harness.feedEscapeSequence(Array("2\r\n".utf8))
        harness.feedEscapeSequence(osc133("D;0"))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.fullCommand, lines.joined(separator: "\n"))
        XCTAssertEqual(mark.firstLineOfCommand, lines[0])
    }

    // MARK: - Prompt on the bottom row

    /// An idle prompt usually sits on the last row. reedline's right prompt
    /// ends at the margin there too, and its exclusion must not depend on a
    /// row below the prompt existing, or Select Current Command picks up the
    /// right prompt.
    func test_reedline_bottomRow_rightPromptExcludedFromCurrentCommand() {
        promptRow = height - 1
        let harness = makeHarness()

        harness.feedEscapeSequence(reedlinePaint(buffer: "echo hi"))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        guard let range = mark.excludedSubranges?.first else {
            XCTFail("Expected an excluded subrange for the right prompt")
            return
        }
        XCTAssertEqual(range.start.status, .valid)
        XCTAssertEqual(range.end.status, .valid,
                       "An end at the margin of the last row must be valid")
        XCTAssertEqual(currentCommandText(in: harness, mark: mark), "echo hi")
    }

    /// Same for p10k with ZLE_RPROMPT_INDENT=0 on the last row.
    func test_p10k_bottomRow_rightPromptAtMargin_excludedFromCurrentCommand() {
        promptRow = height - 1
        let harness = makeHarness()

        harness.feedEscapeSequence(p10kPaint(buffer: "echo hi",
                                             rightPromptColumn: zshRightPromptColumn(indent: 0)))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        guard let range = mark.excludedSubranges?.first else {
            XCTFail("Expected an excluded subrange for the right prompt")
            return
        }
        XCTAssertEqual(range.end.status, .valid,
                       "An end at the margin of the last row must be valid")
        XCTAssertEqual(currentCommandText(in: harness, mark: mark), "echo hi")
    }

    // MARK: - powerlevel10k: right prompt bracketed separately after B

    /// p10k sends the primary B before its right prompt, then a second B after
    /// the right prompt. That second B must only close the right prompt: the
    /// command start stays after the left prompt instead of moving to where the
    /// right prompt ended.
    func test_p10k_secondBAfterRightPrompt_doesNotMoveCommandStart() {
        let harness = makeHarness()
        let column = zshRightPromptColumn(indent: 1)

        harness.feedEscapeSequence(p10kPaint(buffer: "echo hi", rightPromptColumn: column))
        harness.sync()

        let start = commandStartCoord(in: harness)
        XCTAssertEqual(start.x, 2, "Command starts after \"$ \"")
        XCTAssertEqual(start.y, Int64(promptRow))

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.excludedSubranges?.count, 1)
        guard let range = mark.excludedSubranges?.first?.absRange else {
            return
        }
        XCTAssertEqual(range.start.x, Int32(column))
        XCTAssertEqual(range.end.x, Int32(column + rightPrompt.count))
        XCTAssertEqual(range.end.y, Int64(promptRow))
    }

    /// Full p10k cycle with zsh's default ZLE_RPROMPT_INDENT=1: the right
    /// prompt is subtracted from the command.
    func test_p10k_fullCycle_recordsCommandWithoutRightPrompt() {
        let harness = makeHarness()

        harness.feedEscapeSequence(p10kCycle(buffer: "echo hi", rightPromptColumn: zshRightPromptColumn(indent: 1)))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.fullCommand, "echo hi")
        XCTAssertEqual(mark.firstLineOfCommand, "echo hi")
        XCTAssertEqual(mark.code, 0)
    }

    /// p10k recommends ZLE_RPROMPT_INDENT=0, which puts the right prompt's last
    /// cell in the last column. The B that closes it then arrives with the
    /// cursor at the margin (x == width). The exclusion must survive that and
    /// still subtract the right prompt from the command.
    func test_p10k_fullCycle_rightPromptAtMargin_recordsCommandWithoutRightPrompt() {
        let harness = makeHarness()

        harness.feedEscapeSequence(p10kCycle(buffer: "echo hi", rightPromptColumn: zshRightPromptColumn(indent: 0)))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.fullCommand, "echo hi")
        XCTAssertEqual(mark.firstLineOfCommand, "echo hi")
    }

    // MARK: - Right prompt hidden or redrawn while typing

    /// zsh erases RPROMPT (EL) once the typed text reaches it and draws the
    /// command over those cells. The right prompt's exclusion no longer
    /// describes what is on screen, so it must not cut characters out of the
    /// command. Modeled on a capture of zsh with powerlevel10k’s markers.
    func test_p10k_rightPromptHiddenByLongCommand_recordsWholeCommand() {
        let harness = makeHarness()
        let column = zshRightPromptColumn(indent: 1)
        let command = "echo " + String(repeating: "x", count: 70)

        var bytes = p10kPaint(buffer: "", rightPromptColumn: column)
        bytes += hideRightPromptWhileTyping(command, rightPromptColumn: column)
        bytes += Array("\r\n".utf8)
        bytes += osc133("C")
        bytes += Array("ok\r\n".utf8)
        bytes += osc133("D;0")
        harness.feedEscapeSequence(bytes)
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.fullCommand, command)
        XCTAssertEqual(mark.excludedSubranges?.count ?? 0, 0,
                       "The hidden right prompt's exclusion is stale")
    }

    /// fish redraws its right prompt after every keystroke. With the right
    /// prompt marked, each redraw closes another P;k=r over the same cells.
    /// Only one exclusion should remain for them.
    func test_fish_rightPromptRedrawnEachKeystroke_keepsOneExclusion() {
        let harness = makeHarness()
        let column = zshRightPromptColumn(indent: 1)

        harness.feedEscapeSequence(fishTyping("echo hi", rightPromptColumn: column))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.excludedSubranges?.count, 1)
        XCTAssertEqual(currentCommandText(in: harness, mark: mark), "echo hi")
    }

    /// The fish redraw, then Return: the visible right prompt is still
    /// subtracted, with a single exclusion.
    func test_fish_rightPromptRedrawnEachKeystroke_fullCycle_recordsCommandWithoutRightPrompt() {
        let harness = makeHarness()
        let column = zshRightPromptColumn(indent: 1)

        var bytes = fishTyping("echo hi", rightPromptColumn: column)
        bytes += Array("\r\n".utf8)
        bytes += osc133("C")
        bytes += Array("hi\r\n".utf8)
        bytes += osc133("D;0")
        harness.feedEscapeSequence(bytes)
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.fullCommand, "echo hi")
        XCTAssertEqual(mark.excludedSubranges?.count, 1)
    }

    /// fish redraws the right prompt on each keystroke until the typed text
    /// reaches it, then erases it (EL) and keeps typing over its cells.
    func test_fish_rightPromptHiddenByLongCommand_recordsWholeCommand() {
        let harness = makeHarness()
        let column = zshRightPromptColumn(indent: 1)
        let command = "echo " + String(repeating: "x", count: 70)
        let visiblePart = String(command.prefix(column - 2))

        var bytes = fishTyping(visiblePart, rightPromptColumn: column)
        bytes += hideRightPromptWhileTyping(command,
                                            rightPromptColumn: column,
                                            alreadyTyped: visiblePart.count)
        bytes += Array("\r\n".utf8)
        bytes += osc133("C")
        bytes += Array("ok\r\n".utf8)
        bytes += osc133("D;0")
        harness.feedEscapeSequence(bytes)
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.fullCommand, command)
        XCTAssertEqual(mark.excludedSubranges?.count ?? 0, 0)
    }

    /// zsh with TRANSIENT_RPROMPT erases the marked right prompt before the
    /// newline. The command is unaffected, and the exclusion over the erased
    /// cells is dropped.
    func test_p10k_transientRightPrompt_dropsExclusion() {
        let harness = makeHarness()
        let column = zshRightPromptColumn(indent: 1)

        var bytes = p10kPaint(buffer: "echo hi", rightPromptColumn: column)
        bytes += csi("K")
        bytes += Array("\r\n".utf8)
        bytes += osc133("C")
        bytes += Array("hi\r\n".utf8)
        bytes += osc133("D;0")
        harness.feedEscapeSequence(bytes)
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.fullCommand, "echo hi")
        XCTAssertEqual(mark.excludedSubranges?.count ?? 0, 0)
    }

    // MARK: - zsh RPROMPT without P;k=r (iTerm2's own zsh integration)

    /// iTerm2's zsh integration doesn't mark RPROMPT, so there is no excluded
    /// subrange. zsh leaves RPROMPT on screen after Return (unless
    /// TRANSIENT_RPROMPT is set) and C arrives from preexec after the newline,
    /// so the command range covers the whole line. The blank cells between the
    /// typed text and RPROMPT must end the command, as they did before
    /// excludedSubranges was introduced. Otherwise the right prompt is recorded
    /// in the mark and in command history. Issue 13168.
    func test_zsh_unmarkedRightPrompt_isNotRecordedInCommand() {
        let harness = makeHarness()

        harness.feedEscapeSequence(zshUnmarkedRightPromptCycle(buffer: "echo hi",
                                                               rightPromptColumn: zshRightPromptColumn(indent: 1)))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertNil(mark.excludedSubranges, "Precondition: nothing marks the right prompt")
        XCTAssertEqual(mark.fullCommand, "echo hi")
        XCTAssertEqual(mark.firstLineOfCommand, "echo hi")
    }

    /// Same, with the multi-word command from the report.
    func test_zsh_unmarkedRightPrompt_longCommand_isNotRecordedInCommand() {
        let harness = makeHarness()
        let command = "aws sso login --profile=athena-dev"

        harness.feedEscapeSequence(zshUnmarkedRightPromptCycle(buffer: command,
                                                               rightPromptColumn: zshRightPromptColumn(indent: 1)))
        harness.sync()

        guard let mark = onlyPromptMark(in: harness) else {
            return
        }
        XCTAssertEqual(mark.fullCommand, command)
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
        harness.feedEscapeSequence(bytes)
        harness.sync()

        XCTAssertEqual(promptMarks(in: harness).count, 1)
        let start = commandStartCoord(in: harness)
        XCTAssertEqual(start.x, 2)
        XCTAssertEqual(start.y, Int64(promptRow))
    }

    /// A P;k=i that arrives mid-line must not insert a newline (that is the
    /// difference between P and A).
    func test_PkEqualsI_midLine_doesNotFreshLine() {
        let harness = makeHarness()

        var bytes = Array("partial".utf8)
        bytes += osc133("P;k=i")
        bytes += Array("$ ".utf8)
        bytes += osc133("B")
        harness.feedEscapeSequence(bytes)
        harness.sync()

        let start = commandStartCoord(in: harness)
        XCTAssertEqual(start.y, Int64(promptRow), "P must not move to a fresh line")
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

    /// CUP to a zero-based column on the prompt row.
    private func moveToPromptRow(column: Int) -> [UInt8] {
        return csi("\(promptRow + 1);\(column + 1)H")
    }

    /// One reedline paint of the primary prompt, as captured from nushell
    /// 0.116.1 (colors removed): hide the cursor, move to the prompt row, erase
    /// below, A, left prompt, then the right prompt inside a cursor
    /// save/restore, then B and the buffer.
    private func reedlinePaint(buffer: String) -> [UInt8] {
        var bytes = csi("?25l")
        bytes += moveToPromptRow(column: 0)
        bytes += csi("J")
        bytes += osc133("A;k=i;click_events=1")
        bytes += Array(leftPrompt.utf8)
        bytes += Array("\u{1B}7".utf8)
        bytes += moveToPromptRow(column: reedlineRightPromptColumn)
        bytes += osc133("P;k=r")
        bytes += Array(rightPrompt.utf8)
        bytes += Array("\u{1B}8".utf8)
        bytes += osc133("B")
        bytes += Array(buffer.utf8)
        bytes += csi("?25h")
        return bytes
    }

    /// A reedline paint of a multi-line buffer, as captured from nushell
    /// 0.116.1: the first line follows the primary prompt, and each later line
    /// is bracketed by A;k=s and B around the continuation indicator. The right
    /// prompt is left out for brevity.
    private func reedlineMultiLinePaint(lines: [String], continuationIndicator: String) -> [UInt8] {
        var bytes = csi("?25l")
        bytes += moveToPromptRow(column: 0)
        bytes += csi("J")
        bytes += osc133("A;k=i;click_events=1")
        bytes += Array(leftPrompt.utf8)
        bytes += osc133("B")
        for (i, line) in lines.enumerated() {
            if i > 0 {
                bytes += Array("\r\n".utf8)
                bytes += osc133("A;k=s;click_events=1")
                bytes += Array(continuationIndicator.utf8)
                bytes += osc133("B")
            }
            bytes += Array(line.utf8)
        }
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
            bytes += moveToPromptRow(column: 0)
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
    private func p10kPaint(buffer: String, rightPromptColumn: Int) -> [UInt8] {
        var bytes = osc133("A")
        bytes += Array("$ ".utf8)
        bytes += osc133("B")
        bytes += Array(buffer.utf8)
        bytes += moveToPromptRow(column: rightPromptColumn)
        bytes += osc133("P;k=r")
        bytes += Array(rightPrompt.utf8)
        bytes += osc133("B")
        bytes += moveToPromptRow(column: 2 + buffer.count)
        return bytes
    }

    /// A p10k paint followed by Return, C, output, and D;0.
    private func p10kCycle(buffer: String, rightPromptColumn: Int) -> [UInt8] {
        var bytes = p10kPaint(buffer: buffer, rightPromptColumn: rightPromptColumn)
        bytes += Array("\r\n".utf8)
        bytes += osc133("C")
        bytes += Array("hi\r\n".utf8)
        bytes += osc133("D;0")
        return bytes
    }

    /// Typing the rest of `command` after `alreadyTyped` characters, as zsh and
    /// fish do once the text reaches the right prompt: at the right prompt's
    /// column they erase to the end of the line, then keep writing.
    private func hideRightPromptWhileTyping(_ command: String,
                                            rightPromptColumn: Int,
                                            alreadyTyped: Int = 0) -> [UInt8] {
        let promptWidth = 2
        var bytes = moveToPromptRow(column: promptWidth + alreadyTyped)
        for (i, ch) in command.enumerated() where i >= alreadyTyped {
            if promptWidth + i == rightPromptColumn {
                bytes += csi("K")
            }
            bytes += Array(String(ch).utf8)
        }
        return bytes
    }

    /// fish's prompt with a marked right prompt, typing `buffer` one
    /// character at a time. As captured from fish 3.7 through 4.9: after each
    /// character fish returns to column 0, moves right to the right prompt,
    /// draws it, and moves back to the end of the typed text.
    private func fishTyping(_ buffer: String, rightPromptColumn: Int) -> [UInt8] {
        let promptWidth = 2
        var bytes = osc133("A")
        bytes += Array("$ ".utf8)
        bytes += osc133("B")
        var typed = 0
        func drawRightPrompt() {
            bytes += Array("\r".utf8) + csi("\(rightPromptColumn)C")
            bytes += osc133("P;k=r")
            bytes += Array(rightPrompt.utf8)
            bytes += osc133("B")
            bytes += Array("\r".utf8) + csi("\(promptWidth + typed)C")
        }
        drawRightPrompt()
        for ch in buffer {
            bytes += Array(String(ch).utf8)
            typed += 1
            drawRightPrompt()
        }
        return bytes
    }

    /// A full cycle as iTerm2's zsh integration sends it with an RPROMPT set:
    /// PS1 is wrapped in A … B, but RPROMPT is not marked. zsh draws the left
    /// prompt and buffer, moves right to draw RPROMPT, and moves back. On
    /// Return it prints the newline, then preexec sends C.
    private func zshUnmarkedRightPromptCycle(buffer: String, rightPromptColumn: Int) -> [UInt8] {
        var bytes = osc133("A")
        bytes += Array("$ ".utf8)
        bytes += osc133("B")
        bytes += Array(buffer.utf8)
        bytes += moveToPromptRow(column: rightPromptColumn)
        bytes += Array(rightPrompt.utf8)
        bytes += moveToPromptRow(column: 2 + buffer.count)
        bytes += Array("\r\n".utf8)
        bytes += osc133("C")
        bytes += Array("hi\r\n".utf8)
        bytes += osc133("D;0")
        return bytes
    }

    // MARK: - Helpers

    /// A harness whose cursor is at the start of the prompt row, below a
    /// "Last login" line.
    private func makeHarness() -> TerminalTestHarness {
        let harness = TerminalTestHarness(width: width, height: height)
        var preamble = "Last login: Mon Oct 12 10:06:41 on ttys001\r\n"
        for i in 1..<max(promptRow, 1) {
            preamble += "output \(i)\r\n"
        }
        harness.feedEscapeSequence(Array(preamble.utf8))
        harness.sync()
        return harness
    }

    /// The text from the command start to the end of the prompt row with the
    /// mark's exclusions removed, as Select Current Command extracts it.
    private func currentCommandText(in harness: TerminalTestHarness,
                                    mark: any VT100ScreenMarkReading) -> String? {
        let start = commandStartCoord(in: harness)
        let range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(start.x,
                                                                       Int32(start.y),
                                                                       Int32(width),
                                                                       Int32(promptRow)),
                                               0, 0)
        return iTermTextExtractor(dataSource: harness.screen).content(in: range,
                                                                      excludingSubranges: mark.excludedSubranges)
    }

    private func linearPosition(_ coord: VT100GridAbsCoord) -> Int64 {
        return coord.y * Int64(width) + Int64(coord.x)
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
                                line: UInt = #line) -> (any VT100ScreenMarkReading)? {
        let marks = promptMarks(in: harness)
        XCTAssertEqual(marks.count, 1, "Expected exactly one prompt mark", file: file, line: line)
        return marks.first
    }
}
