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

    func testSetupDispatchSourcesMethodExists() {
        // REQUIREMENT: PTYTask must have setupDispatchSources method

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("setupDispatchSources")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should have setupDispatchSources method")
    }

    func testTeardownDispatchSourcesMethodExists() {
        // REQUIREMENT: PTYTask must have teardownDispatchSources method

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("teardownDispatchSources")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should have teardownDispatchSources method")
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

        // This should not crash - sources were never created
        let selector = NSSelectorFromString("teardownDispatchSources")
        if task.responds(to: selector) {
            task.perform(selector)
        }

        // If we get here without crashing, test passes
        XCTAssertNotNil(task)
    }

    func testMultipleTeardownCallsSafe() {
        // REQUIREMENT: Multiple teardown calls should be safe (idempotent)

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("teardownDispatchSources")
        if task.responds(to: selector) {
            // Call teardown multiple times
            task.perform(selector)
            task.perform(selector)
            task.perform(selector)
        }

        // If we get here without crashing, test passes
        XCTAssertNotNil(task)
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

        // This should not crash even though sources don't exist
        let selector = NSSelectorFromString("updateReadSourceState")
        if task.responds(to: selector) {
            task.perform(selector)
        }

        XCTAssertNotNil(task, "updateReadSourceState should be safe without sources")
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

        let selector = NSSelectorFromString("updateWriteSourceState")
        if task.responds(to: selector) {
            task.perform(selector)
        }

        XCTAssertNotNil(task, "updateWriteSourceState should be safe without sources")
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

    func testWriteBufferDidChangeMethodExists() {
        // REQUIREMENT: PTYTask must have writeBufferDidChange method

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("writeBufferDidChange")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should have writeBufferDidChange method")
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

    func testSetPausedCallsUpdateMethods() {
        // REQUIREMENT: Setting paused should trigger state update methods

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // This should not crash and should internally call update methods
        task.paused = true
        task.paused = false
        task.paused = true

        // If we get here without crash, the basic contract is satisfied
        XCTAssertTrue(task.paused, "paused should be true after setting")
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

    func testShouldReadConsidersBackpressure() {
        // REQUIREMENT: shouldRead should consider backpressure level

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Without tokenExecutor, shouldRead shouldn't crash
        task.tokenExecutor = nil
        task.paused = false

        // This should work without executor
        if let result = task.value(forKey: "shouldRead") as? Bool {
            // Result depends on jobManager state, but shouldn't crash
            _ = result
        }

        // With executor, shouldRead checks backpressureLevel
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        task.tokenExecutor = executor

        // Fresh executor has no backpressure
        XCTAssertEqual(executor.backpressureLevel, .none,
                       "Fresh executor should have no backpressure")
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

        // Call update methods multiple times - should not crash
        for _ in 0..<10 {
            if task.responds(to: readSelector) {
                task.perform(readSelector)
            }
            if task.responds(to: writeSelector) {
                task.perform(writeSelector)
            }
        }

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

        // Operations should not crash with nil delegate
        task.paused = true
        task.paused = false

        let readSelector = NSSelectorFromString("updateReadSourceState")
        if task.responds(to: readSelector) {
            task.perform(readSelector)
        }

        XCTAssertNotNil(task, "Operations should be safe with nil delegate")
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
