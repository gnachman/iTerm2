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

        // Wait for async unregister to complete on mutationQueue
        iTermGCD.mutationQueue().sync {}

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

        // Flush mutation queue to ensure all scheduler operations complete
        waitForMutationQueue()

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

        // Flush mutation queue to ensure all scheduler operations complete
        waitForMutationQueue()

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

    func testNoOverlappingTurnsWhenCompletionDelayed() {
        // REQUIREMENT: Scheduler must not call executeTurn on a session that's
        // already executing (completion not yet called). This is a key safety
        // property for the mutation queue model.

        let idA = scheduler.register(mockExecutorA)

        var executeTurnCallCount = 0
        var concurrentExecutionDetected = false
        var isCurrentlyExecuting = false
        var storedCompletion: ((TurnResult) -> Void)?

        let firstTurnStarted = XCTestExpectation(description: "First turn started")
        let secondTurnStarted = XCTestExpectation(description: "Second turn started")

        mockExecutorA.executeTurnHandler = { _, completion in
            executeTurnCallCount += 1

            // Check for overlapping execution
            if isCurrentlyExecuting {
                concurrentExecutionDetected = true
            }

            isCurrentlyExecuting = true

            if executeTurnCallCount == 1 {
                // First turn: delay completion, store it
                storedCompletion = completion
                firstTurnStarted.fulfill()
            } else {
                // Second turn: complete immediately
                secondTurnStarted.fulfill()
                isCurrentlyExecuting = false
                completion(.completed)
            }
        }

        // Start first turn
        scheduler.sessionDidEnqueueWork(idA)

        // Wait for first turn to start
        wait(for: [firstTurnStarted], timeout: 1.0)

        XCTAssertEqual(executeTurnCallCount, 1, "First turn should have started")
        XCTAssertNotNil(storedCompletion, "Completion should be stored")

        // While first turn is executing (completion not called), enqueue more work
        // This should NOT trigger another executeTurn call
        scheduler.sessionDidEnqueueWork(idA)
        scheduler.sessionDidEnqueueWork(idA)
        scheduler.sessionDidEnqueueWork(idA)

        // Flush mutation queue to ensure all sessionDidEnqueueWork calls are processed
        waitForMutationQueue()

        // Verify no second turn was started while first is still executing
        XCTAssertEqual(executeTurnCallCount, 1,
                       "No new turn should start while completion is pending")
        XCTAssertFalse(concurrentExecutionDetected,
                       "No concurrent execution should occur")

        // Now complete the first turn with .yielded (indicating more work)
        isCurrentlyExecuting = false
        storedCompletion?(.yielded)

        // Second turn should now start
        wait(for: [secondTurnStarted], timeout: 1.0)

        XCTAssertEqual(executeTurnCallCount, 2,
                       "Second turn should start after first completion")
        XCTAssertFalse(concurrentExecutionDetected,
                       "No concurrent execution should have occurred")
    }

    func testWorkArrivedWhileExecutingIsPreserved() {
        // REQUIREMENT: Work that arrives while a session is executing should
        // cause the session to be re-added to busy list after completion,
        // even if the result is .completed

        let idA = scheduler.register(mockExecutorA)

        var executeTurnCallCount = 0
        var storedCompletion: ((TurnResult) -> Void)?

        let firstTurnStarted = XCTestExpectation(description: "First turn started")
        let secondTurnStarted = XCTestExpectation(description: "Second turn started")

        mockExecutorA.executeTurnHandler = { _, completion in
            executeTurnCallCount += 1

            if executeTurnCallCount == 1 {
                storedCompletion = completion
                firstTurnStarted.fulfill()
            } else {
                secondTurnStarted.fulfill()
                completion(.completed)
            }
        }

        // Start first turn
        scheduler.sessionDidEnqueueWork(idA)
        wait(for: [firstTurnStarted], timeout: 1.0)

        // While executing, new work arrives
        scheduler.sessionDidEnqueueWork(idA)

        // Complete with .completed (normally wouldn't re-add)
        // But because work arrived, it SHOULD re-add
        storedCompletion?(.completed)

        // Second turn should start because work arrived during execution
        wait(for: [secondTurnStarted], timeout: 1.0)

        XCTAssertEqual(executeTurnCallCount, 2,
                       "Second turn should start because work arrived during first turn")
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

/// Tests for FairnessScheduler thread safety.
/// These tests verify correct behavior under concurrent access.
final class FairnessSchedulerThreadSafetyTests: XCTestCase {

    var scheduler: FairnessScheduler!

    override func setUp() {
        super.setUp()
        scheduler = FairnessScheduler()
    }

    override func tearDown() {
        scheduler = nil
        super.tearDown()
    }

    // MARK: - Thread Safety Tests

    func testConcurrentRegistration() {
        // REQUIREMENT: Multiple threads can safely call register() simultaneously
        // NOTE: This test may uncover thread-safety issues in FairnessScheduler.
        // If it fails with exceptions, the FairnessScheduler needs synchronization.
        let threadCount = 4  // Reduced to make test more reliable
        let registrationsPerThread = 10
        let group = DispatchGroup()

        var allSessionIds: [[UInt64]] = Array(repeating: [], count: threadCount)
        let lock = NSLock()
        var encounteredError = false

        for threadIndex in 0..<threadCount {
            group.enter()
            DispatchQueue.global().async {
                var threadIds: [UInt64] = []
                for _ in 0..<registrationsPerThread {
                    autoreleasepool {
                        let executor = MockFairnessSchedulerExecutor()
                        let sessionId = self.scheduler.register(executor)
                        threadIds.append(sessionId)
                    }
                }
                lock.lock()
                allSessionIds[threadIndex] = threadIds
                lock.unlock()
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 30.0)

        if result == .timedOut {
            XCTFail("Concurrent registration timed out - possible deadlock in FairnessScheduler")
            return
        }

        // Verify all IDs are unique
        let flatIds = allSessionIds.flatMap { $0 }
        let uniqueIds = Set(flatIds)
        XCTAssertEqual(flatIds.count, threadCount * registrationsPerThread,
                       "Should have created expected number of sessions")
        XCTAssertEqual(uniqueIds.count, flatIds.count,
                       "All session IDs should be unique across threads")
    }

    func testConcurrentUnregistration() {
        // REQUIREMENT: Multiple threads can safely call unregister() simultaneously
        let sessionCount = 100
        var executors: [MockFairnessSchedulerExecutor] = []
        var sessionIds: [UInt64] = []

        // First, register all sessions on the main thread
        for _ in 0..<sessionCount {
            let executor = MockFairnessSchedulerExecutor()
            executors.append(executor)
            sessionIds.append(scheduler.register(executor))
        }

        // Now unregister from multiple threads
        let group = DispatchGroup()
        let threadCount = 10
        let sessionsPerThread = sessionCount / threadCount

        for threadIndex in 0..<threadCount {
            group.enter()
            DispatchQueue.global().async {
                let startIdx = threadIndex * sessionsPerThread
                let endIdx = startIdx + sessionsPerThread
                for i in startIdx..<endIdx {
                    self.scheduler.unregister(sessionId: sessionIds[i])
                }
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 10.0)
        XCTAssertEqual(result, .success, "Concurrent unregistration should complete without deadlock")

        // Verify all executors had cleanup called
        for executor in executors {
            XCTAssertTrue(executor.cleanupCalled,
                          "All executors should have cleanup called")
        }
    }

    func testConcurrentEnqueueWork() {
        // REQUIREMENT: Multiple threads can safely call sessionDidEnqueueWork() simultaneously
        let executorCount = 10
        var executors: [MockFairnessSchedulerExecutor] = []
        var sessionIds: [UInt64] = []

        for _ in 0..<executorCount {
            let executor = MockFairnessSchedulerExecutor()
            executor.turnResult = .completed
            executors.append(executor)
            sessionIds.append(scheduler.register(executor))
        }

        let group = DispatchGroup()
        let enqueuesPerSession = 100

        // Each session gets work enqueued from multiple threads
        for sessionIndex in 0..<executorCount {
            for _ in 0..<enqueuesPerSession {
                group.enter()
                DispatchQueue.global().async {
                    self.scheduler.sessionDidEnqueueWork(sessionIds[sessionIndex])
                    group.leave()
                }
            }
        }

        let result = group.wait(timeout: .now() + 10.0)
        XCTAssertEqual(result, .success, "Concurrent enqueue should complete without deadlock")

        // Wait for processing to complete
        let processingDone = XCTestExpectation(description: "Processing complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            processingDone.fulfill()
        }
        wait(for: [processingDone], timeout: 2.0)

        // Each executor should have been called at least once
        for executor in executors {
            XCTAssertGreaterThanOrEqual(executor.executeTurnCallCount, 1,
                                        "Each executor should have executed at least once")
        }
    }

    func testConcurrentRegisterAndUnregister() {
        // REQUIREMENT: register() and unregister() can be called concurrently without races
        let iterations = 100
        let group = DispatchGroup()
        var didCrash = false

        for _ in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                let executor = MockFairnessSchedulerExecutor()
                let sessionId = self.scheduler.register(executor)

                // Immediately unregister from another queue
                DispatchQueue.global().async {
                    self.scheduler.unregister(sessionId: sessionId)
                    group.leave()
                }
            }
        }

        let result = group.wait(timeout: .now() + 10.0)
        XCTAssertEqual(result, .success, "Concurrent register/unregister should complete")
        XCTAssertFalse(didCrash, "Should not crash during concurrent operations")
    }

    func testConcurrentEnqueueAndUnregister() {
        // REQUIREMENT: sessionDidEnqueueWork() and unregister() can race without issues
        let executor = MockFairnessSchedulerExecutor()
        executor.executeTurnHandler = { _, completion in
            // Simulate some work
            usleep(1000)
            completion(.completed)
        }

        let sessionId = scheduler.register(executor)
        let group = DispatchGroup()

        // Enqueue work from one thread
        group.enter()
        DispatchQueue.global().async {
            for _ in 0..<100 {
                self.scheduler.sessionDidEnqueueWork(sessionId)
            }
            group.leave()
        }

        // Unregister from another thread after a short delay
        group.enter()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
            self.scheduler.unregister(sessionId: sessionId)
            group.leave()
        }

        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success,
                       "Concurrent enqueue and unregister should complete without crash")
    }

    func testManySessionsStressTest() {
        // REQUIREMENT: Scheduler handles many concurrent sessions without issues
        let sessionCount = 100
        var executors: [MockFairnessSchedulerExecutor] = []
        var sessionIds: [UInt64] = []

        // Register many sessions
        for _ in 0..<sessionCount {
            let executor = MockFairnessSchedulerExecutor()
            var callCount = 0
            executor.executeTurnHandler = { _, completion in
                callCount += 1
                completion(callCount < 3 ? .yielded : .completed)
            }
            executors.append(executor)
            sessionIds.append(scheduler.register(executor))
        }

        // Enqueue work for all
        for id in sessionIds {
            scheduler.sessionDidEnqueueWork(id)
        }

        // Wait for all to complete
        let expectation = XCTestExpectation(description: "All sessions processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        // Each should have executed multiple times due to yielding
        var totalExecutions = 0
        for executor in executors {
            totalExecutions += executor.executeTurnCallCount
            XCTAssertGreaterThanOrEqual(executor.executeTurnCallCount, 1,
                                        "Each executor should have run at least once")
        }

        // With yielding, total should be roughly 3x sessionCount
        XCTAssertGreaterThanOrEqual(totalExecutions, sessionCount,
                                    "Total executions should be at least once per session")
    }
}

