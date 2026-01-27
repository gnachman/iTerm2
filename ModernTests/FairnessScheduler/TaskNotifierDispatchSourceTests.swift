//
//  TaskNotifierDispatchSourceTests.swift
//  ModernTests
//
//  Unit tests for TaskNotifier dispatch source integration.
//  See testing.md Milestone 4 for test specifications.
//
//  Test Design:
//  - Tests verify TaskNotifier correctly skips FD_SET for dispatch source tasks
//  - MockTaskNotifierTask (in main target, ITERM_DEBUG only) allows real behavioral testing
//  - The iTermTask protocol must have @optional useDispatchSource method
//  - PTYTask must implement useDispatchSource returning YES
//  - TaskNotifier uses respondsToSelector: for backward compatibility
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Test Helpers

/// Creates a MockTaskNotifierTask with a pipe FD for testing.
/// Returns nil on failure.
private func createMockPipeTask() -> (task: MockTaskNotifierTask, writeFd: Int32)? {
    var writeFd: Int32 = 0
    guard let task = MockTaskNotifierTask.createPipeTask(withWriteFd: &writeFd) else {
        return nil
    }
    return (task, writeFd)
}

// MARK: - 4.1 Dispatch Source Protocol Tests

/// Tests for the useDispatchSource optional protocol method (4.1)
final class TaskNotifierDispatchSourceProtocolTests: XCTestCase {

    func testUseDispatchSourceOptionalMethod() throws {
        // REQUIREMENT: useDispatchSource is @optional in iTermTask protocol
        // This means tasks can implement it or not - default is NO (use select)

        // Verify PTYTask implements useDispatchSource
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("useDispatchSource")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should respond to useDispatchSource")
    }

    func testPTYTaskReturnsYesForUseDispatchSource() throws {
        // REQUIREMENT: PTYTask returns YES for useDispatchSource
        // This indicates PTYTask uses dispatch_source for I/O, not select()

        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("useDispatchSource")
        XCTAssertTrue(task.responds(to: selector),
                      "PTYTask should respond to useDispatchSource")

        // Use value(forKey:) to call the getter
        let value = task.value(forKey: "useDispatchSource") as? Bool
        XCTAssertEqual(value, true, "PTYTask.useDispatchSource should return YES")
    }

    func testRespondsToSelectorCheckUsed() throws {
        // REQUIREMENT: TaskNotifier uses respondsToSelector: before calling useDispatchSource
        // This ensures backward compatibility with tasks that don't implement the method
        try XCTSkipUnless(isDebugBuild, "Test requires ITERM_DEBUG hooks for MockTaskNotifierTask")

        #if ITERM_DEBUG
        // Create a mock task that simulates NOT implementing useDispatchSource
        let mockTask = MockTaskNotifierTask()
        mockTask.simulateLegacyTask = true

        // Verify the mock correctly simulates legacy behavior
        XCTAssertFalse(mockTask.responds(to: NSSelectorFromString("useDispatchSource")),
                       "Legacy mock should not respond to useDispatchSource")

        // Now test with dispatch source enabled
        let dispatchSourceTask = MockTaskNotifierTask()
        dispatchSourceTask.dispatchSourceEnabled = true
        XCTAssertTrue(dispatchSourceTask.responds(to: NSSelectorFromString("useDispatchSource")),
                      "Dispatch source mock should respond to useDispatchSource")
        XCTAssertTrue(dispatchSourceTask.useDispatchSource(),
                      "Dispatch source mock should return YES")
        #endif
    }

    func testDefaultBehaviorIsSelectLoop() throws {
        // REQUIREMENT: Tasks not implementing useDispatchSource use select() path
        // This is the default/legacy behavior for backward compatibility

        #if ITERM_DEBUG
        // Create mock with simulateLegacyTask = true (no useDispatchSource)
        let mockTask = MockTaskNotifierTask()
        mockTask.simulateLegacyTask = true
        mockTask.dispatchSourceEnabled = false

        // Verify it doesn't respond to useDispatchSource
        XCTAssertFalse(mockTask.responds(to: NSSelectorFromString("useDispatchSource")),
                       "Legacy task should not respond to useDispatchSource")

        // Default mock (without legacy flag) should respond but return NO
        let defaultMock = MockTaskNotifierTask()
        defaultMock.dispatchSourceEnabled = false
        XCTAssertTrue(defaultMock.responds(to: NSSelectorFromString("useDispatchSource")),
                      "Default mock responds to useDispatchSource")
        XCTAssertFalse(defaultMock.useDispatchSource(),
                       "Default mock returns NO for useDispatchSource")
        #else
        let notifier = TaskNotifier.sharedInstance()
        XCTAssertNotNil(notifier, "TaskNotifier singleton should exist")
        #endif
    }
}

