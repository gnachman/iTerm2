//
//  DispatchSourceReadWriteTests.swift
//  ModernTests
//
//  Read handler pipeline and write path round-trip tests for dispatch sources.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Event Handler Tests

/// Tests for handler method existence and wiring
final class DispatchSourceEventHandlerTests: XCTestCase {

    func testHandleReadEventWiring() {
        // PTYTaskIOHandler's handleReadEvent is private, invoked by dispatch source.
        // Verify the handler is correctly wired by checking that dispatch sources are created.

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

        XCTAssertTrue(task.testHasReadSource(),
                      "Read source should exist (handleReadEvent is internal to handler)")

        task.testTeardownDispatchSourcesForTesting()
    }

    func testHandleWriteEventWiring() {
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

        XCTAssertTrue(task.testHasWriteSource(),
                      "Write source should exist (handleWriteEvent is internal to handler)")

        task.testTeardownDispatchSourcesForTesting()
    }

    func testProcessReadMethodExists() {
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        XCTAssertTrue(task.responds(to: #selector(task.processRead)),
                      "PTYTask should have processRead method")
    }

    func testProcessWriteMethodExists() {
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        XCTAssertTrue(task.responds(to: #selector(task.processWrite)),
                      "PTYTask should have processWrite method")
    }
}

// MARK: - Read Handler Pipeline Tests

/// Tests for the read handler pipeline (data on fd -> read -> delegate)
final class DispatchSourceReadPipelineTests: XCTestCase {

    func testReadSourceTriggersThreadedReadTask() {
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

        let readExpectation = XCTestExpectation(description: "threadedReadTask called")
        mockDelegate.onThreadedRead = { _ in
            readExpectation.fulfill()
        }

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        XCTAssertFalse(task.testIsReadSourceSuspended(), "Read source should be resumed")

        let testMessage = "Hello from read handler test!"
        let testData = testMessage.data(using: .utf8)!
        let bytesWritten = testData.withUnsafeBytes { bufferPointer -> Int in
            let rawPointer = bufferPointer.baseAddress!
            return Darwin.write(pipe.writeFd, rawPointer, testData.count)
        }
        XCTAssertEqual(bytesWritten, testData.count, "Should write all bytes to pipe")

        wait(for: [readExpectation], timeout: 2.0)

        XCTAssertGreaterThan(mockDelegate.getReadCount(), 0, "threadedReadTask should be called")

        if let receivedData = mockDelegate.getLastReadData() {
            let receivedString = String(data: receivedData, encoding: .utf8)
            XCTAssertEqual(receivedString, testMessage, "Delegate should receive the written data")
        } else {
            XCTFail("Delegate should have received data")
        }

        task.testTeardownDispatchSourcesForTesting()
    }

    func testReadHandlerDoesNotBlock() {
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

        let readExpectation = XCTestExpectation(description: "Quick read")
        mockDelegate.onThreadedRead = { _ in
            readExpectation.fulfill()
        }

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        let startTime = CFAbsoluteTimeGetCurrent()

        let testData = "Quick read test".data(using: .utf8)!
        testData.withUnsafeBytes { bufferPointer in
            let rawPointer = bufferPointer.baseAddress!
            _ = Darwin.write(pipe.writeFd, rawPointer, testData.count)
        }

        wait(for: [readExpectation], timeout: 2.0)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, 0.5, "Read handler should complete quickly (not block)")

        task.testTeardownDispatchSourcesForTesting()
    }

    func testMultipleReadsAccumulate() {
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
        task.testIoAllowedOverride = NSNumber(value: true)
        task.paused = false

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        var totalReceived = Data()
        let lock = NSLock()

        let messages = ["First", "Second", "Third"]
        let expectedBytes = messages.reduce(0) { $0 + $1.data(using: .utf8)!.count }

        mockDelegate.onThreadedRead = { data in
            lock.lock()
            totalReceived.append(data)
            lock.unlock()
        }

        for msg in messages {
            let data = msg.data(using: .utf8)!
            data.withUnsafeBytes { bufferPointer in
                let rawPointer = bufferPointer.baseAddress!
                _ = Darwin.write(pipe.writeFd, rawPointer, data.count)
            }
        }

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

        lock.lock()
        let receivedString = String(data: totalReceived, encoding: .utf8) ?? ""
        lock.unlock()

        for msg in messages {
            XCTAssertTrue(receivedString.contains(msg), "Should receive message: \(msg)")
        }

        task.testTeardownDispatchSourcesForTesting()
    }
}

// MARK: - Write Path Tests

/// Tests for write buffer and write source behavior
final class DispatchSourceWriteHandlerTests: XCTestCase {

    func testWriteBufferDidChangeWakesWriteSource() {
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
        task.testShouldWriteOverride = true

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testIsWriteSourceSuspended(), "Write source should start suspended (empty buffer)")
        XCTAssertFalse(task.testWriteBufferHasData(), "Write buffer should be empty initially")

        let testData = "Hello".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)

        XCTAssertTrue(task.testWriteBufferHasData(), "Write buffer should have data after append")
        XCTAssertTrue(task.wantsWrite,
                      "wantsWrite should be true with override and data in buffer")

        task.perform(NSSelectorFromString("writeBufferDidChange"))
        task.testWaitForIOQueue()

        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData() {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained, "Write buffer should be drained after write source fires")

