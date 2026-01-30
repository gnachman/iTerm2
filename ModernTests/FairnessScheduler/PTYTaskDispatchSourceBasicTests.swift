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
        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks for dispatch source introspection")

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
        #endif
    }

    func testTeardownCleansUpSources() throws {
        // REQUIREMENT: teardownDispatchSources removes sources and cleans up state
        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks for dispatch source introspection")

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

    // MARK: - Gap 2: Teardown with Suspended Sources

    func testTeardownWithSuspendedReadSource() throws {
        // GAP 2: Verify teardown doesn't crash when read source is suspended.
        // dispatch_source_cancel on a suspended source crashes unless resumed first.
        // The implementation must resume before canceling.

        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks")

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

        #if ITERM_DEBUG
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
        #endif
    }

    func testTeardownWithSuspendedWriteSource() throws {
        // GAP 2: Verify teardown doesn't crash when write source is suspended.
        // Write source starts suspended (empty buffer) and stays that way if no writes.

        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks")

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

        #if ITERM_DEBUG
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Write source starts suspended (empty buffer)
        XCTAssertTrue(task.testIsWriteSourceSuspended, "Write source should be suspended with empty buffer")

        // Teardown with suspended write source - should NOT crash
        task.testTeardownDispatchSourcesForTesting()

        // If we get here, test passed (no crash)
        XCTAssertFalse(task.testHasWriteSource, "Write source should be nil after teardown")
        #endif
    }

    func testTeardownWithBothSourcesSuspended() throws {
        // GAP 2: Verify teardown doesn't crash when BOTH sources are suspended.
        // This is the worst case - both read and write sources need resume-before-cancel.

        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks")

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

        #if ITERM_DEBUG
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
        #endif
    }
}

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