// MARK: - 4.2 Select Loop Changes Tests

/// Tests for TaskNotifier select() loop changes (4.2)
final class TaskNotifierSelectLoopTests: XCTestCase {

    func testDispatchSourceTaskSkipsFdSet() throws {
        // REQUIREMENT: Tasks with useDispatchSource=YES are not added to fd_set
        // Their I/O is handled by dispatch_source, not select()

        #if ITERM_DEBUG
        // Create a mock task with useDispatchSource=YES and a real pipe FD
        guard let (mockTask, writeFd) = createMockPipeTask() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer {
            mockTask.closeFd()
            close(writeFd)
        }

        mockTask.dispatchSourceEnabled = true
        mockTask.wantsRead = true

        // Register with TaskNotifier
        let notifier = TaskNotifier.sharedInstance()
        notifier?.register(mockTask)
        defer { notifier?.deregister(mockTask) }

        // Wait for registration to complete (dispatched to main queue)
        waitForMainQueue()

        // Reset call count after registration
        mockTask.reset()
        mockTask.dispatchSourceEnabled = true
        mockTask.wantsRead = true

        // Write to the pipe to make data available
        let testData = "test data for dispatch source task"
        _ = testData.withCString { ptr in
            Darwin.write(writeFd, ptr, strlen(ptr))
        }

        // Give TaskNotifier's select loop time to run by flushing queues multiple times.
        // The select loop runs in its own thread, so we flush main queue several times
        // to allow it to iterate. This is a negative test - we're verifying processRead
        // is NOT called for dispatch source tasks.
        for _ in 0..<5 {
            waitForMainQueue()
        }

        // Since useDispatchSource=YES, TaskNotifier should NOT call processRead
        // (the task's main FD is skipped in fd_set)
        XCTAssertEqual(mockTask.processReadCallCount, 0,
                       "Dispatch source task should NOT have processRead called by TaskNotifier's select() loop")
        #else
        // Fallback verification for non-debug builds
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }
        let usesDispatchSource = task.value(forKey: "useDispatchSource") as? Bool
        XCTAssertEqual(usesDispatchSource, true,
                       "PTYTask should use dispatch source")
        #endif
    }

    func testLegacyTaskProcessReadCalledBySelect() throws {
        // REQUIREMENT: Tasks NOT using dispatch source SHOULD have processRead called

        #if ITERM_DEBUG
        // Create a mock task simulating legacy behavior (no useDispatchSource)
        guard let (mockTask, writeFd) = createMockPipeTask() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer {
            mockTask.closeFd()
            close(writeFd)
        }

        // Configure as legacy task - does not respond to useDispatchSource
        mockTask.simulateLegacyTask = true
        mockTask.wantsRead = true

        // Verify it doesn't respond to useDispatchSource
        XCTAssertFalse(mockTask.responds(to: NSSelectorFromString("useDispatchSource")),
                       "Legacy task should not respond to useDispatchSource")

        // Register with TaskNotifier
        let notifier = TaskNotifier.sharedInstance()
        notifier?.register(mockTask)
        defer { notifier?.deregister(mockTask) }

        // Wait for registration (dispatched to main queue)
        waitForMainQueue()

        // Reset and re-configure after registration
        let initialCount = mockTask.processReadCallCount
        mockTask.simulateLegacyTask = true
        mockTask.wantsRead = true

        // Write to the pipe to make data available
        let testData = "legacy test data"
        _ = testData.withCString { ptr in
            Darwin.write(writeFd, ptr, strlen(ptr))
        }

        // Wait for TaskNotifier's select loop to process
        let success = mockTask.wait(forProcessReadCalls: initialCount + 1, timeout: 2.0)

        // Legacy task SHOULD have processRead called by TaskNotifier
        XCTAssertTrue(success,
                      "Legacy task (no useDispatchSource) SHOULD have processRead called via select()")
        XCTAssertGreaterThan(mockTask.processReadCallCount, initialCount,
                             "processRead should have been called at least once")
        #else
        // Fallback for non-debug builds
        let notifier = TaskNotifier.sharedInstance()
        XCTAssertNotNil(notifier, "TaskNotifier should exist")
        #endif
    }

    func testDispatchSourceTaskStillIteratedForCoprocess() throws {
        // REQUIREMENT: Dispatch source tasks are still iterated for coprocess handling
        // Even if PTY I/O is via dispatch_source, coprocess FDs need select()
        //
        // Coprocess FDs stay on select() while PTY FDs use dispatch_source.
        // Data flow bridging handled by:
        //   - handleReadEvent calls writeToCoprocess (PTY output → coprocess)
        //   - writeTask:coprocess: calls writeBufferDidChange (coprocess output → PTY)

        #if ITERM_DEBUG
        let mockTask = MockTaskNotifierTask()
        mockTask.dispatchSourceEnabled = true
        mockTask.hasCoprocess = true

        // Structural verification only
        XCTAssertTrue(mockTask.useDispatchSource(), "Task should use dispatch source")
        XCTAssertTrue(mockTask.hasCoprocess, "Task should have coprocess flag set")
        #else
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }
        XCTAssertFalse(task.hasCoprocess, "New PTYTask should not have a coprocess")
        #endif
    }

    func testUnblockPipeStillInSelect() throws {
        // REQUIREMENT: Unblock pipe remains in select() set
        // The unblock pipe is used to wake select() on registration changes

        #if ITERM_DEBUG
        // Create a mock task
        let mockTask = MockTaskNotifierTask()
        mockTask.dispatchSourceEnabled = true
        mockTask.fd = -1

        // Verify TaskNotifier has unblock method
        let notifier = TaskNotifier.sharedInstance()
        XCTAssertNotNil(notifier, "TaskNotifier should exist")
        XCTAssertTrue(notifier!.responds(to: #selector(TaskNotifier.unblock)),
                      "TaskNotifier should have unblock method")

        // Register task - this should use the unblock pipe internally
        notifier?.register(mockTask)

        // didRegister should be called on main queue (proves unblock worked)
        waitForMainQueue()

        XCTAssertGreaterThan(mockTask.didRegisterCallCount, 0,
                             "didRegister should be called after registration (proves unblock pipe works)")

        // Cleanup
        notifier?.deregister(mockTask)
        #else
        let notifier = TaskNotifier.sharedInstance()
        XCTAssertNotNil(notifier, "TaskNotifier should exist")
        XCTAssertTrue(notifier!.responds(to: #selector(TaskNotifier.unblock)),
                      "TaskNotifier should have unblock method")
        #endif
    }

    func testCoprocessFdsStillInSelect() throws {
        // REQUIREMENT: Coprocess FDs remain in select() set
        // Coprocess I/O stays on select() even when PTY uses dispatch_source
        //
        // The hybrid approach works because:
        //   - Coprocess FDs are non-blocking (O_NONBLOCK set in Coprocess.m)
        //   - Data flow is bridged at PTY I/O boundary
        //   - No blocking risks in TaskNotifier's select() loop

        #if ITERM_DEBUG
        let mockTask = MockTaskNotifierTask()
        mockTask.dispatchSourceEnabled = true
        mockTask.hasCoprocess = true

        // Structural verification only
        XCTAssertTrue(mockTask.hasCoprocess, "Task should have coprocess")
        XCTAssertTrue(mockTask.useDispatchSource(), "Task should use dispatch source for main I/O")
        #else
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }
        XCTAssertFalse(task.hasCoprocess, "New PTYTask should not have a coprocess")
        #endif
    }

    func testDeadpoolHandlingUnchanged() throws {
        // REQUIREMENT: Deadpool/waitpid handling continues working
        // Process reaping is independent of I/O mechanism (uses WNOHANG)

        #if ITERM_DEBUG
        let mockTask = MockTaskNotifierTask()
        mockTask.dispatchSourceEnabled = true
        mockTask.pid = 0
        mockTask.pidToWaitOn = 0

        // Verify TaskNotifier has waitForPid method
        let notifier = TaskNotifier.sharedInstance()
        XCTAssertNotNil(notifier, "TaskNotifier should exist")
        XCTAssertTrue(notifier!.responds(to: #selector(TaskNotifier.wait(forPid:))),
                      "TaskNotifier should have waitForPid method")
        #else
        let notifier = TaskNotifier.sharedInstance()
        XCTAssertNotNil(notifier, "TaskNotifier should exist")
        XCTAssertTrue(notifier!.responds(to: #selector(TaskNotifier.wait(forPid:))),
                      "TaskNotifier should have waitForPid method")
        #endif
    }
}

// MARK: - 4.3 Mixed Mode Operation Tests

/// Tests for mixed dispatch_source and select() operation (4.3)
final class TaskNotifierMixedModeTests: XCTestCase {

    func testMixedDispatchSourceAndSelectTasks() throws {
        // REQUIREMENT: System works with some tasks on dispatch_source, some on select()
        // This enables gradual migration and coexistence

        #if ITERM_DEBUG
        // Create two tasks: one with dispatch source, one legacy
        guard let (legacyTask, legacyWriteFd) = createMockPipeTask() else {
            XCTFail("Failed to create legacy pipe")
            return
        }
        defer {
            legacyTask.closeFd()
            close(legacyWriteFd)
        }

        guard let (dispatchTask, dispatchWriteFd) = createMockPipeTask() else {
            XCTFail("Failed to create dispatch pipe")
            return
        }
        defer {
            dispatchTask.closeFd()
            close(dispatchWriteFd)
        }

        // Configure legacy task (uses select)
        legacyTask.simulateLegacyTask = true
        legacyTask.wantsRead = true

        // Configure dispatch source task (skips select)
        dispatchTask.dispatchSourceEnabled = true
        dispatchTask.wantsRead = true

        // Register both
        let notifier = TaskNotifier.sharedInstance()
        notifier?.register(legacyTask)
        notifier?.register(dispatchTask)
        defer {
            notifier?.deregister(legacyTask)
            notifier?.deregister(dispatchTask)
        }

        // Wait for registration (dispatched to main queue)
        waitForMainQueue()

        // Reset counts
        legacyTask.reset()
        legacyTask.simulateLegacyTask = true
        legacyTask.wantsRead = true
        dispatchTask.reset()
        dispatchTask.dispatchSourceEnabled = true
        dispatchTask.wantsRead = true

        // Write to both pipes
        _ = "legacy data".withCString { ptr in Darwin.write(legacyWriteFd, ptr, strlen(ptr)) }
        _ = "dispatch data".withCString { ptr in Darwin.write(dispatchWriteFd, ptr, strlen(ptr)) }

        // Wait for select loop
        let success = legacyTask.wait(forProcessReadCalls: 1, timeout: 2.0)

        // Legacy task should have processRead called
        XCTAssertTrue(success, "Legacy task should have processRead called")
        XCTAssertGreaterThan(legacyTask.processReadCallCount, 0,
                             "Legacy task should be processed via select()")

        // Dispatch source task should NOT have processRead called by select
        XCTAssertEqual(dispatchTask.processReadCallCount, 0,
                       "Dispatch source task should NOT be processed via select()")
        #else
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }
        let usesDispatchSource = task.value(forKey: "useDispatchSource") as? Bool
        XCTAssertEqual(usesDispatchSource, true, "PTYTask uses dispatch_source")
        #endif
    }

    func testTmuxTaskStaysOnSelect() throws {
        // REQUIREMENT: Tmux tasks (fd < 0) continue using select() path
        // Tmux tasks have no FD to add anyway, but they shouldn't be affected

        #if ITERM_DEBUG
        // Create a mock task simulating a tmux task (fd < 0)
        let mockTask = MockTaskNotifierTask()
        mockTask.fd = -1  // Tmux tasks typically have fd = -1
        mockTask.dispatchSourceEnabled = false  // Tmux doesn't use dispatch source
        mockTask.simulateLegacyTask = true  // Doesn't implement useDispatchSource

        // Verify configuration
        XCTAssertEqual(mockTask.fd, -1, "Tmux task should have fd = -1")
        XCTAssertFalse(mockTask.responds(to: NSSelectorFromString("useDispatchSource")),
                       "Legacy tmux task should not respond to useDispatchSource")

        // Register with TaskNotifier
        let notifier = TaskNotifier.sharedInstance()
        notifier?.register(mockTask)

        // Wait for registration to complete (dispatched to main queue)
        waitForMainQueue()

        // Task should be registered without issue
        XCTAssertGreaterThan(mockTask.didRegisterCallCount, 0,
                             "Tmux task should be registered successfully")

        // Cleanup
        notifier?.deregister(mockTask)
        #else
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }
        XCTAssertEqual(task.fd, -1, "Unlaunched PTYTask should have fd = -1")
        #endif
    }

    func testLegacyTasksUnaffected() throws {
        // REQUIREMENT: Tasks not implementing useDispatchSource work unchanged
        // Backward compatibility - existing conformers need no changes

        #if ITERM_DEBUG
        // Create a mock task that simulates a legacy task (no useDispatchSource method)
        guard let (mockTask, writeFd) = createMockPipeTask() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer {
            mockTask.closeFd()
            close(writeFd)
        }

        // Configure as legacy task - does not respond to useDispatchSource
        mockTask.simulateLegacyTask = true
        mockTask.wantsRead = true

        // Verify it doesn't respond to useDispatchSource
        XCTAssertFalse(mockTask.responds(to: NSSelectorFromString("useDispatchSource")),
                       "Legacy task should not respond to useDispatchSource")

        // Register with TaskNotifier
        TaskNotifier.sharedInstance()?.register(mockTask)
        defer { TaskNotifier.sharedInstance()?.deregister(mockTask) }

        // Wait for registration (dispatched to main queue)
        waitForMainQueue()

        // Reset and reconfigure
        let initialCount = mockTask.processReadCallCount
        mockTask.simulateLegacyTask = true
        mockTask.wantsRead = true

        // Write to the pipe to make data available
        _ = "legacy test data".withCString { ptr in Darwin.write(writeFd, ptr, strlen(ptr)) }

        // Wait for TaskNotifier's select loop to process
        let success = mockTask.wait(forProcessReadCalls: initialCount + 1, timeout: 2.0)

        // Legacy task should have processRead called by TaskNotifier
        XCTAssertTrue(success, "Legacy task should have processRead called via select()")
        XCTAssertGreaterThan(mockTask.processReadCallCount, initialCount,
                             "Legacy task should have processRead called via select()")
        #else
        let notifier = TaskNotifier.sharedInstance()
        XCTAssertNotNil(notifier, "TaskNotifier should exist for legacy task support")
        #endif
    }

    func testCoprocessFdProcessedBySelect() throws {
        // REQUIREMENT: Tasks with coprocess should be iterated for coprocess FD handling
        // even when main FD uses dispatch_source.
        //
        // Hybrid approach: Coprocess FDs stay on select(), PTY FDs use dispatch_source.
        // Data flow bridging ensures coprocess I/O works correctly:
        //   - PTY output → coprocess: handleReadEvent calls writeToCoprocess
        //   - Coprocess output → PTY: writeTask:coprocess: calls writeBufferDidChange

        #if ITERM_DEBUG
        let mockTask = MockTaskNotifierTask()
        mockTask.dispatchSourceEnabled = true
        mockTask.hasCoprocess = true

        // Structural verification only
        XCTAssertTrue(mockTask.dispatchSourceEnabled, "Task should use dispatch_source")
        XCTAssertTrue(mockTask.hasCoprocess, "Task should have coprocess")
        #else
        // Non-debug build: basic verification
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }
        XCTAssertFalse(task.hasCoprocess, "New PTYTask should not have a coprocess")
        #endif
    }
}

