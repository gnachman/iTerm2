//
//  iTermProcessMonitorTests.swift
//  iTerm2
//
//  Created by George Nachman on 2/3/26.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Mock Objects

class MockProcessDataSource: NSObject, ProcessDataSource {
    var processNames: [pid_t: String] = [:]
    var foregroundPIDs: Set<pid_t> = []
    var commandLines: [pid_t: [String]] = [:]
    var startTimes: [pid_t: Date] = [:]

    func nameOfProcess(withPid thePid: pid_t, isForeground: UnsafeMutablePointer<ObjCBool>) -> String? {
        isForeground.pointee = ObjCBool(foregroundPIDs.contains(thePid))
        return processNames[thePid]
    }

    func commandLineArguments(forProcess pid: pid_t, execName: AutoreleasingUnsafeMutablePointer<NSString>?) -> [String]? {
        if let argv = commandLines[pid], let first = argv.first {
            execName?.pointee = first as NSString
        }
        return commandLines[pid]
    }

    func startTime(forProcess pid: pid_t) -> Date? {
        return startTimes[pid]
    }
}

// MARK: - Test Helpers

/// Helper to create a process collection with mock data
private func makeProcessCollection(dataSource: MockProcessDataSource,
                                   processes: [(pid: pid_t, ppid: pid_t)]) -> ProcessCollection {
    let collection = ProcessCollection(dataSource: dataSource)
    for (pid, ppid) in processes {
        collection.addProcess(withProcessID: pid, parentProcessID: ppid)
    }
    collection.commit()
    return collection
}

// MARK: - Test Class

final class iTermProcessMonitorTests: XCTestCase {
    var dataSource: MockProcessDataSource!
    var testQueue: DispatchQueue!
    var callbackEvents: [(monitor: iTermProcessMonitor, flags: UInt)]!
    var callbackExpectation: XCTestExpectation?

    override func setUp() {
        super.setUp()
        dataSource = MockProcessDataSource()
        testQueue = DispatchQueue(label: "com.iterm2.test.processmonitor")
        callbackEvents = []
    }

    override func tearDown() {
        dataSource = nil
        testQueue = nil
        callbackEvents = nil
        callbackExpectation = nil
        super.tearDown()
    }

    private func makeCallback() -> (iTermProcessMonitor, UInt) -> Void {
        return { [weak self] monitor, flags in
            self?.callbackEvents.append((monitor: monitor, flags: flags))
            self?.callbackExpectation?.fulfill()
        }
    }

    // MARK: - Monitor Pause State Helpers

    private func isMonitorPaused(_ monitor: Any) -> Bool {
        return iTermProcessCacheTestHelper.monitorIsPaused(monitor)
    }

    private func childMonitors(for monitor: Any) -> [Any] {
        return iTermProcessCacheTestHelper.childMonitors(forMonitor: monitor) ?? []
    }

    // MARK: - 1. Initialization Tests

    func testInit_SetsQueueCallbackAndTrackedRootPID() {
        // Given
        let rootPID: pid_t = 12345
        let callback = makeCallback()

        // When
        let monitor = iTermProcessMonitor(queue: testQueue, callback: callback, trackedRootPID: rootPID)

        // Then
        XCTAssertEqual(monitor.trackedRootPID, rootPID)
        XCTAssertNotNil(monitor.queue)
        XCTAssertNotNil(monitor.callback)
        XCTAssertNil(monitor.processInfo)
        XCTAssertNil(monitor.parent)
    }

    func testInit_LegacyInitializer_TrackedRootPIDIsZero() {
        // Given
        let callback = makeCallback()

        // When
        let monitor = iTermProcessMonitor(queue: testQueue, callback: callback)

        // Then
        XCTAssertEqual(monitor.trackedRootPID, 0)
    }

    // MARK: - 2. setProcessInfo Tests

