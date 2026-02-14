//
//  PTYTaskDispatchSourceHandlerTests.swift
//  ModernTests
//
//  Event handler tests: handleReadEvent, handleWriteEvent, pipelines.
//

import XCTest
@testable import iTerm2SharedARC

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

        // Wait for the dispatch source to fire and drain the buffer.
        // Use iteration-based loop for determinism instead of wall-clock timeout.
        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained,
                      "Write buffer should be drained after write source fires")

        // Reset override
        task.testShouldWriteOverride = false

        // Cleanup
        task.testTeardownDispatchSourcesForTesting()
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

        // Wait for the dispatch source to fire and drain the buffer.
        // Use iteration-based loop for determinism instead of wall-clock timeout.
        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained,
                      "Buffer should be drained after write source fires (write completed)")

        // Reset override
        task.testShouldWriteOverride = false

        task.testTeardownDispatchSourcesForTesting()
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

        // Wait for the dispatch source to fire and drain the buffer after unpause.
        // Use iteration-based loop for determinism instead of wall-clock timeout.
        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained,
                      "Buffer should be drained after unpause triggers write")

        // Reset override
        task.testShouldWriteOverride = false

        task.testTeardownDispatchSourcesForTesting()
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
final class PTYTaskReadHandlerPipelineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(true)
    }

    override func tearDown() {
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(false)
        super.tearDown()
    }

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

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        // Track total data received
        var totalReceived = Data()
        let lock = NSLock()

        // Calculate expected total bytes
        let messages = ["First", "Second", "Third"]
        let expectedBytes = messages.reduce(0) { $0 + $1.data(using: .utf8)!.count }

        mockDelegate.onThreadedRead = { data in
            lock.lock()
            totalReceived.append(data)
            lock.unlock()
        }

        // Write multiple chunks of data
        for msg in messages {
            let data = msg.data(using: .utf8)!
            data.withUnsafeBytes { bufferPointer in
                let rawPointer = bufferPointer.baseAddress!
                _ = Darwin.write(pipe.writeFd, rawPointer, data.count)
            }
        }

        // Wait for all bytes to be received using iteration-based loop
        // The reads may be coalesced into fewer callbacks, but total data should match
        var allDataReceived = false
        for _ in 0..<200 {
            task.testWaitForIOQueue()
            lock.lock()
            let received = totalReceived.count >= expectedBytes
            lock.unlock()
            if received {
                allDataReceived = true
                break
            }
        }
        XCTAssertTrue(allDataReceived, "All data should be received")

        // Verify all data was received
        lock.lock()
        let receivedString = String(data: totalReceived, encoding: .utf8) ?? ""
        lock.unlock()

        for msg in messages {
            XCTAssertTrue(receivedString.contains(msg), "Should receive message: \(msg)")
        }

        task.testTeardownDispatchSourcesForTesting()
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
    }
}

// EnqueuingPTYTaskDelegate is defined in Mocks/EnqueuingPTYTaskDelegate.swift

// MARK: - 3.8 Write Path Round-Trip Tests

/// Tests that verify data written via writeTask: actually appears on the fd.
/// These tests exercise the complete write path, not just state changes.
final class PTYTaskWritePathRoundTripTests: XCTestCase {

    func testWriteTaskDataAppearsOnFd() throws {
        // GAP 6: Verify the complete write path via dispatch source.
        // This tests: writeTask: -> writeBuffer -> writeBufferDidChange -> updateWriteSourceState
        //          -> shouldWrite=YES -> write source resumes -> handleWriteEvent -> processWrite
        //          -> data written to fd
        //
        // If this test fails, the write path is broken (which matches the "typing doesn't work" bug).

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create pipe: task writes to writeFd, we read from readFd
        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        // Set the WRITE fd - this is what processWrite will write to
        task.testSetFd(pipe.writeFd)
        task.paused = false

        // Enable ioAllowed override (necessary since we don't have a real process)
        // but do NOT use testShouldWriteOverride - we want to test the real shouldWrite logic
        task.testIoAllowedOverride = NSNumber(value: true)

        // Setup dispatch sources
        task.testSetupDispatchSourcesForTesting()
        defer { task.testTeardownDispatchSourcesForTesting() }
        task.testWaitForIOQueue()

        // Verify initial state
        XCTAssertTrue(task.testIsWriteSourceSuspended, "Write source should start suspended (empty buffer)")

        // Use writeTask: - the public API that typing uses
        let testMessage = "Hello from keyboard!"
        let testData = testMessage.data(using: .utf8)!
        task.write(testData)

        // Wait for the write to complete
        // Use iteration-based loop, not wall-clock timeout
        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained, "Write buffer should be drained after write source fires")

        // NOW THE KEY ASSERTION: verify data actually appeared on the pipe
        var readBuffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = Darwin.read(pipe.readFd, &readBuffer, readBuffer.count)

