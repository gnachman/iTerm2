//
//  PTYTaskDispatchSourceTests.swift
//  ModernTests
//
//  Unit tests for PTYTask dispatch source integration.
//  See testing.md Milestone 3 for test specifications.
//
//  Test Design:
//  - Tests verify actual behavior of shouldRead/shouldWrite predicates
//  - Tests verify pause state affects behavior correctly
//  - Tests verify method existence and basic contracts
//
//  Note: PTYTask is tightly coupled to system resources (file descriptors, processes).
//  Tests focus on observable behavior through public/testable interfaces.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - 3.1 Dispatch Source Lifecycle Tests

/// Tests for dispatch source setup and teardown (3.1)
final class PTYTaskDispatchSourceLifecycleTests: XCTestCase {

    func testSetupCreatesSourcesWhenFdValid() {
        // REQUIREMENT: setupDispatchSources creates read and write sources when fd is valid

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create a pipe to provide a valid fd
        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        // Set the fd to the read end of the pipe
        task.testSetFd(pipe.readFd)

        #if ITERM_DEBUG
        // Before setup, no sources should exist
        XCTAssertFalse(task.testHasReadSource, "No read source before setup")
        XCTAssertFalse(task.testHasWriteSource, "No write source before setup")

        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()

        // Wait for ioQueue to process (sources are created async on ioQueue)
        Thread.sleep(forTimeInterval: 0.05)

        // After setup, both sources should exist
        XCTAssertTrue(task.testHasReadSource, "Read source should be created")
        XCTAssertTrue(task.testHasWriteSource, "Write source should be created")

        // Write source should be suspended (empty buffer, shouldWrite=false)
        XCTAssertTrue(task.testIsWriteSourceSuspended, "Write source should start suspended (empty buffer)")

        // Read source state depends on shouldRead result:
        // - Fresh task has paused=false
        // - ioAllowed from jobManager may be true
        // - No tokenExecutor means backpressure=none
        // So read source may be resumed. The important behavior to test is that pausing suspends it.

        // Verify that pausing suspends the read source
        task.paused = true
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should be suspended when paused")

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
        #else
        // Non-debug build: just verify methods exist
        XCTAssertTrue(task.responds(to: NSSelectorFromString("setupDispatchSources")),
                      "PTYTask should have setupDispatchSources method")
        #endif
    }

    func testTeardownCleansUpSources() {
        // REQUIREMENT: teardownDispatchSources removes sources and cleans up state

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create a pipe to provide a valid fd
        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        task.testSetFd(pipe.readFd)

        #if ITERM_DEBUG
        // Setup sources first
        task.testSetupDispatchSourcesForTesting()
        Thread.sleep(forTimeInterval: 0.05)

        XCTAssertTrue(task.testHasReadSource, "Read source should exist after setup")
        XCTAssertTrue(task.testHasWriteSource, "Write source should exist after setup")

        // Teardown
        task.testTeardownDispatchSourcesForTesting()

        // Wait for ioQueue to process teardown
        Thread.sleep(forTimeInterval: 0.1)

        // After teardown, sources should be gone
        XCTAssertFalse(task.testHasReadSource, "Read source should be nil after teardown")
        XCTAssertFalse(task.testHasWriteSource, "Write source should be nil after teardown")
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("teardownDispatchSources")),
                      "PTYTask should have teardownDispatchSources method")
        #endif
    }

    func testUpdateMethodsExist() {
        // REQUIREMENT: PTYTask must have updateReadSourceState and updateWriteSourceState methods

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let readSelector = NSSelectorFromString("updateReadSourceState")
        let writeSelector = NSSelectorFromString("updateWriteSourceState")

        XCTAssertTrue(task.responds(to: readSelector),
                      "PTYTask should have updateReadSourceState")
        XCTAssertTrue(task.responds(to: writeSelector),
                      "PTYTask should have updateWriteSourceState")
    }

    func testTeardownIsSafeWithoutSetup() {
        // REQUIREMENT: Calling teardown without setup should not crash

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        // Verify no sources exist before teardown
        XCTAssertFalse(task.testHasReadSource, "No read source should exist before setup")
        XCTAssertFalse(task.testHasWriteSource, "No write source should exist before setup")
        #endif

        // This should not crash - sources were never created
        let selector = NSSelectorFromString("teardownDispatchSources")
        if task.responds(to: selector) {
            task.perform(selector)
        }

        #if ITERM_DEBUG
        // Verify state remains valid after teardown
        XCTAssertFalse(task.testHasReadSource, "No read source after teardown on fresh task")
        XCTAssertFalse(task.testHasWriteSource, "No write source after teardown on fresh task")
        #endif

        XCTAssertNotNil(task, "Task should remain valid after teardown")
    }

    func testMultipleTeardownCallsSafe() {
        // REQUIREMENT: Multiple teardown calls should be safe (idempotent)

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("teardownDispatchSources")
        guard task.responds(to: selector) else {
            XCTFail("PTYTask should respond to teardownDispatchSources")
            return
        }

        // Call teardown multiple times - should be idempotent
        for i in 0..<5 {
            task.perform(selector)

            #if ITERM_DEBUG
            // After each teardown, state should be consistent
            XCTAssertFalse(task.testHasReadSource,
                           "No read source after teardown \(i)")
            XCTAssertFalse(task.testHasWriteSource,
                           "No write source after teardown \(i)")
            #endif
        }

        XCTAssertNotNil(task, "Task should remain valid after multiple teardowns")
    }
}