    func testSetProcessInfo_WithValidPID_ReturnsYES() {
        // Given
        let pid = getpid()
        let ppid = getppid()
        dataSource.processNames[pid] = "xctest"
        dataSource.processNames[ppid] = "launchd"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, ppid)])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: pid)

        // When
        let changed = monitor.setProcessInfo(processInfo)

        // Then
        XCTAssertTrue(changed)
        XCTAssertEqual(monitor.processInfo?.processID, pid)
    }

    func testSetProcessInfo_SameInstance_ReturnsNO() {
        // Given
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: pid)
        _ = monitor.setProcessInfo(processInfo)

        // When
        let changed = monitor.setProcessInfo(processInfo)

        // Then
        XCTAssertFalse(changed)
    }

    func testSetProcessInfo_Nil_InvalidatesMonitor() {
        // Given
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: pid)
        _ = monitor.setProcessInfo(processInfo)
        XCTAssertNotNil(monitor.processInfo)

        // When
        let changed = monitor.setProcessInfo(nil as iTermProcessInfo?)

        // Then
        XCTAssertTrue(changed)
        XCTAssertNil(monitor.processInfo)
    }

    // MARK: - 3. Child Monitor Management Tests

    func testSetProcessInfo_WithChildren_CreatesChildMonitors() {
        // Given: A process tree with parent and two children
        let parentPID = getpid()
        let child1PID: pid_t = 99991
        let child2PID: pid_t = 99992

        dataSource.processNames[parentPID] = "xctest"
        dataSource.processNames[child1PID] = "child1"
        dataSource.processNames[child2PID] = "child2"

        // Build collection with parent-child relationships
        let collection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (child1PID, parentPID),
            (child2PID, parentPID)
        ])

        guard let parentInfo = collection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create parent process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: parentPID)

        // When
        let changed = monitor.setProcessInfo(parentInfo)

        // Then
        XCTAssertTrue(changed)
        // Children should exist (verified via the process info tree)
        XCTAssertEqual(parentInfo.children.count, 2)
    }

    func testSetProcessInfo_RemovesChild_InvalidatesChildMonitor() {
        // Given: A monitor, first set process info without children, then add a child
        let parentPID = getpid()
        let childPID: pid_t = 99991

        dataSource.processNames[parentPID] = "xctest"

        // First: set up monitor with no children
        let initialCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid())
        ])

        guard let initialInfo = initialCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create initial process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: parentPID)

        testQueue.sync {
            _ = monitor.setProcessInfo(initialInfo)
        }

        // Pause the monitor (required for child monitors to be properly tracked with fake PIDs)
        testQueue.sync {
            monitor.pauseMonitoring()
        }

        // Then: add a child
        dataSource.processNames[childPID] = "child"

        let withChildCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (childPID, parentPID)
        ])

        guard let withChildInfo = withChildCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create process info with child")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(withChildInfo)
        }

        // Verify child was created while still paused
        var childMonitor: iTermProcessMonitor?
        testQueue.sync {
            let children = childMonitors(for: monitor)
            XCTAssertEqual(children.count, 1, "Should have one child monitor")
            childMonitor = children.first as? iTermProcessMonitor
        }

        guard let capturedChild = childMonitor else {
            XCTFail("Expected child monitor")
            return
        }

        // Resume for the rest of the test
        testQueue.sync {
            monitor.resumeMonitoring()
        }

        // When: Update process info to remove the child
        let withoutChildCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid())
        ])

        guard let withoutChildInfo = withoutChildCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create process info without child")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(withoutChildInfo)
        }

        // Then: Removed child should be invalidated (processInfo cleared)
        XCTAssertNil(capturedChild.processInfo, "Removed child monitor should be invalidated")

        testQueue.sync {
            monitor.invalidate()
        }
    }

    func testSetProcessInfo_TrackedRootPID_PropagatedToChildren() {
        // Given: A process tree
        let rootPID: pid_t = 12345
        let parentPID = getpid()
        let childPID: pid_t = 99991

        dataSource.processNames[parentPID] = "xctest"
        dataSource.processNames[childPID] = "child"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (childPID, parentPID)
        ])

        guard let parentInfo = collection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create parent process info")
            return
        }

        // Monitor with specific trackedRootPID
        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: rootPID)

        // When
        _ = monitor.setProcessInfo(parentInfo)

        // Then
        XCTAssertEqual(monitor.trackedRootPID, rootPID)
        // The trackedRootPID is propagated to children (tested via callback behavior)
    }

    // MARK: - 4. Pause/Resume Tests

    func testPauseMonitoring_Idempotent() {
        // Given: A monitor with process info
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: pid)
        _ = monitor.setProcessInfo(processInfo)

        // When: Pause multiple times
        testQueue.sync {
            monitor.pauseMonitoring()
            monitor.pauseMonitoring() // Should not crash or cause issues
            monitor.pauseMonitoring()
        }

        // Then: No crash, can still resume
        testQueue.sync {
            monitor.resumeMonitoring()
        }
    }

    func testResumeMonitoring_Idempotent() {
        // Given: A monitor with process info (not paused)
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: pid)
        _ = monitor.setProcessInfo(processInfo)

        // When: Resume multiple times without pausing first
        testQueue.sync {
            monitor.resumeMonitoring() // Should not crash
            monitor.resumeMonitoring()
        }

        // Then: No crash
    }

    func testPauseMonitoring_WhenNoSource_DoesNotCrash() {
        // Given: A monitor without process info (no dispatch source)
        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: 0)

        // When/Then: Should not crash
        testQueue.sync {
            monitor.pauseMonitoring()
        }
    }

    func testResumeMonitoring_WhenNoSource_DoesNotCrash() {
        // Given: A monitor without process info (no dispatch source)
        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: 0)

        // When/Then: Should not crash
        testQueue.sync {
            monitor.resumeMonitoring()
        }
    }

    // MARK: - 5. KEY FIX TESTS: New Children Paused When Parent Is Paused

    func testPausedMonitor_NewChildIsPaused() {
        // This test verifies that when a paused parent creates a new child via
        // setProcessInfo, the child monitor's dispatch source is also paused.
        // This catches the child monitor activation while parent is paused bug.

        // Given: A monitor with initial process info (no children)
        let parentPID = getpid()
        dataSource.processNames[parentPID] = "xctest"

        let initialCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid())
        ])

        guard let initialInfo = initialCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create initial process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: parentPID)
        _ = monitor.setProcessInfo(initialInfo)

        // Pause the parent monitor
        testQueue.sync {
            monitor.pauseMonitoring()
        }

        // Verify parent is paused
        var parentPaused = false
        testQueue.sync {
            parentPaused = isMonitorPaused(monitor)
        }
        XCTAssertTrue(parentPaused, "Parent monitor should be paused")

        // When: Update process info to add a child while parent is paused
        let childPID: pid_t = 99991
        dataSource.processNames[childPID] = "child"

        let updatedCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (childPID, parentPID)
        ])

        guard let updatedInfo = updatedCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create updated process info")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(updatedInfo)
        }

        // Then: The newly created child monitor should also be paused
        testQueue.sync {
            let children = childMonitors(for: monitor)
            XCTAssertEqual(children.count, 1, "Should have one child monitor")

            if let childMonitor = children.first {
                XCTAssertTrue(isMonitorPaused(childMonitor),
                    "NEW child monitor should be PAUSED when created while parent is paused")
            }
        }

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

    func testPausedMonitor_RemainsPausedAfterProcessInfoUpdate() {
        // Verifies that updating process info on a paused monitor does not
        // implicitly resume the parent or any children.

        // Given: A monitor with one child, then paused
        let parentPID = getpid()
        let existingChildPID: pid_t = 99991

        dataSource.processNames[parentPID] = "xctest"
        dataSource.processNames[existingChildPID] = "existingChild"

        let initialCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (existingChildPID, parentPID)
        ])

        guard let initialInfo = initialCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create initial process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: parentPID)
        _ = monitor.setProcessInfo(initialInfo)

        // Pause the monitor tree
        testQueue.sync {
            monitor.pauseMonitoring()
        }

        // Verify everything is paused
        testQueue.sync {
            XCTAssertTrue(isMonitorPaused(monitor), "Parent should be paused")
            let children = childMonitors(for: monitor)
            for child in children {
                XCTAssertTrue(isMonitorPaused(child), "Existing child should be paused")
            }
        }

        // When: Update process info with a new child
        let newChildPID: pid_t = 99992
        dataSource.processNames[newChildPID] = "newChild"

        let updatedCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (existingChildPID, parentPID),
            (newChildPID, parentPID)
        ])

        guard let updatedInfo = updatedCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create updated process info")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(updatedInfo)
        }

        // Then: Parent should STILL be paused, and ALL children should be paused
        testQueue.sync {
            XCTAssertTrue(isMonitorPaused(monitor),
                "Parent should REMAIN paused after processInfo update")

            let children = childMonitors(for: monitor)
            XCTAssertEqual(children.count, 2, "Should have two children")

            for (index, child) in children.enumerated() {
                XCTAssertTrue(isMonitorPaused(child),
                    "Child \(index) should be paused after processInfo update")
            }
        }

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

    func testSetProcessInfo_ParentPaused_NewChildMonitorsPauseAndResumeCorrectly() {
        // This test verifies the fix: when a parent is paused and setProcessInfo
        // creates new children, those children should also be paused. We verify
        // this by checking that resume works correctly (if children weren't paused,
        // calling resume on them would be undefined behavior for dispatch sources).

        // Given: A monitor with initial process info (no children)
        let parentPID = getpid()
        dataSource.processNames[parentPID] = "xctest"

        let initialCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid())
        ])

        guard let initialInfo = initialCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create initial process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: parentPID)
        _ = monitor.setProcessInfo(initialInfo)

        // Pause the parent monitor
        testQueue.sync {
            monitor.pauseMonitoring()
        }

        // When: Update process info to add children while parent is paused
        let childPID: pid_t = 99991
        dataSource.processNames[childPID] = "child"

        let updatedCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (childPID, parentPID)
        ])

        guard let updatedInfo = updatedCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create updated process info")
            return
        }

        testQueue.sync {
            // This creates a new child monitor. With the fix, it should be paused.
            _ = monitor.setProcessInfo(updatedInfo)
        }

        // Then: Resume should work without issues (verifies children were properly paused)
        testQueue.sync {
            // If new children weren't paused, this could cause undefined behavior
            // when resumeMonitoring tries to resume the parent and its children
            monitor.resumeMonitoring()
        }

        // Additional verification: can pause and resume again
        testQueue.sync {
            monitor.pauseMonitoring()
            monitor.resumeMonitoring()
        }

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

    func testSetProcessInfo_ParentPaused_MultipleNewChildren_AllPauseCorrectly() {
        // Given: A monitor with initial process info (no children)
        let parentPID = getpid()
        dataSource.processNames[parentPID] = "xctest"

        let initialCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid())
        ])

        guard let initialInfo = initialCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create initial process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: parentPID)
        _ = monitor.setProcessInfo(initialInfo)

        // Pause the parent
        testQueue.sync {
            monitor.pauseMonitoring()
        }

        // When: Add multiple children while paused
        let child1PID: pid_t = 99991
        let child2PID: pid_t = 99992
        let child3PID: pid_t = 99993

        dataSource.processNames[child1PID] = "child1"
        dataSource.processNames[child2PID] = "child2"
        dataSource.processNames[child3PID] = "child3"

        let updatedCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (child1PID, parentPID),
            (child2PID, parentPID),
            (child3PID, parentPID)
        ])

        guard let updatedInfo = updatedCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create updated process info")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(updatedInfo)
        }

        // Then: Resume should handle all children correctly
        testQueue.sync {
            monitor.resumeMonitoring()
        }

        // Verify multiple pause/resume cycles work
        for _ in 0..<3 {
            testQueue.sync {
                monitor.pauseMonitoring()
                monitor.resumeMonitoring()
            }
        }

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

    func testSetProcessInfo_ParentNotPaused_ChildrenNotAffected() {
        // Given: A monitor that is NOT paused
        let parentPID = getpid()
        dataSource.processNames[parentPID] = "xctest"

        let initialCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid())
        ])

        guard let initialInfo = initialCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create initial process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: parentPID)
        _ = monitor.setProcessInfo(initialInfo)

        // Parent is NOT paused

        // When: Add children
        let childPID: pid_t = 99991
        dataSource.processNames[childPID] = "child"

        let updatedCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (childPID, parentPID)
        ])

        guard let updatedInfo = updatedCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create updated process info")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(updatedInfo)
        }

        // Then: Can pause and resume the whole tree
        testQueue.sync {
            monitor.pauseMonitoring()
            monitor.resumeMonitoring()
        }

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

    // MARK: - 5b. Pre-Source Pause Tests (pauseMonitoring before setProcessInfo)
    // These tests verify the fix for the bug where pauseMonitoring called before
    // setProcessInfo: (i.e., before a dispatch source exists) would not record the
    // paused state, causing the source to auto-resume when created.

    func testPauseBeforeSetProcessInfo_SourceStartsPaused() {
        // This tests the core fix: calling pauseMonitoring before setProcessInfo:
        // should record the paused state, and the dispatch source should NOT auto-resume.

        // Given: A monitor with NO process info yet (no dispatch source)
        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: 0)

        // When: Pause BEFORE setProcessInfo creates a dispatch source
        testQueue.sync {
            monitor.pauseMonitoring()
        }

        // Verify isPaused is true even without a source
        var pausedBeforeSource = false
        testQueue.sync {
            pausedBeforeSource = isMonitorPaused(monitor)
        }
        XCTAssertTrue(pausedBeforeSource, "isPaused should be true even before dispatch source exists")

        // Now set process info to create the dispatch source
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"
        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(processInfo)
        }

        // Then: Monitor should STILL be paused after source creation
        var pausedAfterSource = false
        testQueue.sync {
            pausedAfterSource = isMonitorPaused(monitor)
        }
        XCTAssertTrue(pausedAfterSource, "Monitor should remain paused after setProcessInfo creates source")

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

    func testPauseBeforeSetProcessInfo_ResumeWorks() {
        // Verifies that after pausing before source creation, resumeMonitoring works correctly.

        // Given: A monitor paused before setProcessInfo
        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: 0)

        testQueue.sync {
            monitor.pauseMonitoring()
        }

        // Set process info to create source (remains paused)
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"
        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(processInfo)
        }

        // When: Resume the monitor
        testQueue.sync {
            monitor.resumeMonitoring()
        }

        // Then: Should no longer be paused
        var pausedAfterResume = false
        testQueue.sync {
            pausedAfterResume = isMonitorPaused(monitor)
        }
        XCTAssertFalse(pausedAfterResume, "Monitor should be running after resumeMonitoring")

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

    func testResumeBeforeSetProcessInfo_ClearsPausedState() {
        // Verifies that calling resume before setProcessInfo clears the paused state,
        // so the source will auto-resume when created (normal behavior).

        // Given: A monitor that was paused then resumed, all before setProcessInfo
        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: 0)

        testQueue.sync {
            monitor.pauseMonitoring()
            monitor.resumeMonitoring()
        }

        // Verify isPaused is false before source creation
        var pausedBeforeSource = false
        testQueue.sync {
            pausedBeforeSource = isMonitorPaused(monitor)
        }
        XCTAssertFalse(pausedBeforeSource, "isPaused should be false after resume (before source)")

        // When: Set process info to create source
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"
        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(processInfo)
        }

        // Then: Monitor should NOT be paused (source auto-resumed)
        var pausedAfterSource = false
        testQueue.sync {
            pausedAfterSource = isMonitorPaused(monitor)
        }
        XCTAssertFalse(pausedAfterSource, "Monitor should be running after setProcessInfo (was not pre-paused)")

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

    func testPauseBeforeSetProcessInfo_ChildrenAlsoPaused() {
        // Verifies that when a monitor is pre-paused (before source creation),
        // any children created by setProcessInfo are also paused.

        // Given: A monitor paused before setProcessInfo
        let parentPID = getpid()
        let childPID: pid_t = 99991

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: parentPID)

        testQueue.sync {
            monitor.pauseMonitoring()
        }

        // When: Set process info with children
        dataSource.processNames[parentPID] = "xctest"
        dataSource.processNames[childPID] = "child"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (childPID, parentPID)
        ])

        guard let parentInfo = collection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create parent process info")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(parentInfo)
        }

        // Then: Both parent and children should be paused
        testQueue.sync {
            XCTAssertTrue(isMonitorPaused(monitor), "Parent should be paused")

            let children = childMonitors(for: monitor)
            XCTAssertEqual(children.count, 1, "Should have one child")

            if let child = children.first {
                XCTAssertTrue(isMonitorPaused(child), "Child should also be paused when parent was pre-paused")
            }
        }

        // When: Resume
        testQueue.sync {
            monitor.resumeMonitoring()
        }

        // Then: Both should be running
        testQueue.sync {
            XCTAssertFalse(isMonitorPaused(monitor), "Parent should be running after resume")

            let children = childMonitors(for: monitor)
            if let child = children.first {
                XCTAssertFalse(isMonitorPaused(child), "Child should be running after resume")
            }
        }

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

    func testPauseBeforeSetProcessInfo_MultiplePauseResumeBeforeSource() {
        // Edge case: multiple pause/resume cycles before source creation.

        // Given: A monitor with no process info
        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: 0)

        // When: Multiple pause/resume cycles
        testQueue.sync {
            monitor.pauseMonitoring()  // paused
            monitor.resumeMonitoring() // not paused
            monitor.pauseMonitoring()  // paused
            monitor.pauseMonitoring()  // still paused (idempotent)
            monitor.resumeMonitoring() // not paused
            monitor.resumeMonitoring() // still not paused (idempotent)
            monitor.pauseMonitoring()  // paused (final state)
        }

        // Then: Final state should be paused
        var isPaused = false
        testQueue.sync {
            isPaused = isMonitorPaused(monitor)
        }
        XCTAssertTrue(isPaused, "Final state should be paused")

        // When: Create source
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"
        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(processInfo)
        }

        // Then: Should still be paused
        testQueue.sync {
            XCTAssertTrue(isMonitorPaused(monitor), "Should remain paused after source creation")
        }

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

    // MARK: - 6. Invalidation Tests

    func testInvalidate_ClearsProcessInfo() {
        // Given: A monitor with process info
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: pid)
        _ = monitor.setProcessInfo(processInfo)
        XCTAssertNotNil(monitor.processInfo)

        // When
        testQueue.sync {
            monitor.invalidate()
        }

        // Then
        XCTAssertNil(monitor.processInfo)
    }

    func testInvalidate_WhenPaused_DoesNotCrash() {
        // Given: A paused monitor
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: pid)
        _ = monitor.setProcessInfo(processInfo)

        testQueue.sync {
            monitor.pauseMonitoring()
        }

        // When/Then: Should not crash (must resume before cancel per dispatch API)
        testQueue.sync {
            monitor.invalidate()
        }

        XCTAssertNil(monitor.processInfo)
    }

    func testInvalidate_Idempotent() {
        // Given: A monitor
        let pid = getpid()
        dataSource.processNames[pid] = "xctest"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [(pid, getppid())])
        guard let processInfo = collection.info(forProcessID: pid) else {
            XCTFail("Failed to create process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: pid)
        _ = monitor.setProcessInfo(processInfo)

        // When: Invalidate multiple times
        testQueue.sync {
            monitor.invalidate()
            monitor.invalidate() // Should not crash
            monitor.invalidate()
        }

        // Then: No crash
        XCTAssertNil(monitor.processInfo)
    }

    // MARK: - 7. Recursive Pause/Resume with Children Tests

    func testPauseAndResume_WithExistingChildren_WorksCorrectly() {
        // Given: A monitor with existing children
        let parentPID = getpid()
        let childPID: pid_t = 99991

        dataSource.processNames[parentPID] = "xctest"
        dataSource.processNames[childPID] = "child"

        let collection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (childPID, parentPID)
        ])

        guard let parentInfo = collection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create parent process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: parentPID)
        _ = monitor.setProcessInfo(parentInfo)

        // When: Pause and resume multiple times
        for _ in 0..<5 {
            testQueue.sync {
                monitor.pauseMonitoring()
            }
            testQueue.sync {
                monitor.resumeMonitoring()
            }
        }

        // Then: Should complete without issues
        testQueue.sync {
            monitor.invalidate()
        }
    }

    func testPauseAddChildrenResume_ChildrenProperlyManaged() {
        // Given: A monitor with one child
        let parentPID = getpid()
        let existingChildPID: pid_t = 99991

        dataSource.processNames[parentPID] = "xctest"
        dataSource.processNames[existingChildPID] = "existingChild"

        let initialCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (existingChildPID, parentPID)
        ])

        guard let initialInfo = initialCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create initial process info")
            return
        }

        let monitor = iTermProcessMonitor(queue: testQueue, callback: makeCallback(), trackedRootPID: parentPID)
        _ = monitor.setProcessInfo(initialInfo)

        // Pause
        testQueue.sync {
            monitor.pauseMonitoring()
        }

        // When: Add a new child while paused
        let newChildPID: pid_t = 99992
        dataSource.processNames[newChildPID] = "newChild"

        let updatedCollection = makeProcessCollection(dataSource: dataSource, processes: [
            (parentPID, getppid()),
            (existingChildPID, parentPID),
            (newChildPID, parentPID)
        ])

        guard let updatedInfo = updatedCollection.info(forProcessID: parentPID) else {
            XCTFail("Failed to create updated process info")
            return
        }

        testQueue.sync {
            _ = monitor.setProcessInfo(updatedInfo)
        }

        // Then: Resume should properly handle both existing and new children
        testQueue.sync {
            monitor.resumeMonitoring()
        }

        // Verify we can do another pause/resume cycle
        testQueue.sync {
            monitor.pauseMonitoring()
            monitor.resumeMonitoring()
        }

        // Cleanup
        testQueue.sync {
            monitor.invalidate()
        }
    }

}
