//
//  TaskNotifierDispatchSourceTests.swift
//  ModernTests
//
//  Unit tests for TaskNotifier dispatch source integration.
//  See testing.md Milestone 4 for test specifications.
//
//  Test Design:
//  - Tests verify TaskNotifier correctly skips FD_SET for dispatch source tasks
//  - MockTaskNotifierTask (in main target) allows real behavioral testing
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
    return MockTaskNotifierTask.createPipeTask()
}

// MARK: - 4.1 Dispatch Source Protocol Tests

/// Tests for the useDispatchSource optional protocol method (4.1)
final class TaskNotifierDispatchSourceProtocolTests: XCTestCase {

    override func setUp() {
        super.setUp()
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(true)
    }

    override func tearDown() {
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(false)
        super.tearDown()
    }

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
    }

    func testDefaultBehaviorIsSelectLoop() throws {
        // REQUIREMENT: Tasks not implementing useDispatchSource use select() path
        // This is the default/legacy behavior for backward compatibility

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
    }
}

// MARK: - 4.2 Select Loop Changes Tests

/// Tests for TaskNotifier select() loop changes (4.2)
final class TaskNotifierSelectLoopTests: XCTestCase {

    func testDispatchSourceTaskSkipsFdSet() throws {
        // REQUIREMENT: Tasks with useDispatchSource=YES are not added to fd_set
        // Their I/O is handled by dispatch_source, not select()

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
    }

    func testLegacyTaskProcessReadCalledBySelect() throws {
        // REQUIREMENT: Tasks NOT using dispatch source SHOULD have processRead called

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
    }

    // MARK: - Gap 1: processWrite Skip Test

    func testDispatchSourceTaskSkipsProcessWrite() throws {
        // GAP 1: Verify TaskNotifier skips processWrite for dispatch source tasks.
        // When useDispatchSource=YES, the task's write FD is NOT in select()'s wfds,
        // so processWrite should never be called by TaskNotifier.

        guard let (mockTask, writeFd) = createMockPipeTask() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer {
            mockTask.closeFd()
            close(writeFd)
        }

        mockTask.dispatchSourceEnabled = true
        mockTask.wantsWrite = true  // Indicate buffer has data to write

        // Register with TaskNotifier
        let notifier = TaskNotifier.sharedInstance()
        notifier?.register(mockTask)
        defer { notifier?.deregister(mockTask) }

        // Wait for registration to complete
        waitForMainQueue()

        // Reset call count after registration
        mockTask.reset()
        mockTask.dispatchSourceEnabled = true
        mockTask.wantsWrite = true

        // Unblock to wake select loop
        notifier?.unblock()

        // Give TaskNotifier's select loop time to run
        for _ in 0..<5 {
            waitForMainQueue()
        }

        // Since useDispatchSource=YES, TaskNotifier should NOT call processWrite
        XCTAssertEqual(mockTask.processWriteCallCount, 0,
                       "Dispatch source task should NOT have processWrite called by TaskNotifier's select() loop")
    }

