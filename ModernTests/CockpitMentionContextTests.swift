//
//  CockpitMentionContextTests.swift
//  ModernTests
//
//  QA finding F-240: a literal word-start '@' (as in "email me @ noon")
//  kept the session picker open on every later keystroke, so Return
//  committed a chip instead of inserting a newline. Only the @-run the
//  caret is in may drive the picker, and a run dismissed with Esc stays
//  dismissed.
//

import XCTest
@testable import iTerm2SharedARC

final class CockpitMentionContextTests: XCTestCase {
    private func context(_ string: String,
                         caret: Int? = nil,
                         dismissed: Int? = nil) -> (range: NSRange, query: String)? {
        let location = caret ?? (string as NSString).length
        return CockpitWindowController.mentionContext(in: string,
                                                      selectedRange: NSRange(location: location, length: 0),
                                                      dismissedLocation: dismissed)
    }

    func testBareAtFollowedBySpaceIsLiteral() {
        XCTAssertNil(context("email me @ noon"))
        XCTAssertNil(context("email me @ "))
    }

    func testAtJustTypedOpensPicker() {
        let result = context("email me @")
        XCTAssertEqual(result?.range, NSRange(location: 9, length: 1))
        XCTAssertEqual(result?.query, "")
    }

    func testQueryWhileTyping() {
        let result = context("echo @ab")
        XCTAssertEqual(result?.range, NSRange(location: 5, length: 3))
        XCTAssertEqual(result?.query, "ab")
    }

    func testCaretOutsideRunIsNotAMention() {
        // "@foo bar" with the caret at the end: the run was finished.
        XCTAssertNil(context("@foo bar"))
        // Caret before the '@'.
        XCTAssertNil(context("x @foo", caret: 1))
    }

    func testCaretInsideLaterRunSkipsEarlierLiteralRun() {
        let string = "@foo and @ba"
        let result = context(string)
        XCTAssertEqual(result?.range, NSRange(location: 9, length: 3))
        XCTAssertEqual(result?.query, "ba")
    }

    func testCaretInMiddleOfRun() {
        let result = context("@abc tail", caret: 2)
        XCTAssertEqual(result?.range, NSRange(location: 0, length: 4))
        XCTAssertEqual(result?.query, "abc")
    }

    func testDismissedRunStaysDismissed() {
        XCTAssertNil(context("a @b", dismissed: 2))
        XCTAssertNotNil(context("a @b", dismissed: nil))
    }

    func testNonEmptySelectionIsNotAMention() {
        XCTAssertNil(CockpitWindowController.mentionContext(in: "@abc",
                                                            selectedRange: NSRange(location: 1, length: 2),
                                                            dismissedLocation: nil))
    }

    func testMidWordAtIsNotAMention() {
        XCTAssertNil(context("user@host"))
    }
}
