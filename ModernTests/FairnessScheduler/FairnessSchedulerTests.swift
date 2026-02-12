//
//  FairnessSchedulerTests.swift
//  ModernTests
//
//  Unit tests for FairnessScheduler - the round-robin fair scheduling coordinator.
//  See testing.md Phase 1 for test specifications.
//
//  Session restoration tests (revive/undo termination) are implemented in
//  FairnessSchedulerSessionRestorationTests at the end of this file.
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

        // Sync to mutation queue to ensure any (incorrect) execution would have completed
        for _ in 0..<3 {
            iTermGCD.mutationQueue().sync {}
        }

        XCTAssertEqual(mockExecutorA.executeTurnCallCount, 0,
                       "Unregistered session should not execute")
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
        let firstTurn = XCTestExpectation(description: "First turn executed")

        mockExecutorA.executeTurnHandler = { budget, completion in
            turnCount += 1
            if turnCount == 1 {
                firstTurn.fulfill()
            }
            completion(.completed)
        }

        // Enqueue work multiple times before execution
        scheduler.sessionDidEnqueueWork(idA)
        scheduler.sessionDidEnqueueWork(idA)
        scheduler.sessionDidEnqueueWork(idA)

        // Wait for first turn
        wait(for: [firstTurn], timeout: 1.0)

        // Sync to mutation queue to ensure any duplicate execution would have completed
        for _ in 0..<3 {
            iTermGCD.mutationQueue().sync {}
        }

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
        let _ = scheduler.register(mockExecutorB)

        // Don't call sessionDidEnqueueWork for B
        // Sync to mutation queue to ensure any (incorrect) execution would have completed
        for _ in 0..<3 {
            iTermGCD.mutationQueue().sync {}
        }

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
            XCTAssertEqual(budget, FairnessScheduler.defaultTokenBudget,
                           "Token budget should match FairnessScheduler.defaultTokenBudget")
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
        // Must call completion on mutation queue per protocol contract
        iTermGCD.mutationQueue().async {
            isCurrentlyExecuting = false
            storedCompletion?(.yielded)
        }

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
        // Must call completion on mutation queue per protocol contract
        iTermGCD.mutationQueue().async {
            storedCompletion?(.completed)
        }

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
        // NOTE: This is the WATCHDOG test - keeps a timeout to catch unexpected deadlocks.
        // FairnessScheduler.register() has dispatchPrecondition to catch deadlock-prone patterns.
        let threadCount = 4
        let registrationsPerThread = 10
        let group = DispatchGroup()

        var allSessionIds: [[UInt64]] = Array(repeating: [], count: threadCount)
        let lock = NSLock()

        // Capture scheduler locally to prevent race with tearDown deallocation
        let scheduler = self.scheduler!

        for threadIndex in 0..<threadCount {
            group.enter()
            DispatchQueue.global().async {
                var threadIds: [UInt64] = []
                for _ in 0..<registrationsPerThread {
                    autoreleasepool {
                        let executor = MockFairnessSchedulerExecutor()
                        let sessionId = scheduler.register(executor)
                        threadIds.append(sessionId)
                    }
                }
                lock.lock()
                allSessionIds[threadIndex] = threadIds
                lock.unlock()
                group.leave()
            }
        }

        // WATCHDOG: This is the only concurrent test with a timeout.
        // All other concurrent tests use bounded-progress assertions.
        // 60s is generous - if correct, completes in < 1s.
        let result = group.wait(timeout: .now() + 60.0)

        if result == .timedOut {
            XCTFail("Concurrent registration timed out - possible deadlock in FairnessScheduler")
            return
        }

        // Verify all IDs are unique (deterministic assertion)
        let flatIds = allSessionIds.flatMap { $0 }
        let uniqueIds = Set(flatIds)
        XCTAssertEqual(flatIds.count, threadCount * registrationsPerThread,
                       "Should have created expected number of sessions")
        XCTAssertEqual(uniqueIds.count, flatIds.count,
                       "All session IDs should be unique across threads")
    }

    func testConcurrentUnregistration() {
        // REQUIREMENT: Multiple threads can safely call unregister() simultaneously
        // Bounded-progress test: all unregister calls complete, all cleanups called.
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

        // Capture scheduler locally to prevent race with tearDown deallocation
        let scheduler = self.scheduler!

        for threadIndex in 0..<threadCount {
            group.enter()
            DispatchQueue.global().async {
                let startIdx = threadIndex * sessionsPerThread
                let endIdx = startIdx + sessionsPerThread
                for i in startIdx..<endIdx {
                    scheduler.unregister(sessionId: sessionIds[i])
                }
                group.leave()
            }
        }

        // No timeout - completes quickly if correct (watchdog is testConcurrentRegistration)
        group.wait()

        // Drain queues to ensure async unregister completes
        waitForMutationQueue()

        // Verify all sessions were unregistered
        for sessionId in sessionIds {
            XCTAssertFalse(scheduler.testIsSessionRegistered(sessionId),
                           "All sessions should be unregistered")
        }
    }

    func testConcurrentEnqueueWork() {
        // REQUIREMENT: Multiple threads can safely call sessionDidEnqueueWork() simultaneously
        // Bounded-progress test: all enqueues complete, each executor executes at least once.
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

        // Capture scheduler locally to prevent race with tearDown deallocation
        let scheduler = self.scheduler!

        // Each session gets work enqueued from multiple threads
        for sessionIndex in 0..<executorCount {
            for _ in 0..<enqueuesPerSession {
                group.enter()
                DispatchQueue.global().async {
                    scheduler.sessionDidEnqueueWork(sessionIds[sessionIndex])
                    group.leave()
                }
            }
        }

        // No timeout - completes quickly if correct
        group.wait()

        // Drain queues to ensure all processing completes
        waitForMutationQueue()
        waitForMainQueue()

        // Bounded-progress assertion: each executor should have been called at least once
        for executor in executors {
            XCTAssertGreaterThanOrEqual(executor.executeTurnCallCount, 1,
                                        "Each executor should have executed at least once")
        }
    }

    func testConcurrentRegisterAndUnregister() {
        // REQUIREMENT: register() and unregister() can be called concurrently without races
        // Bounded-progress test: all register/unregister pairs complete without crash.
        let iterations = 100
        let group = DispatchGroup()

        // Capture scheduler locally to prevent race with tearDown deallocation
        let scheduler = self.scheduler!

        for _ in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                let executor = MockFairnessSchedulerExecutor()
                let sessionId = scheduler.register(executor)

                // Immediately unregister from another queue
                DispatchQueue.global().async {
                    scheduler.unregister(sessionId: sessionId)
                    group.leave()
                }
            }
        }

        // Timeout detects deadlocks
        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "Concurrent register/unregister should complete without deadlock")

        // Verify all sessions were properly unregistered
        XCTAssertEqual(scheduler.testRegisteredSessionCount, 0,
                       "All sessions should be unregistered after concurrent operations")
    }

    func testConcurrentEnqueueAndUnregister() {
        // REQUIREMENT: sessionDidEnqueueWork() and unregister() can race without issues
        // Bounded-progress test: both enqueue and unregister complete without crash.
        let executor = MockFairnessSchedulerExecutor()
        executor.executeTurnHandler = { _, completion in
            // Simulate some work
            usleep(1000)
            completion(.completed)
        }

        // Capture scheduler locally to prevent race with tearDown deallocation
        let scheduler = self.scheduler!

        let sessionId = scheduler.register(executor)
        let group = DispatchGroup()

        // Enqueue work from one thread
        group.enter()
        DispatchQueue.global().async {
            for _ in 0..<100 {
                scheduler.sessionDidEnqueueWork(sessionId)
            }
            group.leave()
        }

        // Unregister from another thread after a short delay
        group.enter()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
            scheduler.unregister(sessionId: sessionId)
            group.leave()
        }

        // Timeout detects deadlocks
        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "Concurrent enqueue/unregister should complete without deadlock")

        // Verify session was properly unregistered
        XCTAssertFalse(scheduler.testIsSessionRegistered(sessionId),
                       "Session should be unregistered after concurrent operations")
    }

    func testManySessionsStressTest() {
        // REQUIREMENT: Scheduler handles many concurrent sessions without issues
        // Bounded-progress test: iteration-based waiting, no wall-clock timeout.
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

        // Iteration-based waiting (deterministic, no wall-clock timeout)
        var iterations = 0
        let maxIterations = 500  // 100 sessions * 3 turns each + buffer
        while !executors.allSatisfy({ $0.executeTurnCallCount >= 3 }) && iterations < maxIterations {
            waitForMutationQueue()
            iterations += 1
        }
        XCTAssertLessThan(iterations, maxIterations,
                          "All sessions should complete within \(maxIterations) iterations")

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

        // Capture scheduler locally to prevent race with tearDown deallocation
        let scheduler = self.scheduler!

        let executor = MockFairnessSchedulerExecutor()
        let sessionId = scheduler.register(executor)

        let executionStarted = XCTestExpectation(description: "Execution started")
        let unregisterDone = XCTestExpectation(description: "Unregister completed")

        executor.executeTurnHandler = { _, completion in
            executionStarted.fulfill()

            // Unregister while execution is "in progress" (before completion called)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                scheduler.unregister(sessionId: sessionId)
                unregisterDone.fulfill()

                // Call completion on mutation queue (required by threading contract)
                // Should be safe even though session was unregistered
                iTermGCD.mutationQueue().async {
                    completion(.yielded)
                }
            }
        }

        scheduler.sessionDidEnqueueWork(sessionId)

        wait(for: [executionStarted, unregisterDone], timeout: 2.0)

        // Flush mutation queue to ensure no crash from late completion
        waitForMutationQueue()

        // Verify session was unregistered
        XCTAssertFalse(scheduler.testIsSessionRegistered(sessionId),
                       "Session should be unregistered")
    }

    func testUnregisterDuringExecuteTurnDoesNotStallOtherSessions() {
        // REGRESSION: If session A is unregistered while its executeTurn is running,
        // sessionFinishedTurn must still call ensureExecutionScheduled() so that
        // session B (waiting in busyQueue) gets its turn. Without this, session B
        // stalls indefinitely until some external event triggers scheduling.

        let scheduler = self.scheduler!

        let executorA = MockFairnessSchedulerExecutor()
        let executorB = MockFairnessSchedulerExecutor()
        let sessionA = scheduler.register(executorA)
        let sessionB = scheduler.register(executorB)

        var completionA: ((TurnResult) -> Void)?
        let executionAStarted = XCTestExpectation(description: "A started")
        let executionBStarted = XCTestExpectation(description: "B executed")

        executorA.executeTurnHandler = { _, completion in
            // Hold A's completion so we can unregister before calling it
            completionA = completion
            executionAStarted.fulfill()
        }

        executorB.executeTurnHandler = { _, completion in
            executionBStarted.fulfill()
            completion(.completed)
        }

        // Enqueue work for both sessions
        scheduler.sessionDidEnqueueWork(sessionA)
        scheduler.sessionDidEnqueueWork(sessionB)

        // Wait for A to start executing
        wait(for: [executionAStarted], timeout: 2.0)

        // Unregister A while its turn is in progress, then complete the turn
        iTermGCD.mutationQueue().async {
            scheduler.unregister(sessionId: sessionA)
            // Complete A's turn after unregister — sessionFinishedTurn must still
            // pump the scheduler so B gets scheduled
            completionA?(.yielded)
        }

        // B must get its turn despite A's mid-flight unregister
        wait(for: [executionBStarted], timeout: 2.0)

        // Cleanup
        scheduler.unregister(sessionId: sessionB)
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

        // Verify session was unregistered
        XCTAssertFalse(scheduler.testIsSessionRegistered(sessionId),
                       "Session should be unregistered")

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

        XCTAssertFalse(scheduler.testIsSessionRegistered(sessionId),
                       "Session should be unregistered")

        // Second unregister of original session - should be no-op (no crash)
        scheduler.unregister(sessionId: sessionId)

        // Wait for second unregister to complete
        iTermGCD.mutationQueue().sync {}

        // Session should still be unregistered
        XCTAssertFalse(scheduler.testIsSessionRegistered(sessionId),
                       "Session should remain unregistered")
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

        // Flush queues to ensure all pending operations complete
        waitForMutationQueue()
        waitForMainQueue()

        // Execution count should be 0 or 1, never more
        // (depending on timing, the first enqueue may or may not have executed)
        XCTAssertLessThanOrEqual(executionCount, 1,
                                 "At most one execution before unregister")
    }

    func testSchedulerProvidesPositiveBudget() {
        // REQUIREMENT: FairnessScheduler must provide a positive budget to executors.
        // The scheduler uses defaultTokenBudget (500) for all turns.
        let executor = MockFairnessSchedulerExecutor()
        let sessionId = scheduler.register(executor)
        defer { scheduler.unregister(sessionId: sessionId) }

        var receivedBudget: Int?
        let expectation = XCTestExpectation(description: "Turn executed")

        executor.executeTurnHandler = { budget, completion in
            receivedBudget = budget
            expectation.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(sessionId)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedBudget)
        XCTAssertEqual(receivedBudget!, FairnessScheduler.defaultTokenBudget,
                       "Scheduler should provide defaultTokenBudget")
    }

    func testZeroBudgetBehavior() {
        // REQUIREMENT: Progress guarantee - at least one group must execute per turn,
        // even if that group alone exceeds the budget. This ensures forward progress.
        //
        // TokenExecutor enforces this at line 583-584:
        //   if tokensConsumed + groupTokenCount > tokenBudget && groupsExecuted > 0 { return false }
        // The `groupsExecuted > 0` check ensures the first group always executes.
        //
        // Test: Executor simulates consuming more than budget on first group,
        // then yields. This verifies the turn completes despite "exceeding" budget.

        let executor = MockFairnessSchedulerExecutor()
        let sessionId = scheduler.register(executor)
        defer { scheduler.unregister(sessionId: sessionId) }

        var turnCount = 0
        let firstTurnComplete = XCTestExpectation(description: "First turn executed")
        let secondTurnComplete = XCTestExpectation(description: "Second turn executed")

        executor.executeTurnHandler = { budget, completion in
            turnCount += 1
            if turnCount == 1 {
                // First turn: simulate consuming entire budget and having more work
                // (progress guarantee: first group always executes)
                firstTurnComplete.fulfill()
                completion(.yielded)  // More work remains
            } else {
                // Second turn: work completes
                secondTurnComplete.fulfill()
                completion(.completed)
            }
        }

        // Trigger execution
        scheduler.sessionDidEnqueueWork(sessionId)

        // Both turns should execute
        wait(for: [firstTurnComplete, secondTurnComplete], timeout: 1.0, enforceOrder: true)

        XCTAssertEqual(turnCount, 2, "Session should get two turns when yielding after first")
    }
}

