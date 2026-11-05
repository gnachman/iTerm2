//
//  PromptRepaintFlickerFixerTests.swift
//  iTerm2
//
//  reedline (nushell) repaints the whole prompt line on every keystroke:
//      ?25l CUP ED A;k=i <left prompt> ESC7 CUP P;k=r <right prompt> ESC8 B <buffer> ?25h
//  all in one write. A sync that lands between the erase and the redrawn
//  buffer draws a line with the command missing, so typing blinks.
//
//  When the cursor is hidden at a prompt and the tokens already queued behind
//  that prove a prompt repaint that shows the cursor again, the flicker fixer
//  (temporary double buffer) keeps drawing the grid as it was before the
//  repaint until the cursor comes back. Nothing else should arm it while
//  Reduce Flicker is off.
//

import XCTest
@testable import iTerm2SharedARC

final class PromptRepaintLookaheadTests: XCTestCase {
    private func repaintShowsCursor(in tokens: [VT100Token]) -> Bool {
        return PromptRepaintLookahead.repaintShowsCursor { body in
            for token in tokens where !body(token) {
                return
            }
        }
    }

    func test_reedlinePaint_isProven() {
        XCTAssertTrue(repaintShowsCursor(
            in: parse(hide() + osc133("A;k=i;click_events=1") + text("~> ") + osc133("B") + text("ls") + show())))
    }

    /// The hide being executed is still at the head of the queue when the lookahead runs.
    func test_leadingHide_isIgnored() {
        XCTAssertTrue(repaintShowsCursor(
            in: parse(hide() + csi("J") + osc133("A") + text("> ") + show())))
    }

    func test_combinedModes_showCursor() {
        XCTAssertTrue(repaintShowsCursor(
            in: parse(osc133("A") + text("> ") + csi("?2004;25h"))))
    }

    func test_noPromptStart_isNotProven() {
        // A full-screen app hiding the cursor while it draws.
        XCTAssertFalse(repaintShowsCursor(
            in: parse(hide() + csi("H") + csi("2J") + text("hello") + show())))
    }

    func test_noShow_isNotProven() {
        // The rest of the repaint hasn't arrived yet.
        XCTAssertFalse(repaintShowsCursor(
            in: parse(hide() + osc133("A") + text("> ") + osc133("B"))))
    }

    func test_showBeforePromptStart_isNotProven() {
        XCTAssertFalse(repaintShowsCursor(
            in: parse(hide() + show() + osc133("A") + text("> ") + show())))
    }

    func test_hideAgainAfterPromptStart_isNotProven() {
        XCTAssertFalse(repaintShowsCursor(
            in: parse(osc133("A") + text("> ") + hide() + show())))
    }

    /// Pressing Enter runs the command and draws the next prompt. That isn't a repaint of the
    /// command line, even when it all arrives in one read.
    func test_commandExecuted_isNotProven() {
        XCTAssertFalse(repaintShowsCursor(
            in: parse(hide() + osc133("C") + text("output\r\n") + osc133("D;0") +
                      osc133("A") + text("> ") + osc133("B") + show())))
    }

    func test_commandFinished_isNotProven() {
        XCTAssertFalse(repaintShowsCursor(
            in: parse(hide() + osc133("D;0") + osc133("A") + text("> ") + osc133("B") + show())))
    }

    func test_otherFinalTermCommands_areNotPromptStarts() {
        XCTAssertFalse(repaintShowsCursor(
            in: parse(osc133("B") + osc133("P;k=r") + osc133("D;0") + show())))
    }
}

final class TokenQueueLookaheadTests: XCTestCase {
    private func tokenArray(_ bytes: [UInt8]) -> TokenArray {
        var vector = CVector()
        CVectorCreate(&vector, 16)
        for token in parse(bytes) {
            CVectorAppendVT100Token(&vector, token)
        }
        return TokenArray(vector, lengthTotal: bytes.count, lengthExcludingInBandSignaling: bytes.count, budget: nil)
    }

    private func queuedStrings(_ queue: TwoTierTokenQueue, limit: Int = 100) -> [String] {
        var result = [String]()
        queue.enumerateQueuedTokens(limit: limit) { token in
            result.append(token.string ?? "\(token.type.rawValue)")
            return true
        }
        return result
    }