        XCTAssertGreaterThan(bytesRead, 0, "Should have read data from pipe")
        if bytesRead > 0 {
            let receivedData = Data(bytes: readBuffer, count: bytesRead)
            let receivedString = String(data: receivedData, encoding: .utf8)
            XCTAssertEqual(receivedString, testMessage,
                           "Data read from pipe should match what was written via writeTask:")
        }
    }

    func testWriteTaskWithoutIoAllowedDoesNotWrite() throws {
        // Verify that shouldWrite returns false when ioAllowed is false,
        // and data stays in buffer (not written to fd)

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

        // Set ioAllowed to FALSE - write should NOT happen
        task.testIoAllowedOverride = NSNumber(value: false)

        task.testSetupDispatchSourcesForTesting()
        defer { task.testTeardownDispatchSourcesForTesting() }
        task.testWaitForIOQueue()

        // Use writeTask:
        let testData = "Should not appear".data(using: .utf8)!
        task.write(testData)
        task.testWaitForIOQueue()

        // Buffer should still have data (not drained, because shouldWrite=false)
        XCTAssertTrue(task.testWriteBufferHasData,
                      "Buffer should retain data when ioAllowed is false")

        // Pipe should be empty
        var readBuffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = Darwin.read(pipe.readFd, &readBuffer, readBuffer.count)
        XCTAssertEqual(bytesRead, -1, "Pipe should have no data (EAGAIN expected)")
        XCTAssertEqual(errno, EAGAIN, "Read should return EAGAIN on empty non-blocking pipe")
    }

    func testMultipleWriteTaskCallsAccumulate() throws {
        // Verify multiple writeTask: calls accumulate in buffer and all get written

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

        task.testIoAllowedOverride = NSNumber(value: true)

        task.testSetupDispatchSourcesForTesting()
        defer { task.testTeardownDispatchSourcesForTesting() }
        task.testWaitForIOQueue()

        // Write multiple chunks
        task.write("Hello ".data(using: .utf8)!)
        task.write("World".data(using: .utf8)!)
        task.write("!".data(using: .utf8)!)

        // Wait for all writes to complete
        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained, "All data should be written")

        // Read all data from pipe
        var allData = Data()
        var readBuffer = [UInt8](repeating: 0, count: 256)
        while true {
            let bytesRead = Darwin.read(pipe.readFd, &readBuffer, readBuffer.count)
            if bytesRead <= 0 { break }
            allData.append(contentsOf: readBuffer[0..<bytesRead])
        }

        let receivedString = String(data: allData, encoding: .utf8)
        XCTAssertEqual(receivedString, "Hello World!",
                       "All writeTask: data should appear on fd in order")
    }

    func testWriteTaskWithRealJobManager() throws {
        // Test write path using the REAL LegacyJobManager (no overrides).
        // testSetFd creates a LegacyJobManager with fd set.
        // LegacyJobManager.ioAllowed returns (fd >= 0) which should be true.
        // LegacyJobManager.isReadOnly returns NO.
        // If this test fails, the bug is in job manager behavior.

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        // testSetFd creates LegacyJobManager and sets fd
        task.testSetFd(pipe.writeFd)
        task.paused = false

        // NO OVERRIDES - use real job manager behavior
        // Verify preconditions
        let jobManager = task.value(forKey: "jobManager")
        XCTAssertNotNil(jobManager, "Job manager should exist after testSetFd")

        // Check shouldWrite transitions WITHOUT dispatch sources (avoids race with write source draining buffer)
        if let shouldWriteBefore = task.value(forKey: "shouldWrite") as? Bool {
            XCTAssertFalse(shouldWriteBefore, "shouldWrite should be false with empty buffer")
        }

        // Add data and verify shouldWrite becomes true (no dispatch sources yet, so buffer won't drain)
        let testMessage = "Real job manager test"
        task.write(testMessage.data(using: .utf8)!)

        if let shouldWriteAfter = task.value(forKey: "shouldWrite") as? Bool {
            XCTAssertTrue(shouldWriteAfter,
                          "shouldWrite should be true after adding data (ioAllowed=\(task.value(forKey: "effectiveIoAllowed") ?? "nil"))")
        }

        // Now set up dispatch sources — the write source will drain the buffer
        task.testSetupDispatchSourcesForTesting()
        defer { task.testTeardownDispatchSourcesForTesting() }

        // Wait for write to complete
        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained, "Buffer should be drained with real job manager")

        // Verify data arrived
        var readBuffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = Darwin.read(pipe.readFd, &readBuffer, readBuffer.count)
        XCTAssertGreaterThan(bytesRead, 0, "Data should have been written to pipe")
        if bytesRead > 0 {
            let received = String(data: Data(bytes: readBuffer, count: bytesRead), encoding: .utf8)
            XCTAssertEqual(received, testMessage, "Written data should match")
        }
    }
}
