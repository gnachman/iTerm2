//
//  DispatchSourceConcurrencyTests.swift
//  ModernTests
//
//  Regression tests for data races in dispatch source management.
//  These verify that concurrent operations on PTYTaskIOHandler don't crash.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Coprocess Setup Serialization Tests

/// Regression test: setupCoprocessSources must serialize source
/// reference assignments on the ioQueue to prevent data races with event
/// handlers and updateCoprocess*SourceState.
final class DispatchSourceCoprocessSerializationTests: XCTestCase {

    /// Rapid sequential setup/teardown of coprocess sources while the primary
    /// sources are active. Tests that the syncOnIOQueue wrapper properly
    /// serializes reference assignments with event handlers.
    func testRapidCoprocessSetupTeardownCycles() {
        guard let task = PTYTask() else {
            XCTFail("Failed to create PTYTask")
            return
        }

        guard let ptyPipe = createTestPipe() else {
            XCTFail("Failed to create PTY pipe")
            return
        }
        defer { closeTestPipe(ptyPipe) }

        task.testSetFd(ptyPipe.readFd)
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        guard let coprocessPipe = createTestPipe() else {
            XCTFail("Failed to create coprocess pipe")
            task.testTeardownDispatchSourcesForTesting()
            return
        }
        defer { closeTestPipe(coprocessPipe) }

        // Rapid setup/teardown cycles — each must properly cancel old sources
        // and assign new references atomically on ioQueue.
        for _ in 0..<20 {
            task.testSetupCoprocessSources(withReadFd: coprocessPipe.readFd,
                                           writeFd: coprocessPipe.writeFd)
            task.testWaitForIOQueue()

            XCTAssertTrue(task.testHasCoprocessReadSource(),
                          "Coprocess read source should exist after setup")
            XCTAssertTrue(task.testHasCoprocessWriteSource(),
                          "Coprocess write source should exist after setup")

            task.testTeardownCoprocessSources()
            task.testWaitForIOQueue()

            XCTAssertFalse(task.testHasCoprocessReadSource(),
                           "Coprocess read source should be nil after teardown")
            XCTAssertFalse(task.testHasCoprocessWriteSource(),
                           "Coprocess write source should be nil after teardown")
        }

        task.testTeardownDispatchSourcesForTesting()
    }

}

// MARK: - Concurrent Teardown + Update Tests

/// Regression test: teardown() concurrent with
/// updateReadSourceState/updateWriteSourceState must not crash.
/// Before the centralized helpers, source references were read from the
/// calling queue and then mutated on ioQueue, creating a TOCTOU race.
final class DispatchSourceConcurrentTeardownUpdateTests: XCTestCase {

    func testConcurrentTeardownAndUpdateDoesNotCrash() {
        for _ in 0..<5 {
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
            task.testIoAllowedOverride = NSNumber(value: true)
            task.paused = false

            task.testSetupDispatchSourcesForTesting(withPid: getpid())
            task.testWaitForIOQueue()

            let group = DispatchGroup()

            // Spam update calls from multiple threads (uses ioQueue.async internally)
            for _ in 0..<10 {
                group.enter()
                DispatchQueue.global().async {
                    task.perform(NSSelectorFromString("updateReadSourceState"))
                    task.perform(NSSelectorFromString("updateWriteSourceState"))
                    group.leave()
                }
            }

            // Concurrently tear down (uses ioQueue.sync internally)
            group.enter()
            DispatchQueue.global().async {
                task.testTeardownDispatchSourcesForTesting()
                group.leave()
            }

            let result = group.wait(timeout: .now() + 5.0)
            XCTAssertEqual(result, .success, "Concurrent teardown+update timed out")

            XCTAssertFalse(task.testHasReadSource(),
                           "Read source should be nil after teardown")
            XCTAssertFalse(task.testHasWriteSource(),
                           "Write source should be nil after teardown")
        }
    }

    func testRapidSetupTeardownCyclesDoNotCrash() {
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
        task.testIoAllowedOverride = NSNumber(value: true)

        // Rapid setup/teardown cycles from the same thread
        for _ in 0..<20 {
            task.testSetupDispatchSourcesForTesting(withPid: getpid())
            task.testWaitForIOQueue()
            task.paused = true
            task.paused = false
            task.testTeardownDispatchSourcesForTesting()
        }

        XCTAssertFalse(task.testHasReadSource(),
                       "Read source should be nil after final teardown")
        XCTAssertFalse(task.testHasWriteSource(),
                       "Write source should be nil after final teardown")
    }
}
