//
//  ClaudeInterruptDetectorTests.swift
//  ModernTests
//
//  Screen classification for the Esc interrupt detector. The
//  fixtures are the trailing lines of real Claude Code screens: a live
//  turn, an interrupted turn, a finished turn, and the extended-thinking
//  spinner that carries no token counter.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeInterruptDetectorTests: XCTestCase {
    private typealias Verdict = ClaudeInterruptDetector.Verdict

    func test_interruptedLineIsIdle() {
        let screen = """
        ⏺ Bash(sleep 30)
          ⎿  Interrupted · What should Claude do instead?

        ❯
        """
        XCTAssertEqual(ClaudeInterruptDetector.classify(screenText: screen), .interrupted)
    }

    func test_bareInterruptedToolResultIsIdle() {
        let screen = """
        ⏺ Bash(sleep 30)
          ⎿  Interrupted

        ❯
        """
        XCTAssertEqual(ClaudeInterruptDetector.classify(screenText: screen), .interrupted)
    }

    func test_liveSpinnerWithTokenCounterIsWorking() {
        let screen = """
        ✽ Baking… (49s · ↓ 3.4k tokens)
        """
        XCTAssertEqual(ClaudeInterruptDetector.classify(screenText: screen), .working)
    }

    func test_extendedThinkingSpinnerIsWorking() {
        let screen = """
        ✢ Ionizing… (20s · still thinking with high effort)
        """
        XCTAssertEqual(ClaudeInterruptDetector.classify(screenText: screen), .working)
    }

    func test_hourLongSpinnerIsWorking() {
        let screen = "✻ Cooking… (1h 2m 3s · ↓ 95.6k tokens)"
        XCTAssertEqual(ClaudeInterruptDetector.classify(screenText: screen), .working)
    }

    // A new turn started while the previous turn’s “Interrupted” line is
    // still visible: the spinner must win.
    func test_spinnerWinsOverStaleInterruptedLine() {
        let screen = """
          ⎿  Interrupted · What should Claude do instead?

        ✽ Baking… (3s · ↓ 12 tokens)
        """
        XCTAssertEqual(ClaudeInterruptDetector.classify(screenText: screen), .working)
    }

    func test_finishedTurnWithoutInterruptIsUnknown() {
        let screen = """
        ✻ Cooked for 1m 12s

        ❯
        """
        XCTAssertEqual(ClaudeInterruptDetector.classify(screenText: screen), .unknown)
    }

    func test_shellPromptIsUnknown() {
        XCTAssertEqual(ClaudeInterruptDetector.classify(screenText: "user@host ~ %"), .unknown)
    }

    // The word alone in prose (e.g. Claude quoting an error) is not an
    // interrupt line.
    func test_interruptedInProseIsUnknown() {
        let screen = "The read() call failed with Interrupted system call."
        XCTAssertEqual(ClaudeInterruptDetector.classify(screenText: screen), .unknown)
    }

    // Esc must be recognized both as the legacy bare byte and as the
    // CSI 27 u form the modern key mapper emits under kitty disambiguate
    // mode, and nothing else may pass.
    func test_escapeKeyEncodings() {
        XCTAssertTrue(ClaudeInterruptDetector.isEscapeKey(Data([0x1b])))
        XCTAssertTrue(ClaudeInterruptDetector.isEscapeKey(Data("\u{1b}[27u".utf8)))
        XCTAssertTrue(ClaudeInterruptDetector.isEscapeKey(Data("\u{1b}[27;1u".utf8)))

        XCTAssertFalse(ClaudeInterruptDetector.isEscapeKey(Data()))
        XCTAssertFalse(ClaudeInterruptDetector.isEscapeKey(Data([0x03])))          // Ctrl-C
        XCTAssertFalse(ClaudeInterruptDetector.isEscapeKey(Data("a".utf8)))
        XCTAssertFalse(ClaudeInterruptDetector.isEscapeKey(Data("\u{1b}a".utf8)))  // legacy Alt-a
        XCTAssertFalse(ClaudeInterruptDetector.isEscapeKey(Data("\u{1b}[A".utf8))) // Up arrow
        XCTAssertFalse(ClaudeInterruptDetector.isEscapeKey(Data("\u{1b}[27;2u".utf8))) // Shift-Esc
        XCTAssertFalse(ClaudeInterruptDetector.isEscapeKey(Data("\u{1b}[27u\u{1b}[27u".utf8)))
    }

    func test_onlyWorkingAndWaitingAreInterruptible() {
        XCTAssertTrue(ClaudeInterruptDetector.isInterruptible(status: "working"))
        XCTAssertTrue(ClaudeInterruptDetector.isInterruptible(status: "Waiting"))
        XCTAssertFalse(ClaudeInterruptDetector.isInterruptible(status: "idle"))
        XCTAssertFalse(ClaudeInterruptDetector.isInterruptible(status: ""))
        XCTAssertFalse(ClaudeInterruptDetector.isInterruptible(status: nil))
    }
}
