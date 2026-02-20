//
//  DispatchSourceEOFTests.swift
//  ModernTests
//
//  Tests for EOF propagation and broken pipe handling with dispatch sources.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - EOF Propagation Tests

/// Tests that EOF on the PTY fd (read returning 0) correctly triggers brokenPipe.
final class DispatchSourceEOFTests: XCTestCase {

    var task: PTYTask!
    var mockDelegate: MockPTYTaskDelegate!
    var pipe: (readFd: Int32, writeFd: Int32)!

    override func setUp() {
        super.setUp()
        task = PTYTask()
        mockDelegate = MockPTYTaskDelegate()
        task.delegate = mockDelegate

        pipe = createTestPipe()
        XCTAssertNotNil(pipe, "Failed to create test pipe")

        task.testSetFd(pipe.readFd)
        task.testIoAllowedOverride = NSNumber(value: true)
        task.testSetupDispatchSourcesForTesting()
    }

    override func tearDown() {
        task.testTeardownDispatchSourcesForTesting()
        if pipe != nil {
            close(pipe.writeFd)
        }
        task.delegate = nil
        task = nil
        mockDelegate = nil
        super.tearDown()
    }

    /// Closing the write end of the pipe triggers EOF on the read end.
    /// handleReadEvent must detect this and call brokenPipe.
    func testEOFTriggersBrokenPipe() {
        close(pipe.writeFd)

        let result = waitForCondition({ self.task.hasBrokenPipe() }, timeout: 2.0)
        XCTAssertTrue(result, "brokenPipe should be set after EOF")
        XCTAssertTrue(mockDelegate.threadedBrokenPipeCalled,
                      "threadedTaskBrokenPipe should be called on EOF")
    }

    /// When there's buffered data followed by EOF, the data must be delivered
    /// before brokenPipe is called.
    func testEOFDeliversBufferedDataFirst() {
        let testMessage = "hello from PTY"

        writeToFd(pipe.writeFd, data: testMessage)
        close(pipe.writeFd)

        let result = waitForCondition({ self.task.hasBrokenPipe() }, timeout: 2.0)
        XCTAssertTrue(result, "brokenPipe should be set after EOF")

        XCTAssertFalse(mockDelegate.readData.isEmpty,
                       "Data should be delivered before brokenPipe")
        let received = mockDelegate.readData.reduce(Data(), +)
        let receivedString = String(data: received, encoding: .utf8)
        XCTAssertEqual(receivedString, testMessage,
                       "All buffered data should be delivered before EOF processing")
    }
}

// MARK: - EOF While Paused Tests

/// Regression test: EOF must be detected even when the task is paused.
/// Pausing suspends the read source. The proc source (DISPATCH_SOURCE_TYPE_PROC)
/// detects process exit and force-resumes the read source for EOF delivery.
/// In tests we simulate this with testSimulateProcessExit().
final class DispatchSourceEOFWhilePausedTests: XCTestCase {

    var task: PTYTask!
    var mockDelegate: MockPTYTaskDelegate!
    var pipe: (readFd: Int32, writeFd: Int32)!

    override func setUp() {
        super.setUp()
        task = PTYTask()
        mockDelegate = MockPTYTaskDelegate()
        task.delegate = mockDelegate

        pipe = createTestPipe()
        XCTAssertNotNil(pipe, "Failed to create test pipe")

        task.testSetFd(pipe.readFd)
        task.testIoAllowedOverride = NSNumber(value: true)
        task.testSetupDispatchSourcesForTesting()
    }

    override func tearDown() {
        task.testTeardownDispatchSourcesForTesting()
        if pipe != nil {
            close(pipe.writeFd)
        }
        task.delegate = nil
        task = nil
        mockDelegate = nil
        super.tearDown()
    }

    /// Closing the write end while paused must still trigger brokenPipe.
    /// The proc source detects process exit and force-resumes the read source
    /// so EOF can be delivered. We simulate this with testSimulateProcessExit().
    func testEOFDetectedWhilePaused() {
        task.testWaitForIOQueue()

        task.paused = true
        task.testWaitForIOQueue()

        // EOF while paused
        close(pipe.writeFd)

        // Simulate the proc source firing (real child processes get a real proc source)
        task.testSimulateProcessExit()
        task.testWaitForIOQueue()

        let result = waitForCondition({ self.task.hasBrokenPipe() }, timeout: 2.0)
        XCTAssertTrue(result, "brokenPipe must be detected even while paused")
        XCTAssertTrue(mockDelegate.threadedBrokenPipeCalled,
                      "threadedTaskBrokenPipe must be called even while paused")
    }

