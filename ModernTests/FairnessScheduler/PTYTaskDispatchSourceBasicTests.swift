//
//  PTYTaskDispatchSourceBasicTests.swift
//  ModernTests
//
//  Basic dispatch source tests: lifecycle, protocol, state transitions.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - 3.1 Dispatch Source Lifecycle Tests

/// Tests for dispatch source setup and teardown (3.1)
final class PTYTaskDispatchSourceLifecycleTests: XCTestCase {

    func testSetupCreatesSourcesWhenFdValid() throws {
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

        // Before setup, no sources should exist
        XCTAssertFalse(task.testHasReadSource, "No read source before setup")
        XCTAssertFalse(task.testHasWriteSource, "No write source before setup")

        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()

        // Wait for ioQueue to process (sources are created async on ioQueue)
        task.testWaitForIOQueue()

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
        task.testWaitForIOQueue()
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should be suspended when paused")

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
    }

    func testTeardownCleansUpSources() throws {
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

        // Setup sources first
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testHasReadSource, "Read source should exist after setup")
        XCTAssertTrue(task.testHasWriteSource, "Write source should exist after setup")

        // Teardown
        task.testTeardownDispatchSourcesForTesting()

        // Wait for ioQueue to process teardown
        task.testWaitForIOQueue()

        // After teardown, sources should be gone
        XCTAssertFalse(task.testHasReadSource, "Read source should be nil after teardown")
        XCTAssertFalse(task.testHasWriteSource, "Write source should be nil after teardown")
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

        // Verify no sources exist before teardown
        XCTAssertFalse(task.testHasReadSource, "No read source should exist before setup")
        XCTAssertFalse(task.testHasWriteSource, "No write source should exist before setup")

        // This should not crash - sources were never created
        let selector = NSSelectorFromString("teardownDispatchSources")
        if task.responds(to: selector) {
            task.perform(selector)
        }

        // Verify state remains valid after teardown
        XCTAssertFalse(task.testHasReadSource, "No read source after teardown on fresh task")
        XCTAssertFalse(task.testHasWriteSource, "No write source after teardown on fresh task")

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

            // After each teardown, state should be consistent
            XCTAssertFalse(task.testHasReadSource,
                           "No read source after teardown \(i)")
            XCTAssertFalse(task.testHasWriteSource,
                           "No write source after teardown \(i)")
        }

        XCTAssertNotNil(task, "Task should remain valid after multiple teardowns")
    }

    // MARK: - Gap 2: Teardown with Suspended Sources

    func testTeardownWithSuspendedReadSource() throws {
        // GAP 2: Verify teardown doesn't crash when read source is suspended.
        // dispatch_source_cancel on a suspended source crashes unless resumed first.
        // The implementation must resume before canceling.

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

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Force read source to suspend by pausing
        task.paused = true
        task.testWaitForIOQueue()
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should be suspended when paused")

        // Teardown with suspended read source - should NOT crash
        task.testTeardownDispatchSourcesForTesting()

        // If we get here, test passed (no crash)
        XCTAssertFalse(task.testHasReadSource, "Read source should be nil after teardown")
    }

    func testTeardownWithSuspendedWriteSource() throws {
        // GAP 2: Verify teardown doesn't crash when write source is suspended.
        // Write source starts suspended (empty buffer) and stays that way if no writes.

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        task.testSetFd(pipe.writeFd)

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Write source starts suspended (empty buffer)
        XCTAssertTrue(task.testIsWriteSourceSuspended, "Write source should be suspended with empty buffer")

        // Teardown with suspended write source - should NOT crash
        task.testTeardownDispatchSourcesForTesting()

        // If we get here, test passed (no crash)
        XCTAssertFalse(task.testHasWriteSource, "Write source should be nil after teardown")
    }

    func testTeardownWithBothSourcesSuspended() throws {
        // GAP 2: Verify teardown doesn't crash when BOTH sources are suspended.
        // This is the worst case - both read and write sources need resume-before-cancel.

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

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Pause to suspend read source
        task.paused = true
        task.testWaitForIOQueue()

        // Verify both sources are suspended
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should be suspended")
        XCTAssertTrue(task.testIsWriteSourceSuspended, "Write source should be suspended (empty buffer)")

        // Teardown with both sources suspended - should NOT crash
        task.testTeardownDispatchSourcesForTesting()

        // If we get here, test passed (no crash)
        XCTAssertFalse(task.testHasReadSource, "Read source should be nil after teardown")
        XCTAssertFalse(task.testHasWriteSource, "Write source should be nil after teardown")
    }
}

final class PTYTaskUseDispatchSourceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(true)
    }

    override func tearDown() {
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(false)
        super.tearDown()
    }

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

        // Record initial state
        let initialHasReadSource = task.testHasReadSource
        let initialHasWriteSource = task.testHasWriteSource

        // Call update methods many times - should be idempotent
        for _ in 0..<20 {
            task.perform(readSelector)
            task.perform(writeSelector)
        }

        // State should be unchanged after idempotent calls
        XCTAssertEqual(task.testHasReadSource, initialHasReadSource,
                       "Read source state should remain stable")
        XCTAssertEqual(task.testHasWriteSource, initialHasWriteSource,
                       "Write source state should remain stable")

        XCTAssertNotNil(task, "Multiple update calls should be safe")
    }
}

// MARK: - Edge Case Tests

/// Tests for edge cases and error conditions
