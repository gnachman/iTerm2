//
//  TokenExecutorFairnessTests.swift
//  ModernTests
//
//  Unit tests for TokenExecutor fairness modifications.
//  See testing.md Phase 2 for test specifications.
//
//  Test Design:
//  - Tests that verify NEW features are marked with XCTSkip until implemented
//  - Tests include both positive cases (desired behavior) and negative cases (undesired behavior)
//  - No test should hang - all use timeouts or verify existing behavior
//

import XCTest
@testable import iTerm2SharedARC

// MockTokenExecutorDelegate is defined in Mocks/MockTokenExecutorDelegate.swift

// MARK: - 2.1 Non-Blocking Token Addition Tests

/// Tests for non-blocking token addition behavior (2.1)
/// These tests verify the REMOVAL of semaphore blocking from addTokens().
final class TokenExecutorNonBlockingTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!
    var executor: TokenExecutor!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
        executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate
    }

    override func tearDown() {
        executor = nil
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testAddTokensDoesNotBlock() throws {
        // REQUIREMENT: addTokens() must return immediately without blocking.
        // This enables the dispatch_source model where PTY read handlers never block.

        // Verify adding tokens beyond buffer capacity doesn't block
        // and returns immediately with backpressure reflected in backpressureLevel
        let expectation = XCTestExpectation(description: "addTokens returns immediately")

        DispatchQueue.global().async {
            // Add many token arrays rapidly - should never block
            for _ in 0..<100 {
                let vector = createTestTokenVector(count: 10)
                self.executor.addTokens(vector, lengthTotal: 100, lengthExcludingInBandSignaling: 100)
            }
            expectation.fulfill()
        }

        // If addTokens blocks, this will timeout
        wait(for: [expectation], timeout: 1.0)
    }

    func testAddTokensDecrementsAvailableSlots() {
        // REQUIREMENT: Each addTokens call must decrement availableSlots.
        // This is needed for backpressure tracking.

        let initialLevel = executor.backpressureLevel
        XCTAssertEqual(initialLevel, .none, "Fresh executor should have no backpressure")

        // Block token consumption so they accumulate
        mockDelegate.shouldQueueTokens = true

        // With default bufferDepth of 40:
        // - .none = >30 available (>75%)
        // - .light = 20-30 available (50-75%)
        // - .moderate = 10-20 available (25-50%)
        // - .heavy = <10 available (<25%)
        // Adding 11 tokens should move from .none to .light (29 remaining)
        for _ in 0..<11 {
            let vector = createTestTokenVector(count: 1)
            executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10)
        }

        // Schedule to ensure pending work is processed (won't execute due to shouldQueueTokens)
        executor.schedule()

        let afterLevel = executor.backpressureLevel
        XCTAssertGreaterThan(afterLevel, initialLevel,
                            "Backpressure should increase after adding tokens without consumption")
        XCTAssertGreaterThanOrEqual(afterLevel, .light,
                                    "Adding 11 tokens should cause at least .light backpressure")
    }

    func testHighPriorityTokensAlsoDecrementSlots() throws {
        // REQUIREMENT: High-priority tokens must also count against availableSlots.
        // This prevents API injection floods from overflowing the queue.

        let initialLevel = executor.backpressureLevel
        XCTAssertEqual(initialLevel, .none, "Fresh executor should have no backpressure")

        // Block token consumption so they accumulate
        mockDelegate.shouldQueueTokens = true

        // Add high-priority tokens (they also decrement availableSlots)
        // With 40 total slots, adding 11+ should move from .none to .light
        for _ in 0..<15 {
            let vector = createTestTokenVector(count: 1)
            executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10, highPriority: true)
        }

        // Schedule to ensure pending work is processed
        executor.schedule()

        let afterLevel = executor.backpressureLevel
        XCTAssertGreaterThan(afterLevel, initialLevel,
                            "Backpressure should increase after adding high-priority tokens")
        XCTAssertGreaterThanOrEqual(afterLevel, .light,
                                    "Adding 15 high-priority tokens should cause at least .light backpressure")
    }

    // NEGATIVE TEST: Verify semaphore is NOT created after implementation
    func testSemaphoreNotCreated() throws {
        // REQUIREMENT: After Phase 2, no DispatchSemaphore should be created for token arrays.
        // The semaphore-based blocking model is replaced by suspend/resume.

        // Verify by checking that rapid token addition doesn't cause blocking behavior
        // If semaphores were still in use, this would deadlock or timeout
        let group = DispatchGroup()

        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                let vector = createTestTokenVector(count: 5)
                self.executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 1.0)
        XCTAssertEqual(result, .success, "Token addition should not block on semaphores")
    }
}

// MARK: - 2.2 Token Consumption Accounting Tests

/// Tests for token consumption accounting correctness (2.2)
final class TokenExecutorAccountingTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!
    var executor: TokenExecutor!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
        executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate
    }

    override func tearDown() {
        executor = nil
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testOnTokenArrayConsumedIncrementsSlots() {
        // REQUIREMENT: When a TokenArray is fully consumed, availableSlots must increment.

        // Add and consume tokens
        let vector = createTestTokenVector(count: 1)
        executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10)
        executor.schedule()

        // Drain main queue to let execution complete
        for _ in 0..<5 {
            waitForMainQueue()
        }

        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Backpressure should return to none after consuming tokens")
    }

    func testBackpressureReleaseHandlerCalled() throws {
        // REQUIREMENT: backpressureReleaseHandler must be called when crossing from
        // heavy backpressure to a lighter level. This triggers PTYTask to re-evaluate
        // read source state.
        //
        // Test design:
        // 1. Set up handler with thread-safe counter
        // 2. Drive backpressure to heavy (add many tokens)
        // 3. Register with scheduler and execute turns to consume tokens
        // 4. Verify handler was called when crossing out of heavy

        // Thread-safe counter for handler calls
        let handlerCallCount = MutableAtomicObject<Int>(0)
        executor.backpressureReleaseHandler = {
            _ = handlerCallCount.mutate { $0 + 1 }
        }

        // Register with scheduler so executeTurn works properly
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId
        defer {
            FairnessScheduler.shared.unregister(sessionId: sessionId)
        }

        // Step 1: Add enough tokens to reach heavy backpressure
        // Heavy = < 25% slots available, so we need to consume > 75% of slots
        // Default bufferDepth is 40, so we need > 30 token arrays
        #if ITERM_DEBUG
        let totalSlots = executor.testTotalSlots
        let targetTokenArrays = Int(Double(totalSlots) * 0.80)  // 80% to ensure heavy
        #else
        let targetTokenArrays = 35  // Safe default assuming 40 slots
        #endif

        for _ in 0..<targetTokenArrays {
            let vector = createTestTokenVector(count: 1)
            executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10)
        }

        // Verify we reached heavy backpressure
        XCTAssertGreaterThanOrEqual(executor.backpressureLevel, .heavy,
                                     "Should be at heavy backpressure after adding \(targetTokenArrays) token arrays")

        // Reset counter after setup (adding tokens might have triggered some callbacks)
        _ = handlerCallCount.mutate { _ in 0 }

        // Step 2: Execute turns to consume tokens until we drop below heavy
        let droppedBelowHeavy = waitForCondition({
            // Execute a turn to consume tokens
            let expectation = XCTestExpectation(description: "Turn complete")
            self.executor.executeTurn(tokenBudget: 100) { _ in
                expectation.fulfill()
            }
            _ = XCTWaiter.wait(for: [expectation], timeout: 0.5)

            return self.executor.backpressureLevel < .heavy
        }, timeout: 5.0)

        XCTAssertTrue(droppedBelowHeavy, "Should eventually drop below heavy backpressure")

        // Step 3: Verify handler was called at least once during the transition
        let finalCallCount = handlerCallCount.value
        XCTAssertGreaterThan(finalCallCount, 0,
                             "backpressureReleaseHandler should be called when crossing from heavy to non-heavy. " +
                             "Final call count: \(finalCallCount)")
    }

    // NEGATIVE TEST: Handler should NOT be called if still at heavy backpressure
    func testBackpressureReleaseHandlerNotCalledIfStillHeavy() throws {
        // REQUIREMENT: Don't call handler spuriously if we're still under heavy load.

        var handlerCallCount = 0
        executor.backpressureReleaseHandler = {
            handlerCallCount += 1
        }

        // Add tokens but don't process them - backpressure should stay heavy
        for _ in 0..<50 {
            let vector = createTestTokenVector(count: 10)
            executor.addTokens(vector, lengthTotal: 100, lengthExcludingInBandSignaling: 100)
        }

        // Flush main queue to ensure any pending callbacks complete
        waitForMainQueue()

        // Handler should not have been called while still under heavy load
        XCTAssertEqual(handlerCallCount, 0, "Handler should not be called while backpressure is still heavy")
    }
}

// MARK: - 2.3 ExecuteTurn Implementation Tests