    /// Buffered data followed by EOF while paused must drain data
    /// before reporting brokenPipe, once the proc source force-resumes reads.
    func testEOFWhilePausedDeliversBufferedData() {
        task.testWaitForIOQueue()

        task.paused = true
        task.testWaitForIOQueue()

        let testMessage = "data before EOF while paused"
        writeToFd(pipe.writeFd, data: testMessage)
        close(pipe.writeFd)

        // Simulate the proc source firing
        task.testSimulateProcessExit()
        task.testWaitForIOQueue()

        let result = waitForCondition({ self.task.hasBrokenPipe() }, timeout: 2.0)
        XCTAssertTrue(result, "brokenPipe must be detected even while paused")

        XCTAssertFalse(mockDelegate.readData.isEmpty,
                       "Buffered data must be delivered even while paused")
        let received = mockDelegate.readData.reduce(Data(), +)
        let receivedString = String(data: received, encoding: .utf8)
        XCTAssertEqual(receivedString, testMessage,
                       "All buffered data must be delivered before brokenPipe while paused")
    }
}

// MARK: - Dispatch Source Teardown on brokenPipe Tests

/// Tests that brokenPipe tears down dispatch sources, preventing post-deregister
/// handler invocations on a dead fd.
final class DispatchSourceBrokenPipeTeardownTests: XCTestCase {

    var task: PTYTask!
    var mockDelegate: MockPTYTaskDelegate!
    var pipe: (readFd: Int32, writeFd: Int32)!

    override func setUp() {
        super.setUp()
        task = PTYTask()
        mockDelegate = MockPTYTaskDelegate()
        task.delegate = mockDelegate

        pipe = createTestPipe()
        XCTAssertNotNil(pipe, "Failed to create test pipe")

        task.testSetFd(pipe.readFd)
        task.testIoAllowedOverride = NSNumber(value: true)
        task.testSetupDispatchSourcesForTesting()
    }

    override func tearDown() {
        task.testTeardownDispatchSourcesForTesting()
        if pipe != nil {
            close(pipe.writeFd)
        }
        task.delegate = nil
        task = nil
        mockDelegate = nil
        super.tearDown()
    }

    /// After brokenPipe (triggered by EOF), dispatch sources must be torn down.
    func testBrokenPipeTeardownsDispatchSources() {
        task.testWaitForIOQueue()
        XCTAssertTrue(task.testHasReadSource(), "Read source should exist before EOF")
        XCTAssertTrue(task.testHasWriteSource(), "Write source should exist before EOF")

        close(pipe.writeFd)

        let result = waitForCondition({ self.task.hasBrokenPipe() }, timeout: 2.0)
        XCTAssertTrue(result, "brokenPipe should be set after EOF")

        task.testWaitForIOQueue()

        XCTAssertFalse(task.testHasReadSource(), "Read source must be nil after brokenPipe")
        XCTAssertFalse(task.testHasWriteSource(), "Write source must be nil after brokenPipe")
    }

    /// After brokenPipe, the read source must not fire again.
    func testNoReadEventsAfterBrokenPipe() {
        close(pipe.writeFd)

        let result = waitForCondition({ self.task.hasBrokenPipe() }, timeout: 2.0)
        XCTAssertTrue(result, "brokenPipe should be set after EOF")

        task.testWaitForIOQueue()
        let readCountAfterBrokenPipe = mockDelegate.readData.count

        Thread.sleep(forTimeInterval: 0.1)
        task.testWaitForIOQueue()

        XCTAssertEqual(mockDelegate.readData.count, readCountAfterBrokenPipe,
                       "No new read events should fire after brokenPipe tears down sources")
    }
}

// MARK: - Edge Case Tests

/// Tests for PTYTask edge cases and nil-safety
final class DispatchSourceEdgeCaseTests: XCTestCase {

    func testFreshTaskHasValidState() {
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        XCTAssertFalse(task.paused, "Fresh task should not be paused")
        XCTAssertEqual(task.fd, -1, "Fresh task should have invalid fd")
    }

    func testTaskWithNilDelegate() {
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        task.delegate = nil

        task.paused = true
        XCTAssertTrue(task.paused, "Pause should work with nil delegate")

        task.paused = false
        XCTAssertFalse(task.paused, "Unpause should work with nil delegate")

        XCTAssertFalse(task.wantsRead, "wantsRead should be false without job manager")
        XCTAssertFalse(task.wantsWrite, "wantsWrite should be false without job manager")

        let readSelector = NSSelectorFromString("updateReadSourceState")
        let writeSelector = NSSelectorFromString("updateWriteSourceState")

        if task.responds(to: readSelector) {
            task.perform(readSelector)
        }
        if task.responds(to: writeSelector) {
            task.perform(writeSelector)
        }

        XCTAssertFalse(task.testHasReadSource(), "No read source with nil delegate")
        XCTAssertFalse(task.testHasWriteSource(), "No write source with nil delegate")
    }

    func testConcurrentPauseChanges() {
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let group = DispatchGroup()

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

        group.wait()
    }
}
