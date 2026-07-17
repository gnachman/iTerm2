//
//  TurnStatusModelTests.swift
//  iTerm2 ModernTests
//
//  TurnStatusModel is the per-chat "is an agent turn in flight" source of truth.
//  Unlike TypingStatusModel it does NOT go false during a mid-turn park, so it is
//  the accurate signal for seeding a phone's turn state on subscribe/reconnect.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class TurnStatusModelTests: XCTestCase {
    func testInProgressDefaultsFalse() {
        XCTAssertFalse(TurnStatusModel().inProgress(chatID: "c"))
    }

    func testSetInProgressTrue() {
        let model = TurnStatusModel()
        model.set(inProgress: true, chatID: "c")
        XCTAssertTrue(model.inProgress(chatID: "c"))
    }

    func testSetInProgressFalseClears() {
        let model = TurnStatusModel()
        model.set(inProgress: true, chatID: "c")
        model.set(inProgress: false, chatID: "c")
        XCTAssertFalse(model.inProgress(chatID: "c"))
    }

    func testPerChatIsolation() {
        let model = TurnStatusModel()
        model.set(inProgress: true, chatID: "c1")
        XCTAssertTrue(model.inProgress(chatID: "c1"))
        XCTAssertFalse(model.inProgress(chatID: "c2"))
    }
}
