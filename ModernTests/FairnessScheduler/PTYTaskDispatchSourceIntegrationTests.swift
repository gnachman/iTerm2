//
//  PTYTaskDispatchSourceIntegrationTests.swift
//  ModernTests
//
//  Integration and edge case tests for PTYTask dispatch sources.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTaskBackpressureIntegrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Enable fairness scheduler so addTokens uses non-blocking path
        // (legacy path blocks on semaphore, which deadlocks tests that add >40 tokens)
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(true)
    }

    override func tearDown() {
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(false)
        super.tearDown()
    }

    func testTokenExecutorPropertyExists() {
        // REQUIREMENT: PTYTask must have tokenExecutor property for backpressure

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Verify tokenExecutor property exists and is settable
        // Initial value should be nil
        XCTAssertNil(task.tokenExecutor, "tokenExecutor should initially be nil")

        // Should be able to set it
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        task.tokenExecutor = executor

        XCTAssertNotNil(task.tokenExecutor, "tokenExecutor should be settable")
    }

    func testBackpressureHeavyWithPositiveSlotsStillSuspendsReadSource() {
        // REQUIREMENT: Heavy backpressure (ratio < 0.25, availableSlots > 0) should suspend read source
        // This tests the "heavy but not blocked" cutoff: backpressureLevel < .heavy gate
        //
        // PTYTask.shouldRead checks: backpressureLevel < BackpressureLevelHeavy
        // .heavy is NOT less than .heavy, so shouldRead=false when level is .heavy
        //
        // With totalSlots=40:
        // - .heavy occurs at ratio < 0.25, meaning available < 10
        // - .blocked occurs at available <= 0
        // Adding 35 tokens leaves 5 available → ratio 0.125 → .heavy (not .blocked)

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create a pipe for valid fd
        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        task.testSetFd(pipe.readFd)
        task.paused = false

        // Setup executor for backpressure tracking
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.testSkipNotifyScheduler = true
        task.tokenExecutor = executor

        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Fresh executor should have no backpressure")

        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Create .heavy backpressure (NOT .blocked) by consuming most but not all slots
        // With 40 slots, adding 35 leaves 5 available → ratio 0.125 → .heavy
        executor.addMultipleTokenArrays(count: 35, tokensPerArray: 5)

        // Verify we're at .heavy (not .blocked) with positive available slots
        XCTAssertEqual(executor.backpressureLevel, .heavy,
                       "Adding 35 tokens (of 40 slots) should cause .heavy backpressure")
        XCTAssertGreaterThan(executor.testAvailableSlots, 0,
                             "Should have positive availableSlots (not blocked)")

        // Trigger state update
        let selector = NSSelectorFromString("updateReadSourceState")
        if task.responds(to: selector) {
            task.perform(selector)
        }
        task.testWaitForIOQueue()

        // With .heavy backpressure, read source should be suspended
        // because shouldRead requires backpressureLevel < .heavy
        XCTAssertTrue(task.testIsReadSourceSuspended,
                      "Read source should be suspended at .heavy backpressure (even with availableSlots > 0)")

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
    }

    func testBackpressureBlockedSuspendsReadSource() {
        // REQUIREMENT: Blocked backpressure (availableSlots <= 0) should suspend read source

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create a pipe for valid fd
        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        task.testSetFd(pipe.readFd)
        task.paused = false

        // Setup executor for backpressure tracking
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.testSkipNotifyScheduler = true
        task.tokenExecutor = executor

        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Fresh executor should have no backpressure")

        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Create blocked backpressure by adding many token arrays (200 > 40 slots)
        executor.addMultipleTokenArrays(count: 200, tokensPerArray: 5)

        // Check backpressure level - should be blocked when exceeding capacity
        XCTAssertEqual(executor.backpressureLevel, .blocked,
                       "Adding more tokens than slots should cause blocked backpressure")

        // Trigger state update
        let selector = NSSelectorFromString("updateReadSourceState")
        if task.responds(to: selector) {
            task.perform(selector)
        }
        task.testWaitForIOQueue()

        // With blocked backpressure, read source should be suspended
        XCTAssertTrue(task.testIsReadSourceSuspended,
                      "Read source should be suspended with blocked backpressure")

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
    }

    func testBackpressureReleaseHandlerCanBeSet() {
        // REQUIREMENT: TokenExecutor's backpressureReleaseHandler should be settable

        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)

        var handlerCalled = false
        executor.backpressureReleaseHandler = {
            handlerCalled = true
        }

        XCTAssertNotNil(executor.backpressureReleaseHandler,
                        "backpressureReleaseHandler should be settable")
    }

    func testReadSourceResumesWhenBackpressureDrops() {
        // REQUIREMENT: Read source should resume when backpressure drops from heavy to below heavy
        // This tests the backpressure release -> read source resume path

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        task.testSetFd(pipe.readFd)
        task.paused = false

        // Setup executor for backpressure tracking
        let terminal = VT100Terminal()
        let mockDelegate = MockTokenExecutorDelegate()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: iTermGCD.mutationQueue())
        executor.delegate = mockDelegate
        executor.testSkipNotifyScheduler = true
        task.tokenExecutor = executor

        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Initially: no backpressure, fd valid, not paused -> read source should be resumed
        XCTAssertEqual(executor.backpressureLevel, .none)
        XCTAssertFalse(task.testIsReadSourceSuspended, "Read source should start resumed (no backpressure)")

        // Create blocked backpressure (200 tokens > 40 slots)
        executor.addMultipleTokenArrays(count: 200, tokensPerArray: 5)
        XCTAssertEqual(executor.backpressureLevel, .blocked, "Should be blocked when exceeding capacity")

        // Trigger state update
        task.perform(NSSelectorFromString("updateReadSourceState"))
        task.testWaitForIOQueue()

        // With blocked backpressure, read source should be suspended
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should suspend with blocked backpressure")

        // Set up handler to track heavy->non-heavy transition
        // The handler fires once per token group consumed, but we only care that
        // it fires at least once when transitioning from heavy to below heavy
        var handlerFired = false
        var wasHeavyWhenHandlerFired = false
        executor.backpressureReleaseHandler = { [weak task, weak executor] in
            if !handlerFired {
                handlerFired = true
                wasHeavyWhenHandlerFired = (executor?.backpressureLevel == .heavy)
            }
            // Handler should trigger read state re-evaluation
            task?.perform(NSSelectorFromString("updateReadSourceState"))
        }

        // Drain tokens by executing a turn with large budget (must run on mutation queue)
        let drainExpectation = XCTestExpectation(description: "Tokens drained")
        iTermGCD.mutationQueue().async {
            executor.executeTurn(tokenBudget: 10000) { result in
                drainExpectation.fulfill()
            }
        }
        wait(for: [drainExpectation], timeout: 2.0)

        // Give time for handler to fire and state to update
        task.testWaitForIOQueue()

        // Backpressure should now be below heavy
        XCTAssertNotEqual(executor.backpressureLevel, .heavy,
                          "Backpressure should drop after draining tokens")

        // Handler should have fired (at least once during the drain)
        XCTAssertTrue(handlerFired,
                       "backpressureReleaseHandler should fire when backpressure drops")

        // Read source should have resumed
        XCTAssertFalse(task.testIsReadSourceSuspended,
                       "Read source should RESUME after backpressure drops")

        task.testTeardownDispatchSourcesForTesting()
    }

    func testDidRegisterWiresBackpressureBeforeStartingSources() {
        // REQUIREMENT: didRegister must call taskDidRegister: (which wires tokenExecutor)
        // BEFORE setupDispatchSources. If sources start first, shouldRead sees executor==nil
        // and skips backpressure checks, allowing unconditional reads.
        //
        // This test wires heavy backpressure in the taskDidRegister: callback.
        // If ordering is correct: sources see the executor with heavy backpressure → suspended.
        // If ordering is wrong: sources see executor==nil → no backpressure → resumed.

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        task.testSetFd(pipe.readFd)
        task.paused = false

        let mockDelegate = MockPTYTaskDelegate()

        // In taskDidRegister:, wire up a tokenExecutor with heavy backpressure.
        // This simulates what PTYSession.taskDidRegister: does in production.
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.testSkipNotifyScheduler = true

        mockDelegate.onTaskDidRegister = { registeredTask in
            registeredTask.tokenExecutor = executor
            // Create .heavy backpressure (35 of 40 slots consumed → ratio 0.125 → .heavy)
            executor.addMultipleTokenArrays(count: 35, tokensPerArray: 5)
        }

        task.delegate = mockDelegate

        // Call didRegister — this triggers taskDidRegister: then setupDispatchSources
        task.perform(NSSelectorFromString("didRegister"))
        task.testWaitForIOQueue()

        // Verify executor was wired
        XCTAssertNotNil(task.tokenExecutor, "tokenExecutor should be wired by taskDidRegister:")
        XCTAssertEqual(executor.backpressureLevel, .heavy,
                       "Backpressure should be heavy after registration callback")

        // The critical assertion: read source should be SUSPENDED because backpressure
        // was already heavy when setupDispatchSources evaluated shouldRead.
        // If didRegister had the wrong order (sources before wiring), the read source
        // would be RESUMED because shouldRead with nil executor skips backpressure.
        XCTAssertTrue(task.testIsReadSourceSuspended,
                      "Read source should start suspended when backpressure is heavy at registration time")

        task.testTeardownDispatchSourcesForTesting()
    }

    func testDidRegisterWithPreloadedDataDoesNotLeakReads() {
        // REQUIREMENT: When data is already readable on the fd at registration time
        // and backpressure is heavy, no threadedReadTask callback should fire.
        //
        // setupDispatchSources does dispatch_resume then dispatch_suspend on the read
        // source (required to transition from "created" to "suspended" state in GCD).
        // If a read event slips through that window, it would bypass backpressure.
        // This test preloads data on the pipe before calling didRegister, then verifies
        // zero delegate callbacks under heavy backpressure.

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        task.testSetFd(pipe.readFd)
        task.paused = false

        let mockDelegate = MockPTYTaskDelegate()

        // Wire heavy backpressure in the taskDidRegister callback (same as production)
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.testSkipNotifyScheduler = true

        mockDelegate.onTaskDidRegister = { registeredTask in
            registeredTask.tokenExecutor = executor
            executor.addMultipleTokenArrays(count: 35, tokensPerArray: 5)
        }

        task.delegate = mockDelegate

        // Preload data on the pipe BEFORE registration so the fd is already readable
        let preloadData = "preloaded data that should not leak through".data(using: .utf8)!
        preloadData.withUnsafeBytes { bufferPointer in
            _ = Darwin.write(pipe.writeFd, bufferPointer.baseAddress!, preloadData.count)
        }

        // Call didRegister — wires backpressure, then sets up dispatch sources
        task.perform(NSSelectorFromString("didRegister"))

        // Wait for IO queue to drain any pending events from the resume/suspend window
        task.testWaitForIOQueue()

        // Wait again — if a read event was queued during the brief resume, it would
        // have dispatched back to IO queue by now
        task.testWaitForIOQueue()

        // The critical assertion: no data should have been delivered to the delegate.
        // The read source should be suspended due to heavy backpressure, and the brief
        // resume/suspend window in setupDispatchSources must not leak events.
        XCTAssertEqual(mockDelegate.readCallCount, 0,
                       "No threadedReadTask should fire when data is preloaded but backpressure is heavy at registration")

        XCTAssertTrue(task.testIsReadSourceSuspended,
                      "Read source should remain suspended under heavy backpressure")

        task.testTeardownDispatchSourcesForTesting()
    }

    func testHeavyBackpressureStopsDataFlow() {
        // REQUIREMENT: When backpressure becomes heavy, the read source should be suspended
        // AND data should actually stop being delivered to the delegate.
        // This is the end-to-end verification that backpressure throttling works.

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        // Create mock delegate to track data flow
        let mockDelegate = MockPTYTaskDelegate()
        task.delegate = mockDelegate

        task.testSetFd(pipe.readFd)
        task.paused = false

        // Setup executor for backpressure tracking
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        executor.testSkipNotifyScheduler = true
        task.tokenExecutor = executor

        // Set up expectation BEFORE starting anything
        let readExpectation = XCTestExpectation(description: "Data read with no backpressure")
        mockDelegate.onThreadedRead = { _ in
            readExpectation.fulfill()
        }

        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        XCTAssertEqual(executor.backpressureLevel, .none)
        XCTAssertFalse(task.testIsReadSourceSuspended, "Read source should start resumed")

        // Step 1: Verify data flows when backpressure is low
        let initialReadCount = mockDelegate.readCallCount
        let testData1 = "Initial data flow test".data(using: .utf8)!
        testData1.withUnsafeBytes { bufferPointer in
            let rawPointer = bufferPointer.baseAddress!
            _ = Darwin.write(pipe.writeFd, rawPointer, testData1.count)
        }

        // Wait for data to be read
        wait(for: [readExpectation], timeout: 2.0)

        XCTAssertGreaterThan(mockDelegate.readCallCount, initialReadCount,
                             "Data should flow when backpressure is low")

        // Clear the callback for next phase
        mockDelegate.onThreadedRead = nil

        // Step 2: Create blocked backpressure (200 tokens > 40 slots)
        executor.addMultipleTokenArrays(count: 200, tokensPerArray: 5)
        XCTAssertEqual(executor.backpressureLevel, .blocked, "Should be blocked when exceeding capacity")

        // Trigger state update
        task.perform(NSSelectorFromString("updateReadSourceState"))
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should suspend with blocked backpressure")

        // Step 3: Write more data - it should NOT be delivered while suspended
        let readCountBeforeWrite = mockDelegate.readCallCount
        let testData2 = "Data during blocked backpressure".data(using: .utf8)!
        testData2.withUnsafeBytes { bufferPointer in
            let rawPointer = bufferPointer.baseAddress!
            _ = Darwin.write(pipe.writeFd, rawPointer, testData2.count)
        }

        // Flush queues to ensure any pending dispatch source events would have been processed
        task.testWaitForIOQueue()
        waitForMainQueue()

        // Data should NOT have been read (source is suspended)
        XCTAssertEqual(mockDelegate.readCallCount, readCountBeforeWrite,
                       "Data should NOT be delivered when read source is suspended due to blocked backpressure")

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
    }
}