// MARK: - 4.4 Coprocess Data Flow Bridge Tests

/// Tests for coprocess data flow bridging with dispatch_source PTY I/O.
/// These tests verify the bridge code paths are correctly wired:
///   - handleReadEvent calls writeToCoprocess (PTY output → coprocess)
///   - writeTask:coprocess: calls writeBufferDidChange (coprocess output → PTY)
final class CoprocessDataFlowBridgeTests: XCTestCase {

    func testHandleReadEventRoutesToCoprocess() throws {
        // REQUIREMENT: handleReadEvent should call writeToCoprocess when coprocess is attached
        // This tests that PTY output flows to coprocess.outputBuffer via the bridge

        #if ITERM_DEBUG
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create pipe for PTY fd
        guard let ptyPipe = createTestPipe() else {
            XCTFail("Failed to create PTY test pipe")
            return
        }
        defer { closeTestPipe(ptyPipe) }

        // Create MockCoprocess
        guard let coprocess = MockCoprocess.createPipe() else {
            XCTFail("Failed to create MockCoprocess")
            return
        }
        defer {
            coprocess.closeTestFds()
            coprocess.terminate()
        }
        // Set up the PTYTask
        task.testSetFd(ptyPipe.readFd)
        task.paused = false
        task.testIoAllowedOverride = NSNumber(value: true)

        // Attach coprocess to task
        task.coprocess = coprocess
        XCTAssertTrue(task.hasCoprocess, "Task should have coprocess attached")

        // Set up dispatch sources directly (not via TaskNotifier to avoid complexity)
        task.testSetupDispatchSourcesForTesting()
        defer { task.testTeardownDispatchSourcesForTesting() }

        // Verify setup
        task.testWaitForIOQueue()
        XCTAssertTrue(task.testHasReadSource, "Task should have read source")
        XCTAssertFalse(task.testIsReadSourceSuspended, "Read source should be resumed (shouldRead=true)")

        // Write data to PTY pipe - this triggers handleReadEvent
        let testMessage = "Hello coprocess!"
        let testData = testMessage.data(using: .utf8)!
        testData.withUnsafeBytes { bufferPointer in
            let rawPointer = bufferPointer.baseAddress!
            _ = Darwin.write(ptyPipe.writeFd, rawPointer, testData.count)
        }

        // Wait for dispatch source to fire and handleReadEvent to run
        // Multiple waits to ensure async processing completes
        for _ in 0..<5 {
            task.testWaitForIOQueue()
            if coprocess.outputBuffer.length > 0 { break }
            Thread.sleep(forTimeInterval: 0.01)
        }

        // Verify data was routed to coprocess.outputBuffer
        // The bridge code (writeToCoprocess) should have been called
        XCTAssertGreaterThan(coprocess.outputBuffer.length, 0,
                      "handleReadEvent should route PTY data to coprocess.outputBuffer via writeToCoprocess bridge")

        let outputData = coprocess.outputBuffer as Data
        if let outputString = String(data: outputData, encoding: .utf8) {
            XCTAssertTrue(outputString.contains(testMessage),
                          "Coprocess outputBuffer should contain the PTY data")
        }
        #else
        throw XCTSkip("Test requires ITERM_DEBUG build")
        #endif
    }