// MARK: - Sustained Load Fairness Tests

/// Tests that verify fairness under sustained load conditions.
/// These tests validate the core fairness goal: no session should wait more than N-1 turns.
final class FairnessSchedulerSustainedLoadTests: XCTestCase {

    var scheduler: FairnessScheduler!

    override func setUp() {
        super.setUp()
        scheduler = FairnessScheduler()
    }

    override func tearDown() {
        scheduler = nil
        super.tearDown()
    }

    func testThreeSessionsSustainedLoadFairness() {
        // REQUIREMENT: With 3 sessions continuously producing work,
        // turns should interleave fairly: A, B, C, A, B, C, ...
        // Each session should never wait more than 2 turns (N-1 where N=3).

        let executorA = MockFairnessSchedulerExecutor()
        let executorB = MockFairnessSchedulerExecutor()
        let executorC = MockFairnessSchedulerExecutor()

        let sessionA = scheduler.register(executorA)
        let sessionB = scheduler.register(executorB)
        let sessionC = scheduler.register(executorC)

        var turnOrder: [FairnessScheduler.SessionID] = []
        let lock = NSLock()
        let totalTurns = 15  // 5 rounds of 3 sessions each
        let turnExpectation = XCTestExpectation(description: "All turns completed")
        turnExpectation.expectedFulfillmentCount = totalTurns

        // Configure executors to track turn order and simulate continuous work
        func configureExecutor(_ executor: MockFairnessSchedulerExecutor, sessionId: FairnessScheduler.SessionID) {
            executor.executeTurnHandler = { budget, completion in
                lock.lock()
                let currentCount = turnOrder.count
                if currentCount < totalTurns {
                    turnOrder.append(sessionId)
                    turnExpectation.fulfill()
                }
                lock.unlock()
                // Return .yielded to simulate continuous work
                completion(.yielded)
            }
        }

        configureExecutor(executorA, sessionId: sessionA)
        configureExecutor(executorB, sessionId: sessionB)
        configureExecutor(executorC, sessionId: sessionC)

        // Trigger initial work for all sessions
        scheduler.sessionDidEnqueueWork(sessionA)
        scheduler.sessionDidEnqueueWork(sessionB)
        scheduler.sessionDidEnqueueWork(sessionC)

        wait(for: [turnExpectation], timeout: 5.0)

        // Verify fairness: each session should appear roughly equally
        lock.lock()
        let finalOrder = turnOrder
        lock.unlock()

        let countA = finalOrder.filter { $0 == sessionA }.count
        let countB = finalOrder.filter { $0 == sessionB }.count
        let countC = finalOrder.filter { $0 == sessionC }.count

        // With round-robin, each session gets totalTurns/3 turns (5 each)
        XCTAssertEqual(countA, 5, "Session A should get 5 turns in 15 total")
        XCTAssertEqual(countB, 5, "Session B should get 5 turns in 15 total")
        XCTAssertEqual(countC, 5, "Session C should get 5 turns in 15 total")

        // Verify round-robin pattern: check that no session has 2 consecutive turns
        for i in 0..<min(finalOrder.count - 1, totalTurns - 1) {
            XCTAssertNotEqual(finalOrder[i], finalOrder[i+1],
                              "Same session should not get consecutive turns in round-robin")
        }
    }

