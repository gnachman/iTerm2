//
//  OnscreenTestGate.swift
//  ModernTests
//
//  Tests that order windows onto the screen or make them key get in the way of
//  using the machine while the suite runs, so they are skipped by default. To
//  run them, set ITERM2_ONSCREEN_TESTS=1 in the test process:
//
//    TEST_RUNNER_ITERM2_ONSCREEN_TESTS=1 tools/run_tests.expect ModernTests/FloatingPaneMouseTests
//
//  (xcodebuild forwards TEST_RUNNER_-prefixed variables with the prefix removed.)
//  SplitPaneStaleTargetTests.m checks the same variable.
//

import XCTest

enum OnscreenTestGate {
    static var enabled: Bool {
        return ProcessInfo.processInfo.environment["ITERM2_ONSCREEN_TESTS"] == "1"
    }

    static func skipUnlessEnabled() throws {
        try XCTSkipUnless(enabled, "Puts windows on screen. Set ITERM2_ONSCREEN_TESTS=1 to run.")
    }
}