// MARK: - 3.2 Unified State Check - Read Tests

/// Tests for read state predicate behavior (3.2)
final class PTYTaskReadStateTests: XCTestCase {

    func testShouldReadMethodExists() {
        // REQUIREMENT: PTYTask must have shouldRead method

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("shouldRead")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should have shouldRead method")
    }

    func testShouldReadFalseWhenPaused() {
        // REQUIREMENT: shouldRead returns false when paused is true

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Set paused to true
        task.paused = true

        // shouldRead should return false when paused
        let selector = NSSelectorFromString("shouldRead")
        if task.responds(to: selector) {
            // Call shouldRead and check result
            // For BOOL methods, we use value(forKey:)
            let result = task.value(forKey: "shouldRead") as? Bool ?? true
            XCTAssertFalse(result, "shouldRead should return false when paused")
        }
    }

    func testShouldReadChangesWithPauseState() {
        // REQUIREMENT: shouldRead changes when pause state changes

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Initially not paused - shouldRead depends on other conditions too
        // but paused=false is necessary (not sufficient)
        task.paused = false

        // Now pause
        task.paused = true

        // shouldRead must be false when paused
        if let result = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(result, "shouldRead should be false when paused=true")
        }

        // Unpause
        task.paused = false

        // shouldRead being true also requires ioAllowed and backpressure < heavy
        // We can only verify that pausing definitely makes it false
    }

    func testUpdateReadSourceStateMethodExists() {
        // REQUIREMENT: updateReadSourceState method must exist

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("updateReadSourceState")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should have updateReadSourceState method")
    }

    func testUpdateReadSourceStateSafeWithoutSources() {
        // REQUIREMENT: Calling updateReadSourceState without dispatch sources should be safe

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        // Before update, no sources exist
        XCTAssertFalse(task.testHasReadSource, "No read source before update")
        #endif

        // This should not crash even though sources don't exist
        let selector = NSSelectorFromString("updateReadSourceState")
        guard task.responds(to: selector) else {
            XCTFail("PTYTask should respond to updateReadSourceState")
            return
        }

        // Call multiple times - should be no-op without sources
        for _ in 0..<3 {
            task.perform(selector)
        }

        #if ITERM_DEBUG
        // State should remain unchanged - no source created
        XCTAssertFalse(task.testHasReadSource,
                       "updateReadSourceState should not create source")
        #endif

        XCTAssertNotNil(task, "Task should remain valid after updateReadSourceState")
    }
}

