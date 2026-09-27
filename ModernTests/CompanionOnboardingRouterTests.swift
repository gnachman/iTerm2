//
//  CompanionOnboardingRouterTests.swift
//  iTerm2 ModernTests
//
//  The wizard-vs-classic routing decision. The key change for AI decoupling: a
//  never-paired, not-yet-configured user is sent to the new choose-mode screen
//  (AI features vs terminal-only) rather than being forced into the AI full setup,
//  and an AI admin policy no longer forces the classic window.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CompanionOnboardingRouterTests: XCTestCase {
    private typealias Router = CompanionOnboardingRouter

    // A new user (never paired, companion not configured) gets the guided wizard
    // starting at the choose-mode fork - not the AI full setup.
    func testNewUserGoesToChooseMode() {
        XCTAssertEqual(
            Router.destination(companionPairingAllowed: true,
                               experienced: false,
                               companionConfigured: false),
            .wizard(.chooseMode))
    }

    // An experienced user (ever paired or paired now) gets the classic settings
    // window regardless of configuration state.
    func testExperiencedUserGoesToClassicSettings() {
        XCTAssertEqual(
            Router.destination(companionPairingAllowed: true,
                               experienced: true,
                               companionConfigured: false),
            .classicSettings)
        XCTAssertEqual(
            Router.destination(companionPairingAllowed: true,
                               experienced: true,
                               companionConfigured: true),
            .classicSettings)
    }

    // Companion is fully configured but no device ever paired: skip the install
    // steps and go straight to phone-app instructions.
    func testConfiguredButUnpairedGoesToPhoneApp() {
        XCTAssertEqual(
            Router.destination(companionPairingAllowed: true,
                               experienced: false,
                               companionConfigured: true),
            .wizard(.phoneApp))
    }

    // An admin policy blocking companion pairing forces the classic window (which
    // explains the block); the wizard can't grant a forbidden capability.
    func testCompanionAdminBlockGoesToClassicSettings() {
        XCTAssertEqual(
            Router.destination(companionPairingAllowed: false,
                               experienced: false,
                               companionConfigured: false),
            .classicSettings)
    }
}
