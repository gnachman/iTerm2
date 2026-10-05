//
//  PTYTextViewAccessibilityAnnouncementTests.swift
//  iTerm2
//
//  Ported from the legacy PTYTextViewAccessibilityTest.m. Covers the pure helper
//  that decides which newly visible lines get announced to VoiceOver.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTextViewAccessibilityAnnouncementTests: XCTestCase {
    private func announcementLines(trimmedLines: [String],
                                   firstAbsoluteLine: Int64,
                                   oldAbsoluteCursorY: Int64,
                                   oldCursorLineString: String) -> [String] {
        return PTYTextView.accessibilityAnnouncementLines(forTrimmedLines: trimmedLines,
                                                          firstAbsoluteLine: firstAbsoluteLine,
                                                          oldAbsoluteCursorY: oldAbsoluteCursorY,
                                                          oldCursorLineString: oldCursorLineString)
    }

    func testSkipsUnchangedOldCursorLineAndEmptyLines() {
        let actual = announcementLines(trimmedLines: [ "pwd", "", "Users/deonnel" ],
                                       firstAbsoluteLine: 42,
                                       oldAbsoluteCursorY: 42,
                                       oldCursorLineString: "pwd   ")
        XCTAssertEqual(actual, [ "Users/deonnel" ])
    }

    func testAnnouncesChangedOldCursorLine() {
        let actual = announcementLines(trimmedLines: [ "hello", "world" ],
                                       firstAbsoluteLine: 100,
                                       oldAbsoluteCursorY: 100,
                                       oldCursorLineString: "echo hello")
        XCTAssertEqual(actual, [ "hello", "world" ])
    }

    func testSkipsOnlyTheOriginalCursorLine() {
        let actual = announcementLines(trimmedLines: [ "prompt", "prompt" ],
                                       firstAbsoluteLine: 7,
                                       oldAbsoluteCursorY: 7,
                                       oldCursorLineString: "prompt")
        XCTAssertEqual(actual, [ "prompt" ])
    }
}
