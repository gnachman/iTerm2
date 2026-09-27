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
}
