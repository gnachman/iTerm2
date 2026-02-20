//
//  DispatchSourceCoprocessTests.swift
//  ModernTests
//
//  Tests for coprocess dispatch source lifecycle: setup, teardown,
//  suspend/resume state, and interaction with primary source teardown.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Coprocess Dispatch Source Tests

/// Tests for coprocess dispatch source setup, teardown, and state transitions.
final class DispatchSourceCoprocessTests: XCTestCase {

    var task: PTYTask!
    /// Primary PTY pipe — needed for testSetupDispatchSourcesForTesting.
    var ptyPipe: (readFd: Int32, writeFd: Int32)!
    /// Coprocess pipe — used as the coprocess read/write fds.
    var coprocessPipe: (readFd: Int32, writeFd: Int32)!

    override func setUp() {
        super.setUp()
        task = PTYTask()

        ptyPipe = createTestPipe()
        XCTAssertNotNil(ptyPipe, "Failed to create PTY pipe")

        coprocessPipe = createTestPipe()
        XCTAssertNotNil(coprocessPipe, "Failed to create coprocess pipe")

        task.testSetFd(ptyPipe.readFd)
        task.testSetupDispatchSourcesForTesting()
        task.testWaitForIOQueue()
    }

    override func tearDown() {
        task.testTeardownDispatchSourcesForTesting()
        if ptyPipe != nil { closeTestPipe(ptyPipe) }
        if coprocessPipe != nil { closeTestPipe(coprocessPipe) }
        task = nil
        super.tearDown()
    }

    // MARK: - Setup

    func testSetupCoprocessSourcesCreatesSources() {
        XCTAssertFalse(task.testHasCoprocessReadSource(), "No coprocess read source before setup")
        XCTAssertFalse(task.testHasCoprocessWriteSource(), "No coprocess write source before setup")

        task.testSetupCoprocessSources(withReadFd: coprocessPipe.readFd, writeFd: coprocessPipe.writeFd)
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testHasCoprocessReadSource(), "Coprocess read source should exist after setup")
        XCTAssertTrue(task.testHasCoprocessWriteSource(), "Coprocess write source should exist after setup")
    }

    func testCoprocessSourcesStartSuspended() {
        task.testSetupCoprocessSources(withReadFd: coprocessPipe.readFd, writeFd: coprocessPipe.writeFd)
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testIsCoprocessReadSourceSuspended(),
                      "Coprocess read source should start suspended")
        XCTAssertTrue(task.testIsCoprocessWriteSourceSuspended(),
                      "Coprocess write source should start suspended")
    }

    // MARK: - Teardown

    func testTeardownCoprocessSourcesCleansUp() {
        task.testSetupCoprocessSources(withReadFd: coprocessPipe.readFd, writeFd: coprocessPipe.writeFd)
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testHasCoprocessReadSource(), "Coprocess read source should exist")
        XCTAssertTrue(task.testHasCoprocessWriteSource(), "Coprocess write source should exist")

        task.testTeardownCoprocessSources()
        task.testWaitForIOQueue()

        XCTAssertFalse(task.testHasCoprocessReadSource(), "Coprocess read source should be nil after teardown")
        XCTAssertFalse(task.testHasCoprocessWriteSource(), "Coprocess write source should be nil after teardown")
    }

    func testTeardownCoprocessSourcesSafeWithoutSetup() {
        XCTAssertFalse(task.testHasCoprocessReadSource(), "No coprocess read source before setup")
        XCTAssertFalse(task.testHasCoprocessWriteSource(), "No coprocess write source before setup")

        // Should not crash
        task.testTeardownCoprocessSources()
        task.testWaitForIOQueue()

        XCTAssertFalse(task.testHasCoprocessReadSource(), "Still no coprocess read source")
        XCTAssertFalse(task.testHasCoprocessWriteSource(), "Still no coprocess write source")
    }

    func testDoubleTeardownCoprocessSourcesSafe() {
        task.testSetupCoprocessSources(withReadFd: coprocessPipe.readFd, writeFd: coprocessPipe.writeFd)
        task.testWaitForIOQueue()

        task.testTeardownCoprocessSources()
        task.testWaitForIOQueue()

        // Second teardown should not crash
        task.testTeardownCoprocessSources()
        task.testWaitForIOQueue()

        XCTAssertFalse(task.testHasCoprocessReadSource(), "No coprocess read source after double teardown")
        XCTAssertFalse(task.testHasCoprocessWriteSource(), "No coprocess write source after double teardown")
    }

    // MARK: - Replacement

    /// Regression: setupCoprocessSources must tear down existing sources before creating new ones.
    func testSetupCoprocessSourcesTearsDownExisting() {
        task.testSetupCoprocessSources(withReadFd: coprocessPipe.readFd, writeFd: coprocessPipe.writeFd)
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testHasCoprocessReadSource(), "First coprocess read source should exist")

        // Create a second pipe for the replacement coprocess
        guard let secondPipe = createTestPipe() else {
            XCTFail("Failed to create second coprocess pipe")
            return
        }
        defer { closeTestPipe(secondPipe) }

        // Second setup should tear down first sources, then create new ones — no crash
        task.testSetupCoprocessSources(withReadFd: secondPipe.readFd, writeFd: secondPipe.writeFd)
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testHasCoprocessReadSource(), "Replacement coprocess read source should exist")
        XCTAssertTrue(task.testHasCoprocessWriteSource(), "Replacement coprocess write source should exist")
    }

    // MARK: - Primary teardown interaction

    /// teardown() on PTYTaskIOHandler calls teardownCoprocessSources(), so tearing
    /// down primary sources must also clean up coprocess sources.
    func testPrimaryTeardownAlsoTearsDownCoprocessSources() {
        task.testSetupCoprocessSources(withReadFd: coprocessPipe.readFd, writeFd: coprocessPipe.writeFd)
        task.testWaitForIOQueue()

        XCTAssertTrue(task.testHasCoprocessReadSource(), "Coprocess read source should exist")
        XCTAssertTrue(task.testHasCoprocessWriteSource(), "Coprocess write source should exist")

        // Primary teardown should also clean up coprocess sources
        task.testTeardownDispatchSourcesForTesting()
        task.testWaitForIOQueue()

        XCTAssertFalse(task.testHasCoprocessReadSource(),
                       "Coprocess read source should be nil after primary teardown")
        XCTAssertFalse(task.testHasCoprocessWriteSource(),
                       "Coprocess write source should be nil after primary teardown")

        // Re-setup primary sources so tearDown() doesn't double-teardown
        task.testSetFd(ptyPipe.readFd)
        task.testSetupDispatchSourcesForTesting()
    }
}
