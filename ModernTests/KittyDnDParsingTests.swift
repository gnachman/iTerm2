//
//  KittyDnDParsingTests.swift
//  iTerm2 ModernTests
//
//  Phase 1 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. Drives raw bytes through the real parser and
//  terminal and asserts the OSC 72 content reaches the screen delegate. Stateful
//  chunk reassembly is the controller's job (phase 2), so this layer delivers
//  each OSC 72 escape sequence's raw content verbatim.
//

import XCTest
@testable import iTerm2SharedARC

final class KittyDnDParsingTests: XCTestCase {
    private func feed(_ harness: TerminalTestHarness, _ string: String) {
        harness.screen.inject(string.data(using: .utf8)!)
        harness.screen.performBlock(joinedThreads: { _, _, _ in })
    }

    private func osc72(_ content: String) -> String {
        return "\u{1b}]72;\(content)\u{1b}\\"
    }

    func testDeliversAnnounceContent() {
        let harness = TerminalTestHarness()
        feed(harness, osc72("t=a"))
        XCTAssertEqual(harness.delegate.kittyDragAndDropContents, ["t=a"])
    }

    // The content after "72;" is delivered verbatim, including the internal ";"
    // that separates metadata from the base64 payload.
    func testDeliversContentWithPayloadIncludingInternalSemicolon() {
        let harness = TerminalTestHarness()
        feed(harness, osc72("t=r:x=1;YWJj"))
        XCTAssertEqual(harness.delegate.kittyDragAndDropContents, ["t=r:x=1;YWJj"])
    }

    func testDeliversMultipleSequencesInOrder() {
        let harness = TerminalTestHarness()
        feed(harness, osc72("t=a") + osc72("t=o:x=1"))
        XCTAssertEqual(harness.delegate.kittyDragAndDropContents, ["t=a", "t=o:x=1"])
    }

    // OSC may be terminated by BEL as well as ST; both must deliver the same
    // content. (Cross-read streaming of a partial sequence is generic VT100
    // parser behavior, identical to OSC 52's, and is not exercisable here
    // because the test harness's injectData: uses a fresh parser per call.)
    func testBELTerminatorDeliversSameContent() {
        let harness = TerminalTestHarness()
        harness.screen.inject("\u{1b}]72;t=r:x=1;YWJj\u{07}".data(using: .utf8)!)
        harness.screen.performBlock(joinedThreads: { _, _, _ in })
        XCTAssertEqual(harness.delegate.kittyDragAndDropContents, ["t=r:x=1;YWJj"])
    }

    // A full-size payload (3072 raw bytes -> exactly 4096 base64 chars) must be
    // delivered without truncation.
    func testDeliversFullSizePayloadWithoutTruncation() {
        let harness = TerminalTestHarness()
        let raw = Data((0..<3072).map { UInt8($0 & 0xff) })
        let b64 = raw.base64EncodedString()
        feed(harness, osc72("t=r:x=1;\(b64)"))
        XCTAssertEqual(harness.delegate.kittyDragAndDropContents, ["t=r:x=1;\(b64)"])
    }
}