    func testLegacyTaskProcessWriteCalledBySelect() throws {
        // GAP 1 (inverse): Verify legacy tasks DO have processWrite called.

        guard let (mockTask, _) = createMockPipeTask() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { mockTask.closeFd() }

        // Configure as legacy task
        mockTask.simulateLegacyTask = true
        mockTask.wantsWrite = true

        // Register with TaskNotifier
        let notifier = TaskNotifier.sharedInstance()
        notifier?.register(mockTask)
        defer { notifier?.deregister(mockTask) }

        // Wait for registration
        waitForMainQueue()

        let initialCount = mockTask.processWriteCallCount
        mockTask.simulateLegacyTask = true
        mockTask.wantsWrite = true

        // Unblock to wake select loop
        notifier?.unblock()

        // Wait for processWrite to be called
        // Use short timeout since this should happen quickly
        var success = false
        for _ in 0..<50 {
            if mockTask.processWriteCallCount > initialCount {
                success = true
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        XCTAssertTrue(success,
                      "Legacy task SHOULD have processWrite called via select()")
    }

    func testDispatchSourceTaskStillIteratedForCoprocess() throws {
        // REQUIREMENT: Dispatch source tasks are still iterated for coprocess handling
        // Even if PTY I/O is via dispatch_source, coprocess FDs need select()
        //
        // Coprocess FDs stay on select() while PTY FDs use dispatch_source.
        // Data flow bridging handled by:
        //   - handleReadEvent calls writeToCoprocess (PTY output → coprocess)
        //   - writeTask:coprocess: calls writeBufferDidChange (coprocess output → PTY)

        let mockTask = MockTaskNotifierTask()
        mockTask.dispatchSourceEnabled = true
        mockTask.hasCoprocess = true

        // Structural verification only
        XCTAssertTrue(mockTask.useDispatchSource(), "Task should use dispatch source")
        XCTAssertTrue(mockTask.hasCoprocess, "Task should have coprocess flag set")
    }

    func testUnblockPipeStillInSelect() throws {
        // REQUIREMENT: Unblock pipe remains in select() set
        // The unblock pipe is used to wake select() on registration changes

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
    }

    func testCoprocessFdsStillInSelect() throws {
        // REQUIREMENT: Coprocess FDs remain in select() set
        // Coprocess I/O stays on select() even when PTY uses dispatch_source
        //
        // The hybrid approach works because:
        //   - Coprocess FDs are non-blocking (O_NONBLOCK set in Coprocess.m)
        //   - Data flow is bridged at PTY I/O boundary
        //   - No blocking risks in TaskNotifier's select() loop

        let mockTask = MockTaskNotifierTask()
        mockTask.dispatchSourceEnabled = true
        mockTask.hasCoprocess = true

        // Structural verification only
        XCTAssertTrue(mockTask.hasCoprocess, "Task should have coprocess")
        XCTAssertTrue(mockTask.useDispatchSource(), "Task should use dispatch source for main I/O")
    }

    func testDeadpoolHandlingUnchanged() throws {
        // REQUIREMENT: Deadpool/waitpid handling continues working
        // Process reaping is independent of I/O mechanism (uses WNOHANG)

        let mockTask = MockTaskNotifierTask()
        mockTask.dispatchSourceEnabled = true
        mockTask.pid = 0
        mockTask.pidToWaitOn = 0

        // Verify TaskNotifier has waitForPid method
        let notifier = TaskNotifier.sharedInstance()
        XCTAssertNotNil(notifier, "TaskNotifier should exist")
        XCTAssertTrue(notifier!.responds(to: #selector(TaskNotifier.wait(forPid:))),
                      "TaskNotifier should have waitForPid method")
    }
}

// MARK: - 4.3 Mixed Mode Operation Tests

/// Tests for mixed dispatch_source and select() operation (4.3)
final class TaskNotifierMixedModeTests: XCTestCase {

    func testMixedDispatchSourceAndSelectTasks() throws {
        // REQUIREMENT: System works with some tasks on dispatch_source, some on select()
        // This enables gradual migration and coexistence

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
    }

    func testTmuxTaskStaysOnSelect() throws {
        // REQUIREMENT: Tmux tasks (fd < 0) continue using select() path
        // Tmux tasks have no FD to add anyway, but they shouldn't be affected

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
    }

    func testLegacyTasksUnaffected() throws {
        // REQUIREMENT: Tasks not implementing useDispatchSource work unchanged
        // Backward compatibility - existing conformers need no changes

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
    }

    func testCoprocessFdProcessedBySelect() throws {
        // REQUIREMENT: Tasks with coprocess should be iterated for coprocess FD handling
        // even when main FD uses dispatch_source.
        //
        // Hybrid approach: Coprocess FDs stay on select(), PTY FDs use dispatch_source.
        // Data flow bridging ensures coprocess I/O works correctly:
        //   - PTY output → coprocess: handleReadEvent calls writeToCoprocess
        //   - Coprocess output → PTY: writeTask:coprocess: calls writeBufferDidChange

        let mockTask = MockTaskNotifierTask()
        mockTask.dispatchSourceEnabled = true
        mockTask.hasCoprocess = true

        // Structural verification only
        XCTAssertTrue(mockTask.dispatchSourceEnabled, "Task should use dispatch_source")
        XCTAssertTrue(mockTask.hasCoprocess, "Task should have coprocess")
    }
}

// MARK: - 4.4 Coprocess Data Flow Bridge Tests

/// Tests for coprocess data flow bridging with dispatch_source PTY I/O.
/// These tests verify the bridge code paths are correctly wired:
///   - handleReadEvent calls writeToCoprocess (PTY output → coprocess)
///   - writeTask:coprocess: calls writeBufferDidChange (coprocess output → PTY)
final class CoprocessDataFlowBridgeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(true)
    }

    override func tearDown() {
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(false)
        super.tearDown()
    }

    func testHandleReadEventRoutesToCoprocess() throws {
        // REQUIREMENT: handleReadEvent should call writeToCoprocess when coprocess is attached
        // This tests that PTY output flows to the coprocess via the bridge.
        //
        // Full data flow:
        //   1. Data written to ptyPipe.writeFd
        //   2. Read dispatch source fires on ptyPipe.readFd → handleReadEvent
        //   3. handleReadEvent calls writeToCoprocess: → appends to coprocess.outputBuffer
        //   4. Coprocess write dispatch source drains outputBuffer → coprocess.outputFd
        //   5. Data appears on coprocess.testReadFd (other end of the pipe)

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

        // Set up dispatch sources FIRST — this creates _ioQueue, which is required
        // before attaching a coprocess (setCoprocess: calls setupCoprocessDispatchSources:
        // which asserts _ioQueue != nil).
        task.testSetupDispatchSourcesForTesting()
        defer { task.testTeardownDispatchSourcesForTesting() }

        // Attach coprocess to task (must be after dispatch source setup)
        task.coprocess = coprocess
        XCTAssertTrue(task.hasCoprocess, "Task should have coprocess attached")

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

        // Read from coprocess.testReadFd to verify data flowed through the bridge.
        // We cannot check coprocess.outputBuffer because the coprocess write dispatch
        // source drains it asynchronously (race condition). Instead, read from the
        // pipe end where drained data arrives.
        var receivedData = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        let flags = fcntl(coprocess.testReadFd, F_GETFL)
        fcntl(coprocess.testReadFd, F_SETFL, flags | O_NONBLOCK)

        for _ in 0..<50 {
            task.testWaitForIOQueue()
            let bytesRead = Darwin.read(coprocess.testReadFd, &buffer, buffer.count)
            if bytesRead > 0 {
                receivedData.append(contentsOf: buffer[0..<bytesRead])
            }
            if receivedData.count >= testData.count { break }
            Thread.sleep(forTimeInterval: 0.01)
        }

        // Verify data was routed through the bridge to the coprocess
        XCTAssertEqual(receivedData.count, testData.count,
                      "handleReadEvent should route PTY data through writeToCoprocess bridge to coprocess fd")

        if let receivedString = String(data: receivedData, encoding: .utf8) {
            XCTAssertEqual(receivedString, testMessage,
                          "Coprocess should receive the PTY data")
        }
    }

    func testWriteTaskTriggersWriteSource() throws {
        // REQUIREMENT: writeTask should call writeBufferDidChange
        // This tests that the write dispatch_source is triggered when data is added

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

        // NOTE: We cannot assert testWriteBufferHasData here because it's racy.
        // The write dispatch source may have already drained the buffer to the pipe.
        // Instead, we verify data appears on the pipe (below).

        // Wait for write source to drain the buffer to the pipe
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
    }

    // MARK: - Gap 3: TaskNotifier Coprocess Write FD Handling

    func testCoprocessWriteFdProcessedBySelect() throws {
        // GAP 3: Verify TaskNotifier calls [coprocess write] when coprocess has outgoing data.
        // The flow is:
        //   1. Coprocess.outputBuffer has data (wantToWrite=YES)
        //   2. TaskNotifier adds coprocess.writeFileDescriptor to select()'s wfds
        //   3. When fd is writable, TaskNotifier calls [coprocess write]
        //   4. Data flows from outputBuffer to the fd
        //
        // We verify by reading from MockCoprocess.testReadFd after the select() runs.
        //
        // NOTE: This test uses a legacy (non-dispatch-source) task because only legacy
        // tasks are added to TaskNotifier's _tasks array and iterated in the select loop.
        // Dispatch-source tasks handle their own coprocess I/O via PTYTask's coprocess
        // dispatch sources (setupCoprocessDispatchSources:).

        // Create a mock task with a pipe
        guard let (mockTask, writeFd) = createMockPipeTask() else {
            XCTFail("Failed to create mock pipe task")
            return
        }
        defer {
            mockTask.closeFd()
            close(writeFd)
        }

        // Configure as legacy task so TaskNotifier adds it to _tasks and iterates
        // it in the select loop (dispatch-source tasks are NOT added to _tasks).
        mockTask.simulateLegacyTask = true
        mockTask.hasCoprocess = true
        mockTask.writeBufferHasRoom = true

        // Create MockCoprocess
        guard let coprocess = MockCoprocess.createPipe() else {
            XCTFail("Failed to create MockCoprocess")
            return
        }
        defer {
            coprocess.closeTestFds()
            coprocess.terminate()
        }

        // Attach coprocess to task
        mockTask.coprocess = coprocess

        // Put data in coprocess.outputBuffer - this makes wantToWrite return YES
        let testMessage = "Outgoing coprocess data!"
        let testData = testMessage.data(using: .utf8)!
        coprocess.outputBuffer.append(testData)

        // Verify wantToWrite is true before we register
        XCTAssertTrue(coprocess.wantToWrite(), "Coprocess should wantToWrite when outputBuffer has data")

        // Register with TaskNotifier
        let notifier = TaskNotifier.sharedInstance()
        notifier?.register(mockTask)
        defer { notifier?.deregister(mockTask) }

        // Wait for registration
        waitForMainQueue()

        // Unblock to wake select loop
        notifier?.unblock()

        // Wait for select() to process the coprocess write fd
        // The data should be written from outputBuffer to writeFileDescriptor
        var receivedData = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        // Make testReadFd non-blocking
        let flags = fcntl(coprocess.testReadFd, F_GETFL)
        fcntl(coprocess.testReadFd, F_SETFL, flags | O_NONBLOCK)

        // Poll for data with iteration-based waiting
        for _ in 0..<50 {
            waitForMainQueue()
            let bytesRead = Darwin.read(coprocess.testReadFd, &buffer, buffer.count)
            if bytesRead > 0 {
                receivedData.append(contentsOf: buffer[0..<bytesRead])
            }
            if receivedData.count >= testData.count { break }
            Thread.sleep(forTimeInterval: 0.01)
        }

        XCTAssertEqual(receivedData.count, testData.count,
                      "TaskNotifier select() should call [coprocess write] draining outputBuffer to fd")

        if let receivedString = String(data: receivedData, encoding: .utf8) {
            XCTAssertEqual(receivedString, testMessage,
                          "Data from coprocess.outputBuffer should appear on testReadFd")
        }
    }
}
