//
//  iTermTabColorInactivityPolicyTests.swift
//  ModernTests
//
//  Custom tab colors may optionally expire after a period without terminal
//  output. These tests keep the clock outside the policy so hours of inactivity
//  can be covered deterministically without timers or sleeps.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTabColorInactivityPolicyTests: XCTestCase {
    func testZeroHoursDisablesExpiration() {
        XCTAssertTrue(iTermTabColorInactivityPolicy.shouldShowCustomColor(
            expirationHours: 0,
            inactiveSeconds: .greatestFiniteMagnitude))
    }

    func testNegativeHoursDisablesExpiration() {
        XCTAssertTrue(iTermTabColorInactivityPolicy.shouldShowCustomColor(
            expirationHours: -1,
            inactiveSeconds: .greatestFiniteMagnitude))
    }

    func testColorIsShownBeforeExpirationThreshold() {
        XCTAssertTrue(iTermTabColorInactivityPolicy.shouldShowCustomColor(
            expirationHours: 2,
            inactiveSeconds: 7_199))
    }

    func testColorIsHiddenAtExpirationThreshold() {
        XCTAssertFalse(iTermTabColorInactivityPolicy.shouldShowCustomColor(
            expirationHours: 2,
            inactiveSeconds: 7_200))
    }

    func testColorRemainsHiddenAfterExpirationThreshold() {
        XCTAssertFalse(iTermTabColorInactivityPolicy.shouldShowCustomColor(
            expirationHours: 2,
            inactiveSeconds: 7_201))
    }

    func testFreshActivityShowsColorAgain() {
        XCTAssertTrue(iTermTabColorInactivityPolicy.shouldShowCustomColor(
            expirationHours: 2,
            inactiveSeconds: 0))
    }
}
