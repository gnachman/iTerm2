//
//  FairnessSchedulerTests.swift
//  ModernTests
//
//  Unit tests for FairnessScheduler - the round-robin fair scheduling coordinator.
//  See testing.md Phase 1 for test specifications.
//

import XCTest
@testable import iTerm2SharedARC

/// Tests for FairnessScheduler session registration and unregistration.
/// (see: testing.md Section 1.1)
final class FairnessSchedulerSessionTests: XCTestCase {

    var scheduler: FairnessScheduler!
    var mockExecutorA: MockFairnessSchedulerExecutor!
    var mockExecutorB: MockFairnessSchedulerExecutor!
    var mockExecutorC: MockFairnessSchedulerExecutor!

    override func setUp() {
        super.setUp()
        scheduler = FairnessScheduler()
        mockExecutorA = MockFairnessSchedulerExecutor()
        mockExecutorB = MockFairnessSchedulerExecutor()
        mockExecutorC = MockFairnessSchedulerExecutor()
    }

    override func tearDown() {
        scheduler = nil
        mockExecutorA = nil
        mockExecutorB = nil
        mockExecutorC = nil
        super.tearDown()
    }

    // MARK: - Registration Tests (1.1)

    func testRegisterReturnsUniqueSessionId() {
        let idA = scheduler.register(mockExecutorA)
        let idB = scheduler.register(mockExecutorB)
        let idC = scheduler.register(mockExecutorC)

        XCTAssertNotEqual(idA, idB, "Session IDs should be unique")
        XCTAssertNotEqual(idB, idC, "Session IDs should be unique")
        XCTAssertNotEqual(idA, idC, "Session IDs should be unique")
    }

    func testRegisterReturnsMonotonicallyIncreasingIds() {
        let idA = scheduler.register(mockExecutorA)
        let idB = scheduler.register(mockExecutorB)
        let idC = scheduler.register(mockExecutorC)

        XCTAssertLessThan(idA, idB, "Session IDs should be monotonically increasing")
        XCTAssertLessThan(idB, idC, "Session IDs should be monotonically increasing")
    }

    func testRegisterMultipleExecutors() {
        let idA = scheduler.register(mockExecutorA)
        let idB = scheduler.register(mockExecutorB)

        // Both should be registered with unique IDs
        XCTAssertNotEqual(idA, idB, "Multiple executors should get unique IDs")
    }

    func testUnregisterRemovesSession() {
        // First verify that a registered session DOES get executed
        let idA = scheduler.register(mockExecutorA)

        let executedOnce = XCTestExpectation(description: "Executed once while registered")
        mockExecutorA.executeTurnHandler = { _, completion in
            executedOnce.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(idA)
        wait(for: [executedOnce], timeout: 1.0)

        XCTAssertEqual(mockExecutorA.executeTurnCallCount, 1,
                       "Registered session should execute when work is enqueued")

        // Now unregister and verify no more execution
        scheduler.unregister(sessionId: idA)
        mockExecutorA.reset()

        // Enqueuing work for unregistered session should be a no-op
        scheduler.sessionDidEnqueueWork(idA)

        // Give scheduler a chance to (incorrectly) execute
        let noExecution = XCTestExpectation(description: "No execution after unregister")
        noExecution.isInverted = true
        mockExecutorA.executeTurnHandler = { _, _ in
            noExecution.fulfill()
        }
        wait(for: [noExecution], timeout: 0.2)

        XCTAssertEqual(mockExecutorA.executeTurnCallCount, 0,
                       "Unregistered session should not execute")
    }

    func testUnregisterCallsCleanupOnExecutor() {
        let idA = scheduler.register(mockExecutorA)
        scheduler.unregister(sessionId: idA)

        XCTAssertTrue(mockExecutorA.cleanupCalled,
                      "cleanupForUnregistration should be called on unregister")
    }

    func testUnregisterNonexistentSessionIsNoOp() {
        // Register a real session first
        let idA = scheduler.register(mockExecutorA)

        // Unregistering non-existent session should not crash or affect existing sessions
        scheduler.unregister(sessionId: 999)

        // Verify the existing session still works
        let expectation = XCTestExpectation(description: "Existing session still works")
        mockExecutorA.executeTurnHandler = { _, completion in
            expectation.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(idA)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockExecutorA.executeTurnCallCount, 1,
                       "Existing session should still work after unregistering non-existent session")
    }

    func testSessionIdNoReuseAfterUnregistration() {
        let idA = scheduler.register(mockExecutorA)
        scheduler.unregister(sessionId: idA)

        let idB = scheduler.register(mockExecutorB)

        XCTAssertNotEqual(idA, idB, "Session IDs should never be reused")
        XCTAssertGreaterThan(idB, idA, "New ID should be greater than unregistered ID")
    }
}

/// Tests for FairnessScheduler busy list management.
/// (see: testing.md Section 1.2)
final class FairnessSchedulerBusyListTests: XCTestCase {

