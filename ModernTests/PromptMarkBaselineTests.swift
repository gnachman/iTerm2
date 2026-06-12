//
//  PromptMarkBaselineTests.swift
//  iTerm2
//
//  Regression coverage for the existing OSC 133 / FinalTerm prompt mark flow.
//  These tests lock in today's behavior before OSC 133 k= (prompt kind) support
//  is added. They drive VT100ScreenMutableState directly via its VT100TerminalDelegate
//  conformance — no real parser, no real shell.
//

import Foundation
import XCTest
@testable import iTerm2SharedARC

final class PromptMarkBaselineTests: XCTestCase {

    // MARK: - Test 12: A B C D;0 lifecycle

    /// A complete prompt → command → output → return-code cycle produces one mark
    /// whose isPrompt is YES, hasCode is YES, and code matches.
    func testSingleCommandLifecycleProducesOneMarkWithReturnCode() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        // A
        harness.sendPromptStart()
        // prompt text
        harness.appendText("$ ")
        // B
        harness.sendCommandStart()
        // typed command
        harness.appendText("echo hi")
        // user presses return
        harness.newline()
        // C (command-read end, output starts)
        harness.sendCommandEnd()
        // output
        harness.appendText("hi")
        harness.newline()
        // D;0
        harness.sendReturnCode(0)
        harness.sync()

        let marks = harness.allScreenMarks()
        XCTAssertEqual(marks.count, 1, "Expected exactly one prompt mark for a single A/B/C/D cycle")

        guard let mark = marks.first else { return }
        XCTAssertTrue(mark.isPrompt, "Mark should be flagged as a prompt mark")
        XCTAssertTrue(mark.hasCode, "Mark should have a return code after D;0")
        XCTAssertEqual(mark.code, 0, "Return code should be 0")
        // Note: endDate is set on this mark only when the *next* prompt-start arrives
        // (assignCurrentCommandEndDate in setPromptStartLine:). A bare D;0 with no
        // following A leaves endDate nil, so we don't assert it here.
    }

    // MARK: - Test 13: two consecutive commands produce two marks

    /// Running two commands in sequence produces two distinct prompt marks. The
    /// previous command's output range is captured before the second prompt is laid down.
    func testTwoConsecutiveCommandsProduceTwoMarks() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        // first cycle
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo one")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("one")
        harness.newline()
        harness.sendReturnCode(0)

        // second cycle
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo two")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("two")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()

        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 2, "Expected two prompt marks for two A/B/C/D cycles")

        // Each mark should have its own return code captured.
        for mark in marks {
            XCTAssertTrue(mark.hasCode, "Each completed command should record its return code")
            XCTAssertEqual(mark.code, 0, "Return code should be 0 for each successful command")
        }
    }

    // MARK: - Test 14: A followed by A (both initial) — second overwrites

    /// Two consecutive prompt-start markers with no B between them (the documented
    /// "k=i overwrite is correct" invariant) result in a single mark, not two. Some
    /// shells/prompts redraw the prompt and this is the safety valve that prevents
    /// duplicate marks from accumulating.
    func testTwoInitialPromptStartsWithoutCommandReuseSingleMark() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        harness.sendPromptStart()
        harness.appendText("$ ")
        // A second prompt-start with no B between is the prompt-redraw case (e.g. powerlevel10k).
        harness.sendPromptStart()
        harness.sync()

        let marks = harness.allScreenMarks()
        XCTAssertEqual(marks.count, 1,
                       "A consecutive prompt-start (with no command begun) must reuse the existing mark, not create a new one")
    }

    // MARK: - Sanity check: parser path produces a mark

    /// Sending a raw `ESC ] 133 ; A BEL` byte stream through threadedReadTask
    /// should produce a prompt mark via VT100Terminal.executeFinalTermToken.
    /// This is the pipeline the live shell harness depends on.
    func testRawByteStreamProducesPromptMark() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        // ESC ] 133 ; A BEL
        let bytes: [CChar] = [0x1B, 0x5D, 0x31, 0x33, 0x33, 0x3B, 0x41, 0x07]
        bytes.withUnsafeBufferPointer { ptr in
            // Cast away const so the (char *) signature is satisfied; the
            // parser only reads.
            let raw = UnsafeMutablePointer(mutating: ptr.baseAddress!)
            harness.screen.threadedReadTask(raw, length: Int32(bytes.count))
        }
        harness.sync()

        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 1, "Synthetic OSC 133;A should produce one prompt mark")
    }

    /// The byte stream that real zsh produces wraps each prompt in CSI/SGR
    /// sequences. Confirm the parser still extracts 133;A from a realistic
    /// preamble.
    func testRealisticZshLikeByteStreamProducesPromptMark() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        // Synthesize a sequence like real zsh: SGR + carriage return + clear-to-end
        // + 133;A + prompt text + 133;B + bracketed-paste-enable.
        let escSeq = "\u{1B}[0m\u{1B}[27m\u{1B}[24m\u{1B}[J" +
                     "\u{1B}]133;A\u{07}" +
                     "MacBook-Pro-2% " +
                     "\u{1B}]133;B\u{07}" +
                     "\u{1B}[K\u{1B}[?2004h"

        let bytes = Array(escSeq.utf8).map { CChar(bitPattern: $0) }
        bytes.withUnsafeBufferPointer { ptr in
            let raw = UnsafeMutablePointer(mutating: ptr.baseAddress!)
            harness.screen.threadedReadTask(raw, length: Int32(bytes.count))
        }
        harness.sync()

        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 1, "Realistic zsh-like preamble should still produce one prompt mark")
    }

    // MARK: - Test 15: trigger-detected prompt sets promptDetectedByTrigger

    /// Triggers that detect prompts via regex create marks with
    /// promptDetectedByTrigger=YES. This baseline confirms the flag is set so that the
    /// upcoming k= work can leave the trigger path alone (always kind=.initial).
    func testTriggerDetectedPromptSetsFlag() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        // Lay down some content so the synthetic trigger has a meaningful y.
        harness.appendText("$ ")

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            let cursorX = mutableState.currentGrid.cursor.x
            let cursorY = mutableState.currentGrid.cursor.y
            let absY = Int64(cursorY) + Int64(mutableState.numberOfScrollbackLines) + mutableState.cumulativeScrollbackOverflow
            _ = mutableState.promptDidStart(at: VT100GridAbsCoordMake(cursorX, absY),
                                            wasInCommand: false,
                                            detectedByTrigger: true,
                                            freshLine: true,
                                            aid: nil)
        })
        harness.sync()

        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 1)
        XCTAssertTrue(marks[0].promptDetectedByTrigger,
                      "Trigger-detected prompt mark should have promptDetectedByTrigger=YES")
    }
}