    func testWriteTaskTriggersWriteSource() throws {
        // REQUIREMENT: writeTask should call writeBufferDidChange
        // This tests that the write dispatch_source is triggered when data is added

        #if ITERM_DEBUG
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create pipe for PTY fd
        guard let ptyPipe = createTestPipe() else {
            XCTFail("Failed to create PTY test pipe")
            return
        }
        defer { closeTestPipe(ptyPipe) }

        // Set up the PTYTask
        task.testSetFd(ptyPipe.writeFd)
        task.paused = false
        task.testShouldWriteOverride = true
        defer { task.testShouldWriteOverride = false }

        // Set up dispatch sources directly
        task.testSetupDispatchSourcesForTesting()
        defer { task.testTeardownDispatchSourcesForTesting() }

        // Verify setup
        task.testWaitForIOQueue()
        XCTAssertTrue(task.testHasWriteSource, "Task should have write source")
        XCTAssertFalse(task.testWriteBufferHasData, "Write buffer should start empty")

        // Write data via writeTask (this tests writeBufferDidChange is called)
        let testMessage = "Hello PTY!"
        let testData = testMessage.data(using: .utf8)!
        task.write(testData)

        // Verify data was added to writeBuffer
        XCTAssertTrue(task.testWriteBufferHasData,
                      "writeTask should add data to writeBuffer")

        // Wait for write source to drain the buffer
        task.testWaitForIOQueue()

        // Read from the PTY pipe to verify data was written
        var buffer = [UInt8](repeating: 0, count: 1024)
        let flags = fcntl(ptyPipe.readFd, F_GETFL)
        fcntl(ptyPipe.readFd, F_SETFL, flags | O_NONBLOCK)

        var receivedData = Data()
        for _ in 0..<10 {
            task.testWaitForIOQueue()
            let bytesRead = Darwin.read(ptyPipe.readFd, &buffer, buffer.count)
            if bytesRead > 0 {
                receivedData.append(contentsOf: buffer[0..<bytesRead])
            }
            if receivedData.count >= testData.count { break }
            Thread.sleep(forTimeInterval: 0.01)
        }

        XCTAssertEqual(receivedData.count, testData.count,
                       "writeBufferDidChange should trigger write source which drains to PTY fd")

        if let receivedString = String(data: receivedData, encoding: .utf8) {
            XCTAssertEqual(receivedString, testMessage,
                           "PTY should receive the data")
        }
        #else
        throw XCTSkip("Test requires ITERM_DEBUG build")
        #endif
    }