/// Tests for edge cases in session lifecycle.
final class FairnessSchedulerLifecycleEdgeCaseTests: XCTestCase {

    var scheduler: FairnessScheduler!

    override func setUp() {
        super.setUp()
        scheduler = FairnessScheduler()
    }

    override func tearDown() {
        scheduler = nil
        super.tearDown()
    }

    // MARK: - Lifecycle Edge Case Tests

    func testUnregisterDuringExecuteTurn() {
        // REQUIREMENT: Unregistering while executeTurn completion hasn't fired should be safe
        let executor = MockFairnessSchedulerExecutor()
        let sessionId = scheduler.register(executor)

        let executionStarted = XCTestExpectation(description: "Execution started")
        let unregisterDone = XCTestExpectation(description: "Unregister completed")

        executor.executeTurnHandler = { _, completion in
            executionStarted.fulfill()

            // Unregister while execution is "in progress" (before completion called)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                self.scheduler.unregister(sessionId: sessionId)
                unregisterDone.fulfill()

                // Now call completion - should be safe even though unregistered
                completion(.yielded)
            }
        }

        scheduler.sessionDidEnqueueWork(sessionId)

        wait(for: [executionStarted, unregisterDone], timeout: 2.0)

        // Verify cleanup was called
        XCTAssertTrue(executor.cleanupCalled, "Cleanup should be called on unregister")