// MARK: - 3.7 useDispatchSource Protocol Tests

/// Tests for the useDispatchSource protocol method (3.7)
final class PTYTaskEdgeCaseTests: XCTestCase {

    func testFreshTaskHasValidState() {
        // REQUIREMENT: Fresh PTYTask should have consistent initial state

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Fresh task should not be paused
        XCTAssertFalse(task.paused, "Fresh task should not be paused")

        // Fresh task has fd = -1 (no process)
        XCTAssertEqual(task.fd, -1, "Fresh task should have invalid fd")

        // Fresh task has no tokenExecutor
        XCTAssertNil(task.tokenExecutor, "Fresh task should have nil tokenExecutor")
    }

    func testTaskWithNilDelegate() {
        // REQUIREMENT: Task should handle nil delegate gracefully

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Ensure delegate is nil
        task.delegate = nil
        XCTAssertNil(task.delegate, "Delegate should be nil for this test")

        // Operations should not crash with nil delegate
        task.paused = true
        XCTAssertTrue(task.paused, "Pause should work with nil delegate")

        task.paused = false
        XCTAssertFalse(task.paused, "Unpause should work with nil delegate")

        // Verify shouldRead/shouldWrite don't crash with nil delegate
        if let shouldRead = task.value(forKey: "shouldRead") as? Bool {
            // With nil delegate and no job manager, shouldRead is likely false
            // The important thing is it didn't crash
            XCTAssertFalse(shouldRead, "shouldRead should be false without job manager")
        }

        if let shouldWrite = task.value(forKey: "shouldWrite") as? Bool {
            // With nil delegate and no buffer, shouldWrite should be false
            XCTAssertFalse(shouldWrite, "shouldWrite should be false without job manager")
        }

        // Update methods should be safe with nil delegate
        let readSelector = NSSelectorFromString("updateReadSourceState")
        let writeSelector = NSSelectorFromString("updateWriteSourceState")

        if task.responds(to: readSelector) {
            task.perform(readSelector)
        }
        if task.responds(to: writeSelector) {
            task.perform(writeSelector)
        }

        // State should be valid after operations
        // No sources should have been created (no valid fd)
        XCTAssertFalse(task.testHasReadSource, "No read source with nil delegate")
        XCTAssertFalse(task.testHasWriteSource, "No write source with nil delegate")

        XCTAssertNotNil(task, "Task should remain valid with nil delegate")
    }

    func testConcurrentPauseChanges() {
        // REQUIREMENT: Concurrent pause changes should be thread-safe

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let group = DispatchGroup()

        // Toggle pause from multiple threads
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                for _ in 0..<100 {
                    task.paused = true
                    task.paused = false
                }
                group.leave()
            }
        }

        // No timeout - operations are bounded (10 threads × 100 iterations each)
        // If there's a deadlock, test runner will kill the test
        group.wait()
    }
}

// MockPTYTaskDelegate is defined in Mocks/MockPTYTaskDelegate.swift

// MARK: - Read Handler Pipeline Tests

/// Tests for the read handler pipeline (read → threadedReadTask)
/// These tests verify that data flows correctly from dispatch source to delegate