    func test_skipsConsumedTokensAndSpansArrays() {
        let queue = TwoTierTokenQueue()
        let first = tokenArray(osc133("A") + osc133("B"))
        _ = first.consume()
        queue.addTokens(first, highPriority: false)
        queue.addTokens(tokenArray(osc133("C")), highPriority: false)

        XCTAssertEqual(queuedStrings(queue), ["B", "C"])
    }

    func test_ignoresHighPriorityTokens() {
        let queue = TwoTierTokenQueue()
        queue.addTokens(tokenArray(osc133("A")), highPriority: true)
        queue.addTokens(tokenArray(osc133("B")), highPriority: false)

        XCTAssertEqual(queuedStrings(queue), ["B"])
    }

    func test_stopsAtLimit() {
        let queue = TwoTierTokenQueue()
        queue.addTokens(tokenArray(osc133("A") + osc133("B")), highPriority: false)
        queue.addTokens(tokenArray(osc133("C")), highPriority: false)

        XCTAssertEqual(queuedStrings(queue, limit: 2), ["A", "B"])
    }

    func test_stopsWhenBodyReturnsFalse() {
        let queue = TwoTierTokenQueue()
        queue.addTokens(tokenArray(osc133("A") + osc133("B") + osc133("C")), highPriority: false)
        var seen = [String]()
        queue.enumerateQueuedTokens(limit: 100) { token in
            seen.append(token.string ?? "")
            return token.string != "B"
        }
        XCTAssertEqual(seen, ["A", "B"])
    }
}

final class PromptRepaintFlickerFixerTests: XCTestCase {
    private let width = 80
    private let height = 24
    private let promptRow = 1
    private let leftPrompt = "/tmp> "

    override func setUp() {
        super.setUp()
        pinAdvancedSetting("HoldScreenDuringPromptRepaint", to: true)
    }

