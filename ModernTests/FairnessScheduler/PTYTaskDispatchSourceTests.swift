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

    func testShouldWriteOverrideProperty() {
        // REQUIREMENT: testShouldWriteOverride should bypass jobManager constraints
        // This tests that the override property is properly accessible from Swift

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        // Initially override should be false
        XCTAssertFalse(task.testShouldWriteOverride, "Override should initially be false")

        // Set override to true
        task.testShouldWriteOverride = true
        XCTAssertTrue(task.testShouldWriteOverride, "Override should be settable to true")

        // Reset override
        task.testShouldWriteOverride = false
        XCTAssertFalse(task.testShouldWriteOverride, "Override should be resettable to false")

        // Now test that override affects shouldWrite with buffer data
        task.testShouldWriteOverride = true
        task.paused = false

        // Add data to buffer
        let testData = "Test data".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)

        // Verify buffer has data
        XCTAssertTrue(task.testWriteBufferHasData, "Buffer should have data after append")

        // With override and data, shouldWrite should be true
        if let shouldWrite = task.value(forKey: "shouldWrite") as? Bool {
            XCTAssertTrue(shouldWrite, "shouldWrite should be true with override and data in buffer")
        }

        // Clean up
        task.testShouldWriteOverride = false
        #endif
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
        // when conditions are favorable (not paused, ioAllowed, buffer has data)
        // Uses testShouldWriteOverride to bypass jobManager.isReadOnly constraint
        //
        // NOTE: When the write source resumes on a valid fd, it may fire immediately
        // and drain the buffer. This test verifies the shouldWrite predicate works
        // correctly, and that the write mechanism is functional (buffer gets drained).

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create a pipe for valid fd - use WRITE end for write source testing
        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        // Set the WRITE fd (pipe.writeFd) for write source to work correctly
        // The fd must be >= 0 for ioAllowed to return true
        task.testSetFd(pipe.writeFd)
        task.paused = false

        #if ITERM_DEBUG
        // Enable write override to bypass jobManager.isReadOnly constraint
        task.testShouldWriteOverride = true

        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Initially write source is suspended (empty buffer, shouldWrite=false)
        XCTAssertTrue(task.testIsWriteSourceSuspended, "Write source should start suspended (empty buffer)")
        XCTAssertFalse(task.testWriteBufferHasData, "Write buffer should be empty initially")

        // Add data to write buffer
        let testData = "Hello".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)

        // Verify buffer has data BEFORE triggering writeBufferDidChange
        XCTAssertTrue(task.testWriteBufferHasData, "Write buffer should have data after append")

        // Verify shouldWrite is true BEFORE the dispatch source has a chance to drain
        guard let shouldWriteBefore = task.value(forKey: "shouldWrite") as? Bool else {
            XCTFail("Could not read shouldWrite")
            return
        }
        XCTAssertTrue(shouldWriteBefore,
                      "shouldWrite should be true with override and data in buffer (before notification)")

        // Now call writeBufferDidChange to trigger the write source resume
        task.perform(NSSelectorFromString("writeBufferDidChange"))
        task.testWaitForIOQueue()
        // Additional small delay for dispatch source to fire (source firing is async from kernel)
        Thread.sleep(forTimeInterval: 0.02)

        // After the wait, the write source likely fired and drained the buffer.
        // This is CORRECT behavior - the mechanism worked! The buffer was written.
        // We verify the mechanism worked by checking that the buffer is now empty
        // (meaning the write completed successfully).
        XCTAssertFalse(task.testWriteBufferHasData,
                       "Write buffer should be drained after write source fires")

        // Reset override
        task.testShouldWriteOverride = false

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("writeBufferDidChange")),
                      "PTYTask should have writeBufferDidChange method")
        #endif
    }

    func testWriteSourceResumesWhenBufferFills() {
        // REQUIREMENT: Write source should resume when buffer transitions from empty to non-empty
        // Uses testShouldWriteOverride to bypass jobManager.isReadOnly constraint
        //
        // NOTE: When write source resumes on a valid writable fd, it fires and drains buffer.
        // This test verifies the shouldWrite predicate and confirms writes complete.

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
        task.paused = false

        #if ITERM_DEBUG
        // Enable write override to bypass jobManager.isReadOnly constraint
        task.testShouldWriteOverride = true

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Verify initial state: empty buffer, write source suspended
        XCTAssertFalse(task.testWriteBufferHasData, "Buffer should be empty initially")
        XCTAssertTrue(task.testIsWriteSourceSuspended, "Write source should be suspended with empty buffer")

        // Fill buffer
        let testData = "Test data for write source".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)
        XCTAssertTrue(task.testWriteBufferHasData, "Buffer should have data after append")

        // Check shouldWrite predicate BEFORE triggering notification
        guard let shouldWrite = task.value(forKey: "shouldWrite") as? Bool else {
            XCTFail("Could not read shouldWrite")
            return
        }
        XCTAssertTrue(shouldWrite, "shouldWrite should be true with override and data in buffer")

        // Trigger write buffer change notification - this will resume write source
        task.perform(NSSelectorFromString("writeBufferDidChange"))
        task.testWaitForIOQueue()
        // Additional small delay for dispatch source to fire
        Thread.sleep(forTimeInterval: 0.02)

        // After the notification and wait, the write source resumed, fired, and drained buffer.
        // This is correct behavior - verify the write completed by checking buffer is empty.
        XCTAssertFalse(task.testWriteBufferHasData,
                       "Buffer should be drained after write source fires (write completed)")

        // Reset override
        task.testShouldWriteOverride = false

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("updateWriteSourceState")))
        #endif
    }

    func testWriteSourceSuspendResumeCycleViaPause() {
        // REQUIREMENT: Write source should suspend when paused and resume when unpaused
        // This tests the pause -> unpause cycle for write source using a paused state
        // to prevent the write from completing, allowing us to observe the resume.

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
        // Enable write override to bypass jobManager.isReadOnly constraint
        task.testShouldWriteOverride = true

        // Start PAUSED - this prevents writes from completing
        task.paused = true

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Step 1: Start paused with empty buffer - write source should be SUSPENDED
        XCTAssertFalse(task.testWriteBufferHasData, "Buffer should be empty initially")
        XCTAssertTrue(task.testIsWriteSourceSuspended, "Write source should be SUSPENDED when paused")

        // Step 2: Add data to buffer while paused
        let testData = "Data for resume test".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)
        XCTAssertTrue(task.testWriteBufferHasData, "Buffer should have data after append")

        // Trigger update - but since we're paused, write source should stay suspended
        task.perform(NSSelectorFromString("writeBufferDidChange"))
        task.testWaitForIOQueue()

        // shouldWrite should be false (paused)
        if let shouldWrite = task.value(forKey: "shouldWrite") as? Bool {
            XCTAssertFalse(shouldWrite, "shouldWrite should be false when paused")
        }
        XCTAssertTrue(task.testIsWriteSourceSuspended, "Write source should stay SUSPENDED when paused")
        XCTAssertTrue(task.testWriteBufferHasData, "Buffer should still have data (no write occurred)")

        // Step 3: Unpause - write source should RESUME and then drain buffer
        task.paused = false
        task.perform(NSSelectorFromString("updateWriteSourceState"))
        task.testWaitForIOQueue()
        // Additional small delay for dispatch source to fire
        Thread.sleep(forTimeInterval: 0.02)

        // After unpause, shouldWrite was true briefly (data + not paused + override),
        // so write source resumed, fired, and drained the buffer.
        // Verify the write completed by checking buffer is empty.
        XCTAssertFalse(task.testWriteBufferHasData,
                       "Buffer should be drained after unpause triggers write")

        // Reset override
        task.testShouldWriteOverride = false

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("updateWriteSourceState")))
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
        task.testWaitForIOQueue()

        // With paused=true, read source should be suspended
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should be suspended when paused=true")
        XCTAssertTrue(task.paused, "Task should be paused")

        // Set paused = false
        task.paused = false
        task.testWaitForIOQueue()

        // After unpause, source should resume (fd is valid so ioAllowed=true, no tokenExecutor so no backpressure)
        XCTAssertFalse(task.paused, "Task should be unpaused")
        XCTAssertFalse(task.testIsReadSourceSuspended, "Read source should RESUME after unpause with valid fd")

        // Now pause again - this should suspend the read source
        task.paused = true
        task.testWaitForIOQueue()

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

    func testReadSourceResumesAfterUnpause() {
        // REQUIREMENT: Read source should resume when unpause makes shouldRead true
        // This tests the full suspend -> resume cycle

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
        // Start unpaused, setup sources
        task.paused = false
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // With valid fd and no pause, read source should be resumed
        // (ioAllowed=true because fd>=0, no tokenExecutor means no backpressure check)
        XCTAssertFalse(task.testIsReadSourceSuspended, "Read source should be resumed initially (favorable conditions)")

        // Pause - should suspend
        task.paused = true
        task.testWaitForIOQueue()
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should suspend on pause")

        // Unpause - should resume (this is the key resume test)
        task.paused = false
        task.testWaitForIOQueue()
        XCTAssertFalse(task.testIsReadSourceSuspended, "Read source should RESUME after unpause")

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("updateReadSourceState")))
        #endif
    }
}