    var scheduler: FairnessScheduler!
    var mockExecutorA: MockFairnessSchedulerExecutor!
    var mockExecutorB: MockFairnessSchedulerExecutor!
    var mockExecutorC: MockFairnessSchedulerExecutor!

    override func setUp() {
        super.setUp()
        scheduler = FairnessScheduler()
        mockExecutorA = MockFairnessSchedulerExecutor()
        mockExecutorB = MockFairnessSchedulerExecutor()
        mockExecutorC = MockFairnessSchedulerExecutor()
    }

    override func tearDown() {
        scheduler = nil
        mockExecutorA = nil
        mockExecutorB = nil
        mockExecutorC = nil
        super.tearDown()
    }

    // MARK: - Busy List Tests (1.2)

    func testEnqueueWorkAddsToBusyList() {
        mockExecutorA.turnResult = .completed
        let idA = scheduler.register(mockExecutorA)

        let expectation = XCTestExpectation(description: "Turn executed")
        mockExecutorA.executeTurnHandler = { budget, completion in
            expectation.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(idA)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mockExecutorA.executeTurnCallCount, 1,
                       "Session should get a turn after enqueueing work")
    }

    func testEnqueueWorkNoDuplicates() {
        mockExecutorA.turnResult = .completed
        let idA = scheduler.register(mockExecutorA)

        var turnCount = 0
        let expectation = XCTestExpectation(description: "Single turn executed")
        mockExecutorA.executeTurnHandler = { budget, completion in
            turnCount += 1
            if turnCount == 1 {
                expectation.fulfill()
            }
            completion(.completed)
        }

        // Enqueue work multiple times before execution
        scheduler.sessionDidEnqueueWork(idA)
        scheduler.sessionDidEnqueueWork(idA)
        scheduler.sessionDidEnqueueWork(idA)

        wait(for: [expectation], timeout: 1.0)

        // Should only execute once (no duplicates in busy list)
        XCTAssertEqual(turnCount, 1,
                       "Multiple enqueues before execution should not create duplicates")
    }

    func testBusyListMaintainsFIFOOrder() {
        // Configure all to yield so we can observe order
        mockExecutorA.turnResult = .completed
        mockExecutorB.turnResult = .completed
        mockExecutorC.turnResult = .completed

        let idA = scheduler.register(mockExecutorA)
        let idB = scheduler.register(mockExecutorB)
        let idC = scheduler.register(mockExecutorC)

        var executionOrder: [String] = []
        let allDone = XCTestExpectation(description: "All turns executed")
        allDone.expectedFulfillmentCount = 3

        mockExecutorA.executeTurnHandler = { _, completion in
            executionOrder.append("A")
            allDone.fulfill()
            completion(.completed)
        }
        mockExecutorB.executeTurnHandler = { _, completion in
            executionOrder.append("B")
            allDone.fulfill()
            completion(.completed)
        }
        mockExecutorC.executeTurnHandler = { _, completion in
            executionOrder.append("C")
            allDone.fulfill()
            completion(.completed)
        }

        // Enqueue in order A, B, C
        scheduler.sessionDidEnqueueWork(idA)
        scheduler.sessionDidEnqueueWork(idB)
        scheduler.sessionDidEnqueueWork(idC)

        wait(for: [allDone], timeout: 2.0)

        XCTAssertEqual(executionOrder, ["A", "B", "C"],
                       "Sessions should execute in FIFO order")
    }