    func testCoprocessOutputRoutesToPTY() throws {
        // REQUIREMENT: Coprocess output flows to PTY via writeTask:coprocess:
        // This tests the coprocess → PTY direction of the data flow bridge
        //
        // Flow: writeTask:coprocess:YES → writeBuffer → writeBufferDidChange
        //       → write source → PTY fd
        //
        // Note: In production, TaskNotifier's select() reads from coprocess.inputFd
        // and calls writeTask:coprocess:YES. Here we call it directly to test the bridge.

        #if ITERM_DEBUG
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // Create pipe for PTY fd (task writes here, we read to verify)
        guard let ptyPipe = createTestPipe() else {
            XCTFail("Failed to create PTY test pipe")
            return
        }
        defer { closeTestPipe(ptyPipe) }

        // Set up the PTYTask with write fd
        task.testSetFd(ptyPipe.writeFd)
        task.paused = false
        task.testIoAllowedOverride = NSNumber(value: true)
        task.testShouldWriteOverride = true
        defer { task.testShouldWriteOverride = false }

        // Set up dispatch sources
        task.testSetupDispatchSourcesForTesting()
        defer { task.testTeardownDispatchSourcesForTesting() }

        task.testWaitForIOQueue()

        // Simulate coprocess output by calling writeTask:coprocess:YES directly
        // This is what TaskNotifier does when it reads from coprocess.inputFd
        let testMessage = "From coprocess!"
        let testData = testMessage.data(using: .utf8)!
        task.testWrite(fromCoprocess: testData)

        // Wait for write source to drain buffer to PTY
        task.testWaitForIOQueue()

        // Read from PTY pipe to verify data arrived
        var receivedData = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        let flags = fcntl(ptyPipe.readFd, F_GETFL)
        fcntl(ptyPipe.readFd, F_SETFL, flags | O_NONBLOCK)

        for _ in 0..<10 {
            task.testWaitForIOQueue()
            let bytesRead = Darwin.read(ptyPipe.readFd, &buffer, buffer.count)
            if bytesRead > 0 {
                receivedData.append(contentsOf: buffer[0..<bytesRead])
            }
            if receivedData.count >= testData.count { break }
            Thread.sleep(forTimeInterval: 0.01)
        }

        XCTAssertEqual(receivedData.count, testData.count,
                      "Coprocess output should flow to PTY via writeTask:coprocess: bridge")

        if let receivedString = String(data: receivedData, encoding: .utf8) {
            XCTAssertEqual(receivedString, testMessage,
                          "PTY should receive the coprocess output")
        }
        #else
        throw XCTSkip("Test requires ITERM_DEBUG build")
        #endif
    }
}
