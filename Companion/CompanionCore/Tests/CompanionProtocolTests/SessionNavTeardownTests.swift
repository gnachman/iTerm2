//
//  SessionNavTeardownTests.swift
//  CompanionCore
//
//  The shared open-conversation/subscription state must survive as long as the
//  chat is mounted on either navigation stack, so a chat is torn down only when
//  its last mount is gone across BOTH stacks.
//

import XCTest
@testable import CompanionProtocol

final class SessionNavTeardownTests: XCTestCase {
    private func fullyRemoved(before: Set<String>, after: Set<String>, other: Set<String>) -> Set<String> {
        SessionNavTeardown.fullyRemoved(before: before, after: after, otherStack: other)
    }

    func test_popsSoleMount_tearsDown() {
        // A was the only mount and is now gone: tear it down.
        XCTAssertEqual(fullyRemoved(before: ["A"], after: [], other: []), ["A"])
    }

    func test_sameChatStillOnOtherStack_isRetained() {
        // A popped off this stack but still open on the other tab: keep it.
        XCTAssertEqual(fullyRemoved(before: ["A"], after: [], other: ["A"]), [])
    }

    func test_duplicateInSameStack_isRetained() {
        // A appears twice in this stack (an @-mention pushed a copy above its
        // own conversation); popping one leaves the other, so keep it.
        XCTAssertEqual(fullyRemoved(before: ["A"], after: ["A"], other: []), [])
    }

    func test_differentChats_onlyTheGoneOneTearsDown() {
        // B popped here while C stays on the other stack: tear down only B.
        XCTAssertEqual(fullyRemoved(before: ["B"], after: [], other: ["C"]), ["B"])
    }

    func test_multipleRemoved() {
        XCTAssertEqual(fullyRemoved(before: ["A", "B", "C"], after: ["B"], other: ["C"]), ["A"])
    }

    func test_nothingRemoved_whenAfterSupersetOfBefore() {
        // A push (not a pop) removes nothing.
        XCTAssertEqual(fullyRemoved(before: ["A"], after: ["A", "B"], other: []), [])
    }
}