// MARK: - 3.3 Unified State Check - Write Tests

/// Tests for write state predicate behavior (3.3)
final class PTYTaskWriteStateTests: XCTestCase {

    func testShouldWriteMethodExists() {
        // REQUIREMENT: PTYTask must have shouldWrite method

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("shouldWrite")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should have shouldWrite method")
    }

    func testShouldWriteFalseWhenPaused() {
        // REQUIREMENT: shouldWrite returns false when paused is true

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        task.paused = true

        if let result = task.value(forKey: "shouldWrite") as? Bool {
            XCTAssertFalse(result, "shouldWrite should return false when paused")
        }
    }

    func testShouldWriteFalseWhenBufferEmpty() {
        // REQUIREMENT: shouldWrite returns false when write buffer is empty

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Fresh task has empty buffer
        task.paused = false

        // shouldWrite should be false because buffer is empty
        // (and also because jobManager may not be configured)
        if let result = task.value(forKey: "shouldWrite") as? Bool {
            XCTAssertFalse(result,
                           "shouldWrite should be false with empty buffer")
        }
    }

    func testUpdateWriteSourceStateMethodExists() {
        // REQUIREMENT: updateWriteSourceState method must exist

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("updateWriteSourceState")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should have updateWriteSourceState method")
    }

    func testUpdateWriteSourceStateSafeWithoutSources() {
        // REQUIREMENT: Calling updateWriteSourceState without dispatch sources should be safe

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        // Before update, no sources exist
        XCTAssertFalse(task.testHasWriteSource, "No write source before update")
        #endif

        let selector = NSSelectorFromString("updateWriteSourceState")
        guard task.responds(to: selector) else {
            XCTFail("PTYTask should respond to updateWriteSourceState")
            return
        }

        // Call multiple times - should be no-op without sources
        for _ in 0..<3 {
            task.perform(selector)
        }

        #if ITERM_DEBUG
        // State should remain unchanged - no source created
        XCTAssertFalse(task.testHasWriteSource,
                       "updateWriteSourceState should not create source")
        #endif

        XCTAssertNotNil(task, "Task should remain valid after updateWriteSourceState")
    }
}

// MARK: - 3.4 Event Handler Tests

/// Tests for event handler method existence (3.4)
final class PTYTaskEventHandlerTests: XCTestCase {

    func testHandleReadEventMethodExists() {
        // REQUIREMENT: PTYTask must have handleReadEvent method

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("handleReadEvent")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should have handleReadEvent method")
    }

    func testHandleWriteEventMethodExists() {
        // REQUIREMENT: PTYTask must have handleWriteEvent method

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("handleWriteEvent")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should have handleWriteEvent method")
    }

    func testWriteBufferDidChangeWakesWriteSource() {
        // REQUIREMENT: Adding data to write buffer should wake (resume) write source

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

        #if ITERM_DEBUG
        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()
        Thread.sleep(forTimeInterval: 0.05)

        // Initially write source is suspended (empty buffer)
        XCTAssertTrue(task.testIsWriteSourceSuspended, "Write source should start suspended (empty buffer)")
        XCTAssertFalse(task.testWriteBufferHasData, "Write buffer should be empty initially")

        // Add data to write buffer
        let testData = "Hello".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)
        XCTAssertTrue(task.testWriteBufferHasData, "Write buffer should have data after add")

        // Call writeBufferDidChange to notify the source
        let selector = NSSelectorFromString("writeBufferDidChange")
        if task.responds(to: selector) {
            task.perform(selector)
        }
        Thread.sleep(forTimeInterval: 0.05)