// MARK: - 3.5b ioAllowed Predicate Tests

/// Tests for ioAllowed affecting shouldRead/shouldWrite predicates
/// These tests use testIoAllowedOverride to control the ioAllowed input
/// without needing a real jobManager or launched process.
final class PTYTaskIoAllowedPredicateTests: XCTestCase {

    func testIoAllowedOverridePropertyExists() {
        // REQUIREMENT: PTYTask must have testIoAllowedOverride property for testing

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        // Should be nil by default
        XCTAssertNil(task.testIoAllowedOverride, "testIoAllowedOverride should be nil by default")

        // Should be settable to @YES
        task.testIoAllowedOverride = NSNumber(value: true)
        XCTAssertEqual(task.testIoAllowedOverride?.boolValue, true)

        // Should be settable to @NO
        task.testIoAllowedOverride = NSNumber(value: false)
        XCTAssertEqual(task.testIoAllowedOverride?.boolValue, false)

        // Should be resettable to nil
        task.testIoAllowedOverride = nil
        XCTAssertNil(task.testIoAllowedOverride)
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("testIoAllowedOverride")))
        #endif
    }

    func testShouldReadFalseWhenIoAllowedFalse() {
        // REQUIREMENT: shouldRead returns false when ioAllowed is false
        // Per spec: shouldRead = !paused && ioAllowed && backpressure < heavy

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        // Set up favorable conditions except ioAllowed
        task.paused = false  // not paused
        // No tokenExecutor means no backpressure check

        // Force ioAllowed = false
        task.testIoAllowedOverride = NSNumber(value: false)

        // shouldRead should be false because ioAllowed is false
        if let result = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(result, "shouldRead should be false when ioAllowed=false")
        } else {
            XCTFail("Could not read shouldRead value")
        }
        #else
        task.paused = true
        if let result = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(result)
        }
        #endif
    }

    func testShouldReadTrueWhenIoAllowedTrueAndOtherConditionsMet() {
        // REQUIREMENT: shouldRead returns true when ioAllowed=true, paused=false, backpressure<heavy
        // Per spec: shouldRead = !paused && ioAllowed && backpressure < heavy

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        // Set up all favorable conditions
        task.paused = false  // not paused
        // No tokenExecutor means no backpressure check (treated as none)

        // Force ioAllowed = true
        task.testIoAllowedOverride = NSNumber(value: true)

        // shouldRead should be true because all conditions are met
        if let result = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertTrue(result, "shouldRead should be true when ioAllowed=true and other conditions met")
        } else {
            XCTFail("Could not read shouldRead value")
        }
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("shouldRead")))
        #endif
    }

    func testShouldReadFlipsWhenIoAllowedChanges() {
        // REQUIREMENT: shouldRead changes when ioAllowed flips from true to false
        // This tests the predicate responds to ioAllowed state changes

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        task.paused = false  // not paused, no backpressure (no executor)

        // Start with ioAllowed = true
        task.testIoAllowedOverride = NSNumber(value: true)
        if let resultTrue = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertTrue(resultTrue, "shouldRead should be true when ioAllowed=true")
        }

        // Flip to ioAllowed = false
        task.testIoAllowedOverride = NSNumber(value: false)
        if let resultFalse = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(resultFalse, "shouldRead should flip to false when ioAllowed flips to false")
        }

        // Flip back to ioAllowed = true
        task.testIoAllowedOverride = NSNumber(value: true)
        if let resultTrueAgain = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertTrue(resultTrueAgain, "shouldRead should flip back to true when ioAllowed flips to true")
        }
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("shouldRead")))
        #endif
    }

    func testShouldWriteFalseWhenIoAllowedFalse() {
        // REQUIREMENT: shouldWrite returns false when ioAllowed is false
        // Per spec: shouldWrite = !paused && !isReadOnly && ioAllowed && bufferHasData

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        // Set up favorable conditions except ioAllowed
        task.paused = false
        task.testShouldWriteOverride = false  // Don't bypass isReadOnly check

        // Add data to buffer
        let testData = "Test data".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)
        XCTAssertTrue(task.testWriteBufferHasData, "Buffer should have data")

        // Force ioAllowed = false
        task.testIoAllowedOverride = NSNumber(value: false)

        // shouldWrite should be false because ioAllowed is false
        if let result = task.value(forKey: "shouldWrite") as? Bool {
            XCTAssertFalse(result, "shouldWrite should be false when ioAllowed=false")
        } else {
            XCTFail("Could not read shouldWrite value")
        }
        #else
        task.paused = true
        if let result = task.value(forKey: "shouldWrite") as? Bool {
            XCTAssertFalse(result)
        }
        #endif
    }

    func testShouldWriteTrueWhenIoAllowedTrueAndOtherConditionsMet() {
        // REQUIREMENT: shouldWrite returns true when all conditions met
        // Per spec: shouldWrite = !paused && !isReadOnly && ioAllowed && bufferHasData
        // Note: We use testShouldWriteOverride to bypass isReadOnly (no real jobManager)

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        task.paused = false
        task.testShouldWriteOverride = true  // Bypass isReadOnly check

        // Add data to buffer
        let testData = "Test data".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)
        XCTAssertTrue(task.testWriteBufferHasData, "Buffer should have data")

        // Force ioAllowed = true (though testShouldWriteOverride bypasses this too)
        task.testIoAllowedOverride = NSNumber(value: true)

        // shouldWrite should be true
        if let result = task.value(forKey: "shouldWrite") as? Bool {
            XCTAssertTrue(result, "shouldWrite should be true when all conditions met")
        } else {
            XCTFail("Could not read shouldWrite value")
        }

        task.testShouldWriteOverride = false
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("shouldWrite")))
        #endif
    }

    func testIoAllowedFalseOverridesPausedFalse() {
        // REQUIREMENT: ioAllowed=false should cause shouldRead=false even when paused=false
        // This verifies that ioAllowed is checked independently of pause state

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        task.paused = false  // Favorable

        // Force ioAllowed = false
        task.testIoAllowedOverride = NSNumber(value: false)

        // shouldRead should still be false (ioAllowed blocks it)
        if let result = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(result, "ioAllowed=false should make shouldRead=false regardless of paused state")
        }
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("shouldRead")))
        #endif
    }

    func testIoAllowedTrueDoesNotOverridePausedTrue() {
        // REQUIREMENT: ioAllowed=true should NOT make shouldRead=true when paused=true
        // This verifies that pause state is still respected

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        #if ITERM_DEBUG
        task.paused = true  // Unfavorable

        // Force ioAllowed = true
        task.testIoAllowedOverride = NSNumber(value: true)

        // shouldRead should still be false (paused blocks it)
        if let result = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(result, "paused=true should make shouldRead=false regardless of ioAllowed")
        }
        #else
        task.paused = true
        if let result = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(result)
        }
        #endif
    }

    // MARK: - Write Source State Transition Tests

    func testWriteSourceSuspendsWhenIoAllowedBecomesFalse() {
        // REQUIREMENT: Write source should suspend when ioAllowed changes from true to false
        // Mirrors testReadSourceSuspendsWhenIoAllowedBecomesFalse for write side
        //
        // Note: We do NOT use testShouldWriteOverride here because that bypasses the
        // ioAllowed check entirely. Without a jobManager, isReadOnly returns false
        // (nil messaging), so the only blocking condition is ioAllowed.

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
        task.paused = false

        #if ITERM_DEBUG
        // Start with ioAllowed = true and data in buffer (write source needs data to resume)
        // Note: NOT using testShouldWriteOverride so ioAllowed check is active
        task.testIoAllowedOverride = NSNumber(value: true)
        let testData = "Test data for write".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Write source should be resumed (ioAllowed=true + data in buffer + not paused)
        XCTAssertFalse(task.testIsWriteSourceSuspended,
                       "Write source should be resumed with ioAllowed=true and data in buffer")

        // Flip ioAllowed to false
        task.testIoAllowedOverride = NSNumber(value: false)
        task.perform(NSSelectorFromString("updateWriteSourceState"))
        task.testWaitForIOQueue()

        // Write source should now be suspended
        XCTAssertTrue(task.testIsWriteSourceSuspended,
                      "Write source should SUSPEND when ioAllowed becomes false")

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("updateWriteSourceState")))
        #endif
    }

    func testWriteSourceResumesWhenIoAllowedBecomesTrue() {
        // REQUIREMENT: Write source should resume when ioAllowed changes from false to true
        // Mirrors testReadSourceResumesWhenIoAllowedBecomesTrue for write side
        //
        // Note: We do NOT use testShouldWriteOverride here because that bypasses the
        // ioAllowed check entirely. Without a jobManager, isReadOnly returns false
        // (nil messaging), so the only blocking condition is ioAllowed.

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
        task.paused = false

        #if ITERM_DEBUG
        // Start with ioAllowed = false and data in buffer
        // Note: NOT using testShouldWriteOverride so ioAllowed check is active
        task.testIoAllowedOverride = NSNumber(value: false)
        let testData = "Test data for write".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Write source should be suspended (ioAllowed=false blocks shouldWrite)
        XCTAssertTrue(task.testIsWriteSourceSuspended,
                      "Write source should be suspended with ioAllowed=false")

        // Flip ioAllowed to true
        task.testIoAllowedOverride = NSNumber(value: true)
        task.perform(NSSelectorFromString("updateWriteSourceState"))
        task.testWaitForIOQueue()

        // Write source should now be resumed (ioAllowed=true + data in buffer)
        XCTAssertFalse(task.testIsWriteSourceSuspended,
                       "Write source should RESUME when ioAllowed becomes true")

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("updateWriteSourceState")))
        #endif
    }

    func testWriteSourceStaysSuspendedWithoutData() {
        // REQUIREMENT: Write source should stay suspended even with ioAllowed=true if no data
        // This is different from read source - write needs data in buffer to resume

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
        task.paused = false

        #if ITERM_DEBUG
        // ioAllowed = true but NO data in buffer
        task.testIoAllowedOverride = NSNumber(value: true)
        task.testShouldWriteOverride = true  // Bypass isReadOnly check
        // Note: NOT adding data to buffer

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Write source should be suspended (no data to write)
        XCTAssertTrue(task.testIsWriteSourceSuspended,
                      "Write source should stay suspended without data in buffer")

        // Now add data - source should resume
        let testData = "Test data".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)
        task.perform(NSSelectorFromString("updateWriteSourceState"))
        task.testWaitForIOQueue()

        // Write source should now be resumed
        XCTAssertFalse(task.testIsWriteSourceSuspended,
                       "Write source should resume after data is added to buffer")

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("updateWriteSourceState")))
        #endif
    }

    func testWriteSourceSuspendsWhenPausedBecomesTrue() {
        // REQUIREMENT: Write source should suspend when paused changes to true
        // Mirrors pause behavior for read source

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
        // Start unpaused with favorable conditions
        task.paused = false
        task.testIoAllowedOverride = NSNumber(value: true)
        task.testShouldWriteOverride = true
        let testData = "Test data".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Write source should be resumed
        XCTAssertFalse(task.testIsWriteSourceSuspended,
                       "Write source should be resumed when unpaused with data")

        // Pause the task
        task.paused = true
        task.testWaitForIOQueue()

        // Write source should now be suspended
        XCTAssertTrue(task.testIsWriteSourceSuspended,
                      "Write source should SUSPEND when paused becomes true")

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("updateWriteSourceState")))
        #endif
    }

    // MARK: - Read Source State Transition Tests

    func testReadSourceSuspendsWhenIoAllowedBecomesFalse() {
        // REQUIREMENT: Read source should suspend when ioAllowed changes from true to false

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

        #if ITERM_DEBUG
        // Start with ioAllowed = true
        task.testIoAllowedOverride = NSNumber(value: true)

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Read source should be resumed (all conditions favorable)
        XCTAssertFalse(task.testIsReadSourceSuspended, "Read source should be resumed with ioAllowed=true")

        // Flip ioAllowed to false
        task.testIoAllowedOverride = NSNumber(value: false)
        task.perform(NSSelectorFromString("updateReadSourceState"))
        task.testWaitForIOQueue()

        // Read source should now be suspended
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should SUSPEND when ioAllowed becomes false")

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("updateReadSourceState")))
        #endif
    }

    func testReadSourceResumesWhenIoAllowedBecomesTrue() {
        // REQUIREMENT: Read source should resume when ioAllowed changes from false to true

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

        #if ITERM_DEBUG
        // Start with ioAllowed = false
        task.testIoAllowedOverride = NSNumber(value: false)

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Read source should be suspended (ioAllowed=false)
        XCTAssertTrue(task.testIsReadSourceSuspended, "Read source should be suspended with ioAllowed=false")

        // Flip ioAllowed to true
        task.testIoAllowedOverride = NSNumber(value: true)
        task.perform(NSSelectorFromString("updateReadSourceState"))
        task.testWaitForIOQueue()

        // Read source should now be resumed
        XCTAssertFalse(task.testIsReadSourceSuspended, "Read source should RESUME when ioAllowed becomes true")

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("updateReadSourceState")))
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
        task.testWaitForIOQueue()

        // Read source state depends on ioAllowed (requires jobManager setup)
        // For this test, we verify the mechanism is in place

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
        // (if it was ever resumed - it may have stayed suspended due to ioAllowed)
        XCTAssertTrue(task.testIsReadSourceSuspended,
                      "Read source should be suspended with blocked backpressure")

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
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)
        task.tokenExecutor = executor

        #if ITERM_DEBUG
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

        // Drain tokens by executing a turn with large budget
        let drainExpectation = XCTestExpectation(description: "Tokens drained")
        executor.executeTurn(tokenBudget: 10000) { result in
            drainExpectation.fulfill()
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
        #else
        XCTAssertNotNil(executor.backpressureReleaseHandler)
        #endif
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
        task.tokenExecutor = executor

        #if ITERM_DEBUG
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

        // Give time for data to (not) be delivered
        Thread.sleep(forTimeInterval: 0.1)
        task.testWaitForIOQueue()

        // Data should NOT have been read (source is suspended)
        XCTAssertEqual(mockDelegate.readCallCount, readCountBeforeWrite,
                       "Data should NOT be delivered when read source is suspended due to blocked backpressure")

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
        #else
        // Non-debug build: basic verification
        XCTAssertNotNil(task.tokenExecutor)
        #endif
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

// MockPTYTaskDelegate is defined in Mocks/MockPTYTaskDelegate.swift

// MARK: - Read Handler Pipeline Tests

/// Tests for the read handler pipeline (read → threadedReadTask)
/// These tests verify that data flows correctly from dispatch source to delegate
final class PTYTaskReadHandlerPipelineTests: XCTestCase {

    func testReadSourceTriggersThreadedReadTask() {
        // REQUIREMENT: When data is available on fd, handleReadEvent should read it
        // and call delegate's threadedReadTask with the data

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        // Create and set mock delegate
        let mockDelegate = MockPTYTaskDelegate()
        task.delegate = mockDelegate

        // Set the READ fd (data will be read from here)
        task.testSetFd(pipe.readFd)
        task.paused = false

        #if ITERM_DEBUG
        // Set up expectation BEFORE any data flow
        let readExpectation = XCTestExpectation(description: "threadedReadTask called")
        mockDelegate.onThreadedRead = { _ in
            readExpectation.fulfill()
        }

        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Verify read source is active (not suspended)
        XCTAssertFalse(task.testIsReadSourceSuspended, "Read source should be resumed")

        // Write data to the pipe (write end) - this should trigger the read source
        let testMessage = "Hello from read handler test!"
        let testData = testMessage.data(using: .utf8)!
        let bytesWritten = testData.withUnsafeBytes { bufferPointer -> Int in
            let rawPointer = bufferPointer.baseAddress!
            return Darwin.write(pipe.writeFd, rawPointer, testData.count)
        }
        XCTAssertEqual(bytesWritten, testData.count, "Should write all bytes to pipe")

        // Wait for dispatch source to fire and process the read
        wait(for: [readExpectation], timeout: 2.0)

        // Verify the delegate received the data
        XCTAssertGreaterThan(mockDelegate.getReadCount(), 0, "threadedReadTask should be called")

        if let receivedData = mockDelegate.getLastReadData() {
            let receivedString = String(data: receivedData, encoding: .utf8)
            XCTAssertEqual(receivedString, testMessage, "Delegate should receive the written data")
        } else {
            XCTFail("Delegate should have received data")
        }

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
        #else
        // Non-debug build: basic verification
        XCTAssertTrue(task.responds(to: NSSelectorFromString("handleReadEvent")))
        #endif
    }

    func testReadHandlerDoesNotBlock() {
        // REQUIREMENT: The read handler should complete quickly (not block on main thread operations)
        // This test verifies the handler returns promptly by measuring elapsed time

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        let mockDelegate = MockPTYTaskDelegate()
        task.delegate = mockDelegate
        task.testSetFd(pipe.readFd)
        task.paused = false

        #if ITERM_DEBUG
        // Set up callback BEFORE starting sources to avoid race condition
        let readExpectation = XCTestExpectation(description: "Quick read")
        mockDelegate.onThreadedRead = { _ in
            readExpectation.fulfill()
        }

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Measure time from write to callback
        let startTime = CFAbsoluteTimeGetCurrent()

        // Write data to trigger read
        let testData = "Quick read test".data(using: .utf8)!
        testData.withUnsafeBytes { bufferPointer in
            let rawPointer = bufferPointer.baseAddress!
            _ = Darwin.write(pipe.writeFd, rawPointer, testData.count)
        }

        wait(for: [readExpectation], timeout: 2.0)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Handler should complete quickly (much less than 1 second)
        // If it were blocking on a semaphore or main thread sync, it would timeout
        XCTAssertLessThan(elapsed, 0.5, "Read handler should complete quickly (not block)")

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("handleReadEvent")))
        #endif
    }

    func testMultipleReadsAccumulate() {
        // REQUIREMENT: Multiple reads should all be delivered to the delegate

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        let mockDelegate = MockPTYTaskDelegate()
        task.delegate = mockDelegate
        task.testSetFd(pipe.readFd)
        task.paused = false

        #if ITERM_DEBUG
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Track total data received
        var totalReceived = Data()
        let lock = NSLock()
        let allDataExpectation = XCTestExpectation(description: "All data received")
        allDataExpectation.expectedFulfillmentCount = 3

        mockDelegate.onThreadedRead = { data in
            lock.lock()
            totalReceived.append(data)
            lock.unlock()
            allDataExpectation.fulfill()
        }

        // Write multiple chunks of data
        let messages = ["First", "Second", "Third"]
        for msg in messages {
            let data = msg.data(using: .utf8)!
            data.withUnsafeBytes { bufferPointer in
                let rawPointer = bufferPointer.baseAddress!
                _ = Darwin.write(pipe.writeFd, rawPointer, data.count)
            }
            // Small delay between writes for dispatch source to fire
            Thread.sleep(forTimeInterval: 0.02)
        }

        wait(for: [allDataExpectation], timeout: 2.0)

        // Verify all data was received
        lock.lock()
        let receivedString = String(data: totalReceived, encoding: .utf8) ?? ""
        lock.unlock()

        for msg in messages {
            XCTAssertTrue(receivedString.contains(msg), "Should receive message: \(msg)")
        }

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("handleReadEvent")))
        #endif
    }

    func testReadPipelineEnqueuesToTokenExecutor() {
        // REQUIREMENT: Full pipeline test - data on fd → read → parse → TokenExecutor enqueue
        // This tests that the dispatch_source handler correctly reads data and the data
        // flows through to the token processing pipeline.
        //
        // The test verifies:
        // 1. Dispatch source reads data from fd
        // 2. Handler calls delegate.threadedReadTask (non-blocking)
        // 3. Delegate can enqueue tokens to TokenExecutor (mimicking PTYSession)
        // 4. TokenExecutor receives the tokens (verified via backpressure change)

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        // Create a real VT100Terminal and TokenExecutor
        let terminal = VT100Terminal()
        let executor = TokenExecutor(terminal, slownessDetector: SlownessDetector(), queue: DispatchQueue.main)

        // Create a delegate that enqueues tokens when data is received (mimicking PTYSession)
        let enqueuingDelegate = EnqueuingPTYTaskDelegate(executor: executor)
        task.delegate = enqueuingDelegate
        task.tokenExecutor = executor

        task.testSetFd(pipe.readFd)
        task.paused = false

        #if ITERM_DEBUG
        // Track initial backpressure level
        let initialLevel = executor.backpressureLevel

        // Set up expectation for delegate call and token enqueue
        let enqueueExpectation = XCTestExpectation(description: "Tokens enqueued")
        enqueuingDelegate.onEnqueued = {
            enqueueExpectation.fulfill()
        }

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        XCTAssertFalse(task.testIsReadSourceSuspended, "Read source should be active")

        // Write data to the pipe - this should trigger the read source
        let testData = "Test data for token pipeline".data(using: .utf8)!
        testData.withUnsafeBytes { bufferPointer in
            let rawPointer = bufferPointer.baseAddress!
            _ = Darwin.write(pipe.writeFd, rawPointer, testData.count)
        }

        // Wait for tokens to be enqueued
        wait(for: [enqueueExpectation], timeout: 2.0)

        // Verify the full pipeline worked:
        // 1. Delegate was called (handler didn't block - we got here within timeout)
        XCTAssertGreaterThan(enqueuingDelegate.enqueueCount, 0,
                             "Delegate should have enqueued tokens")

        // 2. Tokens were actually added to executor
        // The delegate adds enough tokens to change backpressure level
        XCTAssertNotEqual(executor.backpressureLevel, initialLevel,
                          "TokenExecutor backpressure should change after enqueue")

        task.testTeardownDispatchSourcesForTesting()
        #else
        XCTAssertTrue(task.responds(to: NSSelectorFromString("handleReadEvent")))
        #endif
    }
}

// EnqueuingPTYTaskDelegate is defined in Mocks/EnqueuingPTYTaskDelegate.swift
