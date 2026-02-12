//
//  PTYTaskDispatchSourceTests.swift
//  ModernTests
//
//  Regression tests for PTYTask dispatch source lifecycle:
//  - EOF propagation (read() returning 0 must trigger brokenPipe)
//  - Dispatch source teardown on brokenPipe
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - EOF Propagation Tests

/// Tests that EOF on the PTY fd (read returning 0) correctly triggers brokenPipe.
/// Regression: Previously, handleReadEvent silently returned on EOF, leaving the
/// session open and the dispatch source firing in an infinite no-op loop.
final class PTYTaskEOFTests: XCTestCase {

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

        // Use the read end as the PTY fd
        task.testSetFd(pipe.readFd)
        task.testIoAllowedOverride = NSNumber(value: true)
        task.testSetupDispatchSourcesForTesting()
    }

    override func tearDown() {
        task.testTeardownDispatchSourcesForTesting()
        // Close write end if still open (read end closed by teardown or brokenPipe)
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
        // Close write end → next read() returns 0 (EOF)
        close(pipe.writeFd)

        // Wait for the dispatch source to fire and process the EOF
        let result = waitForCondition({ self.task.hasBrokenPipe() }, timeout: 2.0)
        XCTAssertTrue(result, "brokenPipe should be set after EOF")
        XCTAssertTrue(mockDelegate.threadedBrokenPipeCalled,
                      "threadedTaskBrokenPipe should be called on EOF")
    }

    /// When there's buffered data followed by EOF, the data must be delivered
    /// before brokenPipe is called.
    func testEOFDeliversBufferedDataFirst() {
        let testMessage = "hello from PTY"

        // Write data then close write end to create: data + EOF in sequence
        writeToFd(pipe.writeFd, data: testMessage)
        close(pipe.writeFd)

        // Wait for brokenPipe (which happens after data delivery)
        let result = waitForCondition({ self.task.hasBrokenPipe() }, timeout: 2.0)
        XCTAssertTrue(result, "brokenPipe should be set after EOF")

        // Verify data was delivered to delegate before brokenPipe
        XCTAssertFalse(mockDelegate.readData.isEmpty,
                       "Data should be delivered before brokenPipe")
        let received = mockDelegate.readData.reduce(Data(), +)
        let receivedString = String(data: received, encoding: .utf8)
        XCTAssertEqual(receivedString, testMessage,
                       "All buffered data should be delivered before EOF processing")
    }
}

// MARK: - Dispatch Source Teardown on brokenPipe Tests

/// Tests that brokenPipe tears down dispatch sources, preventing post-deregister
/// handler invocations on a dead fd.
/// Regression: Previously, brokenPipe only called deregisterTask: (no-op for
/// fairness tasks not in _tasks), leaving sources active on the closed fd.
final class PTYTaskBrokenPipeSourceTeardownTests: XCTestCase {

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
        // Sources should already be torn down by brokenPipe in most tests,
        // but call teardown defensively for tests that don't trigger brokenPipe.
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
        // Verify sources exist before EOF
        task.testWaitForIOQueue()
        XCTAssertTrue(task.testHasReadSource, "Read source should exist before EOF")
        XCTAssertTrue(task.testHasWriteSource, "Write source should exist before EOF")

        // Trigger EOF
        close(pipe.writeFd)

        // Wait for brokenPipe to be called
        let result = waitForCondition({ self.task.hasBrokenPipe() }, timeout: 2.0)
        XCTAssertTrue(result, "brokenPipe should be set after EOF")

        // Drain ioQueue to ensure teardown has completed
        task.testWaitForIOQueue()

        // Verify sources are torn down
        XCTAssertFalse(task.testHasReadSource,
                       "Read source must be nil after brokenPipe")
        XCTAssertFalse(task.testHasWriteSource,
                       "Write source must be nil after brokenPipe")
    }

    /// After brokenPipe, the read source must not fire again.
    /// We verify this by checking that no new data is delivered after brokenPipe.
    func testNoReadEventsAfterBrokenPipe() {
        // Trigger EOF
        close(pipe.writeFd)

        // Wait for brokenPipe
        let result = waitForCondition({ self.task.hasBrokenPipe() }, timeout: 2.0)
        XCTAssertTrue(result, "brokenPipe should be set after EOF")

        // Record read count at this point
        task.testWaitForIOQueue()
        let readCountAfterBrokenPipe = mockDelegate.readData.count

        // Wait a bit to ensure no spurious handler invocations
        Thread.sleep(forTimeInterval: 0.1)
        task.testWaitForIOQueue()

        XCTAssertEqual(mockDelegate.readData.count, readCountAfterBrokenPipe,
                       "No new read events should fire after brokenPipe tears down sources")
    }
}