        task.testShouldWriteOverride = false
        task.testTeardownDispatchSourcesForTesting()
    }

    func testWriteSourceResumesWhenBufferFills() {
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
        task.testShouldWriteOverride = true

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        XCTAssertFalse(task.testWriteBufferHasData(), "Buffer should be empty initially")
        XCTAssertTrue(task.testIsWriteSourceSuspended(), "Write source should be suspended with empty buffer")

        let testData = "Test data for write source".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)
        XCTAssertTrue(task.testWriteBufferHasData(), "Buffer should have data after append")
        XCTAssertTrue(task.wantsWrite, "wantsWrite should be true with override and data in buffer")

        task.perform(NSSelectorFromString("writeBufferDidChange"))
        task.testWaitForIOQueue()

        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData() {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained, "Buffer should be drained after write source fires")

        task.testShouldWriteOverride = false
        task.testTeardownDispatchSourcesForTesting()
    }

    func testWriteSourceSuspendResumeCycleViaPause() {
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
        task.testShouldWriteOverride = true
        task.paused = true

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        XCTAssertFalse(task.testWriteBufferHasData(), "Buffer should be empty initially")
        XCTAssertTrue(task.testIsWriteSourceSuspended(), "Write source should be SUSPENDED when paused")

        let testData = "Data for resume test".data(using: .utf8)!
        task.testAppendData(toWriteBuffer: testData)
        XCTAssertTrue(task.testWriteBufferHasData(), "Buffer should have data after append")

        task.perform(NSSelectorFromString("writeBufferDidChange"))
        task.testWaitForIOQueue()

        XCTAssertFalse(task.wantsWrite, "wantsWrite should be false when paused")
        XCTAssertTrue(task.testIsWriteSourceSuspended(), "Write source should stay SUSPENDED when paused")
        XCTAssertTrue(task.testWriteBufferHasData(), "Buffer should still have data (no write occurred)")

        // Unpause - write source should RESUME and drain buffer
        task.paused = false
        task.perform(NSSelectorFromString("updateWriteSourceState"))
        task.testWaitForIOQueue()

        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData() {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained, "Buffer should be drained after unpause triggers write")

        task.testShouldWriteOverride = false
        task.testTeardownDispatchSourcesForTesting()
    }
}

// MARK: - Write Path Round-Trip Tests

/// Tests that verify data written via writeTask: actually appears on the fd.
final class DispatchSourceWritePathRoundTripTests: XCTestCase {

    func testWriteTaskDataAppearsOnFd() throws {
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

        XCTAssertTrue(task.testIsWriteSourceSuspended(), "Write source should start suspended (empty buffer)")

        let testMessage = "Hello from keyboard!"
        let testData = testMessage.data(using: .utf8)!
        task.write(testData)

        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData() {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained, "Write buffer should be drained after write source fires")

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
        task.testIoAllowedOverride = NSNumber(value: false)

        task.testSetupDispatchSourcesForTesting()
        defer { task.testTeardownDispatchSourcesForTesting() }
        task.testWaitForIOQueue()

        let testData = "Should not appear".data(using: .utf8)!
        task.write(testData)
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testWriteBufferHasData(),
                      "Buffer should retain data when ioAllowed is false")

        var readBuffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = Darwin.read(pipe.readFd, &readBuffer, readBuffer.count)
        XCTAssertEqual(bytesRead, -1, "Pipe should have no data (EAGAIN expected)")
        XCTAssertEqual(errno, EAGAIN, "Read should return EAGAIN on empty non-blocking pipe")
    }

    func testMultipleWriteTaskCallsAccumulate() throws {
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

        task.write("Hello ".data(using: .utf8)!)
        task.write("World".data(using: .utf8)!)
        task.write("!".data(using: .utf8)!)

        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData() {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained, "All data should be written")

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

        // NO OVERRIDES - use real job manager behavior
        let jobManager = task.value(forKey: "jobManager")
        XCTAssertNotNil(jobManager, "Job manager should exist after testSetFd")

        // Check wantsWrite transitions WITHOUT dispatch sources
        XCTAssertFalse(task.wantsWrite, "wantsWrite should be false with empty buffer")

        let testMessage = "Real job manager test"
        task.write(testMessage.data(using: .utf8)!)
        XCTAssertTrue(task.wantsWrite,
                      "wantsWrite should be true after adding data")

        // Now set up dispatch sources - the write source will drain the buffer
        task.testSetupDispatchSourcesForTesting()
        defer { task.testTeardownDispatchSourcesForTesting() }

        var bufferDrained = false
        for _ in 0..<100 {
            task.testWaitForIOQueue()
            if !task.testWriteBufferHasData() {
                bufferDrained = true
                break
            }
        }
        XCTAssertTrue(bufferDrained, "Buffer should be drained with real job manager")

        var readBuffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = Darwin.read(pipe.readFd, &readBuffer, readBuffer.count)
        XCTAssertGreaterThan(bytesRead, 0, "Data should have been written to pipe")
        if bytesRead > 0 {
            let received = String(data: Data(bytes: readBuffer, count: bytesRead), encoding: .utf8)
            XCTAssertEqual(received, testMessage, "Written data should match")
        }
    }
}