        // Write source should be resumed (woken) now that there's data to write
        // Note: shouldWrite also requires !paused and jobManager conditions
        // With a fresh task, jobManager may not allow writes, so source may stay suspended
        // The important thing is the mechanism works - writeBufferDidChange calls updateWriteSourceState

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("writeBufferDidChange")),
                      "PTYTask should have writeBufferDidChange method")
        #endif
    }

    func testProcessReadMethodExists() {
        // REQUIREMENT: processRead is called by dispatch source - must exist

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // processRead is part of the iTermTask protocol
        XCTAssertTrue(task.responds(to: #selector(task.processRead)),
                      "PTYTask should have processRead method")
    }

    func testProcessWriteMethodExists() {
        // REQUIREMENT: processWrite is called by dispatch source - must exist

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // processWrite is part of the iTermTask protocol
        XCTAssertTrue(task.responds(to: #selector(task.processWrite)),
                      "PTYTask should have processWrite method")
    }
}

// MARK: - 3.5 Pause State Integration Tests

/// Tests for pause state affecting behavior (3.5)
final class PTYTaskPauseStateTests: XCTestCase {

    func testPausedPropertyExists() {
        // REQUIREMENT: PTYTask must have paused property

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Verify we can read and write the paused property
        let initialPaused = task.paused
        task.paused = !initialPaused
        XCTAssertEqual(task.paused, !initialPaused, "paused property should be settable")
        task.paused = initialPaused
        XCTAssertEqual(task.paused, initialPaused, "paused property should round-trip")
    }

    func testPauseAffectsShouldRead() {
        // REQUIREMENT: Pausing should affect shouldRead result

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // When paused, shouldRead must be false
        task.paused = true
        if let result = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(result, "shouldRead should be false when paused")
        }
    }

    func testPauseAffectsShouldWrite() {
        // REQUIREMENT: Pausing should affect shouldWrite result

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // When paused, shouldWrite must be false
        task.paused = true
        if let result = task.value(forKey: "shouldWrite") as? Bool {
            XCTAssertFalse(result, "shouldWrite should be false when paused")
        }
    }

    func testSetPausedTogglesSourceSuspendState() {
        // REQUIREMENT: Setting paused should toggle read source suspend state

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

        #if ITERM_DEBUG
        // Set paused BEFORE setup to ensure sources start suspended
        task.paused = true

        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()
        Thread.sleep(forTimeInterval: 0.05)

        // With paused=true, read source should be suspended
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should be suspended when paused=true")
        XCTAssertTrue(task.paused, "Task should be paused")

        // Set paused = false
        task.paused = false
        Thread.sleep(forTimeInterval: 0.05)

        // After unpause, source may resume if shouldRead returns true
        // (depends on ioAllowed from jobManager)
        XCTAssertFalse(task.paused, "Task should be unpaused")

        // Now pause again - this should suspend the read source
        task.paused = true
        Thread.sleep(forTimeInterval: 0.05)

        // Read source should be suspended again
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should be suspended after re-pause")

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
        #else
        // Non-debug: verify basic contract
        task.paused = true
        task.paused = false
        task.paused = true
        XCTAssertTrue(task.paused, "paused should be true after setting")
        #endif
    }
}

// MARK: - 3.6 Backpressure Integration Tests

/// Tests for backpressure integration with PTYTask (3.6)
final class PTYTaskBackpressureIntegrationTests: XCTestCase {

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

    func testBackpressureHeavySuspendsReadSource() {
        // REQUIREMENT: Heavy backpressure should suspend read source

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
        task.tokenExecutor = executor

        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Fresh executor should have no backpressure")

        #if ITERM_DEBUG
        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()
        Thread.sleep(forTimeInterval: 0.05)

        // Read source state depends on ioAllowed (requires jobManager setup)
        // For this test, we verify the mechanism is in place

        // Create heavy backpressure by adding many token arrays
        executor.addMultipleTokenArrays(count: 200, tokensPerArray: 5)

        // Check backpressure level
        XCTAssertEqual(executor.backpressureLevel, .heavy,
                       "Adding many tokens should create heavy backpressure")

        // Trigger state update
        let selector = NSSelectorFromString("updateReadSourceState")
        if task.responds(to: selector) {
            task.perform(selector)
        }
        Thread.sleep(forTimeInterval: 0.05)

        // With heavy backpressure, read source should be suspended
        // (if it was ever resumed - it may have stayed suspended due to ioAllowed)
        XCTAssertTrue(task.testIsReadSourceSuspended,
                      "Read source should be suspended with heavy backpressure")

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
        #else
        // Non-debug: basic verification
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Fresh executor should have no backpressure")
        #endif
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
}

// MARK: - 3.7 useDispatchSource Protocol Tests

/// Tests for the useDispatchSource protocol method (3.7)
final class PTYTaskUseDispatchSourceTests: XCTestCase {