    /// The keystroke that turns "ec" into "ech" hides the cursor while the rest of
    /// the repaint waits in the queue. The flicker fixer should hold the line as it
    /// was, and let go once the cursor is shown again.
    func test_reedlineRepaint_holdsPreRepaintGridUntilCursorShown() {
        let harness = makeEditingHarness(buffer: "ec")

        var armed = false
        var expirationPending = false
        var savedPromptLine: String?
        harness.screen.performBlock(joinedThreads: { terminal, mutableState, _ in
            self.queue(self.reedlinePaint(buffer: "ech"), in: mutableState)
            self.execute(hide(), on: terminal!)
            let buffer = mutableState.temporaryDoubleBuffer
            armed = buffer?.promptRepaint == true
            expirationPending = mutableState.unconditionalTemporaryDoubleBuffer.expirationPendingForTesting
            savedPromptLine = buffer?.savedState?.grid.compactLineDump()
                .components(separatedBy: "\n")[self.promptRow]
        })
        XCTAssertTrue(armed, "Hiding the cursor before a proven prompt repaint should arm the flicker fixer")
        XCTAssertTrue(expirationPending, "The saved grid should still expire if the cursor is never shown")
        XCTAssertTrue(savedPromptLine?.hasPrefix(leftPrompt + "ec") ?? false,
                      "The saved grid should hold the line from before the repaint, got \(savedPromptLine ?? "nil")")

        harness.sync()

        var savedStateAfterShow: PTYTextViewSynchronousUpdateState?
        var expirationPendingAfterShow = true
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            let buffer = mutableState.unconditionalTemporaryDoubleBuffer
            savedStateAfterShow = buffer.savedState
            expirationPendingAfterShow = buffer.expirationPendingForTesting
        })
        XCTAssertNil(savedStateAfterShow, "Showing the cursor should end the repaint")
        XCTAssertFalse(expirationPendingAfterShow, "Showing the cursor, not the timer, should end the repaint")
    }

    func test_settingOff_doesNotArm() {
        let harness = makeEditingHarness(buffer: "ec")
        withAdvancedSetting("HoldScreenDuringPromptRepaint", false) {
            XCTAssertFalse(armsWhenHiding(harness, queued: reedlinePaint(buffer: "ech")))
        }
    }

    func test_commandSubmitted_doesNotArm() {
        let harness = makeEditingHarness(buffer: "echo")
        let bytes = hide() + text("\r\n") + osc133("C") + text("hi\r\n") + osc133("D;0") +
            osc133("A;k=i") + text(leftPrompt) + osc133("B") + show()
        XCTAssertFalse(armsWhenHiding(harness, queued: bytes))
    }

    func test_notEditingAtPrompt_doesNotArm() {
        let harness = makeHarness()
        XCTAssertFalse(armsWhenHiding(harness, queued: reedlinePaint(buffer: "")))
    }

    func test_cursorShowNotQueued_doesNotArm() {
        let harness = makeEditingHarness(buffer: "ec")
        var paint = reedlinePaint(buffer: "ech")
        paint.removeLast(show().count)
        XCTAssertFalse(armsWhenHiding(harness, queued: paint))
    }

    func test_fullScreenRedraw_doesNotArm() {
        let harness = makeEditingHarness(buffer: "ec")
        XCTAssertFalse(armsWhenHiding(harness, queued: hide() + csi("H") + csi("2J") + text("top") + show()))
    }

    // MARK: - Helpers

    private func armsWhenHiding(_ harness: TerminalTestHarness, queued bytes: [UInt8]) -> Bool {
        var armed = false
        harness.screen.performBlock(joinedThreads: { terminal, mutableState, _ in
            self.queue(bytes, in: mutableState)
            self.execute(hide(), on: terminal!)
            armed = mutableState.unconditionalTemporaryDoubleBuffer.savedState != nil
        })
        harness.sync()
        return armed
    }

    /// Adds bytes to the token executor's queue as a pty read would. Called while
    /// joined, so they wait there until the join ends.
    private func queue(_ bytes: [UInt8], in mutableState: VT100ScreenMutableState) {
        var copy = bytes.map { CChar(bitPattern: $0) }
        copy.withUnsafeMutableBufferPointer { buffer in
            mutableState.threadedReadTask(buffer.baseAddress!, length: Int32(buffer.count))
        }
    }

    private func execute(_ bytes: [UInt8], on terminal: VT100Terminal) {
        for token in parse(bytes) {
            terminal.execute(token)
        }
    }

    private func makeHarness() -> TerminalTestHarness {
        let harness = TerminalTestHarness(width: width, height: height)
        // The saved grid's timer must not expire it behind the test's back, which would make the
        // tests that check that the hold ends pass for the wrong reason.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.unconditionalTemporaryDoubleBuffer.manualExpirationForTesting = true
        })
        harness.feedEscapeSequence(text("Last login: Mon Oct 12 10:06:41 on ttys001\r\n"))
        harness.sync()
        return harness
    }

    /// A harness whose shell has painted its prompt with `buffer` typed after it.
    private func makeEditingHarness(buffer: String) -> TerminalTestHarness {
        let harness = makeHarness()
        harness.feedEscapeSequence(reedlinePaint(buffer: buffer))
        harness.sync()
        return harness
    }

    private func reedlinePaint(buffer: String) -> [UInt8] {
        let rightPrompt = " 10/12/2026 10:12:24 AM"
        var bytes = hide()
        bytes += moveToPromptRow(column: 0)
        bytes += csi("J")
        bytes += osc133("A;k=i;click_events=1")
        bytes += text(leftPrompt)
        bytes += text("\u{1B}7")
        bytes += moveToPromptRow(column: width - rightPrompt.count)
        bytes += osc133("P;k=r")
        bytes += text(rightPrompt)
        bytes += text("\u{1B}8")
        bytes += osc133("B")
        bytes += text(buffer)
        bytes += show()
        return bytes
    }

    private func moveToPromptRow(column: Int) -> [UInt8] {
        return csi("\(promptRow + 1);\(column + 1)H")
    }
}

// MARK: - Byte helpers

private func text(_ string: String) -> [UInt8] {
    return Array(string.utf8)
}

private func csi(_ body: String) -> [UInt8] {
    return text("\u{1B}[\(body)")
}

private func osc133(_ body: String) -> [UInt8] {
    return text("\u{1B}]133;\(body)\u{1B}\\")
}

private func hide() -> [UInt8] {
    return csi("?25l")
}

private func show() -> [UInt8] {
    return csi("?25h")
}

private func parse(_ bytes: [UInt8]) -> [VT100Token] {
    let parser = VT100Parser()
    parser.encoding = String.Encoding.utf8.rawValue
    bytes.withUnsafeBufferPointer { buffer in
        parser.putStreamData(buffer.baseAddress, length: Int32(buffer.count))
    }
    var vector = CVector()
    CVectorCreate(&vector, 100)
    _ = parser.addParsedTokens(to: &vector)
    var result = [VT100Token]()
    for i in 0..<CVectorCount(&vector) {
        result.append(CVectorGetObject(&vector, i) as! VT100Token)
    }
    CVectorReleaseObjectsAndDestroy(vector)
    return result
}
