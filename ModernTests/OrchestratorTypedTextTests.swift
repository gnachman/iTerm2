//
//  OrchestratorTypedTextTests.swift
//  iTerm2 ModernTests
//
//  Offline tests for OrchestratorDispatcher.splitTrailingSubmit, the rule
//  that turns a trailing newline in a send_text payload into the Return
//  keystroke instead of pasted data. Without it, text "\n" with
//  append_newline=false was delivered as a bracketed paste of a bare LF,
//  which a TUI like Claude Code inserts as an empty line rather than
//  treating as Enter.
//

import XCTest
@testable import iTerm2SharedARC

final class OrchestratorTypedTextTests: XCTestCase {

    func testBareNewlineWithoutAppendBecomesReturn() {
        let r = OrchestratorDispatcher.splitTrailingSubmit(text: "\n", appendNewline: false)
        XCTAssertEqual(r.body, "")
        XCTAssertTrue(r.submits)
    }

    func testBareCarriageReturnWithoutAppendBecomesReturn() {
        let r = OrchestratorDispatcher.splitTrailingSubmit(text: "\r", appendNewline: false)
        XCTAssertEqual(r.body, "")
        XCTAssertTrue(r.submits)
    }

    func testTrailingCRLFIsPeeledAsOneUnit() {
        let r = OrchestratorDispatcher.splitTrailingSubmit(text: "ls\r\n", appendNewline: false)
        XCTAssertEqual(r.body, "ls")
        XCTAssertTrue(r.submits)
    }

    func testTrailingNewlineWithAppendSubmitsOnce() {
        // The model asked for a newline twice (explicit \n plus the default
        // append). That collapses to a single Return; it does not paste a
        // line break and then submit.
        let r = OrchestratorDispatcher.splitTrailingSubmit(text: "foo\n", appendNewline: true)
        XCTAssertEqual(r.body, "foo")
        XCTAssertTrue(r.submits)
    }

    func testOnlyOneTrailingNewlineIsPeeled() {
        let r = OrchestratorDispatcher.splitTrailingSubmit(text: "foo\n\n", appendNewline: false)
        XCTAssertEqual(r.body, "foo\n")
        XCTAssertTrue(r.submits)
    }

    func testInteriorNewlinesStayInBody() {
        let r = OrchestratorDispatcher.splitTrailingSubmit(text: "a\nb", appendNewline: false)
        XCTAssertEqual(r.body, "a\nb")
        XCTAssertFalse(r.submits)
    }

    func testNoTrailingNewlineHonorsAppendFlag() {
        let off = OrchestratorDispatcher.splitTrailingSubmit(text: "foo", appendNewline: false)
        XCTAssertEqual(off.body, "foo")
        XCTAssertFalse(off.submits)

        let on = OrchestratorDispatcher.splitTrailingSubmit(text: "foo", appendNewline: true)
        XCTAssertEqual(on.body, "foo")
        XCTAssertTrue(on.submits)
    }

    func testEmptyTextHonorsAppendFlag() {
        let off = OrchestratorDispatcher.splitTrailingSubmit(text: "", appendNewline: false)
        XCTAssertEqual(off.body, "")
        XCTAssertFalse(off.submits)

        let on = OrchestratorDispatcher.splitTrailingSubmit(text: "", appendNewline: true)
        XCTAssertEqual(on.body, "")
        XCTAssertTrue(on.submits)
    }

    func testControlBytesBeforeTrailingNewlineStayInBody() {
        // ESC :q LF to quit vim: the ESC and :q are keystrokes for the raw
        // write path; the LF is the submit.
        let r = OrchestratorDispatcher.splitTrailingSubmit(text: "\u{1b}:q\n", appendNewline: false)
        XCTAssertEqual(r.body, "\u{1b}:q")
        XCTAssertTrue(r.submits)
    }
}