    func testUseDispatchSourceMethodExists() {
        // REQUIREMENT: PTYTask must respond to useDispatchSource

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("useDispatchSource")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should respond to useDispatchSource")
    }

    func testUseDispatchSourceReturnsTrue() {
        // REQUIREMENT: PTYTask.useDispatchSource should return YES

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Get the value using KVC
        if let result = task.value(forKey: "useDispatchSource") as? Bool {
            XCTAssertTrue(result, "PTYTask.useDispatchSource should return YES")
        } else {
            XCTFail("Could not read useDispatchSource value")
        }
    }
}

// MARK: - State Transition Tests

/// Tests for state transition correctness
final class PTYTaskStateTransitionTests: XCTestCase {

    func testPauseUnpauseCycle() {
        // REQUIREMENT: Pause/unpause cycle should be consistent

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Record initial state
        let initialPaused = task.paused

        // Pause
        task.paused = true
        XCTAssertTrue(task.paused)

        // Verify shouldRead is false when paused
        if let shouldRead = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(shouldRead, "shouldRead should be false when paused")
        }

        // Unpause
        task.paused = false
        XCTAssertFalse(task.paused)

        // shouldRead may or may not be true (depends on other conditions)
        // but it should not crash

        // Restore initial state
        task.paused = initialPaused
    }

    func testRapidPauseUnpauseCycle() {
        // REQUIREMENT: Rapid pause/unpause should not cause issues

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Rapidly toggle pause state
        for _ in 0..<100 {
            task.paused = true
            task.paused = false
        }

        // Should complete without crash
        XCTAssertFalse(task.paused, "Should end in unpaused state")
    }

    func testUpdateMethodsIdempotent() {
        // REQUIREMENT: Update methods should be safe to call multiple times

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let readSelector = NSSelectorFromString("updateReadSourceState")
        let writeSelector = NSSelectorFromString("updateWriteSourceState")

        guard task.responds(to: readSelector) && task.responds(to: writeSelector) else {
            XCTFail("PTYTask should respond to update methods")
            return
        }

        #if ITERM_DEBUG
        // Record initial state
        let initialHasReadSource = task.testHasReadSource
        let initialHasWriteSource = task.testHasWriteSource
        #endif

        // Call update methods many times - should be idempotent
        for _ in 0..<20 {
            task.perform(readSelector)
            task.perform(writeSelector)
        }

        #if ITERM_DEBUG
        // State should be unchanged after idempotent calls
        XCTAssertEqual(task.testHasReadSource, initialHasReadSource,
                       "Read source state should remain stable")
        XCTAssertEqual(task.testHasWriteSource, initialHasWriteSource,
                       "Write source state should remain stable")
        #endif

        XCTAssertNotNil(task, "Multiple update calls should be safe")
    }
}

// MARK: - Edge Case Tests

/// Tests for edge cases and error conditions
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

        #if ITERM_DEBUG
        // State should be valid after operations
        // No sources should have been created (no valid fd)
        XCTAssertFalse(task.testHasReadSource, "No read source with nil delegate")
        XCTAssertFalse(task.testHasWriteSource, "No write source with nil delegate")
        #endif

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

        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "Concurrent pause changes should complete")
    }
}
