//
//  CompanionPairingFailureTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

/// F-100 / F-336: toggling generative AI while the pairing window showed a
/// failed pairing rebuilt the idle state, erasing the error and the QR code,
/// because a failed pairing is no longer listening.
@MainActor
final class CompanionPairingFailureTests: XCTestCase {
    func testAIToggleDoesNotEraseAPairingFailure() {
        XCTAssertFalse(CompanionPairingWindowController.shouldRebuildReadyToPair(aiAvailabilityChanged: true,
                                                                                 isListening: false,
                                                                                 pairingAuthInFlight: false,
                                                                                 showingPairingFailure: true))
    }

    func testAIToggleRebuildsTheIdleState() {
        XCTAssertTrue(CompanionPairingWindowController.shouldRebuildReadyToPair(aiAvailabilityChanged: true,
                                                                                isListening: false,
                                                                                pairingAuthInFlight: false,
                                                                                showingPairingFailure: false))
        XCTAssertFalse(CompanionPairingWindowController.shouldRebuildReadyToPair(aiAvailabilityChanged: false,
                                                                                 isListening: false,
                                                                                 pairingAuthInFlight: false,
                                                                                 showingPairingFailure: false))
        XCTAssertFalse(CompanionPairingWindowController.shouldRebuildReadyToPair(aiAvailabilityChanged: true,
                                                                                 isListening: true,
                                                                                 pairingAuthInFlight: false,
                                                                                 showingPairingFailure: false))
        XCTAssertFalse(CompanionPairingWindowController.shouldRebuildReadyToPair(aiAvailabilityChanged: true,
                                                                                 isListening: false,
                                                                                 pairingAuthInFlight: true,
                                                                                 showingPairingFailure: false))
    }
}
