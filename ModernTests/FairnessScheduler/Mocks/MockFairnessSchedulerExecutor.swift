//
//  MockFairnessSchedulerExecutor.swift
//  ModernTests
//
//  Mock executor for testing FairnessScheduler in isolation.
//  This simulates the TokenExecutor interface that FairnessScheduler will use.
//

import Foundation
@testable import iTerm2SharedARC

// TurnResult and FairnessSchedulerExecutor are defined in FairnessScheduler.swift

/// Mock implementation for testing FairnessScheduler without real TokenExecutor.
final class MockFairnessSchedulerExecutor: FairnessSchedulerExecutor {

    // MARK: - Configuration

    /// The result to return from executeTurn. Set this before each test scenario.
    var turnResult: TurnResult = .completed

    /// If set, executeTurn calls this instead of using turnResult.
    /// Useful for dynamic behavior or async testing.
    var executeTurnHandler: ((Int, @escaping (TurnResult) -> Void) -> Void)?

    /// Delay before calling completion (simulates execution time)
    var executionDelay: TimeInterval = 0

    /// Whether cleanupForUnregistration was called
    private(set) var cleanupCalled = false

    /// Number of times cleanupForUnregistration was called
    private(set) var cleanupCallCount = 0

    // MARK: - Call Tracking

    struct ExecuteTurnCall: Equatable {
        let tokenBudget: Int
        let timestamp: Date

        static func == (lhs: ExecuteTurnCall, rhs: ExecuteTurnCall) -> Bool {
            return lhs.tokenBudget == rhs.tokenBudget
        }
    }

    private(set) var executeTurnCalls: [ExecuteTurnCall] = []
    private(set) var totalTokenBudgetConsumed: Int = 0

    // MARK: - FairnessSchedulerExecutor

    func executeTurn(tokenBudget: Int, completion: @escaping (TurnResult) -> Void) {
        executeTurnCalls.append(ExecuteTurnCall(tokenBudget: tokenBudget, timestamp: Date()))
        totalTokenBudgetConsumed += tokenBudget

        if let handler = executeTurnHandler {
            handler(tokenBudget, completion)
            return
        }

        if executionDelay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + executionDelay) { [turnResult] in
                completion(turnResult)
            }
        } else {
            completion(turnResult)
        }
    }

    func cleanupForUnregistration() {
        cleanupCalled = true
        cleanupCallCount += 1
    }

    // MARK: - Test Helpers

    func reset() {
        turnResult = .completed
        executeTurnHandler = nil
        executionDelay = 0
        cleanupCalled = false
        cleanupCallCount = 0
        executeTurnCalls = []
        totalTokenBudgetConsumed = 0
    }

    /// Returns the number of times executeTurn was called
    var executeTurnCallCount: Int {
        return executeTurnCalls.count
    }
}
