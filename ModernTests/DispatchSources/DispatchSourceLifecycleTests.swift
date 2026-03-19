//
//  DispatchSourceLifecycleTests.swift
//  ModernTests
//
//  Tests for dispatch source setup, teardown, and idempotent operations.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Dispatch Source Lifecycle Tests

/// Tests for dispatch source setup and teardown
final class DispatchSourceLifecycleTests: XCTestCase {

    func testSetupCreatesSourcesWhenFdValid() throws {
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

        XCTAssertFalse(task.testHasReadSource(), "No read source before setup")
        XCTAssertFalse(task.testHasWriteSource(), "No write source before setup")

        task.testSetupDispatchSourcesForTesting(withPid: getpid())
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testHasReadSource(), "Read source should be created")
        XCTAssertTrue(task.testHasWriteSource(), "Write source should be created")

        // Write source should be suspended (empty buffer)
        XCTAssertTrue(task.testIsWriteSourceSuspended(), "Write source should start suspended (empty buffer)")

        // Read source suspends when paused (proc source handles EOF detection)
        task.paused = true
        task.testWaitForIOQueue()
        XCTAssertTrue(task.testIsReadSourceSuspended(), "Read source should be suspended when paused")

        task.testTeardownDispatchSourcesForTesting()
    }

    func testTeardownCleansUpSources() throws {
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

        XCTAssertTrue(task.testHasReadSource(), "Read source should exist after setup")
        XCTAssertTrue(task.testHasWriteSource(), "Write source should exist after setup")

        task.testTeardownDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        XCTAssertFalse(task.testHasReadSource(), "Read source should be nil after teardown")
        XCTAssertFalse(task.testHasWriteSource(), "Write source should be nil after teardown")
    }

    func testUpdateMethodsExist() {
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
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        XCTAssertFalse(task.testHasReadSource(), "No read source should exist before setup")
        XCTAssertFalse(task.testHasWriteSource(), "No write source should exist before setup")

        let selector = NSSelectorFromString("teardownDispatchSources")
        if task.responds(to: selector) {
            task.perform(selector)
        }

        XCTAssertFalse(task.testHasReadSource(), "No read source after teardown on fresh task")
        XCTAssertFalse(task.testHasWriteSource(), "No write source after teardown on fresh task")
    }

    func testMultipleTeardownCallsSafe() {
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        let selector = NSSelectorFromString("teardownDispatchSources")
        guard task.responds(to: selector) else {
            XCTFail("PTYTask should respond to teardownDispatchSources")
            return
        }

        for i in 0..<5 {
            task.perform(selector)
            XCTAssertFalse(task.testHasReadSource(), "No read source after teardown \(i)")
            XCTAssertFalse(task.testHasWriteSource(), "No write source after teardown \(i)")
        }
    }

    func testTeardownWithSuspendedReadSourceWhilePaused() throws {
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
        task.testSetupDispatchSourcesForTesting(withPid: getpid())
        task.testWaitForIOQueue()

        // Read source suspends when paused (proc source handles EOF detection)
        task.paused = true
        task.testWaitForIOQueue()
        XCTAssertTrue(task.testIsReadSourceSuspended(), "Read source should be suspended when paused")

        // Teardown with suspended read source while paused - should NOT crash
        task.testTeardownDispatchSourcesForTesting()
        XCTAssertFalse(task.testHasReadSource(), "Read source should be nil after teardown")
    }

    func testTeardownWithSuspendedWriteSource() throws {
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

        XCTAssertTrue(task.testIsWriteSourceSuspended(), "Write source should be suspended with empty buffer")

        // Teardown with suspended write source - should NOT crash
        task.testTeardownDispatchSourcesForTesting()
        XCTAssertFalse(task.testHasWriteSource(), "Write source should be nil after teardown")
    }

    func testTeardownWhilePausedWithBothSourcesSuspended() throws {
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
        task.testSetupDispatchSourcesForTesting(withPid: getpid())
        task.testWaitForIOQueue()

        task.paused = true
        task.testWaitForIOQueue()

        // Both sources suspend when paused (proc source handles EOF detection)
        XCTAssertTrue(task.testIsReadSourceSuspended(), "Read source should be suspended when paused")
        XCTAssertTrue(task.testIsWriteSourceSuspended(), "Write source should be suspended (empty buffer)")

        // Teardown with both sources suspended - should NOT crash
        task.testTeardownDispatchSourcesForTesting()
        XCTAssertFalse(task.testHasReadSource(), "Read source should be nil after teardown")
        XCTAssertFalse(task.testHasWriteSource(), "Write source should be nil after teardown")
    }

    /// Regression test: closeFileDescriptorAndDeregisterIfPossible must tear down
    /// dispatch sources before the job manager closes the fd. Otherwise the sources
    /// remain active on a potentially reused descriptor.
    func testCloseFileDescriptorTearsDownSourcesFirst() throws {
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let pipe = createTestPipe() else {
            XCTFail("Failed to create test pipe")
            return
        }
        defer { closeTestPipe(pipe) }

        // testSetFd creates an iTermLegacyJobManager, so set the mock AFTER
        task.testSetFd(pipe.readFd)
        let mockJobManager = MockJobManager()
        mockJobManager.fd = pipe.readFd
        task.testSetJobManager(mockJobManager)
        task.testIoAllowedOverride = NSNumber(value: true)

        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testHasReadSource(), "Read source should exist after setup")
        XCTAssertTrue(task.testHasWriteSource(), "Write source should exist after setup")

        // This must tear down sources before closing the fd
        task.closeFileDescriptorAndDeregisterIfPossible()

        XCTAssertFalse(task.testHasReadSource(),
                       "Read source should be torn down after closeFileDescriptorAndDeregisterIfPossible")
        XCTAssertFalse(task.testHasWriteSource(),
                       "Write source should be torn down after closeFileDescriptorAndDeregisterIfPossible")
        XCTAssertEqual(mockJobManager.closeFileDescriptorCallCount, 1,
                       "Job manager closeFileDescriptor should have been called")
    }

    /// Regression test: When registration is dispatched async to the main queue,
    /// the task may be stopped (fd closed) before didRegister runs. didRegister
    /// must guard against fd < 0 and skip ioHandler creation.
    func testDidRegisterSkipsIOHandlerWhenFdClosed() throws {
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        // A fresh PTYTask has fd = -1 (no job manager fd yet).
        // This simulates the race where the task is stopped before didRegister runs.
        XCTAssertEqual(task.fd, -1, "Fresh task should have fd = -1")

        // Enable the per-PTY dispatch sources setting for this test
        let key = "UsePerPTYDispatchSources"
        let oldValue = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            if let old = oldValue {
                UserDefaults.standard.set(old, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }

        XCTAssertTrue(iTermAdvancedSettingsModel.usePerPTYDispatchSources(),
                      "Setting should be enabled for this test")

        // Call didRegister — should NOT crash and should NOT create an ioHandler.
        // didRegister is declared on the iTermTask protocol; use perform() to call it.
        task.perform(NSSelectorFromString("didRegister"))

        // No sources should exist because didRegister guarded against fd < 0
        XCTAssertFalse(task.testHasReadSource(),
                       "No read source should be created when fd is closed at registration time")
        XCTAssertFalse(task.testHasWriteSource(),
                       "No write source should be created when fd is closed at registration time")
    }
}
