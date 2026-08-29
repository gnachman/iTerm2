//
//  SleepPreventionCoordinatorTests.swift
//  ModernTests
//
//  Tests for the pure count decision of the sleep-prevention coordinator: how many sessions keep
//  the machine awake, including exclusion of a terminating session (F1) and de-duplication of a
//  session that transiently appears in both the live and buried lists while being buried (F25).
//

import XCTest
@testable import iTerm2SharedARC

final class SleepPreventionCoordinatorTests: XCTestCase {
    private func count(_ guids: [String],
                       excluding: String? = nil,
                       onPower: Bool = true,
                       battery: Bool = false) -> Int {
        return SleepPreventionCoordinator.numberOfSessionsPreventingSleep(
            requesterGUIDs: guids, excludingGUID: excluding,
            connectedToPower: onPower, allowedOnBattery: battery)
    }

    // F1: the terminating session is still enumerated at WillTerminate time, so excluding the last
    // requester must drop the count to 0 (assertion released).
    func testLastRequesterTerminatingReleases() {
        XCTAssertEqual(count(["A"], excluding: "A"), 0)
    }

    func testOtherRequesterRemainsHolds() {
        XCTAssertEqual(count(["A", "B"], excluding: "A"), 1)
    }

    func testNoExclusionCounts() {
        XCTAssertEqual(count(["A"]), 1)
        XCTAssertEqual(count(["A", "B"]), 2)
    }

    func testNoRequestersIsZero() {
        XCTAssertEqual(count([]), 0)
    }

    // AC-only (allowedOnBattery == false) on battery: hold nothing.
    func testACOnlyOnBatteryIsZero() {
        XCTAssertEqual(count(["A"], onPower: false, battery: false), 0)
    }

    func testBatteryAllowedCounts() {
        XCTAssertEqual(count(["A"], onPower: false, battery: true), 1)
    }

    // F25: a session buried transiently appears in both allSessions() and buriedSessions(), so the
    // requester list contains its GUID twice. It must be counted once.
    func testDuplicateGuidsCountedOnce() {
        XCTAssertEqual(count(["G", "G"]), 1)
        XCTAssertEqual(count(["G", "G", "H"]), 2)
    }

    func testExcludingNonRequesterHolds() {
        XCTAssertEqual(count(["A", "B"], excluding: "Z"), 2)
    }

    // The ungated requester count (for the status label) ignores the power gate but still dedups
    // and honors exclusion. On battery with the default policy, holding==0 while requesting>0, which
    // is what lets the label say "would prevent sleep, but disabled on battery" instead of "none".
    func testRequesterCountIgnoresPowerGate() {
        func requesting(_ guids: [String], excluding: String? = nil) -> Int {
            return SleepPreventionCoordinator.numberOfSessionsRequestingPreventSleep(
                requesterGUIDs: guids, excludingGUID: excluding)
        }
        // On battery, gated count is 0 but requester count is not.
        XCTAssertEqual(count(["A"], onPower: false, battery: false), 0)
        XCTAssertEqual(requesting(["A"]), 1)
        XCTAssertEqual(requesting(["G", "G", "H"]), 2)   // dedup
        XCTAssertEqual(requesting(["A", "B"], excluding: "A"), 1)
    }
}