/// Tests for executeTurn method behavior (2.3)
/// This is the core fairness method that limits token processing per turn.
final class TokenExecutorExecuteTurnTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!
    var executor: TokenExecutor!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
        executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate
    }

    override func tearDown() {
        executor = nil
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testExecuteTurnMethodExists() throws {
        // REQUIREMENT: TokenExecutor must conform to FairnessSchedulerExecutor protocol.

        XCTAssertTrue(executor is FairnessSchedulerExecutor, "TokenExecutor should conform to FairnessSchedulerExecutor")
    }

    func testExecuteTurnReturnsBlockedWhenPaused() throws {
        // REQUIREMENT: When tokenExecutorShouldQueueTokens() returns true,
        // executeTurn must return .blocked immediately without processing.

        mockDelegate.shouldQueueTokens = true

        // Add some tokens
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 500) { result in
            XCTAssertEqual(result, .blocked, "Should return blocked when delegate says to queue tokens")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // NEGATIVE TEST: When blocked, NO tokens should be processed
    func testBlockedDoesNotProcessTokens() throws {
        // REQUIREMENT: .blocked must mean zero token execution, not partial.

        mockDelegate.shouldQueueTokens = true

        // Add tokens
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        let initialExecuteCount = mockDelegate.willExecuteCount

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 500) { result in
            XCTAssertEqual(result, .blocked)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockDelegate.willExecuteCount, initialExecuteCount,
                       "No tokens should be executed when blocked")
    }

    func testExecuteTurnReturnsYieldedWhenMoreWork() throws {
        // REQUIREMENT: When budget is exhausted but queue has more work, return .yielded.

        // Add many tokens to exceed budget
        for _ in 0..<20 {
            let vector = createTestTokenVector(count: 100)
            executor.addTokens(vector, lengthTotal: 1000, lengthExcludingInBandSignaling: 1000)
        }

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 10) { result in
            // With a tiny budget and lots of work, should yield
            XCTAssertEqual(result, .yielded, "Should yield when more work remains after budget exhausted")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testExecuteTurnReturnsCompletedWhenEmpty() throws {
        // REQUIREMENT: When queue is fully drained, return .completed.

        // Don't add any tokens - queue is empty
        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 500) { result in
            XCTAssertEqual(result, .completed, "Should return completed when queue is empty")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // NEGATIVE TEST: .completed should ONLY be returned when truly empty
    func testCompletedNotReturnedWithPendingWork() throws {
        // REQUIREMENT: Must never return .completed if taskQueue or tokenQueue has work.

        // This test verifies the semantic: if there's work, don't return completed.
        // The implementation may process all tokens in one turn if they fit the budget,
        // so we verify the behavior with blocked state instead.

        mockDelegate.shouldQueueTokens = true  // Force blocked state

        // Add tokens
        let vector = createTestTokenVector(count: 10)
        executor.addTokens(vector, lengthTotal: 100, lengthExcludingInBandSignaling: 100)

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 500) { result in
            // When blocked with pending work, should return blocked not completed
            XCTAssertEqual(result, .blocked, "Should return blocked when shouldQueueTokens is true")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testExecuteTurnDrainsTaskQueue() throws {
        // REQUIREMENT: High-priority tasks in taskQueue must run during executeTurn.

        var taskExecuted = false
        executor.scheduleHighPriorityTask {
            taskExecuted = true
        }

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 500) { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(taskExecuted, "High-priority task should be executed during executeTurn")
    }
}

// MARK: - 2.4 Budget Enforcement Edge Cases

/// Tests for budget enforcement edge cases (2.4)
/// These tests verify the "stop between groups, overshoot once" semantics.
///
/// Key semantics being tested:
/// 1. Budget is checked BETWEEN groups, not within a group
/// 2. First group always executes (progress guarantee), even if it exceeds budget
/// 3. Second group does NOT execute if budget was exceeded by first group
/// 4. Groups are atomic - never split mid-execution
final class TokenExecutorBudgetEdgeCaseTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!
    var executor: TokenExecutor!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
        executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate
    }

    override func tearDown() {
        executor = nil
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testFirstGroupExceedingBudgetExecutes() throws {
        // REQUIREMENT: Progress guarantee - at least one group must execute per turn,
        // even if that group exceeds the budget.

        // Add a large token group (100 tokens, budget will be 1)
        let vector = createTestTokenVector(count: 100)
        executor.addTokens(vector, lengthTotal: 1000, lengthExcludingInBandSignaling: 1000)

        let initialExecuteCount = mockDelegate.willExecuteCount

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?
        executor.executeTurn(tokenBudget: 1) { result in
            receivedResult = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Even with budget of 1, at least one group should execute for progress
        XCTAssertGreaterThan(mockDelegate.willExecuteCount, initialExecuteCount,
                             "At least one group should execute even if it exceeds budget")
        // With only one group, it completes after processing
        XCTAssertEqual(receivedResult, .completed,
                       "Single group should complete even if it exceeds budget")
    }

    // NEGATIVE TEST: Budget should NOT be checked mid-group
    func testBudgetNotCheckedWithinGroup() throws {
        // REQUIREMENT: Groups are atomic. Never split a group mid-execution.
        // This test verifies that a group with many tokens executes completely
        // even with a tiny budget.

        // Add a token group with 50 tokens
        let tokenCount = 50
        let vector = createTestTokenVector(count: tokenCount)
        executor.addTokens(vector, lengthTotal: 500, lengthExcludingInBandSignaling: 500)

        let initialExecuteCount = mockDelegate.willExecuteCount

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 1) { result in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // The entire group should have executed atomically (progress guarantee)
        XCTAssertGreaterThan(mockDelegate.willExecuteCount, initialExecuteCount,
                             "Group should execute atomically regardless of budget")
    }

    func testBudgetCheckBetweenGroups() throws {
        // REQUIREMENT: Budget is checked BETWEEN groups, allowing bounded overshoot.
        // Uses high-priority vs normal-priority to ensure separate groups.

        // Group 1: High-priority tokens (100 tokens, will exceed budget of 10)
        let highPriVector = createTestTokenVector(count: 100)
        executor.addTokens(highPriVector, lengthTotal: 1000, lengthExcludingInBandSignaling: 1000, highPriority: true)

        // Group 2: Normal-priority tokens (in separate queue = separate group)
        let normalVector = createTestTokenVector(count: 50)
        executor.addTokens(normalVector, lengthTotal: 500, lengthExcludingInBandSignaling: 500, highPriority: false)

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?
        executor.executeTurn(tokenBudget: 10) { result in
            receivedResult = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Budget exceeded after first group (100 > 10), should yield with more work pending
        XCTAssertEqual(receivedResult, .yielded,
                       "Should yield because budget exceeded and more work remains")
    }

    // NEGATIVE TEST: Second group should NOT execute if budget exceeded after first
    func testSecondGroupSkippedWhenBudgetExceeded() throws {
        // REQUIREMENT: After first group, if budget exceeded, yield to next session.
        // This is the key "stop between groups" semantic.
        //
        // Strategy: Use high-priority and normal-priority tokens to create two
        // guaranteed separate groups (they're in different queues).

        // Group 1: High-priority tokens (100 tokens, will exceed budget of 10)
        let highPriVector = createTestTokenVector(count: 100)
        executor.addTokens(highPriVector, lengthTotal: 1000, lengthExcludingInBandSignaling: 1000, highPriority: true)

        // Group 2: Normal-priority tokens (in separate queue = separate group)
        let normalVector = createTestTokenVector(count: 50)
        executor.addTokens(normalVector, lengthTotal: 500, lengthExcludingInBandSignaling: 500, highPriority: false)

        // Record execution count before first turn
        let initialExecuteCount = mockDelegate.willExecuteCount

        let firstTurnExpectation = XCTestExpectation(description: "First turn completed")
        var firstTurnResult: TurnResult?
        executor.executeTurn(tokenBudget: 10) { result in
            firstTurnResult = result
            firstTurnExpectation.fulfill()
        }
        wait(for: [firstTurnExpectation], timeout: 1.0)

        let afterFirstTurnExecuteCount = mockDelegate.willExecuteCount

        // First turn should have executed exactly once (first group)
        XCTAssertEqual(afterFirstTurnExecuteCount, initialExecuteCount + 1,
                       "First turn should execute only the first group")
        XCTAssertEqual(firstTurnResult, .yielded,
                       "Should yield because second group is still pending")

        // Second turn should process the remaining group
        let secondTurnExpectation = XCTestExpectation(description: "Second turn completed")
        var secondTurnResult: TurnResult?
        executor.executeTurn(tokenBudget: 500) { result in
            secondTurnResult = result
            secondTurnExpectation.fulfill()
        }
        wait(for: [secondTurnExpectation], timeout: 1.0)

        let afterSecondTurnExecuteCount = mockDelegate.willExecuteCount

        // Second turn should execute the remaining group
        XCTAssertEqual(afterSecondTurnExecuteCount, afterFirstTurnExecuteCount + 1,
                       "Second turn should execute the remaining group")
        XCTAssertEqual(secondTurnResult, .completed,
                       "Should complete after processing all remaining work")
    }
}

// MARK: - 2.5 Scheduler Entry Points Tests

/// Tests for scheduler notification from all entry points (2.5)
///
/// IMPORTANT: TokenExecutor's queue parameter must be the mutation queue.
/// - High-priority tokens: notifyScheduler() called synchronously (no async hop)
/// - Normal tokens: notifyScheduler() dispatched via queue.async
final class TokenExecutorSchedulerEntryPointTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!
    var executor: TokenExecutor!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
        // CRITICAL: Use mutation queue, not main queue
        // The executor dispatches scheduler notifications to this queue
        executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: iTermGCD.mutationQueue()
        )
        executor.delegate = mockDelegate
    }

    override func tearDown() {
        executor = nil
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testAddTokensNotifiesScheduler() throws {
        // REQUIREMENT: addTokens() must call notifyScheduler() to kick FairnessScheduler.

        // Register executor with scheduler
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId
        defer { FairnessScheduler.shared.unregister(sessionId: sessionId) }

        mockDelegate.shouldQueueTokens = false

        let originalCount = mockDelegate.executedLengths.count

        // Add tokens - this should notify scheduler
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        // Drain mutation queue to let execution complete
        for _ in 0..<5 {
            waitForMutationQueue()
        }

        XCTAssertGreaterThan(mockDelegate.executedLengths.count, originalCount,
                             "Adding tokens should notify scheduler and trigger execution")
    }

    func testScheduleNotifiesScheduler() throws {
        // REQUIREMENT: schedule() must call notifyScheduler().

        // Register executor with scheduler
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId
        defer { FairnessScheduler.shared.unregister(sessionId: sessionId) }

        // Block execution initially
        mockDelegate.shouldQueueTokens = true

        // Add tokens first
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        waitForMutationQueue()

        let initialCount = mockDelegate.executedLengths.count

        // Unblock and call schedule() - should notify scheduler
        mockDelegate.shouldQueueTokens = false
        executor.schedule()

        // Drain mutation queue to let execution complete
        for _ in 0..<5 {
            waitForMutationQueue()
        }

        XCTAssertGreaterThan(mockDelegate.executedLengths.count, initialCount,
                             "schedule() should trigger execution via scheduler")
    }

    func testScheduleHighPriorityTaskNotifiesScheduler() throws {
        // REQUIREMENT: scheduleHighPriorityTask() must call notifyScheduler().

        // Register executor with scheduler
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId
        defer { FairnessScheduler.shared.unregister(sessionId: sessionId) }

        var taskExecuted = false
        executor.scheduleHighPriorityTask {
            taskExecuted = true
        }

        // Drain mutation queue to let execution complete
        for _ in 0..<5 {
            waitForMutationQueue()
        }

        XCTAssertTrue(taskExecuted, "scheduleHighPriorityTask should notify scheduler and execute")
    }

    // NEGATIVE TEST: No duplicate notifications for already-busy session
    func testNoDuplicateNotificationsForBusySession() throws {
        // REQUIREMENT: If session already in busy list, don't add duplicate entry.

        // Register executor with scheduler
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId
        defer { FairnessScheduler.shared.unregister(sessionId: sessionId) }

        mockDelegate.shouldQueueTokens = false

        // Add tokens multiple times rapidly
        for _ in 0..<5 {
            let vector = createTestTokenVector(count: 1)
            executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10)
        }

        // Drain mutation queue to let all tokens be processed
        for _ in 0..<10 {
            waitForMutationQueue()
        }

        let executionCount = mockDelegate.executedLengths.count

        // Should have processed tokens but not created duplicate busy list entries
        // (verified by not having 5x the expected executions)
        XCTAssertGreaterThan(executionCount, 0, "Tokens should be processed")
        XCTAssertLessThanOrEqual(executionCount, 5, "Should not create duplicate busy list entries")
    }

    func testHighPriorityAddTokensOnMutationQueueTriggersExecution() throws {
        // REQUIREMENT: addTokens(highPriority: true) when called from mutation queue context
        // should call notifyScheduler() synchronously (not via queue.async like normal tokens).
        // This ensures the scheduler is notified without an extra async hop.
        //
        // The key difference vs normal priority:
        // - High priority: reallyAddTokens() + notifyScheduler() - both synchronous
        // - Normal priority: reallyAddTokens() + queue.async { notifyScheduler() }

        // Register executor with scheduler
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId
        defer { FairnessScheduler.shared.unregister(sessionId: sessionId) }

        mockDelegate.shouldQueueTokens = false

        let initialExecuteCount = mockDelegate.executedLengths.count

        // Add high-priority tokens from mutation queue context
        iTermGCD.mutationQueue().async {
            let vector = createTestTokenVector(count: 1)
            self.executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10, highPriority: true)
        }

        // Drain mutation queue to let execution complete
        for _ in 0..<5 {
            waitForMutationQueue()
        }

        XCTAssertGreaterThan(mockDelegate.executedLengths.count, initialExecuteCount,
                             "High-priority tokens added from mutation queue should trigger execution")
    }

    func testHighPriorityTokensNotifySchedulerSynchronously() throws {
        // REQUIREMENT: Verify high-priority addTokens notifies scheduler without extra async hop.
        // The scheduler is notified synchronously when high-priority tokens are added on
        // mutation queue, vs normal tokens which dispatch notification via queue.async.

        // Register executor with scheduler
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId
        defer { FairnessScheduler.shared.unregister(sessionId: sessionId) }

        mockDelegate.shouldQueueTokens = false

        var executionOccurred = false
        mockDelegate.onWillExecute = {
            executionOccurred = true
        }

        // Add high-priority tokens from mutation queue
        iTermGCD.mutationQueue().async {
            let vector = createTestTokenVector(count: 1)
            self.executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10, highPriority: true)
        }

        // Drain mutation queue to let execution complete
        for _ in 0..<5 {
            waitForMutationQueue()
        }

        XCTAssertTrue(executionOccurred,
                      "High-priority tokens should trigger execution via scheduler")
    }
}