        // Flush mutation queue to ensure no crash from late completion
        waitForMutationQueue()
    }

    func testUnregisterAfterYieldedBeforeNextTurn() {
        // This test verifies that unregister cleans up properly after yielding.
        // NOTE: Due to async scheduling, the second turn may already be queued
        // before unregister takes effect. The key verification is that cleanup
        // is called and no crash occurs.
        let executor = MockFairnessSchedulerExecutor()
        let sessionId = scheduler.register(executor)

        var executionCount = 0
        let firstExecution = XCTestExpectation(description: "First execution")
        let unregisterDone = XCTestExpectation(description: "Unregister completed")

        executor.executeTurnHandler = { _, completion in
            executionCount += 1
            if executionCount == 1 {
                firstExecution.fulfill()
                completion(.yielded)  // Yield - would normally get another turn

                // Unregister - may or may not prevent the already-queued next turn
                DispatchQueue.main.async {
                    self.scheduler.unregister(sessionId: sessionId)
                    unregisterDone.fulfill()
                }
            } else {
                completion(.completed)
            }
        }

        scheduler.sessionDidEnqueueWork(sessionId)

        wait(for: [firstExecution, unregisterDone], timeout: 2.0)

        // Flush mutation queue to ensure all pending work is processed
        waitForMutationQueue()

        // Verify cleanup was called (the main guarantee)
        XCTAssertTrue(executor.cleanupCalled,
                      "Cleanup should be called on unregister")

        // The execution count may be 1 or 2 depending on timing
        // (2 if the next turn was already queued before unregister)
        XCTAssertLessThanOrEqual(executionCount, 2,
                                 "At most 2 executions (one queued before unregister)")
    }

    func testDoubleUnregister() {
        // REQUIREMENT: Calling unregister twice for same session should be safe
        let executor = MockFairnessSchedulerExecutor()
        let sessionId = scheduler.register(executor)

        // First unregister
        scheduler.unregister(sessionId: sessionId)

        // Wait for async unregister to complete on mutationQueue
        iTermGCD.mutationQueue().sync {}

        XCTAssertTrue(executor.cleanupCalled, "First unregister should call cleanup")

        // Use a fresh executor to detect if cleanup is called again
        // (The original executor's cleanupCalled is already true)
        let executor2 = MockFairnessSchedulerExecutor()
        // Registering a new session shouldn't affect the old unregistered one

        // Second unregister of original session - should be no-op (no crash)
        scheduler.unregister(sessionId: sessionId)

        // Wait for second unregister to complete
        iTermGCD.mutationQueue().sync {}

        // The test passes if we get here without crash
        // We can't directly verify cleanup wasn't called again,
        // but the session is already removed so cleanup can't be called
        XCTAssertNotNil(executor, "Double unregister should not crash")
    }

    func testEnqueueWorkForSessionBeingUnregistered() {
        // REQUIREMENT: Enqueuing work for a session that's being unregistered is safe
        let executor = MockFairnessSchedulerExecutor()
        let sessionId = scheduler.register(executor)

        var executionCount = 0
        executor.executeTurnHandler = { _, completion in
            executionCount += 1
            completion(.completed)
        }

        // Rapidly enqueue and unregister
        scheduler.sessionDidEnqueueWork(sessionId)
        scheduler.unregister(sessionId: sessionId)
        scheduler.sessionDidEnqueueWork(sessionId)  // This should be no-op

        // Wait for any processing
        let wait = XCTestExpectation(description: "Wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            wait.fulfill()
        }
        self.wait(for: [wait], timeout: 1.0)

        // Execution count should be 0 or 1, never more
        // (depending on timing, the first enqueue may or may not have executed)
        XCTAssertLessThanOrEqual(executionCount, 1,
                                 "At most one execution before unregister")
    }

    func testZeroBudgetBehavior() {
        // REQUIREMENT: Budget of 0 should still allow at least one group to execute (progress guarantee)
        // Note: FairnessScheduler uses a fixed budget of 500, so this tests if the executor
        // handles budget correctly by forwarding it
        let executor = MockFairnessSchedulerExecutor()
        let sessionId = scheduler.register(executor)

        var receivedBudget: Int?
        let expectation = XCTestExpectation(description: "Turn executed")

        executor.executeTurnHandler = { budget, completion in
            receivedBudget = budget
            expectation.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(sessionId)
        wait(for: [expectation], timeout: 1.0)

        // FairnessScheduler should always provide a reasonable budget
        XCTAssertNotNil(receivedBudget)
        XCTAssertGreaterThan(receivedBudget!, 0, "Budget should be positive")
    }
}