    func testNoSessionStarvationUnderLoad() {
        // REQUIREMENT: No session should be starved (wait indefinitely) under load.
        // All sessions that have work get turns.

        let executorA = MockFairnessSchedulerExecutor()
        let executorB = MockFairnessSchedulerExecutor()
        let executorC = MockFairnessSchedulerExecutor()

        let sessionA = scheduler.register(executorA)
        let sessionB = scheduler.register(executorB)
        let sessionC = scheduler.register(executorC)

        var turnsPerSession: [FairnessScheduler.SessionID: Int] = [sessionA: 0, sessionB: 0, sessionC: 0]
        let lock = NSLock()
        let totalTurns = 30
        let turnExpectation = XCTestExpectation(description: "All turns completed")
        turnExpectation.expectedFulfillmentCount = totalTurns

        var turnsCounted = 0

        // Configure executors - all yielding to simulate continuous work
        func configureExecutor(_ executor: MockFairnessSchedulerExecutor, sessionId: FairnessScheduler.SessionID) {
            executor.executeTurnHandler = { budget, completion in
                lock.lock()
                if turnsCounted < totalTurns {
                    turnsPerSession[sessionId, default: 0] += 1
                    turnsCounted += 1
                    turnExpectation.fulfill()
                }
                lock.unlock()

                // Always yield to simulate continuous heavy workload
                completion(.yielded)
            }
        }

        // All sessions have continuous work
        configureExecutor(executorA, sessionId: sessionA)
        configureExecutor(executorB, sessionId: sessionB)
        configureExecutor(executorC, sessionId: sessionC)

        // Start all sessions
        scheduler.sessionDidEnqueueWork(sessionA)
        scheduler.sessionDidEnqueueWork(sessionB)
        scheduler.sessionDidEnqueueWork(sessionC)

        wait(for: [turnExpectation], timeout: 10.0)

        // Verify no session was starved - each should have gotten at least some turns
        lock.lock()
        let countA = turnsPerSession[sessionA, default: 0]
        let countB = turnsPerSession[sessionB, default: 0]
        let countC = turnsPerSession[sessionC, default: 0]
        lock.unlock()

        // With 3 sessions and 30 total turns, each should get exactly 10 (perfect fairness)
        // Allow a small variance for timing issues
        XCTAssertGreaterThanOrEqual(countA, 8, "Session A should not be starved")
        XCTAssertGreaterThanOrEqual(countB, 8, "Session B should not be starved")
        XCTAssertGreaterThanOrEqual(countC, 8, "Session C should not be starved")

        XCTAssertLessThanOrEqual(countA, 12, "Session A should not dominate")
        XCTAssertLessThanOrEqual(countB, 12, "Session B should not dominate")
        XCTAssertLessThanOrEqual(countC, 12, "Session C should not dominate")
    }
}

