//
//  InstanceLockCompareRenderingTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

/// F-220: when another instance holds the lock, -compare-rendering now prints
/// an error and exits nonzero instead of auto-answering Quit with status 0.
final class InstanceLockCompareRenderingTests: XCTestCase {
    func testConflictMessageIsAnErrorResultNamingThePID() {
        let message = InstanceLock.compareRenderingConflictMessage(pid: 4242)
        XCTAssertTrue(message.hasPrefix("RESULT: ERROR"), message)
        XCTAssertTrue(message.contains("4242"), message)
        XCTAssertTrue(message.hasSuffix("\n"), message)
    }
}
