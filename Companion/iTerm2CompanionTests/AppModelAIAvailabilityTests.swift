//
//  AppModelAIAvailabilityTests.swift
//  iTerm2CompanionTests
//
//  The phone tracks whether the paired Mac has AI available so it can disable its
//  chat surfaces when AI is off. It defaults to true (a pre-13 Mac only ever paired
//  with AI on) and flips live on the aiAvailabilityChanged host event, moving the
//  user off the now-disabled Chats tab.
//

import XCTest
import CompanionProtocol
@testable import iTerm2Companion

@MainActor
final class AppModelAIAvailabilityTests: XCTestCase {
    func test_defaultsToAvailable() {
        // A fresh model assumes AI is available until a handshake says otherwise,
        // so a pre-13 Mac (no aiAvailable field -> nil -> true) behaves as before.
        XCTAssertTrue(AppModel().aiAvailable)
    }

    func test_aiAvailabilityChangedFlipsFlag() {
        let model = AppModel()
        model.testHandleHostEvent(.aiAvailabilityChanged(available: false))
        XCTAssertFalse(model.aiAvailable)
        model.testHandleHostEvent(.aiAvailabilityChanged(available: true))
        XCTAssertTrue(model.aiAvailable)
    }

    func test_aiTurningOffMovesUserOffChatsTab() {
        let model = AppModel()
        model.selectedTab = .chats
        model.testHandleHostEvent(.aiAvailabilityChanged(available: false))
        XCTAssertEqual(model.selectedTab, .sessions,
                       "the user must not be stranded on the disabled Chats tab")
    }

    func test_aiTurningOffLeavesSessionsTabAlone() {
        let model = AppModel()
        model.selectedTab = .sessions
        model.testHandleHostEvent(.aiAvailabilityChanged(available: false))
        XCTAssertEqual(model.selectedTab, .sessions)
    }
}
