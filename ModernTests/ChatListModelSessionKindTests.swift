//
//  ChatListModelSessionKindTests.swift
//  iTerm2 ModernTests
//
//  A chat's terminal and browser slots must each hold a session of their own
//  kind. ChatListModel.sessionGuidsByKind sorts a pair of guids into the right
//  slots, including when they arrive swapped.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatListModelSessionKindTests: XCTestCase {
    private let kinds: [String: Bool] = ["T": false, "T2": false, "B": true, "B2": true]

    private func sorted(terminal: String?, browser: String?) -> (terminal: String?, browser: String?) {
        ChatListModel.sessionGuidsByKind(terminal: terminal, browser: browser) { self.kinds[$0] }
    }

    func testCorrectSlotsAreKept() {
        let result = sorted(terminal: "T", browser: "B")
        XCTAssertEqual(result.terminal, "T")
        XCTAssertEqual(result.browser, "B")
    }

    func testSwappedSlotsAreBothKept() {
        let result = sorted(terminal: "B", browser: "T")
        XCTAssertEqual(result.terminal, "T")
        XCTAssertEqual(result.browser, "B")
    }

    func testBrowserInTerminalSlotMoves() {
        let result = sorted(terminal: "B", browser: nil)
        XCTAssertNil(result.terminal)
        XCTAssertEqual(result.browser, "B")
    }

    func testTerminalInBrowserSlotMoves() {
        let result = sorted(terminal: nil, browser: "T")
        XCTAssertEqual(result.terminal, "T")
        XCTAssertNil(result.browser)
    }

    func testTwoBrowsersKeepTheOneInTheBrowserSlot() {
        let result = sorted(terminal: "B", browser: "B2")
        XCTAssertNil(result.terminal)
        XCTAssertEqual(result.browser, "B2")
    }

    func testTwoTerminalsKeepTheOneInTheTerminalSlot() {
        let result = sorted(terminal: "T", browser: "T2")
        XCTAssertEqual(result.terminal, "T")
        XCTAssertNil(result.browser)
    }

    /// A session that is not live has no known kind, so it stays where it was.
    func testUnresolvedGuidsStayInPlace() {
        let result = sorted(terminal: "gone1", browser: "gone2")
        XCTAssertEqual(result.terminal, "gone1")
        XCTAssertEqual(result.browser, "gone2")
    }

    /// A live session of the right kind takes the slot over an unresolved one.
    func testLiveSessionClaimsSlotFromUnresolvedOne() {
        let result = sorted(terminal: "gone", browser: "T")
        XCTAssertEqual(result.terminal, "T")
        XCTAssertNil(result.browser)
    }

    func testEmptySlotsStayEmpty() {
        let result = sorted(terminal: nil, browser: nil)
        XCTAssertNil(result.terminal)
        XCTAssertNil(result.browser)
    }
}