    func testEmptyBusyListNoExecution() {
        // First verify that enqueueing work DOES trigger execution
        let idA = scheduler.register(mockExecutorA)

        let executedWithWork = XCTestExpectation(description: "Executed when work enqueued")
        mockExecutorA.executeTurnHandler = { _, completion in
            executedWithWork.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(idA)
        wait(for: [executedWithWork], timeout: 1.0)

        XCTAssertEqual(mockExecutorA.executeTurnCallCount, 1,
                       "Session should execute when work is enqueued")

        // Now register a new session but don't enqueue work
        let idB = scheduler.register(mockExecutorB)

        let noExecutionWithoutWork = XCTestExpectation(description: "No execution without work")
        noExecutionWithoutWork.isInverted = true

        mockExecutorB.executeTurnHandler = { _, _ in
            noExecutionWithoutWork.fulfill()
        }

        // Don't call sessionDidEnqueueWork for B
        wait(for: [noExecutionWithoutWork], timeout: 0.2)

        XCTAssertEqual(mockExecutorB.executeTurnCallCount, 0,
                       "Session should not execute without enqueued work")
    }
}

/// Tests for FairnessScheduler turn execution flow.
/// (see: testing.md Section 1.3)
final class FairnessSchedulerTurnExecutionTests: XCTestCase {

    var scheduler: FairnessScheduler!
    var mockExecutorA: MockFairnessSchedulerExecutor!
    var mockExecutorB: MockFairnessSchedulerExecutor!

    override func setUp() {
        super.setUp()
        scheduler = FairnessScheduler()
        mockExecutorA = MockFairnessSchedulerExecutor()
        mockExecutorB = MockFairnessSchedulerExecutor()
    }

    override func tearDown() {
        scheduler = nil
        mockExecutorA = nil
        mockExecutorB = nil
        super.tearDown()
    }

    // MARK: - Turn Execution Tests (1.3)

    func testYieldedResultReaddsToBusyListTail() {
        let idA = scheduler.register(mockExecutorA)
        let idB = scheduler.register(mockExecutorB)

        var aExecutionCount = 0
        var executionOrder: [String] = []
        let expectation = XCTestExpectation(description: "Multiple turns")
        expectation.expectedFulfillmentCount = 3

        mockExecutorA.executeTurnHandler = { _, completion in
            aExecutionCount += 1
            executionOrder.append("A\(aExecutionCount)")
            expectation.fulfill()
            // First time yield, second time complete
            completion(aExecutionCount == 1 ? .yielded : .completed)
        }
        mockExecutorB.executeTurnHandler = { _, completion in
            executionOrder.append("B")
            expectation.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(idA)
        scheduler.sessionDidEnqueueWork(idB)

        wait(for: [expectation], timeout: 2.0)

        // A yields, goes to back, B runs, then A runs again
        XCTAssertEqual(executionOrder, ["A1", "B", "A2"],
                       "Yielded session should go to back of queue")
    }

    func testCompletedResultDoesNotReaddWithoutNewWork() {
        let idA = scheduler.register(mockExecutorA)

        var executionCount = 0
        let expectation = XCTestExpectation(description: "Single execution")

        mockExecutorA.executeTurnHandler = { _, completion in
            executionCount += 1
            expectation.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(idA)

        wait(for: [expectation], timeout: 1.0)

        // Wait a bit more to ensure no additional executions
        let noMoreExecutions = XCTestExpectation(description: "No more")
        noMoreExecutions.isInverted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if executionCount > 1 {
                noMoreExecutions.fulfill()
            }
        }
        wait(for: [noMoreExecutions], timeout: 0.2)

        XCTAssertEqual(executionCount, 1,
                       "Completed session should not be re-added without new work")
    }

    func testBlockedResultDoesNotReaddToBusyList() {
        let idA = scheduler.register(mockExecutorA)

        var executionCount = 0
        let expectation = XCTestExpectation(description: "Blocked execution")

        mockExecutorA.executeTurnHandler = { _, completion in
            executionCount += 1
            expectation.fulfill()
            completion(.blocked)
        }

        scheduler.sessionDidEnqueueWork(idA)

        wait(for: [expectation], timeout: 1.0)

        // Wait to ensure no re-execution
        let noMoreExecutions = XCTestExpectation(description: "No more")
        noMoreExecutions.isInverted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if executionCount > 1 {
                noMoreExecutions.fulfill()
            }
        }
        wait(for: [noMoreExecutions], timeout: 0.2)

        XCTAssertEqual(executionCount, 1,
                       "Blocked session should not be re-added until unblocked")
    }

