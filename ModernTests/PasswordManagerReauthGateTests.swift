//
//  PasswordManagerReauthGateTests.swift
//  ModernTests
//
//  The password manager caches a successful Touch ID / password authentication on
//  a process-lifetime singleton, so once you unlock it once, subsequent opens
//  (⌥⌘F, from a profile, a new window) skip the prompt until the screen locks.
//  "Require Authentication on Every Open" opts out of that reuse so every open
//  re-prompts. The decision is factored into a pure function so it can be tested
//  without LocalAuthentication: a cached authentication may be reused unless the
//  user requires authentication on every open, and the every-open preference only
//  applies when authentication is required at all.
//

import XCTest
@testable import iTerm2SharedARC

final class PasswordManagerReauthGateTests: XCTestCase {
    func testReusesCachedAuthByDefault() {
        // Auth required, every-open off: the historical behavior. Reuse the cache.
        XCTAssertTrue(PasswordManagerDataSourceProvider.mayReuseAuthentication(authRequired: true,
                                                                               requireEveryOpen: false))
    }

    func testEveryOpenForcesReauth() {
        // Auth required, every-open on: never reuse; force a fresh prompt each open.
        XCTAssertFalse(PasswordManagerDataSourceProvider.mayReuseAuthentication(authRequired: true,
                                                                                requireEveryOpen: true))
    }

    func testEveryOpenIsMootWhenAuthNotRequired() {
        // With authentication not required there is no prompt to force, so the
        // every-open preference cannot lock the user out of an unprotected manager.
        XCTAssertTrue(PasswordManagerDataSourceProvider.mayReuseAuthentication(authRequired: false,
                                                                               requireEveryOpen: true))
        XCTAssertTrue(PasswordManagerDataSourceProvider.mayReuseAuthentication(authRequired: false,
                                                                               requireEveryOpen: false))
    }

    // The settings menu shows the three stored settings as one exclusive choice.
    private func mode(_ authRequired: Bool,
                      _ afterScreenLocks: Bool,
                      _ everyOpen: Bool) -> PasswordManagerAuthenticationMode {
        return PasswordManagerDataSourceProvider.authenticationMode(authRequired: authRequired,
                                                                    afterScreenLocks: afterScreenLocks,
                                                                    everyOpen: everyOpen)
    }

    func testModeIsNeverWhenAuthNotRequired() {
        // Leftover sub-settings from before authentication was turned off don't matter.
        XCTAssertEqual(mode(false, false, false), .never)
        XCTAssertEqual(mode(false, true, false), .never)
        XCTAssertEqual(mode(false, false, true), .never)
        XCTAssertEqual(mode(false, true, true), .never)
    }

    func testModeOncePerLaunch() {
        XCTAssertEqual(mode(true, false, false), .oncePerLaunch)
    }

    func testModeOncePerLaunchAndAfterScreenLocks() {
        XCTAssertEqual(mode(true, true, false), .oncePerLaunchAndAfterScreenLocks)
    }

    func testEveryOpenTakesPrecedenceOverAfterScreenLocks() {
        XCTAssertEqual(mode(true, false, true), .everyOpen)
        XCTAssertEqual(mode(true, true, true), .everyOpen)
    }

    func testScreenLockRequiresAuthenticationOnlyForModesThatPromptAfterALock() {
        // These modes revoke the cached authentication and close an open window
        // when the screen locks.
        XCTAssertTrue(PasswordManagerDataSourceProvider.requiresAuthenticationAfterScreenLock(mode: .oncePerLaunchAndAfterScreenLocks))
        XCTAssertTrue(PasswordManagerDataSourceProvider.requiresAuthenticationAfterScreenLock(mode: .everyOpen))
        XCTAssertFalse(PasswordManagerDataSourceProvider.requiresAuthenticationAfterScreenLock(mode: .oncePerLaunch))
        XCTAssertFalse(PasswordManagerDataSourceProvider.requiresAuthenticationAfterScreenLock(mode: .never))
    }
}
