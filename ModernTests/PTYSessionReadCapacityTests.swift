//
//  PTYSessionReadCapacityTests.swift
//  iTerm2
//
//  A tmux gateway stops reading while its panes' unread output is over budget.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionReadCapacityTests: XCTestCase {
    func testOnlyAGatewayIsLimitedByItsPanesOutput() {
        let session = PTYSession(synthetic: false)!
        let budget = ByteBudget(capacity: 4)
        session.setTmuxOutputBudgetForTesting(budget)
        budget.take(10)
        defer {
            budget.give(10)
        }
        XCTAssertTrue(session.taskHasReadCapacity())
        session.setTmuxModeForTesting(TMUX_GATEWAY)
        XCTAssertFalse(session.taskHasReadCapacity())
    }

    // A monitor waiting for the panes to drain must check again when the gateway leaves tmux mode,
    // because the budget, still full, no longer limits it.
    func testLeavingGatewayModeWakesAWaitingMonitor() {
        let session = PTYSession(synthetic: false)!
        let budget = ByteBudget(capacity: 4)
        session.setTmuxOutputBudgetForTesting(budget)
        session.setTmuxModeForTesting(TMUX_GATEWAY)
        budget.take(10)
        defer {
            budget.give(10)
        }
        XCTAssertFalse(session.taskHasReadCapacity())

        let queue = DispatchQueue(label: "PTYSessionReadCapacityTests")
        let woken = expectation(description: "Woken")
        session.taskNotifyWhenReadCapacityAvailable(on: queue) {
            woken.fulfill()
        }
        queue.sync {}
        session.setTmuxModeForTesting(TMUX_NONE)
        wait(for: [woken], timeout: 10)
        XCTAssertTrue(session.taskHasReadCapacity())
    }
}