    func testExecuteTurnCalledWithCorrectBudget() {
        let idA = scheduler.register(mockExecutorA)

        let expectation = XCTestExpectation(description: "Turn executed")
        mockExecutorA.executeTurnHandler = { budget, completion in
            XCTAssertEqual(budget, 500, "Default token budget should be 500")
            expectation.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(idA)

        wait(for: [expectation], timeout: 1.0)
    }
}

/// Tests for FairnessScheduler round-robin fairness guarantees.
/// (see: testing.md Section 1.4)
final class FairnessSchedulerRoundRobinTests: XCTestCase {

    var scheduler: FairnessScheduler!
    var executors: [MockFairnessSchedulerExecutor]!
    var sessionIds: [UInt64]!

    override func setUp() {
        super.setUp()
        scheduler = FairnessScheduler()
        executors = (0..<3).map { _ in MockFairnessSchedulerExecutor() }
        sessionIds = executors.map { scheduler.register($0) }
    }

    override func tearDown() {
        scheduler = nil
        executors = nil
        sessionIds = nil
        super.tearDown()
    }

    // MARK: - Round-Robin Tests (1.4)

    func testThreeSessionsRoundRobin() {
        var executionOrder: [Int] = []
        let expectation = XCTestExpectation(description: "Round robin")
        expectation.expectedFulfillmentCount = 6  // Each session twice

        for (index, executor) in executors.enumerated() {
            var callCount = 0
            executor.executeTurnHandler = { _, completion in
                callCount += 1
                executionOrder.append(index)
                expectation.fulfill()
                // Yield twice, then complete
                completion(callCount < 2 ? .yielded : .completed)
            }
        }

        // Enqueue work for all sessions
        for id in sessionIds {
            scheduler.sessionDidEnqueueWork(id)
        }

        wait(for: [expectation], timeout: 3.0)

        // Should be: 0, 1, 2, 0, 1, 2 (round robin)
        XCTAssertEqual(executionOrder, [0, 1, 2, 0, 1, 2],
                       "Sessions should execute in round-robin order")
    }

    func testSingleSessionGetsAllTurns() {
        let expectation = XCTestExpectation(description: "Multiple turns")
        expectation.expectedFulfillmentCount = 3

        var turnCount = 0
        executors[0].executeTurnHandler = { _, completion in
            turnCount += 1
            expectation.fulfill()
            completion(turnCount < 3 ? .yielded : .completed)
        }

        scheduler.sessionDidEnqueueWork(sessionIds[0])

        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(turnCount, 3,
                       "Single session should get consecutive turns when alone")
    }

    func testNewSessionAddedToTail() {
        var executionOrder: [String] = []
        let expectation = XCTestExpectation(description: "New session at tail")
        expectation.expectedFulfillmentCount = 3

        // A and B are already registered
        executors[0].executeTurnHandler = { _, completion in
            executionOrder.append("A")
            expectation.fulfill()
            completion(.completed)
        }
        executors[1].executeTurnHandler = { _, completion in
            executionOrder.append("B")
            expectation.fulfill()
            completion(.completed)
        }

        // Enqueue A and B
        scheduler.sessionDidEnqueueWork(sessionIds[0])
        scheduler.sessionDidEnqueueWork(sessionIds[1])

        // Register and enqueue C (new session)
        let newExecutor = MockFairnessSchedulerExecutor()
        let newId = scheduler.register(newExecutor)
        newExecutor.executeTurnHandler = { _, completion in
            executionOrder.append("C")
            expectation.fulfill()
            completion(.completed)
        }
        scheduler.sessionDidEnqueueWork(newId)

        wait(for: [expectation], timeout: 2.0)

        // C should be at the end
        XCTAssertEqual(executionOrder, ["A", "B", "C"],
                       "New session should be added to tail of busy list")
    }
}
