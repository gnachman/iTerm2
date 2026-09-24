//
//  ForkedServerRegistryTests.swift
//  ModernTests
//
//  Ownership of an iTermServer is process-scoped and keyed by socket number, so that a client
//  torn down while its server keeps running still recognizes that server as ours. See issue
//  12106.
//

import XCTest
@testable import iTerm2SharedARC

class ForkedServerRegistryTests: XCTestCase {
    private var registry = ForkedServerRegistry()

    override func setUp() {
        super.setUp()
        registry = ForkedServerRegistry()
    }

    func testSocketWeNeverLaunchedOnIsNotOurs() {
        XCTAssertFalse(registry.everLaunchedServer(socketNumber: 1))
    }

    func testRecordedSocketIsOurs() {
        registry.record(socketNumber: 1)
        XCTAssertTrue(registry.everLaunchedServer(socketNumber: 1))
    }

    func testOtherSocketsAreUnaffectedByARecord() {
        registry.record(socketNumber: 1)
        XCTAssertFalse(registry.everLaunchedServer(socketNumber: 2))
    }

    func testSeveralSocketsCanBeOurs() {
        registry.record(socketNumber: 1)
        registry.record(socketNumber: 3)
        XCTAssertTrue(registry.everLaunchedServer(socketNumber: 1))
        XCTAssertFalse(registry.everLaunchedServer(socketNumber: 2))
        XCTAssertTrue(registry.everLaunchedServer(socketNumber: 3))
    }

    func testRecordingTwiceIsHarmless() {
        registry.record(socketNumber: 1)
        registry.record(socketNumber: 1)
        XCTAssertTrue(registry.everLaunchedServer(socketNumber: 1))
    }

    // A server we forked keeps its socket number for the life of the app. Relaunching one on
    // the same number after the first died must still read as ours.
    func testRelaunchingOnTheSameSocketStaysOurs() {
        registry.record(socketNumber: 2)
        registry.record(socketNumber: 2)
        XCTAssertTrue(registry.everLaunchedServer(socketNumber: 2))
    }
}
