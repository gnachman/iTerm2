//
//  PTYTaskDispatchSourcePredicateTests.swift
//  ModernTests
//
//  State predicate tests: shouldRead, shouldWrite, pause, ioAllowed.
//

import XCTest
@testable import iTerm2SharedARC

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

        // Before update, no sources exist
        XCTAssertFalse(task.testHasReadSource, "No read source before update")

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

        // State should remain unchanged - no source created
        XCTAssertFalse(task.testHasReadSource,
                       "updateReadSourceState should not create source")

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

        // Before update, no sources exist
        XCTAssertFalse(task.testHasWriteSource, "No write source before update")

        let selector = NSSelectorFromString("updateWriteSourceState")
        guard task.responds(to: selector) else {
            XCTFail("PTYTask should respond to updateWriteSourceState")
            return
        }

        // Call multiple times - should be no-op without sources
        for _ in 0..<3 {
            task.perform(selector)
        }

        // State should remain unchanged - no source created
        XCTAssertFalse(task.testHasWriteSource,
                       "updateWriteSourceState should not create source")

        XCTAssertNotNil(task, "Task should remain valid after updateWriteSourceState")
    }
}

// MARK: - 3.4 Event Handler Tests

/// Tests for event handler method existence (3.4)
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
    }

    func testShouldReadFalseWhenIoAllowedFalse() {
        // REQUIREMENT: shouldRead returns false when ioAllowed is false
        // Per spec: shouldRead = !paused && ioAllowed && backpressure < heavy

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

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
    }

    func testShouldReadTrueWhenIoAllowedTrueAndOtherConditionsMet() {
        // REQUIREMENT: shouldRead returns true when ioAllowed=true, paused=false, backpressure<heavy
        // Per spec: shouldRead = !paused && ioAllowed && backpressure < heavy

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

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
    }

    func testShouldReadFlipsWhenIoAllowedChanges() {
        // REQUIREMENT: shouldRead changes when ioAllowed flips from true to false
        // This tests the predicate responds to ioAllowed state changes

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

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
    }

    func testShouldWriteFalseWhenIoAllowedFalse() {
        // REQUIREMENT: shouldWrite returns false when ioAllowed is false
        // Per spec: shouldWrite = !paused && !isReadOnly && ioAllowed && bufferHasData

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

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
    }

    func testShouldWriteTrueWhenIoAllowedTrueAndOtherConditionsMet() {
        // REQUIREMENT: shouldWrite returns true when all conditions met
        // Per spec: shouldWrite = !paused && !isReadOnly && ioAllowed && bufferHasData
        // Note: We use testShouldWriteOverride to bypass isReadOnly (no real jobManager)

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

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
    }

    func testIoAllowedFalseOverridesPausedFalse() {
        // REQUIREMENT: ioAllowed=false should cause shouldRead=false even when paused=false
        // This verifies that ioAllowed is checked independently of pause state

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        task.paused = false  // Favorable

        // Force ioAllowed = false
        task.testIoAllowedOverride = NSNumber(value: false)

        // shouldRead should still be false (ioAllowed blocks it)
        if let result = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(result, "ioAllowed=false should make shouldRead=false regardless of paused state")
        }
    }

    func testIoAllowedTrueDoesNotOverridePausedTrue() {
        // REQUIREMENT: ioAllowed=true should NOT make shouldRead=true when paused=true
        // This verifies that pause state is still respected

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        task.paused = true  // Unfavorable

        // Force ioAllowed = true
        task.testIoAllowedOverride = NSNumber(value: true)

        // shouldRead should still be false (paused blocks it)
        if let result = task.value(forKey: "shouldRead") as? Bool {
            XCTAssertFalse(result, "paused=true should make shouldRead=false regardless of ioAllowed")
        }
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
    }
}

// MARK: - 3.6 Backpressure Integration Tests

/// Tests for backpressure integration with PTYTask (3.6)
