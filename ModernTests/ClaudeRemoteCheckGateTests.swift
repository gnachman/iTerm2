//
//  ClaudeRemoteCheckGateTests.swift
//  iTerm2 ModernTests
//
//  The health monitor checks each SSH Integration connection for Claude Code's hook once, but
//  only once the integration is in use.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeRemoteCheckGateTests: XCTestCase {
    // Claude ran on the host before the integration was set up: the host is checked once it is.
    func testAConnectionSeenBeforeTheIntegrationIsInUseIsCheckedLater() {
        var gate = ClaudeRemoteCheckGate()
        XCTAssertFalse(gate.shouldCheck("c1", integrationInUse: false))
        XCTAssertFalse(gate.hasChecked("c1"))
        XCTAssertTrue(gate.shouldCheck("c1", integrationInUse: true))
    }

    func testEachConnectionIsCheckedOnce() {
        var gate = ClaudeRemoteCheckGate()
        XCTAssertTrue(gate.shouldCheck("c1", integrationInUse: true))
        XCTAssertFalse(gate.shouldCheck("c1", integrationInUse: true))
        XCTAssertTrue(gate.hasChecked("c1"))
        XCTAssertTrue(gate.shouldCheck("c2", integrationInUse: true))
    }

    func testAForgottenConnectionIsCheckedAgain() {
        var gate = ClaudeRemoteCheckGate()
        XCTAssertTrue(gate.shouldCheck("c1", integrationInUse: true))
        gate.forget("c1")
        XCTAssertTrue(gate.shouldCheck("c1", integrationInUse: true))
    }
}