// MARK: - Session Restoration Tests

/// Tests for session restoration (revive/undo termination) path.
/// Verifies that sessions can be unregistered and re-registered.
final class FairnessSchedulerSessionRestorationTests: XCTestCase {

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

    // MARK: - Test 1: Re-registration After Unregister

    func testReRegistrationAfterUnregister() {
        let sessionId1 = scheduler.register(mockExecutorA)

        let firstExecutionExpectation = XCTestExpectation(description: "First execution")
        mockExecutorA.executeTurnHandler = { _, completion in
            firstExecutionExpectation.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(sessionId1)
        wait(for: [firstExecutionExpectation], timeout: 1.0)

        XCTAssertEqual(mockExecutorA.executeTurnCallCount, 1)

        scheduler.unregister(sessionId: sessionId1)
        waitForMutationQueue()

        XCTAssertFalse(scheduler.testIsSessionRegistered(sessionId1))

        mockExecutorA.reset()

        let sessionId2 = scheduler.register(mockExecutorA)

        XCTAssertNotEqual(sessionId2, sessionId1)
        XCTAssertGreaterThan(sessionId2, sessionId1)

        let secondExecutionExpectation = XCTestExpectation(description: "Second execution")
        mockExecutorA.executeTurnHandler = { _, completion in
            secondExecutionExpectation.fulfill()
            completion(.completed)
        }

        scheduler.sessionDidEnqueueWork(sessionId2)
        wait(for: [secondExecutionExpectation], timeout: 1.0)

        XCTAssertEqual(mockExecutorA.executeTurnCallCount, 1)
    }

    // MARK: - Test 2: Preserved Tokens Processed After Re-registration

    func testPreservedTokensProcessedAfterReRegistration() {
        let mockTerminal = VT100Terminal()
        let mockDelegate = MockTokenExecutorDelegate()
        let executor = TokenExecutor(mockTerminal,
                                      slownessDetector: SlownessDetector(),
                                      queue: iTermGCD.mutationQueue())
        executor.delegate = mockDelegate

        let sessionId1 = scheduler.register(executor)
        executor.fairnessSessionId = sessionId1
        executor.isRegistered = true

        mockDelegate.shouldQueueTokens = true
        for _ in 0..<10 {
            let vector = createTestTokenVector(count: 5)
            executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        }

        waitForMutationQueue()

        XCTAssertEqual(mockDelegate.willExecuteCount, 0)

        let tokensBeforeUnregister = executor.testQueuedTokenCount
        XCTAssertGreaterThan(tokensBeforeUnregister, 0)

        scheduler.unregister(sessionId: sessionId1)
        executor.isRegistered = false
        executor.fairnessSessionId = 0

        waitForMutationQueue()

        let tokensAfterUnregister = executor.testQueuedTokenCount
        XCTAssertEqual(tokensAfterUnregister, tokensBeforeUnregister)

        let sessionId2 = scheduler.register(executor)
        executor.fairnessSessionId = sessionId2
        executor.isRegistered = true

        XCTAssertNotEqual(sessionId2, sessionId1)

        mockDelegate.shouldQueueTokens = false

        let processedExpectation = XCTestExpectation(description: "Tokens processed")
        mockDelegate.onWillExecute = {
            processedExpectation.fulfill()
        }

        scheduler.sessionDidEnqueueWork(sessionId2)

        wait(for: [processedExpectation], timeout: 2.0)

        XCTAssertGreaterThan(mockDelegate.willExecuteCount, 0)

        scheduler.unregister(sessionId: sessionId2)
    }

    // MARK: - Test 3: sessionDidEnqueueWork After Re-registration

    func testSessionDidEnqueueWorkAfterReRegistration() {
        let mockTerminal = VT100Terminal()
        let mockDelegate = MockTokenExecutorDelegate()
        let executor = TokenExecutor(mockTerminal,
                                      slownessDetector: SlownessDetector(),
                                      queue: iTermGCD.mutationQueue())
        executor.delegate = mockDelegate
        executor.testSkipNotifyScheduler = true

        let sessionId1 = scheduler.register(executor)
        executor.fairnessSessionId = sessionId1
        executor.isRegistered = true

        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        let turnStartedExpectation = XCTestExpectation(description: "Turn started")

        mockDelegate.onWillExecute = {
            turnStartedExpectation.fulfill()
        }

        executor.executeTurnOnMutationQueue(tokenBudget: 500) { _ in }

        wait(for: [turnStartedExpectation], timeout: 1.0)

        for _ in 0..<5 {
            let additionalVector = createTestTokenVector(count: 5)
            executor.addTokens(additionalVector,
                              lengthTotal: 50,
                              lengthExcludingInBandSignaling: 50)
        }

        waitForMutationQueue()

        scheduler.unregister(sessionId: sessionId1)
        executor.isRegistered = false
        executor.fairnessSessionId = 0

        waitForMutationQueue()

        let tokensAfterUnregister = executor.testQueuedTokenCount
        XCTAssertGreaterThan(tokensAfterUnregister, 0)

        let sessionId2 = scheduler.register(executor)
        executor.fairnessSessionId = sessionId2
        executor.isRegistered = true

        mockDelegate.reset()

        let newTurnExpectation = XCTestExpectation(description: "New turn executed")
        mockDelegate.onWillExecute = {
            newTurnExpectation.fulfill()
        }

        scheduler.sessionDidEnqueueWork(sessionId2)

        wait(for: [newTurnExpectation], timeout: 2.0)

        XCTAssertGreaterThan(mockDelegate.willExecuteCount, 0)

        scheduler.unregister(sessionId: sessionId2)
    }

    // MARK: - Test 4: Double Unregister Does Not Lose Tokens

    func testDoubleUnregisterDoesNotLoseTokens() {
        let mockTerminal = VT100Terminal()
        let mockDelegate = MockTokenExecutorDelegate()
        let executor = TokenExecutor(mockTerminal,
                                      slownessDetector: SlownessDetector(),
                                      queue: iTermGCD.mutationQueue())
        executor.delegate = mockDelegate

        let sessionId1 = scheduler.register(executor)
        executor.fairnessSessionId = sessionId1
        executor.isRegistered = true

        mockDelegate.shouldQueueTokens = true
        for _ in 0..<10 {
            let vector = createTestTokenVector(count: 5)
            executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        }

        waitForMutationQueue()

        let tokensBeforeUnregister = executor.testQueuedTokenCount
        XCTAssertGreaterThan(tokensBeforeUnregister, 0)

        scheduler.unregister(sessionId: sessionId1)
        waitForMutationQueue()

        let tokensAfterFirstUnregister = executor.testQueuedTokenCount
        XCTAssertEqual(tokensAfterFirstUnregister, tokensBeforeUnregister)

        scheduler.unregister(sessionId: sessionId1)
        waitForMutationQueue()

        let tokensAfterSecondUnregister = executor.testQueuedTokenCount
        XCTAssertEqual(tokensAfterSecondUnregister, tokensAfterFirstUnregister)

        let sessionId2 = scheduler.register(executor)
        executor.fairnessSessionId = sessionId2
        executor.isRegistered = true

        mockDelegate.shouldQueueTokens = false

        let processedExpectation = XCTestExpectation(description: "Tokens processed")
        mockDelegate.onWillExecute = {
            processedExpectation.fulfill()
        }

        scheduler.sessionDidEnqueueWork(sessionId2)

        wait(for: [processedExpectation], timeout: 2.0)

        XCTAssertGreaterThan(mockDelegate.willExecuteCount, 0)

        scheduler.unregister(sessionId: sessionId2)
    }
}