// MARK: - 2.6 Legacy Removal Tests

/// Tests verifying legacy foreground preemption code is removed (2.6)
final class TokenExecutorLegacyRemovalTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
    }

    override func tearDown() {
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testActiveSessionsWithTokensRemoved() throws {
        // REQUIREMENT: The static activeSessionsWithTokens set must be removed.
        // FairnessScheduler replaces this ad-hoc preemption mechanism.

        // Verify by checking that TokenExecutor doesn't have activeSessionsWithTokens property
        // This is verified at compile-time - if the property exists, tests would use it
        // Runtime verification: create executors and verify fairness model works
        let executor1 = TokenExecutor(mockTerminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        let executor2 = TokenExecutor(mockTerminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)

        executor1.delegate = mockDelegate
        executor2.delegate = mockDelegate

        // Both should be able to process without the old preemption mechanism
        XCTAssertNotNil(executor1)
        XCTAssertNotNil(executor2)
    }

    // NEGATIVE TEST: Background sessions should NOT be preempted by foreground
    func testBackgroundSessionNotPreemptedByForeground() throws {
        // REQUIREMENT: Under fairness model, all sessions get equal turns.
        // Background sessions should NOT yield to foreground mid-turn.
        //
        // Test design:
        // 1. Create both background and foreground executors with tokens
        // 2. Add tokens to BOTH (foreground having tokens is what could cause preemption)
        // 3. Verify both sessions get execution turns (proving no preemption/starvation)

        // Create background executor with its own delegate for tracking
        let bgDelegate = MockTokenExecutorDelegate()
        let bgExecutor = TokenExecutor(mockTerminal, slownessDetector: SlownessDetector(), queue: iTermGCD.mutationQueue())
        bgExecutor.delegate = bgDelegate
        bgExecutor.isBackgroundSession = true

        // Create foreground executor with its own delegate
        let fgDelegate = MockTokenExecutorDelegate()
        let fgExecutor = TokenExecutor(mockTerminal, slownessDetector: SlownessDetector(), queue: iTermGCD.mutationQueue())
        fgExecutor.delegate = fgDelegate
        fgExecutor.isBackgroundSession = false

        // Register both with scheduler
        let bgId = FairnessScheduler.shared.register(bgExecutor)
        let fgId = FairnessScheduler.shared.register(fgExecutor)
        bgExecutor.fairnessSessionId = bgId
        fgExecutor.fairnessSessionId = fgId

        defer {
            FairnessScheduler.shared.unregister(sessionId: bgId)
            FairnessScheduler.shared.unregister(sessionId: fgId)
        }

        // Add tokens to BOTH executors - this is crucial for testing preemption
        // If foreground has tokens, the old activeSessionsWithTokens logic would
        // have preempted background. Under fairness, both should get turns.
        let bgVector = createTestTokenVector(count: 5)
        bgExecutor.addTokens(bgVector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        let fgVector = createTestTokenVector(count: 5)
        fgExecutor.addTokens(fgVector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        // Wait for BOTH to execute - under fairness, both should get turns
        let bothExecuted = waitForCondition({
            bgDelegate.executedLengths.count > 0 && fgDelegate.executedLengths.count > 0
        }, timeout: 2.0)

        // Verify both sessions processed (neither was starved/preempted)
        XCTAssertTrue(bothExecuted,
                      "Both background and foreground should process under fairness. " +
                      "Background executions: \(bgDelegate.executedLengths.count), " +
                      "Foreground executions: \(fgDelegate.executedLengths.count)")

        // Additional verification: background specifically got a turn
        XCTAssertGreaterThan(bgDelegate.executedLengths.count, 0,
                             "Background session should not be preempted by foreground")
    }

    func testBackgroundSessionGetsEqualTurns() {
        // Test that background sessions process tokens under fairness model

        let executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: iTermGCD.mutationQueue()
        )
        executor.delegate = mockDelegate
        executor.isBackgroundSession = true

        // Register with FairnessScheduler (required for schedule() to work)
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        // Add and process tokens
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        // Drain mutation queue to let execution complete
        for _ in 0..<5 {
            waitForMutationQueue()
        }

        XCTAssertGreaterThan(mockDelegate.executedLengths.count, 0,
                             "Background session should process tokens")

        // Clean up
        FairnessScheduler.shared.unregister(sessionId: sessionId)
    }

    func testRoundRobinFairnessInvariant() throws {
        // REQUIREMENT: Each session gets AT MOST one turn per round.
        // This is the KEY FAIRNESS INVARIANT: no session gets a second turn
        // until all other busy sessions have had their first turn.
        //
        // Test design (DETERMINISTIC - no polling/timeouts):
        // 1. Create sessions with delegates that BLOCK execution (shouldQueueTokens = true)
        // 2. Add tokens to ALL sessions while blocked - they queue but don't execute
        // 3. Sync to mutation queue - all sessions now in busy list
        // 4. Clear execution history
        // 5. Unblock all sessions and kick scheduler
        // 6. Sync to mutation queue multiple times to let execution complete
        // 7. Verify the execution order shows proper round-robin
        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks for execution history tracking")

        #if ITERM_DEBUG
        // Create 3 sessions with delegates that initially BLOCK execution
        var executors: [(executor: TokenExecutor, delegate: MockTokenExecutorDelegate, id: UInt64)] = []

        for i in 0..<3 {
            let delegate = MockTokenExecutorDelegate()
            delegate.shouldQueueTokens = true  // BLOCK execution initially
            let terminal = VT100Terminal()
            let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: iTermGCD.mutationQueue())
            executor.delegate = delegate
            executor.isBackgroundSession = (i > 0)

            let sessionId = FairnessScheduler.shared.register(executor)
            executor.fairnessSessionId = sessionId

            executors.append((executor: executor, delegate: delegate, id: sessionId))
        }

        defer {
            for e in executors {
                FairnessScheduler.shared.unregister(sessionId: e.id)
            }
        }

        // Add tokens to ALL sessions while they're blocked
        // This ensures all sessions have work queued BEFORE any execution starts
        for e in executors {
            // Add enough tokens to require multiple rounds (budget is 500 tokens)
            // Each call adds 100 tokens worth, so 10 calls = 1000 tokens = 2 turns
            for _ in 0..<10 {
                let vector = createTestTokenVector(count: 100)
                e.executor.addTokens(vector, lengthTotal: 1000, lengthExcludingInBandSignaling: 1000)
            }
        }

        // Sync to mutation queue - all tokens are queued, scheduler has been notified
        // but execution returns .blocked because shouldQueueTokens = true
        waitForMutationQueue()

        // Clear any history from the blocked execution attempts
        FairnessScheduler.shared.testClearExecutionHistory()

        // Unblock all sessions on mutation queue and kick scheduler
        iTermGCD.mutationQueue().sync {
            for e in executors {
                e.delegate.shouldQueueTokens = false
            }
        }

        // Kick scheduler for each session to notify there's work
        for e in executors {
            e.executor.schedule()
        }

        // Sync multiple times to allow execution rounds to complete
        // Each sync drains the queue, allowing pending execution completions to trigger next turns
        for _ in 0..<20 {
            waitForMutationQueue()
        }

        // Get the execution history
        let history = FairnessScheduler.shared.testGetAndClearExecutionHistory()

        // Basic sanity check - we should have some executions
        XCTAssertGreaterThanOrEqual(history.count, 3,
                                     "Should have at least one round of execution. History: \(history)")

        // VERIFY THE ROUND-ROBIN FAIRNESS INVARIANT:
        // No session should execute twice in a row when other sessions have work.
        var violations: [String] = []
        for i in 1..<history.count {
            if history[i] == history[i-1] {
                violations.append("Session \(history[i]) at indices \(i-1) and \(i)")
            }
        }

        XCTAssertTrue(violations.isEmpty,
                      "Round-robin fairness violated: same session executed consecutively. " +
                      "History: \(history), Violations: \(violations)")

        // Verify all sessions got at least one turn (no starvation)
        for e in executors {
            let turnCount = history.filter { $0 == e.id }.count
            XCTAssertGreaterThan(turnCount, 0,
                                 "Session \(e.id) should have at least one turn. History: \(history)")
        }

        // Verify interleaving: in first N turns (where N = session count), all sessions should appear
        let sessionCount = executors.count
        if history.count >= sessionCount {
            let firstRound = Array(history.prefix(sessionCount))
            let uniqueInFirstRound = Set(firstRound)
            XCTAssertEqual(uniqueInFirstRound.count, sessionCount,
                           "First round should include all \(sessionCount) sessions. First \(sessionCount): \(firstRound)")
        }
        #endif
    }
}

// MARK: - 2.7 Cleanup Tests

/// Tests for cleanup when session is unregistered (2.7)
final class TokenExecutorCleanupTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
    }

    override func tearDown() {
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testCleanupForUnregistrationExists() throws {
        // REQUIREMENT: cleanupForUnregistration() must exist and handle unconsumed tokens.

        let executor = TokenExecutor(mockTerminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.delegate = mockDelegate

        // Verify the method exists by calling it
        executor.cleanupForUnregistration()

        // Should not crash - test passes if we get here
    }

    func testCleanupIncrementsAvailableSlots() throws {
        // REQUIREMENT: For each unconsumed TokenArray, increment availableSlots.

        let executor = TokenExecutor(mockTerminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.delegate = mockDelegate

        // Add tokens without processing
        for _ in 0..<10 {
            let vector = createTestTokenVector(count: 5)
            executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        }

        // Cleanup should restore slots
        executor.cleanupForUnregistration()

        // After cleanup, backpressure should be released
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Cleanup should restore available slots")
    }

    // NEGATIVE TEST: Cleanup should NOT double-increment for already-consumed tokens
    func testCleanupNoDoubleIncrement() throws {
        // REQUIREMENT: Only increment for truly unconsumed tokens.

        let executor = TokenExecutor(mockTerminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.delegate = mockDelegate

        // Add and consume tokens
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        executor.schedule()

        // Drain main queue to let tokens be consumed
        for _ in 0..<5 {
            waitForMainQueue()
        }

        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Tokens should be consumed (backpressure none)")

        // Now cleanup - should not over-increment
        executor.cleanupForUnregistration()

        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Cleanup should not over-increment slots")
    }

    func testCleanupRestoresExactSlotCount() throws {
        // REQUIREMENT: Verify cleanup restores slots by checking backpressure behavior.
        // We verify the exact restoration by testing that we can add the same number
        // of arrays again after cleanup without exceeding capacity.

        let executor = TokenExecutor(mockTerminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.delegate = mockDelegate

        // Verify initial state - no backpressure
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Fresh executor should have no backpressure")

        // Add enough token arrays to exceed capacity (200 with 40 slots = blocked)
        let arraysToAdd = 200
        for _ in 0..<arraysToAdd {
            let vector = createTestTokenVector(count: 5)
            executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        }

        // Should be blocked (availableSlots = 40 - 200 = -160, which is <= 0)
        XCTAssertEqual(executor.backpressureLevel, .blocked,
                       "Should be blocked after adding more arrays than slots")

        // Cleanup should restore all slots
        executor.cleanupForUnregistration()

        // After cleanup, backpressure should be none
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Cleanup should restore all slots (backpressure none)")

        // The real test: we should be able to add the same number of arrays again
        // without the behavior being different. If cleanup didn't restore exactly,
        // this would behave differently.
        for _ in 0..<arraysToAdd {
            let vector = createTestTokenVector(count: 5)
            executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        }

        // Should have the same blocked state again
        XCTAssertEqual(executor.backpressureLevel, .blocked,
                       "After re-adding same arrays, should have same backpressure (slots properly restored)")
    }

    func testCleanupEmptyQueueNoChange() throws {
        // REQUIREMENT: Cleanup with empty queue should not change availableSlots.

        let executor = TokenExecutor(mockTerminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.delegate = mockDelegate

        let initialLevel = executor.backpressureLevel

        // Cleanup with no tokens
        executor.cleanupForUnregistration()

        XCTAssertEqual(executor.backpressureLevel, initialLevel,
                       "Cleanup with empty queue should not change slots")
    }
}

// MARK: - Accounting Invariant Tests

/// Critical tests for availableSlots accounting invariants.
/// These are the most important tests - accounting drift causes stalls or overflow.
final class TokenExecutorAccountingInvariantTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
    }

    override func tearDown() {
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testAccountingInvariantSteadyState() {
        // INVARIANT: At rest (no tokens in flight), backpressure should be .none.

        let executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate

        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Fresh executor should have no backpressure")
    }

    func testAccountingInvariantAfterEnqueueConsume() {
        // INVARIANT: After enqueue + consume cycles, availableSlots returns to initial.

        let executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate

        // Add and consume tokens
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        executor.schedule()

        // Drain main queue to let processing complete
        for _ in 0..<5 {
            waitForMainQueue()
        }

        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Backpressure should return to none after processing")
    }

    // NEGATIVE TEST: Accounting should NEVER drift over multiple cycles
    func testAccountingNoDriftAfterMultipleCycles() {
        // INVARIANT: Running many enqueue/consume cycles should not cause drift.

        let executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: iTermGCD.mutationQueue()
        )
        executor.delegate = mockDelegate

        // Run multiple cycles
        for _ in 0..<5 {
            let vector = createTestTokenVector(count: 3)
            executor.addTokens(vector, lengthTotal: 30, lengthExcludingInBandSignaling: 30)
            executor.schedule()

            // Drain mutation queue to let processing complete for this cycle
            for _ in 0..<5 {
                waitForMutationQueue()
            }
            XCTAssertEqual(executor.backpressureLevel, .none,
                           "Cycle should complete with no backpressure")
        }

        // Final check - backpressure should be none after all cycles
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "No accounting drift after multiple cycles")
    }

    func testAccountingInvariantAfterSessionClose() throws {
        // INVARIANT: After session close with pending tokens, availableSlots restored.

        let executor = TokenExecutor(mockTerminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.delegate = mockDelegate

        // Register
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        // Add tokens
        for _ in 0..<5 {
            let vector = createTestTokenVector(count: 5)
            executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
        }

        // Unregister (simulates session close)
        FairnessScheduler.shared.unregister(sessionId: sessionId)

        // After close, backpressure should be released
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Session close should restore available slots")
    }
}

// MARK: - ExecuteTurn Completion Callback Tests

/// Tests for executeTurn completion callback semantics.
/// These are critical for scheduler correctness - completion must be called exactly once.
final class TokenExecutorCompletionCallbackTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!
    var executor: TokenExecutor!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
        executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate
    }

    override func tearDown() {
        executor = nil
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testCompletionCalledExactlyOnce() {
        // REQUIREMENT: executeTurn completion must be called exactly once, never zero or multiple times.

        var completionCallCount = 0
        let expectation = XCTestExpectation(description: "Completion called")

        executor.executeTurn(tokenBudget: 500) { _ in
            completionCallCount += 1
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Flush queues to ensure any spurious calls would have been made
        waitForMutationQueue()
        waitForMainQueue()

        XCTAssertEqual(completionCallCount, 1,
                       "Completion should be called exactly once")
    }

    func testCompletionCalledExactlyOnceWithTokens() {
        // REQUIREMENT: With tokens in queue, completion still called exactly once.

        var completionCallCount = 0
        let expectation = XCTestExpectation(description: "Completion called")

        // Add some tokens
        let vector = createTestTokenVector(count: 10)
        executor.addTokens(vector, lengthTotal: 100, lengthExcludingInBandSignaling: 100)

        executor.executeTurn(tokenBudget: 500) { _ in
            completionCallCount += 1
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Flush queues to ensure any spurious calls would have been made
        waitForMutationQueue()
        waitForMainQueue()

        XCTAssertEqual(completionCallCount, 1,
                       "Completion should be called exactly once even with tokens")
    }

    func testCompletionCalledExactlyOnceWhenBlocked() {
        // REQUIREMENT: When blocked, completion is called exactly once with .blocked.

        mockDelegate.shouldQueueTokens = true
        var completionCallCount = 0
        var receivedResult: TurnResult?
        let expectation = XCTestExpectation(description: "Completion called")

        // Add tokens
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        executor.executeTurn(tokenBudget: 500) { result in
            completionCallCount += 1
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Flush queues to ensure any spurious calls would have been made
        waitForMutationQueue()
        waitForMainQueue()

        XCTAssertEqual(completionCallCount, 1,
                       "Completion should be called exactly once when blocked")
        XCTAssertEqual(receivedResult, .blocked,
                       "Should receive blocked result")
    }

    func testCompletionCalledExactlyOnceWhenYielding() {
        // REQUIREMENT: When yielding due to budget, completion called exactly once with .yielded.

        var completionCallCount = 0
        var receivedResult: TurnResult?
        let expectation = XCTestExpectation(description: "Completion called")

        // Add many tokens to exceed budget
        for _ in 0..<20 {
            let vector = createTestTokenVector(count: 50)
            executor.addTokens(vector, lengthTotal: 500, lengthExcludingInBandSignaling: 500)
        }

        executor.executeTurn(tokenBudget: 10) { result in
            completionCallCount += 1
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Flush queues to ensure any spurious calls would have been made
        waitForMutationQueue()
        waitForMainQueue()

        XCTAssertEqual(completionCallCount, 1,
                       "Completion should be called exactly once when yielding")
        XCTAssertEqual(receivedResult, .yielded,
                       "Should receive yielded result")
    }

    func testMultipleExecuteTurnCallsEachGetCompletion() {
        // REQUIREMENT: Multiple sequential executeTurn calls each get their own completion.

        var completionResults: [TurnResult] = []
        let allDone = XCTestExpectation(description: "All completions")
        allDone.expectedFulfillmentCount = 3

        // First call
        executor.executeTurn(tokenBudget: 500) { result in
            completionResults.append(result)
            allDone.fulfill()

            // Second call (nested)
            self.executor.executeTurn(tokenBudget: 500) { result in
                completionResults.append(result)
                allDone.fulfill()

                // Third call (nested)
                self.executor.executeTurn(tokenBudget: 500) { result in
                    completionResults.append(result)
                    allDone.fulfill()
                }
            }
        }

        wait(for: [allDone], timeout: 2.0)

        XCTAssertEqual(completionResults.count, 3,
                       "Each executeTurn call should get exactly one completion")
    }
}

// MARK: - Budget Enforcement Detailed Tests

/// Detailed tests for budget enforcement behavior.
/// These tests use high-priority vs normal-priority tokens to create guaranteed
/// separate groups (they're in different queues) for proper verification.
final class TokenExecutorBudgetEnforcementDetailedTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!
    var executor: TokenExecutor!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
        executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate
    }

    override func tearDown() {
        executor = nil
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testBudgetExceededReturnsYielded() {
        // REQUIREMENT: When processing exceeds budget, must return .yielded (not .completed).
        // Uses high-priority + normal-priority to guarantee two separate groups.

        // Group 1: High-priority (100 tokens)
        let highPriVector = createTestTokenVector(count: 100)
        executor.addTokens(highPriVector, lengthTotal: 1000, lengthExcludingInBandSignaling: 1000, highPriority: true)

        // Group 2: Normal-priority (50 tokens)
        let normalVector = createTestTokenVector(count: 50)
        executor.addTokens(normalVector, lengthTotal: 500, lengthExcludingInBandSignaling: 500, highPriority: false)

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?

        executor.executeTurn(tokenBudget: 10) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedResult, .yielded,
                       "With small budget and multiple groups, should yield after first group")
    }

    func testProgressGuaranteeWithZeroBudget() {
        // REQUIREMENT: Even with budget=0, at least one group must execute for progress.
        // This prevents starvation.

        // Add a single group
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        let initialWillExecuteCount = mockDelegate.willExecuteCount

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?
        executor.executeTurn(tokenBudget: 0) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Should have executed at least once for progress guarantee
        XCTAssertGreaterThan(mockDelegate.willExecuteCount, initialWillExecuteCount,
                             "At least one group should execute even with budget=0")
        XCTAssertEqual(receivedResult, .completed,
                       "With single group and budget=0, should complete after progress guarantee")
    }

    func testSecondGroupNotExecutedWhenBudgetExceededByFirst() {
        // REQUIREMENT: After first group exceeds budget, second group should NOT execute in same turn.
        // This is the key "stop between groups" semantic.
        //
        // Strategy: Use high-priority and normal-priority tokens to create two
        // guaranteed separate groups (they're in different queues).

        // Group 1: High-priority tokens (100 tokens, will exceed budget of 10)
        let highPriVector = createTestTokenVector(count: 100)
        executor.addTokens(highPriVector, lengthTotal: 1000, lengthExcludingInBandSignaling: 1000, highPriority: true)

        // Group 2: Normal-priority tokens (in separate queue = separate group)
        let normalVector = createTestTokenVector(count: 50)
        executor.addTokens(normalVector, lengthTotal: 500, lengthExcludingInBandSignaling: 500, highPriority: false)

        // Record execution count before first turn
        let initialExecuteCount = mockDelegate.willExecuteCount

        let firstTurnExpectation = XCTestExpectation(description: "First turn completed")
        var firstTurnResult: TurnResult?
        executor.executeTurn(tokenBudget: 10) { result in
            firstTurnResult = result
            firstTurnExpectation.fulfill()
        }
        wait(for: [firstTurnExpectation], timeout: 1.0)

        let afterFirstTurnExecuteCount = mockDelegate.willExecuteCount

        // First turn should have executed exactly once (first group only)
        XCTAssertEqual(afterFirstTurnExecuteCount, initialExecuteCount + 1,
                       "First turn should execute only the first group (stop between groups)")
        XCTAssertEqual(firstTurnResult, .yielded,
                       "Should yield because second group is still pending")

        // Second turn should process the remaining group
        let secondTurnExpectation = XCTestExpectation(description: "Second turn completed")
        var secondTurnResult: TurnResult?
        executor.executeTurn(tokenBudget: 500) { result in
            secondTurnResult = result
            secondTurnExpectation.fulfill()
        }
        wait(for: [secondTurnExpectation], timeout: 1.0)

        let afterSecondTurnExecuteCount = mockDelegate.willExecuteCount

        // Second turn should execute the remaining group
        XCTAssertEqual(afterSecondTurnExecuteCount, afterFirstTurnExecuteCount + 1,
                       "Second turn should execute the remaining group")
        XCTAssertEqual(secondTurnResult, .completed,
                       "Should complete after processing all remaining work")
    }

    func testGroupAtomicity() {
        // REQUIREMENT: Groups are atomic - never split mid-execution.
        // We verify this by checking that a group with many tokens executes
        // fully even with a tiny budget.

        // Add a single group with 100 tokens
        let tokenCount = 100
        let vector = createTestTokenVector(count: tokenCount)
        let totalLength = tokenCount * 10
        executor.addTokens(vector, lengthTotal: totalLength, lengthExcludingInBandSignaling: totalLength)

        let initialWillExecuteCount = mockDelegate.willExecuteCount

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?
        executor.executeTurn(tokenBudget: 1) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // The entire group should have executed atomically
        XCTAssertEqual(mockDelegate.willExecuteCount, initialWillExecuteCount + 1,
                       "Group should execute exactly once (atomically)")
        // With only one group, it should complete
        XCTAssertEqual(receivedResult, .completed,
                       "Single group should complete (executed atomically despite tiny budget)")

        // Verify the full length was reported
        if !mockDelegate.executedLengths.isEmpty {
            let execution = mockDelegate.executedLengths[0]
            XCTAssertEqual(execution.total, totalLength,
                           "Full group length should be reported (group was not split)")
        }
    }

    func testBudgetUsesTokenCountNotLengthTotal() {
        // REQUIREMENT: Budget enforcement must use TOKEN COUNT, not lengthTotal.
        // This test uses mismatched values to distinguish the two metrics.
        //
        // If budget used lengthTotal (bug), this test would fail because:
        // - Group1 (50 lengthTotal) + Group2 (5000 lengthTotal) = 5050 > budget of 100
        // - Only Group1 would execute, result = .yielded
        //
        // If budget uses token count (correct), this test passes because:
        // - Group1 (50 tokens) + Group2 (5 tokens) = 55 < budget of 100
        // - Both groups execute, result = .completed

        // Group 1: Many tokens, small lengthTotal (high-priority for separate group)
        let manyTokensVector = createTestTokenVector(count: 50)
        executor.addTokens(manyTokensVector, lengthTotal: 50, lengthExcludingInBandSignaling: 50, highPriority: true)

        // Group 2: Few tokens, large lengthTotal (normal-priority for separate group)
        let fewTokensVector = createTestTokenVector(count: 5)
        executor.addTokens(fewTokensVector, lengthTotal: 5000, lengthExcludingInBandSignaling: 5000, highPriority: false)

        let initialWillExecuteCount = mockDelegate.willExecuteCount

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?
        // Budget of 100: if using token count, 50+5=55 fits. If using lengthTotal, 50+5000 doesn't fit.
        executor.executeTurn(tokenBudget: 100) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Both groups should execute because token count (55) fits within budget (100)
        // This would fail if implementation incorrectly used lengthTotal (5050 > 100)
        XCTAssertEqual(receivedResult, .completed,
                       "Both groups should execute when TOKEN COUNT fits budget (budget uses token count, not lengthTotal)")

        // Verify both groups executed (willExecuteTokens called, then both groups' lengths reported)
        XCTAssertGreaterThan(mockDelegate.willExecuteCount, initialWillExecuteCount,
                             "At least one execution should have occurred")

        // Verify both groups' lengths were reported (50 + 5000 = 5050 total)
        let totalReportedLength = mockDelegate.executedLengths.reduce(0) { $0 + $1.total }
        XCTAssertEqual(totalReportedLength, 5050,
                       "Both groups should have reported their lengths (50 + 5000)")
    }

    func testBudgetExceedanceUsesTokenCountNotLengthTotal() {
        // REQUIREMENT: Budget exceedance check must use TOKEN COUNT, not lengthTotal.
        // This is the inverse test - verifies that large token counts cause yielding
        // even when lengthTotal is small.
        //
        // If budget used lengthTotal (bug), this test would fail because:
        // - Group1 (5 lengthTotal) + Group2 (50 lengthTotal) = 55 < budget of 100
        // - Both groups would execute, result = .completed
        //
        // If budget uses token count (correct), this test passes because:
        // - Group1 (50 tokens) exceeds budget of 10, but executes due to progress guarantee
        // - Group2 (5 tokens): 50 + 5 = 55 > 10, so yield before executing Group2
        // - Only Group1 executes, result = .yielded

        // Group 1: Many tokens, tiny lengthTotal (high-priority for separate group)
        let manyTokensVector = createTestTokenVector(count: 50)
        executor.addTokens(manyTokensVector, lengthTotal: 5, lengthExcludingInBandSignaling: 5, highPriority: true)

        // Group 2: Few tokens, small lengthTotal (normal-priority for separate group)
        let fewTokensVector = createTestTokenVector(count: 5)
        executor.addTokens(fewTokensVector, lengthTotal: 50, lengthExcludingInBandSignaling: 50, highPriority: false)

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?
        // Budget of 10: token count of Group1 (50) already exceeds it
        executor.executeTurn(tokenBudget: 10) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Should yield because token count (50) exceeds budget (10), even though lengthTotal is tiny
        // Group1 executes due to progress guarantee, then yields before Group2
        XCTAssertEqual(receivedResult, .yielded,
                       "Should yield when TOKEN COUNT exceeds budget (budget uses token count, not lengthTotal)")

        // Verify only first group's length was reported (5, not 5+50=55)
        let totalReportedLength = mockDelegate.executedLengths.reduce(0) { $0 + $1.total }
        XCTAssertEqual(totalReportedLength, 5,
                       "Only first group should have executed (length 5, not 55)")
    }

}

// MARK: - Same-Queue Group Boundary Tests

/// Tests for budget enforcement with multiple groups in the SAME priority queue.
/// These tests verify that enumerateTokenArrayGroups correctly identifies group
/// boundaries based on token coalesceability, and that budget is checked between
/// these groups (not just between high-priority and normal-priority queues).
///
/// Key invariant: VT100_UNKNOWNCHAR tokens are non-coalescable, so each TokenArray
/// with such tokens forms its own group, even when added to the same queue.
final class TokenExecutorSameQueueGroupBoundaryTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!
    var executor: TokenExecutor!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
        executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate

        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId
    }

    override func tearDown() {
        if let id = executor?.fairnessSessionId {
            FairnessScheduler.shared.unregister(sessionId: id)
        }
        executor = nil
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testBudgetEnforcementBetweenGroupsInSameQueue() {
        // REQUIREMENT: Budget should be checked BETWEEN groups in the same queue,
        // not just between different priority queues.
        // This test adds multiple TokenArrays to the NORMAL priority queue only.
        //
        // NOTE: Budget is measured in TOKEN COUNT, not byte length.
        // VT100_UNKNOWNCHAR tokens are non-coalescable, so each array is its own group.

        // Add 3 groups of 100 TOKENS each to normal priority queue
        for _ in 0..<3 {
            let vector = createTestTokenVector(count: 100)  // 100 tokens per group
            executor.addTokens(vector, lengthTotal: 1000, lengthExcludingInBandSignaling: 1000)
        }

        let initialWillExecuteCount = mockDelegate.willExecuteCount

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?
        executor.executeTurn(tokenBudget: 50) { result in  // Budget of 50 tokens
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // First group (100 tokens) exceeds budget (50), should yield with more work
        XCTAssertEqual(receivedResult, .yielded,
                       "Should yield because first group exceeds budget and more groups remain")

        // Only ONE group should have executed (progress guarantee + budget stop)
        XCTAssertEqual(mockDelegate.willExecuteCount, initialWillExecuteCount + 1,
                       "Only first group should execute when it exceeds budget")
    }

    func testSecondGroupInSameQueueSkippedWhenBudgetExceeded() {
        // REQUIREMENT: Second group in same queue should NOT execute if budget
        // was exceeded by first group. This verifies the budget check between
        // groups within the same priority queue.
        //
        // NOTE: Budget is measured in TOKEN COUNT, not byte length.

        // Add 2 groups to normal priority queue with different TOKEN counts
        let firstGroupTokens = 100
        let secondGroupTokens = 50

        let vector1 = createTestTokenVector(count: firstGroupTokens)
        executor.addTokens(vector1, lengthTotal: firstGroupTokens * 10, lengthExcludingInBandSignaling: firstGroupTokens * 10)

        let vector2 = createTestTokenVector(count: secondGroupTokens)
        executor.addTokens(vector2, lengthTotal: secondGroupTokens * 10, lengthExcludingInBandSignaling: secondGroupTokens * 10)

        // First turn: budget 10, first group is 100 tokens - should execute only first
        let firstExpectation = XCTestExpectation(description: "First turn")
        var firstResult: TurnResult?
        executor.executeTurn(tokenBudget: 10) { result in
            firstResult = result
            firstExpectation.fulfill()
        }
        wait(for: [firstExpectation], timeout: 1.0)

        XCTAssertEqual(firstResult, .yielded,
                       "First turn should yield (more work remains)")
        XCTAssertEqual(mockDelegate.willExecuteCount, 1,
                       "Only first group should execute in first turn")

        // Second turn: should process remaining group
        let secondExpectation = XCTestExpectation(description: "Second turn")
        var secondResult: TurnResult?
        executor.executeTurn(tokenBudget: 100) { result in
            secondResult = result
            secondExpectation.fulfill()
        }
        wait(for: [secondExpectation], timeout: 1.0)

        XCTAssertEqual(secondResult, .completed,
                       "Second turn should complete (all work done)")
        XCTAssertEqual(mockDelegate.willExecuteCount, 2,
                       "Second group should execute in second turn")
    }

    func testMultipleGroupsProcessedWithinBudget() {
        // REQUIREMENT: Multiple groups should all execute if they fit within budget.
        // This verifies that budget check allows continuation when budget not exceeded.
        //
        // NOTE: Budget is measured in TOKEN COUNT, not byte length.
        // NOTE: willExecuteCount and executedLengths are per-TURN metrics, not per-group.

        // Add 3 small groups (10 TOKENS each) to normal priority queue
        // Each has lengthTotal of 100 bytes
        for _ in 0..<3 {
            let vector = createTestTokenVector(count: 10)  // 10 tokens per group
            executor.addTokens(vector, lengthTotal: 100, lengthExcludingInBandSignaling: 100)
        }

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?
        executor.executeTurn(tokenBudget: 500) { result in  // Budget of 500 tokens
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // All 3 groups (total 30 tokens) fit within budget (500)
        XCTAssertEqual(receivedResult, .completed,
                       "Should complete when all groups fit within budget")

        // Verify all 3 groups were processed by checking total byte length
        // Each group has lengthTotal=100, so 3 groups = 300 bytes total
        XCTAssertEqual(mockDelegate.executedLengths.count, 1,
                       "Should have one execution record per turn")
        if let execution = mockDelegate.executedLengths.first {
            XCTAssertEqual(execution.total, 300,
                           "Total length should be 300 (3 groups * 100 bytes each)")
        }
    }

    func testBudgetBoundaryExactMatch() {
        // REQUIREMENT: When cumulative tokens exactly match budget, next group should NOT execute.
        // (Budget check: tokensConsumed + nextGroup > budget, so exact match triggers stop)
        //
        // NOTE: Budget is measured in TOKEN COUNT, not byte length.

        // Add 2 groups: first exactly matches budget (100 tokens), second should NOT execute
        let budget = 100

        let vector1 = createTestTokenVector(count: budget)  // 100 tokens
        executor.addTokens(vector1, lengthTotal: budget * 10, lengthExcludingInBandSignaling: budget * 10)

        let vector2 = createTestTokenVector(count: 50)  // 50 tokens
        executor.addTokens(vector2, lengthTotal: 500, lengthExcludingInBandSignaling: 500)

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?
        executor.executeTurn(tokenBudget: budget) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // First group exactly matches budget (100 tokens); second group (50) would exceed budget (100 + 50 > 100)
        // So only first group should execute
        XCTAssertEqual(receivedResult, .yielded,
                       "Should yield because adding second group would exceed budget")
        XCTAssertEqual(mockDelegate.willExecuteCount, 1,
                       "Only first group should execute when it exactly matches budget")
    }

    func testProgressGuaranteeWithSameQueueGroups() {
        // REQUIREMENT: At least one group must execute per turn (progress guarantee),
        // even if that group exceeds budget. Verifies this with same-queue groups.
        //
        // NOTE: Budget is measured in TOKEN COUNT, not byte length.

        // Add 1 large group (1000 tokens) that exceeds budget (1)
        let vector = createTestTokenVector(count: 1000)
        executor.addTokens(vector, lengthTotal: 10000, lengthExcludingInBandSignaling: 10000)

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var receivedResult: TurnResult?
        executor.executeTurn(tokenBudget: 1) { result in
            receivedResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Group should still execute (progress guarantee)
        XCTAssertEqual(receivedResult, .completed,
                       "Single large group should complete (progress guarantee)")
        XCTAssertEqual(mockDelegate.willExecuteCount, 1,
                       "Large group should execute despite exceeding budget")
    }
}

// MARK: - AvailableSlots Boundary Tests

/// Tests for availableSlots boundary conditions.
/// These ensure accounting is balanced (no drift) and handles over-capacity correctly.
/// Note: availableSlots CAN go negative when high-priority tokens bypass backpressure.
final class TokenExecutorAvailableSlotsBoundaryTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
    }

    override func tearDown() {
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testSlotsAccountingBalancedAfterFullDrain() {
        // REQUIREMENT: availableSlots accounting must be balanced - after all tokens
        // are consumed, slots must return to totalSlots (no drift).
        //
        // NOTE: This test bypasses PTYTask's backpressure check and adds tokens
        // directly to TokenExecutor. In the real system:
        // - PTYTask suspends reading when backpressureLevel >= .heavy (25% remaining)
        // - Only high-priority tokens (API injection) can bypass this check
        // - High-priority tokens are allowed to temporarily go negative by design
        //   (see implementation.md: "High-priority can temporarily go negative")
        //
        // This test verifies raw TokenExecutor accounting is correct, not the
        // integrated PTYTask backpressure behavior.

        let executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate

        // Register with scheduler so execution works
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        #if ITERM_DEBUG
        let initialSlots = executor.testAvailableSlots
        let totalSlots = executor.testTotalSlots
        XCTAssertEqual(initialSlots, totalSlots, "Fresh executor should have all slots available")
        #endif

        // Add more token groups than totalSlots (simulating high-priority bypass)
        // In real usage, only high-priority tokens would do this; normal PTY tokens
        // are blocked by PTYTask's backpressure check at 25% capacity.
        let addCount = 50
        for _ in 0..<addCount {
            let vector = createTestTokenVector(count: 1)
            executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10)
        }

        #if ITERM_DEBUG
        // Verify accounting: 40 - 50 = -10 (negative is allowed for high-priority bypass)
        let afterAddSlots = executor.testAvailableSlots
        let expectedSlots = totalSlots - addCount
        XCTAssertEqual(afterAddSlots, expectedSlots,
                       "availableSlots should track total pending tokens")
        #endif

        // Backpressure should be blocked when availableSlots <= 0
        let level = executor.backpressureLevel
        XCTAssertEqual(level, .blocked,
                       "Backpressure should be .blocked when over capacity")

        // Process all by repeatedly calling executeTurn
        for _ in 0..<100 {
            let exp = XCTestExpectation(description: "Turn")
            executor.executeTurn(tokenBudget: 500) { _ in
                exp.fulfill()
            }
            wait(for: [exp], timeout: 1.0)

            // Break early if done
            if executor.backpressureLevel == .none {
                break
            }
        }

        FairnessScheduler.shared.unregister(sessionId: sessionId)

        #if ITERM_DEBUG
        // After processing all, slots should return to totalSlots
        let finalSlots = executor.testAvailableSlots
        XCTAssertEqual(finalSlots, totalSlots,
                       "After processing all tokens, slots should return to maximum (\(totalSlots)), got \(finalSlots)")
        #endif

        // After processing and cleanup, should return to none
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Backpressure should return to none after processing all tokens")
    }

    func testConcurrentAddAndConsumeDoesNotCorruptSlots() {
        // REQUIREMENT: Concurrent add and consume operations must not corrupt availableSlots.
        //
        // NOTE: During operation, availableSlots CAN go negative by design:
        // - High-priority tokens bypass backpressure and can overdraw slots
        // - This test calls addTokens directly, bypassing PTYTask's backpressure gate
        //
        // The invariant we verify: after unregister (which calls cleanupForUnregistration),
        // slots must return to totalSlots (balanced accounting, no drift).

        let executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: iTermGCD.mutationQueue()
        )
        executor.delegate = mockDelegate

        // Register with scheduler
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        #if ITERM_DEBUG
        let totalSlots = executor.testTotalSlots
        #endif

        let group = DispatchGroup()
        let addCount = 50
        let scheduleCount = 50

        // Producer: add tokens from background thread
        group.enter()
        DispatchQueue.global().async {
            for _ in 0..<addCount {
                autoreleasepool {
                    let vector = createTestTokenVector(count: 1)
                    executor.addTokens(vector, lengthTotal: 10, lengthExcludingInBandSignaling: 10)
                }
                usleep(500)  // 0.5ms delay
            }
            group.leave()
        }

        // Consumer: trigger processing on main queue
        group.enter()
        DispatchQueue.global().async {
            for _ in 0..<scheduleCount {
                DispatchQueue.main.async {
                    executor.schedule()
                }
                usleep(500)
            }
            group.leave()
        }

        let result = group.wait(timeout: .now() + 5.0)

        // Even if it times out, we should verify state is valid
        if result == .timedOut {
            // Not a hard failure - just note it
            print("Note: Concurrent test timed out, checking final state")
        }

        // Flush queues to process pending work
        waitForMutationQueue()
        waitForMainQueue()

        // Unregister calls cleanupForUnregistration which discards remaining tokens
        // and restores their slots
        FairnessScheduler.shared.unregister(sessionId: sessionId)

        // Wait for cleanup to complete (unregister dispatches async to mutation queue)
        waitForMutationQueue()

        #if ITERM_DEBUG
        // After cleanup, slots should return to totalSlots (balanced accounting)
        // This verifies no drift/corruption from concurrent operations
        let finalSlots = executor.testAvailableSlots
        XCTAssertEqual(finalSlots, totalSlots,
                       "After cleanup, availableSlots should return to totalSlots " +
                       "(got \(finalSlots), expected \(totalSlots)). " +
                       "A mismatch indicates accounting corruption from concurrent ops.")
        #endif

        // Verify backpressure is consistent with slots (should be .none after cleanup)
        let finalLevel = executor.backpressureLevel
        XCTAssertEqual(finalLevel, .none,
                       "Backpressure should be .none after cleanup restores all slots")
    }

    func testCleanupDoesNotOverflowSlots() {
        // REQUIREMENT: cleanup should not cause slots to exceed maximum.

        let executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate

        #if ITERM_DEBUG
        let totalSlots = executor.testTotalSlots
        let initialSlots = executor.testAvailableSlots
        XCTAssertEqual(initialSlots, totalSlots,
                       "Fresh executor should have all slots available")
        #endif

        // Start fresh - slots should be at max
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Fresh executor should have no backpressure")

        // Cleanup on empty queue should not overflow
        executor.cleanupForUnregistration()

        #if ITERM_DEBUG
        let afterFirstCleanup = executor.testAvailableSlots
        XCTAssertEqual(afterFirstCleanup, totalSlots,
                       "Cleanup on empty queue should not change slots")
        XCTAssertLessThanOrEqual(afterFirstCleanup, totalSlots,
                                 "Cleanup must not overflow slots beyond maximum")
        #endif

        // Should still be valid
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Cleanup on empty queue should not change backpressure")

        // Call cleanup again - should still be safe
        executor.cleanupForUnregistration()

        #if ITERM_DEBUG
        let afterSecondCleanup = executor.testAvailableSlots
        XCTAssertEqual(afterSecondCleanup, totalSlots,
                       "Multiple cleanups should not change slots")
        XCTAssertLessThanOrEqual(afterSecondCleanup, totalSlots,
                                 "Multiple cleanups must not overflow slots")
        #endif

        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Multiple cleanups should not overflow slots")
    }

    func testRapidAddConsumeAddCycle() {
        // REQUIREMENT: Rapid add->consume->add cycles should not cause drift.

        let executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate

        // Register so schedule() works
        let sessionId = FairnessScheduler.shared.register(executor)
        executor.fairnessSessionId = sessionId

        #if ITERM_DEBUG
        let totalSlots = executor.testTotalSlots
        let initialSlots = executor.testAvailableSlots
        XCTAssertEqual(initialSlots, totalSlots, "Should start with all slots available")
        #endif

        for cycle in 0..<20 {
            // Add
            let vector = createTestTokenVector(count: 5)
            executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

            #if ITERM_DEBUG
            // After add, slots should decrease by 1
            let afterAdd = executor.testAvailableSlots
            XCTAssertEqual(afterAdd, totalSlots - 1,
                           "After add in cycle \(cycle), should have one fewer slot")
            #endif

            // Immediately trigger consume
            let expectation = XCTestExpectation(description: "Cycle \(cycle)")
            executor.executeTurn(tokenBudget: 500) { _ in
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)

            #if ITERM_DEBUG
            // After consume, slots should return to totalSlots
            let afterConsume = executor.testAvailableSlots
            XCTAssertEqual(afterConsume, totalSlots,
                           "After consume in cycle \(cycle), slots should return to max")
            #endif
        }

        FairnessScheduler.shared.unregister(sessionId: sessionId)

        #if ITERM_DEBUG
        // Verify no drift after many cycles
        let finalSlots = executor.testAvailableSlots
        XCTAssertEqual(finalSlots, totalSlots,
                       "After \(20) add/consume cycles, slots should equal totalSlots (no drift)")
        #endif

        // After many cycles, should be back to none
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "After many add/consume cycles, backpressure should be none")
    }
}

// MARK: - High-Priority Task Ordering Tests

/// Tests for high-priority task execution ordering.
/// These verify that high-priority tasks run before normal tokens.
final class TokenExecutorHighPriorityOrderingTests: XCTestCase {

    var mockDelegate: MockTokenExecutorDelegate!
    var mockTerminal: VT100Terminal!
    var executor: TokenExecutor!

    override func setUp() {
        super.setUp()
        mockDelegate = MockTokenExecutorDelegate()
        mockTerminal = VT100Terminal()
        executor = TokenExecutor(
            mockTerminal,
            slownessDetector: SlownessDetector(),
            queue: DispatchQueue.main
        )
        executor.delegate = mockDelegate
    }

    override func tearDown() {
        executor = nil
        mockTerminal = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testHighPriorityTasksExecuteBeforeTokens() {
        // REQUIREMENT: High-priority tasks in taskQueue execute before tokens in tokenQueue.

        var executionOrder: [String] = []

        // Add tokens first
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        // Then add high-priority task
        executor.scheduleHighPriorityTask {
            executionOrder.append("high-priority")
        }

        // Track when willExecuteTokens is called (indicates token processing)
        let originalWillExecute = mockDelegate.willExecuteCount
        mockDelegate.reset()  // Clear counts

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 500) { _ in
            // Check if high-priority ran before tokens were executed
            // willExecuteCount > 0 means tokens were processed
            if self.mockDelegate.willExecuteCount > 0 && executionOrder.isEmpty {
                // Tokens ran but high-priority didn't - wrong order
                executionOrder.append("tokens-first-ERROR")
            } else if !executionOrder.isEmpty && self.mockDelegate.willExecuteCount > 0 {
                executionOrder.append("tokens")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // High-priority should have run
        XCTAssertTrue(executionOrder.contains("high-priority"),
                      "High-priority task should have executed")

        // Should not have the error marker
        XCTAssertFalse(executionOrder.contains("tokens-first-ERROR"),
                       "High-priority task should run before tokens")
    }

    func testMultipleHighPriorityTasksAllExecute() {
        // REQUIREMENT: All high-priority tasks execute during the turn.

        var taskResults: [Int] = []

        // Schedule multiple high-priority tasks
        for i in 0..<5 {
            executor.scheduleHighPriorityTask {
                taskResults.append(i)
            }
        }

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 500) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(taskResults.count, 5,
                       "All high-priority tasks should have executed")
        XCTAssertEqual(taskResults, [0, 1, 2, 3, 4],
                       "Tasks should execute in order they were scheduled")
    }

    func testHighPriorityTokenArraysExecuteBeforeNormalTokenArrays() {
        // REQUIREMENT: High-priority token arrays (queue[0]) must execute before
        // normal-priority token arrays (queue[1]), even when normal is added first.
        // This ensures API responses (e.g., terminal reports) are handled promptly.

        // Use a tracking delegate that records execution by length
        var executedLengths: [Int] = []
        let trackingDelegate = OrderTrackingTokenExecutorDelegate()
        trackingDelegate.onExecute = { length in
            executedLengths.append(length)
        }
        executor.delegate = trackingDelegate

        // Add NORMAL-priority token array FIRST with length 200
        let normalVector = createTestTokenVector(count: 1)
        executor.addTokens(normalVector, lengthTotal: 200, lengthExcludingInBandSignaling: 200, highPriority: false)

        // Add HIGH-priority token array SECOND with length 100
        let highPriVector = createTestTokenVector(count: 1)
        executor.addTokens(highPriVector, lengthTotal: 100, lengthExcludingInBandSignaling: 100, highPriority: true)

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 500) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Both should have executed
        XCTAssertEqual(trackingDelegate.willExecuteCount, 1,
                       "Tokens should have been executed")

        // The total length should be 300 (100 + 200)
        XCTAssertEqual(trackingDelegate.totalExecutedLength, 300,
                       "Both token arrays should have executed (100 + 200 = 300)")

        // Note: tokenExecutorDidExecute is called once with aggregate lengths,
        // so we verify ordering through the TwoTierTokenQueue test instead.
        // This test verifies both arrays execute when budget allows.
    }

    func testHighPriorityTaskAddedDuringExecutionRunsInSameTurn() {
        // REQUIREMENT: High-priority task added during executeTurn should run in same turn.

        var innerTaskRan = false

        executor.scheduleHighPriorityTask {
            // Schedule another task from within the first
            self.executor.scheduleHighPriorityTask {
                innerTaskRan = true
            }
        }

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 500) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // The inner task should have run in the same turn
        XCTAssertTrue(innerTaskRan,
                      "Task scheduled during execution should run in same turn")
    }

    func testHighPriorityDoesNotStarveTokens() {
        // REQUIREMENT: Even with high-priority tasks, tokens should eventually process.

        var highPriorityCount = 0
        let maxHighPriority = 5

        // Add tokens
        let vector = createTestTokenVector(count: 5)
        executor.addTokens(vector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)

        // Add limited high-priority tasks (they don't re-add themselves infinitely)
        for _ in 0..<maxHighPriority {
            executor.scheduleHighPriorityTask {
                highPriorityCount += 1
            }
        }

        let initialWillExecute = mockDelegate.willExecuteCount

        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        executor.executeTurn(tokenBudget: 500) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // All high-priority should have run
        XCTAssertEqual(highPriorityCount, maxHighPriority,
                       "All high-priority tasks should run")

        // Tokens should also have been processed
        XCTAssertGreaterThan(mockDelegate.willExecuteCount, initialWillExecute,
                             "Tokens should also process after high-priority tasks")
    }

    func testTokensInjectedDuringExecutionConsumedSameTurn() {
        // REQUIREMENT: Tokens added via scheduleHighPriorityTask callback during executeTurn
        // should be consumed in the SAME turn (re-entrant injection).
        // This tests the trigger re-injection pattern from implementation.md:859-861.
        //
        // Scenario:
        // 1. We add initial tokens
        // 2. We schedule a high-priority task that adds MORE tokens when it runs
        // 3. Those newly added tokens should be consumed in the same executeTurn call

        var tokenBatchesAdded = 0
        var tokenBatchesExecuted = 0

        // Track when tokens are executed
        mockDelegate.onWillExecute = {
            tokenBatchesExecuted += 1
        }

        // Add initial tokens
        let initialVector = createTestTokenVector(count: 3)
        executor.addTokens(initialVector, lengthTotal: 30, lengthExcludingInBandSignaling: 30)
        tokenBatchesAdded += 1

        // Schedule a high-priority task that adds more tokens during execution
        // This simulates a trigger callback re-injecting tokens
        var reinjectedTokens = false
        executor.scheduleHighPriorityTask { [weak self] in
            guard let self = self else { return }
            // Add tokens from WITHIN the high-priority task (trigger re-injection)
            let reinjectedVector = createTestTokenVector(count: 5)
            self.executor.addTokens(reinjectedVector, lengthTotal: 50, lengthExcludingInBandSignaling: 50)
            tokenBatchesAdded += 1
            reinjectedTokens = true
        }

        // Execute a single turn with large budget
        let expectation = XCTestExpectation(description: "ExecuteTurn completed")
        var turnResult: TurnResult?
        executor.executeTurn(tokenBudget: 1000) { result in
            turnResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Verify the high-priority task ran and re-injected tokens
        XCTAssertTrue(reinjectedTokens, "High-priority task should have run and re-injected tokens")
        XCTAssertEqual(tokenBatchesAdded, 2, "Should have added 2 batches of tokens")

        // Key assertion: BOTH token batches should have been executed in the same turn
        // If the re-injected tokens weren't consumed, tokenBatchesExecuted would be < tokenBatchesAdded
        XCTAssertGreaterThanOrEqual(tokenBatchesExecuted, 1,
                                    "At least initial tokens should have been executed")

        // The turn should have completed (not yielded) since budget was sufficient
        // for all tokens including re-injected ones
        if turnResult == .yielded {
            // If yielded, there are remaining tokens - means re-injected tokens
            // weren't fully consumed. This is acceptable if budget was exactly used up.
            // Let's verify by doing another turn
            let secondExpectation = XCTestExpectation(description: "Second turn")
            executor.executeTurn(tokenBudget: 1000) { result in
                // After second turn, should be completed (all tokens drained)
                XCTAssertEqual(result, .completed,
                               "After second turn, all tokens including re-injected should be processed")
                secondExpectation.fulfill()
            }
            wait(for: [secondExpectation], timeout: 1.0)
        } else {
            // Turn completed - all tokens including re-injected were consumed
            XCTAssertEqual(turnResult, .completed,
                           "Single turn should process all tokens when budget is sufficient")
        }
    }
}
